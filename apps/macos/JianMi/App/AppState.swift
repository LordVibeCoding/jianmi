import AppKit
import Foundation

/// 全局应用状态机：未建库 → 已锁定 ⇄ 已解锁。
/// 自动锁定：屏幕锁定 / 系统睡眠 → 立即清内存密钥。
@MainActor
final class AppState: ObservableObject {
    enum VaultState { case needsSetup, locked, unlocked }

    @Published private(set) var state: VaultState
    @Published var lastError: String?

    let vault: VaultManager
    private(set) var store: EntryStore?

    init(vault: VaultManager = VaultManager()) {
        self.vault = vault
        self.state = vault.vaultExists ? .locked : .needsSetup
        registerAutoLock()
    }

    // ── 生命周期 ──────────────────────────────────────────
    /// 创建密码库，返回恢复码（仅展示一次）。
    func completeSetup(masterPassword: String) throws -> String {
        let recoveryCode = try vault.create(masterPassword: masterPassword)
        store = try EntryStore(vault: vault)
        state = .unlocked
        return recoveryCode
    }

    func unlock(masterPassword: String) throws {
        try vault.unlock(masterPassword: masterPassword)
        store = try EntryStore(vault: vault)
        state = .unlocked
    }

    func unlockWithBiometrics() async {
        do {
            try await vault.unlockWithBiometrics()
            store = try EntryStore(vault: vault)
            state = .unlocked
        } catch {
            lastError = error.localizedDescription
        }
    }

    func lock() {
        store = nil
        vault.lock()
        if state == .unlocked { state = .locked }
    }

    // ── 自动锁定 ──────────────────────────────────────────
    private func registerAutoLock() {
        // 屏幕锁定
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.lock() }
        }
        // 系统睡眠
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.lock() }
        }
    }
}
