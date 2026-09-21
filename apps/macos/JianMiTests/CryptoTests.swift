import XCTest
@testable import JianMi

final class CryptoTests: XCTestCase {
    let crypto = CryptoEngine.shared

    // 测试用小参数 KDF（Argon2 64MB 全参数跑一次即可，其余用小参数提速）
    func fastKey(_ password: String, salt: [UInt8]) throws -> [UInt8] {
        try crypto.deriveKey(password: password, salt: salt,
                             opsLimit: 1, memLimit: 8 * 1024 * 1024)
    }

    func testKDFDeterministic() throws {
        let salt = try crypto.randomBytes(CryptoEngine.saltLength)
        let k1 = try fastKey("测试密码abc", salt: salt)
        let k2 = try fastKey("测试密码abc", salt: salt)
        XCTAssertEqual(k1, k2, "相同密码+盐必须派生相同密钥")
        XCTAssertEqual(k1.count, CryptoEngine.keyLength)

        let salt2 = try crypto.randomBytes(CryptoEngine.saltLength)
        let k3 = try fastKey("测试密码abc", salt: salt2)
        XCTAssertNotEqual(k1, k3, "不同盐必须派生不同密钥")

        let k4 = try fastKey("测试密码abd", salt: salt)
        XCTAssertNotEqual(k1, k4, "不同密码必须派生不同密钥")
    }

    func testKDFProductionParams() throws {
        // 生产参数完整跑一遍（64MB / ops 3），确认可用且耗时可接受
        let salt = try crypto.randomBytes(CryptoEngine.saltLength)
        let start = Date()
        let key = try crypto.deriveKey(password: "生产参数测试", salt: salt)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(key.count, 32)
        XCTAssertLessThan(elapsed, 5.0, "KDF 耗时超过 5 秒，参数需要调整")
    }

    func testSealOpenRoundtrip() throws {
        let key = try crypto.randomBytes(32)
        let plain = Data("机密数据 🔐 secret".utf8)
        let aad = Data("entry-uuid-123".utf8)

        let blob = try crypto.seal(plaintext: plain, key: key, aad: aad)
        XCTAssertEqual(Array(blob.prefix(2)), CryptoEngine.magic)

        let opened = try crypto.open(blob: blob, key: key, aad: aad)
        XCTAssertEqual(opened, plain)
    }

    func testOpenFailsWithWrongKey() throws {
        let key = try crypto.randomBytes(32)
        let wrongKey = try crypto.randomBytes(32)
        let blob = try crypto.seal(plaintext: Data("x".utf8), key: key)
        XCTAssertThrowsError(try crypto.open(blob: blob, key: wrongKey))
    }

    func testOpenFailsWithWrongAAD() throws {
        let key = try crypto.randomBytes(32)
        let blob = try crypto.seal(
            plaintext: Data("x".utf8), key: key, aad: Data("uuid-A".utf8))
        XCTAssertThrowsError(
            try crypto.open(blob: blob, key: key, aad: Data("uuid-B".utf8)),
            "AAD 不匹配必须解密失败（防密文调包）")
    }

    func testOpenFailsWhenTampered() throws {
        let key = try crypto.randomBytes(32)
        var blob = try crypto.seal(plaintext: Data("重要数据".utf8), key: key)
        blob[blob.count - 1] ^= 0xFF   // 篡改最后一个字节
        XCTAssertThrowsError(try crypto.open(blob: blob, key: key))
    }

    func testNonceUniqueness() throws {
        let key = try crypto.randomBytes(32)
        let plain = Data("同样的明文".utf8)
        let b1 = try crypto.seal(plaintext: plain, key: key)
        let b2 = try crypto.seal(plaintext: plain, key: key)
        XCTAssertNotEqual(b1, b2, "相同明文两次加密必须产生不同密文（随机 nonce）")
    }

    func testRecoveryCodeRoundtrip() throws {
        let key = try crypto.randomBytes(32)
        let code = RecoveryCode.encode(key)
        XCTAssertEqual(RecoveryCode.decode(code), key)
        // 容错：小写、去分隔符、加空格
        XCTAssertEqual(RecoveryCode.decode(code.lowercased()), key)
        XCTAssertEqual(RecoveryCode.decode(code.replacingOccurrences(of: "-", with: " ")), key)
        // 无效输入
        XCTAssertNil(RecoveryCode.decode("太短"))
        XCTAssertNil(RecoveryCode.decode(String(repeating: "Z", count: 64)))
    }

    func testPasswordGenerator() {
        var opts = PasswordGenerator.Options()
        opts.length = 24
        let p = PasswordGenerator.generate(opts)
        XCTAssertEqual(p.count, 24)
        XCTAssertTrue(p.contains(where: { $0.isUppercase }))
        XCTAssertTrue(p.contains(where: { $0.isLowercase }))
        XCTAssertTrue(p.contains(where: { $0.isNumber }))
        // 唯一性冒烟测试
        XCTAssertNotEqual(PasswordGenerator.generate(opts), PasswordGenerator.generate(opts))
    }
}
