import SwiftUI

struct VaultHomeView: View {
    @EnvironmentObject var vault: VaultService; @State private var selection: UUID?; @State private var query = ""; @State private var kind: VaultItemKind?; @State private var favoriteOnly = false; @State private var editorItem: VaultItem?; @State private var showSettings = false; @State private var showGenerator = false
    private var items: [VaultItem] { (vault.payload?.items ?? []).filter { (!favoriteOnly || $0.isFavorite) && (kind == nil || $0.kind == kind) && (query.isEmpty || $0.matches(query)) }.sorted { if $0.isFavorite != $1.isFavorite { return $0.isFavorite }; return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending } }
    var body: some View {
        NavigationSplitView { List(selection: $selection) {
            Section { Button { kind = nil; favoriteOnly = false } label: { Label("Todos os itens", systemImage: "tray.full.fill") }; Button { kind = nil; favoriteOnly = true } label: { Label("Favoritos", systemImage: "star.fill") } }
            Section("Categorias") { ForEach(VaultItemKind.allCases) { value in Button { kind = value; query = ""; favoriteOnly = false } label: { Label(value.title, systemImage: value.symbol) } } }
        }.navigationTitle("Lion").toolbar { ToolbarItem(placement: .bottomBar) { Button { showSettings = true } label: { Label("Configurações", systemImage: "gear") } } }
        } content: { List(items, selection: $selection) { item in VaultRow(item: item).tag(item.id).swipeActions { Button(role: .destructive) { try? vault.delete(ids: [item.id]) } label: { Label("Apagar", systemImage: "trash") } } }
            .navigationTitle(kind?.title ?? "Meu cofre").searchable(text: $query, prompt: "Pesquisar senhas…")
            .overlay { if items.isEmpty { ContentUnavailableView("Nenhum item", systemImage: "lock.square", description: Text("Toque em + Novo para começar.")) } }
            .toolbar { ToolbarItemGroup(placement: .primaryAction) { Button { showGenerator = true } label: { Image(systemName: "wand.and.stars") }; Menu { ForEach(VaultItemKind.allCases) { value in Button { var item = VaultItem(); item.kind = value; item.category = value.title; editorItem = item } label: { Label(value.title, systemImage: value.symbol) } } } label: { Label("Novo", systemImage: "plus") } } }
        } detail: { if let id = selection, let item = vault.payload?.items.first(where: { $0.id == id }) { ItemDetailView(item: item) { editorItem = item } } else { ContentUnavailableView("Selecione um item", systemImage: "lock.shield") } }
        .sheet(item: $editorItem) { ItemEditorView(item: $0) }.sheet(isPresented: $showSettings) { NavigationStack { SettingsView() } }.sheet(isPresented: $showGenerator) { NavigationStack { GeneratorView() } }
    }
}

struct VaultRow: View { let item: VaultItem; var body: some View { HStack(spacing: 12) { Image(systemName: item.kind.symbol).foregroundStyle(.white).frame(width: 36, height: 36).background(.indigo.gradient, in: RoundedRectangle(cornerRadius: 10)); VStack(alignment: .leading) { Text(item.title.isEmpty ? "Sem título" : item.title).fontWeight(.semibold); Text(item.username.isEmpty ? item.website : item.username).font(.caption).foregroundStyle(.secondary).lineLimit(1) }; Spacer(); if item.isFavorite { Image(systemName: "star.fill").foregroundStyle(.yellow).accessibilityLabel("Favorito") } } } }

struct ItemDetailView: View {
    let item: VaultItem; let edit: () -> Void; @State private var showPassword = false
    var body: some View { List { Section { HStack { Image(systemName: item.kind.symbol).font(.title).foregroundStyle(.indigo); VStack(alignment: .leading) { Text(item.title).font(.title2.bold()); Text(item.category).foregroundStyle(.secondary) } } }
        if item.kind == .login { Section("Credenciais") { ValueRow(label: "Usuário", value: item.username); HStack { VStack(alignment: .leading) { Text("Senha").font(.caption).foregroundStyle(.secondary); Text(showPassword ? item.password : String(repeating: "•", count: 12)).monospaced() }; Spacer(); Button(showPassword ? "Ocultar" : "Mostrar") { showPassword.toggle() }; Button { ClipboardService.shared.copy(item.password, clearAfter: 30) } label: { Image(systemName: "doc.on.doc") } }; ValueRow(label: "Site", value: item.website); ValueRow(label: "E-mail", value: item.email) } }
        if item.kind == .card { Section("Cartão") { ValueRow(label: "Titular", value: item.cardholder); ValueRow(label: "Número", value: showPassword ? item.cardNumber : "•••• •••• •••• " + item.cardNumber.suffix(4)); ValueRow(label: "Validade", value: item.expiry); ValueRow(label: "Banco", value: item.bank) } }
        if !item.notes.isEmpty { Section("Notas") { Text(item.notes) } }
        if !item.customFields.isEmpty { Section("Campos personalizados") { ForEach(item.customFields) { field in ValueRow(label: field.name, value: field.isSensitive && !showPassword ? "••••••••" : field.value) } } }
    }.navigationTitle("Detalhes").toolbar { Button("Editar", action: edit) } }
}

struct ValueRow: View { let label: String; let value: String; var body: some View { if !value.isEmpty { VStack(alignment: .leading, spacing: 3) { Text(label).font(.caption).foregroundStyle(.secondary); Text(value).textSelection(.enabled) } } } }
