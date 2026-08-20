import AppKit
import SwiftUI

final class LionMacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        applyDockIcon()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        applyDockIcon()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationDidBecomeActive(_ notification: Notification) { applyDockIcon() }

    private func applyDockIcon() {
        if let icon = NSImage(named: "LionLogo") {
            NSApplication.shared.applicationIconImage = icon
        }
    }
}

@main
struct LionPasswordMacApp: App {
    @NSApplicationDelegateAdaptor(LionMacAppDelegate.self) private var appDelegate
    @StateObject private var vault = VaultService()

    var body: some Scene {
        WindowGroup {
            MacAppContent()
                .environmentObject(vault)
                .tint(.lionBlue)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Novo item") {
                    NotificationCenter.default.post(name: .newLionItem, object: nil)
                }
                .keyboardShortcut("n")
            }
        }
        Settings { LionAboutView() }
    }
}

extension Notification.Name {
    static let newLionItem = Notification.Name("newLionItem")
}

struct MacAppContent: View {
    @EnvironmentObject private var vault: VaultService
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(LionPreferenceKey.appearance) private var appearance = "system"
    @AppStorage(LionPreferenceKey.autoLock) private var autoLock = AutoLockDuration.immediately.rawValue
    @AppStorage(LionPreferenceKey.privacyCover) private var privacyCover = true
    @State private var backgroundDate: Date?
    @State private var isObscured = false

    var body: some View {
        ZStack {
            MacRootView()
            if isObscured {
                ZStack {
                    Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
                    VStack(spacing: 14) {
                        LionMacMark()
                        Label("Conteúdo protegido", systemImage: "lock.fill")
                    }
                }
            }
        }
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
        .privacySensitive()
        .onChange(of: scenePhase) { _, phase in handle(phase) }
        .sheet(isPresented: Binding(
            get: { vault.pendingRecoveryKey != nil },
            set: { if !$0 { vault.acknowledgeRecoveryKey() } }
        )) {
            if let recoveryKey = vault.pendingRecoveryKey {
                MacRecoveryKeyView(recoveryKey: recoveryKey).environmentObject(vault)
            }
        }
    }

    private func handle(_ phase: ScenePhase) {
        if phase != .active {
            isObscured = privacyCover
            backgroundDate = Date()
            if AutoLockDuration(rawValue: autoLock) == .immediately { vault.lockVault() }
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

struct MacRootView: View {
    @EnvironmentObject private var vault: VaultService

    var body: some View {
        if vault.isUnlocked {
            MacVaultView()
        } else if vault.hasVault {
            MacUnlockView()
        } else {
            MacWelcomeView()
        }
    }
}

struct MacWelcomeView: View {
    @EnvironmentObject private var vault: VaultService
    @State private var name = "Meu Cofre"
    @State private var password = ""
    @State private var confirmation = ""
    @State private var error: String?
    @State private var importing = false
    @State private var importURL: URL?

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            LionMacMark()
            Text("Lion Password").font(.largeTitle.bold())
            Text("Cofre local e privado para seu Mac").foregroundStyle(.secondary)
            GroupBox("Criar primeiro cofre") {
                VStack(spacing: 12) {
                    TextField("Nome do cofre", text: $name)
                    SecureField("Senha mestra (mínimo 12 caracteres)", text: $password)
                    SecureField("Confirmar senha", text: $confirmation)
                    if let error { Text(error).foregroundStyle(.red) }
                    HStack {
                        Button("Abrir cofre existente") { importing = true }
                        Button("Criar cofre") { create() }
                            .buttonStyle(.borderedProminent)
                            .disabled(password.count < 12 || password != confirmation || name.isEmpty)
                    }
                }
                .padding(8)
            }
            .frame(width: 460)
            Text("Guarde a chave de recuperação que será mostrada após criar o cofre.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Link(
                "Criado por Lion Code Technology",
                destination: URL(string: "https://lioncodetech.com.br/")!
            )
            .font(.caption)
            Spacer()
        }
        .padding(40)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.lionVault]) { result in
            switch result {
            case let .success(url): importURL = url
            case let .failure(error): self.error = error.localizedDescription
            }
        }
        .sheet(isPresented: Binding(
            get: { importURL != nil },
            set: { if !$0 { importURL = nil } }
        )) {
            if let importURL { MacImportVaultView(url: importURL) }
        }
    }

    private func create() {
        do {
            try vault.createVault(name: name, password: password)
            password = ""
            confirmation = ""
        } catch { self.error = error.localizedDescription }
    }
}

struct MacUnlockView: View {
    @EnvironmentObject private var vault: VaultService
    @State private var password = ""
    @State private var error: String?
    @State private var confirmation: String?
    @State private var attemptedAutomaticTouchID = false
    @State private var hasTouchIDKey = BiometricKeyStore().exists
    @State private var showRecovery = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            LionMacMark()
            Text("Lion Password").font(.largeTitle.bold())
            if hasTouchIDKey {
                Label("Touch ID vinculado e ativo", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(.green)
            }
            SecureField("Senha mestra", text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(width: 360)
                .onSubmit(unlock)
            if let confirmation { Text(confirmation).foregroundStyle(.green) }
            if let error { Text(error).foregroundStyle(.red).frame(maxWidth: 520) }
            Button("Desbloquear", action: unlock)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(password.isEmpty)
            Button {
                hasTouchIDKey ? unlockWithTouchID() : activateTouchID()
            } label: {
                Label(
                    hasTouchIDKey ? "Desbloquear com Touch ID" : "Ativar Touch ID",
                    systemImage: "touchid"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!hasTouchIDKey && password.isEmpty)
            Button("Usar chave de recuperação") { showRecovery = true }
                .buttonStyle(.link)
            if !hasTouchIDKey {
                Text("Digite a senha mestra e clique em Ativar Touch ID. O vínculo será confirmado antes de retornar a esta tela.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .task {
            guard hasTouchIDKey, !attemptedAutomaticTouchID else { return }
            attemptedAutomaticTouchID = true
            unlockWithTouchID()
        }
        .sheet(isPresented: $showRecovery) { MacRecoveryUnlockView() }
    }

    private func unlock() {
        do {
            error = nil
            confirmation = nil
            try vault.openVault(password: password)
            password = ""
        } catch { self.error = error.localizedDescription }
    }

    private func activateTouchID() {
        do {
            error = nil
            confirmation = nil
            let store = BiometricKeyStore()
            guard store.isAvailable else { throw VaultError.biometricsUnavailable }
            try vault.openVault(password: password)
            do {
                try vault.enableBiometricUnlock()
            } catch {
                vault.lockVault()
                throw error
            }
            vault.lockVault()
            hasTouchIDKey = store.exists
            guard hasTouchIDKey else { throw VaultError.biometricsUnavailable }
            password = ""
            confirmation = "Touch ID vinculado com sucesso. Clique em Desbloquear com Touch ID para testar."
        } catch { self.error = error.localizedDescription }
    }

    private func unlockWithTouchID() {
        Task {
            do { try await vault.openVaultWithBiometrics() }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct MacRecoveryUnlockView: View {
    @EnvironmentObject private var vault: VaultService
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Chave de recuperação").font(.title2.bold())
            TextField("LION-RECOVERY-…", text: $key)
                .font(.body.monospaced())
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                Button("Desbloquear") {
                    do {
                        try vault.openVault(recoveryKey: key)
                        key = ""
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
                .buttonStyle(.borderedProminent)
                .disabled(key.isEmpty)
            }
        }
        .padding(28)
        .frame(width: 620)
    }
}

struct MacImportVaultView: View {
    @EnvironmentObject private var vault: VaultService
    @Environment(\.dismiss) private var dismiss
    let url: URL
    @State private var useRecovery = false
    @State private var secret = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Importar \(url.lastPathComponent)").font(.title2.bold())
            Toggle("Usar chave de recuperação", isOn: $useRecovery)
            if useRecovery {
                TextField("LION-RECOVERY-…", text: $secret).font(.body.monospaced())
            } else {
                SecureField("Senha mestra", text: $secret)
            }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                Button("Importar") { importVault() }
                    .buttonStyle(.borderedProminent)
                    .disabled(secret.isEmpty)
            }
        }
        .padding(28)
        .frame(width: 560)
    }

    private func importVault() {
        do {
            if useRecovery {
                try vault.importEncrypted(from: url, recoveryKey: secret)
            } else {
                try vault.importEncrypted(from: url, password: secret)
            }
            secret = ""
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct LionMacMark: View {
    var body: some View {
        Image("LionLogo")
            .resizable()
            .scaledToFit()
            .frame(width: 92, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .lionViolet.opacity(0.3), radius: 14, y: 6)
    }
}

struct LionAboutView: View {
    var body: some View {
        VStack(spacing: 14) {
            LionMacMark()
            Text("Lion Password").font(.title.bold())
            Text("Gerenciador de senhas local e privado").foregroundStyle(.secondary)
            Divider()
            Text("Criado por").font(.caption).foregroundStyle(.secondary)
            Link(
                "Lion Code Technology",
                destination: URL(string: "https://lioncodetech.com.br/")!
            )
            .font(.headline)
            Text("© 2026 Lion Code Technology").font(.caption).foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(width: 380, height: 360)
    }
}

struct MacRecoveryKeyView: View {
    @EnvironmentObject private var vault: VaultService
    let recoveryKey: String
    @State private var confirmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Guarde sua chave de recuperação", systemImage: "key.viewfinder")
                .font(.title2.bold())
            Text(recoveryKey)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .privacySensitive()
                .padding()
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            Text("Ela é mostrada uma única vez. Salve-a separadamente; o Lion não a envia nem a persiste em texto puro.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Copiar") { ClipboardService.shared.copy(recoveryKey) }
                Toggle("Salvei em local seguro", isOn: $confirmed)
                Spacer()
                Button("Concluir") { vault.acknowledgeRecoveryKey() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!confirmed)
            }
        }
        .padding(28)
        .frame(width: 620)
        .interactiveDismissDisabled(true)
    }
}
