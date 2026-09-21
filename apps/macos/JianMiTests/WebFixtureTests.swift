import XCTest
@testable import JianMi

/// 跨语言兼容性夹具：导出 Swift 加密的真实数据，供 Node/浏览器端 JS 验证解密。
/// 运行后生成 /tmp/jianmi-web-fixture.json，由 scripts/verify_web_crypto.mjs 校验。
final class WebFixtureTests: XCTestCase {
    func testExportWebFixture() throws {
        let crypto = CryptoEngine.shared
        let password = "网页测试密码2024!"

        // 1. 模拟 vault.json：小参数 KDF（node 端同参数验证）
        let salt = try crypto.randomBytes(CryptoEngine.saltLength)
        let ops = 2
        let mem = 16 * 1024 * 1024
        var masterKey = try crypto.deriveKey(password: password, salt: salt,
                                             opsLimit: ops, memLimit: mem)
        defer { crypto.zero(&masterKey) }
        let vaultKey = try crypto.randomBytes(32)
        let wrapped = try crypto.seal(
            plaintext: Data(vaultKey), key: masterKey,
            aad: Data("jianmi.vaultkey.v1".utf8))

        // 2. 模拟同步载荷：SecretBody → secretBlob(AAD=uuid) → SyncPayload(AAD=sync:uuid)
        let uuid = "fixture-uuid-0001"
        var body = SecretBody()
        body.username = "测试账号@example.com"
        body.password = "P@ssw0rd-网页验证"
        body.urlFull = "https://github.com/login"

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let secretBlob = try crypto.seal(
            plaintext: try encoder.encode(body),
            key: vaultKey, aad: Data(uuid.utf8))

        let payload = SyncPayload(
            type: .website, title: "GitHub", urlHost: "github.com",
            tags: ["测试"], favorite: true,
            createdAt: Date(), updatedAt: Date(), deletedAt: nil,
            secretBlob: secretBlob)
        let payloadBlob = try crypto.seal(
            plaintext: try encoder.encode(payload),
            key: vaultKey, aad: Data("sync:\(uuid)".utf8))

        // 3. 导出夹具
        let fixture: [String: Any] = [
            "password": password,
            "kdfSalt": Data(salt).base64EncodedString(),
            "kdfOpsLimit": ops,
            "kdfMemLimit": mem,
            "wrappedVaultKey": wrapped.base64EncodedString(),
            "uuid": uuid,
            "payload": payloadBlob.base64EncodedString(),
            "expected": [
                "title": "GitHub",
                "username": body.username,
                "password": body.password,
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: fixture, options: .prettyPrinted)
        try data.write(to: URL(fileURLWithPath: "/tmp/jianmi-web-fixture.json"))
    }
}
