import SwiftUI
import UniformTypeIdentifiers

struct ItemEditorView: View {
    @EnvironmentObject var vault: VaultService; @Environment(\.dismiss) var dismiss; @State var item: VaultItem; @State private var showPassword = false; @State private var generator = false; @State private var error: String?
    var body: some View { NavigationStack { Form {
        Section("Informações") { TextField("Título", text: $item.title); Picker("Tipo", selection: $item.kind) { ForEach(VaultItemKind.allCases) { Text($0.title).tag($0) } }; TextField("Categoria", text: $item.category); Toggle("Favorito", isOn: $item.isFavorite) }
        if item.kind == .login { Section("Credenciais") { TextField("Usuário", text: $item.username).textContentType(.username); HStack { Group { if showPassword { TextField("Senha", text: $item.password) } else { SecureField("Senha", text: $item.password) } }.textContentType(.newPassword); Button { showPassword.toggle() } label: { Image(systemName: showPassword ? "eye.slash" : "eye") }; Button { generator = true } label: { Image(systemName: "wand.and.stars") } }; TextField("Site / URL", text: $item.website).textContentType(.URL).keyboardType(.URL); TextField("E-mail", text: $item.email).textContentType(.emailAddress).keyboardType(.emailAddress) } }
        if item.kind == .card { Section("Cartão") { TextField("Titular", text: $item.cardholder); SecureField("Número", text: $item.cardNumber).keyboardType(.numberPad); TextField("Validade", text: $item.expiry); SecureField("Código de segurança", text: $item.securityCode).keyboardType(.numberPad); TextField("Banco", text: $item.bank); TextField("Bandeira", text: $item.cardBrand) } }
        Section("Notas e tags") { TextEditor(text: $item.notes).frame(minHeight: 100); TextField("Tags separadas por vírgula", text: Binding(get: { item.tags.joined(separator: ", ") }, set: { item.tags = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } })) }
        Section("Campos personalizados") { ForEach($item.customFields) { $field in VStack { TextField("Nome", text: $field.name); HStack { if field.isSensitive { SecureField("Valor", text: $field.value) } else { TextField("Valor", text: $field.value) }; Toggle("Sensível", isOn: $field.isSensitive).labelsHidden() } }; Button { item.customFields.append(CustomField()) } label: { Label("Adicionar campo", systemImage: "plus") } }
        if let error { Text(error).foregroundStyle(.red) }
    }.navigationTitle(item.title.isEmpty ? "Novo item" : "Editar item").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Salvar") { save() }.disabled(item.title.isEmpty) } }.sheet(isPresented: $generator) { NavigationStack { GeneratorView { item.password = $0; generator = false } } } } }
    private func save() { item.updatedAt = Date(); do { try vault.upsert(item); dismiss() } catch { self.error = error.localizedDescription } }
}

struct GeneratorView: View {
    @Environment(\.dismiss) var dismiss; var use: ((String) -> Void)?; @State private var mode = 0; @State private var options = PasswordOptions(); @State private var result = ""; @State private var words = 5; @State private var separator = "-"; @State private var capitalize = false; @State private var number = true
    var body: some View { Form { Picker("Modo", selection: $mode) { Text("Senha").tag(0); Text("Frase-senha").tag(1) }.pickerStyle(.segmented)
        if mode == 0 { Section("Opções") { Stepper("Comprimento: \(options.length)", value: $options.length, in: 8...128); Toggle("A–Z", isOn: $options.uppercase); Toggle("a–z", isOn: $options.lowercase); Toggle("0–9", isOn: $options.digits); Toggle("Símbolos", isOn: $options.symbols); Toggle("Excluir semelhantes", isOn: $options.excludeSimilar) } } else { Section("Opções") { Stepper("Palavras: \(words)", value: $words, in: 3...10); TextField("Separador", text: $separator); Toggle("Capitalizar", isOn: $capitalize); Toggle("Adicionar número", isOn: $number) } }
        Section("Resultado") { Text(result.isEmpty ? "Toque em Gerar" : result).font(.body.monospaced()).textSelection(.enabled); Button("Gerar") { generate() }; Button { ClipboardService.shared.copy(result, clearAfter: 30) } label: { Label("Copiar", systemImage: "doc.on.doc") }.disabled(result.isEmpty); if let use { Button("Usar no registro") { use(result) }.disabled(result.isEmpty) } }
    }.navigationTitle("Gerador seguro").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Concluir") { dismiss() } } }.onAppear(perform: generate) }
    private func generate() { do { if mode == 0 { result = try SecurePasswordGenerator.password(options: options) } else { result = try SecurePasswordGenerator.passphrase(words: words, separator: separator, capitalize: capitalize, includeNumber: number) } } catch { result = "" } }
}

struct SettingsView: View {
    @EnvironmentObject var vault: VaultService; @Environment(\.dismiss) var dismiss
    @AppStorage("appearance") private var appearance = "system"; @AppStorage("autoLock") private var autoLock = AutoLockDuration.immediately.rawValue; @AppStorage("clipboard") private var clipboard = 30; @AppStorage("biometrics") private var biometrics = false; @State private var exporting = false; @State private var importing = false; @State private var importURL: URL?; @State private var showImportPassword = false; @State private var securityError: String?
    var body: some View { Form { Section("Segurança") { Toggle("Face ID / Touch ID", isOn: Binding(get: { biometrics }, set: { value in do { if value { try vault.enableBiometricUnlock() } else { vault.disableBiometricUnlock() }; biometrics = value } catch { securityError = error.localizedDescription; biometrics = false } })); Picker("Bloqueio automático", selection: $autoLock) { Text("Imediatamente").tag(AutoLockDuration.immediately.rawValue); Text("Após 30 segundos").tag(AutoLockDuration.seconds30.rawValue); Text("1 minuto").tag(AutoLockDuration.minute1.rawValue); Text("5 minutos").tag(AutoLockDuration.minutes5.rawValue); Text("15 minutos").tag(AutoLockDuration.minutes15.rawValue) }; Picker("Limpar clipboard", selection: $clipboard) { Text("15 segundos").tag(15); Text("30 segundos").tag(30); Text("60 segundos").tag(60); Text("Nunca").tag(0) }; Toggle("Ocultar conteúdo no background", isOn: .constant(true)).disabled(true) }
        Section("Cofre") { Button { exporting = true } label: { Label("Exportar cofre", systemImage: "square.and.arrow.up") }; Button { importing = true } label: { Label("Importar cofre", systemImage: "square.and.arrow.down") }; Button { vault.lockVault(); dismiss() } label: { Label("Bloquear agora", systemImage: "lock.fill") } }
        Section("Aparência") { Picker("Tema", selection: $appearance) { Text("Sistema").tag("system"); Text("Claro").tag("light"); Text("Escuro").tag("dark") } }
        if let securityError { Section { Text(securityError).foregroundStyle(.red) } }
        Section("Privacidade") { LabeledContent("Rede", value: "Nenhum acesso"); LabeledContent("Analytics", value: "Desativado"); LabeledContent("Formato", value: "lionvault v1") }
        Section("Sobre") { Link("Lion Code Technology", destination: URL(string: "https://lioncodetech.com.br/")!); Text("Criado por Lion Code Technology").foregroundStyle(.secondary) }
    }.navigationTitle("Configurações").toolbar { Button("Concluir") { dismiss() } }
      .fileExporter(isPresented: $exporting, document: VaultDocument(data: (try? vault.encryptedData()) ?? Data()), contentType: .lionVault, defaultFilename: "backup.lionvault") { _ in }
      .fileImporter(isPresented: $importing, allowedContentTypes: [.lionVault]) { result in if case .success(let url) = result { importURL = url; showImportPassword = true } }
      .sheet(isPresented: $showImportPassword) { if let importURL { ImportVaultView(url: importURL) } }
    }
}

struct VaultDocument: FileDocument { static var readableContentTypes: [UTType] = [.lionVault]; var data: Data; init(data: Data) { self.data = data }; init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }; func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) } }
