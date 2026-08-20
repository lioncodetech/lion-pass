import Foundation
import CryptoKit
import CommonCrypto
import Security

public protocol VaultCryptoService: Sendable {
    func randomData(count: Int) throws -> Data
    func deriveKey(password: String, salt: Data, parameters: KDFParameters) throws -> SymmetricKey
    func encrypt(_ payload: VaultPayload, key: SymmetricKey, salt: Data, parameters: KDFParameters) throws -> Data
    func decrypt(_ data: Data, password: String) throws -> (VaultPayload, SymmetricKey)
    func decrypt(_ data: Data, key: SymmetricKey) throws -> VaultPayload
}

public struct AppleVaultCryptoService: VaultCryptoService {
    public init() {}
    public func randomData(count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        guard status == errSecSuccess else { throw VaultError.invalidFormat }; return data
    }

    public func deriveKey(password: String, salt: Data, parameters: KDFParameters) throws -> SymmetricKey {
        let passwordData = Data(password.utf8); var output = Data(count: parameters.keyLength)
        let status = output.withUnsafeMutableBytes { out in
            salt.withUnsafeBytes { saltBytes in passwordData.withUnsafeBytes { pwd in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pwd.bindMemory(to: Int8.self).baseAddress, passwordData.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    parameters.iterations, out.bindMemory(to: UInt8.self).baseAddress, parameters.keyLength)
            }}
        }
        guard status == kCCSuccess else { throw VaultError.invalidFormat }
        return SymmetricKey(data: output)
    }

    public func encrypt(_ payload: VaultPayload, key: SymmetricKey, salt: Data, parameters: KDFParameters) throws -> Data {
        let encoded = try JSONEncoder.lion.encode(payload)
        let nonceData = try randomData(count: 12); let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealed = try AES.GCM.seal(encoded, using: key, nonce: nonce)
        let envelope = VaultEnvelope(magic: "LIONVAULT", version: 1, kdf: parameters, salt: salt,
            nonce: nonceData, ciphertext: sealed.ciphertext, tag: sealed.tag)
        return try JSONEncoder.lion.encode(envelope)
    }

    public func decrypt(_ data: Data, password: String) throws -> (VaultPayload, SymmetricKey) {
        guard data.count > 64 else { throw VaultError.truncated }
        let envelope: VaultEnvelope
        do { envelope = try JSONDecoder.lion.decode(VaultEnvelope.self, from: data) } catch { throw VaultError.invalidFormat }
        guard envelope.magic == "LIONVAULT" else { throw VaultError.invalidFormat }
        guard envelope.version == 1 else { throw VaultError.unsupportedVersion }
        guard envelope.nonce.count == 12, envelope.tag.count == 16, envelope.salt.count >= 16 else { throw VaultError.invalidFormat }
        let key = try deriveKey(password: password, salt: envelope.salt, parameters: envelope.kdf)
        return (try decrypt(data, key: key), key)
    }
    public func decrypt(_ data: Data, key: SymmetricKey) throws -> VaultPayload {
        guard data.count > 64 else { throw VaultError.truncated }
        guard let envelope = try? JSONDecoder.lion.decode(VaultEnvelope.self, from: data), envelope.magic == "LIONVAULT", envelope.version == 1 else { throw VaultError.invalidFormat }
        do { let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: envelope.nonce), ciphertext: envelope.ciphertext, tag: envelope.tag); return try JSONDecoder.lion.decode(VaultPayload.self, from: AES.GCM.open(box, using: key)) } catch { throw VaultError.wrongPasswordOrTampered }
    }
}

extension JSONEncoder { static var lion: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .millisecondsSince1970; e.outputFormatting = [.sortedKeys]; return e } }
extension JSONDecoder { static var lion: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .millisecondsSince1970; return d } }
