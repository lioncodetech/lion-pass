using System.Collections.ObjectModel;
using LionPass.Core;
using LionPass.Security;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage.Pickers;
using Windows.System;
using WinRT.Interop;

namespace LionPass.App;

public sealed partial class MainWindow : Window
{
    private readonly VaultService _vault = new(new VaultCryptoService(), new VaultStorageService());
    private readonly WindowsHelloKeyStore _hello = new();
    private readonly ObservableCollection<VaultItem> _visibleItems = [];
    private readonly Microsoft.UI.Dispatching.DispatcherQueueTimer _autoLockTimer;
    private string _filter = "all";
    private VaultItem? _selected;
    private bool _passwordVisible;
    private int _copyConfirmationVersion;

    public MainWindow()
    {
        InitializeComponent();
        ItemsList.ItemsSource = _visibleItems;
        PopulateNavigation();
        _autoLockTimer = DispatcherQueue.CreateTimer();
        _autoLockTimer.Interval = TimeSpan.FromMinutes(5);
        _autoLockTimer.Tick += (_, _) => LockVault();
        Activated += Window_Activated;
        Closed += (_, _) => _vault.Dispose();
        _ = RefreshHelloAsync();
    }

    private async void Window_Activated(object sender, WindowActivatedEventArgs args)
    {
        if (_vault.IsUnlocked && args.WindowActivationState != WindowActivationState.Deactivated)
        { _autoLockTimer.Stop(); _autoLockTimer.Start(); }
        await RefreshHelloAsync();
    }

    private async Task RefreshHelloAsync()
    {
        var user = Environment.UserName;
        try
        {
            var available = _hello.Exists && await _hello.IsAvailableAsync();
            HelloButton.Visibility = available ? Visibility.Visible : Visibility.Collapsed;
            HelloBadge.Visibility = available ? Visibility.Visible : Visibility.Collapsed;
            UnlockInstruction.Text = available
                ? $"Use o Windows Hello ou digite a senha mestra do Lion Pass para “{user}”."
                : $"Digite a senha mestra do Lion Pass para “{user}”.";
        }
        catch
        {
            HelloButton.Visibility = Visibility.Collapsed;
            HelloBadge.Visibility = Visibility.Collapsed;
            UnlockInstruction.Text = $"Digite a senha mestra do Lion Pass para “{user}”.";
        }
    }

    private async void Unlock_Click(object sender, RoutedEventArgs e)
    {
        await RunUnlockAsync(() => _vault.Open(MasterPassword.Password));
    }

    private async void MasterPassword_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key == Windows.System.VirtualKey.Enter) await RunUnlockAsync(() => _vault.Open(MasterPassword.Password));
    }

    private async void Hello_Click(object sender, RoutedEventArgs e)
    {
        await RunUnlockAsync(async () =>
        {
            var key = await _hello.LoadAsync();
            try { _vault.OpenWithContentKey(key); }
            finally { System.Security.Cryptography.CryptographicOperations.ZeroMemory(key); }
        });
    }

    private async Task RunUnlockAsync(Action action)
    {
        try { action(); ShowVault(); }
        catch (Exception error) { ShowUnlockError(error.Message); }
        await Task.CompletedTask;
    }

    private async Task RunUnlockAsync(Func<Task> action)
    {
        try { await action(); ShowVault(); }
        catch (Exception error) { ShowUnlockError(error.Message); }
    }

    private async void Create_Click(object sender, RoutedEventArgs e)
    {
        var name = new TextBox { Header = "Nome do cofre", Text = "My Pass" };
        var password = new PasswordBox { Header = "Senha mestra", PlaceholderText = "Mínimo de 12 caracteres" };
        var confirmation = new PasswordBox { Header = "Confirmar senha" };
        var panel = new StackPanel { Spacing = 12 };
        panel.Children.Add(name); panel.Children.Add(password); panel.Children.Add(confirmation);
        var dialog = Dialog("Criar cofre", panel, "Criar");
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        if (password.Password != confirmation.Password)
        { ShowUnlockError("As senhas não coincidem."); return; }
        try
        {
            var recovery = _vault.Create(name.Text, password.Password);
            await MessageAsync("Chave de recuperação", $"Guarde esta chave em um local seguro. Ela não será enviada a nenhum servidor.\n\n{recovery}");
            ShowVault();
        }
        catch (Exception error) { ShowUnlockError(error.Message); }
    }

    private async void Import_Click(object sender, RoutedEventArgs e)
    {
        var picker = new FileOpenPicker();
        picker.FileTypeFilter.Add(".lionvault");
        InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));
        var file = await picker.PickSingleFileAsync();
        if (file is null) return;
        var password = new PasswordBox { Header = "Senha mestra" };
        var dialog = Dialog("Importar cofre", password, "Importar");
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        try { _vault.Import(file.Path, password.Password); ShowVault(); }
        catch (Exception error) { ShowUnlockError(error.Message); }
    }

    private void ShowVault()
    {
        UnlockView.Visibility = Visibility.Collapsed;
        VaultView.Visibility = Visibility.Visible;
        MasterPassword.Password = "";
        VaultTitle.Text = _vault.Payload?.Name ?? "Lion Pass";
        _autoLockTimer.Stop(); _autoLockTimer.Start();
        PopulateNavigation(); RefreshItems();
    }

    private void Lock_Click(object sender, RoutedEventArgs e) => LockVault();

    private void LockVault()
    {
        _autoLockTimer.Stop(); _vault.Lock(); _visibleItems.Clear(); _selected = null;
        VaultView.Visibility = Visibility.Collapsed; UnlockView.Visibility = Visibility.Visible;
        _ = RefreshHelloAsync();
    }

    private void PopulateNavigation()
    {
        TypesPanel.Children.Clear();
        foreach (var value in Enum.GetValues<VaultItemKind>())
        {
            var item = new NavigationViewItem { Content = TypeTitle(value), Tag = $"type:{value}" };
            item.Icon = new SymbolIcon(value switch
            {
                VaultItemKind.Login => Symbol.Permissions,
                VaultItemKind.Card => Symbol.ContactInfo,
                VaultItemKind.SecureNote => Symbol.Document,
                VaultItemKind.Identity => Symbol.Contact,
                _ => Symbol.AllApps
            });
            item.Tapped += Filter_Tapped; TypesPanel.Children.Add(item);
        }
        CategoriesPanel.Children.Clear();
        foreach (var category in _vault.Payload?.AllCategories ?? VaultPayload.DefaultCategories)
        {
            var item = new NavigationViewItem { Content = category, Tag = $"category:{category}", Icon = new SymbolIcon(CategorySymbol(category)) };
            item.Tapped += Filter_Tapped; CategoriesPanel.Children.Add(item);
        }
    }

    private void Filter_Tapped(object sender, TappedRoutedEventArgs e)
    {
        if (sender is not NavigationViewItem item || item.Tag is not string tag) return;
        _filter = tag; CollectionTitle.Text = item.Content?.ToString() ?? "Itens"; RefreshItems();
    }

    private void SearchBox_TextChanged(object sender, TextChangedEventArgs e) => RefreshItems();
    private void SortBox_SelectionChanged(object sender, SelectionChangedEventArgs e) => RefreshItems();

    private void RefreshItems()
    {
        if (_vault.Payload is null) return;
        IEnumerable<VaultItem> values = _vault.Payload.Items;
        values = _filter switch
        {
            "favorites" => values.Where(x => x.DeletedAt is null && x.IsFavorite),
            "security" => values.Where(x => x.DeletedAt is null && PasswordSecurityAudit.Warning(x, _vault.Payload.Items) is not null),
            "trash" => values.Where(x => x.DeletedAt is not null),
            _ when _filter.StartsWith("type:") => values.Where(x => x.DeletedAt is null && x.Kind.ToString() == _filter[5..]),
            _ when _filter.StartsWith("category:") => values.Where(x => x.DeletedAt is null && x.Category == _filter[9..]),
            _ => values.Where(x => x.DeletedAt is null)
        };
        values = values.Where(item => item.Matches(SearchBox.Text));
        var sort = (SortBox.SelectedItem as ComboBoxItem)?.Tag?.ToString();
        values = sort switch
        {
            "recent" => values.OrderByDescending(x => x.UpdatedAt),
            "category" => values.OrderBy(x => x.Category).ThenBy(x => x.Title),
            _ => values.OrderBy(x => x.Title, StringComparer.CurrentCultureIgnoreCase)
        };
        _visibleItems.Clear(); foreach (var item in values) _visibleItems.Add(item);
        ItemCount.Text = $"{_visibleItems.Count} itens";
    }

    private void ItemsList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        _selected = ItemsList.SelectedItem as VaultItem;
        EmptyDetail.Visibility = _selected is null ? Visibility.Visible : Visibility.Collapsed;
        DetailPanel.Visibility = _selected is null ? Visibility.Collapsed : Visibility.Visible;
        if (_selected is null) return;
        _passwordVisible = false;
        DetailInitial.Text = _selected.DisplayInitial;
        DetailTitle.Text = _selected.Title; DetailKind.Text = TypeTitle(_selected.Kind);
        DetailUsername.Text = _selected.Username; DetailPassword.Password = _selected.Password;
        DetailWebsite.Text = _selected.Website; DetailEmail.Text = _selected.Email;
        DetailModified.Text = _selected.UpdatedAt.ToLocalTime().ToString("g");
        DetailNotes.Text = _selected.Notes;
        RestoreButton.Visibility = _selected.DeletedAt is null ? Visibility.Collapsed : Visibility.Visible;
        DeleteButton.Content = _selected.DeletedAt is null ? "Mover para Lixeira" : "Excluir definitivamente";
        var warning = PasswordSecurityAudit.Warning(_selected, _vault.Payload?.Items ?? []);
        SecurityCard.Severity = warning is null ? InfoBarSeverity.Success : InfoBarSeverity.Warning;
        SecurityCard.Title = warning is null ? "Nenhum problema encontrado" : "Recomendação de segurança";
        SecurityCard.Message = warning ?? "Esta senha é exclusiva e não apresenta problemas na verificação local.";
    }

    private async void Add_Click(object sender, RoutedEventArgs e)
    {
        var item = await ShowEditorAsync(new VaultItem { Password = PasswordGenerator.Generate() }, "Novo item");
        if (item is null) return;
        try { _vault.Upsert(item); RefreshItems(); ItemsList.SelectedItem = item; }
        catch (Exception error) { await MessageAsync("Não foi possível salvar", error.Message); }
    }

    private async void Edit_Click(object sender, RoutedEventArgs e)
    {
        if (_selected is null) return;
        var item = await ShowEditorAsync(_selected with
        {
            Tags = _selected.Tags.ToList(), CustomFields = _selected.CustomFields.ToList(),
            PasswordHistory = _selected.PasswordHistory.ToList()
        }, "Editar item");
        if (item is null) return;
        _vault.Upsert(item); RefreshItems(); ItemsList.SelectedItem = item;
    }

    private async Task<VaultItem?> ShowEditorAsync(VaultItem item, string title)
    {
        var type = new ComboBox { Header = "Tipo", ItemsSource = Enum.GetValues<VaultItemKind>(), SelectedItem = item.Kind };
        var name = new TextBox { Header = "Título", Text = item.Title };
        var username = new TextBox { Header = "Usuário", Text = item.Username };
        var password = new PasswordBox { Header = "Senha", Password = item.Password };
        var generate = new Button { Content = "Gerar senha segura", HorizontalAlignment = HorizontalAlignment.Right };
        generate.Click += (_, _) => password.Password = PasswordGenerator.Generate();
        var website = new TextBox { Header = "Site", Text = item.Website };
        var email = new TextBox { Header = "E-mail", Text = item.Email };
        var tags = new TextBox { Header = "Tags", Text = string.Join(", ", item.Tags), PlaceholderText = "trabalho, urgente" };
        var category = new ComboBox { Header = "Categoria", ItemsSource = _vault.Payload?.AllCategories, SelectedItem = item.Category };
        var favorite = new CheckBox { Content = "Favorito", IsChecked = item.IsFavorite };
        var cardholder = new TextBox { Header = "Titular do cartão", Text = item.Cardholder };
        var cardNumber = new TextBox { Header = "Número do cartão", Text = item.CardNumber };
        var expiry = new TextBox { Header = "Validade", Text = item.Expiry };
        var securityCode = new PasswordBox { Header = "Código de segurança", Password = item.SecurityCode };
        var bank = new TextBox { Header = "Banco", Text = item.Bank };
        var notes = new TextBox { Header = "Notas", Text = item.Notes, AcceptsReturn = true, MinHeight = 90, TextWrapping = TextWrapping.Wrap };
        var panel = new StackPanel { Spacing = 10, Width = 520 };
        foreach (var control in new UIElement[] { type, name, username, password, generate, website, email, tags, category, favorite, cardholder, cardNumber, expiry, securityCode, bank, notes }) panel.Children.Add(control);
        var dialog = Dialog(title, new ScrollViewer { Content = panel, MaxHeight = 620 }, "Salvar");
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return null;
        item.Kind = (VaultItemKind?)type.SelectedItem ?? VaultItemKind.Login;
        item.Title = name.Text.Trim(); item.Username = username.Text; item.Password = password.Password;
        item.Website = website.Text.Trim(); item.Email = email.Text.Trim(); item.Notes = notes.Text;
        item.Tags = tags.Text.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).Distinct(StringComparer.CurrentCultureIgnoreCase).ToList();
        item.Category = category.SelectedItem?.ToString() ?? "Outros"; item.IsFavorite = favorite.IsChecked == true;
        item.Cardholder = cardholder.Text; item.CardNumber = cardNumber.Text; item.Expiry = expiry.Text;
        item.SecurityCode = securityCode.Password; item.Bank = bank.Text;
        return item;
    }

    private void Restore_Click(object sender, RoutedEventArgs e)
    {
        if (_selected is null) return;
        _vault.Restore([_selected.Id]);
        _selected = null; ItemsList.SelectedItem = null; RefreshItems();
        EmptyDetail.Visibility = Visibility.Visible; DetailPanel.Visibility = Visibility.Collapsed;
    }

    private async void Delete_Click(object sender, RoutedEventArgs e)
    {
        if (_selected is null) return;
        if (_selected.DeletedAt is null) _vault.SoftDelete([_selected.Id]);
        else _vault.PermanentlyDelete([_selected.Id]);
        _selected = null; ItemsList.SelectedItem = null; RefreshItems();
        EmptyDetail.Visibility = Visibility.Visible;
        DetailPanel.Visibility = Visibility.Collapsed;
        await Task.CompletedTask;
    }

    private void CopyUsername_Click(object sender, RoutedEventArgs e) => CopySecret(_selected?.Username, "Usuário copiado");
    private void CopyPassword_Click(object sender, RoutedEventArgs e) => CopySecret(_selected?.Password, "Senha copiada");
    private void CopyWebsite_Click(object sender, RoutedEventArgs e) => CopySecret(_selected?.Website, "Site copiado");
    private void CopyEmail_Click(object sender, RoutedEventArgs e) => CopySecret(_selected?.Email, "E-mail copiado");

    private void UsernameRow_Tapped(object sender, TappedRoutedEventArgs e)
    {
        CopySecret(_selected?.Username, "Usuário copiado");
        e.Handled = true;
    }

    private void PasswordRow_Tapped(object sender, TappedRoutedEventArgs e)
    {
        CopySecret(_selected?.Password, "Senha copiada");
        e.Handled = true;
    }

    private void WebsiteRow_Tapped(object sender, TappedRoutedEventArgs e)
    {
        if (_selected is null || string.IsNullOrWhiteSpace(_selected.Website)) return;
        if (sender is FrameworkElement target) WebsiteFlyout.ShowAt(target);
        e.Handled = true;
    }

    private static void CopyableRow_PointerEntered(object sender, PointerRoutedEventArgs e) => SetCopyHint(sender, true);
    private static void CopyableRow_PointerExited(object sender, PointerRoutedEventArgs e) => SetCopyHint(sender, false);

    private static void SetCopyHint(object sender, bool visible)
    {
        if (sender is not Grid grid) return;
        var hint = grid.Children.OfType<FontIcon>().FirstOrDefault(icon => icon.Tag as string == "CopyHint");
        if (hint is not null) hint.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;
    }

    private async void CopySecret(string? value, string confirmation)
    {
        if (string.IsNullOrEmpty(value)) return;
        var package = new DataPackage(); package.SetText(value); Clipboard.SetContent(package);
        ShowCopyConfirmation(confirmation);
        await Task.Delay(TimeSpan.FromSeconds(30));
        try
        {
            var current = await Clipboard.GetContent().GetTextAsync();
            if (current == value) Clipboard.Clear();
        }
        catch { }
    }

    private async void ShowCopyConfirmation(string message)
    {
        var version = ++_copyConfirmationVersion;
        CopyConfirmation.Title = message;
        CopyConfirmation.IsOpen = true;
        await Task.Delay(TimeSpan.FromSeconds(1.6));
        if (version == _copyConfirmationVersion) CopyConfirmation.IsOpen = false;
    }

    private void ShowPassword_Click(object sender, RoutedEventArgs e)
    {
        _passwordVisible = !_passwordVisible;
        DetailPassword.PasswordRevealMode = _passwordVisible ? PasswordRevealMode.Visible : PasswordRevealMode.Hidden;
        if (sender is Button button) button.Content = _passwordVisible ? "Ocultar" : "Mostrar";
    }

    private async void OpenWebsite_Click(object sender, RoutedEventArgs e)
    {
        if (_selected is null || string.IsNullOrWhiteSpace(_selected.Website)) return;
        var value = _selected.Website.Trim();
        if (!value.Contains("://", StringComparison.Ordinal)) value = "https://" + value;
        if (Uri.TryCreate(value, UriKind.Absolute, out var uri)) await Launcher.LaunchUriAsync(uri);
    }

    private async void Export_Click(object sender, RoutedEventArgs e)
    {
        var picker = new FileSavePicker { SuggestedFileName = "Lion Pass Backup" };
        picker.FileTypeChoices.Add("Cofre Lion", [".lionvault"]);
        InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));
        var file = await picker.PickSaveFileAsync(); if (file is not null) _vault.Export(file.Path);
    }

    private async void ImportCsv_Click(object sender, RoutedEventArgs e)
    {
        var picker = new FileOpenPicker(); picker.FileTypeFilter.Add(".csv");
        InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));
        var file = await picker.PickSingleFileAsync(); if (file is null) return;
        try { _vault.ImportItems(CsvTransfer.Import(await File.ReadAllTextAsync(file.Path))); RefreshItems(); }
        catch (Exception error) { await MessageAsync("Importação", error.Message); }
    }

    private async void ExportCsv_Click(object sender, RoutedEventArgs e)
    {
        var picker = new FileSavePicker { SuggestedFileName = "Lion Pass Passwords" };
        picker.FileTypeChoices.Add("CSV", [".csv"]);
        InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));
        var file = await picker.PickSaveFileAsync(); if (file is null) return;
        var items = _visibleItems.Where(item => item.DeletedAt is null);
        await File.WriteAllTextAsync(file.Path, CsvTransfer.Export(items));
    }

    private async void Category_Click(object sender, RoutedEventArgs e)
    {
        var name = new TextBox { Header = "Nome da nova categoria" };
        var dialog = Dialog("Nova categoria", name, "Adicionar");
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        try { _vault.AddCategory(name.Text); PopulateNavigation(); }
        catch (Exception error) { await MessageAsync("Categoria", error.Message); }
    }

    private async void Settings_Click(object sender, RoutedEventArgs e)
    {
        var hello = new CheckBox { Content = "Desbloquear com Windows Hello", IsChecked = _hello.Exists, IsEnabled = await _hello.IsAvailableAsync() };
        var history = new CheckBox { Content = "Guardar histórico das últimas senhas", IsChecked = _vault.Payload?.PasswordHistoryEnabled };
        var compromised = new CheckBox { Content = "Detectar senhas comprometidas localmente", IsChecked = true };
        var strong = new CheckBox { Content = "Sugerir senhas fortes", IsChecked = true };
        var contact = new CheckBox { Content = "Permitir abrir sites associados", IsChecked = true };
        var panel = new StackPanel { Spacing = 12, Width = 500 };
        foreach (var control in new UIElement[] { hello, history, compromised, strong, contact }) panel.Children.Add(control);
        var dialog = Dialog("Ajustes", panel, "Salvar");
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        try
        {
            if (hello.IsChecked == true && !_hello.Exists) await _hello.SaveAsync(_vault.GetContentKey());
            else if (hello.IsChecked != true) _hello.Delete();
            if (_vault.Payload is not null && _vault.Payload.PasswordHistoryEnabled != (history.IsChecked == true))
            { _vault.Payload.PasswordHistoryEnabled = history.IsChecked == true; _vault.Save(); }
            await RefreshHelloAsync();
        }
        catch (Exception error) { await MessageAsync("Windows Hello", error.Message); }
    }

    private ContentDialog Dialog(string title, object content, string primary) => new()
    {
        Title = title, Content = content, PrimaryButtonText = primary,
        CloseButtonText = "Cancelar", DefaultButton = ContentDialogButton.Primary,
        XamlRoot = Content.XamlRoot
    };

    private async Task MessageAsync(string title, string message)
    {
        var dialog = new ContentDialog { Title = title, Content = new TextBlock { Text = message, TextWrapping = TextWrapping.Wrap },
            CloseButtonText = "OK", XamlRoot = Content.XamlRoot };
        await dialog.ShowAsync();
    }

    private void ShowUnlockError(string message)
    { UnlockMessage.Message = message; UnlockMessage.IsOpen = true; }

    private static string TypeTitle(VaultItemKind kind) => kind switch
    { VaultItemKind.Login => "Logins", VaultItemKind.Card => "Cartões", VaultItemKind.SecureNote => "Notas seguras", VaultItemKind.Identity => "Identidades", _ => "Outros" };

    private static Symbol CategorySymbol(string category) => category.ToLowerInvariant() switch
    {
        "e-mail" => Symbol.Mail, "bancos" => Symbol.Library, "redes sociais" => Symbol.People,
        "trabalho" => Symbol.Admin, "compras" => Symbol.Shop, "streaming" => Symbol.Video,
        "wi-fi" => Symbol.Globe, "cartões" => Symbol.ContactInfo, "notas" => Symbol.Document,
        "identidades" => Symbol.Contact, _ => Symbol.Folder
    };
}
