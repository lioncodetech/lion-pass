using LionPass.Core;

if (args.Length != 1) throw new ArgumentException("Informe o caminho do fixture.");
var payload = new VaultPayload
{
    Name = "Linux Compatibility Fixture",
    CustomCategories = ["Interoperabilidade"],
    Items =
    [
        new VaultItem
        {
            Title = "Synthetic Linux Login",
            Username = "linux@example.test",
            Password = "Synthetic-Only-Password-2026!",
            Website = "https://example.test/linux",
            Category = "Interoperabilidade",
            Notes = "Fixture criada no Linux; não contém credenciais reais.",
            IsFavorite = true
        }
    ]
};
var created = new VaultCryptoService().Create(
    payload,
    "Lion-Pass-Compatibility-2026!",
    new KdfParameters { Iterations = 100_000 });
Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(args[0]))!);
File.WriteAllBytes(args[0], created.EncryptedData);
