import Combine
import CryptoKit
import Foundation

@MainActor
public final class VaultService: ObservableObject {
    @Published public private(set) var payload: VaultPayload?
    @Published public private(set) var isUnlocked = false
    @Published public private(set) var pendingRecoveryKey: String?
    @Published public var lastError: String?

    private let crypto: VaultCryptoService
    private let storage: VaultStorageService
    private let biometricStore: any BiometricKeyStoring
    private var contentKey: Data?
    private var envelope: VaultEnvelope?
    private var parameters = KDFParameters()

    public init(
        crypto: VaultCryptoService = AppleVaultCryptoService(),
        storage: VaultStorageService = LocalVaultStorageService(),
        biometricStore: any BiometricKeyStoring = BiometricKeyStore()
    ) {
        self.crypto = crypto
        self.storage = storage
        self.biometricStore = biometricStore
    }

    public var hasVault: Bool {
        FileManager.default.fileExists(atPath: storage.vaultURL.path)
    }

    public var hasPreviousBackup: Bool { storage.hasPreviousBackup }

    public func createVault(name: String, password: String) throws {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanName.isEmpty == false, password.count >= 12 else {
            throw VaultError.invalidFormat
        }
        let newPayload = VaultPayload(name: cleanName)
        let created = try crypto.createEncryptedVault(
            newPayload,
            password: password,
            parameters: parameters
        )
        try crypto.verifyIntegrity(
            created.encryptedData,
            key: SymmetricKey(data: created.contentKey)
        )
        try storage.writeEncryptedVaultAtomically(created.encryptedData)
        biometricStore.delete()
        payload = newPayload
        contentKey = created.contentKey
        envelope = created.envelope
        pendingRecoveryKey = created.recoveryKey
        isUnlocked = true
        syncAutoFillIdentities()
    }

    public func acknowledgeRecoveryKey() {
        pendingRecoveryKey = nil
    }

    public func revealRecoveryKey() throws -> String {
        guard let contentKey else { throw VaultError.notOpen }
        return try crypto.recoveryKey(for: contentKey)
    }

    public func openVault(password: String) throws {
        apply(try crypto.unlock(try storage.readEncryptedVault(), password: password))
    }

    public func openVault(recoveryKey: String) throws {
        apply(try crypto.unlock(try storage.readEncryptedVault(), recoveryKey: recoveryKey))
    }

    public func enableBiometricUnlock() throws {
        guard let contentKey else { throw VaultError.notOpen }
        try biometricStore.save(key: SymmetricKey(data: contentKey))
    }

    public func disableBiometricUnlock() {
        biometricStore.delete()
    }

    public func openVaultWithBiometrics() async throws {
        let key = try await biometricStore.load()
        let data = try storage.readEncryptedVault()
        let decodedEnvelope = try crypto.decodeEnvelope(data)
        let decodedPayload = try crypto.decrypt(data, key: key)
        apply(
            UnlockedVault(
                payload: decodedPayload,
                contentKey: key.withUnsafeBytes { Data($0) },
                envelope: decodedEnvelope
            )
        )
    }

    public func lockVault() {
        payload = nil
        contentKey = nil
        envelope = nil
        pendingRecoveryKey = nil
        lastError = nil
        isUnlocked = false
    }

    public func saveVault() throws {
        guard var currentPayload = payload, let contentKey, let envelope else {
            throw VaultError.notOpen
        }
        currentPayload.modifiedAt = Date()
        let data = try crypto.encrypt(
            currentPayload,
            contentKey: contentKey,
            preserving: envelope
        )
        try crypto.verifyIntegrity(data, key: SymmetricKey(data: contentKey))
        try storage.writeEncryptedVaultAtomically(data)
        self.payload = currentPayload
        self.envelope = try crypto.decodeEnvelope(data)
        syncAutoFillIdentities()
    }

    public func upsert(_ candidate: VaultItem) throws {
        guard var currentPayload = payload else { throw VaultError.notOpen }
        var item = candidate
        let now = Date()
        item.updatedAt = now

        if let index = currentPayload.items.firstIndex(where: { $0.id == item.id }) {
            let previous = currentPayload.items[index]
            item.createdAt = previous.createdAt
            if currentPayload.passwordHistoryEnabled,
               previous.password.isEmpty == false,
               previous.password != item.password {
                var history = previous.passwordHistory
                if history.last?.password != previous.password {
                    history.append(
                        PasswordRevision(password: previous.password, changedAt: now)
                    )
                }
                item.passwordHistory = Array(history.suffix(20))
            } else if item.passwordHistory.isEmpty {
                item.passwordHistory = previous.passwordHistory
            }
            currentPayload.items[index] = item
        } else {
            item.createdAt = now
            currentPayload.items.append(item)
        }
        payload = currentPayload
        try saveVault()
    }

    public func delete(ids: Set<UUID>) throws {
        guard var currentPayload = payload else { throw VaultError.notOpen }
        currentPayload.items.removeAll { ids.contains($0.id) }
        payload = currentPayload
        try saveVault()
    }

    public func setPasswordHistoryEnabled(_ enabled: Bool) throws {
        guard var currentPayload = payload else { throw VaultError.notOpen }
        currentPayload.passwordHistoryEnabled = enabled
        payload = currentPayload
        try saveVault()
    }

    public func addCategory(_ name: String) throws {
        guard var currentPayload = payload else { throw VaultError.notOpen }
        let cleanName = normalizedCategory(name)
        guard cleanName.isEmpty == false else { throw VaultError.invalidFormat }
        guard !currentPayload.allCategories.contains(where: {
            $0.compare(cleanName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) else { throw VaultError.categoryAlreadyExists }
        currentPayload.customCategories.append(cleanName)
        payload = currentPayload
        try saveVault()
    }

    public func renameCategory(_ oldName: String, to newName: String) throws {
        guard var currentPayload = payload else { throw VaultError.notOpen }
        guard let index = currentPayload.customCategories.firstIndex(of: oldName) else {
            throw VaultError.categoryNotFound
        }
        let cleanName = normalizedCategory(newName)
        guard cleanName.isEmpty == false else { throw VaultError.invalidFormat }
        guard !currentPayload.allCategories.contains(where: {
            $0 != oldName && $0.compare(
                cleanName,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame
        }) else { throw VaultError.categoryAlreadyExists }
        currentPayload.customCategories[index] = cleanName
        for itemIndex in currentPayload.items.indices where currentPayload.items[itemIndex].category == oldName {
            currentPayload.items[itemIndex].category = cleanName
        }
        payload = currentPayload
        try saveVault()
    }

    public func deleteCategory(_ name: String) throws {
        guard var currentPayload = payload else { throw VaultError.notOpen }
        if VaultPayload.defaultCategories.contains(name) {
            throw VaultError.cannotDeleteDefaultCategory
        }
        guard currentPayload.customCategories.contains(name) else {
            throw VaultError.categoryNotFound
        }
        currentPayload.customCategories.removeAll { $0 == name }
        for index in currentPayload.items.indices where currentPayload.items[index].category == name {
            currentPayload.items[index].category = "Outros"
        }
        payload = currentPayload
        try saveVault()
    }

    public func changeMasterPassword(current: String, new: String) throws {
        guard new.count >= 12 else { throw VaultError.invalidFormat }
        let data = try storage.readEncryptedVault()
        let unlocked = try crypto.unlock(data, password: current)
        let rewrapped = try crypto.rewrap(
            data,
            contentKey: unlocked.contentKey,
            newPassword: new,
            parameters: parameters
        )
        _ = try crypto.unlock(rewrapped, password: new)
        try storage.writeEncryptedVaultAtomically(rewrapped)
        apply(
            UnlockedVault(
                payload: unlocked.payload,
                contentKey: unlocked.contentKey,
                envelope: try crypto.decodeEnvelope(rewrapped)
            )
        )
        // The content key is intentionally preserved, so an existing biometric slot remains valid.
    }

    public func verifyIntegrity() throws {
        guard let contentKey else { throw VaultError.notOpen }
        let stored = try storage.readEncryptedVault()
        try crypto.verifyIntegrity(stored, key: SymmetricKey(data: contentKey))
    }

    public func restorePreviousBackup(password: String) throws {
        let previous = try storage.readPreviousBackup()
        let unlocked = try crypto.unlock(previous, password: password)
        try storage.restorePreviousBackup()
        apply(unlocked)
        biometricStore.delete()
    }

    public func encryptedData() throws -> Data {
        try storage.readEncryptedVault()
    }

    public func importEncrypted(from url: URL, password: String) throws {
        let data = try storage.importVault(from: url)
        let unlocked = try crypto.unlock(data, password: password)
        try storage.writeEncryptedVaultAtomically(data)
        apply(unlocked)
        biometricStore.delete()
    }

    public func importEncrypted(from url: URL, recoveryKey: String) throws {
        let data = try storage.importVault(from: url)
        let unlocked = try crypto.unlock(data, recoveryKey: recoveryKey)
        try storage.writeEncryptedVaultAtomically(data)
        apply(unlocked)
        biometricStore.delete()
    }

    private func apply(_ unlocked: UnlockedVault) {
        payload = unlocked.payload
        contentKey = unlocked.contentKey
        envelope = unlocked.envelope
        parameters = unlocked.envelope.kdf
        lastError = nil
        isUnlocked = true
        syncAutoFillIdentities()
    }

    private func normalizedCategory(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private func syncAutoFillIdentities() {
#if os(iOS)
        let items = payload?.items ?? []
        Task { try? await AutoFillIdentityService.sync(items: items) }
#endif
    }
}
