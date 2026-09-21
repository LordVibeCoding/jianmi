import Foundation
import GRDB

/// SQLite（GRDB, WAL）+ FTS5 全文索引（标题/域名/标签 → 免解锁毫秒级模糊搜索）。
enum AppDatabase {
    static func open(at url: URL) throws -> DatabaseQueue {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        var config = Configuration()
        config.foreignKeysEnabled = true
        let dbQueue = try DatabaseQueue(path: url.path, configuration: config)
        try migrator.migrate(dbQueue)
        return dbQueue
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "entry") { t in
                t.primaryKey("uuid", .text)
                t.column("type", .text).notNull()
                t.column("title", .text).notNull()
                t.column("urlHost", .text)
                t.column("tags", .text).notNull().defaults(to: "[]")
                t.column("localOnly", .boolean).notNull().defaults(to: false)
                t.column("favorite", .boolean).notNull().defaults(to: false)
                t.column("version", .integer).notNull().defaults(to: 1)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
                t.column("secretBlob", .blob).notNull()
            }
            try db.create(index: "entry_updatedAt", on: "entry", columns: ["updatedAt"])

            try db.create(virtualTable: "entry_fts", using: FTS5()) { t in
                t.synchronize(withTable: "entry")
                t.column("title")
                t.column("urlHost")
                t.column("tags")
            }
        }

        // v2: 同步支持 —— 已同步版本标记 + 键值元数据表（lastSeq 等）
        migrator.registerMigration("v2-sync") { db in
            try db.alter(table: "entry") { t in
                t.add(column: "syncedVersion", .integer).notNull().defaults(to: 0)
            }
            try db.create(table: "app_meta") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
        }
        return migrator
    }
}
