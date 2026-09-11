using System.Data;
using Dapper;
using Microsoft.EntityFrameworkCore;
using Pms.Infrastructure.Persistence.EfCore;

namespace Pms.Infrastructure.Persistence.Dapper;

public sealed record DashboardMetrics(int MyTasks, int OverdueTasks, int CompletedTasks, int InProgressTasks, int TotalTasks);

public sealed class DashboardRepository(PmsDbContext db)
{
    public async Task<DashboardMetrics> GetMetrics(Guid userId, Guid? projectId, CancellationToken ct)
    {
        var connection = db.Database.GetDbConnection();
        if (connection.State != ConnectionState.Open) await connection.OpenAsync(ct);
        var command = new CommandDefinition(
            "usp_GetDashboardMetrics",
            new { UserId = userId, ProjectId = projectId },
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct);
        var row = await connection.QuerySingleOrDefaultAsync<DashboardMetricsRow>(command);
        return row is null
            ? new DashboardMetrics(0, 0, 0, 0, 0)
            : new DashboardMetrics(row.MyTasks, row.OverdueTasks, row.CompletedTasks, row.InProgressTasks, row.TotalTasks);
    }

    private sealed class DashboardMetricsRow
    {
        public int MyTasks { get; init; }
        public int OverdueTasks { get; init; }
        public int CompletedTasks { get; init; }
        public int InProgressTasks { get; init; }
        public int TotalTasks { get; init; }
    }
}