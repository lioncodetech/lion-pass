using System.Security.Cryptography;
using System.Text;

namespace LionPass.Core;

public static class PasswordGenerator
{
    public static string Generate(int length = 24, bool uppercase = true, bool lowercase = true,
        bool digits = true, bool symbols = true, bool excludeSimilar = true)
    {
        var groups = new List<string>();
        if (uppercase) groups.Add("ABCDEFGHIJKLMNOPQRSTUVWXYZ");
        if (lowercase) groups.Add("abcdefghijklmnopqrstuvwxyz");
        if (digits) groups.Add("0123456789");
        if (symbols) groups.Add("!@#$%^&*()-_=+[]{};:,.?");
        if (excludeSimilar) groups = groups.Select(x => new string(x.Where(c => !"Il1O0|".Contains(c)).ToArray())).ToList();
        groups.RemoveAll(string.IsNullOrEmpty);
        if (groups.Count == 0) return "";
        length = Math.Max(8, Math.Max(length, groups.Count));
        var result = groups.Select(group => group[RandomNumberGenerator.GetInt32(group.Length)]).ToList();
        var alphabet = string.Concat(groups);
        while (result.Count < length) result.Add(alphabet[RandomNumberGenerator.GetInt32(alphabet.Length)]);
        for (var index = result.Count - 1; index > 0; index--)
        {
            var destination = RandomNumberGenerator.GetInt32(index + 1);
            (result[index], result[destination]) = (result[destination], result[index]);
        }
        return new string(result.ToArray());
    }
}

public static class PasswordSecurityAudit
{
    private static readonly HashSet<string> Common = new(StringComparer.OrdinalIgnoreCase)
    {
        "123456", "12345678", "123456789", "1234567890", "password", "password1",
        "qwerty", "qwerty123", "abc123", "111111", "000000", "admin", "letmein",
        "welcome", "iloveyou", "senha", "senha123", "changeme"
    };

    public static string? Warning(VaultItem item, IEnumerable<VaultItem> items)
    {
        if (item.Kind != VaultItemKind.Login || item.DeletedAt is not null || item.Password.Length == 0) return null;
        if (Common.Contains(item.Password)) return "Esta senha aparece em listas locais de senhas muito comprometidas.";
        if (item.Password.Length < 12) return "Esta senha é curta. Use pelo menos 12 caracteres.";
        if (items.Any(other => other.Id != item.Id && other.Kind == VaultItemKind.Login &&
            other.DeletedAt is null && other.Password.Length > 0 && other.Password == item.Password))
            return "Esta senha está sendo reutilizada em outra conta.";
        return null;
    }
}

public static class CsvTransfer
{
    private static readonly string[] Header = ["title", "username", "password", "website", "email", "notes", "category", "favorite"];

    public static string Export(IEnumerable<VaultItem> items)
    {
        var lines = new List<string> { string.Join(',', Header) };
        lines.AddRange(items.Select(item => string.Join(',', new[]
        {
            item.Title, item.Username, item.Password, item.Website, item.Email,
            item.Notes, item.Category, item.IsFavorite ? "true" : "false"
        }.Select(Escape))));
        return string.Join(Environment.NewLine, lines);
    }

    public static IReadOnlyList<VaultItem> Import(string csv)
    {
        var rows = Parse(csv).ToList();
        if (rows.Count == 0) return [];
        var header = rows[0].Select((name, index) => (name, index))
            .ToDictionary(x => x.name.Trim().ToLowerInvariant(), x => x.index);
        string Value(IReadOnlyList<string> row, string name) =>
            header.TryGetValue(name, out var index) && index < row.Count ? row[index] : "";
        return rows.Skip(1).Where(row => row.Any(value => value.Length > 0)).Select(row => new VaultItem
        {
            Title = Value(row, "title"), Username = Value(row, "username"),
            Password = Value(row, "password"), Website = Value(row, "website"),
            Email = Value(row, "email"), Notes = Value(row, "notes"),
            Category = string.IsNullOrWhiteSpace(Value(row, "category")) ? "Logins" : Value(row, "category"),
            IsFavorite = bool.TryParse(Value(row, "favorite"), out var favorite) && favorite
        }).ToArray();
    }

    private static string Escape(string value)
    {
        var safeValue = NeutralizeFormula(value);
        return safeValue.IndexOfAny([',', '"', '\r', '\n']) >= 0
            ? $"\"{safeValue.Replace("\"", "\"\"")}\"" : safeValue;
    }

    private static string NeutralizeFormula(string value)
    {
        if (value.Length == 0) return value;
        return value[0] is '=' or '+' or '-' or '@' or '\t' or '\r' ? "'" + value : value;
    }

    private static IEnumerable<IReadOnlyList<string>> Parse(string text)
    {
        var row = new List<string>();
        var field = new StringBuilder();
        var quoted = false;
        for (var index = 0; index < text.Length; index++)
        {
            var current = text[index];
            if (quoted && current == '"' && index + 1 < text.Length && text[index + 1] == '"')
            { field.Append('"'); index++; }
            else if (current == '"') quoted = !quoted;
            else if (!quoted && current == ',') { row.Add(field.ToString()); field.Clear(); }
            else if (!quoted && (current == '\r' || current == '\n'))
            {
                if (current == '\r' && index + 1 < text.Length && text[index + 1] == '\n') index++;
                row.Add(field.ToString()); field.Clear(); yield return row; row = [];
            }
            else field.Append(current);
        }
        if (field.Length > 0 || row.Count > 0) { row.Add(field.ToString()); yield return row; }
    }
}
