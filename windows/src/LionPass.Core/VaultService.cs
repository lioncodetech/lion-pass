using System.Security.Cryptography;

namespace LionPass.Core;

public sealed class VaultService : IDisposable
{
    private readonly VaultCryptoService _crypto;
    private readonly VaultStorageService _storage;
    private byte[]? _contentKey;
    private VaultEnvelope? _envelope;

    public VaultPayload? Payload { get; private set; }
    public bool IsUnlocked => Payload is not null && _contentKey is not null;
    public bool HasVault => _storage.HasVault;
    public string? PendingRecoveryKey { get; private set; }

    public VaultService(VaultCryptoService crypto, VaultStorageService storage)
    { _crypto = crypto; _storage = storage; }

    public string Create(string name, string password)
    {
        if (string.IsNullOrWhiteSpace(name) || password.Length < 12) throw VaultException.InvalidFormat();
        var payload = new VaultPayload { Name = name.Trim() };
        var created = _crypto.Create(payload, password);
        _storage.WriteAtomically(created.EncryptedData);
        Apply(new UnlockedVault(payload, created.ContentKey, created.Envelope));
        PendingRecoveryKey = created.RecoveryKey;
        return created.RecoveryKey;
    }

    public void Open(string password) => Apply(_crypto.Unlock(_storage.Read(), password));
    public void OpenWithRecoveryKey(string recoveryKey) => Apply(_crypto.UnlockWithRecoveryKey(_storage.Read(), recoveryKey));
    public void OpenWithContentKey(byte[] key) => Apply(_crypto.Unlock(_storage.Read(), key));
    public byte[] GetContentKey() => _contentKey?.ToArray() ?? throw VaultException.NotOpen();

    public void Lock()
    {
        if (_contentKey is not null) CryptographicOperations.ZeroMemory(_contentKey);
        _contentKey = null; _envelope = null; Payload = null; PendingRecoveryKey = null;
    }

    public void Save()
    {
        var payload = Payload ?? throw VaultException.NotOpen();
        var key = _contentKey ?? throw VaultException.NotOpen();
        var envelope = _envelope ?? throw VaultException.NotOpen();
        payload.ModifiedAt = DateTimeOffset.UtcNow;
        var data = _crypto.Encrypt(payload, key, envelope);
        _ = _crypto.Unlock(data, key);
        _storage.WriteAtomically(data);
        _envelope = _crypto.DecodeEnvelope(data);
    }

    public void Upsert(VaultItem item)
    {
        var payload = Payload ?? throw VaultException.NotOpen();
        var existing = payload.Items.FindIndex(value => value.Id == item.Id);
        item.UpdatedAt = DateTimeOffset.UtcNow;
        if (existing >= 0)
        {
            var previous = payload.Items[existing];
            item.CreatedAt = previous.CreatedAt;
            if (payload.PasswordHistoryEnabled && previous.Password.Length > 0 && previous.Password != item.Password)
            {
                item.PasswordHistory = previous.PasswordHistory.ToList();
                if (item.PasswordHistory.LastOrDefault()?.Password != previous.Password)
                    item.PasswordHistory.Add(new PasswordRevision { Password = previous.Password });
                item.PasswordHistory = item.PasswordHistory.TakeLast(20).ToList();
            }
            payload.Items[existing] = item;
        }
        else payload.Items.Add(item);
        Save();
    }

    public void SoftDelete(IEnumerable<Guid> ids) => Mutate(ids, item => item.DeletedAt = DateTimeOffset.UtcNow);
    public void Restore(IEnumerable<Guid> ids) => Mutate(ids, item => item.DeletedAt = null);
    public void PermanentlyDelete(IEnumerable<Guid> ids)
    {
        var selected = ids.ToHashSet();
        (Payload ?? throw VaultException.NotOpen()).Items.RemoveAll(item => item.DeletedAt is not null && selected.Contains(item.Id));
        Save();
    }

    public void ImportItems(IEnumerable<VaultItem> items)
    {
        var payload = Payload ?? throw VaultException.NotOpen();
        var existing = payload.Items.Select(item => item.Id).ToHashSet();
        foreach (var source in items)
        {
            var item = source with { };
            if (existing.Contains(item.Id)) item.Id = Guid.NewGuid();
            item.DeletedAt = null;
            item.UpdatedAt = DateTimeOffset.UtcNow;
            payload.Items.Add(item);
            existing.Add(item.Id);
        }
        Save();
    }

    public void AddCategory(string name)
    {
        var payload = Payload ?? throw VaultException.NotOpen();
        var clean = name.Trim();
        if (clean.Length == 0) throw VaultException.InvalidFormat();
        if (payload.AllCategories.Contains(clean, StringComparer.CurrentCultureIgnoreCase))
            throw new VaultException("Já existe uma categoria com esse nome.");
        payload.CustomCategories.Add(clean);
        Save();
    }

    public void RenameCategory(string current, string replacement)
    {
        var payload = Payload ?? throw VaultException.NotOpen();
        var index = payload.CustomCategories.FindIndex(value => value.Equals(current, StringComparison.CurrentCultureIgnoreCase));
        if (index < 0) throw new VaultException("Somente categorias personalizadas podem ser renomeadas.");
        var clean = replacement.Trim();
        if (clean.Length == 0 || payload.AllCategories.Any(value => !value.Equals(current, StringComparison.CurrentCultureIgnoreCase) && value.Equals(clean, StringComparison.CurrentCultureIgnoreCase)))
            throw new VaultException("O novo nome de categoria é inválido ou já existe.");
        payload.CustomCategories[index] = clean;
        foreach (var item in payload.Items.Where(item => item.Category.Equals(current, StringComparison.CurrentCultureIgnoreCase))) item.Category = clean;
        Save();
    }

    public void DeleteCategory(string name)
    {
        var payload = Payload ?? throw VaultException.NotOpen();
        if (VaultPayload.DefaultCategories.Contains(name, StringComparer.CurrentCultureIgnoreCase))
            throw new VaultException("As categorias padrão não podem ser apagadas.");
        if (!payload.CustomCategories.Remove(name)) throw new VaultException("A categoria não foi encontrada.");
        foreach (var item in payload.Items.Where(item => item.Category.Equals(name, StringComparison.CurrentCultureIgnoreCase))) item.Category = "Outros";
        Save();
    }

    public void ChangeMasterPassword(string current, string replacement)
    {
        if (replacement.Length < 12) throw VaultException.InvalidFormat();
        var unlocked = _crypto.Unlock(_storage.Read(), current);
        var data = _crypto.Rewrap(_storage.Read(), unlocked.ContentKey, replacement);
        _ = _crypto.Unlock(data, replacement);
        _storage.WriteAtomically(data);
        Apply(new UnlockedVault(unlocked.Payload, unlocked.ContentKey, _crypto.DecodeEnvelope(data)));
    }

    public void Import(string path, string password)
    {
        _storage.Import(path, password, _crypto);
        Open(password);
    }

    public void Export(string path) => _storage.Export(path);

    private void Mutate(IEnumerable<Guid> ids, Action<VaultItem> action)
    {
        var selected = ids.ToHashSet();
        foreach (var item in (Payload ?? throw VaultException.NotOpen()).Items.Where(item => selected.Contains(item.Id)))
        { action(item); item.UpdatedAt = DateTimeOffset.UtcNow; }
        Save();
    }

    private void Apply(UnlockedVault unlocked)
    {
        Lock();
        Payload = unlocked.Payload;
        _contentKey = unlocked.ContentKey;
        _envelope = unlocked.Envelope;
    }

    public void Dispose() { Lock(); GC.SuppressFinalize(this); }
}
