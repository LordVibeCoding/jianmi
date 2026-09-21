import MarkdownUI
import SwiftUI

/// 条目详情：卡片式布局 + Markdown 笔记渲染 + TOTP + 自定义字段。
@MainActor
struct EntryDetailView: View {
    @ObservedObject var store: EntryStore
    let entry: Entry
    var onDelete: () -> Void = {}

    @State private var body_: SecretBody?
    @State private var decryptError: String?
    @State private var revealPassword = false
    @State private var revealPrivateKey = false

    private var category: Category { CategoryStore.shared.category(for: entry.type) }
    @State private var showingEditor = false
    @State private var confirmDelete = false
    @State private var copiedField: String?

    var body: some View {
        Group {
            if let body_ {
                detail(body_)
            } else if let decryptError {
                ContentUnavailableView(
                    "解密失败", systemImage: "exclamationmark.triangle",
                    description: Text(decryptError))
            } else {
                ProgressView()
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    try? store.toggleFavorite(entry)
                } label: {
                    Label("收藏", systemImage: entry.favorite ? "star.fill" : "star")
                        .foregroundStyle(entry.favorite ? .yellow : .primary)
                }
                .help(entry.favorite ? "取消收藏" : "收藏")

                Button {
                    PinnedPanelManager.shared.pin(entry: entry, store: store)
                } label: {
                    Label("钉住", systemImage: "pin")
                }
                .help("钉在屏幕上（置顶小窗）")

                Button {
                    showingEditor = true
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
                .keyboardShortcut("e", modifiers: .command)
                .help("编辑 (⌘E)")

                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .help("删除条目")
            }
        }
        .onAppear(perform: decrypt)
        .sheet(isPresented: $showingEditor) {
            EntryEditorView(store: store, editing: entry) { _ in decrypt() }
        }
        .confirmationDialog("确定删除「\(entry.title)」吗？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) {
                try? store.softDelete(entry)
                onDelete()
            }
        } message: {
            Text("删除后将从所有已同步设备移除。")
        }
    }

    private func decrypt() {
        do { body_ = try store.decryptBody(of: entry) }
        catch { decryptError = error.localizedDescription }
    }

    // ── 布局 ─────────────────────────────────────────────
    private func detail(_ body: SecretBody) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                // SSH 连接卡片（一键复制命令）
                if let command = body.sshCommand {
                    Card {
                        HStack(spacing: 12) {
                            Image(systemName: "terminal")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("SSH 连接命令").font(.caption2).foregroundStyle(.secondary)
                                Text(command)
                                    .font(.callout.monospaced())
                                    .textSelection(.enabled)
                                    .lineLimit(2)
                            }
                            Spacer()
                            copyButton(command, key: "sshCommand")
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)

                        if let host = body.host, !host.isEmpty {
                            divider
                            fieldRow(icon: "server.rack", label: "主机",
                                     value: host + ((body.port?.isEmpty == false && body.port != "22")
                                                    ? ":\(body.port!)" : ""),
                                     copyKey: "host")
                        }
                        if let keyPath = body.sshKeyPath, !keyPath.isEmpty {
                            divider
                            fieldRow(icon: "folder", label: "SSH 密钥路径",
                                     value: keyPath, copyKey: "sshKeyPath")
                        }
                    }
                }

                // 凭证卡片
                let chain = body.chain ?? ""
                let privateKey = body.privateKey ?? ""
                if !body.username.isEmpty || !body.password.isEmpty
                    || !body.totpSecret.isEmpty || !chain.isEmpty || !privateKey.isEmpty {
                    Card {
                        if !body.username.isEmpty {
                            fieldRow(icon: "person", label: "账号",
                                     value: body.username, copyKey: "username")
                            if !body.password.isEmpty || !body.totpSecret.isEmpty
                                || !chain.isEmpty || !privateKey.isEmpty { divider }
                        }
                        if !body.password.isEmpty {
                            passwordRow(body.password)
                            if !body.totpSecret.isEmpty || !chain.isEmpty || !privateKey.isEmpty { divider }
                        }
                        if !body.totpSecret.isEmpty {
                            TOTPRow(secret: body.totpSecret)
                                .padding(.horizontal, 14).padding(.vertical, 10)
                            if !chain.isEmpty || !privateKey.isEmpty { divider }
                        }
                        if !chain.isEmpty {
                            fieldRow(icon: "point.3.connected.trianglepath.dotted", label: "网络链",
                                     value: chain, copyKey: "chain")
                            if !privateKey.isEmpty { divider }
                        }
                        if !privateKey.isEmpty {
                            privateKeyRow(privateKey)
                        }
                    }
                }

                // 更多账号
                if let extras = body.extraAccounts, !extras.isEmpty {
                    ForEach(Array(extras.enumerated()), id: \.element.id) { index, account in
                        VStack(alignment: .leading, spacing: 6) {
                            sectionLabel(account.label.isEmpty ? "账号 \(index + 2)" : account.label)
                            Card {
                                ExtraAccountRow(account: account, index: index + 2)
                            }
                        }
                    }
                }

                // 网址卡片
                if !body.urlFull.isEmpty {
                    Card {
                        fieldRow(icon: "link", label: "网址",
                                 value: body.urlFull, copyKey: "url", isLink: true)
                    }
                }

                // 自定义字段
                if !body.customFields.isEmpty {
                    Card {
                        ForEach(Array(body.customFields.enumerated()), id: \.element.id) { index, field in
                            CustomFieldRow(field: field)
                            if index < body.customFields.count - 1 { divider }
                        }
                    }
                }

                // 标签
                if !entry.tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(entry.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 9).padding(.vertical, 3)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }

                // Markdown 笔记
                if !body.notesMarkdown.isEmpty {
                    if category.isNoteLike {
                        // 安全笔记 = 备忘录风格：正文直接铺在窗口上，无框无块背景
                        Divider().opacity(0.4)
                        Markdown(body.notesMarkdown.noteMarkdown)
                            .markdownTheme(.jianmi)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            sectionLabel("笔记")
                            Card {
                                Markdown(body.notesMarkdown.noteMarkdown)
                                    .markdownTheme(.jianmi)
                                    .textSelection(.enabled)
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }

                // 密码历史
                if !body.passwordHistory.isEmpty {
                    DisclosureGroup {
                        Card {
                            ForEach(Array(body.passwordHistory.reversed().enumerated()),
                                    id: \.offset) { index, record in
                                HStack {
                                    Text(record.changedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(String(repeating: "•", count: 10))
                                        .font(.caption.monospaced())
                                    Button {
                                        SecurePasteboard.copy(record.value)
                                    } label: {
                                        Image(systemName: "doc.on.doc").font(.caption)
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                if index < body.passwordHistory.count - 1 { divider }
                            }
                        }
                    } label: {
                        sectionLabel("历史密码（\(body.passwordHistory.count)）")
                    }
                }

                footer
            }
            .padding(category.isNoteLike ? 28 : 20)
            .frame(maxWidth: category.isNoteLike ? 760 : 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: category.isNoteLike ? .leading : .center)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            TypeBadge(typeID: entry.type, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title).font(.title2.bold())
                HStack(spacing: 8) {
                    Text(category.name)
                    if entry.localOnly {
                        Label("仅本机", systemImage: "lock.laptopcomputer")
                            .foregroundStyle(.orange)
                    } else if entry.syncedVersion >= entry.version {
                        Label("已同步", systemImage: "checkmark.icloud")
                            .foregroundStyle(.green)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var footer: some View {
        Text("创建于 \(entry.createdAt.formatted(date: .abbreviated, time: .omitted)) · 修改于 \(entry.updatedAt.formatted(date: .abbreviated, time: .shortened)) · 版本 \(entry.version)")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.top, 4)
    }

    private var divider: some View {
        Divider().padding(.leading, 44).opacity(0.5)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
    }

    // ── 行组件 ───────────────────────────────────────────
    private func fieldRow(icon: String, label: String, value: String,
                          copyKey: String, isLink: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                if isLink, let url = URL(string: value.contains("://") ? value : "https://" + value) {
                    Link(value, destination: url).font(.callout).lineLimit(1)
                } else {
                    Text(value).font(.callout).textSelection(.enabled).lineLimit(1)
                }
            }
            Spacer()
            copyButton(value, key: copyKey)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private func passwordRow(_ password: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "key")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text("密码").font(.caption2).foregroundStyle(.secondary)
                Text(revealPassword ? password : String(repeating: "•", count: 12))
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            }
            Spacer()
            Button {
                revealPassword.toggle()
            } label: {
                Image(systemName: revealPassword ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .help(revealPassword ? "隐藏" : "显示")
            copyButton(password, key: "password")
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private func privateKeyRow(_ key: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "key.horizontal")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text("私钥/助记词").font(.caption2).foregroundStyle(.secondary)
                Text(revealPrivateKey ? key : String(repeating: "•", count: 16))
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(revealPrivateKey ? 6 : 1)
            }
            Spacer()
            Button {
                revealPrivateKey.toggle()
            } label: {
                Image(systemName: revealPrivateKey ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            copyButton(key, key: "privateKey")
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private func copyButton(_ value: String, key: String) -> some View {
        Button {
            SecurePasteboard.copy(
                value, clearAfter: (key == "password" || key == "privateKey") ? 30 : 0)
            copiedField = key
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if copiedField == key { copiedField = nil }
            }
        } label: {
            Image(systemName: copiedField == key ? "checkmark" : "doc.on.doc")
                .foregroundStyle(copiedField == key ? .green : .secondary)
        }
        .buttonStyle(.borderless)
        .help((key == "password" || key == "privateKey")
              ? "复制（30 秒后自动清除剪贴板）" : "复制")
    }
}

/// 额外账号行：账号 + 密码（独立显隐/复制）。
/// 额外账号卡片内容：与主账号同规格（账号/密码/验证码）。
struct ExtraAccountRow: View {
    let account: SecretBody.ExtraAccount
    let index: Int
    @State private var reveal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !account.username.isEmpty {
                row(icon: "person", label: "账号") {
                    Text(account.username)
                        .font(.callout).textSelection(.enabled).lineLimit(1)
                } trailing: {
                    copyButton(account.username, clear: false, help: "复制账号")
                }
                if !account.password.isEmpty || !account.totpSecret.isEmpty {
                    Divider().padding(.leading, 44).opacity(0.5)
                }
            }
            if !account.password.isEmpty {
                row(icon: "key", label: "密码") {
                    Text(reveal ? account.password : String(repeating: "•", count: 12))
                        .font(.callout.monospaced()).textSelection(.enabled)
                } trailing: {
                    Button {
                        reveal.toggle()
                    } label: {
                        Image(systemName: reveal ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    copyButton(account.password, clear: true, help: "复制（30 秒后自动清除）")
                }
                if !account.totpSecret.isEmpty {
                    Divider().padding(.leading, 44).opacity(0.5)
                }
            }
            if !account.totpSecret.isEmpty {
                TOTPRow(secret: account.totpSecret)
                    .padding(.horizontal, 14).padding(.vertical, 10)
            }
        }
    }

    private func row(
        icon: String, label: String,
        @ViewBuilder content: () -> some View,
        @ViewBuilder trailing: () -> some View
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                content()
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private func copyButton(_ value: String, clear: Bool, help: String) -> some View {
        Button {
            SecurePasteboard.copy(value, clearAfter: clear ? 30 : 0)
        } label: {
            Image(systemName: "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

struct CustomFieldRow: View {
    let field: SecretBody.CustomField
    @State private var reveal = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: field.kind == .hidden ? "asterisk" : "text.alignleft")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(field.label).font(.caption2).foregroundStyle(.secondary)
                Text(field.kind == .hidden && !reveal
                     ? String(repeating: "•", count: 10) : field.value)
                    .font(field.kind == .hidden ? .callout.monospaced() : .callout)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
            Spacer()
            if field.kind == .hidden {
                Button { reveal.toggle() } label: {
                    Image(systemName: reveal ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
            }
            Button {
                SecurePasteboard.copy(field.value, clearAfter: field.kind == .hidden ? 30 : 0)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }
}
