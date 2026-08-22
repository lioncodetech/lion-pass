using Microsoft.UI.Xaml;

namespace LionPass.App;

public partial class App : Application
{
    private Window? _window;

    public App()
    {
        StartupDiagnostics.Install();
        try
        {
            InitializeComponent();
        }
        catch (Exception error)
        {
            StartupDiagnostics.Report("Falha ao carregar os recursos visuais do aplicativo.", error);
            throw;
        }

        UnhandledException += (_, args) =>
            StartupDiagnostics.Report("Falha não tratada na interface do aplicativo.", args.Exception);
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        try
        {
            _window = new MainWindow();
            _window.Activate();
            StartupDiagnostics.MarkStartupSucceeded();
        }
        catch (Exception error)
        {
            StartupDiagnostics.Report("Não foi possível abrir a janela principal.", error);
            Environment.Exit(1);
        }
    }
}
