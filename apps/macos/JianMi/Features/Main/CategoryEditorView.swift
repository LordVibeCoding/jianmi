import SwiftUI

/// 新建 / 编辑自定义分类：名称、图标、配色、包含哪些字段。
@MainActor
struct CategoryEditorView: View {
    var editing: Category?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var categories = CategoryStore.shared

    @State private var name = ""
    @State private var icon = "tag"
    @State private var colorHex = "#3478F6"
    @State private var fields: Set<FieldKey> = [.url, .username, .password]
    @State private var forcesLocalOnly = false
    @State private var loaded = false

    private static let icons = [
        "tag", "folder", "briefcase", "gamecontroller", "cart",
        "creditcard", "banknote", "building.columns", "graduationcap",
        "airplane", "car", "house", "heart", "cross.case",
        "wifi", "envelope", "phone", "tv", "cloud", "shield",
    ]

    private static let colors = [
        "#3478F6", "#5E5CE6", "#9558F6", "#E8912D",
        "#E0426B", "#2FA85A", "#2FA8A8", "#8E8E93",
    ]

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏 + 实时预览
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 34 * 0.28, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(hex: colorHex).opacity(0.75), Color(hex: colorHex)],
                        startPoint: .top, endPoint: .bottom))
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                Text(editing == nil ? "新建分类" : "编辑「\(editing!.name)」")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 14)

            Divider()

            Form {
                Section {
                    TextField("分类名称", text: $name, prompt: Text("如：游戏、公司内网"))
                }

                Section("图标") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 10), spacing: 8) {
                        ForEach(Self.icons, id: \.self) { symbol in
                            Button {
                                icon = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .font(.system(size: 14))
                                    .frame(width: 30, height: 30)
                                    .background(
                                        icon == symbol
                                            ? AnyShapeStyle(Color.accentColor.opacity(0.2))
                                            : AnyShapeStyle(.clear),
                                        in: RoundedRectangle(cornerRadius: 6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(icon == symbol ? Color.accentColor : .clear))
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                Section("颜色") {
                    HStack(spacing: 10) {
                        ForEach(Self.colors, id: \.self) { hex in
                            Button {
                                colorHex = hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Circle().strokeBorder(
                                            .primary.opacity(colorHex == hex ? 0.8 : 0),
                                            lineWidth: 2))
                            }
                            .buttonStyle(.borderless)
                        }
                        Spacer()
                    }
                }

                Section("此分类包含的字段") {
                    ForEach(FieldKey.allCases) { field in
                        Toggle(field.label, isOn: Binding(
                            get: { fields.contains(field) },
                            set: { on in
                                if on { fields.insert(field) } else { fields.remove(field) }
                            }))
                    }
                    Text("名称、标签、自定义字段与 Markdown 笔记始终可用。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    Toggle(isOn: $forcesLocalOnly) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("强制仅本机")
                            Text("此分类的条目永不同步到服务器")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(editing == nil ? "创建" : "保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(14)
        }
        .frame(width: 460, height: 560)
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let editing {
            name = editing.name
            icon = editing.icon
            colorHex = editing.colorHex
            fields = Set(editing.fields)
            forcesLocalOnly = editing.forcesLocalOnly
        }
    }

    private func save() {
        let category = Category(
            id: editing?.id ?? "custom-\(UUID().uuidString.lowercased().prefix(8))",
            name: name.trimmingCharacters(in: .whitespaces),
            icon: icon,
            colorHex: colorHex,
            fields: FieldKey.allCases.filter { fields.contains($0) },   // 保持稳定顺序
            forcesLocalOnly: forcesLocalOnly)
        categories.save(category)
        dismiss()
    }
}
