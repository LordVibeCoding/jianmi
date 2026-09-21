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
        // 「证件」已移除：需要的话用自定义分类创建；
        // 存量 identity 条目仍可在全部条目中查看（兑底样式）并可改分类
        Category(id: "note", name: "安全笔记", icon: "note.text",
                 colorHex: "#E3B341", fields: [],
                 isNoteLike: true, isBuiltin: true),
    ]

    @Published private(set) var custom: [Category] = []
    /// 内置分类的用户自定义覆盖（改名/换图标/换色/改字段）
    @Published private(set) var overrides: [String: Category] = [:]

    var all: [Category] {
        Self.builtins.map { overrides[$0.id] ?? $0 } + custom
    }

    private static let defaultsKey = "categories.custom"
    private static let overridesKey = "categories.overrides"

    init() { load() }

    static func baseBuiltin(id: String) -> Category? {
        builtins.first { $0.id == id }
    }

    func isOverridden(_ id: String) -> Bool { overrides[id] != nil }

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
        if let base = Self.baseBuiltin(id: category.id) {
            var override = category
            // 内置底线不可篡改：钱包类强制仅本机不许关，笔记类始终是文档模式
            override.isBuiltin = true
            override.isNoteLike = base.isNoteLike
            if base.forcesLocalOnly { override.forcesLocalOnly = true }
            overrides[category.id] = override
        } else if let index = custom.firstIndex(where: { $0.id == category.id }) {
            custom[index] = category
        } else {
            custom.append(category)
        }
        persist()
    }

    /// 内置分类恢复默认外观与字段。
    func resetBuiltin(id: String) {
        overrides.removeValue(forKey: id)
        persist()
    }

    func remove(id: String) {
        custom.removeAll { $0.id == id }
        persist()
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let list = try? JSONDecoder().decode([Category].self, from: data) {
            custom = list
        }
        if let data = UserDefaults.standard.data(forKey: Self.overridesKey),
           let map = try? JSONDecoder().decode([String: Category].self, from: data) {
            overrides = map
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
        if let data = try? JSONEncoder().encode(overrides) {
            UserDefaults.standard.set(data, forKey: Self.overridesKey)
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
