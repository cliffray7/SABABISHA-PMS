using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using Pms.Api.Auth;
using Pms.Domain.Entities;
using Pms.Infrastructure.Persistence.EfCore;

namespace Pms.Api.Activity;

/// <summary>Queues a workspace activity record on the current DbContext so it commits with the business change.</summary>
public static class ActivityRecorder
{
    public static async Task InactivateTaskAssignmentsAsync(
        PmsDbContext db,
        ClaimsPrincipal actor,
        HttpRequest request,
        Guid organizationId,
        Guid userId,
        string userName,
        string reason,
        Guid? projectId,
        CancellationToken cancellationToken)
    {
        var assignments = await (from assignee in db.TaskAssignees
                                 join task in db.Tasks on assignee.TaskId equals task.Id
                                 join project in db.Projects on task.ProjectId equals project.Id
                                 where assignee.UserId == userId && assignee.Status == "active"
                                     && project.OrganizationId == organizationId
                                     && (projectId == null || project.Id == projectId)
                                 select new { Assignee = assignee, TaskId = task.Id, TaskTitle = task.Title, ProjectId = project.Id, ProjectName = project.Name })
            .ToListAsync(cancellationToken);

        foreach (var assignment in assignments)
        {
            assignment.Assignee.Status = "inactive";
            await RecordAsync(db, actor, request, organizationId, "Tasks", "task.assignee_inactivated", "task",
                assignment.TaskId, assignment.TaskTitle,
                $"removed {userName}'s active assignment from task \"{assignment.TaskTitle}\" in project \"{assignment.ProjectName}\" because {reason}",
                cancellationToken, assignment.ProjectId);
        }
    }

    public static void RecordPlatform(
        PmsDbContext db,
        HttpRequest request,
        Guid? actorUserId,
        string actorName,
        string action,
        Guid entityId,
        string entityName,
        string description,
        string status)
    {
        var correlationId = request.Headers["X-Correlation-ID"].FirstOrDefault();
        if (string.IsNullOrWhiteSpace(correlationId) || correlationId.Length > 128)
            correlationId = request.HttpContext.TraceIdentifier;

        db.ActivityEvents.Add(new ActivityEvent
        {
            Id = Guid.NewGuid(),
            OrganizationId = null,
            ProjectId = null,
            ActorUserId = actorUserId,
            ActorName = actorName.Length > 201 ? actorName[..201] : actorName,
            Category = "System",
            Action = action,
            EntityType = "Authentication",
            EntityId = entityId,
            EntityName = entityName.Length > 300 ? entityName[..300] : entityName,
            Description = description.Length > 500 ? description[..500] : description,
            Status = status,
            CorrelationId = correlationId,
            CreatedAtUtc = DateTime.UtcNow
        });
    }

    public static async Task RecordAsync(
        PmsDbContext db,
        ClaimsPrincipal actor,
        HttpRequest request,
        Guid organizationId,
        string category,
        string action,
        string entityType,
        Guid entityId,
        string entityName,
        string description,
        CancellationToken cancellationToken,
        Guid? projectId = null)
    {
        var actorId = CurrentUser.Id(actor);
        var actorName = await db.Users.AsNoTracking()
            .Where(user => user.Id == actorId)
            .Select(user => user.FirstName + " " + user.LastName)
            .SingleOrDefaultAsync(cancellationToken) ?? "Workspace member";
        var correlationId = request.Headers["X-Correlation-ID"].FirstOrDefault();
        if (string.IsNullOrWhiteSpace(correlationId) || correlationId.Length > 128)
            correlationId = request.HttpContext.TraceIdentifier;

        db.ActivityEvents.Add(new ActivityEvent
        {
            Id = Guid.NewGuid(),
            OrganizationId = organizationId,
            ProjectId = projectId,
            ActorUserId = actorId,
            ActorName = actorName.Length > 201 ? actorName[..201] : actorName,
            Category = category,
            Action = action,
            EntityType = entityType,
            EntityId = entityId,
            EntityName = entityName.Length > 300 ? entityName[..300] : entityName,
            Description = description.Length > 500 ? description[..500] : description,
            Status = "succeeded",
            CorrelationId = correlationId,
            CreatedAtUtc = DateTime.UtcNow
        });
    }
}
