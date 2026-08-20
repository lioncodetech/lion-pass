import SwiftUI

@main struct LionPasswordApp: App {
    @StateObject private var vault = VaultService()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("autoLock") private var autoLock = AutoLockDuration.immediately.rawValue
    @State private var backgroundDate: Date?
    @State private var isObscured = false

    var body: some Scene {
        WindowGroup {
            ZStack { RootView().environmentObject(vault); if isObscured { PrivacyCoverView().transition(.opacity) } }
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
                .privacySensitive()
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { isObscured = true; backgroundDate = Date(); if AutoLockDuration(rawValue: autoLock) == .immediately { vault.lockVault() } }
                    if phase == .active { if let backgroundDate, Date().timeIntervalSince(backgroundDate) >= (AutoLockDuration(rawValue: autoLock)?.seconds ?? 0) { vault.lockVault() }; isObscured = false }
                }
        }
    }
}

struct PrivacyCoverView: View { var body: some View { ZStack { Color(.systemBackground).ignoresSafeArea(); VStack(spacing: 16) { LionMark(size: 72); Text("Lion Password").font(.title2.bold()); Label("Conteúdo protegido", systemImage: "lock.fill").foregroundStyle(.secondary) } } } }

struct RootView: View {
    @EnvironmentObject var vault: VaultService
    var body: some View { Group { if vault.isUnlocked { VaultHomeView() } else if vault.hasVault { UnlockView() } else { WelcomeView() } }.animation(.easeInOut, value: vault.isUnlocked) }
}
