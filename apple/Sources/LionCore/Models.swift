import Foundation

public enum LionIdentifiers {
    public static let applicationGroup = "group.com.lioncodetech.lionpassword"
    public static let keychainAccessGroup = "com.lioncodetech.lionpassword.shared"
    public static let vaultType = "com.lioncodetech.lion-vault"
}

public enum VaultItemKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case login
    case card
    case secureNote
    case identity
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .login: LionL10n.text("Logins")
        case .card: LionL10n.text("Cartões")
        case .secureNote: LionL10n.text("Notas seguras")
        case .identity: LionL10n.text("Identidades")
        case .other: LionL10n.text("Outros")
        }
    }

    public var symbol: String {
        switch self {
        case .login: "key.fill"
        case .card: "creditcard.fill"
        case .secureNote: "lock.doc.fill"
        case .identity: "person.text.rectangle.fill"
        case .other: "square.grid.2x2.fill"
        }
    }
}

public struct CustomField: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var name = ""
    public var value = ""
    public var isSensitive = false

    public init(id: UUID = UUID(), name: String = "", value: String = "", isSensitive: Bool = false) {
        self.id = id
        self.name = name
        self.value = value
        self.isSensitive = isSensitive
    }
}

public struct PasswordRevision: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var password: String
    public var changedAt = Date()

    public init(id: UUID = UUID(), password: String, changedAt: Date = Date()) {
        self.id = id
        self.password = password
        self.changedAt = changedAt
    }
}

public struct VaultItem: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var kind: VaultItemKind = .login
    public var title = ""
    public var username = ""
    public var password = ""
    public var website = ""
    public var email = ""
    public var notes = ""
    public var category = "Logins"
    public var tags: [String] = []
    public var isFavorite = false
    public var customFields: [CustomField] = []
    public var passwordHistory: [PasswordRevision] = []
    public var cardholder = ""
    public var cardNumber = ""
    public var expiry = ""
    public var securityCode = ""
    public var bank = ""
    public var cardBrand = ""
    public var createdAt = Date()
    public var updatedAt = Date()
    public var deletedAt: Date?

    public init() {}

    public func matches(_ query: String) -> Bool {
        let foldedQuery = query.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: .current
        )
        let searchable = [title, username, website, email, category]
            .joined(separator: " ")
            .appending(" " + tags.joined(separator: " "))
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return searchable.contains(foldedQuery)
    }
}

public enum PasswordSecurityAudit {
    private static let commonlyCompromised = Set([
        "123456", "12345678", "123456789", "1234567890", "password", "password1",
        "qwerty", "qwerty123", "abc123", "111111", "000000", "admin", "letmein",
        "welcome", "iloveyou", "senha", "senha123", "changeme"
    ])

    public static func warning(for item: VaultItem, in items: [VaultItem]) -> String? {
        guard item.kind == .login, item.deletedAt == nil, !item.password.isEmpty else { return nil }
        if commonlyCompromised.contains(item.password.localizedLowercase) {
            return LionL10n.text("Esta senha aparece em listas locais de senhas muito comprometidas. Troque-a imediatamente.")
        }
        if item.password.count < 12 {
            return LionL10n.text("Esta senha é curta. Use pelo menos 12 caracteres e prefira uma senha gerada.")
        }
        let reused = items.contains {
            $0.id != item.id && $0.kind == .login && $0.deletedAt == nil
                && !$0.password.isEmpty && $0.password == item.password
        }
        if reused {
            return LionL10n.text("Esta senha está sendo reutilizada em outra conta. Use uma senha exclusiva.")
        }
        return nil
    }

    public static func vulnerableCount(in items: [VaultItem]) -> Int {
        items.filter { warning(for: $0, in: items) != nil }.count
    }
}

public struct VaultPayload: Codable, Equatable, Sendable {
    public static let defaultCategories = [
        "Logins", "E-mail", "Bancos", "Redes sociais", "Trabalho", "Compras",
        "Streaming", "Wi-Fi", "Cartões", "Notas", "Identidades", "Outros"
    ]

    public var id = UUID()
    public var name: String
    public var items: [VaultItem] = []
    public var customCategories: [String] = []
    public var createdAt = Date()
    public var modifiedAt = Date()
    public var passwordHistoryEnabled = true

    public init(name: String) {
        self.name = name
    }

    public var allCategories: [String] {
        var seen = Set<String>()
        return (Self.defaultCategories + customCategories)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.localizedLowercase).inserted }
    }

    public static func categorySymbol(for category: String) -> String {
        let normalized = category
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch normalized {
        case "logins", "login", "senhas", "senha":
            return "key.fill"
        case "e-mail", "email", "emails":
            return "envelope.fill"
        case "bancos", "banco", "financas", "financeiro":
            return "building.columns.fill"
        case "redes sociais", "rede social", "social":
            return "person.2.fill"
        case "trabalho", "profissional", "empresa":
            return "briefcase.fill"
        case "compras", "compra", "lojas", "loja":
            return "cart.fill"
        case "streaming", "filmes", "series":
            return "play.tv.fill"
        case "wi-fi", "wifi", "internet":
            return "wifi"
        case "cartoes", "cartao":
            return "creditcard.fill"
        case "notas", "nota":
            return "note.text"
        case "identidades", "identidade", "documentos", "documento":
            return "person.text.rectangle.fill"
        case "outros", "outro":
            return "square.grid.2x2.fill"
        default:
            return "folder.badge.gearshape"
        }
    }
}

public struct KDFParameters: Codable, Equatable, Sendable {
    public var algorithm = "PBKDF2-HMAC-SHA256"
    public var iterations: UInt32 = 600_000
    public var keyLength = 32

    public init(
        algorithm: String = "PBKDF2-HMAC-SHA256",
        iterations: UInt32 = 600_000,
        keyLength: Int = 32
    ) {
        self.algorithm = algorithm
        self.iterations = iterations
        self.keyLength = keyLength
    }
}

public struct VaultEnvelope: Codable, Sendable {
    public let magic: String
    public let version: Int
    public let kdf: KDFParameters
    public let salt: Data
    public let nonce: Data
    public let ciphertext: Data
    public let tag: Data
    public let keyNonce: Data?
    public let wrappedKey: Data?
    public let keyTag: Data?

    public init(
        magic: String,
        version: Int,
        kdf: KDFParameters,
        salt: Data,
        nonce: Data,
        ciphertext: Data,
        tag: Data,
        keyNonce: Data? = nil,
        wrappedKey: Data? = nil,
        keyTag: Data? = nil
    ) {
        self.magic = magic
        self.version = version
        self.kdf = kdf
        self.salt = salt
        self.nonce = nonce
        self.ciphertext = ciphertext
        self.tag = tag
        self.keyNonce = keyNonce
        self.wrappedKey = wrappedKey
        self.keyTag = keyTag
    }
}

public struct CreatedVault: Sendable {
    public let encryptedData: Data
    public let contentKey: Data
    public let recoveryKey: String
    public let envelope: VaultEnvelope
}

public struct UnlockedVault: Sendable {
    public let payload: VaultPayload
    public let contentKey: Data
    public let envelope: VaultEnvelope
}

public enum VaultError: LocalizedError, Equatable {
    case invalidFormat
    case unsupportedVersion
    case unsupportedKDF
    case invalidKDFParameters
    case wrongPasswordOrTampered
    case invalidRecoveryKey
    case truncated
    case notOpen
    case biometricsUnavailable
    case categoryAlreadyExists
    case categoryNotFound
    case cannotDeleteDefaultCategory
    case noPreviousBackup
    case verificationFailed

    public var errorDescription: String? {
        switch self {
        case .invalidFormat: LionL10n.text("O arquivo não é um cofre Lion válido.")
        case .unsupportedVersion: LionL10n.text("Esta versão do cofre ainda não é suportada.")
        case .unsupportedKDF: LionL10n.text("O algoritmo de derivação deste cofre não é suportado.")
        case .invalidKDFParameters: LionL10n.text("Os parâmetros de segurança do cofre são inválidos.")
        case .wrongPasswordOrTampered: LionL10n.text("Senha incorreta ou arquivo adulterado.")
        case .invalidRecoveryKey: LionL10n.text("A chave de recuperação é inválida ou não pertence a este cofre.")
        case .truncated: LionL10n.text("O arquivo do cofre está truncado.")
        case .notOpen: LionL10n.text("O cofre está bloqueado.")
        case .biometricsUnavailable: LionL10n.text("A autenticação biométrica não está disponível.")
        case .categoryAlreadyExists: LionL10n.text("Já existe uma categoria com esse nome.")
        case .categoryNotFound: LionL10n.text("A categoria não foi encontrada.")
        case .cannotDeleteDefaultCategory: LionL10n.text("As categorias padrão não podem ser apagadas.")
        case .noPreviousBackup: LionL10n.text("Não há uma versão anterior do cofre para restaurar.")
        case .verificationFailed: LionL10n.text("A gravação segura do cofre não pôde ser verificada.")
        }
    }
}
