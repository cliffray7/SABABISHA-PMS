using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using Pms.Api.Controllers.Rest.V1;

namespace Pms.IntegrationTests;

public sealed class AdminObservabilityAuthorizationTests
{
    private static readonly Guid SuperAdminId = Guid.Parse("6cbe1ce7-d603-4ca2-af1a-2e395ea41f80");
    private static readonly Guid TenantAdminId = Guid.Parse("d91f3025-2ec5-40d1-9e48-aa6f8e375e70");
    private const string Issuer = "TaskFlow.IntegrationTests";
    private const string Audience = "TaskFlow.IntegrationTests.Client";
    private const string SigningKey = "integration-test-signing-key-32-bytes-minimum";
    private static readonly string[] ProtectedRoutes =
    [
        "/api/v1/admin/system-health",
        "/api/v1/admin/observability"
    ];

    [Fact]
    public async Task AnonymousRequestsAreRejectedByTheHttpAuthorizationPipeline()
    {
        using var factory = new AdminApiFactory();
        using var client = factory.CreateClient();

        foreach (var route in ProtectedRoutes)
        {
            using var response = await client.GetAsync(route);
            Assert.Equal(System.Net.HttpStatusCode.Unauthorized, response.StatusCode);
        }
    }

    [Fact]
    public async Task AuthenticatedTenantAdminIsForbiddenByTheHttpAuthorizationPipeline()
    {
        using var factory = new AdminApiFactory();
        using var client = factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new("Bearer", CreateToken(TenantAdminId, factory.Services));

        foreach (var route in ProtectedRoutes)
        {
            using var response = await client.GetAsync(route);
            Assert.Equal(System.Net.HttpStatusCode.Forbidden, response.StatusCode);
        }
    }

    [Fact]
    public async Task ConfiguredSuperAdminCanAccessBothReadOnlyHealthRoutes()
    {
        using var factory = new AdminApiFactory();
        using var client = factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new("Bearer", CreateToken(GetConfiguredSuperAdminId(factory.Services), factory.Services));

        foreach (var route in ProtectedRoutes)
        {
            using var response = await client.GetAsync(route);
            Assert.Equal(System.Net.HttpStatusCode.OK, response.StatusCode);
        }
    }

    private static Guid GetConfiguredSuperAdminId(IServiceProvider services)
    {
        var adminIds = services.GetRequiredService<IConfiguration>()
            .GetSection("Operations:AdminUserIds").Get<string[]>();
        Assert.Contains(SuperAdminId.ToString(), adminIds ?? []);
        return SuperAdminId;
    }

    private static string CreateToken(Guid subject, IServiceProvider services)
    {
        var validation = services.GetRequiredService<IOptionsMonitor<JwtBearerOptions>>()
            .Get(JwtBearerDefaults.AuthenticationScheme).TokenValidationParameters;
        var signingKey = Assert.IsType<SymmetricSecurityKey>(validation.IssuerSigningKey);
        var issuer = Assert.IsType<string>(validation.ValidIssuer);
        var audience = Assert.IsType<string>(validation.ValidAudience);
        var credentials = new SigningCredentials(
            signingKey,
            SecurityAlgorithms.HmacSha256);
        var token = new JwtSecurityToken(
            issuer,
            audience,
            [new Claim(JwtRegisteredClaimNames.Sub, subject.ToString())],
            expires: DateTime.UtcNow.AddMinutes(5),
            signingCredentials: credentials);
        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    private sealed class AdminApiFactory : WebApplicationFactory<AdminSystemHealthController>
    {
        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            builder.UseEnvironment("Testing");
            builder.ConfigureAppConfiguration((_, configuration) =>
            {
                configuration.Sources.Clear();
                configuration.AddInMemoryCollection(new Dictionary<string, string?>
                {
                    ["Jwt:Issuer"] = Issuer,
                    ["Jwt:Audience"] = Audience,
                    ["Jwt:SigningKey"] = SigningKey,
                    ["Operations:AdminUserIds:0"] = SuperAdminId.ToString(),
                    ["ConnectionStrings:PmsDatabase"] = "Server=127.0.0.1,1;Database=unused;User Id=test;Password=test;TrustServerCertificate=True;Connect Timeout=1"
                });
            });
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<IHostedService>();
                services.RemoveAll<HealthCheckService>();
                services.AddSingleton<HealthCheckService>(new HealthyHealthCheckService());
            });
        }
    }

    private sealed class HealthyHealthCheckService : HealthCheckService
    {
        public override Task<HealthReport> CheckHealthAsync(
            Func<HealthCheckRegistration, bool>? predicate,
            CancellationToken cancellationToken = default) =>
            Task.FromResult(new HealthReport(
                new Dictionary<string, HealthReportEntry>(),
                TimeSpan.Zero));
    }
}
