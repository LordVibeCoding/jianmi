import Foundation
import GRDB

/// 侧栏筛选。
enum SidebarFilter: Hashable {
    case all
    case favorites
    case localOnly
    case category(String)
}

/// 条目编辑草稿（UI 层与加密层的桥）。
struct EntryDraft {
    var type: String = "login"
    var title: String = ""
    var urlFull: String = ""
    var username: String = ""
    var password: String = ""
    var totpSecret: String = ""
    var chain: String = ""
    var privateKey: String = ""
    var customFields: [SecretBody.CustomField] = []
    var notesMarkdown: String = ""
    var tags: [String] = []
    var localOnly: Bool = false
    var favorite: Bool = false

    static func from(entry: Entry, body: SecretBody) -> EntryDraft {
        EntryDraft(
            type: entry.type, title: entry.title, urlFull: body.urlFull,
            username: body.username, password: body.password,
            totpSecret: body.totpSecret,
            chain: body.chain ?? "", privateKey: body.privateKey ?? "",
            customFields: body.customFields,
            notesMarkdown: body.notesMarkdown, tags: entry.tags,
            localOnly: entry.localOnly, favorite: entry.favorite)
    }
}

/// 条目仓库：CRUD + FTS 搜索 + 加解密封装。
@MainActor
final class EntryStore: ObservableObject {
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var counts: [SidebarFilter: Int] = [:]
    @Published var searchText: String = "" { didSet { reload() } }
    @Published var filter: SidebarFilter = .all { didSet { reload() } }

    /// 数据变更回调（AppState 用于触发防抖同步）
    var onChange: (() -> Void)?

    let dbQueue: DatabaseQueue
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
                case .category(let id):
                    conditions.append("entry.type = ?")
                    args.append(id)
                }
                sql += " WHERE " + conditions.joined(separator: " AND ")
                sql += " ORDER BY entry.favorite DESC, entry.updatedAt DESC"
                return try Entry.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            }
            reloadCounts()
        } catch {
            NSLog("EntryStore.reload 失败: \(error)")
            entries = []
        }
    }

    private func reloadCounts() {
        var result: [SidebarFilter: Int] = [:]
        do {
            try dbQueue.read { db in
                result[.all] = try Int.fetchOne(
                    db, sql: "SELECT COUNT(*) FROM entry WHERE deletedAt IS NULL") ?? 0
                result[.favorites] = try Int.fetchOne(
                    db, sql: "SELECT COUNT(*) FROM entry WHERE deletedAt IS NULL AND favorite = 1") ?? 0
                result[.localOnly] = try Int.fetchOne(
                    db, sql: "SELECT COUNT(*) FROM entry WHERE deletedAt IS NULL AND localOnly = 1") ?? 0
                let rows = try Row.fetchAll(
                    db, sql: "SELECT type, COUNT(*) AS c FROM entry WHERE deletedAt IS NULL GROUP BY type")
                for row in rows {
                    let id = CategoryStore.normalize(row["type"])
                    let count: Int = row["c"]
                    result[.category(id), default: 0] += count
                }
            }
        } catch {}
        counts = result
    }

    /// 快速搜索面板专用（不干扰主窗口的筛选状态）。
    func quickSearch(_ query: String, limit: Int = 8) -> [Entry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return (try? dbQueue.read { db in
            if q.isEmpty {
                return try Entry.fetchAll(db, sql: """
                    SELECT * FROM entry WHERE deletedAt IS NULL
                    ORDER BY favorite DESC, updatedAt DESC LIMIT ?
                    """, arguments: [limit])
            }
            guard let pattern = FTS5Pattern(matchingAllPrefixesIn: q) else { return [] }
            return try Entry.fetchAll(db, sql: """
                SELECT entry.* FROM entry
                JOIN entry_fts ON entry_fts.rowid = entry.rowid AND entry_fts MATCH ?
                WHERE entry.deletedAt IS NULL
                ORDER BY entry.favorite DESC, entry.updatedAt DESC LIMIT ?
                """, arguments: [pattern, limit])
        }) ?? []
    }

    /// 按域名匹配（浏览器扩展用）：精确匹配或子域名匹配。
    func matching(host: String, limit: Int = 20) -> [Entry] {
        let h = host.lowercased()
        // 去 www 前缀的主域名，让 www.github.com 能匹配 github.com 条目
        let bare = h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
        return (try? dbQueue.read { db in
            try Entry.fetchAll(db, sql: """
                SELECT * FROM entry
                WHERE deletedAt IS NULL AND urlHost IS NOT NULL AND (
                    urlHost = ?1 OR urlHost = ?2 OR
                    urlHost LIKE '%.' || ?2 OR ?2 LIKE '%.' || urlHost
                )
                ORDER BY favorite DESC, updatedAt DESC LIMIT ?3
                """, arguments: [h, bare, limit])
        }) ?? []
    }

    /// 导出用：指定分类（nil = 全部）的全部未删除条目。
    func allEntries(categoryID: String?) -> [Entry] {
        (try? dbQueue.read { db in
            if let id = categoryID {
                return try Entry.fetchAll(db, sql: """
                    SELECT * FROM entry WHERE deletedAt IS NULL AND type = ?
                    ORDER BY updatedAt DESC
                    """, arguments: [id])
            }
            return try Entry.fetchAll(db, sql: """
                SELECT * FROM entry WHERE deletedAt IS NULL ORDER BY type, updatedAt DESC
                """)
        }) ?? []
    }

    /// 按 uuid 取单条（浏览器扩展用）。
    func entry(uuid: String) -> Entry? {
        try? dbQueue.read { db in try Entry.fetchOne(db, key: uuid) }
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
        body.totpSecret = draft.totpSecret
        body.chain = draft.chain.isEmpty ? nil : draft.chain
        body.privateKey = draft.privateKey.isEmpty ? nil : draft.privateKey
        body.customFields = draft.customFields
        body.notesMarkdown = draft.notesMarkdown

        let now = Date()
        let entry = Entry(
            uuid: uuid,
            type: draft.type,
            title: draft.title.isEmpty ? "未命名" : draft.title,
            urlHost: Self.host(from: draft.urlFull),
            tags: draft.tags,
            localOnly: draft.localOnly
                || CategoryStore.shared.category(for: draft.type).forcesLocalOnly,
            favorite: draft.favorite,
            version: 1,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            secretBlob: try encrypt(body, uuid: uuid),
            syncedVersion: 0)

        try dbQueue.write { db in try entry.insert(db) }
        reload()
        onChange?()
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
        body.totpSecret = draft.totpSecret
        body.chain = draft.chain.isEmpty ? nil : draft.chain
        body.privateKey = draft.privateKey.isEmpty ? nil : draft.privateKey
        body.customFields = draft.customFields
        body.notesMarkdown = draft.notesMarkdown

        var updated = entry
        updated.type = draft.type
        updated.title = draft.title.isEmpty ? "未命名" : draft.title
        updated.urlHost = Self.host(from: draft.urlFull)
        updated.tags = draft.tags
        updated.localOnly = draft.localOnly
            || CategoryStore.shared.category(for: draft.type).forcesLocalOnly
        updated.favorite = draft.favorite
        updated.version += 1
        updated.updatedAt = Date()
        updated.secretBlob = try encrypt(body, uuid: entry.uuid)

        try dbQueue.write { db in try updated.update(db) }
        reload()
        onChange?()
    }

    func toggleFavorite(_ entry: Entry) throws {
        var updated = entry
        updated.favorite.toggle()
        updated.version += 1
        updated.updatedAt = Date()
        try dbQueue.write { db in try updated.update(db) }
        reload()
        onChange?()
    }

    /// 软删除（墓碑）—— 同步协议需要，且防误删。
    func softDelete(_ entry: Entry) throws {
        var updated = entry
        updated.deletedAt = Date()
        updated.version += 1
        try dbQueue.write { db in try updated.update(db) }
        reload()
        onChange?()
    }

    // ── 工具 ──────────────────────────────────────────────
    nonisolated static func host(from urlString: String) -> String? {
        guard !urlString.isEmpty else { return nil }
        var s = urlString
        if !s.contains("://") { s = "https://" + s }
        return URLComponents(string: s)?.host?.lowercased()
    }
}
