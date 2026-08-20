import Foundation
import LocalAuthentication
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public protocol BiometricUnlockService { func authenticate(reason: String) async throws }
public struct AppleBiometricUnlockService: BiometricUnlockService {
    public init() {}
    public func authenticate(reason: String) async throws {
        let context = LAContext(); var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { throw VaultError.biometricsUnavailable }
        guard try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) else { throw VaultError.biometricsUnavailable }
    }
}

@MainActor public final class ClipboardService {
    public static let shared = ClipboardService(); private var generation = UUID()
    public func copy(_ value: String, clearAfter seconds: TimeInterval?) {
#if canImport(UIKit)
        UIPasteboard.general.setItems([[UTType.plainText.identifier: value]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(seconds ?? 86_400)])
#elseif canImport(AppKit)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
#endif
        let token = UUID(); generation = token
        guard let seconds else { return }
        Task { try? await Task.sleep(for: .seconds(seconds)); guard generation == token else { return }
#if canImport(UIKit)
            if UIPasteboard.general.string == value { UIPasteboard.general.items = [] }
#elseif canImport(AppKit)
            if NSPasteboard.general.string(forType: .string) == value { NSPasteboard.general.clearContents() }
#endif
        }
    }
}
import UniformTypeIdentifiers
import Security
import CryptoKit

public struct BiometricKeyStore: Sendable {
    private let service = "com.example.lionpassword.biometric-key"
    public init() {}
    public var exists: Bool { SecItemCopyMatching([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecReturnData: false] as CFDictionary, nil) == errSecSuccess }
    public func save(key: SymmetricKey) throws {
        delete(); var error: Unmanaged<CFError>?
        guard let control = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.biometryCurrentSet], &error) else { throw error!.takeRetainedValue() }
        let data = key.withUnsafeBytes { Data($0) }
        let status = SecItemAdd([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: "vault-key", kSecValueData: data, kSecAttrAccessControl: control] as CFDictionary, nil)
        guard status == errSecSuccess else { throw VaultError.biometricsUnavailable }
    }
    public func load() async throws -> SymmetricKey {
        try await Task.detached { let context = LAContext(); context.localizedReason = "Desbloquear seu cofre Lion"; var result: CFTypeRef?
            let status = SecItemCopyMatching([kSecClass: kSecClassGenericPassword, kSecAttrService: self.service, kSecReturnData: true, kSecUseAuthenticationContext: context, kSecUseOperationPrompt: "Desbloquear seu cofre Lion"] as CFDictionary, &result)
            guard status == errSecSuccess, let data = result as? Data else { throw VaultError.biometricsUnavailable }; return SymmetricKey(data: data)
        }.value
    }
    public func delete() { SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service] as CFDictionary) }
}

public enum AutoLockDuration: String, CaseIterable, Identifiable { case immediately, seconds30, minute1, minutes5, minutes15; public var id: String { rawValue }; public var seconds: TimeInterval { switch self { case .immediately: 0; case .seconds30: 30; case .minute1: 60; case .minutes5: 300; case .minutes15: 900 } } }
