import AppKit
import SwiftUI

/// 钉住的悬浮小窗：置顶显示单个条目（抄激活码/助记词/看 TOTP 场景）。
@MainActor
final class PinnedPanelManager {
    static let shared = PinnedPanelManager()
    private var panels: [String: NSPanel] = [:]

    func pin(entry: Entry, store: EntryStore) {
        if let existing = panels[entry.uuid] {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled, .closable, .utilityWindow, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.title = entry.title
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        let hosting = NSHostingView(rootView:
            PinnedEntryView(entry: entry, store: store)
                .environmentObject(AppState.shared))
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentView = hosting

        // 右上角层叠排列
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            let offset = CGFloat(panels.count) * 28
            panel.setFrameTopLeftPoint(NSPoint(
                x: f.maxX - 340 - offset, y: f.maxY - 20 - offset))
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: panel, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.panels.removeValue(forKey: entry.uuid) }
        }

        panel.makeKeyAndOrderFront(nil)
        panels[entry.uuid] = panel
    }

    func closeAll() {
        panels.values.forEach { $0.close() }
        panels.removeAll()
    }
}

struct PinnedEntryView: View {
    let entry: Entry
    let store: EntryStore

    @State private var body_: SecretBody?
    @State private var reveal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TypeBadge(type: entry.type, size: 24)
                Text(entry.title).font(.headline).lineLimit(1)
                Spacer()
            }
            if let b = body_ {
                if !b.username.isEmpty {
                    pinRow(label: "账号", value: b.username, mono: false)
                }
                if !b.password.isEmpty {
                    pinRow(label: "密码",
                           value: reveal ? b.password : "••••••••••••",
                           copyValue: b.password, mono: true, revealable: true)
                }
                if !b.totpSecret.isEmpty {
                    TOTPRow(secret: b.totpSecret)
                }
                if !b.notesMarkdown.isEmpty {
                    ScrollView {
                        Text(b.notesMarkdown)
                            .font(.caption)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                }
            }
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { body_ = try? store.decryptBody(of: entry) }
    }

    @ViewBuilder
    private func pinRow(label: String, value: String, copyValue: String? = nil,
                        mono: Bool, revealable: Bool = false) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 30, alignment: .leading)
            Text(value)
                .font(mono ? .callout.monospaced() : .callout)
                .textSelection(.enabled)
                .lineLimit(1)
            Spacer()
            if revealable {
                Button { reveal.toggle() } label: {
                    Image(systemName: reveal ? "eye.slash" : "eye").font(.caption)
                }
                .buttonStyle(.borderless)
            }
            Button {
                SecurePasteboard.copy(copyValue ?? value)
            } label: {
                Image(systemName: "doc.on.doc").font(.caption)
            }
            .buttonStyle(.borderless)
        }
    }
}

/// TOTP 验证码行（倒计时环 + 点击复制）。
struct TOTPRow: View {
    let secret: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let code = TOTP.code(secret: secret, at: context.date) ?? "──────"
            let remaining = TOTP.remainingSeconds(at: context.date)
            HStack {
                Text("验证码").font(.caption).foregroundStyle(.secondary).frame(width: 30, alignment: .leading)
                Text(formatted(code))
                    .font(.title3.monospaced().weight(.medium))
                    .foregroundStyle(remaining < 5 ? .red : .primary)
                    .contentTransition(.numericText())
                Spacer()
                ZStack {
                    Circle().stroke(.quaternary, lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: remaining / TOTP.period)
                        .stroke(remaining < 5 ? Color.red : Color.accentColor,
                                style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 18, height: 18)
                Button {
                    SecurePasteboard.copy(code, clearAfter: 30)
                } label: {
                    Image(systemName: "doc.on.doc").font(.caption)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func formatted(_ code: String) -> String {
        guard code.count == 6 else { return code }
        let mid = code.index(code.startIndex, offsetBy: 3)
        return "\(code[..<mid]) \(code[mid...])"
    }
}
