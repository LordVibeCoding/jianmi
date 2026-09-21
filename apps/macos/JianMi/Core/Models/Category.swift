import SwiftUI

/// 条目可包含的内置字段。
enum FieldKey: String, Codable, CaseIterable, Identifiable {
    case url, username, password, totp, chain, privateKey

    var id: String { rawValue }

    var label: String {
        switch self {
        case .url:        return "网址"
        case .username:   return "账号"
        case .password:   return "密码"
        case .totp:       return "两步验证（TOTP）"
        case .chain:      return "网络链"
        case .privateKey: return "私钥/助记词"
        }
    }
}

/// 分类：决定条目编辑器显示哪些字段、图标与配色。
/// 内置分类代码定义；自定义分类由用户创建（侧栏 ➕）。
struct Category: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var icon: String            // SF Symbol
    var colorHex: String
    var fields: [FieldKey]
    var forcesLocalOnly: Bool = false
    var isNoteLike: Bool = false    // 纯 Markdown 文档模式（安全笔记）
    var isBuiltin: Bool = false

    var color: Color { Color(hex: colorHex) }
}

@MainActor
final class CategoryStore: ObservableObject {
    static let shared = CategoryStore()

    static let builtins: [Category] = [
        Category(id: "login", name: "账号", icon: "person.badge.key.fill",
                 colorHex: "#3478F6",
                 fields: [.url, .username, .password, .totp], isBuiltin: true),
        Category(id: "wallet", name: "钱包/助记词", icon: "bitcoinsign.circle",
                 colorHex: "#E8912D",
                 fields: [.chain, .privateKey],
                 forcesLocalOnly: true, isBuiltin: true),
        Category(id: "ssh", name: "服务器/SSH", icon: "terminal",
                 colorHex: "#9558F6",
                 fields: [.url, .username, .password], isBuiltin: true),
        Category(id: "identity", name: "证件", icon: "person.text.rectangle",
                 colorHex: "#2FA8A8", fields: [], isBuiltin: true),
        Category(id: "note", name: "安全笔记", icon: "note.text",
                 colorHex: "#E3B341", fields: [],
                 isNoteLike: true, isBuiltin: true),
    ]

    @Published private(set) var custom: [Category] = []

    var all: [Category] { Self.builtins + custom }

    private static let defaultsKey = "categories.custom"

    init() { load() }

    /// 旧类型 ID 归一化：网站/App/银行卡 → 账号。
    nonisolated static func normalize(_ id: String) -> String {
        switch id {
        case "website", "app", "bank_card": return "login"
        default: return id
        }
    }

    func category(for rawID: String) -> Category {
        let id = Self.normalize(rawID)
        if let found = all.first(where: { $0.id == id }) { return found }
        // 已删除的自定义分类 → 兜底展示
        return Category(id: id, name: id, icon: "tag", colorHex: "#8E8E93",
                        fields: [.url, .username, .password, .totp])
    }

    // ── 自定义分类 CRUD ──────────────────────────────────
    func save(_ category: Category) {
        if let index = custom.firstIndex(where: { $0.id == category.id }) {
            custom[index] = category
        } else {
            custom.append(category)
        }
        persist()
    }

    func remove(id: String) {
        custom.removeAll { $0.id == id }
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let list = try? JSONDecoder().decode([Category].self, from: data) else { return }
        custom = list
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}

// ── 十六进制颜色 ─────────────────────────────────────────
extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}
