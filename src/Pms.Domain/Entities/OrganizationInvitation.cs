namespace Pms.Domain.Entities;

public sealed class OrganizationInvitation
{
    public Guid Id { get; set; }
    public Guid OrganizationId { get; set; }
    public required string Email { get; set; }
    public required string Role { get; set; }
    public required string TokenHash { get; set; }
    public DateTime ExpiresAt { get; set; }
    public DateTime? AcceptedAt { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
