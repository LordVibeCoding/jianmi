import SwiftUI

/// ⌥⌘N 快速捕获：注册新账号 → 一个面板 5 秒存完。
struct QuickCaptureView: View {
    let prefill: BrowserTab?
    var onDone: () -> Void

    @EnvironmentObject private var app: AppState

    @State private var title = ""
    @State private var url = ""
    @State private var username = ""
    @State private var password = ""
    @State private var localOnly = false
    @State private var revealPassword = true
    @State private var saved = false
    @State private var error: String?
    @FocusState private var focus: Field?

    enum Field { case title, url, username, password }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)

            if app.state != .unlocked {
                InlineUnlockView()
                    .padding(20)
            } else {
                form
            }
        }
        .frame(width: 460)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator.opacity(0.6), lineWidth: 1))
        .overlay {
            if saved {
                SuccessToast(text: "已保存到简密")
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.25), value: saved)
        .onAppear {
            if let tab = prefill {
                url = tab.url
                title = tab.suggestedName
                // 已预填名称和网址 → 直接聚焦账号
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { focus = .username }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { focus = .title }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            AppBadge(size: 22)
            Text("新建条目")
                .font(.system(size: 13, weight: .semibold))
            if prefill != nil {
                Label("已抓取当前网页", systemImage: "wand.and.stars")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            Spacer()
            KeyCap(text: "esc")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var form: some View {
        VStack(spacing: 0) {
            fieldRow(icon: "textformat", placeholder: "名称（如：GitHub）",
                     text: $title, field: .title)
            Divider().padding(.leading, 44).opacity(0.4)
            fieldRow(icon: "link", placeholder: "网址",
                     text: $url, field: .url)
            Divider().padding(.leading, 44).opacity(0.4)
            fieldRow(icon: "person", placeholder: "账号（用户名 / 邮箱 / 手机号）",
                     text: $username, field: .username)
            Divider().padding(.leading, 44).opacity(0.4)
            passwordRow

            Divider().opacity(0.5)
            footer
        }
    }

    private func fieldRow(icon: String, placeholder: String,
                          text: Binding<String>, field: Field) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($focus, equals: field)
                .onSubmit { advance(from: field) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private var passwordRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "key")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Group {
                if revealPassword {
                    TextField("密码", text: $password)
                } else {
                    SecureField("密码", text: $password)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 14, design: .monospaced))
            .focused($focus, equals: .password)
            .onSubmit { save() }

            Button {
                password = PasswordGenerator.generate()
                revealPassword = true
            } label: {
                Image(systemName: "dice")
            }
            .buttonStyle(.borderless)
            .help("生成强密码")

            Button {
                revealPassword.toggle()
            } label: {
                Image(systemName: revealPassword ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private var footer: some View {
        HStack {
            Toggle("仅本机", isOn: $localOnly)
                .toggleStyle(.checkbox)
                .font(.callout)
                .help("不同步到服务器")
            if let error {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(1)
            }
            Spacer()
            HStack(spacing: 4) {
                KeyCap(text: "↩")
                Text("保存").font(.caption).foregroundStyle(.secondary)
            }
            Button("保存") { save() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(title.isEmpty && url.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func advance(from field: Field) {
        switch field {
        case .title:    focus = .url
        case .url:      focus = .username
        case .username: focus = .password
        case .password: save()
        }
    }

    private func save() {
        guard let store = app.store else { return }
        guard !title.isEmpty || !url.isEmpty else { return }
        var draft = EntryDraft()
        draft.title = title.isEmpty ? (BrowserTab(title: "", url: url).suggestedName) : title
        draft.urlFull = url
        draft.username = username
        draft.password = password
        draft.localOnly = localOnly
        do {
            try store.add(draft: draft)
            saved = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { onDone() }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// 面板内嵌解锁（主密码 / Touch ID）。
struct InlineUnlockView: View {
    @EnvironmentObject private var app: AppState
    @State private var password = ""
    @State private var error: String?
    @State private var isWorking = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill").foregroundStyle(.secondary)
                Text("简密已锁定").font(.callout.weight(.medium))
            }
            HStack(spacing: 8) {
                SecureField("主密码", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit(unlock)
                if app.vault.biometricEnabled {
                    Button {
                        biometric()
                    } label: {
                        Image(systemName: "touchid")
                            .font(.system(size: 16))
                    }
                    .help("触控 ID 解锁")
                }
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { focused = true }
        }
    }

    private func unlock() {
        guard !password.isEmpty, !isWorking else { return }
        isWorking = true
        error = nil
        let pwd = password
        Task {
            do {
                try app.unlock(masterPassword: pwd)
            } catch {
                self.error = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func biometric() {
        AppDelegate.shared?.capturePanel.beginSystemPrompt()
        AppDelegate.shared?.searchPanel.beginSystemPrompt()
        Task {
            await app.unlockWithBiometrics()
            AppDelegate.shared?.capturePanel.endSystemPrompt()
            AppDelegate.shared?.searchPanel.endSystemPrompt()
        }
    }
}
