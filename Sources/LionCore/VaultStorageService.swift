import Foundation

public protocol VaultStorageService: Sendable {
    var vaultURL: URL { get }
    var hasPreviousBackup: Bool { get }
    func readEncryptedVault() throws -> Data
    func readPreviousBackup() throws -> Data
    func writeEncryptedVaultAtomically(_ data: Data) throws
    func restorePreviousBackup() throws
    func importVault(from url: URL) throws -> Data
    func exportVault(to url: URL) throws
}

public struct LocalVaultStorageService: VaultStorageService {
    public let vaultURL: URL
    public let backupURL: URL

    public init(baseURL: URL? = nil) {
#if os(iOS)
        let shared = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: LionIdentifiers.applicationGroup
        )
        let root = shared ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
#else
        // Personal macOS builds do not require an App Group container.
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
#endif
        let directory = baseURL ?? root.appendingPathComponent("LionPassword", isDirectory: true)
#if os(iOS)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
#else
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
#endif
        vaultURL = directory.appendingPathComponent("default.lionvault")
        backupURL = directory.appendingPathComponent("default.previous.lionvault")
    }

    public var hasPreviousBackup: Bool {
        FileManager.default.fileExists(atPath: backupURL.path)
    }

    public func readEncryptedVault() throws -> Data {
        try Data(contentsOf: vaultURL, options: .mappedIfSafe)
    }

    public func readPreviousBackup() throws -> Data {
        guard hasPreviousBackup else { throw VaultError.noPreviousBackup }
        return try Data(contentsOf: backupURL, options: .mappedIfSafe)
    }

    public func writeEncryptedVaultAtomically(_ data: Data) throws {
        guard data.isEmpty == false else { throw VaultError.invalidFormat }
        let fileManager = FileManager.default
        let temporaryURL = vaultURL.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).lionvault.tmp")
        defer { try? fileManager.removeItem(at: temporaryURL) }

#if os(iOS)
        try data.write(to: temporaryURL, options: [.atomic, .completeFileProtection])
#else
        try data.write(to: temporaryURL, options: .atomic)
#endif
        guard try Data(contentsOf: temporaryURL) == data else {
            throw VaultError.verificationFailed
        }

        if fileManager.fileExists(atPath: vaultURL.path) {
            try? fileManager.removeItem(at: backupURL)
            try fileManager.copyItem(at: vaultURL, to: backupURL)
            _ = try fileManager.replaceItemAt(
                vaultURL,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
        } else {
            try fileManager.moveItem(at: temporaryURL, to: vaultURL)
        }

        guard try readEncryptedVault() == data else { throw VaultError.verificationFailed }
    }

    public func restorePreviousBackup() throws {
        let previous = try readPreviousBackup()
        try writeEncryptedVaultAtomically(previous)
    }

    public func importVault(from url: URL) throws -> Data {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values?.fileSize, size > 100 * 1_024 * 1_024 {
            throw VaultError.invalidFormat
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    public func exportVault(to url: URL) throws {
#if os(iOS)
        try readEncryptedVault().write(to: url, options: [.atomic, .completeFileProtection])
#else
        try readEncryptedVault().write(to: url, options: .atomic)
#endif
    }
}
