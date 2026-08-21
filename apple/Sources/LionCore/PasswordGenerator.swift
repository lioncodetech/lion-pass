import Foundation
import Security

public struct PasswordOptions: Sendable {
    public var length = 24
    public var uppercase = true
    public var lowercase = true
    public var digits = true
    public var symbols = true
    public var excludeSimilar = true

    public init() {}
}

public enum SecurePasswordGenerator {
    private static let similarCharacters = Set("Il1O0|")
    private static let passphrasePrefixes = [
        "azul", "bravo", "claro", "doce", "exato", "feliz", "gentil", "honesto",
        "ideal", "jovem", "livre", "manso", "nobre", "novo", "pronto", "puro",
        "rapido", "raro", "sereno", "solar", "suave", "terno", "unico", "vasto",
        "verde", "vivo", "agil", "calmo", "forte", "justo", "leal", "seguro"
    ]
    private static let passphraseSuffixes = [
        "amora", "aurora", "bosque", "brisa", "cedro", "cristal", "duna", "estrela",
        "farol", "folha", "ilha", "jardim", "lago", "leao", "lua", "marfim",
        "nuvem", "oceano", "pedra", "ponte", "rio", "serra", "sol", "vento",
        "campo", "chave", "fonte", "monte", "porto", "trilha", "vale", "vila"
    ]

    public static func password(options: PasswordOptions) throws -> String {
        var groups: [[Character]] = []
        if options.uppercase { groups.append(Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")) }
        if options.lowercase { groups.append(Array("abcdefghijklmnopqrstuvwxyz")) }
        if options.digits { groups.append(Array("0123456789")) }
        if options.symbols { groups.append(Array("!@#$%^&*()-_=+[]{};:,.?")) }
        if options.excludeSimilar {
            groups = groups.map { $0.filter { !similarCharacters.contains($0) } }
        }
        groups.removeAll(where: \.isEmpty)
        guard groups.isEmpty == false else { return "" }

        let length = max(8, max(options.length, groups.count))
        let alphabet = groups.flatMap { $0 }
        var result: [Character] = try groups.map { group in
            group[try randomIndex(upperBound: group.count)]
        }
        while result.count < length {
            result.append(alphabet[try randomIndex(upperBound: alphabet.count)])
        }
        try secureShuffle(&result)
        return String(result)
    }

    public static func passphrase(
        words: Int,
        separator: String,
        capitalize: Bool,
        includeNumber: Bool
    ) throws -> String {
        var result = try (0..<max(6, words)).map { _ in
            passphrasePrefixes[try randomIndex(upperBound: passphrasePrefixes.count)]
                + passphraseSuffixes[try randomIndex(upperBound: passphraseSuffixes.count)]
        }
        if capitalize {
            result = result.map { $0.prefix(1).uppercased() + $0.dropFirst() }
        }
        if includeNumber { result.append(String(try randomIndex(upperBound: 100))) }
        return result.joined(separator: separator)
    }

    public static func passphraseEntropyBits(words: Int, includeNumber: Bool) -> Int {
        let combinationsPerWord = passphrasePrefixes.count * passphraseSuffixes.count
        let wordEntropy = log2(Double(combinationsPerWord)) * Double(max(6, words))
        let numberEntropy = includeNumber ? log2(Double(100)) : 0
        return Int((wordEntropy + numberEntropy).rounded(.down))
    }

    public static func estimatedEntropyBits(options: PasswordOptions) -> Int {
        var count = 0
        if options.uppercase { count += 26 }
        if options.lowercase { count += 26 }
        if options.digits { count += 10 }
        if options.symbols { count += 25 }
        if options.excludeSimilar { count = max(1, count - 6) }
        return Int((log2(Double(max(1, count))) * Double(max(8, options.length))).rounded(.down))
    }

    private static func secureShuffle(_ values: inout [Character]) throws {
        guard values.count > 1 else { return }
        for index in stride(from: values.count - 1, through: 1, by: -1) {
            let destination = try randomIndex(upperBound: index + 1)
            if index != destination { values.swapAt(index, destination) }
        }
    }

    private static func randomIndex(upperBound: Int) throws -> Int {
        guard upperBound > 0, upperBound <= Int(UInt32.max) else {
            throw VaultError.invalidFormat
        }
        let bound = UInt32(upperBound)
        let limit = UInt32.max - UInt32.max % bound
        var value: UInt32 = 0
        repeat {
            guard SecRandomCopyBytes(kSecRandomDefault, 4, &value) == errSecSuccess else {
                throw VaultError.invalidFormat
            }
        } while value >= limit
        return Int(value % bound)
    }
}
