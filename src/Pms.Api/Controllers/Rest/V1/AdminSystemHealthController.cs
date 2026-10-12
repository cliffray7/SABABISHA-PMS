using Microsoft.AspNetCore.Authorization;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.Mvc;

namespace Pms.Api.Controllers.Rest.V1;

public sealed record SystemHealthComponent(
    string Id,
    string Name,
    string Status,
    string Signal,
    string Summary);

public sealed record SystemHealthResponse(
    string OverallStatus,
    DateTimeOffset CheckedAt,
    IReadOnlyList<SystemHealthComponent> Components);

[ApiController]
[Route("api/v1/admin/system-health")]
[Authorize(Policy = "SuperAdmin")]
public sealed class AdminSystemHealthController(
    HealthCheckService healthChecks,
    IConfiguration configuration) : ControllerBase
{
    [HttpGet]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<ActionResult<SystemHealthResponse>> Get(CancellationToken cancellationToken)
    {
        // This database probe is intentionally request-driven. The Super Admin
        // explicitly refreshes the page; we do not wake serverless SQL on a timer.
        var report = await healthChecks.CheckHealthAsync(
            check => check.Tags.Contains("ready"), cancellationToken);
        var databaseHealthy = report.Entries.TryGetValue("database", out var database)
            && database.Status == Microsoft.Extensions.Diagnostics.HealthChecks.HealthStatus.Healthy;

        var emailConfigured = !string.IsNullOrWhiteSpace(configuration["Brevo:ApiKey"]);
        var aiConfigured = !string.IsNullOrWhiteSpace(configuration["Gemini:ApiKey"])
            && !string.IsNullOrWhiteSpace(configuration["Gemini:Model"]);

        var components = new[]
        {
            new SystemHealthComponent(
                "api", "ASP.NET Core API", "healthy", "request",
                "The API is responding to this authenticated health request."),
            new SystemHealthComponent(
                "database", "SQL Server", databaseHealthy ? "healthy" : "unavailable", "connectivity",
                databaseHealthy ? "SQL Server accepted a connectivity check." : "SQL Server did not pass the connectivity check."),
            new SystemHealthComponent(
                "email", "Email service", emailConfigured ? "configured" : "not_configured", "configuration",
                emailConfigured ? "Brevo credentials are configured; delivery is not probed." : "Brevo credentials are not configured."),
            new SystemHealthComponent(
                "ai", "AI provider", aiConfigured ? "configured" : "not_configured", "configuration",
                aiConfigured ? "Gemini credentials and model are configured; provider availability is not probed." : "Gemini credentials or model are not configured."),
            new SystemHealthComponent(
                "realtime", "Realtime (SignalR)", "not_instrumented", "not_instrumented",
                "The hub is configured, but connection and message delivery health are not measured."),
            new SystemHealthComponent(
                "background_jobs", "Background jobs", "not_instrumented", "not_instrumented",
                "Job run history and processing delay are not currently measured.")
        };

        return Ok(new SystemHealthResponse(
            databaseHealthy ? "unknown" : "degraded",
            DateTimeOffset.UtcNow,
            components));
    }
}
