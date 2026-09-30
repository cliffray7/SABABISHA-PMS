namespace Pms.Domain.Entities;

/// <summary>Immutable record of a completed privileged platform operation.</summary>
public sealed class AdminAuditEvent
{
    public Guid Id { get; set; }
    public Guid ActorId { get; set; }
    public required string ActorDisplayName { get; set; }
    public required string Action { get; set; }
    public required string TargetType { get; set; }
    public Guid TargetId { get; set; }
    public required string TargetDisplayName { get; set; }
    public required string Outcome { get; set; }
    public string? Reason { get; set; }
    public required string CorrelationId { get; set; }
    public DateTimeOffset OccurredAt { get; set; }
}
