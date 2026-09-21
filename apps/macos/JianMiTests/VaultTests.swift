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

        // 多账号：往返 + 磁盘无明文
        var multiDraft = EntryDraft.from(entry: entry, body: body)
        multiDraft.extraAccounts = [
            .init(label: "小号", username: "alt@example.com", password: "AltP@ss999"),
            .init(label: "", username: "third", password: ""),
        ]
        try awaitMainActor { try store.update(entry, with: multiDraft) }
        let updated = try awaitMainActor { self.requireEntry(store, uuid: entry.uuid) }
        let multiBody = try awaitMainActor { try store.decryptBody(of: updated) }
        XCTAssertEqual(multiBody.extraAccounts?.count, 2)
        XCTAssertEqual(multiBody.extraAccounts?[0].username, "alt@example.com")
        XCTAssertEqual(multiBody.extraAccounts?[0].password, "AltP@ss999")
        let rawMulti = try Data(contentsOf: vault.dbURL)
        XCTAssertNil(rawMulti.range(of: Data("AltP@ss999".utf8)), "额外账号密码明文泄露！")

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

    func testSSHCommand() {
        var body = SecretBody()
        XCTAssertNil(body.sshCommand, "无主机时不生成命令")

        body.host = "192.168.1.100"
        XCTAssertEqual(body.sshCommand, "ssh 192.168.1.100")

        body.username = "root"
        XCTAssertEqual(body.sshCommand, "ssh root@192.168.1.100")

        body.port = "22"
        XCTAssertEqual(body.sshCommand, "ssh root@192.168.1.100", "默认端口不加 -p")

        body.port = "2222"
        XCTAssertEqual(body.sshCommand, "ssh -p 2222 root@192.168.1.100")

        body.sshKeyPath = "~/.ssh/id_rsa"
        XCTAssertEqual(body.sshCommand, "ssh -i ~/.ssh/id_rsa -p 2222 root@192.168.1.100")
    }

    func testExport() throws {
        try vault.create(masterPassword: "导出测试密码")
        let store = try awaitMainActor { try EntryStore(vault: self.vault) }

        var login = EntryDraft()
        login.title = "GitHub"
        login.username = "octocat"
        login.password = "S3cret!"
        login.urlFull = "https://github.com"
        _ = try awaitMainActor { try store.add(draft: login) }

        var note = EntryDraft()
        note.type = "note"
        note.title = "测试笔记"
        note.notesMarkdown = "正文内容\n第二行"
        _ = try awaitMainActor { try store.add(draft: note) }

        // JSON：字段完整、可解析
        let data = try awaitMainActor {
            try Exporter.json(entries: store.allEntries(categoryID: nil), store: store)
        }
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(root["count"] as? Int, 2)
        let items = root["entries"] as! [[String: Any]]
        let github = items.first { $0["title"] as? String == "GitHub" }!
        XCTAssertEqual(github["password"] as? String, "S3cret!")
        XCTAssertEqual(github["username"] as? String, "octocat")

        // 单分类范围
        let onlyNotes = try awaitMainActor { store.allEntries(categoryID: "note") }
        XCTAssertEqual(onlyNotes.count, 1)

        // Markdown：笔记导出可与导入往返（# 标题 + 正文）
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("jianmi-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try awaitMainActor {
            try Exporter.markdownFiles(entries: onlyNotes, store: store, to: tempDir)
        }
        let noteFile = tempDir.appendingPathComponent("测试笔记.md")
        let content = try String(contentsOf: noteFile, encoding: .utf8)
        XCTAssertTrue(content.hasPrefix("# 测试笔记"))
        XCTAssertTrue(content.contains("正文内容\n第二行"))
    }

    @MainActor
    private func requireEntry(_ store: EntryStore, uuid: String) -> Entry {
        store.entry(uuid: uuid)!
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
