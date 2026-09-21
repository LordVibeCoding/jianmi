import Foundation

extension String {
    /// 笔记渲染用的 Markdown 预处理（贴合中文输入习惯）：
    ///
    /// 1. **回车即换行**：标准 Markdown 会把单个换行合并成一行（软换行），
    ///    这不符合笔记类应用的直觉 —— 给每个非空行补两个尾随空格（硬换行）。
    /// 2. **`#标题` 自动补空格**：中文输入很少在 # 后打空格，
    ///    `#无敌的` → `# 无敌的`，让标题正常渲染。
    ///
    /// 代码块（``` / ~~~ 围栏）内不做任何处理，保持原样。
    var noteMarkdown: String {
        var output: [String] = []
        output.reserveCapacity(64)
        var inFence = false

        for raw in components(separatedBy: "\n") {
            var line = raw
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 围栏代码块开/关
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                output.append(line)
                continue
            }
            if inFence {
                output.append(line)
                continue
            }

            // "#标题" → "# 标题"（1~6 个 #，后面紧跟非空格非#字符时补空格）
            line = line.replacingOccurrences(
                of: #"^(\s{0,3}#{1,6})(?![#\s])"#,
                with: "$1 ",
                options: .regularExpression)

            // 非空行补硬换行（表格/列表/标题加尾随空格均无副作用）
            if !trimmed.isEmpty {
                line += "  "
            }
            output.append(line)
        }
        return output.joined(separator: "\n")
    }
}
