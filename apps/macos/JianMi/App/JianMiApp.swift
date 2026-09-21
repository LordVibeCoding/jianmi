import SwiftUI

/// 简密 —— 简单记录你的密码，但你的密码将会 100% 安全。
///
/// Agent 模式（LSUIElement）：无 Dock 图标，菜单栏常驻。
@main
struct JianMiApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        Window("简密", id: "main") {
            RootView()
                .environmentObject(app)
                .frame(minWidth: 760, minHeight: 480)
        }
        .defaultSize(width: 960, height: 620)

        MenuBarExtra("简密", systemImage: "key.fill") {
            MenuBarView()
                .environmentObject(app)
        }
    }
}
