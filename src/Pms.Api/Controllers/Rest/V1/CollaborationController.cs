using System.ComponentModel.DataAnnotations;
using Path = System.IO.Path;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Pms.Api.Auth;
using Pms.Domain.Entities;
using Pms.Infrastructure.Persistence.EfCore;
namespace Pms.Api.Controllers.Rest.V1;
[ApiController, Authorize]
public sealed class CollaborationController(PmsDbContext db, IWebHostEnvironment environment) : ControllerBase
{
    private async Task<WorkTask?> TaskAccess(Guid id, bool write, CancellationToken ct)
    {
        var task = await db.Tasks.AsNoTracking().SingleOrDefaultAsync(x => x.Id == id && x.DeletedAt == null, ct);
        if (task is null || !await (from projectMember in db.ProjectMembers
            join project in db.Projects on projectMember.ProjectId equals project.Id
            join organizationMember in db.OrganizationMembers on project.OrganizationId equals organizationMember.OrganizationId
            where projectMember.ProjectId == task.ProjectId && projectMember.UserId == CurrentUser.Id(User) && projectMember.Status == "active"
                && organizationMember.UserId == CurrentUser.Id(User) && organizationMember.Status == "active"
                && project.ArchivedAt == null && (!write || projectMember.Role != "VIEWER")
            select projectMember).AnyAsync(ct)) return null;
        return task;
    }
    [HttpGet("/api/v1/tasks/{id:guid}/comments")]
    public async Task<IActionResult> Comments(Guid id, CancellationToken ct)
    {
        if (await TaskAccess(id, false, ct) is null) return NotFound();
        return Ok(await (from c in db.Comments join u in db.Users on c.UserId equals u.Id where c.TaskId == id && c.DeletedAt == null orderby c.CreatedAt select new { c.Id, c.UserId, c.Content, c.CreatedAt, c.ParentCommentId, author = u.FirstName + " " + u.LastName }).ToListAsync(ct));
    }
    [HttpPost("/api/v1/tasks/{id:guid}/comments")]
    public async Task<IActionResult> Comment(Guid id, CommentRequest r, CancellationToken ct)
    {
        var task = await TaskAccess(id, true, ct); if (task is null) return NotFound();
        if (string.IsNullOrWhiteSpace(r.Content)) return BadRequest(new { message = "Write a comment first." });
        if (r.ParentCommentId is not null && !await db.Comments.AnyAsync(x => x.Id == r.ParentCommentId && x.TaskId == id && x.DeletedAt == null, ct)) return BadRequest(new { message = "Invalid parent comment." });
        var mentions = r.MentionedUserIds.Distinct().ToArray();
        if (await db.ProjectMembers.CountAsync(x => x.ProjectId == task.ProjectId && mentions.Contains(x.UserId) && x.Status == "active", ct) != mentions.Length) return BadRequest(new { message = "Only project members can be mentioned." });
        var c = new Comment { Id = Guid.NewGuid(), TaskId = id, UserId = CurrentUser.Id(User), Content = r.Content.Trim(), ParentCommentId = r.ParentCommentId };
        db.Comments.Add(c);
        foreach (var uid in mentions) db.CommentMentions.Add(new CommentMention { Id = Guid.NewGuid(), CommentId = c.Id, UserId = uid });
        var recipients = (await db.TaskAssignees.Where(x => x.TaskId == id).Select(x => x.UserId).ToListAsync(ct)).Concat(mentions).Append(task.CreatedBy).Distinct().Where(x => x != CurrentUser.Id(User));
        foreach (var uid in recipients) db.Notifications.Add(new Notification { Id = Guid.NewGuid(), UserId = uid, Type = "COMMENT", Message = $"New comment on {task.Title}.", EntityType = "TASK", RelatedId = id });
        await db.SaveChangesAsync(ct); return Ok(new { c.Id });
    }
    [HttpDelete("/api/v1/tasks/{taskId:guid}/comments/{commentId:guid}")]
    public async Task<IActionResult> DeleteComment(Guid taskId, Guid commentId, CancellationToken ct)
    {
        var task = await TaskAccess(taskId, true, ct);
        var comment = await db.Comments.SingleOrDefaultAsync(x => x.Id == commentId && x.TaskId == taskId && x.DeletedAt == null, ct);
        if (task is null || comment is null) return NotFound();
        var userId = CurrentUser.Id(User);
        var canDelete = comment.UserId == userId || await IsManager(task.ProjectId, userId, ct);
        if (!canDelete) return Forbid();
        comment.DeletedAt = DateTime.UtcNow; comment.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct); return NoContent();
    }
    [HttpGet("/api/v1/tasks/{id:guid}/attachments")]
    public async Task<IActionResult> Attachments(Guid id, CancellationToken ct)
    {
        if (await TaskAccess(id, false, ct) is null) return NotFound();
        return Ok(await db.Attachments.Where(x => x.TaskId == id && x.DeletedAt == null).Select(x => new { x.Id, x.UploadedBy, x.FileName, x.FileSize, x.CreatedAt }).ToListAsync(ct));
    }
    [HttpPost("/api/v1/tasks/{id:guid}/attachments"), RequestSizeLimit(11_000_000)]
    public async Task<IActionResult> Upload(Guid id, IFormFile file, CancellationToken ct)
    {
        var task = await TaskAccess(id, true, ct);
        if (task is null) return NotFound();
        if (file.Length <= 0 || file.Length > 10_000_000) return BadRequest(new { message = "Choose a file between 1 byte and 10 MB." });
        var name = Path.GetFileName(file.FileName); if (name.Length > 500) return BadRequest(new { message = "File name is too long." });
        var attachment = new Attachment { Id = Guid.NewGuid(), TaskId = id, UploadedBy = CurrentUser.Id(User), FileName = name, FileUrl = "local", FileSize = file.Length, FileType = "application/octet-stream" };
        var folder = Path.Combine(environment.ContentRootPath, ".data", "uploads"); Directory.CreateDirectory(folder);
        var path = Path.Combine(folder, attachment.Id.ToString());
        var recipients = await db.ProjectMembers
            .Where(member => member.ProjectId == task.ProjectId && member.Status == "active"
                && member.UserId != attachment.UploadedBy
                && (member.UserId == task.CreatedBy || db.TaskAssignees.Any(assignee =>
                    assignee.TaskId == id && assignee.UserId == member.UserId && assignee.Status == "active")))
            .Select(member => member.UserId).Distinct().ToListAsync(ct);
        try
        {
            await using (var output = System.IO.File.Create(path)) await file.CopyToAsync(output, ct);
            db.Attachments.Add(attachment);
            foreach (var recipient in recipients)
                db.Notifications.Add(new Notification
                {
                    Id = Guid.NewGuid(), UserId = recipient, Type = "ATTACHMENT",
                    Message = $"A file was attached to {task.Title}.",
                    EntityType = "TASK", RelatedId = task.Id
                });
            // File metadata and notifications commit together. Failed uploads notify nobody.
            await db.SaveChangesAsync(ct);
        }
        catch { if (System.IO.File.Exists(path)) System.IO.File.Delete(path); throw; }
        return Ok(new { attachment.Id, attachment.FileName, attachment.FileSize });
    }
    [HttpGet("/api/v1/attachments/{id:guid}/download")]
    public async Task<IActionResult> Download(Guid id, CancellationToken ct)
    {
        var attachment = await db.Attachments.SingleOrDefaultAsync(x => x.Id == id && x.DeletedAt == null, ct);
        if (attachment?.TaskId is not Guid taskId || await TaskAccess(taskId, false, ct) is null) return NotFound();
        var path = Path.Combine(environment.ContentRootPath, ".data", "uploads", id.ToString());
        return System.IO.File.Exists(path) ? PhysicalFile(path, "application/octet-stream", attachment.FileName) : NotFound();
    }
    [HttpDelete("/api/v1/attachments/{id:guid}")]
    public async Task<IActionResult> DeleteAttachment(Guid id, CancellationToken ct)
    {
        var attachment = await db.Attachments.SingleOrDefaultAsync(x => x.Id == id && x.DeletedAt == null, ct);
        if (attachment?.TaskId is not Guid taskId) return NotFound();
        var task = await TaskAccess(taskId, true, ct);
        if (task is null) return NotFound();
        var userId = CurrentUser.Id(User);
        if (attachment.UploadedBy != userId && !await IsManager(task.ProjectId, userId, ct)) return Forbid();
        attachment.DeletedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);
        var path = Path.Combine(environment.ContentRootPath, ".data", "uploads", id.ToString());
        if (System.IO.File.Exists(path)) System.IO.File.Delete(path);
        return NoContent();
    }
    [HttpGet("/api/v1/notifications")]
    public async Task<IActionResult> Notifications(CancellationToken ct) => Ok(await db.Notifications.Where(x => x.UserId == CurrentUser.Id(User)).OrderByDescending(x => x.CreatedAt).Select(x => new { x.Id, x.Message, x.IsRead, x.CreatedAt, x.RelatedId, projectId = db.Tasks.Where(t => t.Id == x.RelatedId && t.DeletedAt == null).Select(t => (Guid?)t.ProjectId).FirstOrDefault() }).ToListAsync(ct));
    [HttpPatch("/api/v1/notifications/read-all")]
    public async Task<IActionResult> ReadAll(CancellationToken ct) { await db.Notifications.Where(x => x.UserId == CurrentUser.Id(User) && !x.IsRead).ExecuteUpdateAsync(s => s.SetProperty(x => x.IsRead, true), ct); return NoContent(); }
    [HttpPatch("/api/v1/notifications/{id:guid}/read")]
    public async Task<IActionResult> Read(Guid id, CancellationToken ct) { await db.Notifications.Where(x => x.Id == id && x.UserId == CurrentUser.Id(User)).ExecuteUpdateAsync(s => s.SetProperty(x => x.IsRead, true), ct); return NoContent(); }
    private Task<bool> IsManager(Guid projectId, Guid userId, CancellationToken ct) => (from member in db.ProjectMembers
        join project in db.Projects on member.ProjectId equals project.Id
        join organizationMember in db.OrganizationMembers on project.OrganizationId equals organizationMember.OrganizationId
        where member.ProjectId == projectId && member.UserId == userId && member.Status == "active"
            && organizationMember.UserId == userId && organizationMember.Status == "active" && organizationMember.Role != "GUEST"
            && (member.Role == "PROJECT_MANAGER" || member.Role == "TEAM_LEAD")
        select member).AnyAsync(ct);
}
public sealed record CommentRequest([Required, StringLength(10000)] string Content, [Required] IReadOnlyCollection<Guid> MentionedUserIds, Guid? ParentCommentId);
