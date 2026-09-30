namespace Pms.Domain.Entities;

/// <summary>Human-readable workspace activity. Kept separate from the immutable admin audit trail.</summary>
public sealed class ActivityEvent
{
    public Guid Id { get; set; }
    public Guid OrganizationId { get; set; }
    public Guid? ProjectId { get; set; }
    public Guid ActorUserId { get; set; }
    public required string ActorName { get; set; }
    public required string Category { get; set; }
    public required string Action { get; set; }
    public required string EntityType { get; set; }
    public Guid EntityId { get; set; }
    public required string EntityName { get; set; }
    public required string Description { get; set; }
    public required string Status { get; set; }
    public required string CorrelationId { get; set; }
    public DateTime CreatedAtUtc { get; set; }
}
