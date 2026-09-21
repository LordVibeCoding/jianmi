import SwiftUI

struct UnlockView: View {
    @EnvironmentObject private var app: AppState

    @State private var password = ""
    @State private var error: String?
    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 20) {
            ZStack(alignment: .bottomTrailing) {
                AppBadge(size: 72)
                Image(systemName: "lock.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white, .orange)
                    .offset(x: 6, y: 6)
            }
            Text("简密已锁定")
                .font(.largeTitle.bold())

            SecureField("主密码", text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .onSubmit(unlock)

            if let error {
                Text(error).foregroundStyle(.red).font(.callout)
            }

            HStack(spacing: 12) {
                Button {
                    unlock()
                } label: {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("解锁").frame(width: 80)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking)

                if app.vault.biometricEnabled {
                    Button {
                        Task { await app.unlockWithBiometrics() }
                    } label: {
                        Label("触控 ID", systemImage: "touchid")
                    }
                }
            }
        }
        .padding(40)
        .onAppear {
            if app.vault.biometricEnabled {
                Task { await app.unlockWithBiometrics() }
            }
        }
    }

    private func unlock() {
        guard !isWorking else { return }
        error = nil
        isWorking = true
        let pwd = password
        Task {
            do {
                try app.unlock(masterPassword: pwd)
                password = ""
            } catch {
                self.error = error.localizedDescription
            }
            isWorking = false
        }
    }
}
