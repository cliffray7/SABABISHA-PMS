using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Pms.Infrastructure.Persistence.EfCore;
using System.Security.Claims;
using System.Text;
using System.Security.Cryptography;
using Microsoft.Data.SqlClient;
using Pms.Api.Reports;

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
        var createStrategy = db.Database.CreateExecutionStrategy();
        await createStrategy.ExecuteAsync(async () =>
        {
            db.ChangeTracker.Clear();
            await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);
            db.Users.Add(user);
            await db.SaveChangesAsync(cancellationToken);
            await AddAuditEventAsync("user.create", "user", user.Id, $"{user.FirstName} {user.LastName}", cancellationToken);
            await db.SaveChangesAsync(cancellationToken);
            await transaction.CommitAsync(cancellationToken);
        });

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
        if (permanent)
        {
            var user = await db.Users.FindAsync([id], cancellationToken);
            if (user is null) return NotFound(new { message = "User not found." });

            // Prevent the super admin from removing themselves.
            var callerId = User.FindFirst(System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Sub)?.Value;
            if (Guid.TryParse(callerId, out var callerGuid) && callerGuid == id)
                return BadRequest(new { message = "You cannot remove your own account." });

            var deleteStrategy = db.Database.CreateExecutionStrategy();
            try
            {
                await deleteStrategy.ExecuteAsync(async () =>
                {
                    db.ChangeTracker.Clear();
                    await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);
                    var currentUser = await db.Users.FindAsync([id], cancellationToken);
                    if (currentUser is null) return;

                    // Credential artifacts may be discarded; workspace records must not be cascade-deleted here.
                    await db.LoginOtpCodes.Where(code => code.UserId == id).ExecuteDeleteAsync(cancellationToken);
                    await db.RefreshTokens.Where(token => token.UserId == id).ExecuteDeleteAsync(cancellationToken);
                    await db.PasswordResetTokens.Where(token => token.UserId == id).ExecuteDeleteAsync(cancellationToken);

                    db.Users.Remove(currentUser);
                    await AddAuditEventAsync("user.delete.permanent", "user", currentUser.Id, $"{currentUser.FirstName} {currentUser.LastName}", cancellationToken);
                    await db.SaveChangesAsync(cancellationToken);
                    await transaction.CommitAsync(cancellationToken);
                });
            }
            catch (DbUpdateException exception) when (HasForeignKeyConflict(exception))
            {
                return Conflict(new
                {
                    code = "USER_HAS_LINKED_DATA",
                    message = "This account is still linked to workspace or project records. No data was deleted; suspend the account to block access while preserving its records."
                });
            }
            return NoContent();
        }

        // Soft suspension preserves workspace data and atomically blocks new authentication.
        var strategy = db.Database.CreateExecutionStrategy();
        var result = await strategy.ExecuteAsync(async () =>
        {
            db.ChangeTracker.Clear();
            await using var transaction = await db.Database.BeginTransactionAsync(System.Data.IsolationLevel.Serializable, cancellationToken);

            var user = await db.Users.SingleOrDefaultAsync(candidate => candidate.Id == id, cancellationToken);
            if (user is null)
            {
                await transaction.RollbackAsync(cancellationToken);
                return (Found: false, Id: id, Status: (string?)null);
            }

            // Prevent the super admin from removing themselves.
            var callerId = User.FindFirst(System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Sub)?.Value;
            if (Guid.TryParse(callerId, out var callerGuid) && callerGuid == id)
            {
                await transaction.RollbackAsync(cancellationToken);
                return (Found: true, Id: user.Id, Status: "self");
            }

            var now = DateTime.UtcNow;
            if (!string.Equals(user.Status, "suspended", StringComparison.OrdinalIgnoreCase))
            {
                user.Status = "suspended";
                user.UpdatedAt = now;
            }

            await db.RefreshTokens
                .Where(token => token.UserId == id && token.RevokedAt == null)
                .ExecuteUpdateAsync(update => update.SetProperty(token => token.RevokedAt, now), cancellationToken);

            await db.LoginOtpCodes
                .Where(code => code.UserId == id && code.UsedAt == null)
                .ExecuteUpdateAsync(update => update.SetProperty(code => code.UsedAt, now), cancellationToken);

            await AddAuditEventAsync("user.suspend", "user", user.Id, $"{user.FirstName} {user.LastName}", cancellationToken);
            await db.SaveChangesAsync(cancellationToken);
            await transaction.CommitAsync(cancellationToken);
            return (Found: true, Id: user.Id, Status: user.Status);
        });

        if (!result.Found) return NotFound(new { message = "User not found." });
        if (result.Status == "self") return BadRequest(new { message = "You cannot remove your own account." });
        return Ok(new { result.Id, Status = result.Status });
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

    [HttpGet("audit-events")]
    public async Task<IActionResult> GetAuditEvents(
        [FromQuery] DateTimeOffset? from,
        [FromQuery] DateTimeOffset? to,
        [FromQuery] Guid? actorId,
        [FromQuery] string? action,
        [FromQuery] string? targetType,
        [FromQuery] Guid? targetId,
        [FromQuery] string? outcome,
        [FromQuery] string? cursor,
        [FromQuery] int? pageSize,
        CancellationToken cancellationToken)
    {
        var now = DateTimeOffset.UtcNow;
        if ((from is null) != (to is null) || (from is not null && to is not null && from >= to))
            return BadRequest(new { code = "INVALID_DATE_RANGE", message = "Provide both from and to, with from earlier than to." });
        if (from > now || to > now)
            return BadRequest(new { code = "INVALID_DATE_RANGE", message = "Audit date ranges cannot be in the future." });
        if (from is not null && to is not null && to.Value - from.Value > TimeSpan.FromDays(366))
            return BadRequest(new { code = "INVALID_DATE_RANGE", message = "The maximum audit date range is 366 days." });
        if (pageSize is < 1 or > 100)
            return BadRequest(new { code = "INVALID_PAGE_SIZE", message = "pageSize must be between 1 and 100." });
        if (action?.Length > 80 || targetType?.Length > 80)
            return BadRequest(new { code = "INVALID_FILTER", message = "Action and targetType filters are too long." });
        if (cursor?.Length > 1024)
            return BadRequest(new { code = "INVALID_CURSOR", message = "The cursor is invalid or does not match these filters." });

        action = string.IsNullOrWhiteSpace(action) ? null : action.Trim().ToLowerInvariant();
        targetType = string.IsNullOrWhiteSpace(targetType) ? null : targetType.Trim().ToLowerInvariant();
        outcome = string.IsNullOrWhiteSpace(outcome) ? null : outcome.Trim().ToLowerInvariant();
        if (outcome is not null && outcome is not ("succeeded" or "failed" or "denied"))
            return BadRequest(new { code = "INVALID_OUTCOME", message = "outcome must be succeeded, failed, or denied." });

        var start = from ?? now.AddDays(-30);
        var end = to ?? now;
        var filtersKey = AuditFiltersKey(from, to, actorId, action, targetType, targetId, outcome);
        (DateTimeOffset OccurredAt, Guid Id)? position = null;
        if (!string.IsNullOrWhiteSpace(cursor))
        {
            try
            {
                var decoded = Encoding.UTF8.GetString(Convert.FromBase64String(cursor.Replace('-', '+').Replace('_', '/') + new string('=', (4 - cursor.Length % 4) % 4)));
                var parts = decoded.Split('|');
                if (parts.Length != 3 || parts[2] != filtersKey || !long.TryParse(parts[0], out var ticks) || !Guid.TryParseExact(parts[1], "N", out var eventId))
                    throw new FormatException();
                position = (new DateTimeOffset(ticks, TimeSpan.Zero), eventId);
            }
            catch (Exception exception) when (exception is FormatException or ArgumentOutOfRangeException)
            {
                return BadRequest(new { code = "INVALID_CURSOR", message = "The cursor is invalid or does not match these filters." });
            }
        }

        var query = db.AdminAuditEvents.AsNoTracking()
            .Where(item => item.OccurredAt >= start && item.OccurredAt < end);
        if (actorId is not null) query = query.Where(item => item.ActorId == actorId.Value);
        if (action is not null) query = query.Where(item => item.Action == action);
        if (targetType is not null) query = query.Where(item => item.TargetType == targetType);
        if (targetId is not null) query = query.Where(item => item.TargetId == targetId.Value);
        if (outcome is not null) query = query.Where(item => item.Outcome == outcome);
        if (position is not null)
            query = query.Where(item => item.OccurredAt < position.Value.OccurredAt ||
                (item.OccurredAt == position.Value.OccurredAt && item.Id.CompareTo(position.Value.Id) < 0));

        var size = pageSize ?? 50;
        var page = await query.OrderByDescending(item => item.OccurredAt).ThenByDescending(item => item.Id)
            .Take(size + 1).ToListAsync(cancellationToken);
        var hasMore = page.Count > size;
        if (hasMore) page.RemoveAt(size);
        var nextCursor = hasMore && page.Count > 0
            ? Convert.ToBase64String(Encoding.UTF8.GetBytes($"{page[^1].OccurredAt.UtcTicks}|{page[^1].Id:N}|{filtersKey}"))
                .TrimEnd('=').Replace('+', '-').Replace('/', '_')
            : null;

        return Ok(new
        {
            items = page.Select(item => new
            {
                eventId = item.Id,
                occurredAt = item.OccurredAt,
                actor = new { id = item.ActorId, displayName = item.ActorDisplayName },
                action = item.Action,
                target = new { type = item.TargetType, id = item.TargetId, displayName = item.TargetDisplayName },
                outcome = item.Outcome,
                reason = item.Reason,
                correlationId = item.CorrelationId
            }),
            nextCursor
        });
    }

    [HttpGet("activity-events")]
    public async Task<IActionResult> GetActivityEvents(
        [FromQuery] Guid? organizationId,
        [FromQuery] string? category,
        [FromQuery] string? search,
        [FromQuery] DateTimeOffset? from,
        [FromQuery] DateTimeOffset? to,
        [FromQuery] string? cursor,
        [FromQuery] int pageSize = 50,
        CancellationToken cancellationToken = default)
    {
        var now = DateTimeOffset.UtcNow;
        if (from is not null && to is not null && from >= to)
            return BadRequest(new { code = "INVALID_DATE_RANGE", message = "The start date must be earlier than the end date." });
        if (from > now || to > now || (from is not null && to is not null && to.Value - from.Value > TimeSpan.FromDays(366)))
            return BadRequest(new { code = "INVALID_DATE_RANGE", message = "Activity date range must be within the last 366 days and cannot be in the future." });
        if (pageSize is < 1 or > 100 || category?.Length > 40 || search?.Length > 100 || cursor?.Length > 1024)
            return BadRequest(new { code = "INVALID_FILTER", message = "An activity filter is invalid or too long." });

        category = string.IsNullOrWhiteSpace(category) ? null : category.Trim();
        search = string.IsNullOrWhiteSpace(search) ? null : search.Trim();
        Guid? idTerm = search is not null && Guid.TryParse(search, out var parsedId) ? parsedId : null;
        var query = from activity in db.ActivityEvents.AsNoTracking()
                    join organizationRow in db.Organizations.AsNoTracking() on activity.OrganizationId equals (Guid?)organizationRow.Id into organizationRows
                    from organization in organizationRows.DefaultIfEmpty()
                    join projectRow in db.Projects.AsNoTracking() on activity.ProjectId equals (Guid?)projectRow.Id into projectRows
                    from project in projectRows.DefaultIfEmpty()
                    select new { Event = activity, OrganizationName = organization == null ? "Platform" : organization.Name, ProjectName = project == null ? null : project.Name };
        if (organizationId is not null) query = query.Where(item => item.Event.OrganizationId == organizationId.Value);
        if (category is not null) query = query.Where(item => item.Event.Category == category);
        if (search is not null)
            query = query.Where(item => item.Event.ActorName.Contains(search) || item.Event.EntityName.Contains(search)
                || item.Event.EntityType.Contains(search) || item.Event.Action.Contains(search)
                || item.Event.Status.Contains(search) || item.Event.Description.Contains(search)
                || item.Event.CorrelationId.Contains(search) || item.OrganizationName.Contains(search)
                || (item.ProjectName != null && item.ProjectName.Contains(search))
                || (idTerm != null && (item.Event.Id == idTerm.Value || item.Event.ActorUserId == idTerm.Value
                    || item.Event.EntityId == idTerm.Value || item.Event.OrganizationId == idTerm.Value
                    || item.Event.ProjectId == idTerm.Value)));
        if (from is not null) query = query.Where(item => item.Event.CreatedAtUtc >= from.Value.UtcDateTime);
        if (to is not null) query = query.Where(item => item.Event.CreatedAtUtc < to.Value.UtcDateTime);

        (DateTime CreatedAt, Guid Id)? position = null;
        if (!string.IsNullOrWhiteSpace(cursor))
        {
            try
            {
                var parts = Encoding.UTF8.GetString(Convert.FromBase64String(cursor)).Split('|');
                if (parts.Length != 2 || !long.TryParse(parts[0], out var ticks) || !Guid.TryParseExact(parts[1], "N", out var id)) throw new FormatException();
                position = (new DateTime(ticks, DateTimeKind.Utc), id);
            }
            catch (Exception exception) when (exception is FormatException or ArgumentOutOfRangeException)
            {
                return BadRequest(new { code = "INVALID_CURSOR", message = "The activity cursor is invalid." });
            }
        }
        if (position is not null)
            query = query.Where(item => item.Event.CreatedAtUtc < position.Value.CreatedAt
                || (item.Event.CreatedAtUtc == position.Value.CreatedAt && item.Event.Id.CompareTo(position.Value.Id) < 0));

        var page = await query.OrderByDescending(item => item.Event.CreatedAtUtc).ThenByDescending(item => item.Event.Id)
            .Take(pageSize + 1).ToListAsync(cancellationToken);
        var hasMore = page.Count > pageSize;
        if (hasMore) page.RemoveAt(pageSize);
        var nextCursor = hasMore && page.Count > 0
            ? Convert.ToBase64String(Encoding.UTF8.GetBytes($"{page[^1].Event.CreatedAtUtc.Ticks}|{page[^1].Event.Id:N}"))
            : null;

        return Ok(new
        {
            items = page.Select(item => new
            {
                eventId = item.Event.Id, item.Event.OrganizationId, organizationName = item.OrganizationName,
                item.Event.ProjectId, projectName = item.ProjectName, actorUserId = item.Event.ActorUserId, actorName = item.Event.ActorName,
                item.Event.Category, item.Event.Action, item.Event.EntityType, item.Event.EntityId, item.Event.EntityName,
                item.Event.Description, item.Event.Status, item.Event.CorrelationId, createdAt = item.Event.CreatedAtUtc
            }),
            nextCursor
        });
    }

    private async Task AddAuditEventAsync(string action, string targetType, Guid targetId, string targetDisplayName, CancellationToken cancellationToken)
    {
        var actorIdValue = User.FindFirst(System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Sub)?.Value
            ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        if (!Guid.TryParse(actorIdValue, out var actorId))
            throw new InvalidOperationException("An authenticated administrator ID is required for audit events.");

        var actorDisplayName = await db.Users.AsNoTracking()
            .Where(user => user.Id == actorId)
            .Select(user => user.FirstName + " " + user.LastName)
            .SingleOrDefaultAsync(cancellationToken) ?? "Administrator";
        var correlationId = Request.Headers["X-Correlation-ID"].FirstOrDefault();
        if (string.IsNullOrWhiteSpace(correlationId) || correlationId.Length > 128)
            correlationId = HttpContext.TraceIdentifier;

        db.AdminAuditEvents.Add(new Pms.Domain.Entities.AdminAuditEvent
        {
            Id = Guid.NewGuid(),
            ActorId = actorId,
            ActorDisplayName = actorDisplayName,
            Action = action,
            TargetType = targetType,
            TargetId = targetId,
            TargetDisplayName = targetDisplayName,
            Outcome = "succeeded",
            CorrelationId = correlationId,
            OccurredAt = DateTimeOffset.UtcNow
        });
    }

    private static string AuditFiltersKey(DateTimeOffset? from, DateTimeOffset? to, Guid? actorId, string? action, string? targetType, Guid? targetId, string? outcome)
    {
        var normalized = $"{from?.UtcTicks}|{to?.UtcTicks}|{actorId}|{action}|{targetType}|{targetId}|{outcome}";
        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(normalized)));
    }

    private static bool HasForeignKeyConflict(Exception exception)
    {
        for (Exception? current = exception; current is not null; current = current.InnerException)
            if (current is SqlException { Number: 547 }) return true;
        return false;
    }

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
            ProjectCount = db.Projects.Count(project => project.OrganizationId == organization.Id && project.DeletedAt == null)
        }).ToListAsync(cancellationToken));

    [HttpGet("projects")]
    public async Task<IActionResult> GetProjects(CancellationToken cancellationToken) => Ok(await db.Projects
        .AsNoTracking()
        .Where(project => project.DeletedAt == null)
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
                .CountAsync(project => project.DeletedAt == null, cancellationToken),

            TotalTasks = await db.Tasks
                .AsNoTracking()
                .CountAsync(task => task.ParentTaskId == null && task.DeletedAt == null
                    && db.Projects.Any(project => project.Id == task.ProjectId && project.DeletedAt == null), cancellationToken),

            CompletedTasks = await db.Tasks
                .AsNoTracking()
                .CountAsync(
                    task => task.Status == "DONE" && task.ParentTaskId == null && task.DeletedAt == null
                        && db.Projects.Any(project => project.Id == task.ProjectId && project.DeletedAt == null),
                    cancellationToken),

            ActiveProjects = await db.Projects
                .AsNoTracking()
                .CountAsync(
                    project => project.Status == "ACTIVE" && project.ArchivedAt == null && project.DeletedAt == null,
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
            .Where(p => p.DeletedAt == null &&
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
            .Where(t => t.DeletedAt == null &&
                db.Projects.Any(project => project.Id == t.ProjectId && project.DeletedAt == null) &&
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
            .Where(t => t.DeletedAt == null &&
                db.Projects.Any(project => project.Id == t.ProjectId && project.DeletedAt == null) &&
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
    // GET /api/v1/admin/reports?format=csv|xlsx|pdf
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

        var normalizedFormat = format.Trim().ToLowerInvariant();
        if (normalizedFormat is not ("csv" or "xlsx" or "pdf"))
        {
            return BadRequest(new
            {
                message = "Invalid report format. Supported formats: csv, xlsx, pdf."
            });
        }

        // Do NOT export complete User entities.
        // That could expose PasswordHash and other internal fields.

        var users = await db.Users
            .AsNoTracking()
            .Select(u => new PlatformUserReport(
                u.Id,
                u.FirstName,
                u.LastName,
                u.Email,
                u.CreatedAt))
            .ToListAsync(cancellationToken);

        var organizations = await db.Organizations
            .AsNoTracking()
            .Select(o => new PlatformOrganizationReport(o.Id, o.Name, o.CreatedAt))
            .ToListAsync(cancellationToken);

        var projects = await db.Projects
            .AsNoTracking()
            .Where(project => project.DeletedAt == null)
            .Select(p => new PlatformProjectReport(p.Id, p.OrganizationId, p.Name, p.Status, p.CreatedAt,
                p.ArchivedAt != null))
            .ToListAsync(cancellationToken);

        var tasks = await db.Tasks
            .AsNoTracking()
            .Where(task => task.DeletedAt == null
                && db.Projects.Any(project => project.Id == task.ProjectId && project.DeletedAt == null))
            .Select(t => new PlatformTaskReport(t.Id, t.ProjectId, t.Title, t.Status, t.Priority, t.DueDate,
                t.CreatedAt, t.ParentTaskId, t.DeletedAt))
            .ToListAsync(cancellationToken);
        var generatedAt = DateTime.UtcNow;
        var reportId = $"RPT-{generatedAt:yyyy-MM}-{Guid.NewGuid().ToString("N")[..8].ToUpperInvariant()}";
        var report = new PlatformReportData(reportId, generatedAt, users, organizations, projects, tasks);
        var bytes = normalizedFormat switch
        {
            "xlsx" => PlatformReportExport.Xlsx(report),
            "pdf" => PlatformReportExport.Pdf(report),
            _ => PlatformReportExport.Csv(report)
        };
        var contentType = normalizedFormat switch
        {
            "xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "pdf" => "application/pdf",
            _ => "text/csv; charset=utf-8"
        };
        var filename = $"taskflow-platform-report-{generatedAt:yyyy-MM-dd-HHmmss}-{reportId[^8..]}.{normalizedFormat}";
        return File(bytes, contentType, filename);
    }
}
