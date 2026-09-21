import SwiftUI

/// 条目详情：解密展示 + 复制（30 秒自动清剪贴板）。
struct EntryDetailView: View {
    @ObservedObject var store: EntryStore
    let entry: Entry

    @State private var body_: SecretBody?
    @State private var decryptError: String?
    @State private var revealPassword = false
    @State private var showingEditor = false
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
        .onAppear(perform: decrypt)
        .sheet(isPresented: $showingEditor) {
            EntryEditorView(store: store, editing: entry) { _ in decrypt() }
        }
    }

    private func decrypt() {
        do {
            body_ = try store.decryptBody(of: entry)
        } catch {
            decryptError = error.localizedDescription
        }
    }

    private func detail(_ body: SecretBody) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 头部
                HStack(spacing: 12) {
                    Image(systemName: entry.type.icon)
                        .font(.system(size: 30))
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading) {
                        Text(entry.title).font(.title2.bold())
                        HStack(spacing: 6) {
                            Text(entry.type.label)
                            if entry.localOnly {
                                Label("仅本机", systemImage: "lock.laptopcomputer")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("编辑") { showingEditor = true }
                        .keyboardShortcut("e", modifiers: .command)
                }

                Divider()

                if !body.username.isEmpty {
                    fieldRow("账号", value: body.username, copyKey: "username")
                }
                if !body.password.isEmpty {
                    passwordRow(body.password)
                }
                if !body.urlFull.isEmpty {
                    fieldRow("网址", value: body.urlFull, copyKey: "url", isLink: true)
                }
                if !entry.tags.isEmpty {
                    HStack {
                        ForEach(entry.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }
                if !body.notesMarkdown.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("笔记").font(.caption).foregroundStyle(.secondary)
                        // TODO(M2): MarkdownUI 渲染
                        Text(body.notesMarkdown)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.quaternary.opacity(0.5),
                                        in: RoundedRectangle(cornerRadius: 6))
                    }
                }

                Spacer(minLength: 0)

                Text("修改于 \(entry.updatedAt.formatted(date: .abbreviated, time: .shortened)) · 版本 \(entry.version)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(20)
        }
    }

    private func fieldRow(_ label: String, value: String,
                          copyKey: String, isLink: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HStack {
                if isLink, let url = URL(string: value.contains("://") ? value : "https://" + value) {
                    Link(value, destination: url).lineLimit(1)
                } else {
                    Text(value).textSelection(.enabled).lineLimit(1)
                }
                Spacer()
                copyButton(value, key: copyKey)
            }
        }
    }

    private func passwordRow(_ password: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("密码").font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(revealPassword ? password : String(repeating: "•", count: 12))
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                Spacer()
                Button {
                    revealPassword.toggle()
                } label: {
                    Image(systemName: revealPassword ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                copyButton(password, key: "password")
            }
        }
    }

    private func copyButton(_ value: String, key: String) -> some View {
        Button {
            SecurePasteboard.copy(value)
            copiedField = key
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if copiedField == key { copiedField = nil }
            }
        } label: {
            Image(systemName: copiedField == key ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .help("复制（30 秒后自动清除剪贴板）")
    }
}
