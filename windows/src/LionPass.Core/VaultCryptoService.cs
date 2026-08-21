using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace LionPass.Core;

public sealed class VaultCryptoService
{
    private const string Magic = "LIONVAULT";
    private const string RecoveryPrefix = "LION-RECOVERY-";

    public CreatedVault Create(VaultPayload payload, string password, KdfParameters? parameters = null)
    {
        parameters ??= new KdfParameters();
        Validate(parameters);
        var contentKey = RandomNumberGenerator.GetBytes(32);
        var salt = RandomNumberGenerator.GetBytes(32);
        var passwordKey = DeriveKey(password, salt, parameters);
        try
        {
            var wrapped = Seal(contentKey, passwordKey);
            var encrypted = Seal(JsonSerializer.SerializeToUtf8Bytes(payload, LionJson.Options), contentKey);
            var envelope = new VaultEnvelope
            {
                Magic = Magic,
                Version = 2,
                Kdf = parameters,
                Salt = salt,
                Nonce = encrypted.Nonce,
                Ciphertext = encrypted.Ciphertext,
                Tag = encrypted.Tag,
                KeyNonce = wrapped.Nonce,
                WrappedKey = wrapped.Ciphertext,
                KeyTag = wrapped.Tag
            };
            return new CreatedVault(
                JsonSerializer.SerializeToUtf8Bytes(envelope, LionJson.Options),
                contentKey,
                CreateRecoveryKey(contentKey),
                envelope);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(passwordKey);
        }
    }

    public UnlockedVault Unlock(byte[] data, string password)
    {
        var envelope = DecodeEnvelope(data);
        var passwordKey = DeriveKey(password, envelope.Salt, envelope.Kdf);
        try
        {
            byte[] contentKey;
            try
            {
                contentKey = envelope.Version == 1
                    ? passwordKey.ToArray()
                    : Open(envelope.KeyNonce!, envelope.WrappedKey!, envelope.KeyTag!, passwordKey);
                return Unlock(data, contentKey);
            }
            catch (CryptographicException)
            {
                throw VaultException.WrongPassword();
            }
        }
        finally
        {
            CryptographicOperations.ZeroMemory(passwordKey);
        }
    }

    public UnlockedVault UnlockWithRecoveryKey(byte[] data, string recoveryKey) =>
        Unlock(data, ParseRecoveryKey(recoveryKey));

    public UnlockedVault Unlock(byte[] data, byte[] contentKey)
    {
        if (contentKey.Length != 32) throw VaultException.WrongPassword();
        var envelope = DecodeEnvelope(data);
        try
        {
            var plain = Open(envelope.Nonce, envelope.Ciphertext, envelope.Tag, contentKey);
            var payload = JsonSerializer.Deserialize<VaultPayload>(plain, LionJson.Options)
                ?? throw VaultException.InvalidFormat();
            return new UnlockedVault(payload, contentKey.ToArray(), envelope);
        }
        catch (CryptographicException)
        {
            throw VaultException.WrongPassword();
        }
        catch (JsonException)
        {
            throw VaultException.WrongPassword();
        }
    }

    public byte[] Encrypt(VaultPayload payload, byte[] contentKey, VaultEnvelope existing)
    {
        Validate(existing);
        if (contentKey.Length != 32) throw VaultException.InvalidFormat();
        var encrypted = Seal(JsonSerializer.SerializeToUtf8Bytes(payload, LionJson.Options), contentKey);
        var envelope = existing with
        {
            Nonce = encrypted.Nonce,
            Ciphertext = encrypted.Ciphertext,
            Tag = encrypted.Tag
        };
        return JsonSerializer.SerializeToUtf8Bytes(envelope, LionJson.Options);
    }

    public byte[] Rewrap(byte[] data, byte[] contentKey, string newPassword, KdfParameters? parameters = null)
    {
        _ = Unlock(data, contentKey);
        parameters ??= new KdfParameters();
        Validate(parameters);
        var current = DecodeEnvelope(data);
        var salt = RandomNumberGenerator.GetBytes(32);
        var passwordKey = DeriveKey(newPassword, salt, parameters);
        try
        {
            var wrapped = Seal(contentKey, passwordKey);
            var envelope = current with
            {
                Version = 2,
                Kdf = parameters,
                Salt = salt,
                KeyNonce = wrapped.Nonce,
                WrappedKey = wrapped.Ciphertext,
                KeyTag = wrapped.Tag
            };
            return JsonSerializer.SerializeToUtf8Bytes(envelope, LionJson.Options);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(passwordKey);
        }
    }

    public VaultEnvelope DecodeEnvelope(byte[] data)
    {
        if (data.Length <= 64) throw VaultException.InvalidFormat();
        try
        {
            var envelope = JsonSerializer.Deserialize<VaultEnvelope>(data, LionJson.Options)
                ?? throw VaultException.InvalidFormat();
            Validate(envelope);
            return envelope;
        }
        catch (JsonException)
        {
            throw VaultException.InvalidFormat();
        }
    }

    public static string CreateRecoveryKey(byte[] contentKey)
    {
        if (contentKey.Length != 32) throw VaultException.InvalidFormat();
        var checksum = SHA256.HashData(contentKey)[..4];
        var value = Convert.ToBase64String([.. contentKey, .. checksum])
            .TrimEnd('=').Replace('+', '-').Replace('/', '_');
        return RecoveryPrefix + value;
    }

    private static byte[] ParseRecoveryKey(string recoveryKey)
    {
        var compact = recoveryKey.Trim();
        if (!compact.StartsWith(RecoveryPrefix, StringComparison.OrdinalIgnoreCase))
            throw new VaultException("A chave de recuperação é inválida.");
        var encoded = compact[RecoveryPrefix.Length..].Replace('-', '+').Replace('_', '/');
        encoded = encoded.PadRight((encoded.Length + 3) / 4 * 4, '=');
        byte[] decoded;
        try { decoded = Convert.FromBase64String(encoded); }
        catch (FormatException) { throw new VaultException("A chave de recuperação é inválida."); }
        if (decoded.Length != 36) throw new VaultException("A chave de recuperação é inválida.");
        var key = decoded[..32];
        if (!CryptographicOperations.FixedTimeEquals(decoded[32..], SHA256.HashData(key)[..4]))
            throw new VaultException("A chave de recuperação é inválida.");
        return key;
    }

    private static byte[] DeriveKey(string password, byte[] salt, KdfParameters parameters)
    {
        Validate(parameters);
        if (salt.Length < 16) throw VaultException.InvalidFormat();
        return Rfc2898DeriveBytes.Pbkdf2(
            Encoding.UTF8.GetBytes(password), salt, checked((int)parameters.Iterations),
            HashAlgorithmName.SHA256, parameters.KeyLength);
    }

    private static (byte[] Nonce, byte[] Ciphertext, byte[] Tag) Seal(byte[] plain, byte[] key)
    {
        var nonce = RandomNumberGenerator.GetBytes(12);
        var ciphertext = new byte[plain.Length];
        var tag = new byte[16];
        using var aes = new AesGcm(key, 16);
        aes.Encrypt(nonce, plain, ciphertext, tag);
        return (nonce, ciphertext, tag);
    }

    private static byte[] Open(byte[] nonce, byte[] ciphertext, byte[] tag, byte[] key)
    {
        var plain = new byte[ciphertext.Length];
        using var aes = new AesGcm(key, 16);
        aes.Decrypt(nonce, ciphertext, tag, plain);
        return plain;
    }

    private static void Validate(KdfParameters parameters)
    {
        if (parameters.Algorithm != "PBKDF2-HMAC-SHA256")
            throw new VaultException("O algoritmo KDF não é suportado.");
        if (parameters.Iterations is < 100_000 or > 5_000_000 || parameters.KeyLength != 32)
            throw new VaultException("Os parâmetros de segurança do cofre são inválidos.");
    }

    private static void Validate(VaultEnvelope envelope)
    {
        if (envelope.Magic != Magic || envelope.Version is < 1 or > 2) throw VaultException.InvalidFormat();
        Validate(envelope.Kdf);
        if (envelope.Salt.Length < 16 || envelope.Nonce.Length != 12 ||
            envelope.Tag.Length != 16 || envelope.Ciphertext.Length == 0) throw VaultException.InvalidFormat();
        if (envelope.Version == 2 &&
            (envelope.KeyNonce?.Length != 12 || envelope.WrappedKey?.Length != 32 || envelope.KeyTag?.Length != 16))
            throw VaultException.InvalidFormat();
    }
}
