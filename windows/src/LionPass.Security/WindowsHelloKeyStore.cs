using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using Windows.Security.Credentials.UI;

namespace LionPass.Security;

public sealed class WindowsHelloKeyStore
{
    private readonly string _keyPath;

    public WindowsHelloKeyStore(string? baseDirectory = null)
    {
        baseDirectory ??= Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Lion Code Technology", "Lion Pass");
        Directory.CreateDirectory(baseDirectory);
        _keyPath = Path.Combine(baseDirectory, "hello-key.dat");
    }

    public bool Exists => File.Exists(_keyPath);

    public async Task<bool> IsAvailableAsync() =>
        await UserConsentVerifier.CheckAvailabilityAsync() == UserConsentVerifierAvailability.Available;

    public async Task SaveAsync(byte[] contentKey)
    {
        if (contentKey.Length != 32) throw new CryptographicException("Chave inválida.");
        await VerifyAsync("Confirme sua identidade para ativar o Windows Hello no Lion Pass.");
        var protectedKey = Dpapi.Protect(contentKey);
        await File.WriteAllBytesAsync(_keyPath, protectedKey);
    }

    public async Task<byte[]> LoadAsync()
    {
        if (!Exists) throw new FileNotFoundException("O Windows Hello ainda não foi ativado.");
        await VerifyAsync("Desbloquear o cofre Lion Pass.");
        return Dpapi.Unprotect(await File.ReadAllBytesAsync(_keyPath));
    }

    public void Delete()
    {
        if (File.Exists(_keyPath)) File.Delete(_keyPath);
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

internal static class Dpapi
{
    private const int CryptProtectUiForbidden = 0x1;

    [StructLayout(LayoutKind.Sequential)]
    private struct DataBlob { public int Size; public IntPtr Data; }

    [DllImport("crypt32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CryptProtectData(
        ref DataBlob input, string? description, IntPtr entropy, IntPtr reserved,
        IntPtr prompt, int flags, ref DataBlob output);

    [DllImport("crypt32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CryptUnprotectData(
        ref DataBlob input, IntPtr description, IntPtr entropy, IntPtr reserved,
        IntPtr prompt, int flags, ref DataBlob output);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr LocalFree(IntPtr memory);

    internal static byte[] Protect(byte[] value) => Transform(value, true);
    internal static byte[] Unprotect(byte[] value) => Transform(value, false);

    private static byte[] Transform(byte[] value, bool protect)
    {
        var input = new DataBlob { Size = value.Length, Data = Marshal.AllocHGlobal(value.Length) };
        var output = new DataBlob();
        try
        {
            Marshal.Copy(value, 0, input.Data, value.Length);
            var success = protect
                ? CryptProtectData(ref input, "Lion Pass Windows Hello key", IntPtr.Zero, IntPtr.Zero,
                    IntPtr.Zero, CryptProtectUiForbidden, ref output)
                : CryptUnprotectData(ref input, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero,
                    IntPtr.Zero, CryptProtectUiForbidden, ref output);
            if (!success) throw new Win32Exception(Marshal.GetLastWin32Error());
            var result = new byte[output.Size];
            Marshal.Copy(output.Data, result, 0, output.Size);
            return result;
        }
        finally
        {
            if (input.Data != IntPtr.Zero)
            {
                Marshal.Copy(new byte[value.Length], 0, input.Data, value.Length);
                Marshal.FreeHGlobal(input.Data);
            }
            if (output.Data != IntPtr.Zero) _ = LocalFree(output.Data);
        }
    }
}
