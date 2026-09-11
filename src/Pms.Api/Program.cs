using System.Text;
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

// Console logging is reliable for local development and avoids Windows Event
// Log permission failures masking the original request exception.
builder.Logging.ClearProviders();
builder.Logging.AddJsonConsole();


const string FrontendCors = "FrontendCors";
builder.Services.AddControllers().AddJsonOptions(options => options.JsonSerializerOptions.ReferenceHandler = System.Text.Json.Serialization.ReferenceHandler.IgnoreCycles);
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
    .WithOrigins("http://127.0.0.1:5173", "http://localhost:5173")
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
    });
builder.Services.AddDbContext<PmsDbContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("PmsDatabase"), sql =>
        sql.EnableRetryOnFailure(5, TimeSpan.FromSeconds(5), null)));
builder.Services.AddHealthChecks().AddCheck<DatabaseHealthCheck>("database", tags: ["ready"]);
builder.Services.AddScoped<DashboardRepository>();
builder.Services.AddHttpClient("Gemini", client => client.Timeout = TimeSpan.FromSeconds(20));
builder.Services.AddScoped<IAiTaskService>(services => new GeminiTaskService(
    services.GetRequiredService<IHttpClientFactory>().CreateClient("Gemini"),
    new GeminiSettings(builder.Configuration["Gemini:ApiKey"], builder.Configuration["Gemini:Model"]),
    services.GetRequiredService<ILogger<GeminiTaskService>>()));
builder.Services.AddAuthorization();
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

app.UseCors(FrontendCors);
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
