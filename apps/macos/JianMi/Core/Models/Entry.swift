import Foundation
import GRDB

/// 条目 —— 明文/密文边界（DESIGN.md §3）：
/// 列表与搜索所需最小集合（标题/域名/标签/分类）明文；
/// 一切"值"（账号/密码/私钥/URL 全文/笔记/自定义字段）在 secretBlob 密文里。
struct Entry: Identifiable, Equatable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "entry"

    var uuid: String
    /// 分类 ID（内置: login/wallet/ssh/identity/note，或自定义分类 ID）
    var type: String
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
    /// 服务器已确认的版本（0 = 从未同步）；version > syncedVersion 即本地有待推更改
    var syncedVersion: Int = 0

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

    /// 同一站点的额外账号，字段与主账号对齐（账号/密码/TOTP）
    struct ExtraAccount: Codable, Equatable, Identifiable {
        var id: UUID = UUID()
        var label: String = ""      // 保留字段兼容旧数据，UI 已不再使用
        var username: String = ""
        var password: String = ""
        var totpSecret: String = ""
    }

    var username: String = ""
    var password: String = ""
    var urlFull: String = ""
    var totpSecret: String = ""
    /// 钱包：网络链（如 Ethereum / Solana / BTC）
    var chain: String?
    /// 钱包：私钥或助记词
    var privateKey: String?
    /// 服务器：主机 IP / 域名
    var host: String?
    /// 服务器：端口（空 = 22）
    var port: String?
    /// 服务器：SSH 私钥文件路径（可替代密码）
    var sshKeyPath: String?
    /// 同站点额外账号
    var extraAccounts: [ExtraAccount]?
    var customFields: [CustomField] = []
    var notesMarkdown: String = ""
    var passwordHistory: [PasswordRecord] = []
}

extension SecretBody {
    /// SSH 一键连接命令：ssh [-i 密钥] [-p 端口] user@host
    var sshCommand: String? {
        guard let host, !host.isEmpty else { return nil }
        var parts = ["ssh"]
        if let keyPath = sshKeyPath, !keyPath.isEmpty {
            parts.append("-i")
            parts.append(keyPath)
        }
        if let port, !port.isEmpty, port != "22" {
            parts.append("-p")
            parts.append(port)
        }
        parts.append(username.isEmpty ? host : "\(username)@\(host)")
        return parts.joined(separator: " ")
    }
}
