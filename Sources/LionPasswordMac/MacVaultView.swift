import SwiftUI
import UniformTypeIdentifiers

struct MacVaultView: View {
    @EnvironmentObject var vault: VaultService
    @State private var selection: UUID?; @State private var query = ""; @State private var category: VaultItemKind?; @State private var editing: VaultItem?; @State private var showGenerator = false; @State private var exporting = false
    private var items: [VaultItem] { (vault.payload?.items ?? []).filter { (category == nil || $0.kind == category) && (query.isEmpty || $0.matches(query)) }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending } }
    var body: some View { NavigationSplitView {
        List(selection: $category) { Label("Todos os itens", systemImage: "tray.full.fill").tag(VaultItemKind?.none); Section("Categorias") { ForEach(VaultItemKind.allCases) { kind in Label(kind.title, systemImage: kind.symbol).tag(Optional(kind)) } } }.navigationTitle("Lion")
    } content: {
        List(items, selection: $selection) { item in HStack { Image(systemName: item.kind.symbol).foregroundStyle(Color.lionBlue); VStack(alignment: .leading) { Text(item.title).fontWeight(.semibold); Text(item.username.isEmpty ? item.website : item.username).font(.caption).foregroundStyle(.secondary) }; Spacer(); if item.isFavorite { Image(systemName: "star.fill").foregroundStyle(.yellow) } }.tag(item.id).contextMenu { Button("Editar") { editing = item }; Button("Apagar", role: .destructive) { try? vault.delete(ids: [item.id]) } } }.searchable(text: $query, prompt: "Pesquisar…").navigationTitle(vault.payload?.name ?? "Meu cofre")
    } detail: {
        if let id = selection, let item = vault.payload?.items.first(where: { $0.id == id }) { MacItemDetail(item: item) { editing = item } } else { ContentUnavailableView("Selecione um item", systemImage: "lock.shield") }
    }.toolbar { ToolbarItemGroup { Button { showGenerator = true } label: { Label("Gerador", systemImage: "wand.and.stars") }; Button { editing = VaultItem() } label: { Label("Novo item", systemImage: "plus") }; Button { exporting = true } label: { Label("Exportar", systemImage: "square.and.arrow.up") }; Button { vault.lockVault() } label: { Label("Bloquear", systemImage: "lock.fill") } } }
      .onReceive(NotificationCenter.default.publisher(for: .newLionItem)) { _ in editing = VaultItem() }
      .sheet(item: $editing) { MacItemEditor(item: $0) }.sheet(isPresented: $showGenerator) { MacGeneratorView() }
      .fileExporter(isPresented: $exporting, document: MacVaultDocument(data: (try? vault.encryptedData()) ?? Data()), contentType: .lionVault, defaultFilename: "backup.lionvault") { _ in }
    }
}

struct MacItemDetail: View {
    let item: VaultItem; let edit: () -> Void; @State private var reveal = false
    var body: some View { Form { Section { Text(item.title).font(.largeTitle.bold()); Text(item.category).foregroundStyle(.secondary) }; if item.kind == .login { Section("Credenciais") { LabeledContent("Usuário", value: item.username); HStack { LabeledContent("Senha", value: reveal ? item.password : "••••••••••••"); Button(reveal ? "Ocultar" : "Mostrar") { reveal.toggle() }; Button("Copiar") { ClipboardService.shared.copy(item.password, clearAfter: 30) } }; LabeledContent("Site", value: item.website); LabeledContent("E-mail", value: item.email) } }; if item.kind == .card { Section("Cartão") { LabeledContent("Titular", value: item.cardholder); LabeledContent("Número", value: reveal ? item.cardNumber : "•••• " + item.cardNumber.suffix(4)); LabeledContent("Validade", value: item.expiry); LabeledContent("Banco", value: item.bank) } }; if !item.notes.isEmpty { Section("Notas") { Text(item.notes).textSelection(.enabled) } }; if !item.customFields.isEmpty { Section("Campos personalizados") { ForEach(item.customFields) { f in LabeledContent(f.name, value: f.isSensitive && !reveal ? "••••••••" : f.value) } } } }.formStyle(.grouped).padding().toolbar { Button("Editar", action: edit) } }
}

struct MacItemEditor: View {
    @EnvironmentObject var vault: VaultService; @Environment(\.dismiss) var dismiss; @State var item: VaultItem; @State private var error: String?
    var body: some View { VStack { Form { Picker("Tipo", selection: $item.kind) { ForEach(VaultItemKind.allCases) { Text($0.title).tag($0) } }; TextField("Título", text: $item.title); Toggle("Favorito", isOn: $item.isFavorite); if item.kind == .login { TextField("Usuário", text: $item.username); SecureField("Senha", text: $item.password); TextField("Site", text: $item.website); TextField("E-mail", text: $item.email) }; if item.kind == .card { TextField("Titular", text: $item.cardholder); SecureField("Número", text: $item.cardNumber); TextField("Validade", text: $item.expiry); SecureField("Código de segurança", text: $item.securityCode); TextField("Banco", text: $item.bank) }; TextField("Categoria", text: $item.category); TextEditor(text: $item.notes).frame(minHeight: 90); if let error { Text(error).foregroundStyle(.red) } }.formStyle(.grouped); HStack { Spacer(); Button("Cancelar") { dismiss() }; Button("Salvar") { do { try vault.upsert(item); dismiss() } catch { self.error = error.localizedDescription } }.buttonStyle(.borderedProminent).disabled(item.title.isEmpty) } }.padding().frame(width: 520, height: 560) }
}

struct MacGeneratorView: View {
    @Environment(\.dismiss) var dismiss; @State private var value = ""; @State private var options = PasswordOptions()
    var body: some View { VStack(spacing: 18) { Text("Gerador seguro").font(.title.bold()); Text(value).font(.title3.monospaced()).textSelection(.enabled).padding().frame(maxWidth: .infinity).background(.quaternary, in: RoundedRectangle(cornerRadius: 10)); Stepper("Comprimento: \(options.length)", value: $options.length, in: 8...128); Toggle("Maiúsculas", isOn: $options.uppercase); Toggle("Minúsculas", isOn: $options.lowercase); Toggle("Números", isOn: $options.digits); Toggle("Símbolos", isOn: $options.symbols); HStack { Button("Gerar") { generate() }; Button("Copiar") { ClipboardService.shared.copy(value, clearAfter: 30) }; Spacer(); Button("Concluir") { dismiss() } } }.padding(28).frame(width: 480).onAppear { generate() } }
    private func generate() { value = (try? SecurePasswordGenerator.password(options: options)) ?? "" }
}

extension UTType { static let lionVault = UTType(exportedAs: "com.lioncodetech.lion-vault", conformingTo: .data) }
struct MacVaultDocument: FileDocument { static var readableContentTypes: [UTType] = [.lionVault]; var data: Data; init(data: Data) { self.data = data }; init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }; func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) } }
