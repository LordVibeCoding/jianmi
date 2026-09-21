import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(app.state == .unlocked ? "打开简密" : "解锁简密…") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("1", modifiers: .command)

        if app.state == .unlocked {
            Button("立即锁定") { app.lock() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
        }

        Divider()

        Button("退出简密") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}
