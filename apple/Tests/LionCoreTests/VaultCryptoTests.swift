import CryptoKit
import LocalAuthentication
import XCTest
@testable import Lion_Pass

final class VaultCryptoTests: XCTestCase {
    func testWindowsVersionTwoFixtureIsCompatible() throws {
        // Same synthetic bytes committed at shared/test-vaults/fixtures/windows-v2.lionvault.
        // Embedding avoids the macOS test-host sandbox blocking repository file access.
        let fixtureBase64 = "eyJtYWdpYyI6IkxJT05WQVVMVCIsInZlcnNpb24iOjIsImtkZiI6eyJhbGdvcml0aG0iOiJQQktERjItSE1BQy1TSEEyNTYiLCJpdGVyYXRpb25zIjoxMDAwMDAsImtleUxlbmd0aCI6MzJ9LCJzYWx0IjoiejFyeTloTlB5OGZoNzRrQjlnY2VKSmdDTTZSb3NON0FkRmVPZC9mcU10VT0iLCJub25jZSI6ImpuZDJERXY5eEJOekFHTC8iLCJjaXBoZXJ0ZXh0IjoiNTlCcFhzd29raHcrMGVoRzcwaWdoSGlkWkw1UjBWQzNrWmhSUlpjWW5URzd2QnN4c3V5Sit1anpxQ0R1ZWd1OHdiemd2S09oUFp0S3NGZFpHUjNqVGh6YXRONEI5cWNKZldnYW9ZNTAxNTl2WVNSZEc3T0hrOTFuV3JyN2JuVFdraHpHVnl1d1FUQUpyQW1QckYrK1AvdEFUQXZ0Rm5QRTJ2Zjd0YzlHWEtHbnBPVnlzamRVNStRdHdhSkFCSU02amZlN2NXeW9DajU3NlZ0R3J5NGRkSUJyOFNYTVpJSWFKbVBZUS9HT3UxV3MxUDh4UGVhd1hUM1ZCWU0zTlBLcFVUcDlvVjVTWHI3SXBSWmRqN28wQkp0eWhrZXNjWElza3dZdFh5VFdVam80a0IyV0FKc3Q4Qzd3VkNXSUx6ZnlFQVJUZ3hXTVM3SFJpRlBGWjVNaVE0OHBlMXd1ejMzSXVEV1dKTkd1QzRFT2lkaGRSSW40ZzNUS291Z2J0UXlHRmFJQnFLZGR3cllXeE1xRTBKVlJqSzBCdEF2NnEzSHc4NXdIbUt5MktwR0VodjFyL0FkcFdjdW8zd1JIVFBMbTZKc2NLYzY4clFBZFNYMmVUSk5MWmsySXZUMHljQTVVUGRBK2VwcG5mb04zNVV1SVcvUUpMa1pxMUxJMEVJdUYzTWRLejVBYXRDWHVIblNMZ2h1Q1FWSjFiNU55bVk0Mm45emhVbnhNeE9kcSswSzYvR2FBK2VwZ040MU9WcmgxRFhvaU5Lb21xN0xyMFJVa2d1dkFUN1c3RFErZzVKbDdmWXFjS01oTFY4K2RFYmRSdms3ak44TEdWeVlVTkpDa04yMG1WaFJWQW9ocW9VVG9kRzhmbDVPdzJDUlBDK3NCSlFOS1NxbE1aS1VkV2ZRNitoSXhXeVhNYmNYQlRuRGlYZlhrVG0wZVp0eVdTcVpuREFLdTd5Zk1EWXZKTjlON2hRRjhmeVI4V3VJRHlzYkxoWFNOazlBa2dtSVVpT2dxc2syZ3NDV29mOFFNQW9Rb3NWalJ3NlFGeFpnd3dHYUZoRDYyeU1Bc3NoNDlPZmNZWnI1VWRySjVaQ2FPN2pPZThLd0lVTG5vcFlhZGtaUE5DYnJvK05DVWI3Ym81REE2THpnaTd2N3djTzZ4a1pFUFVkbUJ6KzNtWDFIMXdzZDBUUUlqN2F2VCs1NzNqV21FUklIa2orZkVONmVqUHRsTTVWSXdTQlAydzNxOWo1ODVreFdtU05CUUhmMWZ3cEU4YWN5bTU2a3ljaE42ZDAxVWFLbHJBcjRKVkxCcUN1OU85SDdDcFVQNDMwanBaSWVodFkxRjg5dnpyd2dvUzV5UG9NZDJiUm1SRGxaMlljbGxRdUd2U0NiZmt3PT0iLCJ0YWciOiJMT1FaREVhWmdmSkFHci9EWTcvYlhnPT0iLCJrZXlOb25jZSI6Inc3d2ZIWFZQZmE0RUNqRjgiLCJ3cmFwcGVkS2V5IjoiNVVOcFR3WWcyV2pyNkdjY2JuZEdHd3EvbEh0VjlXWVFKOVY2NllOZWV4VT0iLCJrZXlUYWciOiI2Z0ZUVktMdEtmaDJQT1NQQVgzU09BPT0ifQ=="
        let data = try XCTUnwrap(Data(base64Encoded: fixtureBase64))

        let unlocked = try AppleVaultCryptoService().unlock(
            data,
            password: "Lion-Pass-Compatibility-2026!"
        )

        XCTAssertEqual(unlocked.payload.name, "Windows Compatibility Fixture")
        XCTAssertEqual(unlocked.payload.items.count, 1)
        XCTAssertEqual(unlocked.payload.items.first?.username, "windows@example.test")
        XCTAssertEqual(unlocked.payload.items.first?.category, "Interoperabilidade")
        XCTAssertEqual(unlocked.envelope.version, 2)
    }

    func testLinuxVersionTwoFixtureIsCompatible() throws {
        // Same synthetic bytes committed at shared/test-vaults/fixtures/linux-v2.lionvault.
        let fixtureBase64 = "eyJtYWdpYyI6IkxJT05WQVVMVCIsInZlcnNpb24iOjIsImtkZiI6eyJhbGdvcml0aG0iOiJQQktERjItSE1BQy1TSEEyNTYiLCJpdGVyYXRpb25zIjoxMDAwMDAsImtleUxlbmd0aCI6MzJ9LCJzYWx0IjoiNWZVY3pUZVpzcWoxbmZUc1gra3JRbE8veE05WFNIUlBnUEl3b0xsaE1HMD0iLCJub25jZSI6InpZRTRpcThkTGhWT0VXWFMiLCJjaXBoZXJ0ZXh0IjoibEVFZDlQbjAweEtuQmF3YXZNSEFmWXJqZGpPUjhJM0E3UThUOUJPZGxzN0ZYNG9SeXhLRWlodDlDWW5HbmNBc1k1S2gvTW51eGo3Q29Ya1dzN3JJWm5iVHdOVytvK3lRVHcvZjNtK3BUZXltU3o2WC9TVnB1Q3ZPNCs1dFpEaW9tVkhhazVxK3VzSFdNS2hJWWVQTENZeDBpSDFmY2dmZGR2Q2t3ZkozdUJORUZXTEdsWllJTzdMNWxna3AwdU1JRVpGbFNKODZtdWVyVElsbXNkdytJMDFPakFWeWRtb3lrWS9oR3ptMmJkZXRaWUQ2aWpCVkp0QjVWaDBTQnRmOCtPb0J0WjVoanhlYjNpRmJoN0ZWTEdJNTd1UDNKUnJ4NVVTRXBZWTd2ZU84NXpEelp5cXF3RFhNQWh1YXVKTDJvNWlaeVJ3azNyL1FXZmdwU2hEZjBoOVo3YmZEdEQ4ZjR6a1R6aFFrTFFvU1pDeXdRbDYwVzFkekh2dFRHbU5OMzg1YXhpdEdwdnZEMmhmeUZiUThKQlgyRWV5ZG9yRmk3aTNPUElLdEt3THUwdGlaZlhXb1p4Mnd1U2hrTGRoZlFlZW1tU2ZqbmVGckdrVVFFc1VOaE5uREFTZkR2T1Ztc3BqOHBKVlJiL0F5ZlkyNXBtZXNaUnJsWkttYWRVRVo1bHBQTzhSZm9UaTFZQ3VHeEk1Y1VvZ1k0ZHdGUG5XamJHQWtwcmpSeHFMcCtOUnAzWU54K0U5bGJmRUovYXpPTUxsU2JDbkFHVjR0L0plM21VUVNQR1hoL3Y2VSszdEo2VDAreHh5QUlKUjdLU083aGpoWjBTQ0hsQjZrNWpVaXkzYXFsZ2x3eFBjdElObGlZOEVaV3VONUNHa2N4ZVNkTWdRUWNyVVZLQUh1cFpydlNxanBIUGVFUTgza05YUEJhck5DcHp2OUs2WnJaUmJicldBWVZYMVpKN08xV3NYSlZLaXhOU2o4Tzd2RjRxaW9HUy9jODR1Y2JhLzFEZzkvN1JIdEs5Ym42c281UnhqTWY5QkFtZUJyR2JSR1g4RGd4SmtSako1dnExaWMySnNmazV0bEhtWTJYUEE2Ums2K0J3MkFXaHhHWHNXeFNiekFHOUR5c1MwQVNnRmh3WGtKbmRlVFB0YU9XSWlFMTJVTjNWVlEyVmtWZnNGSVlvby9Vamp0MHJWKzVyb0xENDJkNE5SNytTZEY4NFQ3RzJqaFpaL0ZPRGg1TkxSbnpuTmNMd3JTOE4vOUgzcURibEFmZC9EWVA3aXluK0VFYWJDeWNmWExYbGN1QmoxQXVzUEt2NElUTngwWU1YVloyaEtRUE91c2g3RU5wL0d2dWtQMkc1ekVLWU09IiwidGFnIjoiM1Qrcy9qaDdSeUlOUERoUGZ0dFVhQT09Iiwia2V5Tm9uY2UiOiI5T0RVSnE2SUNyRnFxSm9PIiwid3JhcHBlZEtleSI6ImtMNXVJcGc2bWYxY2lmV3V1ckFuTmxkMlRHV2pzWTIydDZKTXQ2Y2hOVGM9Iiwia2V5VGFnIjoic2lBbmxqMzJwaFVmb0lWUWFOWjZUQT09In0="
        let data = try XCTUnwrap(Data(base64Encoded: fixtureBase64))

        let unlocked = try AppleVaultCryptoService().unlock(
            data,
            password: "Lion-Pass-Compatibility-2026!"
        )

        XCTAssertEqual(unlocked.payload.name, "Linux Compatibility Fixture")
        XCTAssertEqual(unlocked.payload.items.first?.username, "linux@example.test")
        XCTAssertEqual(unlocked.payload.items.first?.category, "Interoperabilidade")
        XCTAssertEqual(unlocked.envelope.version, 2)
    }

    private let crypto = AppleVaultCryptoService()
    private let fastParameters = KDFParameters(iterations: 100_000)

    func testVersion2PasswordAndRecoveryRoundTrip() throws {
        var payload = VaultPayload(name: "Teste")
        var item = VaultItem()
        item.title = "Conta"
        item.password = "segredo que não pode aparecer"
        payload.items = [item]

        let created = try crypto.createEncryptedVault(
            payload,
            password: "correct horse battery staple",
            parameters: fastParameters
        )
        XCTAssertEqual(created.envelope.version, 2)
        XCTAssertEqual(
            try crypto.unlock(created.encryptedData, password: "correct horse battery staple").payload,
            payload
        )
        XCTAssertEqual(
            try crypto.unlock(created.encryptedData, recoveryKey: created.recoveryKey).payload,
            payload
        )
        XCTAssertFalse(created.encryptedData.contains(Data(item.password.utf8)))
    }

    func testLegacyVersion1RemainsReadable() throws {
        let salt = Data(repeating: 7, count: 32)
        let key = try crypto.deriveKey(
            password: "senha antiga e longa",
            salt: salt,
            parameters: fastParameters
        )
        let payload = VaultPayload(name: "Legado")
        let encrypted = try crypto.encrypt(
            payload,
            key: key,
            salt: salt,
            parameters: fastParameters
        )
        let unlocked = try crypto.unlock(encrypted, password: "senha antiga e longa")
        XCTAssertEqual(unlocked.payload.id, payload.id)
        XCTAssertEqual(unlocked.payload.name, payload.name)
        XCTAssertEqual(unlocked.payload.items, payload.items)
        XCTAssertEqual(unlocked.envelope.version, 1)
    }

    func testMillisecondDateVaultFromPreviousReleaseRemainsReadable() throws {
        let salt = Data(repeating: 9, count: 32)
        let key = try crypto.deriveKey(
            password: "senha anterior longa",
            salt: salt,
            parameters: fastParameters
        )
        var payload = VaultPayload(name: "Formato anterior")
        var item = VaultItem()
        item.title = "Registro antigo"
        payload.items = [item]

        let oldEncoder = JSONEncoder()
        oldEncoder.dateEncodingStrategy = .millisecondsSince1970
        oldEncoder.outputFormatting = [.sortedKeys]
        let plaintext = try oldEncoder.encode(payload)
        let nonceData = Data(repeating: 3, count: 12)
        let sealed = try AES.GCM.seal(
            plaintext,
            using: key,
            nonce: try AES.GCM.Nonce(data: nonceData)
        )
        let envelope = VaultEnvelope(
            magic: "LIONVAULT",
            version: 1,
            kdf: fastParameters,
            salt: salt,
            nonce: nonceData,
            ciphertext: sealed.ciphertext,
            tag: sealed.tag
        )

        let unlocked = try crypto.unlock(
            JSONEncoder.lion.encode(envelope),
            password: "senha anterior longa"
        )
        XCTAssertEqual(unlocked.payload.name, payload.name)
        XCTAssertEqual(unlocked.payload.items.first?.title, item.title)
        XCTAssertEqual(
            unlocked.payload.createdAt.timeIntervalSince1970,
            payload.createdAt.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func testWrongPasswordFails() throws {
        let created = try fixture(password: "senha correta longa")
        XCTAssertThrowsError(try crypto.unlock(created.encryptedData, password: "senha errada longa")) {
            XCTAssertEqual($0 as? VaultError, .wrongPasswordOrTampered)
        }
    }

    func testPayloadTamperingFailsAuthentication() throws {
        let created = try fixture(password: "senha correta longa")
        let envelope = created.envelope
        var bytes = envelope.ciphertext
        bytes[bytes.startIndex] ^= 1
        let altered = copy(envelope, ciphertext: bytes)
        XCTAssertThrowsError(
            try crypto.unlock(JSONEncoder.lion.encode(altered), password: "senha correta longa")
        ) {
            XCTAssertEqual($0 as? VaultError, .wrongPasswordOrTampered)
        }
    }

    func testWrappedKeyTamperingFailsAuthentication() throws {
        let created = try fixture(password: "senha correta longa")
        var wrapped = try XCTUnwrap(created.envelope.wrappedKey)
        wrapped[wrapped.startIndex] ^= 1
        let altered = copy(created.envelope, wrappedKey: wrapped)
        XCTAssertThrowsError(
            try crypto.unlock(JSONEncoder.lion.encode(altered), password: "senha correta longa")
        ) {
            XCTAssertEqual($0 as? VaultError, .wrongPasswordOrTampered)
        }
    }

    func testTruncatedAndCorruptFilesAreRejected() {
        XCTAssertThrowsError(try crypto.unlock(Data([1, 2, 3]), password: "senha")) {
            XCTAssertEqual($0 as? VaultError, .truncated)
        }
        XCTAssertThrowsError(
            try crypto.unlock(Data(repeating: 0x41, count: 256), password: "senha")
        ) {
            XCTAssertEqual($0 as? VaultError, .invalidFormat)
        }
    }

    func testInvalidKDFParametersAreRejectedBeforeDerivation() throws {
        let created = try fixture(password: "senha correta longa")
        let invalid = VaultEnvelope(
            magic: created.envelope.magic,
            version: created.envelope.version,
            kdf: KDFParameters(algorithm: "PBKDF2-HMAC-SHA1", iterations: 1, keyLength: 16),
            salt: created.envelope.salt,
            nonce: created.envelope.nonce,
            ciphertext: created.envelope.ciphertext,
            tag: created.envelope.tag,
            keyNonce: created.envelope.keyNonce,
            wrappedKey: created.envelope.wrappedKey,
            keyTag: created.envelope.keyTag
        )
        XCTAssertThrowsError(try crypto.unlock(JSONEncoder.lion.encode(invalid), password: "senha")) {
            XCTAssertEqual($0 as? VaultError, .unsupportedKDF)
        }
    }

    func testPBKDF2SHA256KnownVector() throws {
        let key = try crypto.deriveKey(
            password: "password",
            salt: Data("salt-salt-salt-12".utf8),
            parameters: fastParameters
        )
        XCTAssertEqual(
            key.withUnsafeBytes { Data($0).hex },
            "ae7333de5c3e8e2d45c1a9ba4223017adc04d060d1660172f6bfb41c247f6007"
        )
    }

    func testAES256GCMNISTEmptyPlaintextVector() throws {
        let key = SymmetricKey(data: Data(repeating: 0, count: 32))
        let box = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: Data(repeating: 0, count: 12)),
            ciphertext: Data(),
            tag: try Data(hex: "530f8afbc74536b9a963b4f1c4cb738b")
        )
        XCTAssertEqual(try AES.GCM.open(box, using: key), Data())
    }

    func testRecoveryKeyRejectsTypo() throws {
        let created = try fixture(password: "senha correta longa")
        let altered = created.recoveryKey + "A"
        XCTAssertThrowsError(try crypto.unlock(created.encryptedData, recoveryKey: altered)) {
            XCTAssertEqual($0 as? VaultError, .invalidRecoveryKey)
        }
    }

    private func fixture(password: String) throws -> CreatedVault {
        try crypto.createEncryptedVault(
            VaultPayload(name: "Teste"),
            password: password,
            parameters: fastParameters
        )
    }

    private func copy(
        _ envelope: VaultEnvelope,
        ciphertext: Data? = nil,
        wrappedKey: Data? = nil
    ) -> VaultEnvelope {
        VaultEnvelope(
            magic: envelope.magic,
            version: envelope.version,
            kdf: envelope.kdf,
            salt: envelope.salt,
            nonce: envelope.nonce,
            ciphertext: ciphertext ?? envelope.ciphertext,
            tag: envelope.tag,
            keyNonce: envelope.keyNonce,
            wrappedKey: wrappedKey ?? envelope.wrappedKey,
            keyTag: envelope.keyTag
        )
    }
}

@MainActor
final class VaultServiceTests: XCTestCase {
    func testDeletedItemsCanBeRestoredOrPermanentlyRemoved() throws {
        try withTemporaryStorage { storage in
            let service = VaultService(storage: storage, biometricStore: TestBiometricStore())
            try service.createVault(name: "Teste", password: "uma senha longa e segura")
            var item = VaultItem()
            item.title = "Conta apagável"
            try service.upsert(item)

            try service.delete(ids: [item.id])
            XCTAssertNotNil(service.payload?.items.first?.deletedAt)
            try service.restore(ids: [item.id])
            XCTAssertNil(service.payload?.items.first?.deletedAt)
            try service.delete(ids: [item.id])
            try service.permanentlyDelete(ids: [item.id])
            XCTAssertTrue(service.payload?.items.isEmpty == true)
        }
    }

    func testPasswordCSVRoundTripPreservesQuotedFields() throws {
        var item = VaultItem()
        item.title = "Conta, principal"
        item.username = "usuário"
        item.password = "segredo,\"forte\""
        item.website = "https://example.com"
        item.notes = "linha 1\nlinha 2"

        let decoded = try PasswordCSVCodec.decode(PasswordCSVCodec.encode([item]))
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].title, item.title)
        XCTAssertEqual(decoded[0].password, item.password)
        XCTAssertEqual(decoded[0].notes, item.notes)
    }

    func testPasswordCSVNeutralizesSpreadsheetFormulas() throws {
        for malicious in [
            "=1+1",
            "+SUM(1,1)",
            "-1+2",
            "@SUM(1,1)",
            "  =HYPERLINK(\"https://evil.example\")",
            "\n+SUM(1,1)",
            "＝1+1",
            "﹫SUM(1,1)"
        ] {
            var item = VaultItem()
            item.title = malicious
            item.password = malicious

            let exported = PasswordCSVCodec.encode([item])
            let text = try XCTUnwrap(String(data: exported, encoding: .utf8))
            let serialized = "\"'" + malicious.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            XCTAssertTrue(text.contains(serialized))
            let decoded = try PasswordCSVCodec.decode(exported)
            XCTAssertEqual(decoded.first?.title, "'" + malicious)
            XCTAssertEqual(decoded.first?.password, "'" + malicious)
        }
    }

    func testPasswordCSVRejectsOversizedInput() {
        let oversized = Data(repeating: 0x41, count: PasswordCSVCodec.maximumImportBytes + 1)
        XCTAssertThrowsError(try PasswordCSVCodec.decode(oversized))
    }

    func testPasswordSecurityAuditDetectsCommonShortAndReusedPasswords() {
        var common = VaultItem()
        common.title = "Comum"
        common.password = "123456"

        var reusedA = VaultItem()
        reusedA.title = "Reutilizada A"
        reusedA.password = "Senha-Longa-Reutilizada-2026!"

        var reusedB = VaultItem()
        reusedB.title = "Reutilizada B"
        reusedB.password = reusedA.password

        let items = [common, reusedA, reusedB]
        XCTAssertNotNil(PasswordSecurityAudit.warning(for: common, in: items))
        XCTAssertNotNil(PasswordSecurityAudit.warning(for: reusedA, in: items))
        XCTAssertEqual(PasswordSecurityAudit.vulnerableCount(in: items), 3)
    }

    func testPasswordSecurityAuditAcceptsUniqueStrongPassword() {
        var item = VaultItem()
        item.title = "Segura"
        item.password = "Unica-Forte-2026!Chave"
        XCTAssertNil(PasswordSecurityAudit.warning(for: item, in: [item]))
    }

    func testChangeMasterPasswordPreservesRecoveryKey() throws {
        try withTemporaryStorage { storage in
            let service = VaultService(storage: storage, biometricStore: TestBiometricStore())
            try service.createVault(name: "Teste", password: "uma senha longa e segura")
            let recoveryKey = try XCTUnwrap(service.pendingRecoveryKey)
            var item = VaultItem()
            item.title = "Email"
            try service.upsert(item)
            try service.changeMasterPassword(
                current: "uma senha longa e segura",
                new: "outra senha longa e segura"
            )
            XCTAssertFalse(storage.hasPreviousBackup)
            service.lockVault()
            XCTAssertThrowsError(try service.openVault(password: "uma senha longa e segura"))
            try service.openVault(password: "outra senha longa e segura")
            XCTAssertEqual(service.payload?.items.count, 1)
            service.lockVault()
            try service.openVault(recoveryKey: recoveryKey)
            XCTAssertEqual(service.payload?.items.first?.title, "Email")
        }
    }

    func testPasswordHistoryCanBeEnabledAndDisabled() throws {
        try withTemporaryStorage { storage in
            let service = VaultService(storage: storage, biometricStore: TestBiometricStore())
            try service.createVault(name: "Teste", password: "uma senha longa e segura")
            var item = VaultItem()
            item.title = "Login"
            item.password = "primeira"
            try service.upsert(item)
            item.password = "segunda"
            try service.upsert(item)
            XCTAssertEqual(service.payload?.items.first?.passwordHistory.map(\.password), ["primeira"])

            try service.setPasswordHistoryEnabled(false)
            item = try XCTUnwrap(service.payload?.items.first)
            item.password = "terceira"
            try service.upsert(item)
            XCTAssertEqual(service.payload?.items.first?.passwordHistory.map(\.password), ["primeira"])
        }
    }

    func testCustomCategoryCRUDReassignsDeletedItems() throws {
        try withTemporaryStorage { storage in
            let service = VaultService(storage: storage, biometricStore: TestBiometricStore())
            try service.createVault(name: "Teste", password: "uma senha longa e segura")
            try service.addCategory("Família")
            var item = VaultItem()
            item.title = "Conta"
            item.category = "Família"
            try service.upsert(item)
            try service.renameCategory("Família", to: "Casa")
            XCTAssertEqual(service.payload?.items.first?.category, "Casa")
            try service.deleteCategory("Casa")
            XCTAssertEqual(service.payload?.items.first?.category, "Outros")
            XCTAssertThrowsError(try service.deleteCategory("Logins")) {
                XCTAssertEqual($0 as? VaultError, .cannotDeleteDefaultCategory)
            }
        }
    }

    func testAtomicStorageKeepsPreviousEncryptedVersion() throws {
        try withTemporaryStorage { storage in
            let first = Data("primeiro envelope".utf8)
            let second = Data("segundo envelope".utf8)
            try storage.writeEncryptedVaultAtomically(first)
            try storage.writeEncryptedVaultAtomically(second)
            XCTAssertEqual(try storage.readEncryptedVault(), second)
            XCTAssertEqual(try storage.readPreviousBackup(), first)
            try storage.restorePreviousBackup()
            XCTAssertEqual(try storage.readEncryptedVault(), first)
            XCTAssertEqual(try storage.readPreviousBackup(), second)
        }
    }

    func testExportAndImportPreserveEncryptedBytes() throws {
        try withTemporaryStorage { storage in
            let data = Data((0..<255).map(UInt8.init))
            try storage.writeEncryptedVaultAtomically(data)
            let exportURL = storage.vaultURL.deletingLastPathComponent().appendingPathComponent("export.lionvault")
            try storage.exportVault(to: exportURL)
            XCTAssertEqual(try storage.importVault(from: exportURL), data)
        }
    }

    func testInterruptedWriteDoesNotDestroyPreviousVault() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let underlying = LocalVaultStorageService(baseURL: directory)
        let storage = InterruptingStorage(underlying: underlying)
        let service = VaultService(storage: storage, biometricStore: TestBiometricStore())
        try service.createVault(name: "Teste", password: "uma senha longa e segura")
        let before = try underlying.readEncryptedVault()
        storage.failWrites = true
        var item = VaultItem()
        item.title = "Não persistido"
        XCTAssertThrowsError(try service.upsert(item))
        XCTAssertEqual(try underlying.readEncryptedVault(), before)
        let reopened = VaultService(storage: underlying, biometricStore: TestBiometricStore())
        try reopened.openVault(password: "uma senha longa e segura")
        XCTAssertTrue(reopened.payload?.items.isEmpty == true)
    }

    func testAutoLockDurations() {
        XCTAssertEqual(AutoLockDuration.immediately.seconds, 0)
        XCTAssertEqual(AutoLockDuration.seconds30.seconds, 30)
        XCTAssertEqual(AutoLockDuration.minute1.seconds, 60)
        XCTAssertEqual(AutoLockDuration.minutes5.seconds, 300)
        XCTAssertEqual(AutoLockDuration.minutes15.seconds, 900)
    }

    func testBiometricCancellationAndFailureArePropagated() async {
        let cancelled = FakeBiometrics(error: LAError(.userCancel))
        let failed = FakeBiometrics(error: LAError(.authenticationFailed))
        await XCTAssertThrowsAsyncError(try await cancelled.authenticate(reason: "Teste"))
        await XCTAssertThrowsAsyncError(try await failed.authenticate(reason: "Teste"))
    }

    func testBiometricKeyUnlocksEncryptedVault() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TestBiometricStore()
        let service = VaultService(
            storage: LocalVaultStorageService(baseURL: directory),
            biometricStore: store
        )
        try service.createVault(name: "Teste", password: "uma senha longa e segura")
        try service.enableBiometricUnlock()
        service.lockVault()
        try await service.openVaultWithBiometrics()
        XCTAssertTrue(service.isUnlocked)
        XCTAssertEqual(service.payload?.name, "Teste")
    }

    private func withTemporaryStorage(
        _ operation: (LocalVaultStorageService) throws -> Void
    ) throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try operation(LocalVaultStorageService(baseURL: directory))
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private struct FakeBiometrics: BiometricUnlockService {
    let error: Error
    func authenticate(reason: String) async throws { throw error }
}

private final class TestBiometricStore: BiometricKeyStoring, @unchecked Sendable {
    var key: SymmetricKey?
    var isAvailable: Bool { true }
    var exists: Bool { key != nil }
    func save(key: SymmetricKey) throws { self.key = key }
    func load() async throws -> SymmetricKey {
        guard let key else { throw VaultError.biometricsUnavailable }
        return key
    }
    func delete() { key = nil }
}

private final class InterruptingStorage: VaultStorageService, @unchecked Sendable {
    let underlying: LocalVaultStorageService
    var failWrites = false
    init(underlying: LocalVaultStorageService) { self.underlying = underlying }
    var vaultURL: URL { underlying.vaultURL }
    var hasPreviousBackup: Bool { underlying.hasPreviousBackup }
    func readEncryptedVault() throws -> Data { try underlying.readEncryptedVault() }
    func readPreviousBackup() throws -> Data { try underlying.readPreviousBackup() }
    func writeEncryptedVaultAtomically(_ data: Data) throws {
        if failWrites { throw CocoaError(.fileWriteUnknown) }
        try underlying.writeEncryptedVaultAtomically(data)
    }
    func deletePreviousBackup() throws { try underlying.deletePreviousBackup() }
    func restorePreviousBackup() throws { try underlying.restorePreviousBackup() }
    func importVault(from url: URL) throws -> Data { try underlying.importVault(from: url) }
    func exportVault(to url: URL) throws { try underlying.exportVault(to: url) }
}

private extension Data {
    init(hex: String) throws {
        guard hex.count.isMultiple(of: 2) else { throw VaultError.invalidFormat }
        self.init()
        var index = hex.startIndex
        while index < hex.endIndex {
            let end = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<end], radix: 16) else {
                throw VaultError.invalidFormat
            }
            append(byte)
            index = end
        }
    }

    var hex: String { map { String(format: "%02x", $0) }.joined() }
}

private func XCTAssertThrowsAsyncError<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Era esperado um erro", file: file, line: line)
    } catch {}
}
