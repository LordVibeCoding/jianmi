import AppKit

struct BrowserTab {
    let title: String
    let url: String

    /// 从域名推断站点名：github.com → Github
    var suggestedName: String {
        guard let host = EntryStore.host(from: url) else {
            return title
        }
        let parts = host.split(separator: ".")
        guard parts.count >= 2 else { return host }
        let core = String(parts[parts.count - 2])
        return core.prefix(1).uppercased() + core.dropFirst()
    }
}

/// 抓取前台浏览器当前标签页（Apple Events，首次触发系统"自动化"授权弹窗）。
/// 用户拒绝授权 → 返回 nil，快速捕获优雅降级为手动输入。
enum BrowserURLGrabber {
    private static let chromiumBundleIDs: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.canary",
        "com.microsoft.edgemac", "com.brave.Browser",
        "company.thebrowser.Browser",   // Arc
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
    ]

    static func grabFrontmost() -> BrowserTab? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else { return nil }

        let source: String
        if bundleID == "com.apple.Safari" {
            source = """
            tell application "Safari"
                return (URL of current tab of front window) & "\\n" & (name of current tab of front window)
            end tell
            """
        } else if chromiumBundleIDs.contains(bundleID) {
            let name = app.localizedName ?? "Google Chrome"
            source = """
            tell application "\(name)"
                return (URL of active tab of front window) & "\\n" & (title of active tab of front window)
            end tell
            """
        } else {
            return nil
        }

        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let output = script.executeAndReturnError(&error)
        guard error == nil, let combined = output.stringValue else { return nil }

        let parts = combined.components(separatedBy: "\n")
        guard let url = parts.first, !url.isEmpty else { return nil }
        let title = parts.count > 1 ? parts[1] : ""
        return BrowserTab(title: title, url: url)
    }
}
