using System.Diagnostics;
namespace LionPass.Security;

public sealed class LinuxKeyringService
{
    private static readonly string[] Attributes = ["application", "lion-pass", "vault", "default"];

    public bool IsAvailable => FindSecretTool() is not null;

    public async Task<bool> ExistsAsync(CancellationToken cancellationToken = default)
    {
        if (!IsAvailable) return false;
        var result = await RunAsync(["lookup", .. Attributes], null, cancellationToken);
        return result.ExitCode == 0 && !string.IsNullOrWhiteSpace(result.Output);
    }

    public async Task SaveAsync(byte[] contentKey, CancellationToken cancellationToken = default)
    {
        if (!IsAvailable)
            throw new InvalidOperationException("O Secret Service não está disponível. Instale libsecret-tools e desbloqueie o chaveiro da sessão.");
        var encoded = Convert.ToBase64String(contentKey);
        var result = await RunAsync(["store", "--label=Lion Pass", .. Attributes], encoded, cancellationToken);
        if (result.ExitCode != 0) throw new InvalidOperationException(result.Error.Trim().Length > 0 ? result.Error.Trim() : "Não foi possível salvar a chave no chaveiro Linux.");
    }

    public async Task<byte[]> LoadAsync(CancellationToken cancellationToken = default)
    {
        var result = await RunAsync(["lookup", .. Attributes], null, cancellationToken);
        if (result.ExitCode != 0 || string.IsNullOrWhiteSpace(result.Output))
            throw new InvalidOperationException("A chave do Lion Pass não foi encontrada no chaveiro Linux.");
        try { return Convert.FromBase64String(result.Output.Trim()); }
        catch (FormatException) { throw new InvalidOperationException("A chave armazenada no chaveiro Linux é inválida."); }
    }

    public async Task DeleteAsync(CancellationToken cancellationToken = default)
    {
        if (!IsAvailable) return;
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
