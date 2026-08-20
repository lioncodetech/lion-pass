import SwiftUI
import AppKit

@main struct LionPasswordMacApp: App {
    @StateObject private var vault = VaultService()
    var body: some Scene {
        WindowGroup { MacRootView().environmentObject(vault).tint(.lionBlue).frame(minWidth: 900, minHeight: 600).onAppear { if let icon = NSImage(named: "LionLogo") { NSApplication.shared.applicationIconImage = icon } } }
            .commands { CommandGroup(replacing: .newItem) { Button("Novo item") { NotificationCenter.default.post(name: .newLionItem, object: nil) }.keyboardShortcut("n") } }
    }
}

extension Notification.Name { static let newLionItem = Notification.Name("newLionItem") }

struct MacRootView: View {
    @EnvironmentObject var vault: VaultService
    var body: some View { if vault.isUnlocked { MacVaultView() } else if vault.hasVault { MacUnlockView() } else { MacWelcomeView() } }
}

struct MacWelcomeView: View {
    @EnvironmentObject var vault: VaultService
    @State private var name = "Meu Cofre"; @State private var password = ""; @State private var confirmation = ""; @State private var error: String?
    var body: some View { VStack(spacing: 22) {
        Spacer(); LionMacMark(); Text("Lion Password").font(.largeTitle.bold()); Text("Cofre local e privado para seu Mac").foregroundStyle(.secondary)
        GroupBox("Criar primeiro cofre") { VStack(spacing: 12) { TextField("Nome do cofre", text: $name); SecureField("Senha mestra (mínimo 12 caracteres)", text: $password); SecureField("Confirmar senha", text: $confirmation); if let error { Text(error).foregroundStyle(.red) }; Button("Criar cofre") { do { try vault.createVault(name: name, password: password) } catch { self.error = error.localizedDescription } }.buttonStyle(.borderedProminent).disabled(password.count < 12 || password != confirmation || name.isEmpty) }.padding(8) }.frame(width: 420)
        Text("Se você esquecer a senha mestra, o cofre não poderá ser recuperado.").font(.caption).foregroundStyle(.secondary); Spacer()
    }.padding(40) }
}

struct MacUnlockView: View {
    @EnvironmentObject var vault: VaultService; @State private var password = ""; @State private var error: String?
    var body: some View { VStack(spacing: 20) { Spacer(); LionMacMark(); Text("Lion Password").font(.largeTitle.bold()); SecureField("Senha mestra", text: $password).textFieldStyle(.roundedBorder).frame(width: 360).onSubmit(unlock); if let error { Text(error).foregroundStyle(.red) }; Button("Desbloquear") { unlock() }.buttonStyle(.borderedProminent).controlSize(.large).disabled(password.isEmpty); if BiometricKeyStore().exists { Button("Usar Touch ID") { Task { do { try await vault.openVaultWithBiometrics() } catch { self.error = error.localizedDescription } } } }; Spacer() }.padding() }
    private func unlock() { do { try vault.openVault(password: password); password = "" } catch { self.error = error.localizedDescription } }
}

struct LionMacMark: View { var body: some View { Image("LionLogo").resizable().scaledToFit().frame(width: 92, height: 92).clipShape(RoundedRectangle(cornerRadius: 20)).shadow(color: .lionViolet.opacity(0.3), radius: 14, y: 6) } }
