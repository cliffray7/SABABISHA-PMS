using System.Diagnostics;
using OpenTelemetry;

namespace Pms.Api.Observability;

/// <summary>
/// Removes high-risk attributes before spans are handed to any configured exporter.
/// Route templates, status codes, service names, and correlation IDs remain available.
/// </summary>
public sealed class TelemetrySanitizingActivityProcessor : BaseProcessor<System.Diagnostics.Activity>
{
    private static readonly string[] RemovedAttributes =
    [
        "url.full",
        "url.path",
        "url.query",
        "http.url",
        "http.target",
        "http.request.header.authorization",
        "http.request.header.cookie",
        "http.request.header.set_cookie",
        "db.statement",
        "db.query.text",
        "exception.message",
        "exception.stacktrace"
    ];

    public override void OnEnd(System.Diagnostics.Activity activity)
    {
        foreach (var attribute in RemovedAttributes)
            activity.SetTag(attribute, null);

        foreach (var tag in activity.TagObjects.ToArray())
        {
            var key = tag.Key.ToLowerInvariant();
            if (key.Contains("token", StringComparison.Ordinal)
                || key.Contains("password", StringComparison.Ordinal)
                || key.Contains("secret", StringComparison.Ordinal)
                || key.Contains("api.key", StringComparison.Ordinal)
                || key.Contains("authorization", StringComparison.Ordinal)
                || key.Contains("cookie", StringComparison.Ordinal))
            {
                activity.SetTag(tag.Key, null);
            }
        }

        base.OnEnd(activity);
    }
}
