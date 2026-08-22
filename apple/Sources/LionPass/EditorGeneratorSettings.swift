import AuthenticationServices
import SwiftUI
import UniformTypeIdentifiers

struct ItemEditorView: View {
    @EnvironmentObject private var vault: VaultService
    @Environment(\.dismiss) private var dismiss
    @State var item: VaultItem
    @State private var showPassword = false
    @State private var generator = false
    @State private var error: String?
    @AppStorage(LionPreferenceKey.suggestStrongPasswords) private var suggestStrongPasswords = true

    private var categories: [String] {
        var values = vault.payload?.allCategories ?? VaultPayload.defaultCategories
        if !values.contains(item.category) { values.append(item.category) }
        return values
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Informações") {
                    TextField("Título", text: $item.title)
                    Picker("Tipo", selection: $item.kind) {
                        ForEach(VaultItemKind.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Categoria", selection: $item.category) {
                        ForEach(categories, id: \.self) { Text($0).tag($0) }
                    }
                    Toggle("Favorito", isOn: $item.isFavorite)
                }

                switch item.kind {
                case .login:
                    loginFields
                case .card:
                    cardFields
                case .secureNote:
                    Section("Nota segura") {
                        TextEditor(text: $item.notes).frame(minHeight: 180)
                    }
                case .identity:
                    Section("Identidade") {
                        TextField("Nome / usuário", text: $item.username)
                        TextField("E-mail", text: $item.email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                        TextEditor(text: $item.notes).frame(minHeight: 120)
                    }
                case .other:
                    Section("Conteúdo") {
                        TextEditor(text: $item.notes).frame(minHeight: 160)
                    }
                }

                Section("Tags") {
                    TextField(
                        "Tags separadas por vírgula",
                        text: Binding(
                            get: { item.tags.joined(separator: ", ") },
                            set: {
                                item.tags = $0.split(separator: ",")
                                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                    .filter { !$0.isEmpty }
                            }
                        )
                    )
                }

                Section("Campos personalizados") {
                    ForEach($item.customFields) { $field in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Nome do campo", text: $field.name)
                            HStack {
                                if field.isSensitive {
                                    SecureField("Valor", text: $field.value)
                                } else {
                                    TextField("Valor", text: $field.value)
                                }
                                Toggle("Sensível", isOn: $field.isSensitive)
                                    .labelsHidden()
                                    .accessibilityLabel("Valor sensível")
                            }
                            Button("Remover campo", role: .destructive) {
                                item.customFields.removeAll { $0.id == field.id }
                            }
                            .font(.caption)
                        }
                    }
                    Button {
                        item.customFields.append(CustomField())
                    } label: {
                        Label("Adicionar campo", systemImage: "plus")
                    }
                }

                if !item.passwordHistory.isEmpty {
                    Section("Histórico de senhas") {
                        ForEach(item.passwordHistory.reversed()) { revision in
                            LabeledContent(
                                revision.changedAt.formatted(date: .abbreviated, time: .shortened),
                                value: String(repeating: "•", count: min(12, max(4, revision.password.count)))
                            )
                        }
                    }
                }

                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(item.title.isEmpty ? "Novo item" : "Editar item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") { save() }
                        .disabled(item.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $generator) {
                NavigationStack {
                    GeneratorView {
                        item.password = $0
                        generator = false
                    }
                }
            }
        }
    }

    private var loginFields: some View {
        Group {
            Section("Credenciais") {
                TextField("Usuário", text: $item.username).textContentType(.username)
                HStack {
                    Group {
                        if showPassword {
                            TextField("Senha", text: $item.password)
                        } else {
                            SecureField("Senha", text: $item.password)
                        }
                    }
                    .textContentType(.newPassword)
                    Button { showPassword.toggle() } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                    }
                    .accessibilityLabel(showPassword ? "Ocultar senha" : "Mostrar senha")
                    if suggestStrongPasswords {
                        Button { generator = true } label: {
                            Image(systemName: "wand.and.stars")
                        }
                        .accessibilityLabel("Gerar senha")
                    }
                }
                TextField("Site / URL", text: $item.website)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                TextField("E-mail", text: $item.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
            }
            Section("Notas") {
                TextEditor(text: $item.notes).frame(minHeight: 100)
            }
        }
    }

    private var cardFields: some View {
        Group {
            Section("Cartão") {
                TextField("Titular", text: $item.cardholder)
                SecureField("Número", text: $item.cardNumber).keyboardType(.numberPad)
                TextField("Validade", text: $item.expiry)
                SecureField("Código de segurança", text: $item.securityCode)
                    .keyboardType(.numberPad)
                TextField("Banco", text: $item.bank)
                TextField("Bandeira", text: $item.cardBrand)
            }
            Section("Notas") {
                TextEditor(text: $item.notes).frame(minHeight: 100)
            }
        }
    }

    private func save() {
        do {
            error = nil
            try vault.upsert(item)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct GeneratorView: View {
    @Environment(\.dismiss) private var dismiss
    var use: ((String) -> Void)?
    @State private var mode = 0
    @State private var options = PasswordOptions()
    @State private var result = ""
    @State private var words = 6
    @State private var separator = "-"
    @State private var capitalize = false
    @State private var number = true

    private var entropy: Int {
        mode == 0
            ? SecurePasswordGenerator.estimatedEntropyBits(options: options)
            : SecurePasswordGenerator.passphraseEntropyBits(words: words, includeNumber: number)
    }

    var body: some View {
        Form {
            Picker("Modo", selection: $mode) {
                Text("Senha").tag(0)
                Text("Frase-senha").tag(1)
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { generate() }

            if mode == 0 {
                Section("Opções") {
                    Stepper("Comprimento: \(options.length)", value: $options.length, in: 8...128)
                    Toggle("A–Z", isOn: $options.uppercase)
                    Toggle("a–z", isOn: $options.lowercase)
                    Toggle("0–9", isOn: $options.digits)
                    Toggle("Símbolos", isOn: $options.symbols)
                    Toggle("Excluir semelhantes", isOn: $options.excludeSimilar)
                }
            } else {
                Section("Opções") {
                    Stepper("Palavras: \(words)", value: $words, in: 6...12)
                    TextField("Separador", text: $separator)
                    Toggle("Capitalizar", isOn: $capitalize)
                    Toggle("Adicionar número", isOn: $number)
                }
            }

            Section("Resultado") {
                Text(result.isEmpty ? "Toque em Gerar" : result)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .privacySensitive()
                Label("Entropia estimada: \(entropy) bits", systemImage: "shield.lefthalf.filled")
                    .font(.caption)
                    .foregroundStyle(entropy >= 60 ? .green : .orange)
                Button("Gerar") { generate() }
                Button {
                    ClipboardService.shared.copy(result)
                } label: {
                    Label("Copiar", systemImage: "doc.on.doc")
                }
                .disabled(result.isEmpty)
                if let use {
                    Button("Usar no registro") { use(result) }.disabled(result.isEmpty)
                }
            }
        }
        .navigationTitle("Gerador seguro")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Concluir") { dismiss() }
            }
        }
        .onAppear(perform: generate)
    }

    private func generate() {
        do {
            if mode == 0 {
                result = try SecurePasswordGenerator.password(options: options)
            } else {
                result = try SecurePasswordGenerator.passphrase(
                    words: words,
                    separator: separator,
                    capitalize: capitalize,
                    includeNumber: number
                )
            }
        } catch {
            result = ""
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var vault: VaultService
    @Environment(\.dismiss) private var dismiss
    @AppStorage(LionPreferenceKey.language) private var language = "pt-BR"
    @AppStorage(LionPreferenceKey.appearance) private var appearance = "system"
    @AppStorage(LionPreferenceKey.autoLock) private var autoLock = AutoLockDuration.immediately.rawValue
    @AppStorage(LionPreferenceKey.clipboard) private var clipboard = 30
    @AppStorage(LionPreferenceKey.privacyCover) private var privacyCover = true
    @AppStorage(LionPreferenceKey.accountDisplayStyle) private var accountDisplayStyle = AccountDisplayStyle.titles.rawValue
    @AppStorage(LionPreferenceKey.passwordSaveBehavior) private var passwordSaveBehavior = PasswordSaveBehavior.ask.rawValue
    @AppStorage(LionPreferenceKey.detectCompromisedPasswords) private var detectCompromisedPasswords = true
    @AppStorage(LionPreferenceKey.suggestStrongPasswords) private var suggestStrongPasswords = true
    @AppStorage(LionPreferenceKey.automaticPasskeyUpgrades) private var automaticPasskeyUpgrades = false
    @AppStorage(LionPreferenceKey.allowContactingWebsites) private var allowContactingWebsites = false
    @State private var biometrics = false
    @State private var exporting = false
    @State private var importing = false
    @State private var importURL: URL?
    @State private var showImportPassword = false
    @State private var showChangePassword = false
    @State private var showCategories = false
    @State private var showRestore = false
    @State private var recoveryKey: String?
    @State private var securityMessage: String?
    @State private var securityError: String?

    var body: some View {
        Form {
            Section("Senhas e contas") {
                Picker("Mostrar contas como", selection: $accountDisplayStyle) {
                    ForEach(AccountDisplayStyle.allCases) { style in
                        Text(style.title).tag(style.rawValue)
                    }
                }
                Picker("Salvar senhas", selection: $passwordSaveBehavior) {
                    ForEach(PasswordSaveBehavior.allCases) { behavior in
                        Text(behavior.title).tag(behavior.rawValue)
                    }
                }
                Toggle("Detectar senhas comprometidas", isOn: $detectCompromisedPasswords)
                if detectCompromisedPasswords {
                    let count = PasswordSecurityAudit.vulnerableCount(in: vault.payload?.items ?? [])
                    Text(count == 0 ? "Nenhuma senha vulnerável detectada localmente." : "(count) senha(s) precisam de atenção.")
                        .font(.caption)
                        .foregroundStyle(count == 0 ? Color.secondary : Color.orange)
                }
                Toggle("Sugerir senhas fortes", isOn: $suggestStrongPasswords)
                Toggle("Permitir upgrades automáticos para passkeys", isOn: $automaticPasskeyUpgrades)
                    .disabled(true)
                Text("Passkeys automáticas exigem uma extensão compatível e assinatura Apple Developer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Permitir contato com sites", isOn: $allowContactingWebsites)
                Text("O Lion Pass não envia senhas e não faz consultas em segundo plano nesta versão.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Segurança") {
                Toggle("Face ID / Touch ID", isOn: Binding(
                    get: { biometrics },
                    set: { updateBiometrics($0) }
                ))
                Picker("Bloqueio automático", selection: $autoLock) {
                    ForEach(AutoLockDuration.allCases) { duration in
                        Text(duration.title).tag(duration.rawValue)
                    }
                }
                Picker("Limpar clipboard", selection: $clipboard) {
                    Text("15 segundos").tag(15)
                    Text("30 segundos").tag(30)
                    Text("60 segundos").tag(60)
                    Text("Nunca").tag(0)
                }
                Toggle("Ocultar conteúdo no background", isOn: $privacyCover)
                Toggle(
                    "Manter histórico de senhas",
                    isOn: Binding(
                        get: { vault.payload?.passwordHistoryEnabled ?? true },
                        set: { value in perform { try vault.setPasswordHistoryEnabled(value) } }
                    )
                )
                Button("Alterar senha mestra") { showChangePassword = true }
                Button("Mostrar chave de recuperação") {
                    perform { recoveryKey = try vault.revealRecoveryKey() }
                }
            }

            Section("AutoFill") {
                Button {
                    Task {
                        do {
                            try await ASSettingsHelper.openCredentialProviderAppSettings()
                        } catch {
                            securityError = error.localizedDescription
                        }
                    }
                } label: {
                    Label("Ativar nas configurações do iOS", systemImage: "rectangle.and.hand.point.up.left")
                }
                Text("Depois de ativado, o Lion oferece logins no Safari e em apps compatíveis.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Backup e restauração") {
                Button { exporting = true } label: {
                    Label("Exportar cofre criptografado", systemImage: "square.and.arrow.up")
                }
                Button { importing = true } label: {
                    Label("Importar cofre criptografado", systemImage: "square.and.arrow.down")
                }
                Button { showRestore = true } label: {
                    Label("Restaurar versão anterior", systemImage: "clock.arrow.circlepath")
                }
                .disabled(!vault.hasPreviousBackup)
                Button {
                    perform {
                        try vault.verifyIntegrity()
                        securityMessage = "Integridade do cofre verificada."
                    }
                } label: {
                    Label("Verificar integridade", systemImage: "checkmark.shield")
                }
            }

            Section("Cofre") {
                Button("Gerenciar categorias") { showCategories = true }
                Button {
                    vault.lockVault()
                    dismiss()
                } label: {
                    Label("Bloquear agora", systemImage: "lock.fill")
                }
            }

            Section("Idioma") {
                Picker("Idioma", selection: $language) {
                    Text("Português (Brasil)").tag("pt-BR")
                    Text("English").tag("en-US")
                    Text("Español").tag("es-ES")
                }
            }
            Section("Aparência") {
                Picker("Tema", selection: $appearance) {
                    Text("Sistema").tag("system")
                    Text("Claro").tag("light")
                    Text("Escuro").tag("dark")
                }
            }

            if let securityMessage {
                Section { Label(securityMessage, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            }
            if let securityError {
                Section { Label(securityError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
            }

            Section("Privacidade") {
                LabeledContent("Rede", value: "Nenhum acesso")
                LabeledContent("Analytics", value: "Desativado")
                LabeledContent("Formato", value: "lionvault v2")
            }
            Section("Sobre") {
                Link("Lion Code Technology", destination: URL(string: "https://lioncodetech.com.br/")!)
                Text("Criado por Lion Code Technology").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Configurações")
        .toolbar { Button("Concluir") { dismiss() } }
        .onAppear { biometrics = BiometricKeyStore().exists }
        .fileExporter(
            isPresented: $exporting,
            document: VaultDocument(data: (try? vault.encryptedData()) ?? Data()),
            contentType: .lionVault,
            defaultFilename: "backup.lionvault"
        ) { result in
            if case let .failure(error) = result { securityError = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.lionVault]) { result in
            switch result {
            case let .success(url):
                importURL = url
                showImportPassword = true
            case let .failure(error):
                securityError = error.localizedDescription
            }
        }
        .sheet(isPresented: $showImportPassword) {
            if let importURL { ImportVaultView(url: importURL) }
        }
        .sheet(isPresented: $showChangePassword) { ChangeMasterPasswordView() }
        .sheet(isPresented: $showCategories) { CategoryManagerView() }
        .sheet(isPresented: $showRestore) { RestoreBackupView() }
        .sheet(isPresented: Binding(
            get: { recoveryKey != nil },
            set: { if !$0 { recoveryKey = nil } }
        )) {
            if let recoveryKey {
                NavigationStack {
                    Form {
                        Text(recoveryKey)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .privacySensitive()
                        Button("Copiar") { ClipboardService.shared.copy(recoveryKey) }
                    }
                    .navigationTitle("Chave de recuperação")
                    .toolbar { Button("Concluir") { self.recoveryKey = nil } }
                }
            }
        }
    }

    private func updateBiometrics(_ enabled: Bool) {
        do {
            securityError = nil
            if enabled {
                guard BiometricKeyStore().isAvailable else { throw VaultError.biometricsUnavailable }
                try vault.enableBiometricUnlock()
                guard BiometricKeyStore().exists else { throw VaultError.biometricsUnavailable }
                securityMessage = "Face ID / Touch ID vinculado e ativo."
            } else {
                vault.disableBiometricUnlock()
                securityMessage = "Desbloqueio biométrico desativado."
            }
            biometrics = enabled
        } catch {
            biometrics = false
            securityError = error.localizedDescription
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            securityError = nil
            try action()
        } catch {
            securityError = error.localizedDescription
        }
    }
}

struct ChangeMasterPasswordView: View {
    @EnvironmentObject private var vault: VaultService
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new = ""
    @State private var confirmation = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Senha atual") { SecureField("Senha atual", text: $current) }
                Section("Nova senha") {
                    SecureField("Nova senha", text: $new)
                    SecureField("Confirmar nova senha", text: $confirmation)
                    if !confirmation.isEmpty, new != confirmation {
                        Text("As senhas não coincidem").foregroundStyle(.red)
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Alterar senha mestra")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Alterar") {
                        do {
                            try vault.changeMasterPassword(current: current, new: new)
                            current = ""
                            new = ""
                            confirmation = ""
                            dismiss()
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                    .disabled(current.isEmpty || new.count < 12 || new != confirmation)
                }
            }
        }
    }
}

struct CategoryManagerView: View {
    @EnvironmentObject private var vault: VaultService
    @Environment(\.dismiss) private var dismiss
    @State private var newCategory = ""
    @State private var editingCategory: String?
    @State private var editedName = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Nova categoria") {
                    HStack {
                        TextField("Nome", text: $newCategory)
                        Button("Adicionar") { add() }.disabled(newCategory.isEmpty)
                    }
                }
                Section("Padrão") {
                    ForEach(VaultPayload.defaultCategories, id: \.self) { Text($0) }
                }
                Section("Personalizadas") {
                    ForEach(vault.payload?.customCategories ?? [], id: \.self) { category in
                        Button(category) {
                            editingCategory = category
                            editedName = category
                        }
                        .swipeActions {
                            Button("Apagar", role: .destructive) { remove(category) }
                        }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Categorias")
            .toolbar { Button("Concluir") { dismiss() } }
            .alert("Renomear categoria", isPresented: Binding(
                get: { editingCategory != nil },
                set: { if !$0 { editingCategory = nil } }
            )) {
                TextField("Nome", text: $editedName)
                Button("Cancelar", role: .cancel) { editingCategory = nil }
                Button("Salvar") { rename() }
            }
        }
    }

    private func add() {
        do {
            try vault.addCategory(newCategory)
            newCategory = ""
        } catch { self.error = error.localizedDescription }
    }

    private func rename() {
        guard let editingCategory else { return }
        do {
            try vault.renameCategory(editingCategory, to: editedName)
            self.editingCategory = nil
        } catch { self.error = error.localizedDescription }
    }

    private func remove(_ category: String) {
        do { try vault.deleteCategory(category) } catch { self.error = error.localizedDescription }
    }
}

struct RestoreBackupView: View {
    @EnvironmentObject private var vault: VaultService
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Versão anterior") {
                    Text("A versão atual será preservada como backup e poderá ser recuperada novamente.")
                    SecureField("Senha mestra da versão anterior", text: $password)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Restaurar backup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Restaurar") {
                        do {
                            try vault.restorePreviousBackup(password: password)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                    .disabled(password.isEmpty)
                }
            }
        }
    }
}

struct VaultDocument: FileDocument {
    static var readableContentTypes: [UTType] = [.lionVault]
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
