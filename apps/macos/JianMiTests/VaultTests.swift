import XCTest
@testable import JianMi

final class VaultTests: XCTestCase {
    var tempDir: URL!
    var vault: VaultManager!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("jianmi-test-\(UUID().uuidString)")
        vault = VaultManager(directoryURL: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testCreateUnlockLockCycle() throws {
        XCTAssertFalse(vault.vaultExists)

        let recovery = try vault.create(masterPassword: "正确的主密码123")
        XCTAssertTrue(vault.vaultExists)
        XCTAssertTrue(vault.isUnlocked)
        XCTAssertFalse(recovery.isEmpty)

        vault.lock()
        XCTAssertFalse(vault.isUnlocked)

        // 错误密码必须失败
        XCTAssertThrowsError(try vault.unlock(masterPassword: "错误密码")) { error in
            XCTAssertEqual(error as? VaultError, .wrongPassword)
        }
        XCTAssertFalse(vault.isUnlocked)

        // 正确密码解锁
        try vault.unlock(masterPassword: "正确的主密码123")
        XCTAssertTrue(vault.isUnlocked)
    }

    func testEmptyMasterPassword() throws {
        // 空主密码：允许创建与解锁，且错误密码仍须失败
        try vault.create(masterPassword: "")
        vault.lock()
        XCTAssertThrowsError(try vault.unlock(masterPassword: "不是空的"))
        try vault.unlock(masterPassword: "")
        XCTAssertTrue(vault.isUnlocked)
    }

    func testRecoveryCodeUnlock() throws {
        let recovery = try vault.create(masterPassword: "主密码abc")
        let keyBefore = vault.vaultKey!.bytes
        vault.lock()

        try vault.unlock(recoveryCode: recovery)
        XCTAssertEqual(vault.vaultKey!.bytes, keyBefore,
                       "恢复码解锁得到的 VaultKey 必须与原始一致")
    }

    func testChangeMasterPassword() throws {
        try vault.create(masterPassword: "旧密码12345")
        let keyBefore = vault.vaultKey!.bytes

        try vault.setMasterPassword("新密码67890")
        vault.lock()

        XCTAssertThrowsError(try vault.unlock(masterPassword: "旧密码12345"))
        try vault.unlock(masterPassword: "新密码67890")
        XCTAssertEqual(vault.vaultKey!.bytes, keyBefore,
                       "改主密码后 VaultKey 不变（无需重加密全库）")
    }

    func testEndToEndEntryStorage() throws {
        try vault.create(masterPassword: "主密码xyz789")

        let store = try awaitMainActor { try EntryStore(vault: self.vault) }

        var draft = EntryDraft()
        draft.title = "GitHub"
        draft.urlFull = "https://github.com/login"
        draft.username = "octocat"
        draft.password = "S3cret!P@ss"
        draft.notesMarkdown = "# 备注\n主账号"

        let entry = try awaitMainActor { try store.add(draft: draft) }
        XCTAssertEqual(entry.urlHost, "github.com")

        // 解密还原
        let body = try awaitMainActor { try store.decryptBody(of: entry) }
        XCTAssertEqual(body.username, "octocat")
        XCTAssertEqual(body.password, "S3cret!P@ss")

        // 磁盘上不可出现明文机密（验收标准：DESIGN.md §8 M1）
        let raw = try Data(contentsOf: vault.dbURL)
        XCTAssertNil(raw.range(of: Data("S3cret!P@ss".utf8)), "密码明文泄露到磁盘！")
        XCTAssertNil(raw.range(of: Data("octocat".utf8)), "账号明文泄露到磁盘！")

        // 钱包类型强制仅本机 + 链/私钥字段
        var walletDraft = EntryDraft()
        walletDraft.type = "wallet"
        walletDraft.title = "BTC 钱包"
        walletDraft.chain = "Bitcoin"
        walletDraft.privateKey = "L4rK3vqM...测试私钥"
        walletDraft.localOnly = false   // 即使用户没勾
        let wallet = try awaitMainActor { try store.add(draft: walletDraft) }
        XCTAssertTrue(wallet.localOnly, "钱包类条目必须强制 localOnly")
        let walletBody = try awaitMainActor { try store.decryptBody(of: wallet) }
        XCTAssertEqual(walletBody.chain, "Bitcoin")
        XCTAssertEqual(walletBody.privateKey, "L4rK3vqM...测试私钥")
        // 私钥不可以明文落盘
        let raw2 = try Data(contentsOf: vault.dbURL)
        XCTAssertNil(raw2.range(of: Data("L4rK3vqM".utf8)), "私钥明文泄露到磁盘！")
    }

    /// 在 MainActor 上同步执行（测试辅助）。
    private func awaitMainActor<T>(_ body: @MainActor @escaping () throws -> T) throws -> T {
        var result: Result<T, Error>!
        let exp = expectation(description: "main actor")
        Task { @MainActor in
            result = Result { try body() }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 10)
        return try result.get()
    }
}
