import SwiftUI
import AppKit

final class LionMacAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private weak var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyDockIcon()
        DispatchQueue.main.async { [weak self] in self?.configureWindows() }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        applyDockIcon()
        configureWindows()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        let window = mainWindow ?? sender.windows.first(where: { $0.canBecomeMain })
        window?.makeKeyAndOrderFront(nil)
        return true
    }

    func windowShouldMiniaturize(_ sender: NSWindow) -> Bool {
        mainWindow = sender
        sender.orderOut(nil)
        return false
    }

    private func configureWindows() {
        for window in NSApplication.shared.windows where window.canBecomeMain {
            if mainWindow == nil { mainWindow = window }
            window.delegate = self
        }
    }

    private func applyDockIcon() {
        if let icon = NSImage(named: "LionLogo") {
            NSApplication.shared.applicationIconImage = icon
        }
    }
}

@main struct LionPasswordMacApp: App {
    @NSApplicationDelegateAdaptor(LionMacAppDelegate.self) private var appDelegate
    @StateObject private var vault = VaultService()
    var body: some Scene {
        WindowGroup { MacRootView().environmentObject(vault).tint(.lionBlue).frame(minWidth: 900, minHeight: 600) }
            .commands { CommandGroup(replacing: .newItem) { Button("Novo item") { NotificationCenter.default.post(name: .newLionItem, object: nil) }.keyboardShortcut("n") } }
        Settings { LionAboutView() }
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
        GroupBox("Criar primeiro cofre") { VStack(spacing: 12) { TextField("Nome do cofre", text: $name); SecureField("Senha mestra (mínimo 12 caracteres)", text: $password); SecureField("Confirmar senha", text: $confirmation); if let error { Text(error).foregroundStyle(.red) }; Button("Criar cofre") { do { try vault.createVault(name: name, password: password); enableTouchIDIfAvailable() } catch { self.error = error.localizedDescription } }.buttonStyle(.borderedProminent).disabled(password.count < 12 || password != confirmation || name.isEmpty) }.padding(8) }.frame(width: 420)
        Text("Se você esquecer a senha mestra, o cofre não poderá ser recuperado.").font(.caption).foregroundStyle(.secondary); Link("Criado por Lion Code Technology", destination: URL(string: "https://lioncodetech.com.br/")!).font(.caption); Spacer()
    }.padding(40) }
    private func enableTouchIDIfAvailable() { let store = BiometricKeyStore(); if store.isAvailable { try? vault.enableBiometricUnlock() } }
}

struct MacUnlockView: View {
    @EnvironmentObject var vault: VaultService; @State private var password = ""; @State private var error: String?
    var body: some View { VStack(spacing: 20) { Spacer(); LionMacMark(); Text("Lion Password").font(.largeTitle.bold()); SecureField("Senha mestra", text: $password).textFieldStyle(.roundedBorder).frame(width: 360).onSubmit(unlock); if let error { Text(error).foregroundStyle(.red) }; Button("Desbloquear") { unlock() }.buttonStyle(.borderedProminent).controlSize(.large).disabled(password.isEmpty); if BiometricKeyStore().exists { Button { unlockWithTouchID() } label: { Label("Desbloquear com Touch ID", systemImage: "touchid") }.buttonStyle(.bordered).controlSize(.large) }; Spacer() }.padding() }
    private func unlock() { do { try vault.openVault(password: password); let store = BiometricKeyStore(); if store.isAvailable { try vault.enableBiometricUnlock() }; password = "" } catch { self.error = error.localizedDescription } }
    private func unlockWithTouchID() { Task { do { try await vault.openVaultWithBiometrics() } catch { self.error = error.localizedDescription } } }
}

struct LionMacMark: View { var body: some View { Image("LionLogo").resizable().scaledToFit().frame(width: 92, height: 92).clipShape(RoundedRectangle(cornerRadius: 20)).shadow(color: .lionViolet.opacity(0.3), radius: 14, y: 6) } }

struct LionAboutView: View {
    var body: some View { VStack(spacing: 14) { LionMacMark(); Text("Lion Password").font(.title.bold()); Text("Gerenciador de senhas local e privado").foregroundStyle(.secondary); Divider(); Text("Criado por").font(.caption).foregroundStyle(.secondary); Link("Lion Code Technology", destination: URL(string: "https://lioncodetech.com.br/")!).font(.headline); Text("© 2026 Lion Code Technology").font(.caption).foregroundStyle(.secondary) }.padding(32).frame(width: 380, height: 360) }
}
