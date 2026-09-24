namespace Pms.Api;

/// <summary>
/// Pings the API's own /api/v1/live endpoint every 14 minutes to prevent
/// Render free tier from spinning down the container after 15 minutes of inactivity.
/// Only active in Production to avoid unnecessary noise during local development.
/// </summary>
public sealed class KeepAliveService(IConfiguration config, ILogger<KeepAliveService> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        // Only run in Production (Render). Skip locally.
        var baseUrl = config["RENDER_EXTERNAL_URL"] ?? config["Kestrel:Endpoints:Http:Url"];
        if (string.IsNullOrWhiteSpace(baseUrl))
        {
            // Derive from ASPNETCORE_URLS or PORT if RENDER_EXTERNAL_URL not set
            var renderUrl = config["RENDER_SERVICE_NAME"] is { } name
                ? $"https://{name}.onrender.com"
                : null;
            baseUrl = renderUrl;
        }

        if (string.IsNullOrWhiteSpace(baseUrl))
        {
            logger.LogInformation("KeepAliveService: no external URL configured, skipping.");
            return;
        }

        var pingUrl = baseUrl.TrimEnd('/') + "/api/v1/live";
        using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };

        logger.LogInformation("KeepAliveService: will ping {Url} every 14 minutes.", pingUrl);

        // Initial delay — wait 2 minutes after startup before first ping.
        await Task.Delay(TimeSpan.FromMinutes(2), stoppingToken);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                var response = await http.GetAsync(pingUrl, stoppingToken);
                logger.LogInformation("KeepAliveService: ping {Status}", (int)response.StatusCode);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                logger.LogWarning("KeepAliveService: ping failed — {Message}", ex.Message);
            }

            await Task.Delay(TimeSpan.FromMinutes(14), stoppingToken);
        }
    }
}
