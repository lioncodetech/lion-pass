using System.Diagnostics;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using LionPass.Core;

namespace LionPass.App;

internal sealed record CreateVaultResult(string Name, string Password, bool StoreInKeyring);
internal sealed record LinuxSettings(int AutoLockMinutes, bool PasswordHistoryEnabled, bool StoreInKeyring, string Language, bool LanguageChosen, bool AutomaticUpdates, bool ReceiveBetaUpdates);

internal static class Dialogs
{
    public static async Task ShowMessageAsync(Window owner, string title, string message)
    {
        title = L(title); message = L(message);
        var window = BaseWindow(title, 500, 260);
        var close = new Button { Content = L("OK"), Classes = { "brand" }, HorizontalAlignment = HorizontalAlignment.Right };
        close.Click += (_, _) => window.Close();
        window.Content = new StackPanel
        {
            Margin = new Thickness(24), Spacing = 18,
            Children =
            {
                new TextBlock { Text = title, FontSize = 24, FontWeight = Avalonia.Media.FontWeight.Bold },
                new TextBlock { Text = message, TextWrapping = Avalonia.Media.TextWrapping.Wrap }, close
            }
        };
        await window.ShowDialog(owner);
    }

    public static async Task<bool> ConfirmAsync(Window owner, string title, string message, string confirmLabel = "Continuar")
    {
        title = L(title); message = L(message); confirmLabel = L(confirmLabel);
        var window = BaseWindow(title, 500, 280);
        var cancel = new Button { Content = L("Cancelar") };
        var confirm = new Button { Content = confirmLabel, Classes = { "brand" } };
        cancel.Click += (_, _) => window.Close(false);
        confirm.Click += (_, _) => window.Close(true);
        window.Content = new StackPanel
        {
            Margin = new Thickness(24), Spacing = 18,
            Children =
            {
                new TextBlock { Text = title, FontSize = 24, FontWeight = Avalonia.Media.FontWeight.Bold },
                new TextBlock { Text = message, TextWrapping = Avalonia.Media.TextWrapping.Wrap },
                new StackPanel
                {
                    Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right,
                    Spacing = 8, Children = { cancel, confirm }
                }
            }
        };
        return await window.ShowDialog<bool>(owner);
    }

    public static async Task<string?> PromptAsync(Window owner, string title, string label, bool password = false)
    {
        title = L(title); label = L(label);
        var window = BaseWindow(title, 460, 220);
        var input = new TextBox { Watermark = label, PasswordChar = password ? '●' : '\0' };
        var cancel = new Button { Content = L("Cancelar") };
        var confirm = new Button { Content = L("Confirmar"), Classes = { "brand" } };
        cancel.Click += (_, _) => window.Close(null);
        confirm.Click += (_, _) => window.Close(input.Text);
        window.Content = new StackPanel
        {
            Margin = new Thickness(24), Spacing = 16,
            Children =
            {
                new TextBlock { Text = title, FontSize = 22, FontWeight = Avalonia.Media.FontWeight.Bold }, input,
                new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Spacing = 8, Children = { cancel, confirm } }
            }
        };
        input.AttachedToVisualTree += (_, _) => input.Focus();
        return await window.ShowDialog<string?>(owner);
    }

    public static async Task<CreateVaultResult?> CreateVaultAsync(Window owner)
    {
        var window = BaseWindow(L("Criar cofre"), 500, 390);
        var name = new TextBox { Watermark = L("Nome do cofre"), Text = L("My Pass") };
        var password = new TextBox { Watermark = L("Senha mestra — mínimo de 12 caracteres"), PasswordChar = '●' };
        var confirmation = new TextBox { Watermark = L("Confirmar senha"), PasswordChar = '●' };
        var status = new TextBlock { Foreground = Avalonia.Media.Brushes.IndianRed, TextWrapping = Avalonia.Media.TextWrapping.Wrap };
        var cancel = new Button { Content = L("Cancelar") };
        var create = new Button { Content = L("Criar"), Classes = { "brand" } };
        cancel.Click += (_, _) => window.Close(null);
        create.Click += (_, _) =>
        {
            if ((password.Text?.Length ?? 0) < 12) { status.Text = L("A senha mestra deve ter pelo menos 12 caracteres."); return; }
            if (password.Text != confirmation.Text) { status.Text = L("As senhas não coincidem."); return; }
            window.Close(new CreateVaultResult(name.Text?.Trim() ?? L("My Pass"), password.Text!, false));
        };
        window.Content = new StackPanel
        {
            Margin = new Thickness(24), Spacing = 13,
            Children =
            {
                new TextBlock { Text = L("Criar cofre local"), FontSize = 24, FontWeight = Avalonia.Media.FontWeight.Bold },
                name, password, confirmation, status,
                new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Spacing = 8, Children = { cancel, create } }
            }
        };
        return await window.ShowDialog<CreateVaultResult?>(owner);
    }

    public static async Task<VaultItem?> EditItemAsync(Window owner, VaultItem source, IReadOnlyList<string> categories)
    {
        var item = source with
        {
            Tags = source.Tags.ToList(), CustomFields = source.CustomFields.ToList(),
            PasswordHistory = source.PasswordHistory.ToList()
        };
        var window = BaseWindow(source.Title.Length == 0 ? L("Novo item") : L("Editar item"), 620, 720);
        window.CanResize = true;
        var kindOptions = Enum.GetValues<VaultItemKind>().Select(value => new TypeOption(value)).ToList();
        var kind = new ComboBox { ItemsSource = kindOptions, SelectedItem = kindOptions.First(option => option.Value == item.Kind) };
        var title = Field(L("Título"), item.Title);
        var username = Field(L("Usuário"), item.Username);
        var password = Field(L("Senha"), item.Password, true);
        var website = Field(L("Site"), item.Website);
        var email = Field(L("E-mail"), item.Email);
        var tags = Field(L("Tags separadas por vírgula"), string.Join(", ", item.Tags));
        var categoryOptions = categories.Select(value => new CategoryOption(value)).ToList();
        var category = new ComboBox { ItemsSource = categoryOptions, SelectedItem = categoryOptions.FirstOrDefault(option => option.Value == item.Category) };
        var favorite = new CheckBox { Content = L("Favorito"), IsChecked = item.IsFavorite };
        var cardholder = Field(L("Titular do cartão"), item.Cardholder);
        var cardNumber = Field(L("Número do cartão"), item.CardNumber);
        var expiry = Field(L("Validade"), item.Expiry);
        var securityCode = Field(L("Código de segurança"), item.SecurityCode, true);
        var bank = Field(L("Banco"), item.Bank);
        var notes = Field(L("Notas"), item.Notes); notes.AcceptsReturn = true; notes.MinHeight = 90; notes.TextWrapping = Avalonia.Media.TextWrapping.Wrap;
        var generate = new Button { Content = L("Gerar senha segura"), HorizontalAlignment = HorizontalAlignment.Right };
        generate.Click += (_, _) => password.Text = PasswordGenerator.Generate();
        var cancel = new Button { Content = L("Cancelar") };
        var save = new Button { Content = L("Salvar"), Classes = { "brand" } };
        cancel.Click += (_, _) => window.Close(null);
        save.Click += (_, _) =>
        {
            if (string.IsNullOrWhiteSpace(title.Text)) return;
            item.Kind = (kind.SelectedItem as TypeOption)?.Value ?? VaultItemKind.Login;
            item.Title = title.Text.Trim(); item.Username = username.Text ?? ""; item.Password = password.Text ?? "";
            item.Website = website.Text?.Trim() ?? ""; item.Email = email.Text?.Trim() ?? ""; item.Notes = notes.Text ?? "";
            item.Tags = (tags.Text ?? "").Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Distinct(StringComparer.CurrentCultureIgnoreCase).ToList();
            item.Category = (category.SelectedItem as CategoryOption)?.Value ?? "Outros"; item.IsFavorite = favorite.IsChecked == true;
            item.Cardholder = cardholder.Text ?? ""; item.CardNumber = cardNumber.Text ?? ""; item.Expiry = expiry.Text ?? "";
            item.SecurityCode = securityCode.Text ?? ""; item.Bank = bank.Text ?? "";
            window.Close(item);
        };
        var form = new StackPanel
        {
            Spacing = 10,
            Children =
            {
                Label(L("Tipo")), kind, Label(L("Título")), title, Label(L("Usuário")), username, Label(L("Senha")), password, generate,
                Label(L("Site")), website, Label(L("E-mail")), email, Label(L("Tags")), tags, Label(L("Categoria")), category, favorite,
                Label(L("Dados de cartão (opcional)")), cardholder, cardNumber, expiry, securityCode, bank,
                Label(L("Notas")), notes,
                new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Spacing = 8, Children = { cancel, save } }
            }
        };
        window.Content = new ScrollViewer { Content = form, Margin = new Thickness(24) };
        return await window.ShowDialog<VaultItem?>(owner);
    }

    public static async Task<LinuxSettings?> SettingsAsync(Window owner, LinuxSettings current, bool keyringAvailable)
    {
        var window = BaseWindow(L("Configurações"), 620, 680);
        var timeout = new NumericUpDown { Minimum = 1, Maximum = 120, Value = current.AutoLockMinutes, Increment = 1 };
        var history = new CheckBox { Content = L("Manter histórico local de alterações de senha"), IsChecked = current.PasswordHistoryEnabled };
        var language = LanguageSelector(current.Language);
        var keyringNotice = new TextBlock
        {
            Text = L("Por segurança, a chave de conteúdo não é salva no chaveiro da sessão. O desbloqueio exige a senha mestra."),
            TextWrapping = Avalonia.Media.TextWrapping.Wrap, Classes = { "muted" }
        };
var automaticUpdates = new CheckBox { Content = L("Atualizações automáticas"), IsChecked = current.AutomaticUpdates };
var betaUpdates = new CheckBox { Content = L("Receber versões beta"), IsChecked = current.ReceiveBetaUpdates };
var version = typeof(Dialogs).Assembly.GetName().Version?.ToString(3) ?? "1.0.0";
var currentVersion = new TextBlock { Text = LinuxLocalization.Format("Versão atual: {0}", version), Classes = { "muted" } };
var checkUpdates = new Button { Content = L("Verificar atualização") };
var stableRelease = new Button { Content = L("Voltar para a última versão estável") };
checkUpdates.Click += (_, _) => OpenReleasePage(betaUpdates.IsChecked == true);
stableRelease.Click += (_, _) => OpenReleasePage(false);
var updateButtons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, Children = { checkUpdates, stableRelease } };
        var cancel = new Button { Content = L("Cancelar") };
        var save = new Button { Content = L("Salvar"), Classes = { "brand" } };
        cancel.Click += (_, _) => window.Close(null);
        save.Click += (_, _) => window.Close(new LinuxSettings((int)(timeout.Value ?? 5), history.IsChecked == true, false, LanguageForIndex(language.SelectedIndex), true, automaticUpdates.IsChecked == true, betaUpdates.IsChecked == true));
        window.Content = new StackPanel
        {
            Margin = new Thickness(24), Spacing = 16,
            Children =
            {
                new TextBlock { Text = L("Segurança e privacidade"), FontSize = 24, FontWeight = Avalonia.Media.FontWeight.Bold },
                Label("Idioma"), language,
                Label(L("Bloquear automaticamente após (minutos)")), timeout, history, keyringNotice,
                new TextBlock { Text = L("O Lion Pass funciona offline. Nenhum cofre, senha ou diagnóstico é enviado a servidores."), TextWrapping = Avalonia.Media.TextWrapping.Wrap, Classes = { "muted" } },
                Label(L("Atualizações")), automaticUpdates, betaUpdates, currentVersion, updateButtons,
                new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Spacing = 8, Children = { cancel, save } }
            }
        };
        return await window.ShowDialog<LinuxSettings?>(owner);
    }

    public static async Task<string?> SelectLanguageAsync(Window owner, string current)
    {
        var window = BaseWindow("Idioma / Language / Idioma", 500, 310);
        var selector = LanguageSelector(current);
        var cancel = new Button { Content = "Cancelar / Cancel / Cancelar" };
        var confirm = new Button { Content = "Continuar / Continue / Continuar", Classes = { "brand" } };
        cancel.Click += (_, _) => window.Close(null);
        confirm.Click += (_, _) => window.Close(LanguageForIndex(selector.SelectedIndex));
        window.Content = new StackPanel
        {
            Margin = new Thickness(24), Spacing = 16,
            Children =
            {
                new TextBlock { Text = "Escolha seu idioma / Choose your language / Elija su idioma", FontSize = 24, FontWeight = Avalonia.Media.FontWeight.Bold, TextWrapping = Avalonia.Media.TextWrapping.Wrap },
                selector,
                new TextBlock { Text = "Você poderá mudar o idioma depois em Configurações. / You can change the language later in Settings. / Podrá cambiar el idioma más tarde en Configuración.", TextWrapping = Avalonia.Media.TextWrapping.Wrap, Classes = { "muted" } },
                new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Spacing = 8, Children = { cancel, confirm } }
            }
        };
        return await window.ShowDialog<string?>(owner);
    }

private static void OpenReleasePage(bool includeBeta)
{
    var path = includeBeta ? "releases" : "releases/latest";
    Process.Start(new ProcessStartInfo("https://github.com/lioncodetech/lion-pass/" + path) { UseShellExecute = true });
}

    private static ComboBox LanguageSelector(string current) => new()
    {
        ItemsSource = new[] { "Português (Brasil)", "English", "Español" },
        SelectedIndex = LinuxLocalization.Normalize(current) switch { "en-US" => 1, "es-ES" => 2, _ => 0 },
        HorizontalAlignment = HorizontalAlignment.Stretch
    };

    private static string LanguageForIndex(int index) => index switch { 1 => "en-US", 2 => "es-ES", _ => "pt-BR" };

    private sealed record TypeOption(VaultItemKind Value)
    {
        public override string ToString() => Value switch
        {
            VaultItemKind.Login => L("Logins"), VaultItemKind.Card => L("Cartões"),
            VaultItemKind.SecureNote => L("Notas seguras"), VaultItemKind.Identity => L("Identidades"), _ => L("Outros")
        };
    }

    private sealed record CategoryOption(string Value)
    {
        public override string ToString() => L(Value);
    }

    private static Window BaseWindow(string title, double width, double height) => new()
    {
        Title = title, Width = width, Height = height, WindowStartupLocation = WindowStartupLocation.CenterOwner,
        CanResize = false, ShowInTaskbar = false
    };

    private static TextBox Field(string watermark, string value, bool secret = false) => new()
    { Watermark = L(watermark), Text = value, PasswordChar = secret ? '●' : '\0' };

    private static TextBlock Label(string value) => new() { Text = L(value), FontWeight = Avalonia.Media.FontWeight.SemiBold };
    private static string L(string value) => LinuxLocalization.Text(value);
}
