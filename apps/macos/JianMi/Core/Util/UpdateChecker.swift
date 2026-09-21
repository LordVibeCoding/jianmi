import AppKit
import Foundation

/// 更新检查：对比 GitHub 最新 Release，提示用户自行下载。
/// 不做自动下载/自动安装 —— 只提醒。
@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    private static let apiURL = URL(
        string: "https://api.github.com/repos/LordVibeCoding/jianmi/releases/latest")!
    static let downloadPage = URL(
        string: "https://github.com/LordVibeCoding/jianmi/releases/latest")!

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    struct Release {
        let version: String
    }

    // ── 触发 ─────────────────────────────────────────────
    /// 启动时静默检查（每 24 小时最多一次；被跳过的版本不再提醒）。
    func autoCheck() {
        let last = UserDefaults.standard.double(forKey: "update.lastCheck")
        guard Date().timeIntervalSince1970 - last > 86_400 else { return }
        Task { await check(interactive: false) }
    }

    /// 设置页手动检查。
    func check(interactive: Bool) async {
        UserDefaults.standard.set(
            Date().timeIntervalSince1970, forKey: "update.lastCheck")

        guard let latest = await fetchLatest() else {
            if interactive {
                simpleAlert("无法检查更新", "请稍后重试，或直接访问 GitHub 发布页。")
            }
            return
        }

        if Self.isNewer(latest.version, than: currentVersion) {
            let skipped = UserDefaults.standard.string(forKey: "update.skippedVersion")
            if !interactive, latest.version == skipped { return }
            presentUpdateAlert(latest)
        } else if interactive {
            simpleAlert("已是最新版本", "当前 v\(currentVersion) 就是最新发布版。")
        }
    }

    // ── 实现 ─────────────────────────────────────────────
    private func fetchLatest() async -> Release? {
        var request = URLRequest(url: Self.apiURL, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return Release(version: version)
    }

    /// 语义化版本比较：1.10.0 > 1.9.9
    static func isNewer(_ a: String, than b: String) -> Bool {
        let av = a.split(separator: ".").map { Int($0) ?? 0 }
        let bv = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(av.count, bv.count) {
            let x = i < av.count ? av[i] : 0
            let y = i < bv.count ? bv[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private func presentUpdateAlert(_ release: Release) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "简密有新版本：v\(release.version)"
        alert.informativeText = """
        当前版本 v\(currentVersion)。
        前往 GitHub 发布页下载最新安装包（DMG），拖入 Applications 覆盖即可。
        """
        alert.addButton(withTitle: "前往下载")
        alert.addButton(withTitle: "稍后提醒")
        alert.addButton(withTitle: "跳过此版本")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(Self.downloadPage)
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(release.version, forKey: "update.skippedVersion")
        default:
            break
        }
    }

    private func simpleAlert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
