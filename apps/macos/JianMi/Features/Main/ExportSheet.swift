import SwiftUI
import UniformTypeIdentifiers

/// 导出：范围（全部 / 单个分类）× 格式（JSON / Markdown）→ 用户自选位置。
/// ⚠️ 导出为明文 —— 界面上有醒目警示。
@MainActor
struct ExportSheet: View {
    @ObservedObject var store: EntryStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var categories = CategoryStore.shared

    enum Format: String, CaseIterable, Identifiable {
        case json, markdown
        var id: String { rawValue }
        var label: String { self == .json ? "JSON（单文件）" : "Markdown（每条一个 .md）" }
    }

    /// nil = 全部分类
    @State private var scopeCategoryID: String?
    @State private var format: Format = .json
    @State private var error: String?
    @State private var isExporting = false

    private var entriesInScope: [Entry] {
        store.allEntries(categoryID: scopeCategoryID)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.up")
                    .font(.title3).foregroundStyle(.tint)
                Text("导出").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 14)

            Divider()

            Form {
                Section {
                    Picker("范围", selection: $scopeCategoryID) {
                        Text("全部分类").tag(String?.none)
                        ForEach(categories.all) { c in
                            Label(c.name, systemImage: c.icon).tag(String?.some(c.id))
                        }
                    }
                    Picker("格式", selection: $format) {
                        ForEach(Format.allCases) { f in
                            Text(f.label).tag(f)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()

                    LabeledContent("将导出") {
                        Text("\(entriesInScope.count) 条")
                            .foregroundStyle(entriesInScope.isEmpty ? .red : .secondary)
                    }
                }

                Section {
                    Label("导出内容为**明文**，包含所有密码与私钥。请存放到安全位置，用完及时删除。",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red).lineLimit(1)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    performExport()
                } label: {
                    if isExporting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("导出…")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(entriesInScope.isEmpty || isExporting)
            }
            .padding(14)
        }
        .frame(width: 420, height: 400)
    }

    // ── 执行 ─────────────────────────────────────────────
    private func performExport() {
        error = nil
        let entries = entriesInScope
        switch format {
        case .json:     exportJSON(entries)
        case .markdown: exportMarkdown(entries)
        }
    }

    private var dateStamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter.string(from: Date())
    }

    private func exportJSON(_ entries: [Entry]) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "jianmi-export-\(dateStamp).json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isExporting = true
        do {
            let data = try Exporter.json(entries: entries, store: store)
            try data.write(to: url, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isExporting = false
    }

    private func exportMarkdown(_ entries: [Entry]) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "导出到此文件夹"
        panel.message = "选择存放 .md 文件的文件夹（每条记录一个文件）"
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        isExporting = true
        do {
            let target = folder.appendingPathComponent("简密导出-\(dateStamp)", isDirectory: true)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            try Exporter.markdownFiles(entries: entries, store: store, to: target)
            NSWorkspace.shared.activateFileViewerSelecting([target])
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isExporting = false
    }
}

// ── 导出器 ───────────────────────────────────────────────
@MainActor
enum Exporter {
    private static let isoFormatter = ISO8601DateFormatter()

    // JSON：单文件，含全部解密字段
    static func json(entries: [Entry], store: EntryStore) throws -> Data {
        var items: [[String: Any]] = []
        for entry in entries {
            let body = try store.decryptBody(of: entry)
            let category = CategoryStore.shared.category(for: entry.type)
            var item: [String: Any] = [
                "uuid": entry.uuid,
                "category": entry.type,
                "categoryName": category.name,
                "title": entry.title,
                "tags": entry.tags,
                "localOnly": entry.localOnly,
                "favorite": entry.favorite,
                "createdAt": isoFormatter.string(from: entry.createdAt),
                "updatedAt": isoFormatter.string(from: entry.updatedAt),
            ]
            if !body.urlFull.isEmpty { item["url"] = body.urlFull }
            if !body.username.isEmpty { item["username"] = body.username }
            if !body.password.isEmpty { item["password"] = body.password }
            if !body.totpSecret.isEmpty { item["totpSecret"] = body.totpSecret }
            if let chain = body.chain, !chain.isEmpty { item["chain"] = chain }
            if let key = body.privateKey, !key.isEmpty { item["privateKey"] = key }
            if let host = body.host, !host.isEmpty { item["host"] = host }
            if let port = body.port, !port.isEmpty { item["port"] = port }
            if let path = body.sshKeyPath, !path.isEmpty { item["sshKeyPath"] = path }
            if let command = body.sshCommand { item["sshCommand"] = command }
            if let extras = body.extraAccounts, !extras.isEmpty {
                item["extraAccounts"] = extras.map {
                    var account: [String: Any] = [
                        "username": $0.username, "password": $0.password,
                    ]
                    if !$0.totpSecret.isEmpty { account["totpSecret"] = $0.totpSecret }
                    return account
                }
            }
            if !body.customFields.isEmpty {
                item["customFields"] = body.customFields.map {
                    ["label": $0.label, "value": $0.value, "hidden": $0.kind == .hidden]
                }
            }
            if !body.notesMarkdown.isEmpty { item["notes"] = body.notesMarkdown }
            items.append(item)
        }

        let root: [String: Any] = [
            "app": "简密 JianMi",
            "format": 1,
            "exportedAt": isoFormatter.string(from: Date()),
            "count": items.count,
            "entries": items,
        ]
        return try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    // Markdown：每条一个 .md（安全笔记纯正文，可与导入往返；其余结构化）
    static func markdownFiles(entries: [Entry], store: EntryStore, to folder: URL) throws {
        var usedNames: Set<String> = []
        for entry in entries {
            let body = try store.decryptBody(of: entry)
            let content = markdown(for: entry, body: body)
            let name = uniqueFilename(for: entry.title, used: &usedNames)
            try content.write(
                to: folder.appendingPathComponent(name),
                atomically: true, encoding: .utf8)
        }
    }

    private static func markdown(for entry: Entry, body: SecretBody) -> String {
        let category = CategoryStore.shared.category(for: entry.type)

        // 安全笔记：标题 + 正文，与导入功能完美往返
        if category.isNoteLike {
            return "# \(entry.title)\n\n\(body.notesMarkdown)\n"
        }

        var lines = ["# \(entry.title)", ""]
        lines.append("- 分类：\(category.name)")
        if !body.urlFull.isEmpty { lines.append("- 网址：\(body.urlFull)") }
        if !body.username.isEmpty { lines.append("- 账号：`\(body.username)`") }
        if !body.password.isEmpty { lines.append("- 密码：`\(body.password)`") }
        if !body.totpSecret.isEmpty { lines.append("- 两步验证密钥：`\(body.totpSecret)`") }
        if let chain = body.chain, !chain.isEmpty { lines.append("- 网络链：\(chain)") }
        if let key = body.privateKey, !key.isEmpty { lines.append("- 私钥/助记词：`\(key)`") }
        if let host = body.host, !host.isEmpty { lines.append("- 主机：\(host)") }
        if let port = body.port, !port.isEmpty { lines.append("- 端口：\(port)") }
        if let path = body.sshKeyPath, !path.isEmpty { lines.append("- SSH 密钥：`\(path)`") }
        if let command = body.sshCommand { lines.append("- 连接命令：`\(command)`") }
        if let extras = body.extraAccounts {
            for (index, account) in extras.enumerated() {
                var line = "- 账号\(index + 2)：`\(account.username)` / `\(account.password)`"
                if !account.totpSecret.isEmpty { line += " / TOTP: `\(account.totpSecret)`" }
                lines.append(line)
            }
        }
        for field in body.customFields where !field.value.isEmpty {
            lines.append("- \(field.label)：`\(field.value)`")
        }
        if !entry.tags.isEmpty { lines.append("- 标签：\(entry.tags.joined(separator: ", "))") }
        if entry.localOnly { lines.append("- 仅本机：是") }
        lines.append("- 更新时间：\(isoFormatter.string(from: entry.updatedAt))")

        if !body.notesMarkdown.isEmpty {
            lines.append("")
            lines.append("---")
            lines.append("")
            lines.append(body.notesMarkdown)
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func uniqueFilename(for title: String, used: inout Set<String>) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|\0")
        var base = title.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        if base.isEmpty { base = "未命名" }
        base = String(base.prefix(60))

        var candidate = base
        var index = 2
        while used.contains(candidate.lowercased()) {
            candidate = "\(base)-\(index)"
            index += 1
        }
        used.insert(candidate.lowercased())
        return candidate + ".md"
    }
}
