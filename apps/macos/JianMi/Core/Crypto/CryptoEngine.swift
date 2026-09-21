import Foundation
import Sodium

/// 加密引擎 —— 简密的安全核心。
///
/// 架构（见 docs/DESIGN.md §2）：
///   主密码 --Argon2id--> MasterKey --解密--> VaultKey --XChaCha20-Poly1305--> 条目密文
///
/// 密文格式（版本化，为算法升级留门）：
///   blob = magic("JM", 2B) | fmtVer(1B) | nonce(24B) + ciphertext + tag(16B)
enum CryptoError: Error, LocalizedError {
    case kdfFailed
    case sealFailed
    case openFailed          // 密钥错误或数据被篡改
    case malformedBlob
    case randomFailed

    var errorDescription: String? {
        switch self {
        case .kdfFailed:     return "密钥派生失败"
        case .sealFailed:    return "加密失败"
        case .openFailed:    return "解密失败：密码错误或数据已损坏"
        case .malformedBlob: return "密文格式无效"
        case .randomFailed:  return "随机数生成失败"
        }
    }
}

struct CryptoEngine {
    static let shared = CryptoEngine()

    private let sodium = Sodium()

    // ── 常量 ──────────────────────────────────────────────
    static let magic: [UInt8] = [0x4A, 0x4D]   // "JM"
    static let formatVersion: UInt8 = 1
    static let keyLength = 32                   // 256-bit
    static let saltLength = 16                  // Argon2 盐
    /// Argon2id 参数：目标解锁耗时 ~500ms（M 系列芯片）
    static let kdfOpsLimit = 3
    static let kdfMemLimit = 64 * 1024 * 1024   // 64 MB

    // ── 随机数 ────────────────────────────────────────────
    func randomBytes(_ count: Int) throws -> [UInt8] {
        guard let bytes = sodium.randomBytes.buf(length: count) else {
            throw CryptoError.randomFailed
        }
        return bytes
    }

    // ── KDF：主密码 → MasterKey ───────────────────────────
    func deriveKey(password: String, salt: [UInt8],
                   opsLimit: Int = CryptoEngine.kdfOpsLimit,
                   memLimit: Int = CryptoEngine.kdfMemLimit) throws -> [UInt8] {
        guard let key = sodium.pwHash.hash(
            outputLength: Self.keyLength,
            passwd: Array(password.utf8),
            salt: salt,
            opsLimit: opsLimit,
            memLimit: memLimit,
            alg: .Argon2ID13
        ) else { throw CryptoError.kdfFailed }
        return key
    }

    // ── AEAD 加密（XChaCha20-Poly1305）────────────────────
    /// aad（附加认证数据）不加密但参与认证 —— 用条目 uuid 防"密文调包"。
    func seal(plaintext: Data, key: [UInt8], aad: Data? = nil) throws -> Data {
        guard let combined: Bytes = sodium.aead.xchacha20poly1305ietf.encrypt(
            message: Array(plaintext),
            secretKey: key,
            additionalData: aad.map(Array.init)
        ) else { throw CryptoError.sealFailed }

        var blob = Data(Self.magic)
        blob.append(Self.formatVersion)
        blob.append(contentsOf: combined)   // nonce(24B) + ct + tag
        return blob
    }

    func open(blob: Data, key: [UInt8], aad: Data? = nil) throws -> Data {
        let headerLen = Self.magic.count + 1
        guard blob.count > headerLen,
              Array(blob.prefix(2)) == Self.magic,
              blob[blob.startIndex + 2] == Self.formatVersion else {
            throw CryptoError.malformedBlob
        }
        let combined = Array(blob.dropFirst(headerLen))
        guard let plain = sodium.aead.xchacha20poly1305ietf.decrypt(
            nonceAndAuthenticatedCipherText: combined,
            secretKey: key,
            additionalData: aad.map(Array.init)
        ) else { throw CryptoError.openFailed }
        return Data(plain)
    }

    // ── 内存卫生 ──────────────────────────────────────────
    func zero(_ bytes: inout [UInt8]) {
        sodium.utils.zero(&bytes)
    }
}

/// 持有敏感字节的容器：析构时自动清零（libsodium memzero，不会被编译器优化掉）。
final class SecureBytes {
    private(set) var bytes: [UInt8]

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    /// 手动销毁（锁定密码库时调用，不等 ARC）
    func destroy() {
        CryptoEngine.shared.zero(&bytes)
        bytes = []
    }

    deinit { destroy() }
}
