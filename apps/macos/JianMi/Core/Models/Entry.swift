import Foundation
import GRDB

/// 条目类型（模板）。钱包类强制 local_only —— 物理上永不进同步队列。
enum EntryType: String, Codable, CaseIterable, Identifiable {
    case website = "website"
    case app = "app"
    case bankCard = "bank_card"
    case wallet = "wallet"
    case ssh = "ssh"
    case identity = "identity"
    case note = "note"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .website:  return "网站"
        case .app:      return "App"
        case .bankCard: return "银行卡"
        case .wallet:   return "钱包/助记词"
        case .ssh:      return "服务器/SSH"
        case .identity: return "证件"
        case .note:     return "安全笔记"
        }
    }

    var icon: String {
        switch self {
        case .website:  return "globe"
        case .app:      return "app.badge"
        case .bankCard: return "creditcard"
        case .wallet:   return "bitcoinsign.circle"
        case .ssh:      return "terminal"
        case .identity: return "person.text.rectangle"
        case .note:     return "note.text"
        }
    }

    /// 钱包助记词级资产：强制仅本机，UI 不允许关闭。
    var forcesLocalOnly: Bool { self == .wallet }
}

/// 条目 —— 明文/密文边界（DESIGN.md §3）：
/// 列表与搜索所需最小集合（标题/域名/标签/类型）明文；
/// 一切"值"（账号/密码/URL 全文/笔记/自定义字段）在 secretBlob 密文里。
struct Entry: Identifiable, Equatable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "entry"

    var uuid: String
    var type: EntryType
    var title: String
    var urlHost: String?
    var tags: [String]
    var localOnly: Bool
    var favorite: Bool
    var version: Int
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var secretBlob: Data

    var id: String { uuid }
}

/// 密文体：JSON 编码后整体 AEAD 加密（AAD = 条目 uuid，防密文调包）。
struct SecretBody: Codable, Equatable {
    struct CustomField: Codable, Equatable, Identifiable {
        enum Kind: String, Codable { case text, hidden, url }
        var id: UUID = UUID()
        var label: String
        var value: String
        var kind: Kind = .text
    }

    struct PasswordRecord: Codable, Equatable {
        var value: String
        var changedAt: Date
    }

    var username: String = ""
    var password: String = ""
    var urlFull: String = ""
    var totpSecret: String = ""
    var customFields: [CustomField] = []
    var notesMarkdown: String = ""
    var passwordHistory: [PasswordRecord] = []
}
