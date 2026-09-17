using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Pms.Infrastructure.Persistence.EfCore;
using System.Globalization;
using CsvHelper;

namespace Pms.Api.Controllers.Rest.V1;

[ApiController]
[Route("api/v1/admin")]
[Authorize(Policy = "SuperAdmin")]
public sealed class AdminController(PmsDbContext db) : ControllerBase
{
    // =====================================================
    // SUPER ADMIN DASHBOARD
    // GET /api/v1/admin/dashboard
    // =====================================================

    [HttpGet("dashboard")]
    public async Task<IActionResult> GetDashboardMetrics(
        CancellationToken cancellationToken)
    {
        var metrics = new
        {
            TotalUsers = await db.Users
                .AsNoTracking()
                .CountAsync(cancellationToken),

            TotalOrganizations = await db.Organizations
                .AsNoTracking()
                .CountAsync(cancellationToken),

            TotalProjects = await db.Projects
                .AsNoTracking()
                .CountAsync(cancellationToken),

            TotalTasks = await db.Tasks
                .AsNoTracking()
                .CountAsync(cancellationToken),

            CompletedTasks = await db.Tasks
                .AsNoTracking()
                .CountAsync(
                    t => t.Status == "DONE",
                    cancellationToken),

            ActiveProjects = await db.Projects
                .AsNoTracking()
                .CountAsync(
                    p => p.Status == "IN_PROGRESS",
                    cancellationToken)
        };

        return Ok(metrics);
    }

    // =====================================================
    // ANALYTICS
    // GET /api/v1/admin/analytics
    // GET /api/v1/admin/analytics?from=...&to=...
    // =====================================================

    [HttpGet("analytics")]
    public async Task<IActionResult> GetAnalytics(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        CancellationToken cancellationToken)
    {
        var fromDate = from ?? DateTime.UtcNow.AddDays(-30);
        var toDate = to ?? DateTime.UtcNow;

        if (fromDate > toDate)
        {
            return BadRequest(new
            {
                message = "'from' cannot be later than 'to'."
            });
        }

        var userGrowth = await db.Users
            .AsNoTracking()
            .Where(u =>
                u.CreatedAt >= fromDate &&
                u.CreatedAt <= toDate)
            .GroupBy(u => u.CreatedAt.Date)
            .Select(g => new
            {
                Date = g.Key,
                Users = g.Count()
            })
            .OrderBy(x => x.Date)
            .ToListAsync(cancellationToken);

        var projectGrowth = await db.Projects
            .AsNoTracking()
            .Where(p =>
                p.CreatedAt >= fromDate &&
                p.CreatedAt <= toDate)
            .GroupBy(p => p.CreatedAt.Date)
            .Select(g => new
            {
                Date = g.Key,
                Projects = g.Count()
            })
            .OrderBy(x => x.Date)
            .ToListAsync(cancellationToken);

        var tasksByStatus = await db.Tasks
            .AsNoTracking()
            .Where(t =>
                t.CreatedAt >= fromDate &&
                t.CreatedAt <= toDate)
            .GroupBy(t => t.Status)
            .Select(g => new
            {
                Status = g.Key,
                Count = g.Count()
            })
            .OrderBy(x => x.Status)
            .ToListAsync(cancellationToken);

        var tasksByPriority = await db.Tasks
            .AsNoTracking()
            .Where(t =>
                t.CreatedAt >= fromDate &&
                t.CreatedAt <= toDate)
            .GroupBy(t => t.Priority)
            .Select(g => new
            {
                Priority = g.Key,
                Count = g.Count()
            })
            .OrderBy(x => x.Priority)
            .ToListAsync(cancellationToken);

        return Ok(new
        {
            From = fromDate,
            To = toDate,
            UserGrowth = userGrowth,
            ProjectGrowth = projectGrowth,
            TasksByStatus = tasksByStatus,
            TasksByPriority = tasksByPriority
        });
    }

    // =====================================================
    // REPORT DOWNLOAD
    // GET /api/v1/admin/reports?format=csv
    // =====================================================

    [HttpGet("reports")]
    public async Task<IActionResult> GetReport(
        [FromQuery] string format,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(format))
        {
            return BadRequest(new
            {
                message = "Report format is required."
            });
        }

        if (!string.Equals(
                format,
                "csv",
                StringComparison.OrdinalIgnoreCase))
        {
            return BadRequest(new
            {
                message = "Invalid report format. Supported format: csv."
            });
        }

        // Do NOT export complete User entities.
        // That could expose PasswordHash and other internal fields.

        var users = await db.Users
            .AsNoTracking()
            .Select(u => new
            {
                u.Id,
                u.FirstName,
                u.LastName,
                u.Email,
                u.CreatedAt
            })
            .ToListAsync(cancellationToken);

        var organizations = await db.Organizations
            .AsNoTracking()
            .Select(o => new
            {
                o.Id,
                o.Name,
                o.CreatedAt
            })
            .ToListAsync(cancellationToken);

        var projects = await db.Projects
            .AsNoTracking()
            .Select(p => new
            {
                p.Id,
                p.OrganizationId,
                p.Name,
                p.Status,
                p.CreatedAt
            })
            .ToListAsync(cancellationToken);

        var tasks = await db.Tasks
            .AsNoTracking()
            .Select(t => new
            {
                t.Id,
                t.ProjectId,
                t.Title,
                t.Status,
                t.Priority,
                t.CreatedAt
            })
            .ToListAsync(cancellationToken);

        using var memoryStream = new MemoryStream();

        using (
            var writer = new StreamWriter(
                memoryStream,
                leaveOpen: true))
        using (
            var csv = new CsvWriter(
                writer,
                CultureInfo.InvariantCulture))
        {
            // Report metadata
            csv.WriteField("TASKFLOW SYSTEM REPORT");
            csv.NextRecord();

            csv.WriteField("Generated At");
            csv.WriteField(
                DateTime.UtcNow.ToString("O"));
            csv.NextRecord();

            csv.NextRecord();

            // USERS
            csv.WriteField("USERS");
            csv.NextRecord();

            csv.WriteRecords(users);
            csv.NextRecord();

            // ORGANIZATIONS
            csv.WriteField("ORGANIZATIONS");
            csv.NextRecord();

            csv.WriteRecords(organizations);
            csv.NextRecord();

            // PROJECTS
            csv.WriteField("PROJECTS");
            csv.NextRecord();

            csv.WriteRecords(projects);
            csv.NextRecord();

            // TASKS
            csv.WriteField("TASKS");
            csv.NextRecord();

            csv.WriteRecords(tasks);

            writer.Flush();
        }

        var bytes = memoryStream.ToArray();

        var fileName =
            $"taskflow-report-{DateTime.UtcNow:yyyy-MM-dd-HHmmss}.csv";

        return File(
            bytes,
            "text/csv; charset=utf-8",
            fileName);
    }
}