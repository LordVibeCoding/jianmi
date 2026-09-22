import Foundation
import Network

/// 浏览器当前标签页信息（由扩展实时上报，替代 AppleScript 自动化）。
struct BrowserTab {
    let title: String
    let url: String

    /// 从域名推断站点名：github.com → Github
    var suggestedName: String {
        guard let host = EntryStore.host(from: url) else { return title }
        let parts = host.split(separator: ".")
        guard parts.count >= 2 else { return host }
        let core = String(parts[parts.count - 2])
        return core.prefix(1).uppercased() + core.dropFirst()
    }
}

/// 本地桥接服务器：浏览器扩展 ↔ 简密 App。
///
/// - 只监听 127.0.0.1:48787，外部网络不可达
/// - 所有请求需 Bearer 配对令牌（设置 → 浏览器扩展 中查看）
/// - 扩展上报当前标签页 → ⌥⌘N 快速捕获零权限预填网址
/// - 扩展可查询匹配条目、获取凭证（自动填充）、保存新账号
@MainActor
final class BridgeServer {
    static let shared = BridgeServer()
    static let defaultPort: UInt16 = 48787

    /// 已知浏览器 Bundle ID（前台是浏览器时才使用上报的标签页预填）
    static let browserBundleIDs: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "com.google.Chrome.canary",
        "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
    ]

    private var listener: NWListener?
    private(set) var lastTab: BrowserTab?
    private(set) var isRunning = false

    /// 配对令牌（首次访问自动生成）。
    var token: String {
        if let t = UserDefaults.standard.string(forKey: "bridge.token"), !t.isEmpty {
            return t
        }
        return regenerateToken()
    }

    @discardableResult
    func regenerateToken() -> String {
        let bytes = (try? CryptoEngine.shared.randomBytes(24)) ?? Array(UUID().uuidString.utf8)
        let t = bytes.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(t, forKey: "bridge.token")
        return t
    }

    // ── 生命周期 ──────────────────────────────────────────
    func start(port: UInt16 = BridgeServer.defaultPort) {
        NSLog("BridgeServer.start(port: %d)", port)
        guard listener == nil else { return }
        _ = token   // 确保令牌已生成

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback),   // 仅本机
            port: NWEndpoint.Port(rawValue: port)!)

        guard let listener = try? NWListener(using: params) else {
            NSLog("BridgeServer: 端口 \(port) 监听失败")
            return
        }
        listener.newConnectionHandler = { conn in
            BridgeHTTP.handle(conn)
        }
        listener.stateUpdateHandler = { [weak self] state in
            NSLog("BridgeServer state: %@", String(describing: state))
            Task { @MainActor in
                self?.isRunning = (state == .ready)
            }
        }
        listener.start(queue: .global(qos: .userInitiated))
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    // ── 路由 ─────────────────────────────────────────────
    func route(_ request: BridgeHTTP.Request) -> BridgeHTTP.Response {
        // 鉴权
        let auth = request.headers["authorization"] ?? ""
        guard auth == "Bearer \(token)" else {
            return .init(status: 401, json: ["error": "invalid token"])
        }

        let app = AppState.shared
        switch (request.method, request.path) {

        case ("GET", "/api/bridge/status"):
            return .init(status: 200, json: [
                "app": "简密",
                "locked": app.state != .unlocked,
                "needsSetup": app.state == .needsSetup,
            ])

        case ("POST", "/api/bridge/tab"):
            guard let obj = request.jsonBody,
                  let url = obj["url"] as? String else {
                return .init(status: 400, json: ["error": "bad request"])
            }
            lastTab = BrowserTab(title: obj["title"] as? String ?? "", url: url)
            return .init(status: 204, json: nil)

        case ("GET", "/api/bridge/categories"):
            let items = CategoryStore.shared.all.map { ["id": $0.id, "name": $0.name] }
            return .init(status: 200, json: ["categories": items])

        case ("GET", "/api/bridge/entries"):
            guard let store = app.store else {
                return .init(status: 423, json: ["locked": true])
            }
            let q = request.query["q"] ?? ""
            let category = request.query["category"] ?? ""
            let host = request.query["host"] ?? ""
            let list: [Entry]
            if !category.isEmpty {
                // 指定分类（可叠加搜索）
                if !q.isEmpty {
                    list = store.quickSearch(q, limit: 50)
                        .filter { CategoryStore.normalize($0.type) == category }
                } else {
                    list = Array(store.allEntries(categoryID: category).prefix(50))
                }
            } else if !q.isEmpty {
                list = store.quickSearch(q, limit: 20)
            } else if !host.isEmpty {
                list = store.matching(host: host, limit: 20)
            } else {
                list = store.quickSearch("", limit: 20)
            }
            let items: [[String: Any]] = list.map { entry in
                let body = try? store.decryptBody(of: entry)
                return [
                    "uuid": entry.uuid,
                    "title": entry.title,
                    "host": entry.urlHost ?? "",
                    "type": entry.type,
                    "username": body?.username ?? "",
                    "hasTotp": !(body?.totpSecret.isEmpty ?? true),
                ]
            }
            return .init(status: 200, json: ["entries": items])

        case ("POST", "/api/bridge/credentials"):
            guard let store = app.store else {
                return .init(status: 423, json: ["locked": true])
            }
            guard let obj = request.jsonBody,
                  let uuid = obj["uuid"] as? String,
                  let entry = store.entry(uuid: uuid),
                  let body = try? store.decryptBody(of: entry) else {
                return .init(status: 404, json: ["error": "not found"])
            }
            var json: [String: Any] = [
                "username": body.username,
                "password": body.password,
            ]
            if !body.totpSecret.isEmpty,
               let code = TOTP.code(secret: body.totpSecret) {
                json["totp"] = code
            }
            return .init(status: 200, json: json)

        case ("POST", "/api/bridge/save"):
            guard let store = app.store else {
                return .init(status: 423, json: ["locked": true])
            }
            guard let obj = request.jsonBody else {
                return .init(status: 400, json: ["error": "bad request"])
            }
            var draft = EntryDraft()
            draft.title = obj["title"] as? String ?? ""
            draft.urlFull = obj["url"] as? String ?? ""
            draft.username = obj["username"] as? String ?? ""
            draft.password = obj["password"] as? String ?? ""
            if draft.title.isEmpty {
                draft.title = BrowserTab(title: "", url: draft.urlFull).suggestedName
            }
            guard !draft.title.isEmpty || !draft.urlFull.isEmpty else {
                return .init(status: 400, json: ["error": "empty entry"])
            }
            do {
                let entry = try store.add(draft: draft)
                return .init(status: 201, json: ["uuid": entry.uuid])
            } catch {
                return .init(status: 500, json: ["error": error.localizedDescription])
            }

        default:
            return .init(status: 404, json: ["error": "not found"])
        }
    }
}

// ── 极简 HTTP/1.1 实现（仅桥接所需，零依赖）───────────────
enum BridgeHTTP {
    struct Request {
        let method: String
        let path: String
        let query: [String: String]
        let headers: [String: String]
        let body: Data

        var jsonBody: [String: Any]? {
            try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        }
    }

    struct Response {
        let status: Int
        let json: [String: Any]?
    }

    nonisolated static func handle(_ conn: NWConnection) {
        conn.start(queue: .global(qos: .userInitiated))
        receive(conn, buffer: Data())
    }

    private nonisolated static func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
            var buf = buffer
            if let data { buf.append(data) }
            guard error == nil, buf.count < 1_048_576 else { conn.cancel(); return }

            if let headerEnd = buf.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = buf[..<headerEnd.lowerBound]
                guard let headerText = String(data: headerData, encoding: .utf8) else {
                    conn.cancel(); return
                }
                let lines = headerText.components(separatedBy: "\r\n")
                var headers: [String: String] = [:]
                for line in lines.dropFirst() {
                    if let colon = line.firstIndex(of: ":") {
                        let key = line[..<colon].lowercased()
                        let value = line[line.index(after: colon)...]
                            .trimmingCharacters(in: .whitespaces)
                        headers[key] = value
                    }
                }
                let contentLength = Int(headers["content-length"] ?? "0") ?? 0
                let bodyStart = headerEnd.upperBound

                if buf.count - bodyStart.utf8Offset(in: buf) >= contentLength {
                    let body = Data(buf[bodyStart...].prefix(contentLength))
                    dispatch(conn, requestLine: lines.first ?? "", headers: headers, body: body)
                } else {
                    receive(conn, buffer: buf)   // 等 body
                }
            } else if !isComplete {
                receive(conn, buffer: buf)       // 等 header
            } else {
                conn.cancel()
            }
        }
    }

    private nonisolated static func dispatch(
        _ conn: NWConnection, requestLine: String,
        headers: [String: String], body: Data
    ) {
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { conn.cancel(); return }
        let method = parts[0]
        let fullPath = parts[1]

        // CORS 预检直接放行（真正的鉴权在实际请求上）
        if method == "OPTIONS" {
            send(conn, status: 204, json: nil)
            return
        }

        var path = fullPath
        var query: [String: String] = [:]
        if let comps = URLComponents(string: "http://localhost" + fullPath) {
            path = comps.path
            for item in comps.queryItems ?? [] {
                query[item.name] = item.value ?? ""
            }
        }

        let request = Request(
            method: method, path: path, query: query,
            headers: headers, body: body)

        Task { @MainActor in
            let response = BridgeServer.shared.route(request)
            send(conn, status: response.status, json: response.json)
        }
    }

    private nonisolated static func send(_ conn: NWConnection, status: Int, json: [String: Any]?) {
        let bodyData: Data
        if let json, let data = try? JSONSerialization.data(withJSONObject: json) {
            bodyData = data
        } else {
            bodyData = Data()
        }
        let reason: String = [200: "OK", 201: "Created", 204: "No Content",
                              400: "Bad Request", 401: "Unauthorized",
                              404: "Not Found", 423: "Locked",
                              500: "Internal Server Error"][status] ?? "OK"
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Access-Control-Allow-Origin: *\r\n"
        head += "Access-Control-Allow-Headers: Authorization, Content-Type\r\n"
        head += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
        head += "Content-Type: application/json; charset=utf-8\r\n"
        head += "Content-Length: \(bodyData.count)\r\n"
        head += "Connection: close\r\n\r\n"

        var out = Data(head.utf8)
        out.append(bodyData)
        conn.send(content: out, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }
}

private extension Data.Index {
    func utf8Offset(in data: Data) -> Int {
        data.distance(from: data.startIndex, to: self)
    }
}
