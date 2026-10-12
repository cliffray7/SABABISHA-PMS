using System.Collections.Concurrent;
using System.Net;
using System.Text;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Pms.Api.Observability;

namespace Pms.IntegrationTests;

public sealed class GrafanaObservabilityTests
{
    [Fact]
    public async Task MissingReadConfigurationReturnsNotConfiguredWithoutRequests()
    {
        var handler = new RecordingHandler();
        var service = CreateService(handler, new Dictionary<string, string?>());

        var response = await service.QueryAsync("1h", CancellationToken.None);

        Assert.Equal("not_configured", response.Metrics.Status);
        Assert.Equal("not_configured", response.Logs.Status);
        Assert.Equal("not_configured", response.Traces.Status);
        Assert.Empty(handler.Requests);
    }

    [Fact]
    public async Task QueriesUseFixedPathsReadCredentialsAndSanitizedResponses()
    {
        var handler = new RecordingHandler();
        var service = CreateService(handler, Configuration());

        var response = await service.QueryAsync("999h", CancellationToken.None);

        Assert.Equal("1h", response.Range);
        Assert.Equal("available", response.Metrics.Status);
        Assert.Equal(10, response.Metrics.RequestsPerSecond);
        Assert.Equal(2, response.Metrics.ServerErrorsPerSecond);
        Assert.Equal(20, response.Metrics.ServerErrorPercent);
        Assert.Equal(250, response.Metrics.P95DurationMilliseconds);
        Assert.Equal("available", response.Logs.Status);
        Assert.Equal("Sanitized application warning or error. Log content is intentionally withheld.",
            Assert.Single(response.Logs.Items).Message);
        Assert.Equal("available", response.Traces.Status);
        Assert.Equal("aabbccdd", Assert.Single(response.Traces.Items).TraceId);

        Assert.Contains(handler.Requests, request => request.Path == "/api/prom/api/v1/query");
        Assert.Contains(handler.Requests, request => request.Path == "/loki/loki/api/v1/query_range");
        Assert.Contains(handler.Requests, request => request.Path == "/tempo/api/search");
        Assert.All(handler.Requests, request => Assert.Equal("Basic " + Convert.ToBase64String(Encoding.UTF8.GetBytes("reader-id:read-token")), request.Authorization));
        Assert.Contains(handler.Requests, request => request.Query.Contains("service_name%3D%22Pms.Api%22", StringComparison.Ordinal));
        Assert.DoesNotContain(handler.Requests, request => request.Query.Contains("999h", StringComparison.Ordinal));
    }

    [Fact]
    public async Task ProviderFailureIsSanitizedAndDoesNotFailDashboardRequest()
    {
        var handler = new RecordingHandler(_ => new HttpResponseMessage(HttpStatusCode.Unauthorized)
        {
            Content = new StringContent("private-token-details")
        });
        var service = CreateService(handler, Configuration());

        var response = await service.QueryAsync("15m", CancellationToken.None);

        Assert.Equal("unavailable", response.Metrics.Status);
        Assert.Equal("unavailable", response.Logs.Status);
        Assert.Equal("unavailable", response.Traces.Status);
        Assert.DoesNotContain("private-token-details", string.Join(" ", response.Logs.Message, response.Traces.Message, response.Metrics.Message));
    }

    private static GrafanaObservabilityService CreateService(
        HttpMessageHandler handler,
        IDictionary<string, string?> values)
    {
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(values).Build();
        return new GrafanaObservabilityService(new StubHttpClientFactory(handler), configuration,
            NullLogger<GrafanaObservabilityService>.Instance);
    }

    private static Dictionary<string, string?> Configuration() => new()
    {
        ["Observability:Grafana:QueryToken"] = "read-token",
        ["Observability:Grafana:Metrics:Endpoint"] = "https://metrics.example.test/api/prom",
        ["Observability:Grafana:Metrics:User"] = "reader-id",
        ["Observability:Grafana:Logs:Endpoint"] = "https://logs.example.test/loki",
        ["Observability:Grafana:Logs:User"] = "reader-id",
        ["Observability:Grafana:Traces:Endpoint"] = "https://traces.example.test/tempo",
        ["Observability:Grafana:Traces:User"] = "reader-id"
    };

    private sealed class StubHttpClientFactory(HttpMessageHandler handler) : IHttpClientFactory
    {
        private readonly HttpClient client = new(handler);
        public HttpClient CreateClient(string name) => client;
    }

    private sealed class RecordingHandler(Func<HttpRequestMessage, HttpResponseMessage>? responseFactory = null) : HttpMessageHandler
    {
        public ConcurrentBag<RecordedRequest> Requests { get; } = [];

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Requests.Add(new RecordedRequest(request.RequestUri!.AbsolutePath, request.RequestUri.Query,
                request.Headers.Authorization?.ToString()));
            if (responseFactory is not null)
                return Task.FromResult(responseFactory(request));

            if (request.RequestUri!.AbsolutePath.EndsWith("/api/v1/query", StringComparison.Ordinal))
            {
                var query = Uri.UnescapeDataString(request.RequestUri.Query);
                var value = query.Contains("histogram_quantile", StringComparison.Ordinal) ? "0.25"
                    : query.Contains("http_response_status_code", StringComparison.Ordinal) ? "2"
                    : "10";
                return Json($"{{\"status\":\"success\",\"data\":{{\"result\":[{{\"value\":[1,\"{value}\"]}}]}}}}");
            }
            if (request.RequestUri.AbsolutePath.EndsWith("/query_range", StringComparison.Ordinal))
                return Json("{\"status\":\"success\",\"data\":{\"result\":[{\"stream\":{\"level\":\"ERROR\"},\"values\":[[\"1791800000000000000\",\"private log body must not be returned\"]]}]}}");
            return Json("{\"traces\":[{\"traceID\":\"aabbccdd\",\"startTimeUnixNano\":1791800000000000000,\"durationMs\":12.5}]}");
        }

        private static Task<HttpResponseMessage> Json(string body) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent(body, Encoding.UTF8, "application/json")
        });
    }

    private sealed record RecordedRequest(string Path, string Query, string? Authorization);
}
