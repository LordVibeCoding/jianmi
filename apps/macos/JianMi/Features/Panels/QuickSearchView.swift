import SwiftUI

/// ⌥⌘P 快速搜索：敲几个字 → 回车复制密码，全程 2 秒。
struct QuickSearchView: View {
    var onDone: () -> Void

    @EnvironmentObject private var app: AppState

    @State private var query = ""
    @State private var results: [Entry] = []
    @State private var selection = 0
    @State private var toast: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            if app.state != .unlocked {
                Divider().opacity(0.5)
                InlineUnlockView().padding(20)
            } else {
                if !results.isEmpty {
                    Divider().opacity(0.5)
                    resultList
                }
                Divider().opacity(0.5)
                footer
            }
        }
        .frame(width: 580)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator.opacity(0.6), lineWidth: 1))
        .overlay {
            if let toast {
                SuccessToast(text: toast)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.25), value: toast != nil)
        .onAppear {
            refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { focused = true }
        }
        .onChange(of: query) { _, _ in refresh() }
        .onChange(of: app.state) { _, newState in
            if newState == .unlocked { refresh() }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("搜索简密…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused($focused)
                .onKeyPress(phases: .down) { press in handleKey(press) }
            KeyCap(text: "esc")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var resultList: some View {
        VStack(spacing: 2) {
            ForEach(Array(results.enumerated()), id: \.element.id) { index, entry in
                row(entry, selected: index == selection)
                    .onTapGesture {
                        selection = index
                        copyPassword()
                    }
            }
        }
        .padding(6)
    }

    private func row(_ entry: Entry, selected: Bool) -> some View {
        HStack(spacing: 10) {
            TypeBadge(type: entry.type, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if let host = entry.urlHost {
                    Text(host)
                        .font(.system(size: 11))
                        .foregroundStyle(selected ? .white.opacity(0.8) : Color.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if entry.favorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(selected ? .white : .yellow)
            }
            if entry.localOnly {
                Image(systemName: "lock.laptopcomputer")
                    .font(.system(size: 10))
                    .foregroundStyle(selected ? .white.opacity(0.8) : Color.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .foregroundStyle(selected ? .white : .primary)
        .contentShape(Rectangle())
    }

    private var footer: some View {
        HStack(spacing: 14) {
            hint("↩", "复制密码")
            hint("⌥↩", "复制账号")
            hint("⌘↩", "打开网址")
            hint("⌃↩", "自动键入")
            Spacer()
            Text("\(results.count) 个结果")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            KeyCap(text: key)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // ── 交互 ─────────────────────────────────────────────
    private func refresh() {
        guard let store = app.store else { results = []; return }
        results = store.quickSearch(query)
        selection = min(selection, max(results.count - 1, 0))
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .downArrow:
            selection = min(selection + 1, max(results.count - 1, 0))
            return .handled
        case .upArrow:
            selection = max(selection - 1, 0)
            return .handled
        case .return:
            if press.modifiers.contains(.command) { openURL() }
            else if press.modifiers.contains(.option) { copyUsername() }
            else if press.modifiers.contains(.control) { autoType() }
            else { copyPassword() }
            return .handled
        default:
            return .ignored
        }
    }

    private var selectedEntry: Entry? {
        results.indices.contains(selection) ? results[selection] : nil
    }

    private func body(of entry: Entry) -> SecretBody? {
        try? app.store?.decryptBody(of: entry)
    }

    private func copyPassword() {
        guard let entry = selectedEntry, let b = body(of: entry), !b.password.isEmpty else { return }
        SecurePasteboard.copy(b.password)
        flash("已复制密码 · 30 秒后自动清除")
    }

    private func copyUsername() {
        guard let entry = selectedEntry, let b = body(of: entry), !b.username.isEmpty else { return }
        SecurePasteboard.copy(b.username, clearAfter: 0)
        flash("已复制账号")
    }

    private func openURL() {
        guard let entry = selectedEntry, let b = body(of: entry), !b.urlFull.isEmpty else { return }
        let s = b.urlFull.contains("://") ? b.urlFull : "https://" + b.urlFull
        if let url = URL(string: s) {
            NSWorkspace.shared.open(url)
            if !b.password.isEmpty { SecurePasteboard.copy(b.password) }
            onDone()
        }
    }

    private func autoType() {
        guard let entry = selectedEntry, let b = body(of: entry), !b.password.isEmpty else { return }
        guard AutoTyper.isTrusted else {
            AutoTyper.requestPermission()
            flash("请先在系统设置中授权辅助功能")
            return
        }
        onDone()   // 先隐藏面板（非激活面板 → 焦点仍在目标 App）
        AutoTyper.type(b.password)
    }

    private func flash(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            toast = nil
            onDone()
        }
    }
}
