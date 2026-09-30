import AppKit
import SwiftUI

/// 站点图标加载：内存 NSCache + 磁盘缓存（~/Library/Caches/JianMi/favicons）。
/// 来源：站点自身 /favicon.ico（沿用网址的协议+端口）→ DuckDuckGo 图标服务兜底；失败记录避免反复请求。
actor FaviconLoader {
    static let shared = FaviconLoader()

    private let cache = NSCache<NSString, NSImage>()
    private var failed: Set<String> = []
    private var inflight: [String: Task<NSImage?, Never>] = [:]
    private let directory: URL

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("JianMi/favicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// urlString：条目完整网址，可省略协议、可带端口（如 84.32.63.86:3000）
    func icon(forURL urlString: String) async -> NSImage? {
        let hasScheme = urlString.contains("://")
        guard let comps = URLComponents(string: hasScheme ? urlString : "https://" + urlString),
              let host = comps.host?.lowercased(), !host.isEmpty else { return nil }
        let authority = comps.port.map { "\(host):\($0)" } ?? host
        // 不同端口视为不同站点；无端口时仍用纯域名作 key，旧磁盘缓存继续有效
        let key = comps.port.map { "\(host)_\($0)" } ?? host
        if let hit = cache.object(forKey: key as NSString) { return hit }
        if failed.contains(key) { return nil }
        if let running = inflight[key] { return await running.value }

        // 站点直取（未写协议则 https/http 都试）→ DDG 兜底（IP/内网站点 DDG 取不到）
        let scheme = comps.scheme?.lowercased() ?? "https"
        let schemes = hasScheme && ["http", "https"].contains(scheme) ? [scheme] : ["https", "http"]
        let sources = schemes.map { "\($0)://\(authority)/favicon.ico" }
            + ["https://icons.duckduckgo.com/ip3/\(host).ico"]

        let task = Task<NSImage?, Never> { [directory] in
            // 磁盘缓存
            let file = directory.appendingPathComponent("\(key).png")
            if let data = try? Data(contentsOf: file),
               let image = NSImage(data: data), image.isValid {
                return image
            }
            // 网络
            for source in sources {
                guard let url = URL(string: source) else { continue }
                var request = URLRequest(url: url, timeoutInterval: 6)
                request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                guard let (data, response) = try? await URLSession.shared.data(for: request),
                      (response as? HTTPURLResponse)?.statusCode == 200,
                      data.count > 60,
                      let image = NSImage(data: data), image.isValid,
                      image.size.width >= 8 else { continue }
                try? data.write(to: file)
                return image
            }
            return nil
        }
        inflight[key] = task
        let result = await task.value
        inflight[key] = nil
        if let result {
            cache.setObject(result, forKey: key as NSString)
        } else {
            failed.insert(key)
        }
        return result
    }
}

/// 条目徽章：有网址（任意分类）→ 站点 favicon（白底圆角卡），无网址/加载失败 → 分类徽章。
/// 可在 设置 → 通用 关闭联网获取。
struct FaviconBadge: View {
    let entry: Entry
    var size: CGFloat = 30

    @State private var icon: NSImage?

    static var enabled: Bool {
        UserDefaults.standard.object(forKey: "favicons.enabled") as? Bool ?? true
    }

    var body: some View {
        Group {
            if let icon {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .frame(width: size, height: size)
                    .overlay {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: size * 0.68, height: size * 0.68)
                            .clipShape(RoundedRectangle(cornerRadius: size * 0.14, style: .continuous))
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                            .strokeBorder(.separator.opacity(0.55), lineWidth: 1))
                    .shadow(color: .black.opacity(0.08), radius: 1.5, y: 1)
            } else {
                TypeBadge(typeID: entry.type, size: size)
            }
        }
        .task(id: "\(entry.uuid)#\(entry.version)") {
            // 明文只有域名，协议/端口在密文完整网址里
            guard Self.enabled, entry.urlHost != nil,
                  let url = try? AppState.shared.store?.decryptBody(of: entry).urlFull,
                  !url.isEmpty else {
                icon = nil
                return
            }
            icon = await FaviconLoader.shared.icon(forURL: url)
        }
    }
}
