import AppKit
import Foundation

/// 全局应用状态机：未建库 → 已锁定 ⇄ 已解锁。
/// 自动锁定：屏幕锁定 / 系统睡眠 → 立即清内存密钥。
@MainActor
final class AppState: ObservableObject {
    enum VaultState { case needsSetup, locked, unlocked }

    static let shared = AppState()

    @Published private(set) var state: VaultState
    @Published var lastError: String?

    let vault: VaultManager
    private(set) var store: EntryStore?
    private(set) var sync: SyncEngine?

    init(vault: VaultManager = VaultManager()) {
        self.vault = vault
        self.state = vault.vaultExists ? .locked : .needsSetup
        registerAutoLock()
    }

    private func attachStore() throws {
        let store = try EntryStore(vault: vault)
        let sync = SyncEngine(store: store, vault: vault)
        store.onChange = { [weak sync] in sync?.scheduleDebounced() }
        self.store = store
        self.sync = sync
        state = .unlocked
        Task { await sync.syncIfEnabled() }   // 解锁后自动同步
    }

    // ── 生命周期 ──────────────────────────────────────────
    /// 创建密码库，返回恢复码（仅展示一次）。
    func completeSetup(masterPassword: String) throws -> String {
        let recoveryCode = try vault.create(masterPassword: masterPassword)
        try attachStore()
        return recoveryCode
    }

    func unlock(masterPassword: String) throws {
        try vault.unlock(masterPassword: masterPassword)
        try attachStore()
    }

    func unlockWithBiometrics() async {
        do {
            try await vault.unlockWithBiometrics()
            try attachStore()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func lock() {
        store = nil
        sync = nil
        vault.lock()
        if state == .unlocked { state = .locked }
        PinnedPanelManager.shared.closeAll()
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
