import XCTest
import CryptoKit
@testable import LionPassword

final class VaultCryptoTests: XCTestCase {
    let crypto = AppleVaultCryptoService()
    func testCorrectPasswordRoundTrip() throws {
        let salt = try crypto.randomData(count: 32), parameters = KDFParameters(), password = "correct horse battery staple"
        let key = try crypto.deriveKey(password: password, salt: salt, parameters: parameters); var payload = VaultPayload(name: "Teste"); var item = VaultItem(); item.title = "Conta"; item.password = "segredo"; payload.items = [item]
        let encrypted = try crypto.encrypt(payload, key: key, salt: salt, parameters: parameters)
        XCTAssertEqual(try crypto.decrypt(encrypted, password: password).0, payload); XCTAssertFalse(encrypted.contains(Data("segredo".utf8)))
    }
    func testWrongPasswordFails() throws { let data = try fixture(password: "certa"); XCTAssertThrowsError(try crypto.decrypt(data, password: "errada")) { XCTAssertEqual($0 as? VaultError, .wrongPasswordOrTampered) } }
    func testTamperingFailsAuthentication() throws { var envelope = try JSONDecoder.lion.decode(VaultEnvelope.self, from: fixture(password: "senha")); var bytes = envelope.ciphertext; bytes[bytes.startIndex] ^= 1; let altered = VaultEnvelope(magic: envelope.magic, version: envelope.version, kdf: envelope.kdf, salt: envelope.salt, nonce: envelope.nonce, ciphertext: bytes, tag: envelope.tag); XCTAssertThrowsError(try crypto.decrypt(JSONEncoder.lion.encode(altered), password: "senha")) }
    func testTruncatedFileRejected() { XCTAssertThrowsError(try crypto.decrypt(Data([1,2,3]), password: "senha")) { XCTAssertEqual($0 as? VaultError, .truncated) } }
    private func fixture(password: String) throws -> Data { let salt = try crypto.randomData(count: 32), p = KDFParameters(), key = try crypto.deriveKey(password: password, salt: salt, parameters: p); return try crypto.encrypt(VaultPayload(name: "Teste"), key: key, salt: salt, parameters: p) }
}

@MainActor final class VaultServiceTests: XCTestCase {
    func testChangeMasterPasswordAndAtomicPersistence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: directory) }
        let storage = LocalVaultStorageService(baseURL: directory), service = VaultService(storage: storage)
        try service.createVault(name: "Teste", password: "uma senha longa e segura"); var item = VaultItem(); item.title = "Email"; try service.upsert(item); try service.changeMasterPassword(current: "uma senha longa e segura", new: "outra senha longa e segura"); service.lockVault()
        XCTAssertThrowsError(try service.openVault(password: "uma senha longa e segura")); try service.openVault(password: "outra senha longa e segura"); XCTAssertEqual(service.payload?.items.count, 1)
    }
}
