using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;
using Windows.Security.Credentials.UI;

namespace LionPass.Security;

public sealed class WindowsHelloKeyStore
{
    private static readonly byte[] RecordMagic = Encoding.ASCII.GetBytes("LPWHKSP1");
    private static readonly CngProvider PassportProvider = new("Microsoft Passport Key Storage Provider");
    private const int MaximumKeyNameBytes = 1024;
    private const int MaximumCiphertextBytes = 16 * 1024;

    private readonly string _keyPath;
    private readonly string _keyNamePrefix;

    public WindowsHelloKeyStore(string? baseDirectory = null)
    {
        baseDirectory ??= Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Lion Code Technology", "Lion Pass");
        Directory.CreateDirectory(baseDirectory);
        _keyPath = Path.Combine(baseDirectory, "hello-key.dat");

        var directoryHash = SHA256.HashData(Encoding.UTF8.GetBytes(Path.GetFullPath(baseDirectory)));
        _keyNamePrefix = $"LionPass-{Convert.ToHexString(directoryHash.AsSpan(0, 8))}";

        RemoveLegacyDpapiRecord();
    }

    public bool Exists
    {
        get
        {
            try
            {
                return TryReadRecord(out var keyName, out _) && CngKey.Exists(
                    keyName, PassportProvider, CngKeyOpenOptions.UserKey);
            }
            catch (CryptographicException)
            {
                return false;
            }
        }
    }

    public async Task<bool> IsAvailableAsync()
    {
        try
        {
            return await UserConsentVerifier.CheckAvailabilityAsync() ==
                UserConsentVerifierAvailability.Available;
        }
        catch
        {
            return false;
        }
    }

    public async Task SaveAsync(byte[] contentKey)
    {
        if (contentKey.Length != 32) throw new CryptographicException("Chave inválida.");
        await VerifyAsync("Confirme sua identidade para ativar o Windows Hello no Lion Pass.");

        var previousKeyName = TryReadRecord(out var existingKeyName, out _) ? existingKeyName : null;
        var newKeyName = $"{_keyNamePrefix}-{Guid.NewGuid():N}";
        var temporaryPath = $"{_keyPath}.{Guid.NewGuid():N}.tmp";
        var keyCreated = false;

        try
        {
            using var key = CreateHelloProtectedKey(newKeyName);
            keyCreated = true;
            using var rsa = new RSACng(key);
            var encryptedKey = rsa.Encrypt(contentKey, RSAEncryptionPadding.OaepSHA256);
            var record = CreateRecord(newKeyName, encryptedKey);

            await File.WriteAllBytesAsync(temporaryPath, record);
            File.Move(temporaryPath, _keyPath, true);

            if (previousKeyName is not null && previousKeyName != newKeyName)
                DeletePersistedKey(previousKeyName);
        }
        catch
        {
            if (File.Exists(temporaryPath)) File.Delete(temporaryPath);
            if (keyCreated) DeletePersistedKey(newKeyName);
            throw;
        }
    }

    public Task<byte[]> LoadAsync()
    {
        if (!TryReadRecord(out var keyName, out var encryptedKey))
            throw new FileNotFoundException("O Windows Hello ainda não foi ativado.");

        try
        {
            using var key = CngKey.Open(keyName, PassportProvider, CngKeyOpenOptions.UserKey);
            using var rsa = new RSACng(key);
            var contentKey = rsa.Decrypt(encryptedKey, RSAEncryptionPadding.OaepSHA256);
            if (contentKey.Length != 32)
            {
                CryptographicOperations.ZeroMemory(contentKey);
                throw new CryptographicException("A chave protegida pelo Windows Hello é inválida.");
            }
            return Task.FromResult(contentKey);
        }
        catch (CryptographicException error)
        {
            throw new UnauthorizedAccessException(
                "O Windows Hello não autorizou o acesso à chave do Lion Pass.", error);
        }
    }

    public void Delete()
    {
        if (TryReadRecord(out var keyName, out _))
            DeletePersistedKey(keyName);
        if (File.Exists(_keyPath)) File.Delete(_keyPath);
    }

    private static CngKey CreateHelloProtectedKey(string keyName)
    {
        var creation = new CngKeyCreationParameters
        {
            Provider = PassportProvider,
            ExportPolicy = CngExportPolicies.None,
            KeyUsage = CngKeyUsages.Decryption,
            KeyCreationOptions = CngKeyCreationOptions.None,
            UIPolicy = new CngUIPolicy(
                CngUIProtectionLevels.ForceHighProtection,
                "Lion Pass",
                "Protege a chave do cofre com o Windows Hello.",
                "Desbloquear o cofre Lion Pass")
        };
        creation.Parameters.Add(new CngProperty(
            "Length",
            BitConverter.GetBytes(2048),
            CngPropertyOptions.None));
        return CngKey.Create(CngAlgorithm.Rsa, keyName, creation);
    }

    private static byte[] CreateRecord(string keyName, byte[] encryptedKey)
    {
        var keyNameBytes = Encoding.UTF8.GetBytes(keyName);
        var record = new byte[RecordMagic.Length + 8 + keyNameBytes.Length + encryptedKey.Length];
        RecordMagic.CopyTo(record, 0);
        BinaryPrimitives.WriteInt32LittleEndian(
            record.AsSpan(RecordMagic.Length, 4), keyNameBytes.Length);
        BinaryPrimitives.WriteInt32LittleEndian(
            record.AsSpan(RecordMagic.Length + 4, 4), encryptedKey.Length);
        keyNameBytes.CopyTo(record, RecordMagic.Length + 8);
        encryptedKey.CopyTo(record, RecordMagic.Length + 8 + keyNameBytes.Length);
        return record;
    }

    private bool TryReadRecord(out string keyName, out byte[] encryptedKey)
    {
        keyName = string.Empty;
        encryptedKey = [];

        if (!File.Exists(_keyPath)) return false;
        var record = File.ReadAllBytes(_keyPath);
        if (record.Length < RecordMagic.Length + 8 ||
            !record.AsSpan(0, RecordMagic.Length).SequenceEqual(RecordMagic))
            return false;

        var keyNameLength = BinaryPrimitives.ReadInt32LittleEndian(
            record.AsSpan(RecordMagic.Length, 4));
        var ciphertextLength = BinaryPrimitives.ReadInt32LittleEndian(
            record.AsSpan(RecordMagic.Length + 4, 4));
        var payloadOffset = RecordMagic.Length + 8;

        if (keyNameLength <= 0 || keyNameLength > MaximumKeyNameBytes ||
            ciphertextLength <= 0 || ciphertextLength > MaximumCiphertextBytes ||
            payloadOffset + keyNameLength + ciphertextLength != record.Length)
            throw new CryptographicException("Registro do Windows Hello inválido.");

        keyName = Encoding.UTF8.GetString(record, payloadOffset, keyNameLength);
        encryptedKey = record.AsSpan(
            payloadOffset + keyNameLength, ciphertextLength).ToArray();
        return true;
    }

    private void RemoveLegacyDpapiRecord()
    {
        if (!File.Exists(_keyPath)) return;
        using var stream = File.OpenRead(_keyPath);
        Span<byte> magic = stackalloc byte[RecordMagic.Length];
        if (stream.Read(magic) != magic.Length || !magic.SequenceEqual(RecordMagic))
            File.Delete(_keyPath);
    }

    private static void DeletePersistedKey(string keyName)
    {
        try
        {
            if (!CngKey.Exists(keyName, PassportProvider, CngKeyOpenOptions.UserKey)) return;
            using var key = CngKey.Open(keyName, PassportProvider, CngKeyOpenOptions.UserKey);
            key.Delete();
        }
        catch (CryptographicException)
        {
            // A remoção é idempotente; uma chave já ausente não deve impedir a limpeza local.
        }
    }

    private static async Task VerifyAsync(string message)
    {
        if (await UserConsentVerifier.CheckAvailabilityAsync() != UserConsentVerifierAvailability.Available)
            throw new InvalidOperationException("O Windows Hello não está disponível ou não foi configurado.");
        var result = await UserConsentVerifier.RequestVerificationAsync(message);
        if (result != UserConsentVerificationResult.Verified)
            throw new UnauthorizedAccessException("A verificação pelo Windows Hello não foi concluída.");
    }
}
