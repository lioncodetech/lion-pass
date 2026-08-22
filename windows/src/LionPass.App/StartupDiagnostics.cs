using System.Runtime.InteropServices;
using System.Text;

namespace LionPass.App;

internal static class StartupDiagnostics
{
    private const long MaximumLogBytes = 1024 * 1024;
    private const uint MbOk = 0x00000000;
    private const uint MbIconError = 0x00000010;
    private const uint MbSetForeground = 0x00010000;
    private const uint MbTopmost = 0x00040000;
    private static int _installed;
    private static int _dialogShown;

    public static string LogPath { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Lion Code Technology",
        "Lion Pass",
        "Logs",
        "startup.log");

    public static string StartupStatePath { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Lion Code Technology",
        "Lion Pass",
        "Logs",
        "startup.ok");

    public static void Install()
    {
        if (Interlocked.Exchange(ref _installed, 1) != 0)
        {
            return;
        }

        AppDomain.CurrentDomain.UnhandledException += (_, args) =>
        {
            var exception = args.ExceptionObject as Exception
                ?? new Exception(args.ExceptionObject?.ToString() ?? "Erro desconhecido.");
            Report("Exceção não tratada no processo.", exception);
        };

        TaskScheduler.UnobservedTaskException += (_, args) =>
        {
            Report("Exceção não observada em uma tarefa em segundo plano.", args.Exception, false);
            args.SetObserved();
        };
    }

    public static void Report(string context, Exception exception, bool showDialog = true)
    {
        TryWriteReport(BuildReport(context, exception));

        if (!showDialog || Interlocked.Exchange(ref _dialogShown, 1) != 0)
        {
            return;
        }

        var message = WindowsLocalization.Format(
            "O Lion Pass não conseguiu iniciar.\n\n{0}\n\nUm relatório foi salvo em:\n{1}",
            context,
            LogPath);

        try
        {
            _ = MessageBoxW(
                IntPtr.Zero,
                message,
                WindowsLocalization.Text("Lion Pass — erro de inicialização"),
                MbOk | MbIconError | MbSetForeground | MbTopmost);
        }
        catch
        {
            // A escrita do relatório é a alternativa caso nem o diálogo nativo possa ser exibido.
        }
    }

    public static void MarkStartupSucceeded()
    {
        try
        {
            var directory = Path.GetDirectoryName(StartupStatePath);
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }

            File.WriteAllText(StartupStatePath, DateTimeOffset.UtcNow.ToString("O"), Encoding.UTF8);
        }
        catch
        {
            // O marcador é apenas diagnóstico e não pode impedir a abertura do aplicativo.
        }
    }

    private static string BuildReport(string context, Exception exception)
    {
        var report = new StringBuilder();
        report.AppendLine(new string('=', 72));
        report.AppendLine($"Data (UTC): {DateTimeOffset.UtcNow:O}");
        report.AppendLine($"Contexto: {context}");
        report.AppendLine($"Sistema: {RuntimeInformation.OSDescription}");
        report.AppendLine($"Arquitetura: {RuntimeInformation.ProcessArchitecture}");
        report.AppendLine($".NET: {RuntimeInformation.FrameworkDescription}");
        report.AppendLine($"Executável: {Environment.ProcessPath ?? "indisponível"}");
        report.AppendLine($"Diretório base: {AppContext.BaseDirectory}");
        report.AppendLine("Exceção:");
        report.AppendLine(exception.ToString());
        return report.ToString();
    }

    private static void TryWriteReport(string report)
    {
        try
        {
            var directory = Path.GetDirectoryName(LogPath);
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }

            if (File.Exists(LogPath) && new FileInfo(LogPath).Length > MaximumLogBytes)
            {
                File.WriteAllText(LogPath, string.Empty, Encoding.UTF8);
            }

            File.AppendAllText(LogPath, report, Encoding.UTF8);
        }
        catch
        {
            // O diagnóstico nunca deve provocar uma segunda falha durante a inicialização.
        }
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int MessageBoxW(IntPtr window, string text, string caption, uint type);
}
