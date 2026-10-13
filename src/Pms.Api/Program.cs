using System.Text;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Diagnostics;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.Routing;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using HotChocolate.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using OpenTelemetry.Exporter;
using OpenTelemetry.Metrics;
using OpenTelemetry.Logs;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using Pms.Api.Auth;
using Pms.Api;
using Pms.Api.Media;
using Pms.Api.GraphQL.Queries;
using Pms.Application.Ai;
using Pms.Infrastructure.Ai;
using Pms.Infrastructure.Persistence.EfCore;
using Pms.Infrastructure.Persistence.Dapper;

var builder = WebApplication.CreateBuilder(args);

// Railway and Render assign the public HTTP port at runtime. Respect their PORT
// value while retaining the normal ASP.NET Core configuration for local and Docker use.
if (int.TryParse(Environment.GetEnvironmentVariable("PORT"), out var port))
    builder.WebHost.UseUrls($"http://0.0.0.0:{port}");

// Console logging is reliable for local development and avoids Windows Event
// Log permission failures masking the original request exception.
builder.Logging.ClearProviders();
builder.Logging.AddJsonConsole();

var telemetryEnabled = builder.Configuration.GetValue<bool>("Observability:Otlp:Enabled");
var otlpEndpoint = builder.Configuration["Observability:Otlp:Endpoint"]
    ?? Environment.GetEnvironmentVariable("OTEL_EXPORTER_OTLP_ENDPOINT");
var configuredTraceSampleRatio = builder.Configuration.GetValue("Observability:TraceSampleRatio", 0.05);
var traceSampleRatio = double.IsFinite(configuredTraceSampleRatio)
    ? Math.Clamp(configuredTraceSampleRatio, 0d, 1d)
    : 0.05;
Uri? safeTelemetryUri = null;
if (Uri.TryCreate(otlpEndpoint, UriKind.Absolute, out var parsedTelemetryUri)
    && (parsedTelemetryUri.Scheme == Uri.UriSchemeHttps
        || (parsedTelemetryUri.Scheme == Uri.UriSchemeHttp && parsedTelemetryUri.IsLoopback)))
{
    safeTelemetryUri = parsedTelemetryUri;
}

static Uri GetOtlpSignalEndpoint(Uri baseEndpoint, string signal)
{
    var endpoint = new UriBuilder(baseEndpoint);
    var signalPath = $"/v1/{signal}";
    if (!endpoint.Path.TrimEnd('/').EndsWith(signalPath, StringComparison.OrdinalIgnoreCase))
        endpoint.Path = $"{endpoint.Path.TrimEnd('/')}{signalPath}";

    return endpoint.Uri;
}

if (telemetryEnabled && safeTelemetryUri is not null)
{
    builder.Services.AddOpenTelemetry()
        .ConfigureResource(resource => resource.AddService("Pms.Api"))
        .WithTracing(tracing => tracing
            .SetSampler(new TraceIdRatioBasedSampler(traceSampleRatio))
            .AddAspNetCoreInstrumentation()
            .AddHttpClientInstrumentation()
            .AddSource("TaskFlow.Api")
            .AddProcessor(new Pms.Api.Observability.TelemetrySanitizingActivityProcessor())
            .AddOtlpExporter(options =>
            {
                options.Endpoint = GetOtlpSignalEndpoint(safeTelemetryUri, "traces");
                options.Protocol = OtlpExportProtocol.HttpProtobuf;
                options.TimeoutMilliseconds = 5000;
                options.MaxRequestSizeBytes = 1024 * 1024;
                options.BatchExportProcessorOptions.MaxQueueSize = 512;
                options.BatchExportProcessorOptions.MaxExportBatchSize = 64;
                options.BatchExportProcessorOptions.ScheduledDelayMilliseconds = 5000;
                options.BatchExportProcessorOptions.ExporterTimeoutMilliseconds = 5000;
                var headers = builder.Configuration["Observability:Otlp:Headers"]
                    ?? Environment.GetEnvironmentVariable("OTEL_EXPORTER_OTLP_HEADERS");
                if (!string.IsNullOrWhiteSpace(headers)) options.Headers = headers;
            }))
        .WithMetrics(metrics => metrics
            .AddMeter("Microsoft.AspNetCore.Hosting", "Microsoft.AspNetCore.Server.Kestrel", "System.Net.Http", "System.Runtime")
            .AddOtlpExporter((options, readerOptions) =>
            {
                options.Endpoint = GetOtlpSignalEndpoint(safeTelemetryUri, "metrics");
                options.Protocol = OtlpExportProtocol.HttpProtobuf;
                options.TimeoutMilliseconds = 5000;
                options.MaxRequestSizeBytes = 1024 * 1024;
                readerOptions.PeriodicExportingMetricReaderOptions.ExportIntervalMilliseconds = 60000;
                var headers = builder.Configuration["Observability:Otlp:Headers"]
                    ?? Environment.GetEnvironmentVariable("OTEL_EXPORTER_OTLP_HEADERS");
                if (!string.IsNullOrWhiteSpace(headers)) options.Headers = headers;
            }))
        .WithLogging(logging =>
        {
            logging.AddProcessor(new Pms.Api.Observability.TelemetrySanitizingLogProcessor());
            logging.AddOtlpExporter((options, processorOptions) =>
            {
                options.Endpoint = GetOtlpSignalEndpoint(safeTelemetryUri, "logs");
                options.Protocol = OtlpExportProtocol.HttpProtobuf;
                options.TimeoutMilliseconds = 5000;
                options.MaxRequestSizeBytes = 1024 * 1024;
                processorOptions.BatchExportProcessorOptions.MaxQueueSize = 512;
                processorOptions.BatchExportProcessorOptions.MaxExportBatchSize = 64;
                processorOptions.BatchExportProcessorOptions.ScheduledDelayMilliseconds = 5000;
                processorOptions.BatchExportProcessorOptions.ExporterTimeoutMilliseconds = 5000;
                var headers = builder.Configuration["Observability:Otlp:Headers"]
                    ?? Environment.GetEnvironmentVariable("OTEL_EXPORTER_OTLP_HEADERS");
                if (!string.IsNullOrWhiteSpace(headers)) options.Headers = headers;
            });
        }, options =>
        {
            options.IncludeScopes = false;
            options.ParseStateValues = true;
            options.IncludeFormattedMessage = false;
    });
    builder.Logging.AddFilter<OpenTelemetryLoggerProvider>(null, LogLevel.Warning);
}


const string FrontendCors = "FrontendCors";
builder.Services.AddControllers().AddJsonOptions(options => options.JsonSerializerOptions.ReferenceHandler = System.Text.Json.Serialization.ReferenceHandler.IgnoreCycles);
builder.Services.AddSignalR();
builder.Services.AddScoped<Pms.Api.Realtime.RealtimePublisher>();
builder.Services.AddHttpClient("Brevo", client =>
{
    client.BaseAddress = new Uri("https://api.brevo.com/");
    client.Timeout = TimeSpan.FromSeconds(15);
});
builder.Services.AddHttpClient<ICloudinaryStorage, CloudinaryStorage>(client =>
    client.Timeout = TimeSpan.FromSeconds(60));
builder.Services.AddHttpClient("GrafanaObservability", client =>
    client.Timeout = TimeSpan.FromSeconds(8));
builder.Services.AddScoped<Pms.Api.Observability.GrafanaObservabilityService>();
builder.Services.AddSingleton<AppMail>();
builder.Services.AddRateLimiter(options => options.AddPolicy("auth", context =>
    System.Threading.RateLimiting.RateLimitPartition.GetSlidingWindowLimiter(
        context.Connection.RemoteIpAddress?.ToString() ?? "local",
        _ => new System.Threading.RateLimiting.SlidingWindowRateLimiterOptions
        {
            PermitLimit = 30,
            Window = TimeSpan.FromMinutes(1),
            SegmentsPerWindow = 6,
            QueueLimit = 0
        })));
builder.Services.AddCors(options => options.AddPolicy(FrontendCors, policy => policy
    .SetIsOriginAllowed(origin => builder.Environment.IsDevelopment()
        || origin == "https://taskflow-pms.vercel.app"
        || origin.EndsWith(".vercel.app", StringComparison.OrdinalIgnoreCase))
    .AllowAnyHeader()
    .AllowAnyMethod()
    .AllowCredentials()));
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
builder.Services.Configure<JwtOptions>(builder.Configuration.GetSection(JwtOptions.SectionName));
builder.Services.AddScoped<TokenService>();
builder.Services.AddScoped<IPasswordHasher<Pms.Domain.Entities.User>, PasswordHasher<Pms.Domain.Entities.User>>();
var jwt = builder.Configuration.GetSection(JwtOptions.SectionName).Get<JwtOptions>()
    ?? throw new InvalidOperationException("Jwt configuration is required.");
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true, ValidIssuer = jwt.Issuer,
            ValidateAudience = true, ValidAudience = jwt.Audience,
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwt.SigningKey)),
            ValidateLifetime = true, ClockSkew = TimeSpan.FromSeconds(30)
        };
        options.MapInboundClaims = false;
        options.Events = new JwtBearerEvents
        {
            OnMessageReceived = context =>
            {
                var token = context.Request.Query["access_token"];
                if (!string.IsNullOrEmpty(token) && context.Request.Path.StartsWithSegments("/hubs/workspace"))
                    context.Token = token;
                return Task.CompletedTask;
            }
        };
    });
builder.Services.AddDbContext<PmsDbContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("PmsDatabase"), sql =>
        // Azure SQL serverless can take up to 30 seconds to resume from auto-pause.
        // Retry up to 6 times with up to 30 seconds between attempts.
        sql.EnableRetryOnFailure(6, TimeSpan.FromSeconds(30), null)
           .CommandTimeout(60)));
builder.Services.AddHealthChecks().AddCheck<DatabaseHealthCheck>(
    "database",
    tags: ["ready"],
    timeout: TimeSpan.FromSeconds(10));
builder.Services.AddScoped<DashboardRepository>();
builder.Services.AddHttpClient("Gemini", client => client.Timeout = TimeSpan.FromSeconds(20));
builder.Services.AddHostedService<KeepAliveService>();
builder.Services.AddHostedService<DeletedContentPurger>();
builder.Services.AddScoped<IAiTaskService>(services => new GeminiTaskService(
    services.GetRequiredService<IHttpClientFactory>().CreateClient("Gemini"),
    new GeminiSettings(builder.Configuration["Gemini:ApiKey"], builder.Configuration["Gemini:Model"]),
    services.GetRequiredService<ILogger<GeminiTaskService>>()));

builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("SuperAdmin", policy =>
        policy.RequireAssertion(context =>
        {
            var adminUserIds = builder.Configuration.GetSection("Operations:AdminUserIds").Get<string[]>() ?? [];
            var userIdClaim = context.User.FindFirst(JwtRegisteredClaimNames.Sub)?.Value ?? context.User.FindFirst(ClaimTypes.NameIdentifier)?.Value;

            if (userIdClaim == null || !Guid.TryParse(userIdClaim, out var userId))
            {
                return false;
            }

            foreach (var adminIdStr in adminUserIds)
            {
                if (Guid.TryParse(adminIdStr, out var adminId) && userId == adminId)
                {
                    return true;
                }
            }

            return false;
        }));
});

builder.Services
    .AddGraphQLServer()
    .AddAuthorizationCore()
    .AddQueryType<PmsQuery>();

var app = builder.Build();

await DatabaseMigrationRunner.ApplyPendingMigrationsAsync(app.Services, app.Logger);

if (telemetryEnabled && safeTelemetryUri is null)
    app.Logger.LogWarning("OTLP telemetry export is disabled because its endpoint is missing or invalid.");

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}
else
{
    app.UseHsts();
}

// CORS must be registered first so the header is present on every response.
app.UseCors(FrontendCors);

// Inline exception handler: wraps the rest of the pipeline so any unhandled
// exception is caught AFTER CORS headers are already written by UseCors above.
app.Use(async (context, next) =>
{
    try
    {
        await next();
    }
    catch (Exception ex)
    {
        var activity = Activity.Current;
        var route = context.GetEndpoint()?.Metadata.GetMetadata<RouteEndpoint>()?.RoutePattern.RawText ?? "unmatched";
        activity?.SetStatus(ActivityStatusCode.Error);
        activity?.SetTag("exception.type", ex.GetType().FullName);
        activity?.AddEvent(new ActivityEvent("exception", tags: new ActivityTagsCollection
        {
            ["exception.type"] = ex.GetType().FullName ?? ex.GetType().Name
        }));
        var correlationId = context.Request.Headers["X-Correlation-ID"].FirstOrDefault()
            ?? activity?.TraceId.ToString();
        app.Logger.LogError("Unhandled request exception {ExceptionType} for {Method} {RouteTemplate} {CorrelationId}",
            ex.GetType().FullName, context.Request.Method, route, correlationId);
        if (!context.Response.HasStarted)
        {
            if (context.Request.Headers.TryGetValue("Origin", out var origin) && !string.IsNullOrEmpty(origin))
            {
                context.Response.Headers["Access-Control-Allow-Origin"] = origin;
                context.Response.Headers["Vary"] = "Origin";
            }
            context.Response.StatusCode = 500;
            context.Response.ContentType = "application/json";
            await context.Response.WriteAsJsonAsync(new { error = "An unexpected error occurred. Please try again." });
        }
    }
});

app.Use(async (context, next) =>
{
    context.Response.Headers["X-Content-Type-Options"] = "nosniff";
    context.Response.Headers["X-Frame-Options"] = "DENY";
    context.Response.Headers["Referrer-Policy"] = "strict-origin-when-cross-origin";
    context.Response.Headers["Permissions-Policy"] = "camera=(), geolocation=(), microphone=()";
    var correlationId = Activity.Current?.TraceId.ToString() ?? Guid.NewGuid().ToString("N");
    context.Request.Headers["X-Correlation-ID"] = correlationId;
    context.Response.Headers["X-Correlation-ID"] = correlationId;
    using (app.Logger.BeginScope(new Dictionary<string, object> { ["CorrelationId"] = correlationId }))
    {
        await next();
        var route = context.GetEndpoint()?.Metadata.GetMetadata<RouteEndpoint>()?.RoutePattern.RawText ?? "unmatched";
        app.Logger.LogInformation("HTTP request completed {Method} {RouteTemplate} {StatusCode} {CorrelationId}",
            context.Request.Method, route, context.Response.StatusCode, correlationId);
    }
});
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();
app.UseMiddleware<Pms.Api.MemberRemoval.MemberRemovalRequestLimitMiddleware>();

app.MapControllers();
app.MapHub<Pms.Api.Realtime.WorkspaceHub>("/hubs/workspace").RequireAuthorization();
app.MapHealthChecks("/api/v1/live", new HealthCheckOptions { Predicate = _ => false });
app.MapHealthChecks("/api/v1/ready", new HealthCheckOptions { Predicate = check => check.Tags.Contains("ready") });
app.MapGraphQL("/graphql");

app.Run();
