using System.Text;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Pms.Api.Auth;
using Pms.Infrastructure.Persistence.EfCore;

namespace Pms.Api.Controllers.Rest.V1;

[ApiController, Authorize, Route("api/v1/activity")]
public sealed class ActivityController(PmsDbContext db) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> List(
        [FromQuery] Guid organizationId,
        [FromQuery] string? category,
        [FromQuery] string? search,
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] string? cursor,
        [FromQuery] int pageSize = 30,
        CancellationToken ct = default)
    {
        var userId = CurrentUser.Id(User);
        if (organizationId == Guid.Empty || !await db.OrganizationMembers.AnyAsync(member =>
                member.OrganizationId == organizationId && member.UserId == userId && member.Status == "active", ct))
            return NotFound();
        var organizationName = await db.Organizations.AsNoTracking().Where(item => item.Id == organizationId)
            .Select(item => item.Name).SingleAsync(ct);
        if (pageSize is < 1 or > 100)
            return BadRequest(new { code = "INVALID_PAGE_SIZE", message = "pageSize must be between 1 and 100." });
        if ((from is null) != (to is null) || from > to)
            return BadRequest(new { code = "INVALID_DATE_RANGE", message = "Provide both from and to, with from on or before to." });
        if (from > DateTime.UtcNow || to > DateTime.UtcNow)
            return BadRequest(new { code = "INVALID_DATE_RANGE", message = "Activity date filters cannot be in the future." });
        if (from is not null && to!.Value - from.Value > TimeSpan.FromDays(366))
            return BadRequest(new { code = "INVALID_DATE_RANGE", message = "The maximum activity date range is 366 days." });
        if (search?.Length > 100 || category?.Length > 40 || cursor?.Length > 1024)
            return BadRequest(new { code = "INVALID_FILTER", message = "A filter is too long." });

        var query = db.ActivityEvents.AsNoTracking().Where(item => item.OrganizationId == organizationId
            && (item.ProjectId == null || db.Projects.Any(project => project.Id == item.ProjectId
                && project.OrganizationId == organizationId
                && db.ProjectMembers.Any(member => member.ProjectId == project.Id
                    && member.UserId == userId && member.Status == "active"))));
        if (!string.IsNullOrWhiteSpace(category)) query = query.Where(item => item.Category == category.Trim());
        if (!string.IsNullOrWhiteSpace(search))
        {
            var term = search.Trim();
            Guid? idTerm = Guid.TryParse(term, out var parsedId) ? parsedId : null;
            query = query.Where(item => item.ActorName.Contains(term) || item.EntityName.Contains(term)
                || item.EntityType.Contains(term) || item.Action.Contains(term) || item.Status.Contains(term)
                || item.Description.Contains(term) || item.CorrelationId.Contains(term)
                || (idTerm != null && (item.Id == idTerm.Value || item.ActorUserId == idTerm.Value
                    || item.EntityId == idTerm.Value || item.ProjectId == idTerm.Value)));
        }
        if (from is not null) query = query.Where(item => item.CreatedAtUtc >= from.Value);
        if (to is not null) query = query.Where(item => item.CreatedAtUtc < to.Value.AddDays(1));

        (DateTime CreatedAt, Guid Id)? position = null;
        if (!string.IsNullOrWhiteSpace(cursor))
        {
            try
            {
                var decoded = Encoding.UTF8.GetString(Convert.FromBase64String(cursor));
                var parts = decoded.Split('|');
                if (parts.Length != 2 || !long.TryParse(parts[0], out var ticks) || !Guid.TryParseExact(parts[1], "N", out var id)) throw new FormatException();
                position = (new DateTime(ticks, DateTimeKind.Utc), id);
            }
            catch (Exception exception) when (exception is FormatException or ArgumentOutOfRangeException)
            {
                return BadRequest(new { code = "INVALID_CURSOR", message = "The activity cursor is invalid." });
            }
        }
        if (position is not null)
            query = query.Where(item => item.CreatedAtUtc < position.Value.CreatedAt
                || (item.CreatedAtUtc == position.Value.CreatedAt && item.Id.CompareTo(position.Value.Id) < 0));

        var page = await query.OrderByDescending(item => item.CreatedAtUtc).ThenByDescending(item => item.Id)
            .Take(pageSize + 1).ToListAsync(ct);
        var hasMore = page.Count > pageSize;
        if (hasMore) page.RemoveAt(pageSize);
        var nextCursor = hasMore && page.Count > 0
            ? Convert.ToBase64String(Encoding.UTF8.GetBytes($"{page[^1].CreatedAtUtc.Ticks}|{page[^1].Id:N}"))
            : null;
        var projectIds = page.Where(item => item.ProjectId != null)
            .Select(item => item.ProjectId!.Value).Distinct().ToArray();
        var projectNames = projectIds.Length == 0
            ? new Dictionary<Guid, string>()
            : await db.Projects.AsNoTracking()
                .Where(project => project.OrganizationId == organizationId && projectIds.Contains(project.Id))
                .ToDictionaryAsync(project => project.Id, project => project.Name, ct);

        return Ok(new
        {
            items = page.Select(item => new
            {
                eventId = item.Id, item.OrganizationId, item.ProjectId,
                projectName = item.ProjectId is Guid projectId && projectNames.TryGetValue(projectId, out var name)
                    ? name : null,
                organizationName, actorUserId = item.ActorUserId, actorName = item.ActorName,
                item.Category, item.Action, item.EntityType, item.EntityId, item.EntityName,
                item.Description, item.Status, item.CorrelationId, createdAt = item.CreatedAtUtc
            }),
            nextCursor
        });
    }
}
