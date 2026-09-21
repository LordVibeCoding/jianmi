import SwiftUI

/// ⌥⌘N 快速捕获：注册新账号 → 一个面板 5 秒存完。
/// 顶部可切换分类（默认「账号」），字段随分类动态变化。
@MainActor
struct QuickCaptureView: View {
    let prefill: BrowserTab?
    var onDone: () -> Void

    @EnvironmentObject private var app: AppState
    @ObservedObject private var categories = CategoryStore.shared

    @State private var typeID = "login"
    @State private var title = ""
    @State private var url = ""
    @State private var username = ""
    @State private var password = ""
    @State private var chain = ""
    @State private var privateKey = ""
    @State private var notes = ""
    @State private var localOnly = false
    @State private var revealPassword = true
    @State private var saved = false
    @State private var error: String?
    @FocusState private var focus: Field?

    enum Field: Hashable { case title, url, username, password, chain, privateKey, notes }

    private var category: Category { categories.category(for: typeID) }
    private func has(_ field: FieldKey) -> Bool { category.fields.contains(field) }

    /// 当前分类下可见的输入字段（决定回车流转顺序）
    private var visibleFields: [Field] {
        var list: [Field] = [.title]
        if has(.url) { list.append(.url) }
        if has(.username) { list.append(.username) }
        if has(.password) { list.append(.password) }
        if has(.chain) { list.append(.chain) }
        if has(.privateKey) { list.append(.privateKey) }
        if category.isNoteLike { list.append(.notes) }
        return list
    }

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
        .onChange(of: typeID) { _, newValue in
            if categories.category(for: newValue).forcesLocalOnly { localOnly = true }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            TypeBadge(typeID: typeID, size: 22)
            Text("新建")
                .font(.system(size: 13, weight: .semibold))
            // 分类选择器（默认第一个：账号）
            Picker("", selection: $typeID) {
                ForEach(categories.all) { c in
                    Text(c.name).tag(c.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .controlSize(.small)

            if prefill != nil, has(.url) {
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
            fieldRow(icon: "textformat",
                     placeholder: category.isNoteLike ? "笔记标题" : "名称（如：GitHub）",
                     text: $title, field: .title)

            if has(.url) {
                rowDivider
                fieldRow(icon: "link", placeholder: "网址", text: $url, field: .url)
            }
            if has(.username) {
                rowDivider
                fieldRow(icon: "person", placeholder: "账号（用户名 / 邮箱 / 手机号）",
                         text: $username, field: .username)
            }
            if has(.password) {
                rowDivider
                passwordRow
            }
            if has(.chain) {
                rowDivider
                fieldRow(icon: "point.3.connected.trianglepath.dotted",
                         placeholder: "网络链（如：Ethereum / Solana）",
                         text: $chain, field: .chain)
            }
            if has(.privateKey) {
                rowDivider
                fieldRow(icon: "key.horizontal", placeholder: "私钥或 12/24 词助记词",
                         text: $privateKey, field: .privateKey, monospaced: true)
            }
            if category.isNoteLike {
                rowDivider
                notesRow
            }

            Divider().opacity(0.5)
            footer
        }
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 44).opacity(0.4)
    }

    private func fieldRow(icon: String, placeholder: String,
                          text: Binding<String>, field: Field,
                          monospaced: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(monospaced ? .system(size: 13, design: .monospaced)
                                 : .system(size: 14))
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
            .onSubmit { advance(from: .password) }

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

    private var notesRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .padding(.top, 2)
            TextEditor(text: $notes)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(height: 90)
                .focused($focus, equals: .notes)
                .overlay(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text("Markdown 内容…")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 1).padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack {
            Toggle("仅本机", isOn: $localOnly)
                .toggleStyle(.checkbox)
                .font(.callout)
                .disabled(category.forcesLocalOnly)
                .help(category.forcesLocalOnly ? "此分类强制仅本机" : "不同步到服务器")
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
                .disabled(!canSave)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var canSave: Bool {
        !title.isEmpty || !url.isEmpty || !privateKey.isEmpty || !notes.isEmpty
    }

    private func advance(from field: Field) {
        guard let index = visibleFields.firstIndex(of: field) else { return }
        if index + 1 < visibleFields.count {
            focus = visibleFields[index + 1]
        } else {
            save()
        }
    }

    private func save() {
        guard let store = app.store, canSave else { return }
        var draft = EntryDraft()
        draft.type = typeID
        draft.title = title.isEmpty
            ? (url.isEmpty ? "未命名" : BrowserTab(title: "", url: url).suggestedName)
            : title
        draft.urlFull = url
        draft.username = username
        draft.password = password
        draft.chain = chain
        draft.privateKey = privateKey
        draft.notesMarkdown = notes
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
