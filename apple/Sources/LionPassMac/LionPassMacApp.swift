import AppKit
import Combine
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
struct LionPassMacApp: App {
    @NSApplicationDelegateAdaptor(LionMacAppDelegate.self) private var appDelegate
    @StateObject private var vault = VaultService()
    @AppStorage(LionPreferenceKey.showInMenuBar) private var showInMenuBar = false
    @AppStorage(LionPreferenceKey.language) private var language = "pt-BR"
    @AppStorage(LionPreferenceKey.languageChosen) private var languageChosen = false

    var body: some Scene {
        WindowGroup("Lion Pass", id: "main") {
            MacAppContent()
                .environmentObject(vault)
                .environment(\.locale, Locale(identifier: language))
                .tint(.lionAccent)
                .frame(minWidth: 900, minHeight: 600)
                .sheet(isPresented: Binding(
                    get: { !languageChosen },
                    set: { _ in }
                )) {
                    MacLanguageSelectionView(language: $language, chosen: $languageChosen)
                }
        }
        .commands { LionPassCommands() }
        MenuBarExtra(
            "Lion Pass",
            systemImage: "key.fill",
            isInserted: $showInMenuBar
        ) {
            LionMenuBarView().environmentObject(vault)
        }
        Settings { MacSettingsView().environmentObject(vault) }
    }
}

struct LionMenuBarView: View {
    @EnvironmentObject private var vault: VaultService

    var body: some View {
        Button("Abrir Lion Pass") {
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate(ignoringOtherApps: true)
            NSApplication.shared.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
        }
        if vault.isUnlocked {
            Button("Bloquear cofre") { vault.lockVault() }
        }
        Divider()
        Button("Sair do Lion Pass") { NSApplication.shared.terminate(nil) }
    }
}

extension Notification.Name {
    static let newLionItem = Notification.Name("newLionItem")
}

enum LionMenuCommand {
    case newItem, newGroup, importPasswords, exportAllPasswords, exportSelectedPasswords, exportVault
    case copyUsername, copyPassword, copyWebsite, editCurrent, deleteSelected, selectAll, find
    case showCollection(String), sort(String)
}

final class LionCommandCenter {
    static let shared = LionCommandCenter()
    let commands = PassthroughSubject<LionMenuCommand, Never>()
    private init() {}
}

struct LionPassCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Nova credencial…") { send(.newItem) }
                .keyboardShortcut("n")
            Button("Nova janela") { openWindow(id: "main") }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Novo grupo local…") { send(.newGroup) }
        }
        CommandGroup(replacing: .importExport) {
            Button("Importar senhas de arquivo…") { send(.importPasswords) }
            Divider()
            Button("Exportar todas as senhas…") { send(.exportAllPasswords) }
            Button("Exportar senhas selecionadas…") { send(.exportSelectedPasswords) }
            Divider()
            Button("Exportar cofre criptografado…") { send(.exportVault) }
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copiar usuário") { send(.copyUsername) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("Copiar senha") { send(.copyPassword) }
                .keyboardShortcut("c", modifiers: [.command, .option])
            Button("Copiar site") { send(.copyWebsite) }
                .keyboardShortcut("c", modifiers: [.command, .option, .shift])
            Divider()
            Button("Editar item atual") { send(.editCurrent) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button("Mover para Apagados") { send(.deleteSelected) }
            Button("Selecionar tudo") { send(.selectAll) }
                .keyboardShortcut("a")
            Button("Buscar") { send(.find) }
                .keyboardShortcut("f")
        }
        CommandGroup(before: .sidebar) {
            Button("Todos os itens") { show("all") }.keyboardShortcut("1")
            Button("Logins") { show("logins") }.keyboardShortcut("2")
            Button("Cartões") { show("cards") }.keyboardShortcut("3")
            Button("Notas seguras") { show("notes") }.keyboardShortcut("4")
            Button("Wi-Fi") { show("wifi") }
            Button("Segurança") { show("security") }.keyboardShortcut("5")
            Button("Apagados") { show("deleted") }.keyboardShortcut("6")
            Divider()
            Menu("Ordenar por") {
                Button("Título") { sort("title") }
                Button("Mais recentes") { sort("recent") }
                Button("Mais antigos") { sort("oldest") }
            }
            Divider()
        }
        CommandGroup(replacing: .help) {
            Button("Ajuda do Lion Pass") {
                if let url = URL(string: "https://lioncodetech.com.br/") { openURL(url) }
            }
                .keyboardShortcut("?", modifiers: .command)
            Button("Bem-vindo ao Lion Pass") {
                NSApplication.shared.orderFrontStandardAboutPanel(nil)
            }
        }
    }

    private func send(_ command: LionMenuCommand) {
        LionCommandCenter.shared.commands.send(command)
    }

    private func show(_ collection: String) {
        send(.showCollection(collection))
    }

    private func sort(_ order: String) {
        send(.sort(order))
    }
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
            Text("Lion Pass").font(.largeTitle.bold())
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
    @State private var hasTouchIDKey = BiometricKeyStore().exists
    @State private var showRecovery = false
    @FocusState private var passwordFocused: Bool

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                lockIdentity
                Text("Lion Pass está bloqueado")
                    .font(.system(size: 28, weight: .bold))
                Text(unlockInstruction)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
                SecureField("Digite a senha mestra", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .frame(width: 380)
                    .focused($passwordFocused)
                    .onSubmit(unlock)
                if let confirmation {
                    Label(confirmation, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                if let error {
                    Text(error)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }
                HStack(spacing: 18) {
                    Button {
                        hasTouchIDKey ? unlockWithTouchID() : activateTouchID()
                    } label: {
                        Label(
                            hasTouchIDKey ? "Usar Touch ID" : "Ativar Touch ID",
                            systemImage: "touchid"
                        )
                    }
                    .buttonStyle(.link)
                    .disabled(!hasTouchIDKey && password.isEmpty)
                    Button("Usar chave de recuperação") { showRecovery = true }
                        .buttonStyle(.link)
                }
                Spacer()
            }
            .padding(40)
        }
        .task {
            passwordFocused = true
        }
        .sheet(isPresented: $showRecovery) { MacRecoveryUnlockView() }
    }

    private var lockIdentity: some View {
        ZStack(alignment: .bottomTrailing) {
            Image("LionLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 112, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.28), radius: 14, y: 8)
            if hasTouchIDKey {
                Image(systemName: "touchid")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.pink)
                    .frame(width: 60, height: 60)
                    .background(.black.opacity(0.88), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.08)))
                    .offset(x: 22, y: 16)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.black.opacity(0.88), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.08)))
                    .offset(x: 18, y: 14)
            }
        }
        .padding(.trailing, 20)
    }

    private var unlockInstruction: String {
        let user = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        let name = user.isEmpty ? "este usuário" : "“\(user)”"
        if hasTouchIDKey {
            return "Use o Touch ID ou digite a senha mestra do Lion Pass para \(name)."
        }
        return "Digite a senha mestra do Lion Pass para \(name)."
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
            Text("Lion Pass").font(.title.bold())
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

private struct MacLanguageSelectionView: View {
    @Binding var language: String
    @Binding var chosen: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image("LionLogo").resizable().scaledToFit().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Lion Pass").font(.title.bold())
                    Text("Escolha seu idioma / Choose your language / Elija su idioma")
                        .foregroundStyle(.secondary)
                }
            }
            Picker("Idioma / Language / Idioma", selection: $language) {
                Text("Português (Brasil)").tag("pt-BR")
                Text("English").tag("en-US")
                Text("Español").tag("es-ES")
            }
            .pickerStyle(.radioGroup)
            HStack {
                Spacer()
                Button("Continuar / Continue / Continuar") { chosen = true }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(width: 520)
        .interactiveDismissDisabled()
    }
}
