import XCTest
@testable import JianMi

/// 桥接服务器测试：真实 TCP 回环请求，验证 HTTP 解析 / 鉴权 / 标签页上报。
final class BridgeServerTests: XCTestCase {
    static let testPort: UInt16 = 48987
    static var started = false

    @MainActor
    private func ensureServer() async {
        if !Self.started {
            BridgeServer.shared.start(port: Self.testPort)
            Self.started = true
            try? await Task.sleep(for: .milliseconds(300))
        }
    }

    private func request(
        _ path: String, method: String = "GET",
        token: String?, body: [String: Any]? = nil
    ) async throws -> (Int, Data) {
        var req = URLRequest(
            url: URL(string: "http://127.0.0.1:\(Self.testPort)\(path)")!,
            timeoutInterval: 5)
        req.httpMethod = method
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }

    func testAuthRequired() async throws {
        await ensureServer()
        // 无令牌 → 401
        let (noAuth, _) = try await request("/api/bridge/status", token: nil)
        XCTAssertEqual(noAuth, 401)
        // 错误令牌 → 401
        let (badAuth, _) = try await request("/api/bridge/status", token: "wrong-token")
        XCTAssertEqual(badAuth, 401)
        // 正确令牌 → 200 且返回锁定状态
        let token = await MainActor.run { BridgeServer.shared.token }
        let (ok, data) = try await request("/api/bridge/status", token: token)
        XCTAssertEqual(ok, 200)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json?["locked"] as? Bool)
    }

    func testTabReportRoundtrip() async throws {
        await ensureServer()
        let token = await MainActor.run { BridgeServer.shared.token }
        let (status, _) = try await request(
            "/api/bridge/tab", method: "POST", token: token,
            body: ["url": "https://github.com/login", "title": "Sign in · GitHub"])
        XCTAssertEqual(status, 204)

        let tab = await MainActor.run { BridgeServer.shared.lastTab }
        XCTAssertEqual(tab?.url, "https://github.com/login")
        XCTAssertEqual(tab?.suggestedName, "Github")
    }

    func testUnknownPathAnd404() async throws {
        await ensureServer()
        let token = await MainActor.run { BridgeServer.shared.token }
        let (status, _) = try await request("/api/bridge/nothing", token: token)
        XCTAssertEqual(status, 404)
    }
}
