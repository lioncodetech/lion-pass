import CryptoKit
import Foundation
import LocalAuthentication
import Security
import UniformTypeIdentifiers
#if os(iOS)
import AuthenticationServices
#endif
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum LionPreferenceKey {
    public static let appearance = "appearance"
    public static let autoLock = "autoLock"
    public static let clipboard = "clipboard"
    public static let biometrics = "biometrics"
    public static let privacyCover = "privacyCover"
    public static let biometricMarker = "biometricKeyStored"
    public static let accountDisplayStyle = "accountDisplayStyle"
    public static let passwordSaveBehavior = "passwordSaveBehavior"
    public static let showInMenuBar = "showPasswordsInMenuBar"
    public static let detectCompromisedPasswords = "detectCompromisedPasswords"
    public static let suggestStrongPasswords = "suggestStrongPasswords"
    public static let automaticPasskeyUpgrades = "automaticPasskeyUpgrades"
    public static let allowContactingWebsites = "allowContactingWebsites"
}

public enum AccountDisplayStyle: String, CaseIterable, Identifiable, Sendable {
    case titles
    case websites
    case usernames

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .titles: "Títulos"
        case .websites: "Sites"
        case .usernames: "Usuários"
        }
    }
}

public enum PasswordSaveBehavior: String, CaseIterable, Identifiable, Sendable {
    case ask
    case always
    case never

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .ask: "Perguntar ao iniciar sessão"
        case .always: "Salvar automaticamente"
        case .never: "Nunca salvar automaticamente"
        }
    }
}

public protocol BiometricUnlockService {
    func authenticate(reason: String) async throws
}

public struct AppleBiometricUnlockService: BiometricUnlockService {
    public init() {}

    public func authenticate(reason: String) async throws {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw VaultError.biometricsUnavailable
        }
        guard try await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: reason
        ) else { throw VaultError.biometricsUnavailable }
    }
}

@MainActor
public final class ClipboardService {
    public static let shared = ClipboardService()
    private var generation = UUID()

    public var configuredClearInterval: TimeInterval? {
        let defaults = UserDefaults.standard
        let value = defaults.object(forKey: LionPreferenceKey.clipboard) == nil
            ? 30
            : defaults.integer(forKey: LionPreferenceKey.clipboard)
        return value > 0 ? TimeInterval(value) : nil
    }

    public func copy(_ value: String) {
        copy(value, clearAfter: configuredClearInterval)
    }

    public func copy(_ value: String, clearAfter seconds: TimeInterval?) {
#if canImport(UIKit)
        var options: [UIPasteboard.OptionsKey: Any] = [.localOnly: true]
        if let seconds, seconds > 0 {
            options[.expirationDate] = Date().addingTimeInterval(seconds)
        }
        UIPasteboard.general.setItems(
            [[UTType.plainText.identifier: value]],
            options: options
        )
#elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
#endif
        let token = UUID()
        generation = token
        guard let seconds, seconds > 0 else { return }

        Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard generation == token else { return }
#if canImport(UIKit)
            if UIPasteboard.general.string == value { UIPasteboard.general.items = [] }
#elseif canImport(AppKit)
            if NSPasteboard.general.string(forType: .string) == value {
                NSPasteboard.general.clearContents()
            }
#endif
        }
    }
}

public protocol BiometricKeyStoring: Sendable {
    var isAvailable: Bool { get }
    var exists: Bool { get }
    func save(key: SymmetricKey) throws
    func load() async throws -> SymmetricKey
    func delete()
}

public struct BiometricKeyStore: BiometricKeyStoring, Sendable {
    private let service = "com.lioncodetech.lionpassword.biometric-key"
    private let account = "vault-key"

    public init() {}

    public var isAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    public var exists: Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        var query = baseQuery
        query[kSecReturnAttributes as String] = true
        query[kSecUseAuthenticationContext as String] = context
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        let itemExists = status == errSecSuccess || status == errSecInteractionNotAllowed
        UserDefaults.standard.set(itemExists, forKey: LionPreferenceKey.biometricMarker)
        return itemExists
    }

    public func save(key: SymmetricKey) throws {
        delete()
        var accessError: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.biometryCurrentSet],
            &accessError
        ) else {
            throw accessError?.takeRetainedValue() ?? VaultError.biometricsUnavailable
        }

        var attributes = baseQuery
        attributes[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        attributes[kSecAttrAccessControl as String] = accessControl
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw keychainError(status, action: "ativar") }
        UserDefaults.standard.set(true, forKey: LionPreferenceKey.biometricMarker)
    }

    public func load() async throws -> SymmetricKey {
        try await Task.detached {
            let context = LAContext()
            context.localizedReason = "Desbloquear seu cofre Lion"
            var query = self.baseQuery
            query[kSecReturnData as String] = true
            query[kSecUseAuthenticationContext as String] = context
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            guard status == errSecSuccess, let data = result as? Data else {
                if status == errSecItemNotFound { self.markMissing() }
                throw self.keychainError(status, action: "desbloquear")
            }
            return SymmetricKey(data: data)
        }.value
    }

    public func delete() {
        SecItemDelete(baseQuery as CFDictionary)
        markMissing()
    }

    private var baseQuery: [String: Any] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]
        return query
    }

    private func markMissing() {
        UserDefaults.standard.set(false, forKey: LionPreferenceKey.biometricMarker)
    }

    private func keychainError(_ status: OSStatus, action: String) -> NSError {
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "erro \(status)"
        return NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(status),
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Não foi possível \(action) com Face ID / Touch ID: \(detail)."
            ]
        )
    }
}

public enum AutoLockDuration: String, CaseIterable, Identifiable, Codable, Sendable {
    case immediately
    case seconds30
    case minute1
    case minutes5
    case minutes15

    public var id: String { rawValue }

    public var seconds: TimeInterval {
        switch self {
        case .immediately: 0
        case .seconds30: 30
        case .minute1: 60
        case .minutes5: 300
        case .minutes15: 900
        }
    }

    public var title: String {
        switch self {
        case .immediately: "Imediatamente"
        case .seconds30: "Após 30 segundos"
        case .minute1: "1 minuto"
        case .minutes5: "5 minutos"
        case .minutes15: "15 minutos"
        }
    }
}

#if os(iOS)
public enum AutoFillIdentityService {
    public static func sync(items: [VaultItem]) async throws {
        let store = ASCredentialIdentityStore.shared
        let state = await store.state()
        guard state.isEnabled else { return }

        let identities: [ASPasswordCredentialIdentity] = items.compactMap { item in
            guard item.kind == .login, item.username.isEmpty == false else { return nil }
            guard let service = serviceIdentifier(for: item.website) else { return nil }
            let identity = ASPasswordCredentialIdentity(
                serviceIdentifier: service,
                user: item.username,
                recordIdentifier: item.id.uuidString
            )
            identity.rank = item.isFavorite ? 100 : 0
            return identity
        }
        try await store.replaceCredentialIdentities(identities)
    }

    private static func serviceIdentifier(for value: String) -> ASCredentialServiceIdentifier? {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.isEmpty == false else { return nil }
        if let url = URL(string: clean), let host = url.host {
            return ASCredentialServiceIdentifier(identifier: host, type: .domain)
        }
        if let url = URL(string: "https://\(clean)"), let host = url.host {
            return ASCredentialServiceIdentifier(identifier: host, type: .domain)
        }
        return nil
    }
}
#endif
