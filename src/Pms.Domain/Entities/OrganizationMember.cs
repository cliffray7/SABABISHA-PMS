namespace Pms.Domain.Entities;

public sealed class OrganizationMember
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public Guid OrganizationId { get; set; }
    public required string Role { get; set; }
    public DateTime JoinedAt { get; set; } = DateTime.UtcNow;
    public string Status { get; set; } = "active";
    public Organization? Organization { get; set; }
}
