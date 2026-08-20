import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    @EnvironmentObject var vault: VaultService
    @State private var creating = false; @State private var importing = false; @State private var importURL: URL?; @State private var showImportPassword = false
    var body: some View {
        NavigationStack { VStack(spacing: 28) {
            Spacer(); LionMark(size: 96)
            VStack(spacing: 8) { Text("Lion Password").font(.largeTitle.bold()); Text("Seu cofre. Suas chaves. Seus dados.").foregroundStyle(.secondary) }
            VStack(spacing: 12) {
                Button { creating = true } label: { Label("Criar novo cofre", systemImage: "plus.circle.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).controlSize(.large)
                Button { importing = true } label: { Label("Abrir cofre existente", systemImage: "folder.fill").frame(maxWidth: .infinity) }.buttonStyle(.bordered).controlSize(.large)
                Button("Importar do KeePass") {}.disabled(true).accessibilityHint("Recurso planejado para uma próxima versão")
            }.frame(maxWidth: 420); Spacer()
            Text("Funciona offline • Sem conta • Criptografia local").font(.footnote).foregroundStyle(.secondary)
        }.padding(28).navigationDestination(isPresented: $creating) { CreateVaultView() }.fileImporter(isPresented: $importing, allowedContentTypes: [.lionVault]) { result in if case .success(let url) = result { importURL = url; showImportPassword = true } }.sheet(isPresented: $showImportPassword) { if let importURL { ImportVaultView(url: importURL) } }
        }
    }
}

struct CreateVaultView: View {
    @EnvironmentObject var vault: VaultService; @Environment(\.dismiss) var dismiss
    @State private var name = "Meu Cofre"; @State private var password = ""; @State private var confirmation = ""; @State private var accepted = false; @State private var error: String?
    private var score: Int { [password.count >= 12, password.rangeOfCharacter(from: .uppercaseLetters) != nil, password.rangeOfCharacter(from: .decimalDigits) != nil, password.rangeOfCharacter(from: .symbols) != nil].filter { $0 }.count }
    var body: some View {
        Form { Section("Cofre") { TextField("Nome", text: $name) }
            Section("Senha mestra") { SecureField("Senha", text: $password); SecureField("Confirmar senha", text: $confirmation); StrengthMeter(score: score) }
            Section { Toggle("Entendo que a senha não pode ser recuperada", isOn: $accepted) } footer: { Text("Se esquecer a senha mestra e não tiver outro método configurado, o conteúdo do cofre não poderá ser recuperado.") }
            if let error { Text(error).foregroundStyle(.red) }
            Button("Criar cofre") { do { try vault.createVault(name: name, password: password) } catch { self.error = error.localizedDescription } }
                .disabled(name.isEmpty || password.count < 12 || password != confirmation || !accepted)
        }.navigationTitle("Novo cofre")
    }
}

struct UnlockView: View {
    @EnvironmentObject var vault: VaultService; @State private var password = ""; @State private var error: String?; @State private var busy = false
    var body: some View { NavigationStack { VStack(spacing: 24) { Spacer(); LionMark(size: 80); Text("Lion Password").font(.title.bold()); Text("Cofre local").foregroundStyle(.secondary)
        SecureField("Senha mestra", text: $password).textContentType(.password).submitLabel(.go).onSubmit(unlock).padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 14)).frame(maxWidth: 420)
        if let error { Label(error, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.red) }
        Button(action: unlock) { if busy { ProgressView() } else { Text("Desbloquear").frame(maxWidth: .infinity) } }.buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: 420).disabled(password.isEmpty || busy)
        Button { Task { do { try await vault.openVaultWithBiometrics() } catch { self.error = error.localizedDescription } } } label: { Label("Usar Face ID / Touch ID", systemImage: "faceid") }.disabled(!BiometricKeyStore().exists).accessibilityHint("Use a biometria configurada neste dispositivo")
        Spacer()
    }.padding() } }
    private func unlock() { busy = true; defer { busy = false }; do { try vault.openVault(password: password); password = "" } catch { self.error = error.localizedDescription } }
}

struct LionMark: View { let size: CGFloat; var body: some View { Image("LionLogo").resizable().scaledToFit().frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.22)).shadow(color: .lionViolet.opacity(0.28), radius: 16, y: 8) } }
struct StrengthMeter: View { let score: Int; var body: some View { VStack(alignment: .leading) { HStack { ForEach(0..<4) { i in Capsule().fill(i < score ? (score < 3 ? Color.orange : Color.green) : Color.secondary.opacity(0.2)).frame(height: 5) } }; Text(["Muito fraca","Fraca","Razoável","Forte","Muito forte"][score]).font(.caption).foregroundStyle(.secondary) } } }

extension UTType { static let lionVault = UTType(exportedAs: "com.example.lion-vault", conformingTo: .data) }

struct ImportVaultView: View {
    @EnvironmentObject var vault: VaultService; @Environment(\.dismiss) var dismiss; let url: URL; @State private var password = ""; @State private var error: String?
    var body: some View { NavigationStack { Form { Section("Cofre selecionado") { Text(url.lastPathComponent) }; Section("Senha mestra") { SecureField("Senha", text: $password) }; if let error { Text(error).foregroundStyle(.red) } }.navigationTitle("Importar cofre").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Importar") { do { try vault.importEncrypted(from: url, password: password); dismiss() } catch { self.error = error.localizedDescription } }.disabled(password.isEmpty) } } } }
}
