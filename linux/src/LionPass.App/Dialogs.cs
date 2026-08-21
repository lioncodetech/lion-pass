using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using LionPass.Core;

namespace LionPass.App;

internal sealed record CreateVaultResult(string Name, string Password, bool StoreInKeyring);
internal sealed record LinuxSettings(int AutoLockMinutes, bool PasswordHistoryEnabled, bool StoreInKeyring);

internal static class Dialogs
{
    public static async Task ShowMessageAsync(Window owner, string title, string message)
    {
        var window = BaseWindow(title, 500, 260);
        var close = new Button { Content = "OK", Classes = { "brand" }, HorizontalAlignment = HorizontalAlignment.Right };
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

    public static async Task<string?> PromptAsync(Window owner, string title, string label, bool password = false)
    {
        var window = BaseWindow(title, 460, 220);
        var input = new TextBox { Watermark = label, PasswordChar = password ? '●' : '\0' };
        var cancel = new Button { Content = "Cancelar" };
        var confirm = new Button { Content = "Confirmar", Classes = { "brand" } };
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
        var window = BaseWindow("Criar cofre", 500, 390);
        var name = new TextBox { Watermark = "Nome do cofre", Text = "My Pass" };
        var password = new TextBox { Watermark = "Senha mestra — mínimo de 12 caracteres", PasswordChar = '●' };
        var confirmation = new TextBox { Watermark = "Confirmar senha", PasswordChar = '●' };
        var keyring = new CheckBox { Content = "Salvar desbloqueio no chaveiro Linux" };
        var status = new TextBlock { Foreground = Avalonia.Media.Brushes.IndianRed, TextWrapping = Avalonia.Media.TextWrapping.Wrap };
        var cancel = new Button { Content = "Cancelar" };
        var create = new Button { Content = "Criar", Classes = { "brand" } };
        cancel.Click += (_, _) => window.Close(null);
        create.Click += (_, _) =>
        {
            if ((password.Text?.Length ?? 0) < 12) { status.Text = "A senha mestra deve ter pelo menos 12 caracteres."; return; }
            if (password.Text != confirmation.Text) { status.Text = "As senhas não coincidem."; return; }
            window.Close(new CreateVaultResult(name.Text?.Trim() ?? "My Pass", password.Text!, keyring.IsChecked == true));
        };
        window.Content = new StackPanel
        {
            Margin = new Thickness(24), Spacing = 13,
            Children =
            {
                new TextBlock { Text = "Criar cofre local", FontSize = 24, FontWeight = Avalonia.Media.FontWeight.Bold },
                name, password, confirmation, keyring, status,
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
        var window = BaseWindow(source.Title.Length == 0 ? "Novo item" : "Editar item", 620, 720);
        window.CanResize = true;
        var kind = new ComboBox { ItemsSource = Enum.GetValues<VaultItemKind>(), SelectedItem = item.Kind };
        var title = Field("Título", item.Title);
        var username = Field("Usuário", item.Username);
        var password = Field("Senha", item.Password, true);
        var website = Field("Site", item.Website);
        var email = Field("E-mail", item.Email);
        var tags = Field("Tags separadas por vírgula", string.Join(", ", item.Tags));
        var category = new ComboBox { ItemsSource = categories, SelectedItem = categories.Contains(item.Category) ? item.Category : categories.FirstOrDefault() };
        var favorite = new CheckBox { Content = "Favorito", IsChecked = item.IsFavorite };
        var cardholder = Field("Titular do cartão", item.Cardholder);
        var cardNumber = Field("Número do cartão", item.CardNumber);
        var expiry = Field("Validade", item.Expiry);
        var securityCode = Field("Código de segurança", item.SecurityCode, true);
        var bank = Field("Banco", item.Bank);
        var notes = Field("Notas", item.Notes); notes.AcceptsReturn = true; notes.MinHeight = 90; notes.TextWrapping = Avalonia.Media.TextWrapping.Wrap;
        var generate = new Button { Content = "Gerar senha segura", HorizontalAlignment = HorizontalAlignment.Right };
        generate.Click += (_, _) => password.Text = PasswordGenerator.Generate();
        var cancel = new Button { Content = "Cancelar" };
        var save = new Button { Content = "Salvar", Classes = { "brand" } };
        cancel.Click += (_, _) => window.Close(null);
        save.Click += (_, _) =>
        {
            if (string.IsNullOrWhiteSpace(title.Text)) return;
            item.Kind = kind.SelectedItem is VaultItemKind selectedKind ? selectedKind : VaultItemKind.Login;
            item.Title = title.Text.Trim(); item.Username = username.Text ?? ""; item.Password = password.Text ?? "";
            item.Website = website.Text?.Trim() ?? ""; item.Email = email.Text?.Trim() ?? ""; item.Notes = notes.Text ?? "";
            item.Tags = (tags.Text ?? "").Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Distinct(StringComparer.CurrentCultureIgnoreCase).ToList();
            item.Category = category.SelectedItem?.ToString() ?? "Outros"; item.IsFavorite = favorite.IsChecked == true;
            item.Cardholder = cardholder.Text ?? ""; item.CardNumber = cardNumber.Text ?? ""; item.Expiry = expiry.Text ?? "";
            item.SecurityCode = securityCode.Text ?? ""; item.Bank = bank.Text ?? "";
            window.Close(item);
        };
        var form = new StackPanel
        {
            Spacing = 10,
            Children =
            {
                Label("Tipo"), kind, Label("Título"), title, Label("Usuário"), username, Label("Senha"), password, generate,
                Label("Site"), website, Label("E-mail"), email, Label("Tags"), tags, Label("Categoria"), category, favorite,
                Label("Dados de cartão (opcional)"), cardholder, cardNumber, expiry, securityCode, bank,
                Label("Notas"), notes,
                new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Spacing = 8, Children = { cancel, save } }
            }
        };
        window.Content = new ScrollViewer { Content = form, Margin = new Thickness(24) };
        return await window.ShowDialog<VaultItem?>(owner);
    }

    public static async Task<LinuxSettings?> SettingsAsync(Window owner, LinuxSettings current, bool keyringAvailable)
    {
        var window = BaseWindow("Configurações", 560, 430);
        var timeout = new NumericUpDown { Minimum = 1, Maximum = 120, Value = current.AutoLockMinutes, Increment = 1 };
        var history = new CheckBox { Content = "Manter histórico local de alterações de senha", IsChecked = current.PasswordHistoryEnabled };
        var keyring = new CheckBox
        {
            Content = keyringAvailable ? "Permitir desbloqueio pelo chaveiro Linux" : "Chaveiro Linux indisponível — instale libsecret-tools",
            IsChecked = current.StoreInKeyring && keyringAvailable, IsEnabled = keyringAvailable
        };
        var cancel = new Button { Content = "Cancelar" };
        var save = new Button { Content = "Salvar", Classes = { "brand" } };
        cancel.Click += (_, _) => window.Close(null);
        save.Click += (_, _) => window.Close(new LinuxSettings((int)(timeout.Value ?? 5), history.IsChecked == true, keyring.IsChecked == true));
        window.Content = new StackPanel
        {
            Margin = new Thickness(24), Spacing = 16,
            Children =
            {
                new TextBlock { Text = "Segurança e privacidade", FontSize = 24, FontWeight = Avalonia.Media.FontWeight.Bold },
                Label("Bloquear automaticamente após (minutos)"), timeout, history, keyring,
                new TextBlock { Text = "O Lion Pass funciona offline. Nenhum cofre, senha ou diagnóstico é enviado a servidores.", TextWrapping = Avalonia.Media.TextWrapping.Wrap, Classes = { "muted" } },
                new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Spacing = 8, Children = { cancel, save } }
            }
        };
        return await window.ShowDialog<LinuxSettings?>(owner);
    }

    private static Window BaseWindow(string title, double width, double height) => new()
    {
        Title = title, Width = width, Height = height, WindowStartupLocation = WindowStartupLocation.CenterOwner,
        CanResize = false, ShowInTaskbar = false
    };

    private static TextBox Field(string watermark, string value, bool secret = false) => new()
    { Watermark = watermark, Text = value, PasswordChar = secret ? '●' : '\0' };

    private static TextBlock Label(string value) => new() { Text = value, FontWeight = Avalonia.Media.FontWeight.SemiBold };
}
