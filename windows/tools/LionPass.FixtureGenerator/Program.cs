using LionPass.Core;

if (args.Length != 1) throw new ArgumentException("Informe o caminho do fixture.");
var payload = new VaultPayload
{
    Name = "Windows Compatibility Fixture",
    CustomCategories = ["Interoperabilidade"],
    Items =
    [
        new VaultItem
        {
            Title = "Synthetic Windows Login",
            Username = "windows@example.test",
            Password = "Synthetic-Only-Password-2026!",
            Website = "https://example.test/windows",
            Category = "Interoperabilidade",
            Notes = "Fixture criada no Windows; não contém credenciais reais.",
            IsFavorite = true
        }
    ]
};
// Compatibility fixtures use the minimum accepted work factor so CI remains
// fast. Production vaults keep the 600,000-iteration default.
var created = new VaultCryptoService().Create(
    payload,
    "Lion-Pass-Compatibility-2026!",
    new KdfParameters { Iterations = 100_000 });
Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(args[0]))!);
File.WriteAllBytes(args[0], created.EncryptedData);
