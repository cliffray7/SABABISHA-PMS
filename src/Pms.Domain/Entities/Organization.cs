namespace Pms.Domain.Entities;

public sealed class Organization
{
    public Guid Id { get; set; }
    public required string Name { get; set; }
    public required string Slug { get; set; }
    public string? Logo { get; set; }
    public string Timezone { get; set; } = "UTC";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    public ICollection<OrganizationMember> Members { get; set; } = [];
}
