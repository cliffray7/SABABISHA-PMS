using System.Text;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using HotChocolate.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Pms.Api.Auth;
using Pms.Api;
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


const string FrontendCors = "FrontendCors";
builder.Services.AddControllers().AddJsonOptions(options => options.JsonSerializerOptions.ReferenceHandler = System.Text.Json.Serialization.ReferenceHandler.IgnoreCycles);
builder.Services.AddHttpClient("Brevo", client =>
{
    client.BaseAddress = new Uri("https://api.brevo.com/");
    client.Timeout = TimeSpan.FromSeconds(15);
});
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
    .SetIsOriginAllowed(_ => true)
    .AllowAnyHeader()
    .AllowAnyMethod()));
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
    });
builder.Services.AddDbContext<PmsDbContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("PmsDatabase"), sql =>
        // Azure SQL serverless can take up to 30 seconds to resume from auto-pause.
        // Retry up to 6 times with up to 30 seconds between attempts.
        sql.EnableRetryOnFailure(6, TimeSpan.FromSeconds(30), null)
           .CommandTimeout(60)));
builder.Services.AddHealthChecks().AddCheck<DatabaseHealthCheck>("database", tags: ["ready"]);
builder.Services.AddScoped<DashboardRepository>();
builder.Services.AddHttpClient("Gemini", client => client.Timeout = TimeSpan.FromSeconds(20));
builder.Services.AddHostedService<KeepAliveService>();
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
            Console.WriteLine("--- SuperAdmin Policy Check ---");
            Console.WriteLine($"Configured Admin IDs: [{string.Join(", ", adminUserIds)}]");

            var userIdClaim = context.User.FindFirst(JwtRegisteredClaimNames.Sub)?.Value ?? context.User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            Console.WriteLine($"User ID Claim from Token: {userIdClaim ?? "NULL"}");

            if (userIdClaim == null || !Guid.TryParse(userIdClaim, out var userId))
            {
                Console.WriteLine("Result: Failure (Could not parse User ID from token).");
                Console.WriteLine("---------------------------------");
                return false;
            }

            foreach (var adminIdStr in adminUserIds)
            {
                if (Guid.TryParse(adminIdStr, out var adminId) && userId == adminId)
                {
                    Console.WriteLine($"Result: Success (User ID {userId} matched Admin ID {adminId}).");
                    Console.WriteLine("---------------------------------");
                    return true;
                }
            }

            Console.WriteLine($"Result: Failure (User ID {userId} not found in configured Admin IDs).");
            Console.WriteLine("---------------------------------");
            return false;
        }));
});

builder.Services
    .AddGraphQLServer()
    .AddAuthorizationCore()
    .AddQueryType<PmsQuery>();

var app = builder.Build();

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
        app.Logger.LogError(ex, "Unhandled exception for {Method} {Path}", context.Request.Method, context.Request.Path);
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
    var correlationId = context.Request.Headers["X-Correlation-ID"].FirstOrDefault() ?? Guid.NewGuid().ToString("N");
    context.Response.Headers["X-Correlation-ID"] = correlationId;
    using (app.Logger.BeginScope(new Dictionary<string, object> { ["CorrelationId"] = correlationId }))
    {
        await next();
        app.Logger.LogInformation("HTTP {Method} {Path} completed with {StatusCode}", context.Request.Method, context.Request.Path, context.Response.StatusCode);
    }
});
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();
app.MapHealthChecks("/api/v1/live", new HealthCheckOptions { Predicate = _ => false });
app.MapHealthChecks("/api/v1/ready", new HealthCheckOptions { Predicate = check => check.Tags.Contains("ready") });
app.MapGraphQL("/graphql");

app.Run();
