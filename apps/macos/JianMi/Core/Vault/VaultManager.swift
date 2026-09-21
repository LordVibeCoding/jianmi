import Foundation
import LocalAuthentication

enum VaultError: Error, LocalizedError {
    case vaultAlreadyExists
    case vaultNotFound
    case wrongPassword
    case invalidRecoveryCode
    case notUnlocked
    case biometricUnavailable
    case biometricNotEnrolled

    var errorDescription: String? {
        switch self {
        case .vaultAlreadyExists:   return "密码库已存在"
        case .vaultNotFound:        return "未找到密码库"
        case .wrongPassword:        return "主密码错误"
        case .invalidRecoveryCode:  return "恢复码无效"
        case .notUnlocked:          return "密码库未解锁"
        case .biometricUnavailable: return "触控 ID 不可用"
        case .biometricNotEnrolled: return "尚未启用触控 ID 解锁"
        }
    }
}

/// 密码库生命周期管理：创建 / 解锁 / 锁定 / 改主密码 / Touch ID。
///
/// 磁盘布局（~/Library/Application Support/JianMi/）：
///   vault.json    元数据：KDF 盐与参数、被 MasterKey 加密的 VaultKey
///   jianmi.sqlite 条目库（字段级加密，见 EntryStore）
final class VaultManager {

    struct Meta: Codable {
        var formatVersion: Int
        var kdfSalt: Data
        var kdfOpsLimit: Int
        var kdfMemLimit: Int
        var wrappedVaultKey: Data       // seal(VaultKey, key: MasterKey)
        var createdAt: Date
        var biometricEnabled: Bool
    }

    let directoryURL: URL
    var metaURL: URL { directoryURL.appendingPathComponent("vault.json") }
    var dbURL: URL { directoryURL.appendingPathComponent("jianmi.sqlite") }

    /// 解锁后的 VaultKey，仅存内存；锁定时立即 memzero。
    private(set) var vaultKey: SecureBytes?

    private let crypto = CryptoEngine.shared
    private static let wrapAAD = Data("jianmi.vaultkey.v1".utf8)

    init(directoryURL: URL? = nil) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directoryURL = appSupport.appendingPathComponent("JianMi", isDirectory: true)
        }
    }

    var vaultExists: Bool { FileManager.default.fileExists(atPath: metaURL.path) }
    var isUnlocked: Bool { vaultKey != nil }

    private func loadMeta() throws -> Meta {
        guard vaultExists else { throw VaultError.vaultNotFound }
        let data = try Data(contentsOf: metaURL)
        return try JSONDecoder().decode(Meta.self, from: data)
    }

    private func saveMeta(_ meta: Meta) throws {
        try FileManager.default.createDirectory(
            at: directoryURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(meta)
        // vault.json 只含密文（盐 + 被主密码包裹的 VaultKey），磁盘加密交给 FileVault
        try data.write(to: metaURL, options: [.atomic])
    }

    // ── 创建密码库 ────────────────────────────────────────
    /// 返回恢复码（只此一次，务必让用户抄写）。
    @discardableResult
    func create(masterPassword: String) throws -> String {
        guard !vaultExists else { throw VaultError.vaultAlreadyExists }

        let salt = try crypto.randomBytes(CryptoEngine.saltLength)
        var masterKey = try crypto.deriveKey(password: masterPassword, salt: salt)
        defer { crypto.zero(&masterKey) }

        let rawVaultKey = try crypto.randomBytes(CryptoEngine.keyLength)
        let wrapped = try crypto.seal(
            plaintext: Data(rawVaultKey), key: masterKey, aad: Self.wrapAAD)

        let meta = Meta(
            formatVersion: 1,
            kdfSalt: Data(salt),
            kdfOpsLimit: CryptoEngine.kdfOpsLimit,
            kdfMemLimit: CryptoEngine.kdfMemLimit,
            wrappedVaultKey: wrapped,
            createdAt: Date(),
            biometricEnabled: false)
        try saveMeta(meta)

        vaultKey = SecureBytes(rawVaultKey)
        return RecoveryCode.encode(rawVaultKey)
    }

    // ── 解锁 ──────────────────────────────────────────────
    func unlock(masterPassword: String) throws {
        let meta = try loadMeta()
        var masterKey = try crypto.deriveKey(
            password: masterPassword, salt: Array(meta.kdfSalt),
            opsLimit: meta.kdfOpsLimit, memLimit: meta.kdfMemLimit)
        defer { crypto.zero(&masterKey) }

        do {
            let raw = try crypto.open(
                blob: meta.wrappedVaultKey, key: masterKey, aad: Self.wrapAAD)
            vaultKey = SecureBytes(Array(raw))
        } catch {
            throw VaultError.wrongPassword
        }
    }

    /// 恢复码 = VaultKey 本身：验证其能否解开任一条目由上层完成；
    /// 这里校验格式后直接采用，并强制用户随后设置新主密码。
    func unlock(recoveryCode: String) throws {
        guard vaultExists else { throw VaultError.vaultNotFound }
        guard let raw = RecoveryCode.decode(recoveryCode) else {
            throw VaultError.invalidRecoveryCode
        }
        vaultKey = SecureBytes(raw)
    }

    /// 改主密码：只需用新 MasterKey 重新包裹 VaultKey（1 条记录，不重加密全库）。
    func setMasterPassword(_ newPassword: String) throws {
        guard let key = vaultKey else { throw VaultError.notUnlocked }
        var meta = try loadMeta()

        let salt = try crypto.randomBytes(CryptoEngine.saltLength)
        var masterKey = try crypto.deriveKey(password: newPassword, salt: salt)
        defer { crypto.zero(&masterKey) }

        meta.kdfSalt = Data(salt)
        meta.wrappedVaultKey = try crypto.seal(
            plaintext: Data(key.bytes), key: masterKey, aad: Self.wrapAAD)
        try saveMeta(meta)
    }

    // ── 锁定 ──────────────────────────────────────────────
    func lock() {
        vaultKey?.destroy()
        vaultKey = nil
    }

    // ── Touch ID 便捷解锁 ─────────────────────────────────
    // 无开发者账号 → 无法用数据保护钥匙串 + Secure Enclave ACL，
    // 折衷：VaultKey 存文件钥匙串（本机、本用户），取用前强制 LAContext 生物认证。
    private static let keychainService = "com.jianmi.mac"
    private static let keychainAccount = "vaultKey"

    var biometricEnabled: Bool { (try? loadMeta())?.biometricEnabled ?? false }

    func enableBiometric() throws {
        guard let key = vaultKey else { throw VaultError.notUnlocked }
        try KeychainHelper.save(
            Data(key.bytes), service: Self.keychainService, account: Self.keychainAccount)
        var meta = try loadMeta()
        meta.biometricEnabled = true
        try saveMeta(meta)
    }

    func disableBiometric() throws {
        KeychainHelper.delete(service: Self.keychainService, account: Self.keychainAccount)
        var meta = try loadMeta()
        meta.biometricEnabled = false
        try saveMeta(meta)
    }

    @MainActor
    func unlockWithBiometrics() async throws {
        guard biometricEnabled else { throw VaultError.biometricNotEnrolled }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw VaultError.biometricUnavailable
        }
        let ok = try await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "解锁简密密码库")
        guard ok, let data = KeychainHelper.load(
            service: Self.keychainService, account: Self.keychainAccount) else {
            throw VaultError.biometricUnavailable
        }
        vaultKey = SecureBytes(Array(data))
    }
}
