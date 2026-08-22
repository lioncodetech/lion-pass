import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct MacVaultView: View {
    @EnvironmentObject private var vault: VaultService
    @AppStorage(LionPreferenceKey.accountDisplayStyle) private var accountDisplayStyle = AccountDisplayStyle.titles.rawValue
    @AppStorage(LionPreferenceKey.detectCompromisedPasswords) private var detectCompromisedPasswords = true
    @State private var selection: Set<UUID> = []
    @State private var query = ""
    @State private var kind: VaultItemKind?
    @State private var category: String?
    @State private var favoritesOnly = false
    @State private var collection = "all"
    @State private var sortOrder = "title"
    @State private var editing: VaultItem?
    @State private var showGenerator = false
    @State private var exporting = false
    @State private var exportingPasswords = false
    @State private var showPasswordExportWarning = false
    @State private var importingPasswords = false
    @State private var passwordExportItems: [VaultItem] = []
    @State private var showNewGroup = false
    @State private var newGroupName = ""
    @State private var commandError: String?
    @State private var typesExpanded = false
    @State private var categoriesExpanded = false

    private var items: [VaultItem] {
        let allItems = vault.payload?.items ?? []
        return allItems
            .filter {
                (collection == "deleted" ? $0.deletedAt != nil : $0.deletedAt == nil)
                    && (collection != "security" || PasswordSecurityAudit.warning(for: $0, in: allItems) != nil)
                    && (kind == nil || $0.kind == kind)
                    && (category == nil || $0.category == category)
                    && (!favoritesOnly || $0.isFavorite)
                    && (query.isEmpty || $0.matches(query))
            }
            .sorted {
                if sortOrder == "recent" { return $0.updatedAt > $1.updatedAt }
                if sortOrder == "oldest" { return $0.updatedAt < $1.updatedAt }
                if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    private var allItemsSelected: Bool {
        collection == "all" && kind == nil && category == nil && !favoritesOnly
    }

    var body: some View {
        NavigationSplitView {
            List {
                Button { resetFilters() } label: {
                    Label("Todos os itens", systemImage: "tray.full.fill")
                }
                .buttonStyle(LionSidebarButtonStyle(isSelected: allItemsSelected))
                Button {
                    resetFilters()
                    favoritesOnly = true
                } label: {
                    Label("Favoritos", systemImage: "star.fill")
                }
                .buttonStyle(LionSidebarButtonStyle(isSelected: favoritesOnly))
                Button { showCollection("security") } label: {
                    HStack {
                        Label("Segurança", systemImage: "exclamationmark.shield.fill")
                        Spacer()
                        Text("\(PasswordSecurityAudit.vulnerableCount(in: vault.payload?.items ?? []))")
                            .font(.caption.monospacedDigit())
                    }
                }
                .buttonStyle(LionSidebarButtonStyle(isSelected: collection == "security"))
                Button { showCollection("deleted") } label: {
                    HStack {
                        Label("Apagados", systemImage: "trash.fill")
                        Spacer()
                        Text("\((vault.payload?.items ?? []).filter { $0.deletedAt != nil }.count)")
                            .font(.caption.monospacedDigit())
                    }
                }
                .buttonStyle(LionSidebarButtonStyle(isSelected: collection == "deleted"))
                Section {
                    DisclosureGroup(isExpanded: $typesExpanded) {
                        ForEach(VaultItemKind.allCases) { value in
                            Button {
                                resetFilters()
                                kind = value
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
                                resetFilters()
                                category = value
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
            .listStyle(.sidebar)
            .navigationTitle("Lion")
        } content: {
            contentColumn
        } detail: {
            if selection.count == 1,
               let id = selection.first,
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
                        Button(value.title) { createItem(of: value) }
                    }
                } label: {
                    Label("Novo item", systemImage: "plus")
                }
                Button(action: exportVisibleOrSelectedPasswords) {
                    Label("Compartilhar", systemImage: "square.and.arrow.up")
                }
                Button { openSettingsWindow() } label: {
                    Label("Configurações", systemImage: "gear")
                }
                Button { vault.lockVault() } label: {
                    Label("Bloquear", systemImage: "lock.fill")
                }
            }
        }
        .onReceive(LionCommandCenter.shared.commands, perform: handleMenuCommand)
        .sheet(item: $editing) { MacItemEditor(item: $0) }
        .sheet(isPresented: $showGenerator) { MacGeneratorView() }
        .fileExporter(
            isPresented: $exporting,
            document: MacVaultDocument(data: (try? vault.encryptedData()) ?? Data()),
            contentType: .lionVault,
            defaultFilename: "backup.lionvault"
        ) { _ in }
        .fileExporter(
            isPresented: $exportingPasswords,
            document: PasswordCSVDocument(items: passwordExportItems),
            contentType: .commaSeparatedText,
            defaultFilename: "lion-pass-passwords.csv"
        ) { handlePasswordExport($0) }
        .fileImporter(
            isPresented: $importingPasswords,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            onCompletion: importPasswords
        )
        .alert("Novo grupo local", isPresented: $showNewGroup) {
            TextField("Nome do grupo", text: $newGroupName)
            Button("Cancelar", role: .cancel) { newGroupName = "" }
            Button("Criar", action: createLocalGroup)
        } message: {
            Text("O grupo será criado como uma categoria local e poderá ser compartilhado por exportação.")
        }
        .alert("Exportar senhas sem criptografia", isPresented: $showPasswordExportWarning) {
            Button("Cancelar", role: .cancel) {
                passwordExportItems = []
            }
            Button("Continuar", role: .destructive) {
                exportingPasswords = true
            }
        } message: {
            Text("O arquivo CSV conterá logins e senhas em texto simples. Qualquer pessoa com acesso ao arquivo poderá lê-los. Deseja continuar?")
        }
        .alert("Não foi possível concluir", isPresented: commandErrorPresented) {
            Button("OK") { commandError = nil }
        } message: {
            Text(commandError ?? "Erro desconhecido")
        }
    }

    private var contentColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(collectionTitle).font(.headline)
                    Text("\(items.count) item(ns)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Título") { sortOrder = "title" }
                    Button("Mais recentes") { sortOrder = "recent" }
                    Button("Mais antigos") { sortOrder = "oldest" }
                } label: {
                    Label("Ordenar", systemImage: "arrow.up.arrow.down")
                }
                .menuStyle(.borderlessButton)
                Menu {
                    ForEach(VaultItemKind.allCases) { value in
                        Button(value.title) { createItem(of: value) }
                    }
                } label: {
                    Label("Novo", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            Divider()
            itemList
        }
        .searchable(text: $query, prompt: "Pesquisar…")
        .navigationTitle(vault.payload?.name ?? "Meu cofre")
    }

    private var itemList: some View {
        List(items, selection: $selection) { item in
            HStack {
                Text(displayInitial(for: item))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color(nsColor: .systemGray), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading) {
                    Text(accountPrimaryText(for: item)).fontWeight(.semibold)
                    Text(accountSecondaryText(for: item))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if detectCompromisedPasswords,
                   PasswordSecurityAudit.warning(for: item, in: vault.payload?.items ?? []) != nil {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                        .help("Esta credencial precisa de atenção")
                } else if item.isFavorite {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                }
            }
            .tag(item.id)
            .contextMenu { itemContextMenu(item) }
        }
        .tint(.lionViolet)
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("Nenhum item", systemImage: "lock.square")
            }
        }
    }

    private func openSettingsWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private func displayInitial(for item: VaultItem) -> String {
        let value = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "?" : String(value.prefix(1)).uppercased()
    }

    @ViewBuilder
    private func itemContextMenu(_ item: VaultItem) -> some View {
        if item.deletedAt == nil {
            if item.kind == .login {
                Button("Copiar usuário") { ClipboardService.shared.copy(item.username) }
                    .disabled(item.username.isEmpty)
                Button("Copiar senha") { ClipboardService.shared.copy(item.password) }
                    .disabled(item.password.isEmpty)
                Button("Copiar site") { ClipboardService.shared.copy(item.website) }
                    .disabled(item.website.isEmpty)
                Button("Abrir no navegador") {
                    if let url = normalizedURL(item.website) { NSWorkspace.shared.open(url) }
                }
                .disabled(normalizedURL(item.website) == nil)
                Divider()
            }
            Button("Editar") { editing = item }
            Button("Mover para Apagados", role: .destructive) { try? vault.delete(ids: [item.id]) }
        } else {
            Button("Restaurar") { try? vault.restore(ids: [item.id]) }
            Button("Apagar definitivamente", role: .destructive) {
                try? vault.permanentlyDelete(ids: [item.id])
                selection.remove(item.id)
            }
        }
    }

    private func normalizedURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else { return nil }
        return url
    }

    private var collectionTitle: String {
        if collection == "security" { return "Segurança" }
        if collection == "deleted" { return "Apagados" }
        if favoritesOnly { return "Favoritos" }
        if let category { return category }
        if let kind { return kind.title }
        return "Todos os itens"
    }

    private var commandErrorPresented: Binding<Bool> {
        Binding(
            get: { commandError != nil },
            set: { presented in if !presented { commandError = nil } }
        )
    }

    private func resetFilters() {
        kind = nil
        category = nil
        favoritesOnly = false
        query = ""
        collection = "all"
    }

    private func createItem(of kind: VaultItemKind) {
        var item = VaultItem()
        item.kind = kind
        item.category = defaultCategory(for: kind)
        editing = item
    }

    private func exportVisibleOrSelectedPasswords() {
        let candidateIDs = selection.isEmpty ? Set(items.map(\.id)) : selection
        requestPasswordExport((vault.payload?.items ?? []).filter {
            candidateIDs.contains($0.id) && $0.deletedAt == nil && $0.kind == .login
        })
    }

    private func requestPasswordExport(_ candidates: [VaultItem]) {
        passwordExportItems = candidates
        if candidates.isEmpty {
            commandError = "Selecione ao menos uma credencial de login para compartilhar."
            passwordExportItems = []
        } else {
            showPasswordExportWarning = true
        }
    }

    private func showCollection(_ requested: String) {
        kind = nil
        category = nil
        favoritesOnly = false
        collection = requested
        switch requested {
        case "logins": kind = .login; collection = "all"
        case "cards": kind = .card; collection = "all"
        case "notes": kind = .secureNote; collection = "all"
        case "wifi": category = "Wi-Fi"; collection = "all"
        default: break
        }
        selection.removeAll()
    }

    private func selectedItem() -> VaultItem? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return vault.payload?.items.first { $0.id == id }
    }

    private func copySelected(_ keyPath: KeyPath<VaultItem, String>) {
        guard let value = selectedItem()?[keyPath: keyPath], !value.isEmpty else { return }
        ClipboardService.shared.copy(value)
    }

    private func editSelected() {
        guard let item = selectedItem(), item.deletedAt == nil else { return }
        editing = item
    }

    private func deleteSelected() {
        guard !selection.isEmpty else { return }
        do {
            if collection == "deleted" {
                try vault.permanentlyDelete(ids: selection)
            } else {
                try vault.delete(ids: selection)
            }
            selection.removeAll()
        } catch { commandError = error.localizedDescription }
    }

    private func handleMenuCommand(_ command: LionMenuCommand) {
        switch command {
        case .newItem:
            editing = VaultItem()
        case .newGroup:
            showNewGroup = true
        case .importPasswords:
            importingPasswords = true
        case .exportAllPasswords:
            requestPasswordExport((vault.payload?.items ?? []).filter {
                $0.deletedAt == nil && $0.kind == .login
            })
        case .exportSelectedPasswords:
            requestPasswordExport((vault.payload?.items ?? []).filter {
                selection.contains($0.id) && $0.deletedAt == nil && $0.kind == .login
            })
        case .exportVault:
            exporting = true
        case .copyUsername:
            copySelected(\.username)
        case .copyPassword:
            copySelected(\.password)
        case .copyWebsite:
            copySelected(\.website)
        case .editCurrent:
            editSelected()
        case .deleteSelected:
            deleteSelected()
        case .selectAll:
            selection = Set(items.map(\.id))
        case .find:
            NSApplication.shared.sendAction(#selector(NSSearchField.selectText(_:)), to: nil, from: nil)
        case let .showCollection(requested):
            showCollection(requested)
        case let .sort(order):
            sortOrder = order
        }
    }

    private func handlePasswordExport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
            passwordExportItems = []
        } catch {
            commandError = error.localizedDescription
        }
    }

    private func importPasswords(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            if let size = values.fileSize, size > PasswordCSVCodec.maximumImportBytes {
                throw PasswordCSVCodec.CodecError.fileTooLarge
            }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            try vault.importItems(try PasswordCSVCodec.decode(data))
        } catch { commandError = error.localizedDescription }
    }

    private func createLocalGroup() {
        do {
            try vault.addCategory(newGroupName)
            newGroupName = ""
        } catch { commandError = error.localizedDescription }
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

    private func accountPrimaryText(for item: VaultItem) -> String {
        switch AccountDisplayStyle(rawValue: accountDisplayStyle) ?? .titles {
        case .titles: item.title.isEmpty ? "Sem título" : item.title
        case .websites: item.website.isEmpty ? (item.title.isEmpty ? "Sem site" : item.title) : item.website
        case .usernames: item.username.isEmpty ? (item.title.isEmpty ? "Sem usuário" : item.title) : item.username
        }
    }

    private func accountSecondaryText(for item: VaultItem) -> String {
        switch AccountDisplayStyle(rawValue: accountDisplayStyle) ?? .titles {
        case .titles: item.username.isEmpty ? item.website : item.username
        case .websites: item.username.isEmpty ? item.title : item.username
        case .usernames: item.website.isEmpty ? item.title : item.website
        }
    }
}

struct MacItemDetail: View {
    private struct CopyConfirmation: Identifiable, Equatable {
        let id = UUID()
        let message: String
    }

    let item: VaultItem
    let edit: () -> Void
    @EnvironmentObject private var vault: VaultService
    @Environment(\.openURL) private var openURL
    @AppStorage(LionPreferenceKey.detectCompromisedPasswords) private var detectCompromisedPasswords = true
    @State private var reveal = false
    @State private var revealedHistory: Set<UUID> = []
    @State private var hoveredCopyRow: String?
    @State private var copyConfirmation: CopyConfirmation?
    @State private var showingWebsiteActions = false

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Text(displayInitial)
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 74, height: 74)
                        .background(Color(nsColor: .systemGray), in: RoundedRectangle(cornerRadius: 14))
                    Text(item.title).font(.largeTitle.bold())
                    Text(item.category).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            if item.kind == .login {
                Section("Credenciais") {
                    copyableRow("Usuário", value: item.username)
                    secretRow("Senha", value: item.password)
                    websiteRow(item.website)
                    copyableRow("E-mail", value: item.email)
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
                            Text("A senha não é curta, não aparece na lista local de senhas muito comprometidas e não está sendo reutilizada em outra conta do cofre.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
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
                        HStack(spacing: 16) {
                            Text(revision.changedAt.formatted(date: .abbreviated, time: .shortened))
                            Spacer()
                            Text(revealedHistory.contains(revision.id) ? revision.password : "••••••••")
                                .font(.body.monospaced())
                        }
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button(revealedHistory.contains(revision.id) ? "Ocultar senha" : "Mostrar senha") {
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
        .overlay(alignment: .top) {
            if let copyConfirmation {
                Label(copyConfirmation.message, systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .overlay {
                        Capsule().stroke(.quaternary, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task(id: copyConfirmation?.id) {
            guard copyConfirmation != nil else { return }
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                copyConfirmation = nil
            }
        }
        .toolbar { Button("Editar", action: edit) }
        .onDisappear {
            reveal = false
            revealedHistory.removeAll()
            hoveredCopyRow = nil
            copyConfirmation = nil
            showingWebsiteActions = false
        }
    }

    private func secretRow(_ label: String, value: String) -> some View {
        LabeledContent(label) {
            Text(reveal ? value : "••••••••••••")
                .font(.body.monospaced())
                .privacySensitive()
                .padding(.trailing, 24)
                .overlay(alignment: .trailing) {
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .opacity(hoveredCopyRow == label && !value.isEmpty ? 1 : 0)
                        .accessibilityHidden(true)
                }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(hoveredCopyRow == label ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .onHover { hovering in
            hoveredCopyRow = hovering ? label : (hoveredCopyRow == label ? nil : hoveredCopyRow)
        }
        .onTapGesture { copy(value, confirmation: "Senha copiada") }
        .help(value.isEmpty ? "Sem valor para copiar" : "Clique para copiar a senha")
        .contextMenu {
            Button(reveal ? "Ocultar senha" : "Mostrar senha") { reveal.toggle() }
            Button("Copiar") { copy(value, confirmation: "Senha copiada") }
                .disabled(value.isEmpty)
        }
    }

    private func copyableRow(_ label: String, value: String) -> some View {
        LabeledContent(label) {
            Text(value)
                .privacySensitive()
                .padding(.trailing, 24)
                .overlay(alignment: .trailing) {
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .opacity(hoveredCopyRow == label && !value.isEmpty ? 1 : 0)
                        .accessibilityHidden(true)
                }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(hoveredCopyRow == label ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .onHover { hovering in
            hoveredCopyRow = hovering ? label : (hoveredCopyRow == label ? nil : hoveredCopyRow)
        }
        .onTapGesture { copy(value, confirmation: "\(label) copiado") }
        .help(value.isEmpty ? "Sem valor para copiar" : "Clique para copiar \(label.lowercased())")
        .contextMenu {
            Button("Copiar") { copy(value, confirmation: "\(label) copiado") }
                .disabled(value.isEmpty)
        }
    }

    private func copy(_ value: String, confirmation message: String) {
        guard !value.isEmpty else { return }
        ClipboardService.shared.copy(value)
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            copyConfirmation = CopyConfirmation(message: message)
        }
    }

    private func websiteRow(_ value: String) -> some View {
        LabeledContent("Site") {
            Text(value)
                .lineLimit(1)
                .padding(.trailing, 24)
                .overlay(alignment: .trailing) {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .opacity(hoveredCopyRow == "Site" && !value.isEmpty ? 1 : 0)
                        .accessibilityHidden(true)
                }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(hoveredCopyRow == "Site" ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .onHover { hovering in
            hoveredCopyRow = hovering ? "Site" : (hoveredCopyRow == "Site" ? nil : hoveredCopyRow)
        }
        .onTapGesture {
            guard !value.isEmpty else { return }
            showingWebsiteActions = true
        }
        .help(value.isEmpty ? "Nenhum site cadastrado" : "Clique para ver as opções do site")
        .popover(isPresented: $showingWebsiteActions, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 2) {
                websiteAction("Abrir site", systemImage: "safari") {
                    showingWebsiteActions = false
                    if let url = normalizedURL(value) { openURL(url) }
                }
                .disabled(normalizedURL(value) == nil)

                websiteAction("Copiar site", systemImage: "doc.on.doc") {
                    showingWebsiteActions = false
                    copy(value, confirmation: "Site copiado")
                }

                Divider().padding(.vertical, 2)

                websiteAction("Editar site", systemImage: "pencil") {
                    showingWebsiteActions = false
                    edit()
                }
            }
            .padding(8)
            .frame(minWidth: 180)
        }
        .contextMenu {
            Button("Copiar site") { copy(value, confirmation: "Site copiado") }
                .disabled(value.isEmpty)
            Button {
                if let url = normalizedURL(value) { openURL(url) }
            } label: {
                Label("Abrir no navegador", systemImage: "arrow.up.right.square")
            }
            .disabled(normalizedURL(value) == nil)
            Divider()
            Button("Editar site", action: edit)
        }
    }

    private func websiteAction(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var displayInitial: String {
        let value = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "?" : String(value.prefix(1)).uppercased()
    }

    private func normalizedURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else { return nil }
        return url
    }

}

struct MacItemEditor: View {
    @EnvironmentObject private var vault: VaultService
    @Environment(\.dismiss) private var dismiss
    @State var item: VaultItem
    @State private var error: String?
    @AppStorage(LionPreferenceKey.suggestStrongPasswords) private var suggestStrongPasswords = true

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
                    HStack {
                        SecureField("Senha", text: $item.password)
                        if suggestStrongPasswords {
                            Button {
                                item.password = (try? SecurePasswordGenerator.password(options: PasswordOptions())) ?? item.password
                            } label: {
                                Label("Sugerir senha forte", systemImage: "wand.and.stars")
                            }
                            .buttonStyle(LionCompactActionButtonStyle())
                        }
                    }
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
    private struct Snapshot {
        let language: String
        let appearance: String
        let autoLock: String
        let clipboard: Int
        let privacyCover: Bool
        let accountDisplayStyle: String
        let passwordSaveBehavior: String
        let showInMenuBar: Bool
        let detectCompromisedPasswords: Bool
        let suggestStrongPasswords: Bool
        let automaticPasskeyUpgrades: Bool
        let allowContactingWebsites: Bool
        let automaticUpdates: Bool
        let receiveBetaUpdates: Bool
        let biometrics: Bool
        let passwordHistoryEnabled: Bool
    }
    @EnvironmentObject private var vault: VaultService
    @Environment(\.dismiss) private var dismiss
    @AppStorage(LionPreferenceKey.language) private var language = "pt-BR"
    @AppStorage(LionPreferenceKey.appearance) private var appearance = "system"
    @AppStorage(LionPreferenceKey.autoLock) private var autoLock = AutoLockDuration.immediately.rawValue
    @AppStorage(LionPreferenceKey.clipboard) private var clipboard = 30
    @AppStorage(LionPreferenceKey.privacyCover) private var privacyCover = true
    @AppStorage(LionPreferenceKey.accountDisplayStyle) private var accountDisplayStyle = AccountDisplayStyle.titles.rawValue
    @AppStorage(LionPreferenceKey.passwordSaveBehavior) private var passwordSaveBehavior = PasswordSaveBehavior.ask.rawValue
    @AppStorage(LionPreferenceKey.showInMenuBar) private var showInMenuBar = false
    @AppStorage(LionPreferenceKey.detectCompromisedPasswords) private var detectCompromisedPasswords = true
    @AppStorage(LionPreferenceKey.suggestStrongPasswords) private var suggestStrongPasswords = true
    @AppStorage(LionPreferenceKey.automaticPasskeyUpgrades) private var automaticPasskeyUpgrades = false
    @AppStorage(LionPreferenceKey.allowContactingWebsites) private var allowContactingWebsites = false
    @AppStorage(LionPreferenceKey.automaticUpdates) private var automaticUpdates = true
    @AppStorage(LionPreferenceKey.receiveBetaUpdates) private var receiveBetaUpdates = false
    @State private var biometrics = BiometricKeyStore().exists
    @State private var showChangePassword = false
    @State private var showCategories = false
    @State private var showRestore = false
    @State private var recoveryKey: String?
    @State private var message: String?
    @State private var error: String?
    @State private var snapshot: Snapshot?

    var body: some View {
        VStack(spacing: 0) {
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
                Text("Esta preferência é usada pelo AutoFill; credenciais criadas manualmente continuam sob seu controle.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Mostrar Lion Pass na barra de menus", isOn: $showInMenuBar)
                Toggle("Detectar senhas comprometidas", isOn: $detectCompromisedPasswords)
                if detectCompromisedPasswords {
                    let count = PasswordSecurityAudit.vulnerableCount(in: vault.payload?.items ?? [])
                    Text(count == 0 ? "Nenhuma senha vulnerável detectada localmente." : "\(count) senha(s) precisam de atenção.")
                        .font(.caption)
                        .foregroundStyle(count == 0 ? Color.secondary : Color.orange)
                }
                Toggle("Sugerir senhas fortes", isOn: $suggestStrongPasswords)
                Toggle("Permitir upgrades automáticos para passkeys", isOn: $automaticPasskeyUpgrades)
                    .disabled(true)
                Text("Passkeys automáticas exigem uma extensão de provedor e assinatura Apple Developer; esta instalação pessoal mantém a opção desativada.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Permitir contato com sites", isOn: $allowContactingWebsites)
                Text("Autoriza futuras consultas de nomes e ícones. O Lion Pass não envia senhas e não faz consultas em segundo plano nesta versão.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
            if let message { Text(message).foregroundStyle(.green) }
            if let error { Text(error).foregroundStyle(.red) }
Section("Atualizações") {
    Toggle("Atualizações automáticas", isOn: $automaticUpdates)
    Toggle("Receber versões beta", isOn: $receiveBetaUpdates)
    LabeledContent("Versão atual", value: currentVersion)
    HStack {
        Button("Verificar atualização") { openReleases(beta: receiveBetaUpdates) }
        Button("Voltar para a última versão estável") { openStableRelease() }
    }
}
            Section("Sobre") {
                Link("Lion Code Technology", destination: URL(string: "https://lioncodetech.com.br/")!)
            }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { cancelChanges() }
                    .keyboardShortcut(.cancelAction)
                Button("Salvar") { saveChanges() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.bar)
        }
        .frame(width: 700, height: settingsWindowHeight)
        .onAppear(perform: captureSnapshot)
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

    private var settingsWindowHeight: CGFloat {
        let visibleHeight = NSScreen.main?.visibleFrame.height ?? 720
        return min(680, max(520, visibleHeight - 96))
    }

private var currentVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
}

private func captureSnapshot() {
    guard snapshot == nil else { return }
    snapshot = Snapshot(
        language: language,
        appearance: appearance,
        autoLock: autoLock,
        clipboard: clipboard,
        privacyCover: privacyCover,
        accountDisplayStyle: accountDisplayStyle,
        passwordSaveBehavior: passwordSaveBehavior,
        showInMenuBar: showInMenuBar,
        detectCompromisedPasswords: detectCompromisedPasswords,
        suggestStrongPasswords: suggestStrongPasswords,
        automaticPasskeyUpgrades: automaticPasskeyUpgrades,
        allowContactingWebsites: allowContactingWebsites,
        automaticUpdates: automaticUpdates,
        receiveBetaUpdates: receiveBetaUpdates,
        biometrics: biometrics,
        passwordHistoryEnabled: vault.payload?.passwordHistoryEnabled ?? true
    )
}

private func cancelChanges() {
    guard let snapshot else { closeSettingsWindow(); return }
    language = snapshot.language
    appearance = snapshot.appearance
    autoLock = snapshot.autoLock
    clipboard = snapshot.clipboard
    privacyCover = snapshot.privacyCover
    accountDisplayStyle = snapshot.accountDisplayStyle
    passwordSaveBehavior = snapshot.passwordSaveBehavior
    showInMenuBar = snapshot.showInMenuBar
    detectCompromisedPasswords = snapshot.detectCompromisedPasswords
    suggestStrongPasswords = snapshot.suggestStrongPasswords
    automaticPasskeyUpgrades = snapshot.automaticPasskeyUpgrades
    allowContactingWebsites = snapshot.allowContactingWebsites
    automaticUpdates = snapshot.automaticUpdates
    receiveBetaUpdates = snapshot.receiveBetaUpdates
    if biometrics != snapshot.biometrics { updateBiometrics(snapshot.biometrics) }
    if vault.payload?.passwordHistoryEnabled != snapshot.passwordHistoryEnabled {
        perform { try vault.setPasswordHistoryEnabled(snapshot.passwordHistoryEnabled) }
    }
    closeSettingsWindow()
}

private func saveChanges() {
    snapshot = nil
    closeSettingsWindow()
}

private func closeSettingsWindow() {
    dismiss()
    NSApplication.shared.keyWindow?.close()
}

private func openReleases(beta: Bool) {
    let path = beta ? "releases" : "releases/latest"
    guard let url = URL(string: "https://github.com/lioncodetech/lion-pass/" + path) else { return }
    NSWorkspace.shared.open(url)
}

private func openStableRelease() {
    guard let url = URL(string: "https://github.com/lioncodetech/lion-pass/releases/latest") else { return }
    NSWorkspace.shared.open(url)
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

struct PasswordCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] = [.commaSeparatedText]
    var data: Data

    init(items: [VaultItem]) {
        data = PasswordCSVCodec.encode(items)
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum PasswordCSVCodec {
    static let maximumImportBytes = 25 * 1024 * 1024
    private static let maximumRows = 100_000
    private static let maximumColumns = 256
    private static let maximumFieldCharacters = 1_048_576

    enum CodecError: LocalizedError {
        case fileTooLarge
        case tooManyRows
        case tooManyColumns
        case fieldTooLarge
        case malformedQuotes

        var errorDescription: String? {
            switch self {
            case .fileTooLarge: "O arquivo CSV excede o limite de 25 MB."
            case .tooManyRows: "O arquivo CSV excede o limite de 100.000 linhas."
            case .tooManyColumns: "O arquivo CSV contém colunas demais."
            case .fieldTooLarge: "Um campo do CSV excede o limite de 1 MB."
            case .malformedQuotes: "O arquivo CSV contém um campo entre aspas incompleto."
            }
        }
    }
    private static let headers = ["title", "username", "password", "website", "email", "category", "notes"]

    static func encode(_ items: [VaultItem]) -> Data {
        let rows = [headers] + items.map {
            [$0.title, $0.username, $0.password, $0.website, $0.email, $0.category, $0.notes]
        }
        let text = rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n")
        return Data(text.utf8)
    }

    static func decode(_ data: Data) throws -> [VaultItem] {
        guard data.count <= maximumImportBytes else { throw CodecError.fileTooLarge }
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        let rows = try parse(text)
        guard let first = rows.first else { return [] }
        let normalizedHeaders = first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase }
        let hasHeader = normalizedHeaders.contains("password") || normalizedHeaders.contains("senha")
        var index: [String: Int] = [:]
        for (position, name) in normalizedHeaders.enumerated() where index[name] == nil {
            index[name] = position
        }

        func value(_ row: [String], names: [String], fallback: Int) -> String {
            let position = names.compactMap { index[$0] }.first ?? fallback
            return row.indices.contains(position) ? row[position] : ""
        }

        return rows.dropFirst(hasHeader ? 1 : 0).compactMap { row in
            guard row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return nil }
            var item = VaultItem()
            item.kind = .login
            item.title = value(row, names: ["title", "titulo", "título", "name", "nome"], fallback: 0)
            item.username = value(row, names: ["username", "usuario", "usuário", "login"], fallback: 1)
            item.password = value(row, names: ["password", "senha"], fallback: 2)
            item.website = value(row, names: ["website", "site", "url"], fallback: 3)
            item.email = value(row, names: ["email", "e-mail"], fallback: 4)
            item.category = value(row, names: ["category", "categoria"], fallback: 5)
            if item.category.isEmpty { item.category = "Logins" }
            item.notes = value(row, names: ["notes", "notas", "observacoes", "observações"], fallback: 6)
            if item.title.isEmpty { item.title = item.website.isEmpty ? item.username : item.website }
            return item
        }
    }

    private static func escape(_ value: String) -> String {
        let safeValue = neutralizeFormula(value)
        return "\"" + safeValue.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func neutralizeFormula(_ value: String) -> String {
        let dangerousPrefixes: Set<Character> = [
            "=", "+", "-", "@", "＝", "＋", "－", "＠", "﹢", "﹣", "﹦", "﹫"
        ]
        for character in value {
            if character.isWhitespace { continue }
            return dangerousPrefixes.contains(character) ? "'" + value : value
        }
        return value
    }

    private static func parse(_ text: String) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var fieldCharacters = 0
        var quoted = false
        var index = text.startIndex

        func appendCharacter(_ character: Character) throws {
            guard fieldCharacters < maximumFieldCharacters else { throw CodecError.fieldTooLarge }
            field.append(character)
            fieldCharacters += 1
        }

        func finishField() throws {
            guard row.count < maximumColumns else { throw CodecError.tooManyColumns }
            row.append(field)
            field = ""
            fieldCharacters = 0
        }

        func finishRow() throws {
            try finishField()
            guard rows.count < maximumRows else { throw CodecError.tooManyRows }
            rows.append(row)
            row = []
        }

        while index < text.endIndex {
            let character = text[index]
            if character == "\"" {
                let next = text.index(after: index)
                if quoted, next < text.endIndex, text[next] == "\"" {
                    try appendCharacter("\"")
                    index = next
                } else {
                    quoted.toggle()
                }
            } else if character == ",", !quoted {
                try finishField()
            } else if (character == "\n" || character == "\r"), !quoted {
                if character == "\r" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\n" { index = next }
                }
                try finishRow()
            } else {
                try appendCharacter(character)
            }
            index = text.index(after: index)
        }
        guard quoted == false else { throw CodecError.malformedQuotes }
        if !field.isEmpty || !row.isEmpty {
            try finishRow()
        }
        return rows
    }
}
