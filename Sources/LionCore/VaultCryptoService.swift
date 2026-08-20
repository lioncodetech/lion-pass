import CommonCrypto
import CryptoKit
import Foundation
import Security

public protocol VaultCryptoService: Sendable {
    func randomData(count: Int) throws -> Data
    func deriveKey(password: String, salt: Data, parameters: KDFParameters) throws -> SymmetricKey
    func encrypt(
        _ payload: VaultPayload,
        key: SymmetricKey,
        salt: Data,
        parameters: KDFParameters
    ) throws -> Data
    func createEncryptedVault(
        _ payload: VaultPayload,
        password: String,
        parameters: KDFParameters
    ) throws -> CreatedVault
    func encrypt(
        _ payload: VaultPayload,
        contentKey: Data,
        preserving envelope: VaultEnvelope
    ) throws -> Data
    func unlock(_ data: Data, password: String) throws -> UnlockedVault
    func unlock(_ data: Data, recoveryKey: String) throws -> UnlockedVault
    func decrypt(_ data: Data, password: String) throws -> (VaultPayload, SymmetricKey)
    func decrypt(_ data: Data, key: SymmetricKey) throws -> VaultPayload
    func verifyIntegrity(_ data: Data, key: SymmetricKey) throws
    func rewrap(
        _ data: Data,
        contentKey: Data,
        newPassword: String,
        parameters: KDFParameters
    ) throws -> Data
    func decodeEnvelope(_ data: Data) throws -> VaultEnvelope
    func recoveryKey(for contentKey: Data) throws -> String
}

public struct AppleVaultCryptoService: VaultCryptoService {
    private static let magic = "LIONVAULT"
    private static let legacyVersion = 1
    private static let currentVersion = 2
    private static let recoveryPrefix = "LION-RECOVERY-"

    public init() {}

    public func randomData(count: Int) throws -> Data {
        guard count > 0 else { throw VaultError.invalidFormat }
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, count, bytes.baseAddress!)
        }
        guard status == errSecSuccess else { throw VaultError.invalidFormat }
        return data
    }

    public func deriveKey(
        password: String,
        salt: Data,
        parameters: KDFParameters
    ) throws -> SymmetricKey {
        try validate(parameters)
        guard salt.count >= 16 else { throw VaultError.invalidKDFParameters }

        let passwordData = Data(password.utf8)
        var output = Data(count: parameters.keyLength)
        let status = output.withUnsafeMutableBytes { outputBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress,
                        passwordData.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        parameters.iterations,
                        outputBytes.bindMemory(to: UInt8.self).baseAddress,
                        parameters.keyLength
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw VaultError.invalidFormat }
        return SymmetricKey(data: output)
    }

    // Version 1 writer retained only for backwards-compatibility tests and imports.
    public func encrypt(
        _ payload: VaultPayload,
        key: SymmetricKey,
        salt: Data,
        parameters: KDFParameters
    ) throws -> Data {
        let sealed = try sealPayload(payload, using: key)
        let envelope = VaultEnvelope(
            magic: Self.magic,
            version: Self.legacyVersion,
            kdf: parameters,
            salt: salt,
            nonce: sealed.nonce,
            ciphertext: sealed.ciphertext,
            tag: sealed.tag
        )
        return try JSONEncoder.lion.encode(envelope)
    }

    public func createEncryptedVault(
        _ payload: VaultPayload,
        password: String,
        parameters: KDFParameters = KDFParameters()
    ) throws -> CreatedVault {
        let contentKey = try randomData(count: 32)
        let salt = try randomData(count: 32)
        let passwordKey = try deriveKey(password: password, salt: salt, parameters: parameters)
        let wrapped = try seal(contentKey, using: passwordKey)
        let encryptedPayload = try sealPayload(payload, using: SymmetricKey(data: contentKey))
        let envelope = VaultEnvelope(
            magic: Self.magic,
            version: Self.currentVersion,
            kdf: parameters,
            salt: salt,
            nonce: encryptedPayload.nonce,
            ciphertext: encryptedPayload.ciphertext,
            tag: encryptedPayload.tag,
            keyNonce: wrapped.nonce,
            wrappedKey: wrapped.ciphertext,
            keyTag: wrapped.tag
        )
        return CreatedVault(
            encryptedData: try JSONEncoder.lion.encode(envelope),
            contentKey: contentKey,
            recoveryKey: try recoveryKey(for: contentKey),
            envelope: envelope
        )
    }

    public func encrypt(
        _ payload: VaultPayload,
        contentKey: Data,
        preserving envelope: VaultEnvelope
    ) throws -> Data {
        guard contentKey.count == 32 else { throw VaultError.invalidFormat }
        try validate(envelope)
        let sealed = try sealPayload(payload, using: SymmetricKey(data: contentKey))
        let updated = VaultEnvelope(
            magic: envelope.magic,
            version: envelope.version,
            kdf: envelope.kdf,
            salt: envelope.salt,
            nonce: sealed.nonce,
            ciphertext: sealed.ciphertext,
            tag: sealed.tag,
            keyNonce: envelope.keyNonce,
            wrappedKey: envelope.wrappedKey,
            keyTag: envelope.keyTag
        )
        return try JSONEncoder.lion.encode(updated)
    }

    public func unlock(_ data: Data, password: String) throws -> UnlockedVault {
        let envelope = try decodeEnvelope(data)
        let passwordKey = try deriveKey(
            password: password,
            salt: envelope.salt,
            parameters: envelope.kdf
        )

        let contentKey: Data
        if envelope.version == Self.legacyVersion {
            contentKey = passwordKey.data
        } else {
            guard
                let keyNonce = envelope.keyNonce,
                let wrappedKey = envelope.wrappedKey,
                let keyTag = envelope.keyTag
            else { throw VaultError.invalidFormat }
            do {
                contentKey = try open(
                    nonce: keyNonce,
                    ciphertext: wrappedKey,
                    tag: keyTag,
                    using: passwordKey
                )
            } catch {
                throw VaultError.wrongPasswordOrTampered
            }
        }

        return UnlockedVault(
            payload: try decryptPayload(envelope, contentKey: contentKey),
            contentKey: contentKey,
            envelope: envelope
        )
    }

    public func unlock(_ data: Data, recoveryKey: String) throws -> UnlockedVault {
        let envelope = try decodeEnvelope(data)
        let contentKey = try contentKey(fromRecoveryKey: recoveryKey)
        do {
            return UnlockedVault(
                payload: try decryptPayload(envelope, contentKey: contentKey),
                contentKey: contentKey,
                envelope: envelope
            )
        } catch {
            throw VaultError.invalidRecoveryKey
        }
    }

    public func decrypt(_ data: Data, password: String) throws -> (VaultPayload, SymmetricKey) {
        let result = try unlock(data, password: password)
        return (result.payload, SymmetricKey(data: result.contentKey))
    }

    public func decrypt(_ data: Data, key: SymmetricKey) throws -> VaultPayload {
        let envelope = try decodeEnvelope(data)
        return try decryptPayload(envelope, contentKey: key.data)
    }

    public func verifyIntegrity(_ data: Data, key: SymmetricKey) throws {
        _ = try decrypt(data, key: key)
    }

    public func rewrap(
        _ data: Data,
        contentKey: Data,
        newPassword: String,
        parameters: KDFParameters = KDFParameters()
    ) throws -> Data {
        let current = try decodeEnvelope(data)
        _ = try decryptPayload(current, contentKey: contentKey)

        let salt = try randomData(count: 32)
        let passwordKey = try deriveKey(password: newPassword, salt: salt, parameters: parameters)
        let wrapped = try seal(contentKey, using: passwordKey)
        let updated = VaultEnvelope(
            magic: Self.magic,
            version: Self.currentVersion,
            kdf: parameters,
            salt: salt,
            nonce: current.nonce,
            ciphertext: current.ciphertext,
            tag: current.tag,
            keyNonce: wrapped.nonce,
            wrappedKey: wrapped.ciphertext,
            keyTag: wrapped.tag
        )
        return try JSONEncoder.lion.encode(updated)
    }

    public func decodeEnvelope(_ data: Data) throws -> VaultEnvelope {
        guard data.count > 64 else { throw VaultError.truncated }
        let envelope: VaultEnvelope
        do {
            envelope = try JSONDecoder.lion.decode(VaultEnvelope.self, from: data)
        } catch {
            throw VaultError.invalidFormat
        }
        try validate(envelope)
        return envelope
    }

    public func recoveryKey(for contentKey: Data) throws -> String {
        guard contentKey.count == 32 else { throw VaultError.invalidRecoveryKey }
        let checksum = Data(SHA256.hash(data: contentKey).prefix(4))
        let encoded = (contentKey + checksum).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return Self.recoveryPrefix + encoded
    }

    private func contentKey(fromRecoveryKey recoveryKey: String) throws -> Data {
        let compact = recoveryKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard compact.uppercased().hasPrefix(Self.recoveryPrefix) else {
            throw VaultError.invalidRecoveryKey
        }
        var encoded = String(compact.dropFirst(Self.recoveryPrefix.count))
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while encoded.count.isMultiple(of: 4) == false { encoded.append("=") }
        guard let decoded = Data(base64Encoded: encoded), decoded.count == 36 else {
            throw VaultError.invalidRecoveryKey
        }
        let key = Data(decoded.prefix(32))
        let expected = Data(SHA256.hash(data: key).prefix(4))
        guard Data(decoded.suffix(4)) == expected else { throw VaultError.invalidRecoveryKey }
        return key
    }

    private func validate(_ parameters: KDFParameters) throws {
        guard parameters.algorithm == "PBKDF2-HMAC-SHA256" else {
            throw VaultError.unsupportedKDF
        }
        guard
            parameters.iterations >= 100_000,
            parameters.iterations <= 5_000_000,
            parameters.keyLength == 32
        else { throw VaultError.invalidKDFParameters }
    }

    private func validate(_ envelope: VaultEnvelope) throws {
        guard envelope.magic == Self.magic else { throw VaultError.invalidFormat }
        guard [Self.legacyVersion, Self.currentVersion].contains(envelope.version) else {
            throw VaultError.unsupportedVersion
        }
        try validate(envelope.kdf)
        guard
            envelope.salt.count >= 16,
            envelope.nonce.count == 12,
            envelope.tag.count == 16,
            envelope.ciphertext.isEmpty == false
        else { throw VaultError.invalidFormat }

        if envelope.version == Self.currentVersion {
            guard
                envelope.keyNonce?.count == 12,
                envelope.wrappedKey?.count == 32,
                envelope.keyTag?.count == 16
            else { throw VaultError.invalidFormat }
        }
    }

    private func sealPayload(
        _ payload: VaultPayload,
        using key: SymmetricKey
    ) throws -> (nonce: Data, ciphertext: Data, tag: Data) {
        try seal(try JSONEncoder.lion.encode(payload), using: key)
    }

    private func seal(
        _ plaintext: Data,
        using key: SymmetricKey
    ) throws -> (nonce: Data, ciphertext: Data, tag: Data) {
        let nonceData = try randomData(count: 12)
        let sealed = try AES.GCM.seal(
            plaintext,
            using: key,
            nonce: try AES.GCM.Nonce(data: nonceData)
        )
        return (nonceData, sealed.ciphertext, sealed.tag)
    }

    private func open(
        nonce: Data,
        ciphertext: Data,
        tag: Data,
        using key: SymmetricKey
    ) throws -> Data {
        let box = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: nonce),
            ciphertext: ciphertext,
            tag: tag
        )
        return try AES.GCM.open(box, using: key)
    }

    private func decryptPayload(_ envelope: VaultEnvelope, contentKey: Data) throws -> VaultPayload {
        guard contentKey.count == 32 else { throw VaultError.wrongPasswordOrTampered }
        do {
            let plaintext = try open(
                nonce: envelope.nonce,
                ciphertext: envelope.ciphertext,
                tag: envelope.tag,
                using: SymmetricKey(data: contentKey)
            )
            // Older Lion vaults encoded dates as milliseconds. New vaults use
            // Date's native reference-interval representation, preserving its
            // full precision without the rounding caused by an epoch conversion.
            // Detect the old representation before decoding so v1/v2 files remain
            // readable while a new round-trip is lossless.
            let decoder = payloadUsesLegacyMilliseconds(plaintext)
                ? JSONDecoder.lionMilliseconds
                : JSONDecoder.lion
            return try decoder.decode(VaultPayload.self, from: plaintext)
        } catch {
            throw VaultError.wrongPasswordOrTampered
        }
    }

    private func payloadUsesLegacyMilliseconds(_ data: Data) -> Bool {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let createdAt = object["createdAt"] as? NSNumber
        else { return false }
        return abs(createdAt.doubleValue) > 10_000_000_000
    }
}

private extension SymmetricKey {
    var data: Data { withUnsafeBytes { Data($0) } }
}

extension JSONEncoder {
    static var lion: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var lion: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return decoder
    }

    static var lionMilliseconds: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
