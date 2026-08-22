using System.Collections.ObjectModel;
using LionPass.Core;
using LionPass.Security;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Windowing;
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
        ApplyWindowIcon();
        if (Content is FrameworkElement root) root.Loaded += MainWindow_Loaded;
        ItemsList.ItemsSource = _visibleItems;
        PopulateNavigation();
        _autoLockTimer = DispatcherQueue.CreateTimer();
        _autoLockTimer.Interval = TimeSpan.FromMinutes(5);
        _autoLockTimer.Tick += (_, _) => LockVault();
        Activated += Window_Activated;
        Closed += (_, _) => _vault.Dispose();
        _ = RefreshHelloAsync();
    }

private void ApplyWindowIcon()
{
    try
    {
        var windowHandle = WindowNative.GetWindowHandle(this);
        var windowId = Microsoft.UI.Win32Interop.GetWindowIdFromWindow(windowHandle);
        var iconPath = Path.Combine(AppContext.BaseDirectory, "Assets", "LionPass.ico");
        AppWindow.GetFromWindowId(windowId)?.SetIcon(iconPath);
    }
    catch (Exception error)
    {
        StartupDiagnostics.Report(L("Não foi possível aplicar o ícone à janela principal."), error);
    }
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
                ? LF("Use o Windows Hello ou digite a senha mestra do Lion Pass para “{0}”.", user)
                : LF("Digite a senha mestra do Lion Pass para “{0}”.", user);
        }
        catch
        {
            HelloButton.Visibility = Visibility.Collapsed;
            HelloBadge.Visibility = Visibility.Collapsed;
            UnlockInstruction.Text = LF("Digite a senha mestra do Lion Pass para “{0}”.", user);
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
        catch (Exception error) { ShowUnlockError(L(error.Message)); }
        await Task.CompletedTask;
    }

    private async Task RunUnlockAsync(Func<Task> action)
    {
        try { await action(); ShowVault(); }
        catch (Exception error) { ShowUnlockError(L(error.Message)); }
    }

    private async void Create_Click(object sender, RoutedEventArgs e)
    {
        var name = new TextBox { Header = L("Nome do cofre"), Text = L("My Pass") };
        var password = new PasswordBox { Header = L("Senha mestra"), PlaceholderText = L("Mínimo de 12 caracteres") };
        var confirmation = new PasswordBox { Header = L("Confirmar senha") };
        var panel = new StackPanel { Spacing = 12 };
        panel.Children.Add(name); panel.Children.Add(password); panel.Children.Add(confirmation);
        var dialog = Dialog(L("Criar cofre"), panel, L("Criar"));
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        if (password.Password != confirmation.Password)
        { ShowUnlockError(L("As senhas não coincidem.")); return; }
        try
        {
            var recovery = _vault.Create(name.Text, password.Password);
            await ShowRecoveryKeyAsync(recovery, true);
            ShowVault();
        }
        catch (Exception error) { ShowUnlockError(L(error.Message)); }
    }

    private async void Import_Click(object sender, RoutedEventArgs e)
    {
        var picker = new FileOpenPicker();
        picker.FileTypeFilter.Add(".lionvault");
        InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));
        var file = await picker.PickSingleFileAsync();
        if (file is null) return;
        var password = new PasswordBox { Header = L("Senha mestra") };
        var dialog = Dialog(L("Importar cofre"), password, L("Importar"));
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        try { _vault.Import(file.Path, password.Password); ShowVault(); }
        catch (Exception error) { ShowUnlockError(L(error.Message)); }
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
            var item = new NavigationViewItem { Content = L(category), Tag = $"category:{category}", Icon = new SymbolIcon(CategorySymbol(category)) };
            item.Tapped += Filter_Tapped; CategoriesPanel.Children.Add(item);
        }
    }

    private void Filter_Tapped(object sender, TappedRoutedEventArgs e)
    {
        if (sender is not NavigationViewItem item || item.Tag is not string tag) return;
        _filter = tag; CollectionTitle.Text = item.Content?.ToString() ?? L("Itens"); RefreshItems();
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
        ItemCount.Text = LF("{0} itens", _visibleItems.Count);
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
        DeleteButton.Content = _selected.DeletedAt is null ? L("Mover para Lixeira") : L("Excluir definitivamente");
        var warning = PasswordSecurityAudit.Warning(_selected, _vault.Payload?.Items ?? []);
        SecurityCard.Severity = warning is null ? InfoBarSeverity.Success : InfoBarSeverity.Warning;
        SecurityCard.Title = warning is null ? L("Nenhum problema encontrado") : L("Recomendação de segurança");
        SecurityCard.Message = warning is null ? L("Esta senha é exclusiva e não apresenta problemas na verificação local.") : L(warning);
    }

    private async void Add_Click(object sender, RoutedEventArgs e)
    {
        var item = await ShowEditorAsync(new VaultItem { Password = PasswordGenerator.Generate() }, L("Novo item"));
        if (item is null) return;
        try { _vault.Upsert(item); RefreshItems(); ItemsList.SelectedItem = item; }
        catch (Exception error) { await MessageAsync(L("Não foi possível salvar"), L(error.Message)); }
    }

    private async void Edit_Click(object sender, RoutedEventArgs e)
    {
        if (_selected is null) return;
        var item = await ShowEditorAsync(_selected with
        {
            Tags = _selected.Tags.ToList(), CustomFields = _selected.CustomFields.ToList(),
            PasswordHistory = _selected.PasswordHistory.ToList()
        }, L("Editar item"));
        if (item is null) return;
        _vault.Upsert(item); RefreshItems(); ItemsList.SelectedItem = item;
    }

    private async Task<VaultItem?> ShowEditorAsync(VaultItem item, string title)
    {
        var typeOptions = Enum.GetValues<VaultItemKind>().Select(value => new TypeOption(value)).ToList();
        var type = new ComboBox { Header = L("Tipo"), ItemsSource = typeOptions, SelectedItem = typeOptions.First(option => option.Value == item.Kind) };
        var name = new TextBox { Header = L("Título"), Text = item.Title };
        var username = new TextBox { Header = L("Usuário"), Text = item.Username };
        var password = new PasswordBox { Header = L("Senha"), Password = item.Password };
        var generate = new Button { Content = L("Gerar senha segura"), HorizontalAlignment = HorizontalAlignment.Right };
        generate.Click += (_, _) => password.Password = PasswordGenerator.Generate();
        var website = new TextBox { Header = L("Site"), Text = item.Website };
        var email = new TextBox { Header = L("E-mail"), Text = item.Email };
        var tags = new TextBox { Header = L("Tags"), Text = string.Join(", ", item.Tags), PlaceholderText = L("trabalho, urgente") };
        var categoryOptions = (_vault.Payload?.AllCategories ?? VaultPayload.DefaultCategories).Select(value => new CategoryOption(value)).ToList();
        var category = new ComboBox { Header = L("Categoria"), ItemsSource = categoryOptions, SelectedItem = categoryOptions.FirstOrDefault(option => option.Value == item.Category) };
        var favorite = new CheckBox { Content = L("Favorito"), IsChecked = item.IsFavorite };
        var cardholder = new TextBox { Header = L("Titular do cartão"), Text = item.Cardholder };
        var cardNumber = new TextBox { Header = L("Número do cartão"), Text = item.CardNumber };
        var expiry = new TextBox { Header = L("Validade"), Text = item.Expiry };
        var securityCode = new PasswordBox { Header = L("Código de segurança"), Password = item.SecurityCode };
        var bank = new TextBox { Header = L("Banco"), Text = item.Bank };
        var notes = new TextBox { Header = L("Notas"), Text = item.Notes, AcceptsReturn = true, MinHeight = 90, TextWrapping = TextWrapping.Wrap };
        var panel = new StackPanel { Spacing = 10, Width = 480, HorizontalAlignment = HorizontalAlignment.Stretch };
        foreach (var control in new UIElement[] { type, name, username, password, generate, website, email, tags, category, favorite, cardholder, cardNumber, expiry, securityCode, bank, notes }) panel.Children.Add(control);
        var editorScroll = new ScrollViewer
        {
            Content = panel,
            MaxHeight = 560,
            Padding = new Thickness(0, 0, 20, 0),
            HorizontalScrollMode = ScrollMode.Disabled,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            VerticalScrollMode = ScrollMode.Auto,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto
        };
        var dialog = Dialog(title, editorScroll, L("Salvar"));
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return null;
        item.Kind = (type.SelectedItem as TypeOption)?.Value ?? VaultItemKind.Login;
        item.Title = name.Text.Trim(); item.Username = username.Text; item.Password = password.Password;
        item.Website = website.Text.Trim(); item.Email = email.Text.Trim(); item.Notes = notes.Text;
        item.Tags = tags.Text.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).Distinct(StringComparer.CurrentCultureIgnoreCase).ToList();
        item.Category = (category.SelectedItem as CategoryOption)?.Value ?? "Outros"; item.IsFavorite = favorite.IsChecked == true;
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

    private void CopyUsername_Click(object sender, RoutedEventArgs e) => CopySecret(_selected?.Username, L("Usuário copiado"));
    private void CopyPassword_Click(object sender, RoutedEventArgs e) => CopySecret(_selected?.Password, L("Senha copiada"));
    private void CopyWebsite_Click(object sender, RoutedEventArgs e) => CopySecret(_selected?.Website, L("Site copiado"));
    private void CopyEmail_Click(object sender, RoutedEventArgs e) => CopySecret(_selected?.Email, L("E-mail copiado"));

    private void UsernameRow_Tapped(object sender, TappedRoutedEventArgs e)
    {
        CopySecret(_selected?.Username, L("Usuário copiado"));
        e.Handled = true;
    }

    private void PasswordRow_Tapped(object sender, TappedRoutedEventArgs e)
    {
        CopySecret(_selected?.Password, L("Senha copiada"));
        e.Handled = true;
    }

    private void WebsiteRow_Tapped(object sender, TappedRoutedEventArgs e)
    {
        if (_selected is null || string.IsNullOrWhiteSpace(_selected.Website)) return;
        if (sender is FrameworkElement target) WebsiteFlyout.ShowAt(target);
        e.Handled = true;
    }

    private void CopyableRow_PointerEntered(object sender, PointerRoutedEventArgs e) => SetCopyHint(sender, true);
    private void CopyableRow_PointerExited(object sender, PointerRoutedEventArgs e) => SetCopyHint(sender, false);

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
        if (sender is Button button) button.Content = _passwordVisible ? L("Ocultar") : L("Mostrar");
    }

    private async void OpenWebsite_Click(object sender, RoutedEventArgs e)
    {
        if (_selected is null || string.IsNullOrWhiteSpace(_selected.Website)) return;
        var value = _selected.Website.Trim();
        if (!value.Contains("://", StringComparison.Ordinal)) value = "https://" + value;
        if (Uri.TryCreate(value, UriKind.Absolute, out var uri) &&
            (uri.Scheme.Equals(Uri.UriSchemeHttp, StringComparison.OrdinalIgnoreCase) ||
             uri.Scheme.Equals(Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase)))
        {
            await Launcher.LaunchUriAsync(uri);
            return;
        }
        await MessageAsync(L("Site inválido"), L("Por segurança, o Lion Pass abre somente endereços HTTP ou HTTPS."));
    }

    private async void Export_Click(object sender, RoutedEventArgs e)
    {
        var picker = new FileSavePicker { SuggestedFileName = "Lion Pass Backup" };
        picker.FileTypeChoices.Add(L("Cofre Lion"), [".lionvault"]);
        InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));
        var file = await picker.PickSaveFileAsync(); if (file is not null) _vault.Export(file.Path);
    }

    private async void ImportCsv_Click(object sender, RoutedEventArgs e)
    {
        var picker = new FileOpenPicker(); picker.FileTypeFilter.Add(".csv");
        InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));
        var file = await picker.PickSingleFileAsync(); if (file is null) return;
        try
        {
            var properties = await file.GetBasicPropertiesAsync();
            if (properties.Size > (ulong)CsvTransfer.MaximumImportBytes)
                throw new InvalidDataException(L("O arquivo CSV excede o limite de 25 MB."));
            _vault.ImportItems(CsvTransfer.Import(await File.ReadAllTextAsync(file.Path)));
            RefreshItems();
        }
        catch (Exception error) { await MessageAsync(L("Importação"), L(error.Message)); }
    }

    private async void ExportCsv_Click(object sender, RoutedEventArgs e)
    {
        var warning = Dialog(L("Exportar senhas sem criptografia"),
            new TextBlock
            {
                Text = L("O arquivo CSV conterá logins e senhas em texto simples. Qualquer pessoa com acesso ao arquivo poderá lê-los. Deseja continuar?"),
                TextWrapping = TextWrapping.Wrap
            }, L("Continuar"));
        if (await warning.ShowAsync() != ContentDialogResult.Primary) return;
        var picker = new FileSavePicker { SuggestedFileName = "Lion Pass Passwords" };
        picker.FileTypeChoices.Add("CSV", [".csv"]);
        InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));
        var file = await picker.PickSaveFileAsync(); if (file is null) return;
        var items = _visibleItems.Where(item => item.DeletedAt is null);
        await File.WriteAllTextAsync(file.Path, CsvTransfer.Export(items));
    }

    private async void Category_Click(object sender, RoutedEventArgs e)
    {
        var name = new TextBox { Header = L("Nome da nova categoria") };
        var dialog = Dialog(L("Nova categoria"), name, L("Adicionar"));
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        try { _vault.AddCategory(name.Text); PopulateNavigation(); }
        catch (Exception error) { await MessageAsync(L("Categoria"), L(error.Message)); }
    }

    private async void Settings_Click(object sender, RoutedEventArgs e)
    {
        var helloAvailable = await _hello.IsAvailableAsync();
        var hello = new CheckBox
        {
            Content = L("Desbloquear com Windows Hello"),
            IsChecked = _hello.Exists,
            IsEnabled = true
        };
        var helloStatus = new TextBlock
        {
            Text = helloAvailable
                ? L("O Windows Hello está disponível neste dispositivo.")
                : L("Ao ativar, o Windows confirmará se o Hello está configurado para esta conta."),
            TextWrapping = TextWrapping.Wrap,
            Opacity = 0.7,
            Margin = new Thickness(24, -8, 0, 0)
        };
        var history = new CheckBox { Content = L("Guardar histórico das últimas senhas"), IsChecked = _vault.Payload?.PasswordHistoryEnabled };
        var compromised = new CheckBox { Content = L("Detectar senhas comprometidas localmente"), IsChecked = true };
        var strong = new CheckBox { Content = L("Sugerir senhas fortes"), IsChecked = true };
        var contact = new CheckBox { Content = L("Permitir abrir sites associados"), IsChecked = true };
        var languageTitle = new TextBlock { Text = L("Idioma"), FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, Margin = new Thickness(0, 8, 0, 0) };
        var languageSelector = CreateLanguageSelector();
        var securityTitle = new TextBlock { Text = L("Segurança"), FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, Margin = new Thickness(0, 8, 0, 0) };
        var recoveryLabel = new TextBlock { Text = L("Chave de recuperação"), FontWeight = Microsoft.UI.Text.FontWeights.SemiBold };
        var recoveryDescription = new TextBlock
        {
            Text = L("Consulte e copie a chave usada para recuperar este cofre."),
            TextWrapping = TextWrapping.Wrap,
            Opacity = 0.75
        };
        var recoveryButton = new Button { Content = L("Exibir chave de recuperação") };
var automaticUpdates = new CheckBox
{
    Content = L("Atualizações automáticas"),
    IsChecked = WindowsLocalization.GetBoolean("AutomaticUpdates", true)
};
var betaUpdates = new CheckBox
{
    Content = L("Receber versões beta"),
    IsChecked = WindowsLocalization.GetBoolean("ReceiveBetaUpdates", false)
};
var version = typeof(MainWindow).Assembly.GetName().Version?.ToString(3) ?? "1.0.0";
var currentVersion = new TextBlock { Text = LF("Versão atual: {0}", version), Opacity = 0.75 };
var checkUpdates = new Button { Content = L("Verificar atualização") };
var stableRelease = new Button { Content = L("Voltar para a última versão estável") };
checkUpdates.Click += async (_, _) =>
{
    var path = betaUpdates.IsChecked == true ? "releases" : "releases/latest";
    await Launcher.LaunchUriAsync(new Uri("https://github.com/lioncodetech/lion-pass/" + path));
};
stableRelease.Click += async (_, _) =>
    await Launcher.LaunchUriAsync(new Uri("https://github.com/lioncodetech/lion-pass/releases/latest"));
var updateButtons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
updateButtons.Children.Add(checkUpdates);
updateButtons.Children.Add(stableRelease);

        var panel = new StackPanel { Spacing = 12, Width = 500 };
        foreach (var control in new UIElement[] { hello, helloStatus, history, compromised, strong, contact, languageTitle, languageSelector }) panel.Children.Add(control);
        foreach (var control in new UIElement[] { securityTitle, recoveryLabel, recoveryDescription, recoveryButton }) panel.Children.Add(control);
        panel.Children.Add(new TextBlock { Text = L("Atualizações"), FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, Margin = new Thickness(0, 8, 0, 0) });
        foreach (var control in new UIElement[] { automaticUpdates, betaUpdates, currentVersion, updateButtons }) panel.Children.Add(control);
        var settingsScroll = new ScrollViewer { Content = panel, MaxHeight = 620, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        var dialog = Dialog(L("Ajustes"), settingsScroll, L("Salvar"));
        var showRecoveryRequested = false;
        recoveryButton.Click += (_, _) => { showRecoveryRequested = true; dialog.Hide(); };
        var result = await dialog.ShowAsync();
        if (showRecoveryRequested)
        {
            try { await ShowRecoveryKeyAsync(_vault.GetRecoveryKey(), false); }
            catch (Exception error) { await MessageAsync(L("Chave de recuperação"), L(error.Message)); }
            return;
        }
        if (result != ContentDialogResult.Primary) return;
        var selectedLanguage = LanguageForIndex(languageSelector.SelectedIndex);
        var languageChanged = selectedLanguage != WindowsLocalization.CurrentLanguage;
        WindowsLocalization.SetBoolean("AutomaticUpdates", automaticUpdates.IsChecked == true);
        WindowsLocalization.SetBoolean("ReceiveBetaUpdates", betaUpdates.IsChecked == true);
        WindowsLocalization.SetLanguage(selectedLanguage);
        if (languageChanged) ApplyLocalization();
        try
        {
            if (hello.IsChecked == true && !_hello.Exists) await _hello.SaveAsync(_vault.GetContentKey());
            else if (hello.IsChecked != true) _hello.Delete();
            if (_vault.Payload is not null && _vault.Payload.PasswordHistoryEnabled != (history.IsChecked == true))
            { _vault.Payload.PasswordHistoryEnabled = history.IsChecked == true; _vault.Save(); }
            await RefreshHelloAsync();
        }
        catch (Exception error) { await MessageAsync("Windows Hello", L(error.Message)); }
    }

    private async Task ShowRecoveryKeyAsync(string recoveryKey, bool isFirstCreation)
    {
        var introduction = new TextBlock
        {
            Text = isFirstCreation
                ? L("Seu cofre foi criado. Guarde esta chave em um local seguro: ela permite recuperar o acesso ao cofre.")
                : L("Esta chave permite recuperar o acesso ao cofre. Guarde-a em um local seguro."),
            TextWrapping = TextWrapping.Wrap
        };
        var recoveryText = new TextBox
        {
            Text = recoveryKey,
            IsReadOnly = true,
            TextWrapping = TextWrapping.Wrap,
            HorizontalAlignment = HorizontalAlignment.Stretch
        };
        var copyButton = new Button { Content = L("Copiar chave") };
        var copyStatus = new TextBlock
        {
            Text = L("Chave copiada. Por segurança, ela será removida da área de transferência em 30 segundos."),
            TextWrapping = TextWrapping.Wrap,
            Visibility = Visibility.Collapsed
        };
        var path = new TextBlock
        {
            Text = L("Você pode consultar esta chave novamente em: Lion Pass > Ajustes > Segurança > Chave de recuperação."),
            TextWrapping = TextWrapping.Wrap,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
        };
        var privacy = new TextBlock
        {
            Text = L("A chave não será enviada a nenhum servidor. Não a compartilhe com outras pessoas."),
            TextWrapping = TextWrapping.Wrap,
            Opacity = 0.75
        };
        var panel = new StackPanel { Spacing = 12, Width = 560 };
        foreach (var control in new UIElement[] { introduction, recoveryText, copyButton, copyStatus, path, privacy }) panel.Children.Add(control);

        copyButton.Click += async (_, _) =>
        {
            var package = new DataPackage();
            package.SetText(recoveryKey);
            Clipboard.SetContent(package);
            copyStatus.Visibility = Visibility.Visible;
            await Task.Delay(TimeSpan.FromSeconds(30));
            try
            {
                var current = await Clipboard.GetContent().GetTextAsync();
                if (current == recoveryKey) Clipboard.Clear();
            }
            catch { }
        };

        var dialog = new ContentDialog
        {
            Title = L("Chave de recuperação"),
            Content = panel,
            CloseButtonText = L("Concluir"),
            XamlRoot = Content.XamlRoot
        };
        await dialog.ShowAsync();
        recoveryText.Text = string.Empty;
    }

    private ContentDialog Dialog(string title, object content, string primary) => new()
    {
        Title = title, Content = content, PrimaryButtonText = primary,
        CloseButtonText = L("Cancelar"), DefaultButton = ContentDialogButton.Primary,
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


    private async void MainWindow_Loaded(object sender, RoutedEventArgs e)
    {
        ApplyLocalization();
        if (!WindowsLocalization.HasChosenLanguage) await ShowLanguageSelectionAsync();
    }

    private async Task ShowLanguageSelectionAsync()
    {
        var selector = CreateLanguageSelector();
        var panel = new StackPanel { Width = 420, Spacing = 12 };
        panel.Children.Add(new TextBlock { Text = "Escolha seu idioma / Choose your language / Elija su idioma", FontSize = 20, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap });
        panel.Children.Add(selector);
        panel.Children.Add(new TextBlock { Text = "Você poderá mudar o idioma depois em Ajustes. / You can change the language later in Settings. / Podrá cambiar el idioma más tarde en Ajustes.", TextWrapping = TextWrapping.Wrap, Opacity = 0.7 });
        var dialog = new ContentDialog { Title = "Idioma / Language / Idioma", Content = panel, PrimaryButtonText = "Continuar / Continue / Continuar", DefaultButton = ContentDialogButton.Primary, XamlRoot = Content.XamlRoot };
        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
        {
            WindowsLocalization.SetLanguage(LanguageForIndex(selector.SelectedIndex));
            ApplyLocalization();
            await RefreshHelloAsync();
        }
    }

    private static ComboBox CreateLanguageSelector() => new()
    {
        ItemsSource = new[] { "Português (Brasil)", "English", "Español" },
        SelectedIndex = WindowsLocalization.CurrentLanguage switch { "en-US" => 1, "es-ES" => 2, _ => 0 },
        HorizontalAlignment = HorizontalAlignment.Stretch
    };

    private static string LanguageForIndex(int index) => index switch { 1 => "en-US", 2 => "es-ES", _ => "pt-BR" };

    private void ApplyLocalization()
    {
        TranslateElement(Content);
        TranslateMenu(WebsiteFlyout);
        foreach (var item in new[] { CopyUsernameMenuItem, TogglePasswordMenuItem, CopyPasswordMenuItem, CopyEmailMenuItem })
            item.Text = L(item.Text);
        PopulateNavigation();
        RefreshItems();
    }

    private static void TranslateMenu(MenuFlyout menu)
    {
        foreach (var item in menu.Items.OfType<MenuFlyoutItem>()) item.Text = WindowsLocalization.Text(item.Text);
    }

    private static void TranslateElement(DependencyObject element)
    {
        switch (element)
        {
            case TextBlock text when !string.IsNullOrWhiteSpace(text.Text): text.Text = WindowsLocalization.Text(text.Text); break;
            case Button button when button.Content is string buttonContent: button.Content = WindowsLocalization.Text(buttonContent); break;
            case AppBarButton appBar: appBar.Label = WindowsLocalization.Text(appBar.Label); break;
            case NavigationViewItem navigation when navigation.Content is string navigationContent: navigation.Content = WindowsLocalization.Text(navigationContent); break;
            case Expander expander when expander.Header is string header: expander.Header = WindowsLocalization.Text(header); break;
            case ComboBoxItem item when item.Content is string itemContent: item.Content = WindowsLocalization.Text(itemContent); break;
            case TextBox textBox:
                if (textBox.Header is string textHeader) textBox.Header = WindowsLocalization.Text(textHeader);
                if (!string.IsNullOrWhiteSpace(textBox.PlaceholderText)) textBox.PlaceholderText = WindowsLocalization.Text(textBox.PlaceholderText);
                break;
            case PasswordBox passwordBox:
                if (passwordBox.Header is string passwordHeader) passwordBox.Header = WindowsLocalization.Text(passwordHeader);
                if (!string.IsNullOrWhiteSpace(passwordBox.PlaceholderText)) passwordBox.PlaceholderText = WindowsLocalization.Text(passwordBox.PlaceholderText);
                break;
        }
        if (element is FrameworkElement framework && ToolTipService.GetToolTip(framework) is string tooltip) ToolTipService.SetToolTip(framework, WindowsLocalization.Text(tooltip));
        for (var index = 0; index < Microsoft.UI.Xaml.Media.VisualTreeHelper.GetChildrenCount(element); index++) TranslateElement(Microsoft.UI.Xaml.Media.VisualTreeHelper.GetChild(element, index));
    }

    private static string L(string value) => WindowsLocalization.Text(value);
    private static string LF(string value, params object[] arguments) => WindowsLocalization.Format(value, arguments);

    private sealed record TypeOption(VaultItemKind Value)
    {
        public override string ToString() => TypeTitle(Value);
    }

    private sealed record CategoryOption(string Value)
    {
        public override string ToString() => L(Value);
    }

    private static string TypeTitle(VaultItemKind kind) => kind switch
    { VaultItemKind.Login => L("Logins"), VaultItemKind.Card => L("Cartões"), VaultItemKind.SecureNote => L("Notas seguras"), VaultItemKind.Identity => L("Identidades"), _ => L("Outros") };

    private static Symbol CategorySymbol(string category) => category.ToLowerInvariant() switch
    {
        "e-mail" => Symbol.Mail, "bancos" => Symbol.Library, "redes sociais" => Symbol.People,
        "trabalho" => Symbol.Admin, "compras" => Symbol.Shop, "streaming" => Symbol.Video,
        "wi-fi" => Symbol.Globe, "cartões" => Symbol.ContactInfo, "notas" => Symbol.Document,
        "identidades" => Symbol.Contact, _ => Symbol.Folder
    };
}
