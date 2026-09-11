using Microsoft.Extensions.Diagnostics.HealthChecks;
using Pms.Infrastructure.Persistence.EfCore;

namespace Pms.Api;

public sealed class DatabaseHealthCheck(PmsDbContext db) : IHealthCheck
{
    public async Task<HealthCheckResult> CheckHealthAsync(HealthCheckContext context, CancellationToken cancellationToken = default)
    {
        try
        {
            return await db.Database.CanConnectAsync(cancellationToken)
                ? HealthCheckResult.Healthy("SQL Server is reachable.")
                : HealthCheckResult.Unhealthy("SQL Server is unavailable.");
        }
        catch (Exception exception)
        {
            return HealthCheckResult.Unhealthy("SQL Server is unavailable.", exception);
        }
    }
}
