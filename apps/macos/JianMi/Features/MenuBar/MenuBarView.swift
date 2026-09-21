import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        // 状态
        switch app.state {
        case .unlocked:
            Text("已解锁").font(.caption)
        case .locked:
            Text("已锁定").font(.caption)
        case .needsSetup:
            Text("尚未初始化").font(.caption)
        }

        Divider()

        Button("打开简密") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("1", modifiers: .command)

        Button("快速搜索") {
            AppDelegate.shared?.toggleQuickSearch()
        }

        Button("快速捕获") {
            AppDelegate.shared?.toggleQuickCapture()
        }

        Divider()

        Button("密码生成器") {
            openWindow(id: "passwordGenerator")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        if app.state == .unlocked {
            if SyncSettings.isConfigured {
                Button("立即同步") {
                    Task { await app.sync?.syncNow() }
                }
            }
            Button("立即锁定") { app.lock() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
        }

        Button("设置…") {
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("退出简密") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}
