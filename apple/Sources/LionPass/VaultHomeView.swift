import SwiftUI

struct VaultHomeView: View {
    @EnvironmentObject private var vault: VaultService
    @State private var selection: UUID?
    @State private var query = ""
    @State private var kind: VaultItemKind?
    @State private var category: String?
    @State private var favoriteOnly = false
    @State private var editorItem: VaultItem?
    @State private var showSettings = false
    @State private var showGenerator = false
    @State private var typesExpanded = false
    @State private var categoriesExpanded = false

    private var items: [VaultItem] {
        (vault.payload?.items ?? [])
            .filter {
                $0.deletedAt == nil
                    && (!favoriteOnly || $0.isFavorite)
                    && (kind == nil || $0.kind == kind)
                    && (category == nil || $0.category == category)
                    && (query.isEmpty || $0.matches(query))
            }
            .sorted {
                if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    private var allItemsSelected: Bool {
        kind == nil && category == nil && !favoriteOnly
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    Button { showAll() } label: {
                        Label("Todos os itens", systemImage: "tray.full.fill")
                    }
                    .buttonStyle(LionSidebarButtonStyle(isSelected: allItemsSelected))
                    Button {
                        favoriteOnly = true
                        kind = nil
                        category = nil
                    } label: {
                        Label("Favoritos", systemImage: "star.fill")
                    }
                    .buttonStyle(LionSidebarButtonStyle(isSelected: favoriteOnly))
                }
                Section {
                    DisclosureGroup(isExpanded: $typesExpanded) {
                        ForEach(VaultItemKind.allCases) { value in
                            Button {
                                kind = value
                                category = nil
                                favoriteOnly = false
                                query = ""
                            } label: {
                                Label(value.title, systemImage: value.symbol)
                            }
                            .buttonStyle(LionSidebarButtonStyle(isSelected: kind == value))
                        }
                    } label: {
                        Label("Tipos", systemImage: "square.stack.3d.up.fill")
                            .fontWeight(.semibold)
                    }
                    .tint(.lionCyan)
                }
                Section {
                    DisclosureGroup(isExpanded: $categoriesExpanded) {
                        ForEach(vault.payload?.allCategories ?? [], id: \.self) { value in
                            Button {
                                category = value
                                kind = nil
                                favoriteOnly = false
                                query = ""
                            } label: {
                                Label(value, systemImage: VaultPayload.categorySymbol(for: value))
                            }
                            .buttonStyle(LionSidebarButtonStyle(isSelected: category == value))
                        }
                    } label: {
                        Label("Categorias", systemImage: "square.grid.2x2")
                            .fontWeight(.semibold)
                    }
                    .tint(.lionCyan)
                }
            }
            .navigationTitle("Lion")
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button { showSettings = true } label: {
                        Label("Configurações", systemImage: "gear")
                    }
                }
            }
        } content: {
            List(items, selection: $selection) { item in
                VaultRow(item: item)
                    .tag(item.id)
                    .swipeActions {
                        Button(role: .destructive) {
                            try? vault.delete(ids: [item.id])
                            if selection == item.id { selection = nil }
                        } label: {
                            Label("Apagar", systemImage: "trash")
                        }
                    }
            }
            .navigationTitle(category ?? kind?.title ?? (favoriteOnly ? "Favoritos" : "Meu cofre"))
            .searchable(text: $query, prompt: "Pesquisar senhas…")
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView(
                        "Nenhum item",
                        systemImage: "lock.square",
                        description: Text("Toque em + Novo para começar.")
                    )
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { showGenerator = true } label: {
                        Image(systemName: "wand.and.stars")
                    }
                    .accessibilityLabel("Gerador de senhas")
                    Menu {
                        ForEach(VaultItemKind.allCases) { value in
                            Button {
                                var item = VaultItem()
                                item.kind = value
                                item.category = defaultCategory(for: value)
                                editorItem = item
                            } label: {
                                Label(value.title, systemImage: value.symbol)
                            }
                        }
                    } label: {
                        Label("Novo", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let id = selection,
               let item = vault.payload?.items.first(where: { $0.id == id }) {
                ItemDetailView(item: item) { editorItem = item }
            } else {
                ContentUnavailableView("Selecione um item", systemImage: "lock.shield")
            }
        }
        .sheet(item: $editorItem) { ItemEditorView(item: $0) }
        .sheet(isPresented: $showSettings) { NavigationStack { SettingsView() } }
        .sheet(isPresented: $showGenerator) { NavigationStack { GeneratorView() } }
    }

    private func showAll() {
        kind = nil
        category = nil
        favoriteOnly = false
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

struct VaultRow: View {
    let item: VaultItem
    @AppStorage(LionPreferenceKey.accountDisplayStyle) private var accountDisplayStyle = AccountDisplayStyle.titles.rawValue

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.kind.symbol)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.lionGradient, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(primaryText).fontWeight(.semibold)
                Text(secondaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if item.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Favorito")
            }
        }
    }

    private var primaryText: String {
        switch AccountDisplayStyle(rawValue: accountDisplayStyle) ?? .titles {
        case .titles: item.title.isEmpty ? "Sem título" : item.title
        case .websites: item.website.isEmpty ? (item.title.isEmpty ? "Sem site" : item.title) : item.website
        case .usernames: item.username.isEmpty ? (item.title.isEmpty ? "Sem usuário" : item.title) : item.username
        }
    }

    private var secondaryText: String {
        switch AccountDisplayStyle(rawValue: accountDisplayStyle) ?? .titles {
        case .titles: item.username.isEmpty ? item.website : item.username
        case .websites: item.username.isEmpty ? item.title : item.username
        case .usernames: item.website.isEmpty ? item.title : item.website
        }
    }
}

struct ItemDetailView: View {
    let item: VaultItem
    let edit: () -> Void
    @EnvironmentObject private var vault: VaultService
    @AppStorage(LionPreferenceKey.detectCompromisedPasswords) private var detectCompromisedPasswords = true
    @State private var showSecrets = false
    @State private var revealedHistory: Set<UUID> = []

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: item.kind.symbol)
                        .font(.title)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.lionGradient, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading) {
                        Text(item.title).font(.title2.bold())
                        Text(item.category).foregroundStyle(.secondary)
                    }
                }
            }

            if item.kind == .login {
                Section("Credenciais") {
                    CopyableValueRow(label: "Usuário", value: item.username)
                    SecretValueRow(label: "Senha", value: item.password, revealed: $showSecrets)
                    WebsiteValueRow(value: item.website)
                    CopyableValueRow(label: "E-mail", value: item.email)
                    LabeledContent(
                        "Modificado",
                        value: item.updatedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }
                if detectCompromisedPasswords {
                    Section("Segurança") {
                        if let warning = PasswordSecurityAudit.warning(for: item, in: vault.payload?.items ?? []) {
                            Label(warning, systemImage: "exclamationmark.shield.fill")
                                .foregroundStyle(.orange)
                        } else {
                            Label("Nenhum problema encontrado", systemImage: "checkmark.shield.fill")
                                .font(.headline)
                                .foregroundStyle(.green)
                            Text("A senha não é curta, não aparece na lista local de senhas muito comprometidas e não está sendo reutilizada.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if item.kind == .card {
                Section("Cartão") {
                    CopyableValueRow(label: "Titular", value: item.cardholder)
                    SecretValueRow(label: "Número", value: item.cardNumber, revealed: $showSecrets)
                    CopyableValueRow(label: "Validade", value: item.expiry)
                    SecretValueRow(label: "Código de segurança", value: item.securityCode, revealed: $showSecrets)
                    CopyableValueRow(label: "Banco", value: item.bank)
                    CopyableValueRow(label: "Bandeira", value: item.cardBrand)
                }
            }

            if !item.notes.isEmpty {
                Section(item.kind == .secureNote ? "Conteúdo" : "Notas") {
                    Text(item.notes).textSelection(.enabled).privacySensitive()
                }
            }

            if !item.tags.isEmpty {
                Section("Tags") { Text(item.tags.joined(separator: ", ")) }
            }

            if !item.customFields.isEmpty {
                Section("Campos personalizados") {
                    ForEach(item.customFields) { field in
                        if field.isSensitive {
                            SecretValueRow(label: field.name, value: field.value, revealed: $showSecrets)
                        } else {
                            CopyableValueRow(label: field.name, value: field.value)
                        }
                    }
                }
            }

            if !item.passwordHistory.isEmpty {
                Section("Histórico de senhas") {
                    ForEach(item.passwordHistory.reversed()) { revision in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(revision.changedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(revealedHistory.contains(revision.id) ? revision.password : "••••••••••••")
                                    .font(.body.monospaced())
                                    .privacySensitive()
                            }
                            Spacer()
                            Button {
                                if revealedHistory.contains(revision.id) {
                                    revealedHistory.remove(revision.id)
                                } else {
                                    revealedHistory.insert(revision.id)
                                }
                            } label: {
                                Image(systemName: revealedHistory.contains(revision.id) ? "eye.slash" : "eye")
                            }
                            .buttonStyle(LionCompactActionButtonStyle())
                            .accessibilityLabel(revealedHistory.contains(revision.id) ? "Ocultar senha anterior" : "Mostrar senha anterior")
                            Button { ClipboardService.shared.copy(revision.password) } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(LionCompactActionButtonStyle())
                            .accessibilityLabel("Copiar senha anterior")
                        }
                    }
                }
            }
        }
        .navigationTitle("Detalhes")
        .toolbar { Button("Editar", action: edit) }
        .onDisappear {
            showSecrets = false
            revealedHistory.removeAll()
        }
    }

}

struct CopyableValueRow: View {
    let label: String
    let value: String

    var body: some View {
        if !value.isEmpty {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                    Text(value).textSelection(.enabled).privacySensitive()
                }
                Spacer()
                Button { ClipboardService.shared.copy(value) } label: {
                    Label("Copiar", systemImage: "doc.on.doc")
                }
                .buttonStyle(LionCompactActionButtonStyle())
                .accessibilityLabel("Copiar \(label)")
            }
        }
    }
}

struct WebsiteValueRow: View {
    let value: String

    private var url: URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else { return nil }
        return url
    }

    var body: some View {
        if !value.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Site").font(.caption).foregroundStyle(.secondary)
                Text(value)
                    .textSelection(.enabled)
                    .lineLimit(2)
                HStack {
                    Button { ClipboardService.shared.copy(value) } label: {
                        Label("Copiar URL", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(LionCompactActionButtonStyle())
                    if let url {
                        Link(destination: url) {
                            Label("Abrir", systemImage: "arrow.up.right.square")
                        }
                        .buttonStyle(LionCompactActionButtonStyle())
                        .accessibilityHint("Abre o site no navegador padrão")
                    }
                }
            }
        }
    }
}

struct SecretValueRow: View {
    let label: String
    let value: String
    @Binding var revealed: Bool

    var body: some View {
        if !value.isEmpty {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                    Text(revealed ? value : "••••••••••••")
                        .font(.body.monospaced())
                        .privacySensitive()
                }
                Spacer()
                Button { revealed.toggle() } label: {
                    Image(systemName: revealed ? "eye.slash" : "eye")
                }
                .buttonStyle(LionCompactActionButtonStyle())
                .accessibilityLabel(revealed ? "Ocultar \(label)" : "Mostrar \(label)")
                Button { ClipboardService.shared.copy(value) } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(LionCompactActionButtonStyle())
                .accessibilityLabel("Copiar \(label)")
            }
        }
    }
}
