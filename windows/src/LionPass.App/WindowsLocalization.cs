using System.Globalization;
using System.Text.Json;
using Microsoft.Win32;

namespace LionPass.App;

internal static class WindowsLocalization
{
    private const string RegistryPath = @"Software\Lion Code Technology\Lion Pass";
    private static readonly Lazy<Dictionary<string, Dictionary<string, string>>> Catalog = new(LoadCatalog);

    public static string CurrentLanguage { get; private set; } = LoadLanguage();
    public static bool HasChosenLanguage
    {
        get { using var key = Registry.CurrentUser.OpenSubKey(RegistryPath); return key?.GetValue("LanguageChosen")?.ToString() == "1"; }
    }

    public static string Text(string source)
    {
        var portuguese = source;
        if (!Catalog.Value.ContainsKey(portuguese))
        {
            var match = Catalog.Value.FirstOrDefault(entry => entry.Value.Values.Contains(source, StringComparer.Ordinal));
            if (!string.IsNullOrEmpty(match.Key)) portuguese = match.Key;
        }
        var locale = CurrentLanguage == "en-US" ? "en" : CurrentLanguage == "es-ES" ? "es" : "pt-BR";
        return Catalog.Value.TryGetValue(portuguese, out var values) && values.TryGetValue(locale, out var value) ? value : portuguese;
    }

    public static string Format(string format, params object[] arguments) =>
        string.Format(CultureInfo.CurrentCulture, Text(format), arguments);

    public static void SetLanguage(string language, bool markChosen = true)
    {
        CurrentLanguage = Normalize(language);
        using var key = Registry.CurrentUser.CreateSubKey(RegistryPath);
        key.SetValue("Language", CurrentLanguage);
        if (markChosen) key.SetValue("LanguageChosen", "1");
        ApplyCulture();
    }

public static bool GetBoolean(string name, bool defaultValue)
{
    using var key = Registry.CurrentUser.OpenSubKey(RegistryPath);
    var stored = key?.GetValue(name);
    return stored is null ? defaultValue : stored.ToString() == "1";
}

public static void SetBoolean(string name, bool value)
{
    using var key = Registry.CurrentUser.CreateSubKey(RegistryPath);
    key.SetValue(name, value ? "1" : "0");
}

    public static void ApplyCulture()
    {
        var culture = CultureInfo.GetCultureInfo(CurrentLanguage);
        CultureInfo.CurrentCulture = culture;
        CultureInfo.CurrentUICulture = culture;
        CultureInfo.DefaultThreadCurrentCulture = culture;
        CultureInfo.DefaultThreadCurrentUICulture = culture;
    }

    private static string LoadLanguage()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RegistryPath);
        var selected = key?.GetValue("Language")?.ToString();
        if (!string.IsNullOrWhiteSpace(selected)) return Normalize(selected);
        return CultureInfo.CurrentUICulture.TwoLetterISOLanguageName switch { "en" => "en-US", "es" => "es-ES", _ => "pt-BR" };
    }

    private static string Normalize(string value) => value.ToLowerInvariant() switch
    {
        "en" or "en-us" or "english" => "en-US",
        "es" or "es-es" or "spanish" => "es-ES",
        _ => "pt-BR"
    };

    private static Dictionary<string, Dictionary<string, string>> LoadCatalog()
    {
        var result = new Dictionary<string, Dictionary<string, string>>(StringComparer.Ordinal);
        var path = Path.Combine(AppContext.BaseDirectory, "Localizable.xcstrings");
        if (!File.Exists(path)) return result;
        using var document = JsonDocument.Parse(File.ReadAllText(path));
        if (!document.RootElement.TryGetProperty("strings", out var strings)) return result;
        foreach (var entry in strings.EnumerateObject())
        {
            var values = new Dictionary<string, string>(StringComparer.Ordinal) { ["pt-BR"] = entry.Name };
            if (entry.Value.TryGetProperty("localizations", out var localizations))
                foreach (var localization in localizations.EnumerateObject())
                    if (localization.Value.TryGetProperty("stringUnit", out var unit) && unit.TryGetProperty("value", out var value))
                        values[localization.Name] = value.GetString() ?? entry.Name;
            result[entry.Name] = values;
        }
        return result;
    }
}
