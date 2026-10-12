using OpenTelemetry;
using OpenTelemetry.Logs;

namespace Pms.Api.Observability;

/// <summary>Exports only a small allowlist of operational log fields.</summary>
public sealed class TelemetrySanitizingLogProcessor : BaseProcessor<LogRecord>
{
    private static readonly HashSet<string> AllowedAttributes = new(StringComparer.OrdinalIgnoreCase)
    {
        "ExceptionType", "StatusCode", "Method", "RouteTemplate", "CorrelationId", "MessageKind"
    };

    public override void OnEnd(LogRecord logRecord)
    {
        var safeAttributes = new List<KeyValuePair<string, object?>>();
        if (logRecord.Attributes is not null)
        {
            foreach (var attribute in logRecord.Attributes)
            {
                if (!AllowedAttributes.Contains(attribute.Key) || !IsSafe(attribute.Key, attribute.Value))
                    continue;

                safeAttributes.Add(attribute);
            }
        }

        // Never forward a rendered message, raw state, or Exception object. These can
        // contain email addresses, tokens, provider response bodies, or request data.
        logRecord.Body = "TaskFlow application event";
        logRecord.FormattedMessage = null;
        logRecord.Exception = null;
        logRecord.Attributes = safeAttributes;

        base.OnEnd(logRecord);
    }

    private static bool IsSafe(string key, object? value)
    {
        if (value is null) return false;

        return key.ToLowerInvariant() switch
        {
            "exceptiontype" => value is string typeName
                && typeName.Length <= 160
                && typeName.All(character => char.IsLetterOrDigit(character) || character is '.' or '_' or '`' or '+'),
            "statuscode" => value is int statusCode && statusCode is >= 100 and <= 599,
            "method" => value is string method && method is "GET" or "POST" or "PUT" or "PATCH" or "DELETE" or "OPTIONS" or "HEAD",
            "routetemplate" => value is string route && route.Length <= 200 && route.StartsWith('/') && !route.Contains('?'),
            "correlationid" => value is string correlationId
                && (Guid.TryParse(correlationId, out _) || (correlationId.Length == 32 && correlationId.All(Uri.IsHexDigit))),
            "messagekind" => value is string kind && kind is "link" or "verification" or "task_assignment",
            _ => false
        };
    }
}
