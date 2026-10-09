using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Pms.Api.Auth;
using Pms.Infrastructure.Persistence.EfCore;

namespace Pms.Api.Controllers.Rest.V1;

[ApiController, Authorize, Route("api/v1/projects/{projectId:guid}/tasks/{taskId:guid}/assignment-history")]
public sealed class TaskAssignmentHistoryController(PmsDbContext db) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> Get(Guid projectId, Guid taskId, CancellationToken cancellationToken)
    {
        var taskExists = await db.Tasks.AsNoTracking().AnyAsync(task => task.Id == taskId
            && task.ProjectId == projectId && task.DeletedAt == null, cancellationToken);
        if (!taskExists) return NotFound();
        if (!await WorkspaceAuthorization.CanAccessProjectAsync(db, projectId, CurrentUser.Id(User),
                write: false, cancellationToken)) return Forbid();

        var events = await db.TaskAssignmentEvents.AsNoTracking()
            .Where(item => item.TaskId == taskId && item.ProjectId == projectId)
            .OrderBy(item => item.OccurredAtUtc).ThenBy(item => item.EventId)
            .Select(item => new
            {
                eventId = item.EventId,
                operationId = item.OperationId,
                organizationId = item.OrganizationId,
                projectId = item.ProjectId,
                taskId = item.TaskId,
                departingMemberId = item.DepartingUserId,
                replacementMemberId = item.ReplacementUserId,
                actorId = item.ActorUserId,
                occurredAtUtc = item.OccurredAtUtc,
                action = item.Action,
                reason = item.ReasonCode
            }).ToListAsync(cancellationToken);
        return Ok(new { taskId, legacyHistoryComplete = false, events });
    }
}
