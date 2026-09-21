import Foundation
import GRDB

/// 侧栏筛选。
enum SidebarFilter: Hashable {
    case all
    case favorites
    case localOnly
    case type(EntryType)

    var label: String {
        switch self {
        case .all:            return "全部条目"
        case .favorites:      return "收藏"
        case .localOnly:      return "仅本机"
        case .type(let t):    return t.label
        }
    }

    var icon: String {
        switch self {
        case .all:            return "tray.full"
        case .favorites:      return "star"
        case .localOnly:      return "lock.laptopcomputer"
        case .type(let t):    return t.icon
        }
    }
}

/// 条目编辑草稿（UI 层与加密层的桥）。
struct EntryDraft {
    var type: EntryType = .website
    var title: String = ""
    var urlFull: String = ""
    var username: String = ""
    var password: String = ""
    var notesMarkdown: String = ""
    var tags: [String] = []
    var localOnly: Bool = false
    var favorite: Bool = false

    static func from(entry: Entry, body: SecretBody) -> EntryDraft {
        EntryDraft(
            type: entry.type, title: entry.title, urlFull: body.urlFull,
            username: body.username, password: body.password,
            notesMarkdown: body.notesMarkdown, tags: entry.tags,
            localOnly: entry.localOnly, favorite: entry.favorite)
    }
}

/// 条目仓库：CRUD + FTS 搜索 + 加解密封装。
@MainActor
final class EntryStore: ObservableObject {
    @Published private(set) var entries: [Entry] = []
    @Published var searchText: String = "" { didSet { reload() } }
    @Published var filter: SidebarFilter = .all { didSet { reload() } }

    private let dbQueue: DatabaseQueue
    private let vault: VaultManager
    private let crypto = CryptoEngine.shared

    init(vault: VaultManager) throws {
        self.vault = vault
        self.dbQueue = try AppDatabase.open(at: vault.dbURL)
        reload()
    }

    // ── 查询 ──────────────────────────────────────────────
    func reload() {
        let search = searchText.trimmingCharacters(in: .whitespaces)
        let filter = self.filter
        do {
            entries = try dbQueue.read { db in
                var sql = "SELECT entry.* FROM entry"
                var args: [DatabaseValueConvertible] = []
                var conditions = ["entry.deletedAt IS NULL"]

                if !search.isEmpty, let pattern = FTS5Pattern(matchingAllPrefixesIn: search) {
                    sql += " JOIN entry_fts ON entry_fts.rowid = entry.rowid AND entry_fts MATCH ?"
                    args.append(pattern)
                }
                switch filter {
                case .all: break
                case .favorites: conditions.append("entry.favorite = 1")
                case .localOnly: conditions.append("entry.localOnly = 1")
                case .type(let t):
                    conditions.append("entry.type = ?")
                    args.append(t.rawValue)
                }
                sql += " WHERE " + conditions.joined(separator: " AND ")
                sql += " ORDER BY entry.favorite DESC, entry.updatedAt DESC"
                return try Entry.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            }
        } catch {
            NSLog("EntryStore.reload 失败: \(error)")
            entries = []
        }
    }

    // ── 加解密 ────────────────────────────────────────────
    private func key() throws -> [UInt8] {
        guard let key = vault.vaultKey else { throw VaultError.notUnlocked }
        return key.bytes
    }

    func decryptBody(of entry: Entry) throws -> SecretBody {
        let data = try crypto.open(
            blob: entry.secretBlob, key: try key(), aad: Data(entry.uuid.utf8))
        return try JSONDecoder().decode(SecretBody.self, from: data)
    }

    private func encrypt(_ body: SecretBody, uuid: String) throws -> Data {
        let data = try JSONEncoder().encode(body)
        return try crypto.seal(plaintext: data, key: try key(), aad: Data(uuid.utf8))
    }

    // ── 写入 ──────────────────────────────────────────────
    @discardableResult
    func add(draft: EntryDraft) throws -> Entry {
        let uuid = UUID().uuidString.lowercased()
        var body = SecretBody()
        body.username = draft.username
        body.password = draft.password
        body.urlFull = draft.urlFull
        body.notesMarkdown = draft.notesMarkdown

        let now = Date()
        let entry = Entry(
            uuid: uuid,
            type: draft.type,
            title: draft.title.isEmpty ? "未命名" : draft.title,
            urlHost: Self.host(from: draft.urlFull),
            tags: draft.tags,
            localOnly: draft.localOnly || draft.type.forcesLocalOnly,
            favorite: draft.favorite,
            version: 1,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            secretBlob: try encrypt(body, uuid: uuid))

        try dbQueue.write { db in try entry.insert(db) }
        reload()
        return entry
    }

    func update(_ entry: Entry, with draft: EntryDraft) throws {
        var body = try decryptBody(of: entry)

        // 密码变更 → 自动留存历史
        if body.password != draft.password, !body.password.isEmpty {
            body.passwordHistory.append(
                .init(value: body.password, changedAt: Date()))
        }
        body.username = draft.username
        body.password = draft.password
        body.urlFull = draft.urlFull
        body.notesMarkdown = draft.notesMarkdown

        var updated = entry
        updated.type = draft.type
        updated.title = draft.title.isEmpty ? "未命名" : draft.title
        updated.urlHost = Self.host(from: draft.urlFull)
        updated.tags = draft.tags
        updated.localOnly = draft.localOnly || draft.type.forcesLocalOnly
        updated.favorite = draft.favorite
        updated.version += 1
        updated.updatedAt = Date()
        updated.secretBlob = try encrypt(body, uuid: entry.uuid)

        try dbQueue.write { db in try updated.update(db) }
        reload()
    }

    func toggleFavorite(_ entry: Entry) throws {
        var updated = entry
        updated.favorite.toggle()
        updated.updatedAt = Date()
        try dbQueue.write { db in try updated.update(db) }
        reload()
    }

    /// 软删除（墓碑）—— 同步协议需要，且防误删。
    func softDelete(_ entry: Entry) throws {
        var updated = entry
        updated.deletedAt = Date()
        updated.version += 1
        try dbQueue.write { db in try updated.update(db) }
        reload()
    }

    // ── 工具 ──────────────────────────────────────────────
    static func host(from urlString: String) -> String? {
        guard !urlString.isEmpty else { return nil }
        var s = urlString
        if !s.contains("://") { s = "https://" + s }
        return URLComponents(string: s)?.host?.lowercased()
    }
}
