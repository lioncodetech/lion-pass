namespace LionPass.Core;

public sealed class VaultStorageService
{
    public string VaultPath { get; }
    public string BackupPath { get; }

    public VaultStorageService(string? baseDirectory = null)
    {
        baseDirectory ??= Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Lion Code Technology", "Lion Pass");
        Directory.CreateDirectory(baseDirectory);
        VaultPath = Path.Combine(baseDirectory, "default.lionvault");
        BackupPath = Path.Combine(baseDirectory, "default.previous.lionvault");
    }

    public bool HasVault => File.Exists(VaultPath);
    public bool HasBackup => File.Exists(BackupPath);
    public byte[] Read() => File.ReadAllBytes(VaultPath);
    public byte[] ReadBackup() => File.ReadAllBytes(BackupPath);

    public void WriteAtomically(byte[] data)
    {
        if (data.Length == 0) throw VaultException.InvalidFormat();
        var temporary = Path.Combine(Path.GetDirectoryName(VaultPath)!, $".{Guid.NewGuid()}.lionvault.tmp");
        try
        {
            File.WriteAllBytes(temporary, data);
            if (!File.ReadAllBytes(temporary).AsSpan().SequenceEqual(data))
                throw new IOException("A gravação segura do cofre não pôde ser verificada.");
            if (File.Exists(VaultPath))
            {
                File.Delete(BackupPath);
                File.Replace(temporary, VaultPath, BackupPath, true);
            }
            else File.Move(temporary, VaultPath);
            if (!Read().AsSpan().SequenceEqual(data))
                throw new IOException("A gravação segura do cofre não pôde ser verificada.");
        }
        finally
        {
            if (File.Exists(temporary)) File.Delete(temporary);
        }
    }

    public void Import(string path, string password, VaultCryptoService crypto)
    {
        var info = new FileInfo(path);
        if (info.Length > 100 * 1024 * 1024) throw VaultException.InvalidFormat();
        var data = File.ReadAllBytes(path);
        _ = crypto.Unlock(data, password);
        WriteAtomically(data);
    }

    public void Export(string path) => File.WriteAllBytes(path, Read());
}
