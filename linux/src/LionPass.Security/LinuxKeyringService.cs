using System.Diagnostics;
namespace LionPass.Security;

public sealed class LinuxKeyringService
{
    private static readonly string[] Attributes = ["application", "lion-pass", "vault", "default"];

    // Secret Service has no application-specific ACL after the user’s collection is unlocked.
    public bool IsAvailable => false;

    public async Task<bool> ExistsAsync(CancellationToken cancellationToken = default)
    {
        await DeleteAsync(cancellationToken);
        return false;
    }

    public async Task SaveAsync(byte[] contentKey, CancellationToken cancellationToken = default)
    {
        await Task.CompletedTask;
        throw new NotSupportedException("O desbloqueio persistente foi desativado no Linux por segurança.");
    }

    public async Task<byte[]> LoadAsync(CancellationToken cancellationToken = default)
    {
        await Task.CompletedTask;
        throw new NotSupportedException("O desbloqueio persistente foi desativado no Linux por segurança.");
    }

    public async Task DeleteAsync(CancellationToken cancellationToken = default)
    {
        if (FindSecretTool() is null) return;
        _ = await RunAsync(["clear", .. Attributes], null, cancellationToken);
    }

    private static string? FindSecretTool()
    {
        foreach (var path in new[] { "/usr/bin/secret-tool", "/usr/local/bin/secret-tool", "/bin/secret-tool" })
            if (File.Exists(path)) return path;
        return null;
    }

    private static async Task<CommandResult> RunAsync(IReadOnlyList<string> arguments, string? input, CancellationToken cancellationToken)
    {
        var executable = FindSecretTool() ?? throw new InvalidOperationException("secret-tool não está instalado.");
        var start = new ProcessStartInfo(executable)
        {
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };
        foreach (var argument in arguments) start.ArgumentList.Add(argument);
        using var process = Process.Start(start) ?? throw new InvalidOperationException("Não foi possível iniciar secret-tool.");
        if (input is not null) await process.StandardInput.WriteAsync(input.AsMemory(), cancellationToken);
        process.StandardInput.Close();
        var outputTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var errorTask = process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken);
        return new CommandResult(process.ExitCode, await outputTask, await errorTask);
    }

    private sealed record CommandResult(int ExitCode, string Output, string Error);
}
