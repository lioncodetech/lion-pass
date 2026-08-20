import SwiftUI
import UniformTypeIdentifiers

struct MacVaultView: View {
    @EnvironmentObject private var vault: VaultService
    @State private var selection: UUID?
    @State private var query = ""
    @State private var kind: VaultItemKind?
    @State private var category: String?
    @State private var favoritesOnly = false
    @State private var editing: VaultItem?
    @State private var showGenerator = false
    @State private var showSettings = false
    @State private var exporting = false

    private var items: [VaultItem] {
        (vault.payload?.items ?? [])
            .filter {
                (kind == nil || $0.kind == kind)
                    && (category == nil || $0.category == category)
                    && (!favoritesOnly || $0.isFavorite)
                    && (query.isEmpty || $0.matches(query))
            }
            .sorted {
                if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    var body: some View {
        NavigationSplitView {
            List {
                Button { resetFilters() } label: {
                    Label("Todos os itens", systemImage: "tray.full.fill")
                }
                Button {
                    resetFilters()
                    favoritesOnly = true
                } label: {
                    Label("Favoritos", systemImage: "star.fill")
                }
                Section("Tipos") {
                    ForEach(VaultItemKind.allCases) { value in
                        Button {
                            resetFilters()
                            kind = value
                        } label: {
                            Label(value.title, systemImage: value.symbol)
                        }
                    }
                }
                Section("Categorias") {
                    ForEach(vault.payload?.allCategories ?? [], id: \.self) { value in
                        Button {
                            resetFilters()
                            category = value
                        } label: {
                            Label(value, systemImage: "folder")
                        }
                    }
                }
            }
            .navigationTitle("Lion")
        } content: {
            List(items, selection: $selection) { item in
                HStack {
                    Image(systemName: item.kind.symbol).foregroundStyle(Color.lionBlue)
                    VStack(alignment: .leading) {
                        Text(item.title).fontWeight(.semibold)
                        Text(item.username.isEmpty ? item.website : item.username)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if item.isFavorite {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                    }
                }
                .tag(item.id)
                .contextMenu {
                    Button("Editar") { editing = item }
                    Button("Apagar", role: .destructive) { try? vault.delete(ids: [item.id]) }
                }
            }
            .searchable(text: $query, prompt: "Pesquisar…")
            .navigationTitle(vault.payload?.name ?? "Meu cofre")
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView("Nenhum item", systemImage: "lock.square")
                }
            }
        } detail: {
            if let id = selection,
               let item = vault.payload?.items.first(where: { $0.id == id }) {
                MacItemDetail(item: item) { editing = item }
            } else {
                ContentUnavailableView("Selecione um item", systemImage: "lock.shield")
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { showGenerator = true } label: {
                    Label("Gerador", systemImage: "wand.and.stars")
                }
                Menu {
                    ForEach(VaultItemKind.allCases) { value in
                        Button(value.title) {
                            var item = VaultItem()
                            item.kind = value
                            item.category = defaultCategory(for: value)
                            editing = item
                        }
                    }
                } label: {
                    Label("Novo item", systemImage: "plus")
                }
                Button { exporting = true } label: {
                    Label("Exportar", systemImage: "square.and.arrow.up")
                }
                Button { showSettings = true } label: {
                    Label("Configurações", systemImage: "gear")
                }
                Button { vault.lockVault() } label: {
                    Label("Bloquear", systemImage: "lock.fill")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newLionItem)) { _ in
            editing = VaultItem()
        }
        .sheet(item: $editing) { MacItemEditor(item: $0) }
        .sheet(isPresented: $showGenerator) { MacGeneratorView() }
        .sheet(isPresented: $showSettings) { MacSettingsView() }
        .fileExporter(
            isPresented: $exporting,
            document: MacVaultDocument(data: (try? vault.encryptedData()) ?? Data()),
            contentType: .lionVault,
            defaultFilename: "backup.lionvault"
        ) { _ in }
    }

    private func resetFilters() {
        kind = nil
        category = nil
        favoritesOnly = false
        query = ""
    }

    private func defaultCategory(for kind: VaultItemKind) -> String {
        switch kind {
        case .login: "Logins"
        case .card: "Cartões"
        case .secureNote: "Notas"
        case .identity: "Identidades"
        case .other: "Outros"
        }
    }
}

struct MacItemDetail: View {
    let item: VaultItem
    let edit: () -> Void
    @State private var reveal = false
    @State private var revealedHistory: Set<UUID> = []

    var body: some View {
        Form {
            Section {
                Text(item.title).font(.largeTitle.bold())
                Text(item.category).foregroundStyle(.secondary)
            }
            if item.kind == .login {
                Section("Credenciais") {
                    LabeledContent("Usuário", value: item.username)
                    secretRow("Senha", value: item.password)
                    LabeledContent("Site", value: item.website)
                    LabeledContent("E-mail", value: item.email)
                }
            }
            if item.kind == .card {
                Section("Cartão") {
                    LabeledContent("Titular", value: item.cardholder)
                    secretRow("Número", value: item.cardNumber)
                    LabeledContent("Validade", value: item.expiry)
                    secretRow("Código", value: item.securityCode)
                    LabeledContent("Banco", value: item.bank)
                    LabeledContent("Bandeira", value: item.cardBrand)
                }
            }
            if !item.notes.isEmpty {
                Section("Notas") { Text(item.notes).textSelection(.enabled).privacySensitive() }
            }
            if !item.customFields.isEmpty {
                Section("Campos personalizados") {
                    ForEach(item.customFields) { field in
                        if field.isSensitive {
                            secretRow(field.name, value: field.value)
                        } else {
                            LabeledContent(field.name, value: field.value)
                        }
                    }
                }
            }
            if !item.passwordHistory.isEmpty {
                Section("Histórico de senhas") {
                    ForEach(item.passwordHistory.reversed()) { revision in
                        HStack {
                            Text(revision.changedAt.formatted(date: .abbreviated, time: .shortened))
                            Spacer()
                            Text(revealedHistory.contains(revision.id) ? revision.password : "••••••••")
                                .font(.body.monospaced())
                            Button(revealedHistory.contains(revision.id) ? "Ocultar" : "Mostrar") {
                                if revealedHistory.contains(revision.id) {
                                    revealedHistory.remove(revision.id)
                                } else {
                                    revealedHistory.insert(revision.id)
                                }
                            }
                            Button("Copiar") { ClipboardService.shared.copy(revision.password) }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .toolbar { Button("Editar", action: edit) }
        .onDisappear {
            reveal = false
            revealedHistory.removeAll()
        }
    }

    private func secretRow(_ label: String, value: String) -> some View {
        HStack {
            LabeledContent(label, value: reveal ? value : "••••••••••••")
            Button(reveal ? "Ocultar" : "Mostrar") { reveal.toggle() }
            Button("Copiar") { ClipboardService.shared.copy(value) }
        }
    }

}

struct MacItemEditor: View {
    @EnvironmentObject private var vault: VaultService
    @Environment(\.dismiss) private var dismiss
    @State var item: VaultItem
    @State private var error: String?

    var body: some View {
        VStack {
            Form {
                Picker("Tipo", selection: $item.kind) {
                    ForEach(VaultItemKind.allCases) { Text($0.title).tag($0) }
                }
                TextField("Título", text: $item.title)
                Toggle("Favorito", isOn: $item.isFavorite)
                if item.kind == .login {
                    TextField("Usuário", text: $item.username)
                    SecureField("Senha", text: $item.password)
                    TextField("Site", text: $item.website)
                    TextField("E-mail", text: $item.email)
                }
                if item.kind == .card {
                    TextField("Titular", text: $item.cardholder)
                    SecureField("Número", text: $item.cardNumber)
                    TextField("Validade", text: $item.expiry)
                    SecureField("Código de segurança", text: $item.securityCode)
                    TextField("Banco", text: $item.bank)
                    TextField("Bandeira", text: $item.cardBrand)
                }
                Picker("Categoria", selection: $item.category) {
                    ForEach(vault.payload?.allCategories ?? [], id: \.self) { Text($0).tag($0) }
                }
                TextEditor(text: $item.notes).frame(minHeight: 90)
                Section("Campos personalizados") {
                    ForEach($item.customFields) { $field in
                        HStack {
                            TextField("Nome", text: $field.name)
                            if field.isSensitive {
                                SecureField("Valor", text: $field.value)
                            } else {
                                TextField("Valor", text: $field.value)
                            }
                            Toggle("Sensível", isOn: $field.isSensitive).labelsHidden()
                            Button(role: .destructive) {
                                item.customFields.removeAll { $0.id == field.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                    Button("Adicionar campo") { item.customFields.append(CustomField()) }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                Button("Salvar") {
                    do {
                        try vault.upsert(item)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
                .buttonStyle(.borderedProminent)
                .disabled(item.title.isEmpty)
            }
        }
        .padding()
        .frame(width: 620, height: 680)
    }
}

struct MacGeneratorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var mode = 0
    @State private var value = ""
    @State private var options = PasswordOptions()
    @State private var words = 6
    @State private var separator = "-"

    var body: some View {
        VStack(spacing: 18) {
            Text("Gerador seguro").font(.title.bold())
            Picker("Modo", selection: $mode) {
                Text("Senha").tag(0)
                Text("Frase-senha").tag(1)
            }
            .pickerStyle(.segmented)
            Text(value)
                .font(.title3.monospaced())
                .textSelection(.enabled)
                .privacySensitive()
                .padding()
                .frame(maxWidth: .infinity)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            if mode == 0 {
                Stepper("Comprimento: \(options.length)", value: $options.length, in: 8...128)
                Toggle("Maiúsculas", isOn: $options.uppercase)
                Toggle("Minúsculas", isOn: $options.lowercase)
                Toggle("Números", isOn: $options.digits)
                Toggle("Símbolos", isOn: $options.symbols)
                Toggle("Excluir semelhantes", isOn: $options.excludeSimilar)
            } else {
                Stepper("Palavras: \(words)", value: $words, in: 6...12)
                TextField("Separador", text: $separator)
            }
            HStack {
                Button("Gerar", action: generate)
                Button("Copiar") { ClipboardService.shared.copy(value) }
                Spacer()
                Button("Concluir") { dismiss() }
            }
        }
        .padding(28)
        .frame(width: 500)
        .onAppear(perform: generate)
        .onChange(of: mode) { generate() }
    }

    private func generate() {
        if mode == 0 {
            value = (try? SecurePasswordGenerator.password(options: options)) ?? ""
        } else {
            value = (try? SecurePasswordGenerator.passphrase(
                words: words,
                separator: separator,
                capitalize: false,
                includeNumber: true
            )) ?? ""
        }
    }
}

struct MacSettingsView: View {
    @EnvironmentObject private var vault: VaultService
    @Environment(\.dismiss) private var dismiss
    @AppStorage(LionPreferenceKey.appearance) private var appearance = "system"
    @AppStorage(LionPreferenceKey.autoLock) private var autoLock = AutoLockDuration.immediately.rawValue
    @AppStorage(LionPreferenceKey.clipboard) private var clipboard = 30
    @AppStorage(LionPreferenceKey.privacyCover) private var privacyCover = true
    @State private var biometrics = BiometricKeyStore().exists
    @State private var showChangePassword = false
    @State private var showCategories = false
    @State private var showRestore = false
    @State private var recoveryKey: String?
    @State private var message: String?
    @State private var error: String?

    var body: some View {
        Form {
            Section("Segurança") {
                Toggle("Touch ID", isOn: Binding(
                    get: { biometrics },
                    set: { updateBiometrics($0) }
                ))
                Picker("Bloqueio automático", selection: $autoLock) {
                    ForEach(AutoLockDuration.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Picker("Limpar clipboard", selection: $clipboard) {
                    Text("15 segundos").tag(15)
                    Text("30 segundos").tag(30)
                    Text("60 segundos").tag(60)
                    Text("Nunca").tag(0)
                }
                Toggle("Ocultar em background", isOn: $privacyCover)
                Toggle(
                    "Histórico de senhas",
                    isOn: Binding(
                        get: { vault.payload?.passwordHistoryEnabled ?? true },
                        set: { value in perform { try vault.setPasswordHistoryEnabled(value) } }
                    )
                )
            }
            Section("Cofre") {
                Button("Alterar senha mestra") { showChangePassword = true }
                Button("Mostrar chave de recuperação") {
                    perform { recoveryKey = try vault.revealRecoveryKey() }
                }
                Button("Gerenciar categorias") { showCategories = true }
                Button("Verificar integridade") {
                    perform {
                        try vault.verifyIntegrity()
                        message = "Integridade verificada."
                    }
                }
                Button("Restaurar versão anterior") { showRestore = true }
                    .disabled(!vault.hasPreviousBackup)
            }
            Section("Aparência") {
                Picker("Tema", selection: $appearance) {
                    Text("Sistema").tag("system")
                    Text("Claro").tag("light")
                    Text("Escuro").tag("dark")
                }
            }
            if let message { Text(message).foregroundStyle(.green) }
            if let error { Text(error).foregroundStyle(.red) }
            Section("Sobre") {
                Link("Lion Code Technology", destination: URL(string: "https://lioncodetech.com.br/")!)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 600, height: 620)
        .toolbar { Button("Concluir") { dismiss() } }
        .sheet(isPresented: $showChangePassword) { MacChangePasswordView() }
        .sheet(isPresented: $showCategories) { MacCategoryManagerView() }
        .sheet(isPresented: $showRestore) { MacRestoreBackupView() }
        .sheet(isPresented: Binding(
            get: { recoveryKey != nil },
            set: { if !$0 { recoveryKey = nil } }
        )) {
            if let recoveryKey {
                VStack(spacing: 18) {
                    Text("Chave de recuperação").font(.title2.bold())
                    Text(recoveryKey).font(.body.monospaced()).textSelection(.enabled)
                    Button("Copiar") { ClipboardService.shared.copy(recoveryKey) }
                    Button("Concluir") { self.recoveryKey = nil }
                }
                .padding(28)
                .frame(width: 620)
            }
        }
    }

    private func updateBiometrics(_ value: Bool) {
        do {
            if value {
                try vault.enableBiometricUnlock()
                guard BiometricKeyStore().exists else { throw VaultError.biometricsUnavailable }
                message = "Touch ID vinculado e ativo."
            } else {
                vault.disableBiometricUnlock()
                message = "Touch ID desativado."
            }
            biometrics = value
        } catch {
            biometrics = false
            self.error = error.localizedDescription
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { self.error = error.localizedDescription }
    }
}

struct MacChangePasswordView: View {
    @EnvironmentObject private var vault: VaultService
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new = ""
    @State private var confirmation = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Alterar senha mestra").font(.title2.bold())
            SecureField("Senha atual", text: $current)
            SecureField("Nova senha", text: $new)
            SecureField("Confirmar nova senha", text: $confirmation)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                Button("Alterar") {
                    do {
                        try vault.changeMasterPassword(current: current, new: new)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
                .buttonStyle(.borderedProminent)
                .disabled(current.isEmpty || new.count < 12 || new != confirmation)
            }
        }
        .padding(28)
        .frame(width: 520)
    }
}

struct MacCategoryManagerView: View {
    @EnvironmentObject private var vault: VaultService
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        VStack(spacing: 14) {
            Text("Categorias").font(.title2.bold())
            HStack {
                TextField("Nova categoria", text: $name)
                Button("Adicionar") {
                    do {
                        try vault.addCategory(name)
                        name = ""
                    } catch { self.error = error.localizedDescription }
                }
                .disabled(name.isEmpty)
            }
            List {
                Section("Padrão") {
                    ForEach(VaultPayload.defaultCategories, id: \.self) { Text($0) }
                }
                Section("Personalizadas") {
                    ForEach(vault.payload?.customCategories ?? [], id: \.self) { category in
                        HStack {
                            Text(category)
                            Spacer()
                            Button("Apagar", role: .destructive) {
                                do { try vault.deleteCategory(category) }
                                catch { self.error = error.localizedDescription }
                            }
                        }
                    }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
            HStack { Spacer(); Button("Concluir") { dismiss() } }
        }
        .padding(24)
        .frame(width: 520, height: 600)
    }
}

struct MacRestoreBackupView: View {
    @EnvironmentObject private var vault: VaultService
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Restaurar versão anterior").font(.title2.bold())
            SecureField("Senha da versão anterior", text: $password)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                Button("Restaurar") {
                    do {
                        try vault.restorePreviousBackup(password: password)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty)
            }
        }
        .padding(28)
        .frame(width: 520)
    }
}

extension UTType {
    static let lionVault = UTType(exportedAs: LionIdentifiers.vaultType, conformingTo: .data)
}

struct MacVaultDocument: FileDocument {
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
