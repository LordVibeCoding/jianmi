import Foundation
import GRDB

// ── 配置 ─────────────────────────────────────────────────
enum SyncSettings {
    private static let tokenService = "com.jianmi.mac"
    private static let tokenAccount = "syncToken"

    static var serverURL: String {
        get { UserDefaults.standard.string(forKey: "sync.serverURL") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "sync.serverURL") }
    }

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "sync.enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "sync.enabled") }
    }

    static var token: String {
        get {
            guard let data = KeychainHelper.load(service: tokenService, account: tokenAccount)
            else { return "" }
            return String(data: data, encoding: .utf8) ?? ""
        }
        set {
            if newValue.isEmpty {
                KeychainHelper.delete(service: tokenService, account: tokenAccount)
            } else {
                try? KeychainHelper.save(Data(newValue.utf8), service: tokenService, account: tokenAccount)
            }
        }
    }

    static var isConfigured: Bool { !serverURL.isEmpty && !token.isEmpty }

    static func normalizedBaseURL() -> URL? {
        var s = serverURL.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "http://" + s }
        if s.hasSuffix("/") { s.removeLast() }
        return URL(string: s)
    }
}

// ── 网络协议模型（与 server/src/main.rs 对齐）──────────────
struct SyncRecord: Codable {
    var uuid: String
    var version: Int
    var seq: Int?
    var deleted: Bool
    var payload: String        // base64(seal(SyncPayload JSON, VaultKey, aad: "sync:"+uuid))
}

/// 零知识同步载荷：条目全部字段（含明文元数据）整体加密后上传。
/// 服务器只见 uuid/version/seq/deleted + 密文。
struct SyncPayload: Codable {
    var type: String        // 分类 ID（旧设备的 website/app/bank_card 在应用时归一化）
    var title: String
    var urlHost: String?
    var tags: [String]
    var favorite: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var secretBlob: Data       // 内层：JM 格式 AEAD 密文（AAD = uuid）
}

private struct PullRequest: Codable { var since_seq: Int }
private struct PullResponse: Codable { var latest_seq: Int; var entries: [SyncRecord] }
private struct PushRequest: Codable { var entries: [SyncRecord] }
private struct PushResponse: Codable {
    struct Accepted: Codable { var uuid: String; var seq: Int }
    var accepted: [Accepted]
    var conflicts: [SyncRecord]
}

enum SyncError: Error, LocalizedError {
    case notConfigured
    case badURL
    case httpError(Int)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "尚未配置同步服务器"
        case .badURL:        return "服务器地址无效"
        case .httpError(let code): return "服务器错误 (HTTP \(code))"
        case .unauthorized:  return "访问令牌无效"
        }
    }
}

// ── 同步引擎 ─────────────────────────────────────────────
@MainActor
final class SyncEngine: ObservableObject {
    enum Status: Equatable {
        case idle
        case syncing
        case success(Date)
        case failed(String)
    }

    @Published private(set) var status: Status = .idle

    private let store: EntryStore
    private let vault: VaultManager
    private let crypto = CryptoEngine.shared
    private var debounceTask: Task<Void, Never>?
    private var periodicTask: Task<Void, Never>?

    private static let jsonEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private static let jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(store: EntryStore, vault: VaultManager) {
        self.store = store
        self.vault = vault
        // 周期同步（解锁期间每 5 分钟）
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                await self?.syncIfEnabled()
            }
        }
    }

    deinit {
        debounceTask?.cancel()
        periodicTask?.cancel()
    }

    /// 数据变更后 3 秒防抖同步。
    func scheduleDebounced() {
        guard SyncSettings.enabled, SyncSettings.isConfigured else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await self?.syncIfEnabled()
        }
    }

    func syncIfEnabled() async {
        guard SyncSettings.enabled, SyncSettings.isConfigured else { return }
        await syncNow()
    }

    func syncNow() async {
        guard status != .syncing else { return }
        status = .syncing
        do {
            try await uploadVaultMetaIfNeeded()
            try await pull()
            try await push()
            status = .success(Date())
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    // ── 连接测试 ──────────────────────────────────────────
    static func testConnection(urlString: String, token: String) async -> Result<Void, Error> {
        var s = urlString.trimmingCharacters(in: .whitespaces)
        if !s.contains("://") { s = "http://" + s }
        if s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s + "/api/health") else {
            return .failure(SyncError.badURL)
        }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(SyncError.badURL)
            }
            switch http.statusCode {
            case 200: return .success(())
            case 401: return .failure(SyncError.unauthorized)
            default:  return .failure(SyncError.httpError(http.statusCode))
            }
        } catch {
            return .failure(error)
        }
    }

    // ── HTTP ─────────────────────────────────────────────
    private func request(_ path: String, method: String, body: Data?) async throws -> Data {
        guard SyncSettings.isConfigured else { throw SyncError.notConfigured }
        guard let base = SyncSettings.normalizedBaseURL() else { throw SyncError.badURL }
        var req = URLRequest(url: base.appendingPathComponent(path), timeoutInterval: 15)
        req.httpMethod = method
        req.httpBody = body
        req.setValue("Bearer \(SyncSettings.token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw SyncError.badURL }
        switch http.statusCode {
        case 200...299: return data
        case 401: throw SyncError.unauthorized
        default:  throw SyncError.httpError(http.statusCode)
        }
    }

    /// 上传 vault.json（KDF 盐 + 被主密码包裹的 VaultKey）—— Web 端解密需要。
    /// 内容本身不含任何可解密材料（零知识），幂等，每次同步都推。
    private func uploadVaultMetaIfNeeded() async throws {
        let metaData = try Data(contentsOf: vault.metaURL)
        _ = try await request("api/vault/meta", method: "PUT", body: metaData)
    }

    // ── Pull ─────────────────────────────────────────────
    private func pull() async throws {
        let lastSeq = Int(getMeta("sync.lastSeq") ?? "0") ?? 0
        let body = try Self.jsonEncoder.encode(PullRequest(since_seq: lastSeq))
        let data = try await request("api/sync/pull", method: "POST", body: body)
        let response = try Self.jsonDecoder.decode(PullResponse.self, from: data)

        for record in response.entries {
            try applyRemote(record)
        }
        setMeta("sync.lastSeq", String(response.latest_seq))
        store.reload()
    }

    private func applyRemote(_ record: SyncRecord) throws {
        let dbQueue = store.dbQueue
        let local = try dbQueue.read { db in
            try Entry.fetchOne(db, key: record.uuid)
        }

        // 本机专属条目：远端任何变更（包括墓碑）一律忽略
        if let local, local.localOnly { return }

        // 远端不比本地新 → 只更新同步水位
        if let local, record.version <= local.version {
            if record.version > local.syncedVersion {
                var updated = local
                updated.syncedVersion = record.version
                try dbQueue.write { db in try updated.update(db) }
            }
            return
        }

        // 本地有未推送的修改 → 先保留冲突副本（永不静默丢数据）
        if let local, local.version > local.syncedVersion {
            try makeConflictCopy(of: local)
        }

        let payload = try decryptPayload(record)
        var entry = Entry(
            uuid: record.uuid,
            type: CategoryStore.normalize(payload.type),
            title: payload.title,
            urlHost: payload.urlHost,
            tags: payload.tags,
            localOnly: false,
            favorite: payload.favorite,
            version: record.version,
            createdAt: payload.createdAt,
            updatedAt: payload.updatedAt,
            deletedAt: payload.deletedAt,
            secretBlob: payload.secretBlob,
            syncedVersion: record.version)
        if record.deleted && entry.deletedAt == nil {
            entry.deletedAt = Date()
        }
        try dbQueue.write { db in try entry.save(db) }
    }

    private func makeConflictCopy(of entry: Entry) throws {
        guard let key = vault.vaultKey else { throw VaultError.notUnlocked }
        // secretBlob 的 AAD 绑定 uuid，复制到新 uuid 必须重加密
        let plaintext = try crypto.open(
            blob: entry.secretBlob, key: key.bytes, aad: Data(entry.uuid.utf8))
        let newUUID = UUID().uuidString.lowercased()
        let newBlob = try crypto.seal(
            plaintext: plaintext, key: key.bytes, aad: Data(newUUID.utf8))

        var copy = entry
        copy.uuid = newUUID
        copy.title = entry.title + "（本机冲突副本）"
        copy.secretBlob = newBlob
        copy.version = 1
        copy.syncedVersion = 0
        copy.updatedAt = Date()
        try store.dbQueue.write { db in try copy.insert(db) }
    }

    // ── Push ─────────────────────────────────────────────
    private func push() async throws {
        let dbQueue = store.dbQueue
        let dirty = try await dbQueue.read { db in
            try Entry.fetchAll(db, sql: """
                SELECT * FROM entry
                WHERE version > syncedVersion
                  AND (localOnly = 0 OR syncedVersion > 0)
                """)
        }
        guard !dirty.isEmpty else { return }

        var records: [SyncRecord] = []
        for entry in dirty {
            // 曾同步过、后被标记"仅本机" → 推墓碑抹掉服务器上的痕迹
            let asTombstone = entry.localOnly || entry.deletedAt != nil
            records.append(SyncRecord(
                uuid: entry.uuid,
                version: entry.version,
                seq: nil,
                deleted: asTombstone,
                payload: try encryptPayload(for: entry, tombstone: entry.localOnly)))
        }

        let body = try Self.jsonEncoder.encode(PushRequest(entries: records))
        let data = try await request("api/sync/push", method: "POST", body: body)
        let response = try Self.jsonDecoder.decode(PushResponse.self, from: data)

        try await dbQueue.write { db in
            for accepted in response.accepted {
                try db.execute(
                    sql: "UPDATE entry SET syncedVersion = version WHERE uuid = ?",
                    arguments: [accepted.uuid])
            }
        }
        for conflict in response.conflicts {
            try applyRemote(conflict)
        }
        store.reload()
    }

    // ── 载荷加解密 ────────────────────────────────────────
    private func encryptPayload(for entry: Entry, tombstone: Bool) throws -> String {
        guard let key = vault.vaultKey else { throw VaultError.notUnlocked }
        let payload = SyncPayload(
            type: entry.type,
            title: tombstone ? "" : entry.title,
            urlHost: tombstone ? nil : entry.urlHost,
            tags: tombstone ? [] : entry.tags,
            favorite: entry.favorite,
            createdAt: entry.createdAt,
            updatedAt: entry.updatedAt,
            deletedAt: tombstone ? (entry.deletedAt ?? Date()) : entry.deletedAt,
            secretBlob: tombstone ? Data() : entry.secretBlob)
        let plain = try Self.jsonEncoder.encode(payload)
        let sealed = try crypto.seal(
            plaintext: plain, key: key.bytes, aad: Data("sync:\(entry.uuid)".utf8))
        return sealed.base64EncodedString()
    }

    private func decryptPayload(_ record: SyncRecord) throws -> SyncPayload {
        guard let key = vault.vaultKey else { throw VaultError.notUnlocked }
        guard let blob = Data(base64Encoded: record.payload) else {
            throw CryptoError.malformedBlob
        }
        let plain = try crypto.open(
            blob: blob, key: key.bytes, aad: Data("sync:\(record.uuid)".utf8))
        return try Self.jsonDecoder.decode(SyncPayload.self, from: plain)
    }

    // ── app_meta 键值 ─────────────────────────────────────
    private func getMeta(_ key: String) -> String? {
        try? store.dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM app_meta WHERE key = ?", arguments: [key])
        }
    }

    private func setMeta(_ key: String, _ value: String) {
        try? store.dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO app_meta(key, value) VALUES(?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """,
                arguments: [key, value])
        }
    }
}
