using System.Reflection;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.EntityFrameworkCore;
using Pms.Api;
using Pms.Api.Controllers.Rest.V1;
using Pms.Infrastructure.Persistence.EfCore;

namespace Pms.IntegrationTests;

public sealed class AdminSystemHealthTests
{
    [Fact]
    public void HealthEndpointRequiresSuperAdminPolicy()
    {
        var authorization = typeof(AdminSystemHealthController).GetCustomAttribute<AuthorizeAttribute>();

        Assert.Equal("SuperAdmin", authorization?.Policy);
        Assert.Null(typeof(AdminSystemHealthController).GetCustomAttribute<AllowAnonymousAttribute>());
    }

    [Fact]
    public async Task HealthyDatabaseDoesNotClaimOverallPlatformHealth()
    {
        var controller = CreateController(HealthStatus.Healthy, null);

        var result = await controller.Get(default);

        var response = Assert.IsType<SystemHealthResponse>(Assert.IsType<OkObjectResult>(result.Result).Value);
        Assert.Equal("unknown", response.OverallStatus);
        Assert.Equal("healthy", Assert.Single(response.Components, component => component.Id == "database").Status);
        Assert.Equal("configured", Assert.Single(response.Components, component => component.Id == "email").Status);
        Assert.Equal("configured", Assert.Single(response.Components, component => component.Id == "ai").Status);
        Assert.Equal("not_instrumented", Assert.Single(response.Components, component => component.Id == "realtime").Status);
        Assert.Equal("not_instrumented", Assert.Single(response.Components, component => component.Id == "background_jobs").Status);
    }

    [Fact]
    public async Task DatabaseFailureReturnsSanitizedDegradedHealth()
    {
        const string privateDiagnostic = "SQL login failed: user=private-user password=secret-value";
        var controller = CreateController(HealthStatus.Unhealthy, new InvalidOperationException(privateDiagnostic));

        var result = await controller.Get(default);

        var response = Assert.IsType<SystemHealthResponse>(Assert.IsType<OkObjectResult>(result.Result).Value);
        Assert.Equal("degraded", response.OverallStatus);
        var database = Assert.Single(response.Components, component => component.Id == "database");
        Assert.Equal("unavailable", database.Status);
        Assert.Contains("did not pass", database.Summary);
        Assert.DoesNotContain(privateDiagnostic, database.Summary);
        Assert.DoesNotContain("secret-value", string.Join(" ", response.Components.Select(component => component.Summary)));
    }

    [Fact]
    public async Task DatabaseHealthCheckConvertsConnectionFailureToUnhealthyResult()
    {
        var options = new DbContextOptionsBuilder<PmsDbContext>()
            .UseSqlServer("Server=tcp:127.0.0.1,1;Initial Catalog=HealthProbeTest;User Id=test;Password=test;Encrypt=False;TrustServerCertificate=True;Connect Timeout=1;ConnectRetryCount=0")
            .Options;
        await using var db = new PmsDbContext(options);
        var check = new DatabaseHealthCheck(db);

        var result = await check.CheckHealthAsync(new HealthCheckContext());

        Assert.Equal(HealthStatus.Unhealthy, result.Status);
        Assert.Equal("SQL Server is unavailable.", result.Description);
        Assert.Null(result.Exception);
    }

    [Fact]
    public async Task MissingProviderConfigurationIsNotReportedAsProviderHealth()
    {
        var controller = CreateController(HealthStatus.Healthy, null, configured: false);

        var result = await controller.Get(default);

        var response = Assert.IsType<SystemHealthResponse>(Assert.IsType<OkObjectResult>(result.Result).Value);
        Assert.Equal("not_configured", Assert.Single(response.Components, component => component.Id == "email").Status);
        Assert.Equal("not_configured", Assert.Single(response.Components, component => component.Id == "ai").Status);
        Assert.Equal("unknown", response.OverallStatus);
    }

    private static AdminSystemHealthController CreateController(
        HealthStatus databaseStatus,
        Exception? exception,
        bool configured = true)
    {
        var entry = new HealthReportEntry(databaseStatus, "database result", TimeSpan.Zero, exception,
            new Dictionary<string, object>(), Array.Empty<string>());
        var report = new HealthReport(new Dictionary<string, HealthReportEntry> { ["database"] = entry }, TimeSpan.Zero);
        var values = configured
            ? new Dictionary<string, string?> { ["Brevo:ApiKey"] = "configured", ["Gemini:ApiKey"] = "configured", ["Gemini:Model"] = "configured" }
            : new Dictionary<string, string?>();
        return new AdminSystemHealthController(new StubHealthCheckService(report), new ConfigurationBuilder().AddInMemoryCollection(values).Build());
    }

    private sealed class StubHealthCheckService(HealthReport report) : HealthCheckService
    {
        public override Task<HealthReport> CheckHealthAsync(
            Func<HealthCheckRegistration, bool>? predicate,
            CancellationToken cancellationToken = default) => Task.FromResult(report);
    }
}
