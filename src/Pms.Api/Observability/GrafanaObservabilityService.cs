using System.Globalization;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace Pms.Api.Observability;

public sealed record GrafanaMetricSummary(
    string Status,
    double? RequestsPerSecond,
    double? ServerErrorsPerSecond,
    double? ServerErrorPercent,
    double? P95DurationMilliseconds,
    IReadOnlyList<GrafanaMetricPoint> Series,
    string Message);

public sealed record GrafanaMetricPoint(
    DateTimeOffset Timestamp,
    double? RequestsPerSecond,
    double? ServerErrorsPerSecond,
    double? ServerErrorPercent,
    double? P50DurationMilliseconds,
    double? P95DurationMilliseconds,
    double? P99DurationMilliseconds);

public sealed record GrafanaLogEntry(DateTimeOffset Timestamp, string Severity, string Message);

public sealed record GrafanaTraceEntry(
    string TraceId,
    string ServiceName,
    DateTimeOffset StartedAt,
    double DurationMilliseconds);

public sealed record GrafanaDataResult<T>(string Status, IReadOnlyList<T> Items, string Message);

public sealed record GrafanaObservabilityResponse(
    string Range,
    DateTimeOffset QueriedAt,
    GrafanaMetricSummary Metrics,
    GrafanaDataResult<GrafanaLogEntry> Logs,
    GrafanaDataResult<GrafanaTraceEntry> Traces);

/// <summary>Read-only, bounded queries for TaskFlow telemetry stored in Grafana Cloud.</summary>
public sealed class GrafanaObservabilityService(
    IHttpClientFactory httpClientFactory,
    IConfiguration configuration,
    ILogger<GrafanaObservabilityService> logger)
{
    private const string ServiceName = "Pms.Api";
    private static readonly TimeSpan RequestTimeout = TimeSpan.FromSeconds(8);

    public async Task<GrafanaObservabilityResponse> QueryAsync(string? range, CancellationToken cancellationToken)
    {
        var normalizedRange = NormalizeRange(range);
        var rangeDuration = ParseRange(normalizedRange);
        var queriedAt = DateTimeOffset.UtcNow;

        var rangeStart = queriedAt - rangeDuration;
        var metricsTask = QueryMetricsAsync(normalizedRange, rangeStart, queriedAt, cancellationToken);
        var logsTask = QueryLogsAsync(rangeStart, queriedAt, cancellationToken);
        var tracesTask = QueryTracesAsync(rangeStart, queriedAt, cancellationToken);
        await Task.WhenAll(metricsTask, logsTask, tracesTask);

        return new GrafanaObservabilityResponse(
            normalizedRange,
            queriedAt,
            await metricsTask,
            await logsTask,
            await tracesTask);
    }

    private async Task<GrafanaMetricSummary> QueryMetricsAsync(
        string range, DateTimeOffset from, DateTimeOffset to, CancellationToken cancellationToken)
    {
        if (!TryGetDataSource("Metrics", out var endpoint, out var username, out var token))
            return new GrafanaMetricSummary("not_configured", null, null, null, null, Array.Empty<GrafanaMetricPoint>(),
                "Grafana metrics read access is not configured.");

        try
        {
            var (step, rateWindow) = GetQueryResolution(range);
            var queryTasks = new[]
            {
                QueryPrometheusSeriesAsync(endpoint, username, token,
                    $"sum(rate(http_server_request_duration_seconds_count{{service_name=\"{ServiceName}\"}}[{rateWindow}]))", from, to, step, cancellationToken),
                QueryPrometheusSeriesAsync(endpoint, username, token,
                    $"sum(rate(http_server_request_duration_seconds_count{{service_name=\"{ServiceName}\",http_response_status_code=~\"5..\"}}[{rateWindow}]))", from, to, step, cancellationToken),
                QueryPrometheusSeriesAsync(endpoint, username, token,
                    $"histogram_quantile(0.50, sum(rate(http_server_request_duration_seconds_bucket{{service_name=\"{ServiceName}\"}}[{rateWindow}])) by (le))", from, to, step, cancellationToken),
                QueryPrometheusSeriesAsync(endpoint, username, token,
                    $"histogram_quantile(0.95, sum(rate(http_server_request_duration_seconds_bucket{{service_name=\"{ServiceName}\"}}[{rateWindow}])) by (le))", from, to, step, cancellationToken),
                QueryPrometheusSeriesAsync(endpoint, username, token,
                    $"histogram_quantile(0.99, sum(rate(http_server_request_duration_seconds_bucket{{service_name=\"{ServiceName}\"}}[{rateWindow}])) by (le))", from, to, step, cancellationToken)
            };
            var values = await Task.WhenAll(queryTasks);
            var timestamps = values.SelectMany(series => series.Keys).Distinct().Order().Take(MaxSeriesPoints).ToArray();
            var points = timestamps.Select(timestamp =>
            {
                var requestRate = GetSample(values[0], timestamp);
                double? serverErrorRate = requestRate.HasValue ? GetSample(values[1], timestamp) ?? 0d : null;
                double? errorPercent = requestRate is > 0 && serverErrorRate.HasValue
                    ? Math.Round(serverErrorRate.Value / requestRate.Value * 100d, 2)
                    : requestRate == 0 ? 0d : null;
                return new GrafanaMetricPoint(timestamp, requestRate, serverErrorRate, errorPercent,
                    ToMilliseconds(GetSample(values[2], timestamp)),
                    ToMilliseconds(GetSample(values[3], timestamp)),
                    ToMilliseconds(GetSample(values[4], timestamp)));
            }).ToArray();
            var latestRequests = LatestValue(points, point => point.RequestsPerSecond);
            var latestErrors = LatestValue(points, point => point.ServerErrorsPerSecond);
            var latestErrorPercent = LatestValue(points, point => point.ServerErrorPercent);
            var latestP95 = LatestValue(points, point => point.P95DurationMilliseconds);
            // If request telemetry exists but there are no 5xx samples, that is a real zero-error result.
            // If the request series itself is absent, keep the error metrics unknown instead of inventing zeroes.
            var hasData = points.Any(point => point.RequestsPerSecond.HasValue
                || point.P50DurationMilliseconds.HasValue || point.P95DurationMilliseconds.HasValue
                || point.P99DurationMilliseconds.HasValue);

            return new GrafanaMetricSummary(
                hasData ? "available" : "no_data",
                latestRequests,
                latestErrors,
                latestErrorPercent,
                latestP95,
                points,
                hasData ? $"Prometheus time-series results for Pms.Api over {range}. Missing individual series are shown as no data." : "No matching metric series were returned for Pms.Api in this range.");
        }
        catch (Exception exception) when (IsProviderFailure(exception))
        {
            logger.LogWarning("Grafana metrics query failed with {ExceptionType}", exception.GetType().Name);
            return new GrafanaMetricSummary("unavailable", null, null, null, null, Array.Empty<GrafanaMetricPoint>(),
                "Grafana metrics could not be queried. Check the server-side read configuration and retry.");
        }
    }

    private async Task<GrafanaDataResult<GrafanaLogEntry>> QueryLogsAsync(
        DateTimeOffset from, DateTimeOffset to, CancellationToken cancellationToken)
    {
        if (!TryGetDataSource("Logs", out var endpoint, out var username, out var token))
            return EmptyResult<GrafanaLogEntry>("not_configured", "Grafana logs read access is not configured.");

        try
        {
            var query = "{service_name=\"Pms.Api\", level=~\"WARN|ERROR\"}";
            var url = AppendPath(endpoint, "loki/api/v1/query_range");
            url = AddQuery(url, ("query", query), ("start", ToUnixNanoseconds(from)),
                ("end", ToUnixNanoseconds(to)), ("limit", "50"), ("direction", "backward"));
            using var document = await SendJsonAsync(url, username, token, cancellationToken);
            var entries = new List<GrafanaLogEntry>();
            if (TryGetProperty(document.RootElement, "data", out var data)
                && TryGetProperty(data, "result", out var streams)
                && streams.ValueKind == JsonValueKind.Array)
            {
                foreach (var stream in streams.EnumerateArray())
                {
                    var severity = "warning/error";
                    if (TryGetProperty(stream, "stream", out var labels)
                        && TryGetProperty(labels, "level", out var level)
                        && level.ValueKind == JsonValueKind.String)
                        severity = NormalizeSeverity(level.GetString());

                    if (!TryGetProperty(stream, "values", out var values) || values.ValueKind != JsonValueKind.Array)
                        continue;
                    foreach (var pair in values.EnumerateArray())
                    {
                        if (pair.ValueKind != JsonValueKind.Array || pair.GetArrayLength() < 1
                            || !long.TryParse(pair[0].GetString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var nanos))
                            continue;
                        entries.Add(new GrafanaLogEntry(FromUnixNanoseconds(nanos), severity,
                            "Sanitized application warning or error. Log content is intentionally withheld."));
                    }
                }
            }

            var limited = entries.OrderByDescending(entry => entry.Timestamp).Take(50).ToArray();
            return new GrafanaDataResult<GrafanaLogEntry>(
                limited.Length == 0 ? "no_data" : "available", limited,
                limited.Length == 0 ? "No warning or error log entries were returned for Pms.Api." : "Sanitized warning and error events from Loki.");
        }
        catch (Exception exception) when (IsProviderFailure(exception))
        {
            logger.LogWarning("Grafana logs query failed with {ExceptionType}", exception.GetType().Name);
            return EmptyResult<GrafanaLogEntry>("unavailable", "Grafana logs could not be queried. Check the server-side read configuration and retry.");
        }
    }

    private async Task<GrafanaDataResult<GrafanaTraceEntry>> QueryTracesAsync(
        DateTimeOffset from, DateTimeOffset to, CancellationToken cancellationToken)
    {
        if (!TryGetDataSource("Traces", out var endpoint, out var username, out var token))
            return EmptyResult<GrafanaTraceEntry>("not_configured", "Grafana traces read access is not configured.");

        try
        {
            var url = AppendPath(endpoint, "api/search");
            url = AddQuery(url,
                ("q", "{ resource.service.name = \"Pms.Api\" }"),
                ("start", from.ToUnixTimeSeconds().ToString(CultureInfo.InvariantCulture)),
                ("end", to.ToUnixTimeSeconds().ToString(CultureInfo.InvariantCulture)),
                ("limit", "20"));
            using var document = await SendJsonAsync(url, username, token, cancellationToken);
            var entries = new List<GrafanaTraceEntry>();
            if (TryGetProperty(document.RootElement, "traces", out var traces) && traces.ValueKind == JsonValueKind.Array)
            {
                foreach (var trace in traces.EnumerateArray())
                {
                    if (!TryGetProperty(trace, "traceID", out var traceIdElement)
                        || traceIdElement.ValueKind != JsonValueKind.String)
                        continue;
                    var traceId = traceIdElement.GetString();
                    if (string.IsNullOrWhiteSpace(traceId) || traceId.Length > 64
                        || !traceId.All(Uri.IsHexDigit)) continue;

                    var startNanos = TryGetProperty(trace, "startTimeUnixNano", out var startElement)
                        && long.TryParse(startElement.ToString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsedStart)
                        ? parsedStart : 0;
                    var duration = TryGetProperty(trace, "durationMs", out var durationElement)
                        && double.TryParse(durationElement.ToString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var parsedDuration)
                        && double.IsFinite(parsedDuration) && parsedDuration >= 0
                        ? parsedDuration : 0;
                    entries.Add(new GrafanaTraceEntry(traceId, ServiceName,
                        startNanos > 0 ? FromUnixNanoseconds(startNanos) : to, duration));
                }
            }

            var limited = entries.Take(20).ToArray();
            return new GrafanaDataResult<GrafanaTraceEntry>(
                limited.Length == 0 ? "no_data" : "available", limited,
                limited.Length == 0 ? "No traces were returned for Pms.Api in this time range." : "Live trace search results from Tempo.");
        }
        catch (Exception exception) when (IsProviderFailure(exception))
        {
            logger.LogWarning("Grafana traces query failed with {ExceptionType}", exception.GetType().Name);
            return EmptyResult<GrafanaTraceEntry>("unavailable", "Grafana traces could not be queried. Check the server-side read configuration and retry.");
        }
    }

    private async Task<IReadOnlyDictionary<DateTimeOffset, double>> QueryPrometheusSeriesAsync(
        Uri endpoint, string username, string token, string query, DateTimeOffset from, DateTimeOffset to, string step,
        CancellationToken cancellationToken)
    {
        var url = AddQuery(AppendPath(endpoint, "api/v1/query_range"),
            ("query", query), ("start", from.ToUnixTimeSeconds().ToString(CultureInfo.InvariantCulture)),
            ("end", to.ToUnixTimeSeconds().ToString(CultureInfo.InvariantCulture)), ("step", step));
        using var document = await SendJsonAsync(url, username, token, cancellationToken);
        var samples = new SortedDictionary<DateTimeOffset, double>();
        if (!TryGetProperty(document.RootElement, "data", out var data)
            || !TryGetProperty(data, "result", out var result)
            || result.ValueKind != JsonValueKind.Array
            || result.GetArrayLength() == 0)
            return samples;

        // All allowlisted PromQL expressions aggregate to a single series. Ignore any extra
        // provider series and cap parsed samples even if a provider violates the requested step.
        var first = result[0];
        if (!TryGetProperty(first, "values", out var values) || values.ValueKind != JsonValueKind.Array)
            return samples;
        foreach (var pair in values.EnumerateArray().Take(MaxSeriesPoints))
        {
            if (pair.ValueKind != JsonValueKind.Array || pair.GetArrayLength() < 2
                || !TryGetDouble(pair[0], out var unixSeconds)
                || !TryGetDouble(pair[1], out var value)
                || unixSeconds < 0 || unixSeconds > DateTimeOffset.MaxValue.ToUnixTimeSeconds())
                continue;
            try
            {
                samples[DateTimeOffset.FromUnixTimeMilliseconds((long)(unixSeconds * 1000d))] = value;
            }
            catch (ArgumentOutOfRangeException)
            {
                // Ignore malformed timestamps from the telemetry provider.
            }
        }
        return samples;
    }

    private static double? GetSample(IReadOnlyDictionary<DateTimeOffset, double> samples, DateTimeOffset timestamp) =>
        samples.TryGetValue(timestamp, out var value) ? value : null;
    private static double? LatestValue(IEnumerable<GrafanaMetricPoint> points, Func<GrafanaMetricPoint, double?> selector) =>
        points.LastOrDefault(point => selector(point).HasValue) is { } latest ? selector(latest) : null;
    private static double? ToMilliseconds(double? seconds) => seconds is { } value ? value * 1000d : null;
    private static bool TryGetDouble(JsonElement element, out double value)
    {
        var raw = element.ValueKind == JsonValueKind.String ? element.GetString() : element.ToString();
        return double.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out value) && double.IsFinite(value);
    }

    private async Task<JsonDocument> SendJsonAsync(Uri url, string username, string token, CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        var encodedCredentials = Convert.ToBase64String(Encoding.UTF8.GetBytes($"{username}:{token}"));
        request.Headers.Authorization = new AuthenticationHeaderValue("Basic", encodedCredentials);
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(RequestTimeout);
        using var response = await httpClientFactory.CreateClient("GrafanaObservability").SendAsync(
            request, HttpCompletionOption.ResponseHeadersRead, timeout.Token);
        response.EnsureSuccessStatusCode();
        await using var stream = await response.Content.ReadAsStreamAsync(timeout.Token);
        return await JsonDocument.ParseAsync(stream, cancellationToken: timeout.Token);
    }

    private bool TryGetDataSource(string name, out Uri endpoint, out string username, out string token)
    {
        endpoint = null!;
        username = configuration[$"Observability:Grafana:{name}:User"] ?? string.Empty;
        token = configuration["Observability:Grafana:QueryToken"] ?? string.Empty;
        var endpointValue = configuration[$"Observability:Grafana:{name}:Endpoint"];
        if (string.IsNullOrWhiteSpace(username) || string.IsNullOrWhiteSpace(token)
            || !Uri.TryCreate(endpointValue, UriKind.Absolute, out var configuredEndpoint)
            || configuredEndpoint.Scheme != Uri.UriSchemeHttps
            || !string.IsNullOrEmpty(configuredEndpoint.UserInfo)
            || !string.IsNullOrEmpty(configuredEndpoint.Query)
            || !string.IsNullOrEmpty(configuredEndpoint.Fragment))
            return false;

        endpoint = configuredEndpoint;
        return true;
    }

    private static Uri AppendPath(Uri endpoint, string relativePath)
    {
        var builder = new UriBuilder(endpoint)
        {
            Path = $"{endpoint.AbsolutePath.TrimEnd('/')}/{relativePath.TrimStart('/')}"
        };
        return builder.Uri;
    }

    private static Uri AddQuery(Uri endpoint, params (string Name, string Value)[] parameters)
    {
        var builder = new UriBuilder(endpoint);
        builder.Query = string.Join("&", parameters.Select(parameter =>
            $"{Uri.EscapeDataString(parameter.Name)}={Uri.EscapeDataString(parameter.Value)}"));
        return builder.Uri;
    }

    private const int MaxSeriesPoints = 168;
    private static string NormalizeRange(string? range) => range is "1h" or "6h" or "24h" or "7d" ? range : "1h";
    private static TimeSpan ParseRange(string range) => range switch
    {
        "6h" => TimeSpan.FromHours(6),
        "24h" => TimeSpan.FromHours(24),
        "7d" => TimeSpan.FromDays(7),
        _ => TimeSpan.FromHours(1)
    };
    private static (string Step, string RateWindow) GetQueryResolution(string range) => range switch
    {
        "6h" => ("5m", "5m"),
        "24h" => ("15m", "15m"),
        "7d" => ("1h", "1h"),
        _ => ("1m", "5m")
    };
    private static string ToUnixNanoseconds(DateTimeOffset value) =>
        checked(value.ToUnixTimeMilliseconds() * 1_000_000).ToString(CultureInfo.InvariantCulture);
    private static DateTimeOffset FromUnixNanoseconds(long value) =>
        DateTimeOffset.FromUnixTimeMilliseconds(value / 1_000_000);
    private static string NormalizeSeverity(string? severity) => severity?.ToUpperInvariant() switch
    {
        "ERROR" or "FATAL" => "error",
        "WARN" or "WARNING" => "warning",
        _ => "warning/error"
    };
    private static bool TryGetProperty(JsonElement element, string name, out JsonElement value)
    {
        if (element.ValueKind == JsonValueKind.Object)
            return element.TryGetProperty(name, out value);
        value = default;
        return false;
    }
    private static bool IsProviderFailure(Exception exception) =>
        exception is HttpRequestException or TaskCanceledException or OperationCanceledException
            or JsonException or InvalidOperationException or FormatException or OverflowException;
    private static GrafanaDataResult<T> EmptyResult<T>(string status, string message) =>
        new(status, Array.Empty<T>(), message);
}
