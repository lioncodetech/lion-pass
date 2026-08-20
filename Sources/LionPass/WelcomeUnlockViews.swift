import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    @EnvironmentObject private var vault: VaultService
    @State private var creating = false
    @State private var importing = false
    @State private var importURL: URL?
    @State private var showImportPassword = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()
                LionMark(size: 96)
                VStack(spacing: 8) {
                    Text("Bem-vindo ao Lion Pass")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text("Seu cofre. Suas chaves. Seus dados.")
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 12) {
                    Button { creating = true } label: {
                        Label("Criar novo cofre", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button { importing = true } label: {
                        Label("Abrir cofre existente", systemImage: "folder.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button("Importar do KeePass") {}
                        .disabled(true)
                        .accessibilityHint("Importação KDBX é opcional e ainda não está disponível")
                }
                .frame(maxWidth: 420)
                Spacer()
                Text("Funciona offline • Sem conta • Criptografia local")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .navigationDestination(isPresented: $creating) { CreateVaultView() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.lionVault]) { result in
                if case let .success(url) = result {
                    importURL = url
                    showImportPassword = true
                }
            }
            .sheet(isPresented: $showImportPassword) {
                if let importURL { ImportVaultView(url: importURL) }
            }
        }
    }
}

struct CreateVaultView: View {
    @EnvironmentObject private var vault: VaultService
    @State private var name = "Meu Cofre"
    @State private var password = ""
    @State private var confirmation = ""
    @State private var accepted = false
    @State private var error: String?

    private var score: Int {
        [
            password.count >= 12,
            password.count >= 16,
            password.rangeOfCharacter(from: .uppercaseLetters) != nil,
            password.rangeOfCharacter(from: .decimalDigits) != nil,
            password.rangeOfCharacter(from: .symbols) != nil
        ].filter { $0 }.count.clamped(to: 0...4)
    }

    var body: some View {
        Form {
            Section("Cofre") {
                TextField("Nome", text: $name)
                    .textContentType(.name)
            }
            Section("Senha mestra") {
                SecureField("Senha", text: $password)
                    .textContentType(.newPassword)
                SecureField("Confirmar senha", text: $confirmation)
                    .textContentType(.newPassword)
                StrengthMeter(score: score)
                if !confirmation.isEmpty, password != confirmation {
                    Label("As senhas não coincidem", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }
            Section {
                Toggle("Entendo como guardar a chave de recuperação", isOn: $accepted)
            } footer: {
                Text("O Lion mostrará uma chave de recuperação uma única vez. Sem a senha mestra, essa chave ou a biometria já vinculada, o cofre não poderá ser recuperado.")
            }
            if let error {
                Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
            }
            Button("Criar cofre") { create() }
                .disabled(
                    name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || password.count < 12
                        || password != confirmation
                        || !accepted
                )
        }
        .navigationTitle("Novo cofre")
    }

    private func create() {
        do {
            error = nil
            try vault.createVault(name: name, password: password)
            password = ""
            confirmation = ""
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct UnlockView: View {
    @EnvironmentObject private var vault: VaultService
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false
    @State private var showRecovery = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                LionMark(size: 80)
                Text("Lion Pass").font(.title.bold())
                Text("Cofre local").foregroundStyle(.secondary)
                SecureField("Senha mestra", text: $password)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .onSubmit(unlock)
                    .padding()
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                    .frame(maxWidth: 420)
                    .accessibilityHint("Digite a senha mestra do cofre")
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .frame(maxWidth: 420)
                }
                Button(action: unlock) {
                    if busy {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Desbloquear").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: 420)
                .disabled(password.isEmpty || busy)

                if BiometricKeyStore().exists {
                    Button { unlockWithBiometrics() } label: {
                        Label("Usar Face ID / Touch ID", systemImage: "touchid")
                    }
                    .accessibilityHint("Use a biometria configurada neste dispositivo")
                }
                Button("Usar chave de recuperação") { showRecovery = true }
                    .font(.callout)
                Spacer()
            }
            .padding()
            .sheet(isPresented: $showRecovery) { RecoveryUnlockView() }
        }
    }

    private func unlock() {
        busy = true
        defer { busy = false }
        do {
            error = nil
            try vault.openVault(password: password)
            password = ""
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func unlockWithBiometrics() {
        Task {
            do {
                error = nil
                try await vault.openVaultWithBiometrics()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

struct RecoveryUnlockView: View {
    @EnvironmentObject private var vault: VaultService
    @Environment(\.dismiss) private var dismiss
    @State private var recoveryKey = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("LION-RECOVERY-…", text: $recoveryKey, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                } header: {
                    Text("Chave de recuperação")
                } footer: {
                    Text("A chave é validada somente no dispositivo e nunca é enviada.")
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Recuperar cofre")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Desbloquear") {
                        do {
                            try vault.openVault(recoveryKey: recoveryKey)
                            recoveryKey = ""
                            dismiss()
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                    .disabled(recoveryKey.isEmpty)
                }
            }
        }
    }
}

struct RecoveryKeySheet: View {
    @EnvironmentObject private var vault: VaultService
    let recoveryKey: String
    @State private var confirmed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Guarde esta chave agora", systemImage: "key.viewfinder")
                        .font(.headline)
                    Text(recoveryKey)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .privacySensitive()
                    Button {
                        ClipboardService.shared.copy(recoveryKey)
                    } label: {
                        Label("Copiar chave", systemImage: "doc.on.doc")
                    }
                } footer: {
                    Text("Ela não será armazenada em texto puro nem mostrada automaticamente novamente. Salve-a em um local seguro e separado do dispositivo.")
                }
                Section {
                    Toggle("Salvei a chave em local seguro", isOn: $confirmed)
                }
            }
            .navigationTitle("Chave de recuperação")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Concluir") { vault.acknowledgeRecoveryKey() }
                        .disabled(!confirmed)
                }
            }
            .interactiveDismissDisabled(true)
        }
    }
}

struct LionMark: View {
    let size: CGFloat

    var body: some View {
        Image("LionLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
            .shadow(color: .lionViolet.opacity(0.28), radius: 16, y: 8)
            .accessibilityLabel("Símbolo do Lion Pass")
    }
}

struct StrengthMeter: View {
    let score: Int

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(index < score ? (score < 3 ? Color.orange : Color.green) : Color.secondary.opacity(0.2))
                        .frame(height: 5)
                }
            }
            Text(["Muito fraca", "Fraca", "Razoável", "Forte", "Muito forte"][score])
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Qualidade da senha: \(["Muito fraca", "Fraca", "Razoável", "Forte", "Muito forte"][score])")
        }
    }
}

extension UTType {
    static let lionVault = UTType(exportedAs: LionIdentifiers.vaultType, conformingTo: .data)
}

struct ImportVaultView: View {
    @EnvironmentObject private var vault: VaultService
    @Environment(\.dismiss) private var dismiss
    let url: URL
    @State private var method = 0
    @State private var secret = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Cofre selecionado") { Text(url.lastPathComponent) }
                Picker("Método", selection: $method) {
                    Text("Senha mestra").tag(0)
                    Text("Chave de recuperação").tag(1)
                }
                .pickerStyle(.segmented)
                Section(method == 0 ? "Senha mestra" : "Chave de recuperação") {
                    if method == 0 {
                        SecureField("Senha", text: $secret)
                    } else {
                        TextField("LION-RECOVERY-…", text: $secret, axis: .vertical)
                            .font(.body.monospaced())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Importar cofre")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importar") { importVault() }.disabled(secret.isEmpty)
                }
            }
        }
    }

    private func importVault() {
        do {
            if method == 0 {
                try vault.importEncrypted(from: url, password: secret)
            } else {
                try vault.importEncrypted(from: url, recoveryKey: secret)
            }
            secret = ""
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
