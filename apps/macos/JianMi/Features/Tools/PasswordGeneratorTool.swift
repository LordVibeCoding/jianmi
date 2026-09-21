import SwiftUI

/// 小工具 · 密码生成器：独立窗口，生成即用，不写库、不留痕。
/// （锁定状态也可用 —— 不涉及任何机密数据）
struct PasswordGeneratorToolView: View {
    @State private var options = PasswordGenerator.Options()
    @State private var generated = PasswordGenerator.generate()
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 头部
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: [.teal.opacity(0.75), .teal],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: "dice")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text("密码生成器").font(.headline)
                    Text("生成即用，不保存、不留痕")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            // 密码展示
            HStack(spacing: 8) {
                Text(generated)
                    .font(.system(size: 15, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    regenerate()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("r", modifiers: .command)
                .help("重新生成 (⌘R)")
            }
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

            // 强度
            HStack(spacing: 8) {
                PasswordStrengthBar(password: generated)
                Text(entropyText)
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }

            Divider()

            // 选项
            HStack {
                Text("长度")
                Text("\(options.length)")
                    .font(.callout.monospacedDigit().weight(.medium))
                    .frame(width: 26, alignment: .trailing)
                Slider(value: Binding(
                    get: { Double(options.length) },
                    set: { options.length = Int($0); regenerate() }
                ), in: 8...64, step: 1)
            }

            HStack(spacing: 14) {
                optionToggle("A-Z", \.upper)
                optionToggle("a-z", \.lower)
                optionToggle("0-9", \.digits)
                optionToggle("#@!", \.symbols)
                optionToggle("排除易混淆", \.excludeAmbiguous)
            }
            .font(.callout)

            Spacer(minLength: 0)

            // 操作
            Button {
                SecurePasteboard.copy(generated, clearAfter: 0)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
            } label: {
                Label(copied ? "已复制" : "复制密码",
                      systemImage: copied ? "checkmark" : "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            Text("已标记为隐私内容，剪贴板管理器不会记录。")
                .font(.caption2).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(20)
        .frame(width: 400, height: 380)
    }

    private func optionToggle(_ label: String,
                              _ keyPath: WritableKeyPath<PasswordGenerator.Options, Bool>) -> some View {
        Toggle(label, isOn: Binding(
            get: { options[keyPath: keyPath] },
            set: { options[keyPath: keyPath] = $0; regenerate() }
        ))
        .toggleStyle(.checkbox)
    }

    private var entropyText: String {
        var pool = 0
        let ambiguousReduction = options.excludeAmbiguous ? 1 : 0
        if options.upper { pool += 26 - 2 * ambiguousReduction }
        if options.lower { pool += 26 - 1 * ambiguousReduction }
        if options.digits { pool += 10 - 2 * ambiguousReduction }
        if options.symbols { pool += 14 - 1 * ambiguousReduction }
        guard pool > 1 else { return "" }
        let bits = Double(options.length) * log2(Double(pool))
        return String(format: "约 %.0f bit 熵", bits)
    }

    private func regenerate() {
        generated = PasswordGenerator.generate(options)
        copied = false
    }
}
