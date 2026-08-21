using System.Text;
using System.Text.Json.Serialization;

namespace LionPass.Core;

public enum VaultItemKind
{
    Login,
    Card,
    SecureNote,
    Identity,
    Other
}

public sealed record CustomField
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "";
    public string Value { get; set; } = "";
    public bool IsSensitive { get; set; }
}

public sealed record PasswordRevision
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Password { get; set; } = "";
    public DateTimeOffset ChangedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed record VaultItem
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public VaultItemKind Kind { get; set; } = VaultItemKind.Login;
    public string Title { get; set; } = "";
    public string Username { get; set; } = "";
    public string Password { get; set; } = "";
    public string Website { get; set; } = "";
    public string Email { get; set; } = "";
    public string Notes { get; set; } = "";
    public string Category { get; set; } = "Logins";
    public List<string> Tags { get; set; } = [];
    public bool IsFavorite { get; set; }
    public List<CustomField> CustomFields { get; set; } = [];
    public List<PasswordRevision> PasswordHistory { get; set; } = [];
    public string Cardholder { get; set; } = "";
    public string CardNumber { get; set; } = "";
    public string Expiry { get; set; } = "";
    public string SecurityCode { get; set; } = "";
    public string Bank { get; set; } = "";
    public string CardBrand { get; set; } = "";
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? DeletedAt { get; set; }

    [JsonIgnore]
    public string DisplayInitial
    {
        get
        {
            var value = string.IsNullOrWhiteSpace(Title) ? "?" : Title.Trim();
            return value[..1].ToUpper(System.Globalization.CultureInfo.CurrentCulture);
        }
    }

    public bool Matches(string query)
    {
        if (string.IsNullOrWhiteSpace(query)) return true;
        var searchable = string.Join(' ',
            Title, Username, Website, Email, Category, string.Join(' ', Tags));
        return searchable.Contains(query.Trim(), StringComparison.CurrentCultureIgnoreCase);
    }
}

public sealed record VaultPayload
{
    public static readonly IReadOnlyList<string> DefaultCategories =
    [
        "Logins", "E-mail", "Bancos", "Redes sociais", "Trabalho", "Compras",
        "Streaming", "Wi-Fi", "Cartões", "Notas", "Identidades", "Outros"
    ];

    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "My Pass";
    public List<VaultItem> Items { get; set; } = [];
    public List<string> CustomCategories { get; set; } = [];
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset ModifiedAt { get; set; } = DateTimeOffset.UtcNow;
    public bool PasswordHistoryEnabled { get; set; } = true;

    [JsonIgnore]
    public IReadOnlyList<string> AllCategories => DefaultCategories
        .Concat(CustomCategories)
        .Where(value => !string.IsNullOrWhiteSpace(value))
        .Distinct(StringComparer.CurrentCultureIgnoreCase)
        .ToArray();
}

public sealed record KdfParameters
{
    public string Algorithm { get; set; } = "PBKDF2-HMAC-SHA256";
    public uint Iterations { get; set; } = 600_000;
    public int KeyLength { get; set; } = 32;
}

public sealed record VaultEnvelope
{
    public string Magic { get; set; } = "LIONVAULT";
    public int Version { get; set; } = 2;
    public KdfParameters Kdf { get; set; } = new();
    public byte[] Salt { get; set; } = [];
    public byte[] Nonce { get; set; } = [];
    public byte[] Ciphertext { get; set; } = [];
    public byte[] Tag { get; set; } = [];
    public byte[]? KeyNonce { get; set; }
    public byte[]? WrappedKey { get; set; }
    public byte[]? KeyTag { get; set; }
}

public sealed record CreatedVault(
    byte[] EncryptedData,
    byte[] ContentKey,
    string RecoveryKey,
    VaultEnvelope Envelope);

public sealed record UnlockedVault(
    VaultPayload Payload,
    byte[] ContentKey,
    VaultEnvelope Envelope);

public sealed class VaultException(string message) : Exception(message)
{
    public static VaultException InvalidFormat() => new("O arquivo não é um cofre Lion válido.");
    public static VaultException WrongPassword() => new("Senha incorreta ou arquivo adulterado.");
    public static VaultException NotOpen() => new("O cofre está bloqueado.");
}
