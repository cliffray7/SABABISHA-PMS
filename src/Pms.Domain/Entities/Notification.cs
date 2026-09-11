namespace Pms.Domain.Entities;

public sealed class Notification
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public required string Type { get; set; }
    public required string Message { get; set; }
    public required string EntityType { get; set; }
    public Guid? RelatedId { get; set; }
    public bool IsRead { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
