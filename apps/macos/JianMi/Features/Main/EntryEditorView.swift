import SwiftUI

/// 新建 / 编辑条目（sheet）。
struct EntryEditorView: View {
    @ObservedObject var store: EntryStore
    let editing: Entry?
    var onSave: (Entry?) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss

    @State private var draft = EntryDraft()
    @State private var tagsText = ""
    @State private var error: String?
    @State private var showGenerator = false
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("类型", selection: $draft.type) {
                        ForEach(EntryType.allCases) { t in
                            Label(t.label, systemImage: t.icon).tag(t)
                        }
                    }
                    TextField("名称", text: $draft.title, prompt: Text("如：GitHub"))
                    TextField("网址", text: $draft.urlFull, prompt: Text("github.com"))
                    TextField("账号", text: $draft.username, prompt: Text("用户名 / 邮箱 / 手机号"))
                    HStack {
                        TextField("密码", text: $draft.password)
                            .font(.body.monospaced())
                        Button {
                            showGenerator.toggle()
                        } label: {
                            Image(systemName: "dice")
                        }
                        .help("生成强密码")
                        .popover(isPresented: $showGenerator) {
                            GeneratorPopover { generated in
                                draft.password = generated
                                showGenerator = false
                            }
                        }
                    }
                }
                Section {
                    TextField("标签", text: $tagsText, prompt: Text("用逗号分隔，如：工作, 主力邮箱"))
                    Toggle(isOn: $draft.localOnly) {
                        VStack(alignment: .leading) {
                            Text("仅本机（不同步到服务器）")
                            if draft.type.forcesLocalOnly {
                                Text("钱包类条目强制仅本机")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(draft.type.forcesLocalOnly)
                }
                Section("笔记（Markdown）") {
                    TextEditor(text: $draft.notesMarkdown)
                        .font(.body.monospaced())
                        .frame(minHeight: 80)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if let error {
                    Text(error).foregroundStyle(.red).font(.callout)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(editing == nil ? "保存" : "更新") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.title.isEmpty && draft.urlFull.isEmpty)
            }
            .padding(12)
        }
        .frame(width: 480, height: 520)
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
                tagsText = entry.tags.joined(separator: ", ")
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
                Spacer()
                Button {
                    regenerate()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            HStack {
                Text("长度 \(options.length)")
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
            Button("使用此密码") { onUse(generated) }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(width: 320)
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
