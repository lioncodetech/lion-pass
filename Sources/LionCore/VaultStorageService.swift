import Foundation

public protocol VaultStorageService: Sendable {
    func readEncryptedVault() throws -> Data
    func writeEncryptedVaultAtomically(_ data: Data) throws
    func importVault(from url: URL) throws -> Data
    func exportVault(to url: URL) throws
    var vaultURL: URL { get }
}

public struct LocalVaultStorageService: VaultStorageService {
    public let vaultURL: URL; private let backupURL: URL
    public init(baseURL: URL? = nil) {
#if os(iOS)
        let shared = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.example.lionpassword")
        let root = shared ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
#else
        // Unsigned personal macOS builds must not use an App Group container.
        // containerURL may return a URL even though the process cannot read it.
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
#endif
        let base = baseURL ?? root.appendingPathComponent("LionPassword", isDirectory: true)
#if os(iOS)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
#else
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
#endif
        vaultURL = base.appendingPathComponent("default.lionvault")
        backupURL = base.appendingPathComponent("default.previous.lionvault")
    }
    public func readEncryptedVault() throws -> Data { try Data(contentsOf: vaultURL, options: .mappedIfSafe) }
    public func writeEncryptedVaultAtomically(_ data: Data) throws {
        let fm = FileManager.default; let temp = vaultURL.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".tmp")
#if os(iOS)
        try data.write(to: temp, options: [.atomic, .completeFileProtection])
#else
        try data.write(to: temp, options: .atomic)
#endif
        _ = try Data(contentsOf: temp) // read-back before replacement
        if fm.fileExists(atPath: vaultURL.path) { try? fm.removeItem(at: backupURL); try fm.copyItem(at: vaultURL, to: backupURL) }
        if fm.fileExists(atPath: vaultURL.path) { _ = try fm.replaceItemAt(vaultURL, withItemAt: temp) } else { try fm.moveItem(at: temp, to: vaultURL) }
    }
    public func importVault(from url: URL) throws -> Data {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }
    public func exportVault(to url: URL) throws {
#if os(iOS)
        try readEncryptedVault().write(to: url, options: [.atomic, .completeFileProtection])
#else
        try readEncryptedVault().write(to: url, options: .atomic)
#endif
    }
}
