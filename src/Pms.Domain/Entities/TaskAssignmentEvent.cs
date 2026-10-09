namespace Pms.Domain.Entities;

/// <summary>Append-only, purge-retained history for task assignment resolution operations.</summary>
public sealed class TaskAssignmentEvent
{
    public Guid EventId { get; set; }
    public Guid OperationId { get; set; }
    public Guid OrganizationId { get; set; }
    public Guid ProjectId { get; set; }
    public Guid TaskId { get; set; }
    public Guid DepartingUserId { get; set; }
    public Guid? ReplacementUserId { get; set; }
    public Guid ActorUserId { get; set; }
    public DateTime OccurredAtUtc { get; set; }
    public required string Action { get; set; }
    public string? ReasonCode { get; set; }
}
