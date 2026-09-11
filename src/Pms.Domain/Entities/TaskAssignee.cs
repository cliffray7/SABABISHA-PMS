namespace Pms.Domain.Entities;

public sealed class TaskAssignee
{
    public Guid Id { get; set; }
    public Guid TaskId { get; set; }
    public Guid UserId { get; set; }
    public DateTime AssignedAt { get; set; } = DateTime.UtcNow;
    public string Status { get; set; } = "active";

    public WorkTask? Task { get; set; }
}
