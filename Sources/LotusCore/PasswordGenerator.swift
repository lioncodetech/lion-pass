import Foundation
import Security

public struct PasswordOptions: Sendable { public var length = 24; public var uppercase = true; public var lowercase = true; public var digits = true; public var symbols = true; public var excludeSimilar = true; public init() {} }

public enum SecurePasswordGenerator {
    public static func password(options: PasswordOptions) throws -> String {
        var alphabet = ""; if options.uppercase { alphabet += "ABCDEFGHIJKLMNOPQRSTUVWXYZ" }; if options.lowercase { alphabet += "abcdefghijklmnopqrstuvwxyz" }
        if options.digits { alphabet += "0123456789" }; if options.symbols { alphabet += "!@#$%^&*()-_=+[]{};:,.?" }
        if options.excludeSimilar { alphabet.removeAll { "Il1O0|".contains($0) } }; guard !alphabet.isEmpty else { return "" }
        let chars = Array(alphabet); return try String((0..<max(4, options.length)).map { _ in chars[try randomIndex(upperBound: chars.count)] })
    }
    public static func passphrase(words: Int, separator: String, capitalize: Bool, includeNumber: Bool) throws -> String {
        let dictionary = ["amora","aurora","bosque","brisa","cedro","cristal","duna","estrela","farol","folha","ilha","jardim","lago","lótus","lua","marfim","nuvem","oceano","pedra","ponte","rio","serra","sol","vento"]
        var result = try (0..<max(3, words)).map { _ in dictionary[try randomIndex(upperBound: dictionary.count)] }
        if capitalize { result = result.map { $0.prefix(1).uppercased() + $0.dropFirst() } }; if includeNumber { result.append(String(try randomIndex(upperBound: 100))) }
        return result.joined(separator: separator)
    }
    private static func randomIndex(upperBound: Int) throws -> Int {
        let limit = UInt32.max - UInt32.max % UInt32(upperBound); var value: UInt32 = 0
        repeat { guard SecRandomCopyBytes(kSecRandomDefault, 4, &value) == errSecSuccess else { throw VaultError.invalidFormat } } while value >= limit
        return Int(value % UInt32(upperBound))
    }
}
