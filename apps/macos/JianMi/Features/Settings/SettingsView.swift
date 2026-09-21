import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("通用", systemImage: "gearshape") }
            HotkeySettings()
                .tabItem { Label("快捷键", systemImage: "keyboard") }
            SecuritySettings()
                .tabItem { Label("安全", systemImage: "lock.shield") }
            SyncSettingsView()
                .tabItem { Label("同步", systemImage: "arrow.triangle.2.circlepath") }
            AboutSettings()
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 480)
    }
}

// ── 通用 ─────────────────────────────────────────────────
struct GeneralSettings: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("autoLockMinutes") private var autoLockMinutes = 15

    var body: some View {
        Form {
            Toggle("登录时启动简密", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    do {
                        if on { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }

            Picker("空闲自动锁定", selection: $autoLockMinutes) {
                Text("1 分钟").tag(1)
                Text("5 分钟").tag(5)
                Text("15 分钟").tag(15)
                Text("1 小时").tag(60)
                Text("从不").tag(0)
            }
            Text("锁屏与系统睡眠时始终立即锁定。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}

// ── 快捷键 ───────────────────────────────────────────────
struct HotkeySettings: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("快速捕获（新建条目）", name: .quickCapture)
            KeyboardShortcuts.Recorder("快速搜索", name: .quickSearch)
            Text("在任何 App 中按下快捷键即可唤起简密浮窗。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}

// ── 安全 ─────────────────────────────────────────────────
struct SecuritySettings: View {
    @EnvironmentObject private var app: AppState
    @State private var biometricOn = false
    @State private var showChangePassword = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Toggle("触控 ID 解锁", isOn: $biometricOn)
                    .disabled(app.state != .unlocked)
                    .onChange(of: biometricOn) { _, on in
                        guard app.state == .unlocked else { return }
                        do {
                            if on { try app.vault.enableBiometric() }
                            else { try app.vault.disableBiometric() }
                            message = nil
                        } catch {
                            message = error.localizedDescription
                            biometricOn = app.vault.biometricEnabled
                        }
                    }
                if app.state != .unlocked {
                    Text("解锁后才能修改安全设置。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                Button("修改主密码…") { showChangePassword = true }
                    .disabled(app.state != .unlocked)
                Button("在访达中显示数据文件") {
                    NSWorkspace.shared.activateFileViewerSelecting([app.vault.directoryURL])
                }
            }

            if let message {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .onAppear { biometricOn = app.vault.biometricEnabled }
        .sheet(isPresented: $showChangePassword) {
            ChangePasswordSheet()
        }
    }
}

struct ChangePasswordSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var current = ""
    @State private var newPassword = ""
    @State private var confirm = ""
    @State private var error: String?
    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 16) {
            Text("修改主密码").font(.headline)
            VStack(spacing: 10) {
                SecureField("当前主密码", text: $current)
                SecureField("新主密码（至少 8 位）", text: $newPassword)
                SecureField("再次输入新主密码", text: $confirm)
            }
            .textFieldStyle(.roundedBorder)

            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    change()
                } label: {
                    if isWorking { ProgressView().controlSize(.small) }
                    else { Text("确认修改") }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isWorking || current.isEmpty || newPassword.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 340)
    }

    private func change() {
        error = nil
        guard newPassword.count >= 8 else { error = "新密码至少 8 位"; return }
        guard newPassword == confirm else { error = "两次输入不一致"; return }
        isWorking = true
        Task {
            do {
                // 验证当前密码（用独立实例避免干扰已解锁状态）
                let verifier = VaultManager(directoryURL: app.vault.directoryURL)
                try verifier.unlock(masterPassword: current)
                verifier.lock()

                try app.vault.setMasterPassword(newPassword)
                await app.sync?.syncIfEnabled()   // 重新上传 vault 元数据
                dismiss()
            } catch {
                self.error = "当前主密码错误"
            }
            isWorking = false
        }
    }
}

// ── 同步 ─────────────────────────────────────────────────
struct SyncSettingsView: View {
    @EnvironmentObject private var app: AppState

    @State private var serverURL = SyncSettings.serverURL
    @State private var token = SyncSettings.token
    @State private var enabled = SyncSettings.enabled
    @State private var testResult: String?
    @State private var testOK = false
    @State private var isTesting = false

    var body: some View {
        Form {
            Section("自托管服务器") {
                TextField("服务器地址", text: $serverURL,
                          prompt: Text("192.168.1.100:8787 或 https://vault.example.com"))
                    .autocorrectionDisabled()
                SecureField("访问令牌", text: $token,
                            prompt: Text("服务器首次启动时生成"))

                HStack {
                    Button {
                        test()
                    } label: {
                        if isTesting { ProgressView().controlSize(.small) }
                        else { Text("测试连接") }
                    }
                    .disabled(serverURL.isEmpty || token.isEmpty || isTesting)

                    if let testResult {
                        Label(testResult, systemImage: testOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(testOK ? .green : .red)
                    }
                    Spacer()
                    Button("保存配置") { saveConfig() }
                        .disabled(serverURL == SyncSettings.serverURL && token == SyncSettings.token)
                }
            }

            Section {
                Toggle("启用自动同步", isOn: $enabled)
                    .onChange(of: enabled) { _, on in SyncSettings.enabled = on }

                HStack {
                    Button("立即同步") {
                        Task { await app.sync?.syncNow() }
                    }
                    .disabled(app.state != .unlocked || !SyncSettings.isConfigured)
                    Spacer()
                    if let sync = app.sync {
                        SyncStatusLabel(sync: sync)
                    }
                }

                Text("零知识架构：服务器上只有密文，标记「仅本机」的条目永不上传。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }

    private func saveConfig() {
        SyncSettings.serverURL = serverURL.trimmingCharacters(in: .whitespaces)
        SyncSettings.token = token.trimmingCharacters(in: .whitespaces)
        testResult = "配置已保存"
        testOK = true
    }

    private func test() {
        isTesting = true
        testResult = nil
        Task {
            let result = await SyncEngine.testConnection(
                urlString: serverURL.trimmingCharacters(in: .whitespaces),
                token: token.trimmingCharacters(in: .whitespaces))
            switch result {
            case .success:
                testResult = "连接成功"
                testOK = true
                saveConfig()
            case .failure(let err):
                testResult = err.localizedDescription
                testOK = false
            }
            isTesting = false
        }
    }
}

struct SyncStatusLabel: View {
    @ObservedObject var sync: SyncEngine

    var body: some View {
        switch sync.status {
        case .idle:
            Label("等待同步", systemImage: "cloud")
                .font(.caption).foregroundStyle(.secondary)
        case .syncing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("同步中…").font(.caption).foregroundStyle(.secondary)
            }
        case .success(let date):
            Label("已同步 \(date.formatted(date: .omitted, time: .shortened))",
                  systemImage: "checkmark.icloud")
                .font(.caption).foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.icloud")
                .font(.caption).foregroundStyle(.red).lineLimit(1)
        }
    }
}

// ── 关于 ─────────────────────────────────────────────────
struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 14) {
            AppBadge(size: 64)
            Text("简密").font(.title.bold())
            Text("简单记录你的密码，但你的密码将会 100% 安全。")
                .font(.callout).foregroundStyle(.secondary)
            Text("版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                .font(.caption).foregroundStyle(.tertiary)
            Divider().frame(width: 200)
            VStack(spacing: 4) {
                Text("零知识加密 · Argon2id + XChaCha20-Poly1305")
                Text("自托管同步 · 本地优先 · 无任何遥测")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(30)
    }
}
