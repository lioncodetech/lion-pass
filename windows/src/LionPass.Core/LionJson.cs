using System.Text.Json;
using System.Text.Json.Serialization;

namespace LionPass.Core;

internal static class LionJson
{
    internal static readonly DateTimeOffset AppleReferenceDate =
        new(2001, 1, 1, 0, 0, 0, TimeSpan.Zero);

    internal static readonly JsonSerializerOptions Options = CreateOptions();

    private static JsonSerializerOptions CreateOptions()
    {
        var options = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            PropertyNameCaseInsensitive = false,
            WriteIndented = false
        };
        options.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.CamelCase));
        options.Converters.Add(new AppleDateConverter());
        options.Converters.Add(new NullableAppleDateConverter());
        return options;
    }
}

internal sealed class AppleDateConverter : JsonConverter<DateTimeOffset>
{
    public override DateTimeOffset Read(ref Utf8JsonReader reader, Type type, JsonSerializerOptions options)
    {
        var value = reader.GetDouble();
        return Math.Abs(value) > 10_000_000_000
            ? DateTimeOffset.FromUnixTimeMilliseconds(checked((long)value))
            : LionJson.AppleReferenceDate.AddSeconds(value);
    }

    public override void Write(Utf8JsonWriter writer, DateTimeOffset value, JsonSerializerOptions options) =>
        writer.WriteNumberValue((value.ToUniversalTime() - LionJson.AppleReferenceDate).TotalSeconds);
}

internal sealed class NullableAppleDateConverter : JsonConverter<DateTimeOffset?>
{
    public override DateTimeOffset? Read(ref Utf8JsonReader reader, Type type, JsonSerializerOptions options)
    {
        if (reader.TokenType == JsonTokenType.Null) return null;
        var value = reader.GetDouble();
        return Math.Abs(value) > 10_000_000_000
            ? DateTimeOffset.FromUnixTimeMilliseconds(checked((long)value))
            : LionJson.AppleReferenceDate.AddSeconds(value);
    }

    public override void Write(Utf8JsonWriter writer, DateTimeOffset? value, JsonSerializerOptions options)
    {
        if (value is null) writer.WriteNullValue();
        else writer.WriteNumberValue((value.Value.ToUniversalTime() - LionJson.AppleReferenceDate).TotalSeconds);
    }
}
