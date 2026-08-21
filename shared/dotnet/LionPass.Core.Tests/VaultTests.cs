using LionPass.Core;
using Xunit;

namespace LionPass.Core.Tests;

public sealed class VaultTests : IDisposable
{
    private const string Password = "correct horse battery staple";
    private readonly string _directory = Path.Combine(Path.GetTempPath(), "LionPassTests", Guid.NewGuid().ToString());

    [Fact]
    public void VersionTwoRoundTripPreservesEveryImportantField()
    {
        var item = new VaultItem
        {
            Title = "Fixture Login", Username = "synthetic@example.test",
            Password = "Strong-Unique-Password-2026!", Website = "https://example.test",
            Email = "synthetic@example.test", Notes = "No real credentials",
            Category = "Trabalho", Tags = ["fixture", "compatibility"], IsFavorite = true,
            CustomFields = [new CustomField { Name = "Tenant", Value = "Lion", IsSensitive = false }]
        };
        var payload = new VaultPayload { Name = "Compatibility", Items = [item], CustomCategories = ["Laboratório"] };
        var crypto = new VaultCryptoService();

        var created = crypto.Create(payload, Password);
        var unlocked = crypto.Unlock(created.EncryptedData, Password);

        Assert.Equal("Compatibility", unlocked.Payload.Name);
        Assert.Equal(item.Id, unlocked.Payload.Items.Single().Id);
        Assert.Equal("synthetic@example.test", unlocked.Payload.Items.Single().Username);
        Assert.Equal("Laboratório", unlocked.Payload.CustomCategories.Single());
        Assert.Equal(2, unlocked.Envelope.Version);
    }

    [Fact]
    public void AppleVersionTwoFixtureIsCompatible()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "apple-v2.lionvault");
        var unlocked = new VaultCryptoService().Unlock(File.ReadAllBytes(path), "Lion-Pass-Compatibility-2026!");
        Assert.Equal("Apple Compatibility Fixture", unlocked.Payload.Name);
        Assert.Equal("apple@example.test", unlocked.Payload.Items.Single().Username);
        Assert.Equal("Interoperabilidade", unlocked.Payload.Items.Single().Category);
        Assert.Equal(2, unlocked.Envelope.Version);
    }

    [Fact]
    public void LinuxVersionTwoFixtureIsCompatible()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "linux-v2.lionvault");
        var unlocked = new VaultCryptoService().Unlock(File.ReadAllBytes(path), "Lion-Pass-Compatibility-2026!");
        Assert.Equal("Linux Compatibility Fixture", unlocked.Payload.Name);
        Assert.Equal("linux@example.test", unlocked.Payload.Items.Single().Username);
        Assert.Equal("Interoperabilidade", unlocked.Payload.Items.Single().Category);
        Assert.Equal(2, unlocked.Envelope.Version);
    }

    [Fact]
    public void WrongPasswordAndTamperingAreRejected()
    {
        var crypto = new VaultCryptoService();
        var created = crypto.Create(new VaultPayload(), Password);
        Assert.Throws<VaultException>(() => crypto.Unlock(created.EncryptedData, "definitely wrong"));
        created.Envelope.Ciphertext[0] ^= 0x80;
        var tampered = System.Text.Json.JsonSerializer.SerializeToUtf8Bytes(
            created.Envelope, new System.Text.Json.JsonSerializerOptions { PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase });
        Assert.Throws<VaultException>(() => crypto.Unlock(tampered, Password));
    }

    [Fact]
    public void RecoveryKeyUnlocksAndDetectsChecksumChanges()
    {
        var crypto = new VaultCryptoService();
        var created = crypto.Create(new VaultPayload { Name = "Recovery" }, Password);
        Assert.Equal("Recovery", crypto.UnlockWithRecoveryKey(created.EncryptedData, created.RecoveryKey).Payload.Name);
        var changed = created.RecoveryKey[..^1] + (created.RecoveryKey[^1] == 'A' ? "B" : "A");
        Assert.Throws<VaultException>(() => crypto.UnlockWithRecoveryKey(created.EncryptedData, changed));
    }

    [Fact]
    public void CsvRoundTripSupportsQuotesCommasAndNewLines()
    {
        var original = new VaultItem { Title = "Example, Inc.", Username = "user", Password = "secret", Notes = "line 1\nline \"2\"" };
        var decoded = CsvTransfer.Import(CsvTransfer.Export([original])).Single();
        Assert.Equal(original.Title, decoded.Title);
        Assert.Equal(original.Notes, decoded.Notes);
    }

    [Theory]
    [InlineData("=HYPERLINK(\"https://evil.example\")")]
    [InlineData("+SUM(1,1)")]
    [InlineData("-1+2")]
    [InlineData("@SUM(1,1)")]
    public void CsvExportNeutralizesSpreadsheetFormulas(string malicious)
    {
        var csv = CsvTransfer.Export([new VaultItem { Title = malicious, Password = malicious }]);
        Assert.Contains("'" + malicious.Replace("\"", "\"\""), csv);
        var decoded = CsvTransfer.Import(csv).Single();
        Assert.Equal("'" + malicious, decoded.Title);
        Assert.Equal("'" + malicious, decoded.Password);
    }

    [Fact]
    public void ServiceSoftDeletesRestoresAndPermanentlyDeletes()
    {
        Directory.CreateDirectory(_directory);
        using var service = new VaultService(new VaultCryptoService(), new VaultStorageService(_directory));
        service.Create("Test", Password);
        var item = new VaultItem { Title = "Temporary", Password = "Long-Enough-Password" };
        service.Upsert(item);
        service.SoftDelete([item.Id]);
        Assert.NotNull(service.Payload!.Items.Single().DeletedAt);
        service.Restore([item.Id]);
        Assert.Null(service.Payload.Items.Single().DeletedAt);
        service.SoftDelete([item.Id]);
        service.PermanentlyDelete([item.Id]);
        Assert.Empty(service.Payload.Items);
    }

    [Fact]
    public void ServiceImportsItemsAndManagesCustomCategories()
    {
        Directory.CreateDirectory(_directory);
        using var service = new VaultService(new VaultCryptoService(), new VaultStorageService(_directory));
        service.Create("Test", Password);
        service.AddCategory("Laboratório");
        service.ImportItems([new VaultItem { Title = "Imported", Category = "Laboratório" }]);
        service.RenameCategory("Laboratório", "Compatibilidade");
        Assert.Equal("Compatibilidade", service.Payload!.Items.Single().Category);
        service.DeleteCategory("Compatibilidade");
        Assert.Equal("Outros", service.Payload.Items.Single().Category);
    }

    [Fact]
    public void SecurityAuditMatchesAppleRules()
    {
        var shortPassword = new VaultItem { Password = "123456" };
        var strong = new VaultItem { Password = "Unique-And-Strong-2026!" };
        Assert.NotNull(PasswordSecurityAudit.Warning(shortPassword, [shortPassword, strong]));
        Assert.Null(PasswordSecurityAudit.Warning(strong, [shortPassword, strong]));
    }

    public void Dispose()
    {
        if (Directory.Exists(_directory)) Directory.Delete(_directory, true);
    }
}
