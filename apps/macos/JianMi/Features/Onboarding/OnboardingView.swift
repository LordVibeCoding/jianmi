import SwiftUI

/// 首次启动：设置主密码 → 展示恢复码（仅此一次）。
struct OnboardingView: View {
    @EnvironmentObject private var app: AppState

    @State private var password = ""
    @State private var confirm = ""
    @State private var error: String?
    @State private var isWorking = false
    @State private var recoveryCode: String?
    @State private var codeConfirmed = false

    var body: some View {
        if let code = recoveryCode {
            recoveryView(code: code)
        } else {
            setupView
        }
    }

    // ── 第一步：设主密码 ──────────────────────────────────
    private var setupView: some View {
        VStack(spacing: 20) {
            AppBadge(size: 72)
            Text("欢迎使用简密")
                .font(.largeTitle.bold())
            Text("简单记录你的密码，但你的密码将会 100% 安全。\n请设置主密码 —— 它是打开一切的唯一钥匙，请务必牢记。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                SecureField("主密码（可留空，位数不限）", text: $password)
                SecureField("再次输入主密码", text: $confirm)
                if !password.isEmpty {
                    HStack {
                        Text("强度").font(.caption).foregroundStyle(.secondary)
                        PasswordStrengthBar(password: password)
                        Spacer()
                    }
                } else {
                    Label("不设主密码：任何能登录这台 Mac 的人都可打开密码库",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .textFieldStyle(.roundedBorder)
            .frame(width: 320)

            if let error {
                Text(error).foregroundStyle(.red).font(.callout)
            }

            Button {
                createVault()
            } label: {
                if isWorking {
                    ProgressView().controlSize(.small)
                } else {
                    Text("创建密码库").frame(width: 120)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking)
        }
        .padding(40)
    }

    private func createVault() {
        error = nil
        guard password == confirm else {
            error = "两次输入不一致"
            return
        }
        isWorking = true
        // Argon2id 计算约 0.5s，放后台避免卡 UI
        let pwd = password
        Task {
            do {
                let code = try app.completeSetup(masterPassword: pwd)
                recoveryCode = code
            } catch {
                self.error = error.localizedDescription
            }
            isWorking = false
        }
    }

    // ── 第二步：抄写恢复码 ────────────────────────────────
    private func recoveryView(code: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("请抄写恢复码")
                .font(.largeTitle.bold())
            Text("这是找回数据的唯一途径（简密没有任何后门）。\n请打印或抄写在纸上，存放到安全的地方。此码只显示这一次。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Text(code)
                .font(.system(.title3, design: .monospaced).bold())
                .textSelection(.enabled)
                .padding()
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            Toggle("我已妥善抄写并保存恢复码", isOn: $codeConfirmed)

            Button("开始使用简密") {
                recoveryCode = nil  // 界面随 app.state 切换到主窗口
            }
            .buttonStyle(.borderedProminent)
            .disabled(!codeConfirmed)
        }
        .padding(40)
    }
}
