import AppKit
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    /// ⌥⌘N 快速捕获（注册新账号场景）
    static let quickCapture = Self("quickCapture", default: .init(.n, modifiers: [.command, .option]))
    /// ⌥⌘P 快速搜索（查密码场景）
    static let quickSearch = Self("quickSearch", default: .init(.p, modifiers: [.command, .option]))
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate!

    let capturePanel = SpotlightPanelController(width: 460)
    let searchPanel = SpotlightPanelController(width: 580)

    private var lastActivity = Date()
    private var idleTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        // 浏览器扩展桥接（仅监听 127.0.0.1）
        BridgeServer.shared.start()

        // 启动 5 秒后静默检查更新（每 24h 至多一次，仅提醒不自动下载）
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            UpdateChecker.shared.autoCheck()
        }

        KeyboardShortcuts.onKeyUp(for: .quickCapture) {
            Task { @MainActor in AppDelegate.shared?.toggleQuickCapture() }
        }
        KeyboardShortcuts.onKeyUp(for: .quickSearch) {
            Task { @MainActor in AppDelegate.shared?.toggleQuickSearch() }
        }

        setupIdleAutoLock()
    }

    // ── 快速捕获 ──────────────────────────────────────────
    func toggleQuickCapture() {
        if capturePanel.isVisible { capturePanel.hide(); return }
        searchPanel.hide()
        // 前台是浏览器 → 用扩展实时上报的标签页预填（零权限，无需任何授权弹窗）
        var tab: BrowserTab?
        if let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           BridgeServer.browserBundleIDs.contains(bundleID) {
            tab = BridgeServer.shared.lastTab
        }
        capturePanel.show(AnyView(
            QuickCaptureView(prefill: tab) { [weak self] in
                self?.capturePanel.hide()
            }
            .environmentObject(AppState.shared)
        ))
    }

    // ── 快速搜索 ──────────────────────────────────────────
    func toggleQuickSearch() {
        if searchPanel.isVisible { searchPanel.hide(); return }
        capturePanel.hide()
        searchPanel.show(AnyView(
            QuickSearchView { [weak self] in
                self?.searchPanel.hide()
            }
            .environmentObject(AppState.shared)
        ))
    }

    // ── 空闲自动锁定 ──────────────────────────────────────
    private func setupIdleAutoLock() {
        NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]
        ) { [weak self] event in
            self?.lastActivity = Date()
            return event
        }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in AppDelegate.shared?.checkIdle() }
        }
    }

    private func checkIdle() {
        let minutes = UserDefaults.standard.object(forKey: "autoLockMinutes") as? Int ?? 15
        guard minutes > 0, AppState.shared.state == .unlocked else { return }
        if Date().timeIntervalSince(lastActivity) > Double(minutes) * 60 {
            AppState.shared.lock()
        }
    }
}
