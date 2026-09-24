using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Pms.Infrastructure.Persistence.EfCore;
using System.Globalization;
using CsvHelper;

namespace Pms.Api.Controllers.Rest.V1;

/// <summary>Request body for admin-created user accounts.</summary>
public sealed record AdminCreateUserRequest(
    string FirstName,
    string LastName,
    string Email,
    string Password,
    string? Timezone);

[ApiController]
[Route("api/v1/admin")]
[Authorize(Policy = "SuperAdmin")]
public sealed class AdminController(PmsDbContext db) : ControllerBase
{
    // =====================================================
    // CREATE USER
    // POST /api/v1/admin/users
    // =====================================================

    [HttpPost("users")]
    public async Task<IActionResult> CreateUser(
        [FromBody] AdminCreateUserRequest request,
        [FromServices] IPasswordHasher<Pms.Domain.Entities.User> passwordHasher,
        CancellationToken cancellationToken)
    {
        var email = request.Email.Trim().ToLowerInvariant();

        if (string.IsNullOrWhiteSpace(request.FirstName) || string.IsNullOrWhiteSpace(request.LastName))
            return BadRequest(new { message = "First and last names are required." });

        if (string.IsNullOrWhiteSpace(request.Password) || request.Password.Length < 8)
            return BadRequest(new { message = "Password must be at least 8 characters." });

        if (await db.Users.AnyAsync(u => u.Email == email, cancellationToken))
            return Conflict(new { message = "An account with that email address already exists." });

        var user = new Pms.Domain.Entities.User
        {
            Id           = Guid.NewGuid(),
            FirstName    = request.FirstName.Trim(),
            LastName     = request.LastName.Trim(),
            Email        = email,
            PasswordHash = string.Empty,
            Status       = "active",
            Timezone     = request.Timezone?.Trim() ?? "UTC",
        };

        user.PasswordHash = passwordHasher.HashPassword(user, request.Password);
        db.Users.Add(user);
        await db.SaveChangesAsync(cancellationToken);

        return CreatedAtAction(nameof(GetUsers), new { },
            new { user.Id, user.FirstName, user.LastName, user.Email, user.Status, user.CreatedAt });
    }

    // =====================================================
    // SUSPEND / DELETE USER
    // DELETE /api/v1/admin/users/{id}            → suspend (soft)
    // DELETE /api/v1/admin/users/{id}?permanent=true → hard delete
    // =====================================================

    [HttpDelete("users/{id:guid}")]
    public async Task<IActionResult> DeleteUser(
        Guid id,
        [FromQuery] bool permanent,
        CancellationToken cancellationToken)
    {
        var user = await db.Users.FindAsync([id], cancellationToken);
        if (user is null) return NotFound(new { message = "User not found." });

        // Prevent the super admin from removing themselves.
        var callerId = User.FindFirst(System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Sub)?.Value;
        if (Guid.TryParse(callerId, out var callerGuid) && callerGuid == id)
            return BadRequest(new { message = "You cannot remove your own account." });

        if (permanent)
        {
            db.Users.Remove(user);
            await db.SaveChangesAsync(cancellationToken);
            return NoContent();
        }

        // Soft suspend — preserves all tasks, comments, and org memberships.
        user.Status    = "suspended";
        user.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(cancellationToken);
        return Ok(new { user.Id, user.Status });
    }

    // =====================================================
    // LIST USERS
    // GET /api/v1/admin/users
    // =====================================================

    [HttpGet("users")]
    public async Task<IActionResult> GetUsers(CancellationToken cancellationToken) => Ok(await db.Users
        .AsNoTracking()
        .OrderByDescending(user => user.CreatedAt)
        .Select(user => new
        {
            user.Id, user.FirstName, user.LastName, user.Email, user.Status, user.CreatedAt,
            OrganizationCount = db.OrganizationMembers.Count(member => member.UserId == user.Id && member.Status == "active")
        }).ToListAsync(cancellationToken));

    [HttpGet("organizations")]
    public async Task<IActionResult> GetOrganizations(CancellationToken cancellationToken) => Ok(await db.Organizations
        .AsNoTracking()
        .OrderByDescending(organization => organization.CreatedAt)
        .Select(organization => new
        {
            organization.Id, organization.Name, organization.Slug, organization.CreatedAt,
            Owner = db.OrganizationMembers.Where(member => member.OrganizationId == organization.Id && member.Role == "OWNER")
                .Join(db.Users, member => member.UserId, user => user.Id, (_, user) => user.FirstName + " " + user.LastName).FirstOrDefault(),
            MemberCount = db.OrganizationMembers.Count(member => member.OrganizationId == organization.Id && member.Status == "active"),
            ProjectCount = db.Projects.Count(project => project.OrganizationId == organization.Id)
        }).ToListAsync(cancellationToken));

    [HttpGet("projects")]
    public async Task<IActionResult> GetProjects(CancellationToken cancellationToken) => Ok(await db.Projects
        .AsNoTracking()
        .OrderByDescending(project => project.CreatedAt)
        .Select(project => new
        {
            project.Id, project.Name, project.Status, project.CreatedAt, project.DueDate, project.ArchivedAt,
            OrganizationName = db.Organizations.Where(organization => organization.Id == project.OrganizationId).Select(organization => organization.Name).FirstOrDefault(),
            TaskCount = db.Tasks.Count(task => task.ProjectId == project.Id && task.ParentTaskId == null && task.DeletedAt == null)
        }).ToListAsync(cancellationToken));
    
    // SUPER ADMIN DASHBOARD
    // GET /api/v1/admin/dashboard


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
                .CountAsync(t => t.ParentTaskId == null && t.DeletedAt == null, cancellationToken),

            CompletedTasks = await db.Tasks
                .AsNoTracking()
                .CountAsync(
                    t => t.Status == "DONE" && t.ParentTaskId == null && t.DeletedAt == null,
                    cancellationToken),

            ActiveProjects = await db.Projects
                .AsNoTracking()
                .CountAsync(
                    p => p.Status == "ACTIVE" && p.ArchivedAt == null,
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
