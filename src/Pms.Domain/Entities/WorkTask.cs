namespace Pms.Domain.Entities;

public sealed class WorkTask
{
    public Guid Id { get; set; }
    public Guid ProjectId { get; set; }
    public Guid? ParentTaskId { get; set; }
    public required string Title { get; set; }
    public string? Description { get; set; }
    public required string Status { get; set; }
    public string Priority { get; set; } = "MEDIUM";
    public DateTime? StartDate { get; set; }
    public DateTime? DueDate { get; set; }
    public Guid CreatedBy { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? CompletedAt { get; set; }
    public DateTime? DeletedAt { get; set; }

    public ICollection<TaskAssignee> Assignees { get; set; } = [];
}
