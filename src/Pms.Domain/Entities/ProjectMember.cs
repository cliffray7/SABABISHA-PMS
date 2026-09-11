namespace Pms.Domain.Entities;

public sealed class ProjectMember
{
    public Guid Id { get; set; }
    public Guid ProjectId { get; set; }
    public Guid UserId { get; set; }
    public required string Role { get; set; }
    public DateTime JoinedAt { get; set; } = DateTime.UtcNow;
    public string Status { get; set; } = "active";
}
