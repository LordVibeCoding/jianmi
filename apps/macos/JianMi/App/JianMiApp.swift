import SwiftUI

/// 简密 —— 简单记录你的密码，但你的密码将会 100% 安全。
///
/// Agent 模式（LSUIElement）：无 Dock 图标，菜单栏常驻，全局快捷键唤起浮窗。
@main
struct JianMiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var app = AppState.shared

    var body: some Scene {
        Window("简密", id: "main") {
            RootView()
                .environmentObject(app)
                .frame(minWidth: 780, minHeight: 500)
        }
        .defaultSize(width: 1000, height: 640)
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView()
                .environmentObject(app)
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(app)
        } label: {
            Image(systemName: app.state == .unlocked ? "key.fill" : "lock.fill")
        }
    }
}
