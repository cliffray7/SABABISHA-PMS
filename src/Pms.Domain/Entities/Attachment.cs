namespace Pms.Domain.Entities;

public sealed class Attachment
{
    public Guid Id { get; set; }
    public Guid? TaskId { get; set; }
    public Guid? CommentId { get; set; }
    public Guid UploadedBy { get; set; }
    public required string FileName { get; set; }
    public required string FileUrl { get; set; }
    public string? FileType { get; set; }
    public long FileSize { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? DeletedAt { get; set; }
}
