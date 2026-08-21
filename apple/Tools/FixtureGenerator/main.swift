import Foundation

guard CommandLine.arguments.count == 2 else {
    fatalError("Informe o caminho de saída do fixture.")
}

var item = VaultItem()
item.title = "Synthetic Apple Login"
item.username = "apple@example.test"
item.password = "Synthetic-Only-Password-2026!"
item.website = "https://example.test/apple"
item.category = "Interoperabilidade"
item.notes = "Fixture criada no Apple; não contém credenciais reais."
item.isFavorite = true

var payload = VaultPayload(name: "Apple Compatibility Fixture")
payload.customCategories = ["Interoperabilidade"]
payload.items = [item]

let created = try AppleVaultCryptoService().createEncryptedVault(
    payload,
    password: "Lion-Pass-Compatibility-2026!",
    parameters: KDFParameters(iterations: 100_000)
)
try created.encryptedData.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
