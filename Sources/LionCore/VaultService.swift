import Foundation
import CryptoKit

@MainActor public final class VaultService: ObservableObject {
    @Published public private(set) var payload: VaultPayload?
    @Published public private(set) var isUnlocked = false
    @Published public var lastError: String?
    private let crypto: VaultCryptoService; private let storage: VaultStorageService
    private var key: SymmetricKey?; private var salt: Data?; private var parameters = KDFParameters()
    public init(crypto: VaultCryptoService = AppleVaultCryptoService(), storage: VaultStorageService = LocalVaultStorageService()) { self.crypto = crypto; self.storage = storage }
    public var hasVault: Bool { FileManager.default.fileExists(atPath: storage.vaultURL.path) }

    public func createVault(name: String, password: String) throws {
        let salt = try crypto.randomData(count: 32); let key = try crypto.deriveKey(password: password, salt: salt, parameters: parameters)
        let payload = VaultPayload(name: name); try storage.writeEncryptedVaultAtomically(crypto.encrypt(payload, key: key, salt: salt, parameters: parameters))
        self.payload = payload; self.salt = salt; self.key = key; isUnlocked = true
    }
    public func openVault(password: String) throws {
        let result = try crypto.decrypt(storage.readEncryptedVault(), password: password)
        payload = result.0; key = result.1
        let envelope = try JSONDecoder.lion.decode(VaultEnvelope.self, from: storage.readEncryptedVault())
        salt = envelope.salt; parameters = envelope.kdf; isUnlocked = true
    }
    public func enableBiometricUnlock() throws { guard let key else { throw VaultError.notOpen }; try BiometricKeyStore().save(key: key) }
    public func disableBiometricUnlock() { BiometricKeyStore().delete() }
    public func openVaultWithBiometrics() async throws {
        let key = try await BiometricKeyStore().load(); let data = try storage.readEncryptedVault(); payload = try crypto.decrypt(data, key: key); self.key = key
        let envelope = try JSONDecoder.lion.decode(VaultEnvelope.self, from: data); salt = envelope.salt; parameters = envelope.kdf; isUnlocked = true
    }
    public func lockVault() { payload = nil; key = nil; salt = nil; isUnlocked = false }
    public func saveVault() throws {
        guard var payload, let key, let salt else { throw VaultError.notOpen }
        payload.modifiedAt = Date(); try storage.writeEncryptedVaultAtomically(crypto.encrypt(payload, key: key, salt: salt, parameters: parameters)); self.payload = payload
    }
    public func upsert(_ item: VaultItem) throws {
        guard var p = payload else { throw VaultError.notOpen }
        if let index = p.items.firstIndex(where: { $0.id == item.id }) { p.items[index] = item } else { p.items.append(item) }
        payload = p; try saveVault()
    }
    public func delete(ids: Set<UUID>) throws { guard var p = payload else { throw VaultError.notOpen }; p.items.removeAll { ids.contains($0.id) }; payload = p; try saveVault() }
    public func changeMasterPassword(current: String, new: String) throws {
        _ = try crypto.decrypt(storage.readEncryptedVault(), password: current)
        guard let payload else { throw VaultError.notOpen }; let newSalt = try crypto.randomData(count: 32)
        let newKey = try crypto.deriveKey(password: new, salt: newSalt, parameters: parameters)
        try storage.writeEncryptedVaultAtomically(crypto.encrypt(payload, key: newKey, salt: newSalt, parameters: parameters)); key = newKey; salt = newSalt
        if BiometricKeyStore().exists { try BiometricKeyStore().save(key: newKey) }
    }
    public func encryptedData() throws -> Data { try storage.readEncryptedVault() }
    public func importEncrypted(from url: URL, password: String) throws {
        let data = try storage.importVault(from: url); _ = try crypto.decrypt(data, password: password); try storage.writeEncryptedVaultAtomically(data); try openVault(password: password)
    }
}
