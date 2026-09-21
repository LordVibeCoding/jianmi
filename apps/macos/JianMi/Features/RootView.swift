import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        content
            .onAppear { AppDelegate.showInDock() }
    }

    @ViewBuilder
    private var content: some View {
        switch app.state {
        case .needsSetup:
            OnboardingView()
        case .locked:
            UnlockView()
        case .unlocked:
            if let store = app.store {
                MainView(store: store)
            } else {
                ProgressView()
            }
        }
    }
}
