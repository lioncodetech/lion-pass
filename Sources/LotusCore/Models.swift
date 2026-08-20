import Foundation

public enum VaultItemKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case login, card, secureNote, identity, other
    public var id: String { rawValue }
    public var title: String {
        switch self { case .login: "Logins"; case .card: "Cartões"; case .secureNote: "Notas seguras"; case .identity: "Identidades"; case .other: "Outros" }
    }
    public var symbol: String {
        switch self { case .login: "key.fill"; case .card: "creditcard.fill"; case .secureNote: "lock.doc.fill"; case .identity: "person.text.rectangle.fill"; case .other: "square.grid.2x2.fill" }
    }
}

public struct CustomField: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID(); public var name = ""; public var value = ""; public var isSensitive = false
}

public struct PasswordRevision: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID(); public var password: String; public var changedAt = Date()
}

public struct VaultItem: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID(); public var kind: VaultItemKind = .login
    public var title = ""; public var username = ""; public var password = ""
    public var website = ""; public var email = ""; public var notes = ""
    public var category = "Logins"; public var tags: [String] = []; public var isFavorite = false
    public var customFields: [CustomField] = []; public var passwordHistory: [PasswordRevision] = []
    public var cardholder = ""; public var cardNumber = ""; public var expiry = ""
    public var securityCode = ""; public var bank = ""; public var cardBrand = ""
    public var createdAt = Date(); public var updatedAt = Date()

    public func matches(_ query: String) -> Bool {
        let q = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return [title, username, website, email, category] .joined(separator: " ").appending(" " + tags.joined(separator: " "))
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(q)
    }
}

public struct VaultPayload: Codable, Equatable, Sendable {
    public var id = UUID(); public var name: String; public var items: [VaultItem] = []
    public var customCategories: [String] = []; public var createdAt = Date(); public var modifiedAt = Date()
    public var passwordHistoryEnabled = true
    public init(name: String) { self.name = name }
}

public struct KDFParameters: Codable, Equatable, Sendable {
    public var algorithm = "PBKDF2-HMAC-SHA256"; public var iterations: UInt32 = 600_000; public var keyLength = 32
}

public struct VaultEnvelope: Codable, Sendable {
    public let magic: String; public let version: Int; public let kdf: KDFParameters
    public let salt: Data; public let nonce: Data; public let ciphertext: Data; public let tag: Data
}

public enum VaultError: LocalizedError, Equatable {
    case invalidFormat, unsupportedVersion, wrongPasswordOrTampered, truncated, notOpen, biometricsUnavailable
    public var errorDescription: String? {
        switch self {
        case .invalidFormat: "O arquivo não é um cofre Lótus válido."
        case .unsupportedVersion: "Esta versão do cofre ainda não é suportada."
        case .wrongPasswordOrTampered: "Senha incorreta ou arquivo adulterado."
        case .truncated: "O arquivo do cofre está truncado."
        case .notOpen: "O cofre está bloqueado."
        case .biometricsUnavailable: "A autenticação biométrica não está disponível."
        }
    }
}
