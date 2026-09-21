import MarkdownUI
import SwiftUI

/// 新建 / 编辑条目（sheet）。
/// 安全笔记类型 = 纯 Markdown 文档模式：不显示账号/密码/网址等凭证字段。
struct EntryEditorView: View {
    @ObservedObject var store: EntryStore
    let editing: Entry?
    var onSave: (Entry?) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss

    @State private var draft = EntryDraft()
    @State private var totpSecret = ""
    @State private var customFields: [SecretBody.CustomField] = []
    @State private var tagsText = ""
    @State private var error: String?
    @State private var showGenerator = false
    @State private var revealPassword = true
    @State private var previewNotes = false
    @State private var loaded = false

    private var isNote: Bool { draft.type == .note }

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack(spacing: 10) {
                TypeBadge(type: draft.type, size: 28)
                Text(editing == nil ? "新建条目" : "编辑「\(editing!.title)」")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 14)

            Divider()

            Form {
                Section {
                    Picker("类型", selection: $draft.type) {
                        ForEach(EntryType.allCases) { t in
                            Label(t.label, systemImage: t.icon).tag(t)
                        }
                    }
                    TextField("名称", text: $draft.title,
                              prompt: Text(isNote ? "笔记标题" : "如：GitHub"))
                    if !isNote {
                    TextField("网址", text: $draft.urlFull, prompt: Text("github.com"))
                    TextField("账号", text: $draft.username, prompt: Text("用户名 / 邮箱 / 手机号"))
                    HStack {
                        Group {
                            if revealPassword {
                                TextField("密码", text: $draft.password)
                            } else {
                                SecureField("密码", text: $draft.password)
                            }
                        }
                        .font(.body.monospaced())

                        if !draft.password.isEmpty {
                            PasswordStrengthBar(password: draft.password)
                        }
                        Button {
                            revealPassword.toggle()
                        } label: {
                            Image(systemName: revealPassword ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        Button {
                            showGenerator.toggle()
                        } label: {
                            Image(systemName: "dice")
                        }
                        .buttonStyle(.borderless)
                        .help("生成强密码")
                        .popover(isPresented: $showGenerator, arrowEdge: .trailing) {
                            GeneratorPopover { generated in
                                draft.password = generated
                                showGenerator = false
                            }
                        }
                    }
                    TextField("两步验证密钥（TOTP）", text: $totpSecret,
                              prompt: Text("base32 密钥或 otpauth:// 链接"))
                    }
                }

                Section {
                    TextField("标签", text: $tagsText, prompt: Text("用逗号分隔，如：工作, 主力邮箱"))
                    Toggle(isOn: $draft.localOnly) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("仅本机（不同步到服务器）")
                            if draft.type.forcesLocalOnly {
                                Text("钱包类条目强制仅本机，保护你的资产")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }
                    .disabled(draft.type.forcesLocalOnly)
                }

                if !isNote {
                Section("自定义字段") {
                    ForEach($customFields) { $field in
                        HStack(spacing: 8) {
                            TextField("字段名", text: $field.label)
                                .frame(width: 110)
                            TextField("内容", text: $field.value)
                            Picker("", selection: $field.kind) {
                                Text("文本").tag(SecretBody.CustomField.Kind.text)
                                Text("隐藏").tag(SecretBody.CustomField.Kind.hidden)
                            }
                            .labelsHidden()
                            .frame(width: 70)
                            Button {
                                customFields.removeAll { $0.id == field.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Button {
                        customFields.append(.init(label: "", value: ""))
                    } label: {
                        Label("添加字段", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                }
                }

                Section(isNote ? "内容（Markdown）" : "笔记（支持 Markdown）") {
                    Picker("", selection: $previewNotes) {
                        Text("编写").tag(false)
                        Text("预览").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if previewNotes {
                        ScrollView {
                            Markdown(draft.notesMarkdown.isEmpty ? "*暂无内容*" : draft.notesMarkdown.noteMarkdown)
                                .markdownTheme(.gitHub)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                        }
                        .frame(minHeight: isNote ? 280 : 90)
                    } else {
                        TextEditor(text: $draft.notesMarkdown)
                            .font(.body.monospaced())
                            .frame(minHeight: isNote ? 280 : 90)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if let error {
                    Text(error).foregroundStyle(.red).font(.callout).lineLimit(1)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(editing == nil ? "保存" : "更新") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.title.isEmpty && draft.urlFull.isEmpty
                              && draft.notesMarkdown.isEmpty)
            }
            .padding(14)
        }
        .frame(width: 520, height: 620)
        .onAppear(perform: load)
        .onChange(of: draft.type) { _, newType in
            if newType.forcesLocalOnly { draft.localOnly = true }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let entry = editing {
            do {
                let body = try store.decryptBody(of: entry)
                draft = EntryDraft.from(entry: entry, body: body)
                totpSecret = body.totpSecret
                customFields = body.customFields
                tagsText = entry.tags.joined(separator: ", ")
                revealPassword = false
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func save() {
        draft.tags = tagsText
            .split(whereSeparator: { $0 == "," || $0 == "，" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        draft.totpSecret = TOTP.normalizeSecret(totpSecret)
        draft.customFields = customFields.filter { !$0.label.isEmpty || !$0.value.isEmpty }
        do {
            if let entry = editing {
                try store.update(entry, with: draft)
                onSave(nil)
            } else {
                let new = try store.add(draft: draft)
                onSave(new)
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// 密码强度指示条。
struct PasswordStrengthBar: View {
    let password: String

    private var strength: (Double, Color) {
        var score = 0.0
        let length = Double(password.count)
        score += min(length / 20.0, 0.5)
        if password.contains(where: { $0.isUppercase }) { score += 0.125 }
        if password.contains(where: { $0.isLowercase }) { score += 0.125 }
        if password.contains(where: { $0.isNumber }) { score += 0.125 }
        if password.contains(where: { !$0.isLetter && !$0.isNumber }) { score += 0.125 }
        let color: Color = score < 0.4 ? .red : score < 0.7 ? .orange : .green
        return (min(score, 1), color)
    }

    var body: some View {
        let (value, color) = strength
        Capsule()
            .fill(.quaternary)
            .frame(width: 50, height: 4)
            .overlay(alignment: .leading) {
                Capsule().fill(color).frame(width: 50 * value)
            }
    }
}

/// 密码生成器弹出框。
struct GeneratorPopover: View {
    var onUse: (String) -> Void

    @State private var options = PasswordGenerator.Options()
    @State private var generated = PasswordGenerator.generate()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(generated)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    regenerate()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
            .padding(8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))

            HStack {
                Text("长度 \(options.length)").font(.callout).frame(width: 55, alignment: .leading)
                Slider(value: Binding(
                    get: { Double(options.length) },
                    set: { options.length = Int($0); regenerate() }
                ), in: 8...64, step: 1)
            }
            HStack(spacing: 12) {
                toggle("A-Z", $options.upper)
                toggle("a-z", $options.lower)
                toggle("0-9", $options.digits)
                toggle("#@!", $options.symbols)
            }
            .font(.callout)

            Button {
                onUse(generated)
            } label: {
                Text("使用此密码").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .frame(width: 340)
    }

    private func toggle(_ label: String, _ binding: Binding<Bool>) -> some View {
        Toggle(label, isOn: Binding(
            get: { binding.wrappedValue },
            set: { binding.wrappedValue = $0; regenerate() }
        ))
        .toggleStyle(.checkbox)
    }

    private func regenerate() {
        generated = PasswordGenerator.generate(options)
    }
}
