import SwiftUI
import UIKit

@main
struct LionPassApp: App {
    @StateObject private var vault = VaultService()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(LionPreferenceKey.language) private var language = "pt-BR"
    @AppStorage(LionPreferenceKey.appearance) private var appearance = "system"
    @AppStorage(LionPreferenceKey.autoLock) private var autoLock = AutoLockDuration.immediately.rawValue
    @AppStorage(LionPreferenceKey.privacyCover) private var privacyCover = true
    @State private var backgroundDate: Date?
    @State private var isObscured = false
    @State private var screenIsCaptured = UIScreen.main.isCaptured

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView().environmentObject(vault).tint(.lionAccent)
                if isObscured || screenIsCaptured {
                    PrivacyCoverView(screenCapture: screenIsCaptured).transition(.opacity)
                }
            }
            .environment(\.locale, Locale(identifier: language))
            .preferredColorScheme(
                appearance == "dark" ? .dark : appearance == "light" ? .light : nil
            )
            .privacySensitive()
            .onChange(of: scenePhase) { _, phase in handle(phase) }
            .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
                screenIsCaptured = UIScreen.main.isCaptured
            }
            .sheet(isPresented: Binding(
                get: { vault.pendingRecoveryKey != nil },
                set: { if !$0 { vault.acknowledgeRecoveryKey() } }
            )) {
                if let recoveryKey = vault.pendingRecoveryKey {
                    RecoveryKeySheet(recoveryKey: recoveryKey).environmentObject(vault)
                }
            }
        }
    }

    private func handle(_ phase: ScenePhase) {
        if phase != .active {
            isObscured = privacyCover
            backgroundDate = Date()
            if AutoLockDuration(rawValue: autoLock) == .immediately {
                vault.lockVault()
            }
            return
        }

        if let backgroundDate,
           let duration = AutoLockDuration(rawValue: autoLock),
           Date().timeIntervalSince(backgroundDate) >= duration.seconds {
            vault.lockVault()
        }
        backgroundDate = nil
        isObscured = false
    }
}

struct PrivacyCoverView: View {
    var screenCapture = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                LionMark(size: 72)
                Text("Lion Pass").font(.title2.bold())
                Label(
                    screenCapture ? "Conteúdo oculto durante captura de tela" : "Conteúdo protegido",
                    systemImage: screenCapture ? "record.circle" : "lock.fill"
                )
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct RootView: View {
    @EnvironmentObject private var vault: VaultService

    var body: some View {
        Group {
            if vault.isUnlocked {
                VaultHomeView()
            } else if vault.hasVault {
                UnlockView()
            } else {
                WelcomeView()
            }
        }
        .animation(.easeInOut, value: vault.isUnlocked)
    }
}
