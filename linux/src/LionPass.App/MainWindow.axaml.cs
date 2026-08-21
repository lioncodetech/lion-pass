using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Input.Platform;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;
using Avalonia.Threading;
using LionPass.Core;
using LionPass.Security;

namespace LionPass.App;

public sealed partial class MainWindow : Window
{
    private readonly VaultService _vault = new(new VaultCryptoService(), new VaultStorageService());
    private readonly LinuxKeyringService _keyring = new();
    private readonly ObservableCollection<VaultItem> _visibleItems = [];
    private readonly DispatcherTimer _autoLockTimer = new();
    private string _filter = "all";
    private VaultItem? _selected;
    private bool _passwordVisible;
    private LinuxSettings _settings = LoadSettings();
    private CancellationTokenSource? _clipboardClearCancellation;
    private int _copyConfirmationVersion;

    public MainWindow()
    {
        InitializeComponent();
        ItemsList.ItemsSource = _visibleItems;
        _autoLockTimer.Tick += (_, _) => LockVault();
        PointerPressed += (_, _) => ResetAutoLock();
        KeyDown += (_, _) => ResetAutoLock();
        Opened += async (_, _) => await RefreshKeyringAsync();
        Closed += (_, _) => { _clipboardClearCancellation?.Cancel(); _vault.Dispose(); };
        PopulateNavigation();
    }

    private async void Unlock_Click(object? sender, RoutedEventArgs e) => await UnlockWithPasswordAsync();

    private async void MasterPassword_KeyDown(object? sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter) await UnlockWithPasswordAsync();
    }

    private async Task UnlockWithPasswordAsync()
    {
        UnlockStatus.Text = "";
        try
        {
            _vault.Open(MasterPasswordBox.Text ?? "");
            if (RememberInKeyringCheck.IsChecked == true) await SaveCurrentKeyAsync();
            ShowVault();
        }
        catch (Exception error) { UnlockStatus.Text = error.Message; }
    }

    private async void Keyring_Click(object? sender, RoutedEventArgs e)
    {
        UnlockStatus.Text = "";
        try
        {
            var key = await _keyring.LoadAsync();
            try { _vault.OpenWithContentKey(key); }
            finally { CryptographicOperations.ZeroMemory(key); }
            ShowVault();
        }
        catch (Exception error) { UnlockStatus.Text = error.Message; }
    }

    private async void Create_Click(object? sender, RoutedEventArgs e)
    {
        var result = await Dialogs.CreateVaultAsync(this);
        if (result is null) return;
        try
        {
            var recovery = _vault.Create(result.Name, result.Password);
            if (result.StoreInKeyring) await SaveCurrentKeyAsync();
            await Dialogs.ShowMessageAsync(this, "Chave de recuperação",
                $"Guarde esta chave fora do computador. Ela não será exibida novamente.\n\n{recovery}");
            ShowVault();
        }
        catch (Exception error) { UnlockStatus.Text = error.Message; }
    }

    private async void ImportVault_Click(object? sender, RoutedEventArgs e)
    {
        var files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = "Importar cofre Lion Pass", AllowMultiple = false,
            FileTypeFilter = [new FilePickerFileType("Cofre Lion Pass") { Patterns = ["*.lionvault"] }]
        });
        var file = files.FirstOrDefault();
        if (file is null) return;
        var password = await Dialogs.PromptAsync(this, "Importar cofre", "Senha mestra", true);
        if (password is null) return;
        try
        {
            _vault.Import(file.Path.LocalPath, password);
            if (RememberInKeyringCheck.IsChecked == true) await SaveCurrentKeyAsync();
            ShowVault();
        }
        catch (Exception error) { UnlockStatus.Text = error.Message; }
    }

    private void ShowVault()
    {
        UnlockView.IsVisible = false; VaultView.IsVisible = true;
        MasterPasswordBox.Text = ""; UnlockStatus.Text = "";
        VaultNameText.Text = _vault.Payload?.Name ?? "Lion Pass";
        PopulateNavigation(); RefreshItems(); ResetAutoLock();
    }

    private void Lock_Click(object? sender, RoutedEventArgs e) => LockVault();

    private void LockVault()
    {
        if (!_vault.IsUnlocked) return;
        _autoLockTimer.Stop(); _vault.Lock(); _visibleItems.Clear(); _selected = null;
        _clipboardClearCancellation?.Cancel();
        VaultView.IsVisible = false; UnlockView.IsVisible = true;
        DetailScroll.IsVisible = false; EmptyDetail.IsVisible = true;
        _ = RefreshKeyringAsync();
    }

    private void ResetAutoLock()
    {
        if (!_vault.IsUnlocked) return;
        _autoLockTimer.Stop();
        _autoLockTimer.Interval = TimeSpan.FromMinutes(Math.Clamp(_settings.AutoLockMinutes, 1, 120));
        _autoLockTimer.Start();
    }

    private async Task RefreshKeyringAsync()
    {
        var user = Environment.UserName;
        try
        {
            var available = _vault.HasVault && await _keyring.ExistsAsync();
            KeyringButton.IsVisible = available;
            KeyringBadge.IsVisible = available;
            UnlockInstruction.Text = available
                ? $"Use o chaveiro Linux ou digite a senha mestra do Lion Pass para “{user}”."
                : $"Digite a senha mestra do Lion Pass para “{user}”.";
        }
        catch
        {
            KeyringButton.IsVisible = false;
            KeyringBadge.IsVisible = false;
            UnlockInstruction.Text = $"Digite a senha mestra do Lion Pass para “{user}”.";
        }
        RememberInKeyringCheck.IsVisible = _keyring.IsAvailable;
    }

    private async Task SaveCurrentKeyAsync()
    {
        var key = _vault.GetContentKey();
        try { await _keyring.SaveAsync(key); }
        finally { CryptographicOperations.ZeroMemory(key); }
        _settings = _settings with { StoreInKeyring = true };
        SaveSettings(_settings);
    }

    private void PopulateNavigation()
    {
        TypesPanel.Children.Clear();
        foreach (var value in Enum.GetValues<VaultItemKind>())
        {
            var button = NavigationButton(TypeTitle(value), $"type:{value}");
            TypesPanel.Children.Add(button);
        }
        CategoriesPanel.Children.Clear();
        foreach (var category in _vault.Payload?.AllCategories ?? VaultPayload.DefaultCategories)
            CategoriesPanel.Children.Add(NavigationButton(category, $"category:{category}"));
    }

    private Button NavigationButton(string title, string tag)
    {
        var button = new Button { Content = title, Tag = tag };
        button.Classes.Add("navigation"); button.Click += Filter_Click;
        return button;
    }

    private void Filter_Click(object? sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string tag } button) return;
        _filter = tag; CollectionTitle.Text = button.Content?.ToString() ?? "Itens";
        RefreshItems();
    }

    private void ShowAll_Click(object? sender, RoutedEventArgs e) { _filter = "all"; CollectionTitle.Text = "Todos os itens"; RefreshItems(); }
    private void ShowFavorites_Click(object? sender, RoutedEventArgs e) { _filter = "favorites"; CollectionTitle.Text = "Favoritos"; RefreshItems(); }
    private void ShowSecurity_Click(object? sender, RoutedEventArgs e) { _filter = "security"; CollectionTitle.Text = "Segurança"; RefreshItems(); }
    private void ShowTrash_Click(object? sender, RoutedEventArgs e) { _filter = "trash"; CollectionTitle.Text = "Lixeira"; RefreshItems(); }
    private void SearchBox_TextChanged(object? sender, TextChangedEventArgs e) => RefreshItems();
    private void SortBox_SelectionChanged(object? sender, SelectionChangedEventArgs e) => RefreshItems();

    private void RefreshItems()
    {
        if (_vault.Payload is null) return;
        IEnumerable<VaultItem> values = _vault.Payload.Items;
        values = _filter switch
        {
            "favorites" => values.Where(x => x.DeletedAt is null && x.IsFavorite),
            "security" => values.Where(x => x.DeletedAt is null && PasswordSecurityAudit.Warning(x, _vault.Payload.Items) is not null),
            "trash" => values.Where(x => x.DeletedAt is not null),
            _ when _filter.StartsWith("type:", StringComparison.Ordinal) => values.Where(x => x.DeletedAt is null && x.Kind.ToString() == _filter[5..]),
            _ when _filter.StartsWith("category:", StringComparison.Ordinal) => values.Where(x => x.DeletedAt is null && x.Category == _filter[9..]),
            _ => values.Where(x => x.DeletedAt is null)
        };
        values = values.Where(item => item.Matches(SearchBox.Text ?? ""));
        var sort = (SortBox.SelectedItem as ComboBoxItem)?.Tag?.ToString();
        values = sort switch
        {
            "recent" => values.OrderByDescending(x => x.UpdatedAt),
            "category" => values.OrderBy(x => x.Category).ThenBy(x => x.Title),
            _ => values.OrderBy(x => x.Title, StringComparer.CurrentCultureIgnoreCase)
        };
        var selectedId = _selected?.Id;
        _visibleItems.Clear(); foreach (var value in values) _visibleItems.Add(value);
        ItemCountText.Text = $"{_visibleItems.Count} itens";
        if (selectedId is not null) ItemsList.SelectedItem = _visibleItems.FirstOrDefault(x => x.Id == selectedId);
    }

    private void ItemsList_SelectionChanged(object? sender, SelectionChangedEventArgs e)
    {
        _selected = ItemsList.SelectedItem as VaultItem;
        EmptyDetail.IsVisible = _selected is null; DetailScroll.IsVisible = _selected is not null;
        if (_selected is null) return;
        _passwordVisible = false;
        DetailInitial.Text = _selected.DisplayInitial;
        DetailTitle.Text = _selected.Title; DetailKind.Text = TypeTitle(_selected.Kind);
        DetailUsername.Text = _selected.Username; DetailPassword.Text = Mask(_selected.Password);
        DetailWebsite.Text = _selected.Website; DetailEmail.Text = _selected.Email;
        DetailModified.Text = _selected.UpdatedAt.ToLocalTime().ToString("g");
        DetailNotes.Text = string.IsNullOrWhiteSpace(_selected.Notes) ? "Sem notas." : _selected.Notes;
        RestoreButton.IsVisible = _selected.DeletedAt is not null;
        DeleteButton.Content = _selected.DeletedAt is null ? "Mover para a lixeira" : "Excluir definitivamente";
        var warning = PasswordSecurityAudit.Warning(_selected, _vault.Payload?.Items ?? []);
        SecurityTitle.Text = warning is null ? "Nenhum problema encontrado" : "Recomendação de segurança";
        SecurityMessage.Text = warning ?? "Esta senha é exclusiva e não apresenta problemas na verificação local.";
        SecurityBorder.BorderBrush = warning is null ? Avalonia.Media.Brushes.MediumTurquoise : Avalonia.Media.Brushes.Orange;
        SecurityBorder.BorderThickness = new Avalonia.Thickness(1);
    }

    private async void Add_Click(object? sender, RoutedEventArgs e)
    {
        if (_vault.Payload is null) return;
        var item = await Dialogs.EditItemAsync(this, new VaultItem { Password = PasswordGenerator.Generate() }, _vault.Payload.AllCategories);
        if (item is null) return;
        try { _vault.Upsert(item); RefreshItems(); ItemsList.SelectedItem = item; }
        catch (Exception error) { await Dialogs.ShowMessageAsync(this, "Não foi possível salvar", error.Message); }
    }

    private async void Edit_Click(object? sender, RoutedEventArgs e)
    {
        if (_selected is null || _vault.Payload is null) return;
        var item = await Dialogs.EditItemAsync(this, _selected, _vault.Payload.AllCategories);
        if (item is null) return;
        try { _vault.Upsert(item); RefreshItems(); ItemsList.SelectedItem = item; }
        catch (Exception error) { await Dialogs.ShowMessageAsync(this, "Não foi possível salvar", error.Message); }
    }

    private void ToggleFavorite_Click(object? sender, RoutedEventArgs e)
    {
        if (_selected is null) return;
        _selected.IsFavorite = !_selected.IsFavorite; _vault.Upsert(_selected); RefreshItems();
    }

    private void ShowPassword_Click(object? sender, RoutedEventArgs e)
    {
        if (_selected is null) return;
        _passwordVisible = !_passwordVisible;
        DetailPassword.Text = _passwordVisible ? _selected.Password : Mask(_selected.Password);
    }

    private async void CopyUsername_Click(object? sender, RoutedEventArgs e) => await CopyAsync(_selected?.Username, "Usuário copiado");
    private async void CopyPassword_Click(object? sender, RoutedEventArgs e) => await CopyAsync(_selected?.Password, "Senha copiada");
    private async void CopyWebsite_Click(object? sender, RoutedEventArgs e) => await CopyAsync(_selected?.Website, "Site copiado");
    private async void CopyEmail_Click(object? sender, RoutedEventArgs e) => await CopyAsync(_selected?.Email, "E-mail copiado");

    private async void UsernameRow_PointerPressed(object? sender, PointerPressedEventArgs e)
    {
        if (sender is not Control target || !e.GetCurrentPoint(target).Properties.IsLeftButtonPressed) return;
        e.Handled = true;
        await CopyAsync(_selected?.Username, "Usuário copiado");
    }

    private async void PasswordRow_PointerPressed(object? sender, PointerPressedEventArgs e)
    {
        if (sender is not Control target || !e.GetCurrentPoint(target).Properties.IsLeftButtonPressed) return;
        e.Handled = true;
        await CopyAsync(_selected?.Password, "Senha copiada");
    }

    private void WebsiteRow_PointerPressed(object? sender, PointerPressedEventArgs e)
    {
        if (_selected is null || string.IsNullOrWhiteSpace(_selected.Website) || sender is not Control target) return;
        if (!e.GetCurrentPoint(target).Properties.IsLeftButtonPressed) return;
        target.ContextMenu?.Open(target);
        e.Handled = true;
    }

    private static void CopyableRow_PointerEntered(object? sender, PointerEventArgs e) => SetCopyHint(sender, true);
    private static void CopyableRow_PointerExited(object? sender, PointerEventArgs e) => SetCopyHint(sender, false);

    private static void SetCopyHint(object? sender, bool visible)
    {
        if (sender is not Grid grid) return;
        var hint = grid.Children.OfType<TextBlock>().FirstOrDefault(text => text.Classes.Contains("copyHint"));
        if (hint is not null) hint.IsVisible = visible;
    }

    private async Task CopyAsync(string? value, string confirmation)
    {
        if (string.IsNullOrEmpty(value) || Clipboard is null) return;
        _clipboardClearCancellation?.Cancel();
        _clipboardClearCancellation = new CancellationTokenSource();
        var cancellation = _clipboardClearCancellation.Token;
        await Clipboard.SetTextAsync(value); ResetAutoLock();
        ShowCopyConfirmation(confirmation);
        try
        {
            await Task.Delay(TimeSpan.FromSeconds(30), cancellation);
            if (await Clipboard.TryGetTextAsync() == value) await Clipboard.ClearAsync();
        }
        catch (OperationCanceledException) { }
    }

    private async void ShowCopyConfirmation(string message)
    {
        var version = ++_copyConfirmationVersion;
        CopyConfirmationText.Text = message;
        CopyConfirmation.IsVisible = true;
        await Task.Delay(TimeSpan.FromSeconds(1.6));
        if (version == _copyConfirmationVersion) CopyConfirmation.IsVisible = false;
    }

    private async void OpenWebsite_Click(object? sender, RoutedEventArgs e)
    {
        if (_selected is null || string.IsNullOrWhiteSpace(_selected.Website)) return;
        var value = _selected.Website.Trim();
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri)) Uri.TryCreate($"https://{value}", UriKind.Absolute, out uri);
        if (uri is null || (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps))
        { await Dialogs.ShowMessageAsync(this, "Site inválido", "Use um endereço HTTP ou HTTPS válido."); return; }
        Process.Start(new ProcessStartInfo(uri.AbsoluteUri) { UseShellExecute = true });
    }

    private void Restore_Click(object? sender, RoutedEventArgs e)
    {
        if (_selected is null) return;
        _vault.Restore([_selected.Id]); RefreshItems();
    }

    private async void Delete_Click(object? sender, RoutedEventArgs e)
    {
        if (_selected is null) return;
        if (_selected.DeletedAt is null) _vault.SoftDelete([_selected.Id]);
        else
        {
            var confirmation = await Dialogs.PromptAsync(this, "Excluir definitivamente", "Digite EXCLUIR para confirmar");
            if (confirmation != "EXCLUIR") return;
            _vault.PermanentlyDelete([_selected.Id]);
        }
        _selected = null; RefreshItems();
        EmptyDetail.IsVisible = true; DetailScroll.IsVisible = false;
    }

    private async void AddCategory_Click(object? sender, RoutedEventArgs e)
    {
        var name = await Dialogs.PromptAsync(this, "Nova categoria", "Nome da categoria");
        if (string.IsNullOrWhiteSpace(name)) return;
        try { _vault.AddCategory(name); PopulateNavigation(); }
        catch (Exception error) { await Dialogs.ShowMessageAsync(this, "Categoria inválida", error.Message); }
    }

    private async void ImportCsv_Click(object? sender, RoutedEventArgs e)
    {
        var files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = "Importar senhas de CSV", AllowMultiple = false,
            FileTypeFilter = [new FilePickerFileType("Arquivo CSV") { Patterns = ["*.csv"] }]
        });
        var file = files.FirstOrDefault(); if (file is null) return;
        try
        {
            _vault.ImportItems(CsvTransfer.Import(await File.ReadAllTextAsync(file.Path.LocalPath)));
            PopulateNavigation(); RefreshItems();
        }
        catch (Exception error) { await Dialogs.ShowMessageAsync(this, "Falha na importação", error.Message); }
    }

    private async void ExportCsv_Click(object? sender, RoutedEventArgs e)
    {
        if (_vault.Payload is null) return;
        var file = await StorageProvider.SaveFilePickerAsync(new FilePickerSaveOptions
        {
            Title = "Exportar senhas para CSV", SuggestedFileName = "lion-pass.csv",
            FileTypeChoices = [new FilePickerFileType("Arquivo CSV") { Patterns = ["*.csv"] }]
        });
        if (file is null) return;
        await File.WriteAllTextAsync(file.Path.LocalPath, CsvTransfer.Export(_vault.Payload.Items.Where(x => x.DeletedAt is null)));
        await Dialogs.ShowMessageAsync(this, "Exportação concluída", "O CSV contém senhas em texto simples. Guarde-o com segurança e apague-o após o uso.");
    }

    private async void ExportVault_Click(object? sender, RoutedEventArgs e)
    {
        var file = await StorageProvider.SaveFilePickerAsync(new FilePickerSaveOptions
        {
            Title = "Exportar cofre criptografado", SuggestedFileName = "lion-pass-backup.lionvault",
            FileTypeChoices = [new FilePickerFileType("Cofre Lion Pass") { Patterns = ["*.lionvault"] }]
        });
        if (file is null) return;
        _vault.Export(file.Path.LocalPath);
    }

    private async void Settings_Click(object? sender, RoutedEventArgs e)
    {
        if (!_vault.IsUnlocked || _vault.Payload is null) return;
        var result = await Dialogs.SettingsAsync(this, _settings with { PasswordHistoryEnabled = _vault.Payload.PasswordHistoryEnabled }, _keyring.IsAvailable);
        if (result is null) return;
        try
        {
            _settings = result; _vault.Payload.PasswordHistoryEnabled = result.PasswordHistoryEnabled; _vault.Save();
            if (result.StoreInKeyring) await SaveCurrentKeyAsync(); else await _keyring.DeleteAsync();
            SaveSettings(_settings); ResetAutoLock(); await RefreshKeyringAsync();
        }
        catch (Exception error) { await Dialogs.ShowMessageAsync(this, "Configuração não aplicada", error.Message); }
    }

    private async void About_Click(object? sender, RoutedEventArgs e) => await Dialogs.ShowMessageAsync(this, "Lion Pass para Linux",
        "Gerenciador de senhas local e offline.\n\nCriado por Lion Code Technology\nhttps://lioncodetech.com.br/\n\n© 2026 Lion Code Technology");

    private void Quit_Click(object? sender, RoutedEventArgs e) => Close();

    private static string Mask(string value) => value.Length == 0 ? "—" : new string('●', Math.Min(value.Length, 20));
    private static string TypeTitle(VaultItemKind value) => value switch
    { VaultItemKind.Login => "Logins", VaultItemKind.Card => "Cartões", VaultItemKind.SecureNote => "Notas seguras", VaultItemKind.Identity => "Identidades", _ => "Outros" };

    private static string SettingsPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Lion Code Technology", "Lion Pass", "linux-settings.json");

    private static LinuxSettings LoadSettings()
    {
        try { return JsonSerializer.Deserialize<LinuxSettings>(File.ReadAllText(SettingsPath)) ?? new LinuxSettings(5, true, false); }
        catch { return new LinuxSettings(5, true, false); }
    }

    private static void SaveSettings(LinuxSettings value)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(SettingsPath)!);
        File.WriteAllText(SettingsPath, JsonSerializer.Serialize(value));
    }
}
