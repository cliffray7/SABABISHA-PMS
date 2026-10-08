using Microsoft.Extensions.Logging;

namespace Pms.Api.Progress;

public sealed record ProjectProgressTask(string Status, DateTime? DueDate, Guid? ParentTaskId = null,
    DateTime? DeletedAt = null);

public sealed record ProjectProgressCalculation(
    bool HasTasks,
    int TotalEligibleTasks,
    int CompletedTasks,
    int? ProgressPercent,
    int OutstandingTaskCount,
    int OverdueTaskCount,
    string TimezoneIdUsed);

/// <summary>Shared task eligibility, completion, and calendar-based overdue rules for project progress.</summary>
public static class ProjectProgressCalculator
{
    public static ProjectProgressCalculation Calculate(
        IEnumerable<ProjectProgressTask> source,
        string? configuredTimezone,
        DateTime utcNow,
        Guid organizationId,
        ILogger? logger = null)
    {
        var tasks = EligibleTasks(source).ToArray();
        var completed = tasks.Count(task => IsDone(task.Status));
        var outstanding = tasks.Where(task => !IsDone(task.Status)).ToArray();
        var (timezone, timezoneId) = ResolveTimezone(configuredTimezone, organizationId, logger);
        var localToday = TimeZoneInfo.ConvertTimeFromUtc(DateTime.SpecifyKind(utcNow, DateTimeKind.Utc), timezone).Date;
        var overdue = outstanding.Count(task => task.DueDate.HasValue && task.DueDate.Value.Date < localToday);
        var percent = tasks.Length == 0
            ? null
            : (int?)Math.Round(completed * 100d / tasks.Length, MidpointRounding.AwayFromZero);

        return new ProjectProgressCalculation(tasks.Length > 0, tasks.Length, completed, percent,
            outstanding.Length, overdue, timezoneId);
    }

    /// <summary>Calculates the shared total/done/rounded progress tuple used by reports.</summary>
    public static (int Total, int Completed, int? Percent) CalculateCompletion(IEnumerable<ProjectProgressTask> source)
    {
        var tasks = EligibleTasks(source).ToArray();
        var completed = tasks.Count(task => IsDone(task.Status));
        return (tasks.Length, completed, tasks.Length == 0
            ? null
            : (int?)Math.Round(completed * 100d / tasks.Length, MidpointRounding.AwayFromZero));
    }

    private static IEnumerable<ProjectProgressTask> EligibleTasks(IEnumerable<ProjectProgressTask> tasks) =>
        tasks.Where(task => task.ParentTaskId is null && task.DeletedAt is null);

    private static bool IsDone(string status) => string.Equals(status, "DONE", StringComparison.OrdinalIgnoreCase);

    private static (TimeZoneInfo Timezone, string Id) ResolveTimezone(string? configuredTimezone, Guid organizationId,
        ILogger? logger)
    {
        if (!string.IsNullOrWhiteSpace(configuredTimezone))
        {
            try
            {
                var timezone = TimeZoneInfo.FindSystemTimeZoneById(configuredTimezone);
                return (timezone, timezone.Id);
            }
            catch (TimeZoneNotFoundException) { }
            catch (InvalidTimeZoneException) { }
            catch (ArgumentException) { }
        }

        logger?.LogWarning("Organization {OrganizationId} has a missing or invalid timezone; project progress uses UTC.",
            organizationId);
        return (TimeZoneInfo.Utc, "UTC");
    }
}
