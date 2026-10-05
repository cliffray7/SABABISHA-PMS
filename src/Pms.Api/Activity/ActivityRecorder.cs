using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using Pms.Api.Auth;
using Pms.Domain.Entities;
using Pms.Infrastructure.Persistence.EfCore;

namespace Pms.Api.Activity;

/// <summary>Queues a workspace activity record on the current DbContext so it commits with the business change.</summary>
public static class ActivityRecorder
{
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
