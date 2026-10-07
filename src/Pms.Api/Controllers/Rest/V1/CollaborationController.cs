using System.ComponentModel.DataAnnotations;
using Path = System.IO.Path;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Pms.Api.Auth;
using Pms.Api.Activity;
using Pms.Api.Media;
using Pms.Domain.Entities;
using Pms.Infrastructure.Persistence.EfCore;
using Pms.Api.Realtime;
namespace Pms.Api.Controllers.Rest.V1;
[ApiController, Authorize]
public sealed class CollaborationController(PmsDbContext db, IWebHostEnvironment environment, IConfiguration configuration, ICloudinaryStorage media, ILogger<CollaborationController> logger, RealtimePublisher realtime) : ControllerBase
{
    private string UploadFolder
    {
        get
        {
            var configuredPath = configuration["Uploads:Path"];
            return string.IsNullOrWhiteSpace(configuredPath)
                ? Path.Combine(environment.ContentRootPath, ".data", "uploads")
                : Path.GetFullPath(configuredPath, environment.ContentRootPath);
        }
    }
    private async Task<WorkTask?> TaskAccess(Guid id, bool write, CancellationToken ct)
    {
        var task = await db.Tasks.AsNoTracking().SingleOrDefaultAsync(x => x.Id == id && x.DeletedAt == null, ct);
        if (task is null || !await WorkspaceAuthorization.CanAccessProjectAsync(
            db, task.ProjectId, CurrentUser.Id(User), write, ct)) return null;
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
        var project = await db.Projects.AsNoTracking().Where(x => x.Id == task.ProjectId).Select(x => new { x.OrganizationId, x.Name }).SingleAsync(ct);
        await ActivityRecorder.RecordAsync(db, User, Request, project.OrganizationId, "Collaboration", mentions.Length > 0 ? "comment.mentioned" : "comment.created", "task", task.Id, task.Title,
            mentions.Length > 0 ? $"commented on task \"{task.Title}\" and mentioned teammates in project \"{project.Name}\"" : $"commented on task \"{task.Title}\" in project \"{project.Name}\"", ct, task.ProjectId);
        await db.SaveChangesAsync(ct); await Publish(task.ProjectId, "collaboration", ct); return Ok(new { c.Id });
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
        var project = await db.Projects.AsNoTracking().Where(x => x.Id == task.ProjectId).Select(x => new { x.OrganizationId, x.Name }).SingleAsync(ct);
        await ActivityRecorder.RecordAsync(db, User, Request, project.OrganizationId, "Collaboration", "comment.deleted", "task", task.Id, task.Title, $"deleted a comment on task \"{task.Title}\" in project \"{project.Name}\"", ct, task.ProjectId);
        await db.SaveChangesAsync(ct); await Publish(task.ProjectId, "collaboration", ct); return NoContent();
    }
    [HttpPost("/api/v1/tasks/{taskId:guid}/comments/{commentId:guid}/restore")]
    public async Task<IActionResult> RestoreComment(Guid taskId, Guid commentId, CancellationToken ct)
    {
        var task = await TaskAccess(taskId, true, ct);
        var comment = await db.Comments.SingleOrDefaultAsync(x => x.Id == commentId && x.TaskId == taskId && x.DeletedAt != null && x.DeletedAt >= DateTime.UtcNow.AddDays(-30), ct);
        if (task is null || comment is null) return NotFound();
        var userId = CurrentUser.Id(User);
        if (comment.UserId != userId && !await IsManager(task.ProjectId, userId, ct)) return Forbid();
        comment.DeletedAt = null;
        comment.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);
        await Publish(task.ProjectId, "collaboration", ct);
        return NoContent();
    }
    [HttpGet("/api/v1/tasks/{id:guid}/attachments")]
    public async Task<IActionResult> Attachments(Guid id, CancellationToken ct)
    {
        if (await TaskAccess(id, false, ct) is null) return NotFound();
        return Ok(await db.Attachments.Where(x => x.TaskId == id && x.DeletedAt == null).Select(x => new { x.Id, x.UploadedBy, x.FileName, x.FileSize, contentType = x.FileType, x.CreatedAt }).ToListAsync(ct));
    }
    [HttpPost("/api/v1/tasks/{id:guid}/attachments"), RequestSizeLimit(11_000_000)]
    public async Task<IActionResult> Upload(Guid id, IFormFile file, CancellationToken ct)
    {
        var task = await TaskAccess(id, true, ct);
        if (task is null) return NotFound();
        if (!media.IsConfigured) return StatusCode(StatusCodes.Status503ServiceUnavailable, new { message = "File storage is not configured." });
        if (file.Length <= 0 || file.Length > 10_000_000) return BadRequest(new { message = "Choose a file between 1 byte and 10 MB." });
        var name = Path.GetFileName(file.FileName); if (name.Length > 500) return BadRequest(new { message = "File name is too long." });
        CloudinaryUpload uploaded;
        try
        {
            await using var input = file.OpenReadStream();
            uploaded = await media.UploadAsync(input, name, "taskflow/attachments", "raw", ct);
        }
        catch (CloudinaryStorageException)
        {
            return StatusCode(StatusCodes.Status502BadGateway, new { message = "The file could not be uploaded. Please try again." });
        }
        var attachment = new Attachment
        {
            Id = Guid.NewGuid(),
            TaskId = id,
            UploadedBy = CurrentUser.Id(User),
            FileName = name,
            FileUrl = uploaded.SecureUrl,
            FileSize = file.Length,
            FileType = file.ContentType,
            CloudinaryPublicId = uploaded.PublicId,
            CloudinaryResourceType = uploaded.ResourceType
        };
        var recipients = await db.ProjectMembers
            .Where(member => member.ProjectId == task.ProjectId && member.Status == "active"
                && member.UserId != attachment.UploadedBy
                && (member.UserId == task.CreatedBy || db.TaskAssignees.Any(assignee =>
                    assignee.TaskId == id && assignee.UserId == member.UserId && assignee.Status == "active")))
            .Select(member => member.UserId).Distinct().ToListAsync(ct);
        db.Attachments.Add(attachment);
        foreach (var recipient in recipients)
            db.Notifications.Add(new Notification
            {
                Id = Guid.NewGuid(), UserId = recipient, Type = "ATTACHMENT",
                Message = $"A file was attached to {task.Title}.",
                EntityType = "TASK", RelatedId = task.Id
            });
        var project = await db.Projects.AsNoTracking().Where(x => x.Id == task.ProjectId).Select(x => new { x.OrganizationId, x.Name }).SingleAsync(ct);
        await ActivityRecorder.RecordAsync(db, User, Request, project.OrganizationId, "Collaboration", "attachment.uploaded", "task", task.Id, task.Title, $"attached a file to task \"{task.Title}\" in project \"{project.Name}\"", ct, task.ProjectId);
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch
        {
            try { await media.DeleteAsync(uploaded.PublicId, uploaded.ResourceType, ct); }
            catch (Exception cleanupError) { logger.LogError(cleanupError, "Could not remove unreferenced Cloudinary attachment {PublicId}.", uploaded.PublicId); }
            throw;
        }
        await Publish(task.ProjectId, "collaboration", ct);
        return Ok(new { attachment.Id, attachment.UploadedBy, attachment.FileName, attachment.FileSize, contentType = attachment.FileType, attachment.CreatedAt });
    }
    [HttpGet("/api/v1/attachments/{id:guid}/download")]
    public async Task<IActionResult> Download(Guid id, CancellationToken ct)
    {
        var attachment = await db.Attachments.SingleOrDefaultAsync(x => x.Id == id && x.DeletedAt == null, ct);
        if (attachment?.TaskId is not Guid taskId || await TaskAccess(taskId, false, ct) is null) return NotFound();
        if (!string.IsNullOrWhiteSpace(attachment.CloudinaryPublicId))
        {
            if (!media.IsConfigured) return StatusCode(StatusCodes.Status503ServiceUnavailable, new { message = "File storage is not configured." });
            try
            {
                var bytes = await media.DownloadAsync(attachment.FileUrl, ct);
                return File(bytes, attachment.FileType ?? "application/octet-stream", attachment.FileName);
            }
            catch (CloudinaryStorageException)
            {
                return StatusCode(StatusCodes.Status502BadGateway, new { message = "The requested file is not available." });
            }
        }
        var path = Path.Combine(UploadFolder, id.ToString());
        return System.IO.File.Exists(path) ? PhysicalFile(path, attachment.FileType ?? "application/octet-stream", attachment.FileName) : NotFound();
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
        var projectInfo = await db.Projects.AsNoTracking().Where(x => x.Id == task.ProjectId).Select(x => new { x.OrganizationId, x.Name }).SingleAsync(ct);
        await ActivityRecorder.RecordAsync(db, User, Request, projectInfo.OrganizationId, "Collaboration", "attachment.deleted", "task", task.Id, task.Title, $"removed a file from task \"{task.Title}\" in project \"{projectInfo.Name}\"", ct, task.ProjectId);
        await db.SaveChangesAsync(ct);
        await Publish(task.ProjectId, "collaboration", ct);
        return NoContent();
    }
    [HttpPost("/api/v1/attachments/{id:guid}/restore")]
    public async Task<IActionResult> RestoreAttachment(Guid id, CancellationToken ct)
    {
        var attachment = await db.Attachments.SingleOrDefaultAsync(x => x.Id == id && x.DeletedAt != null && x.DeletedAt >= DateTime.UtcNow.AddDays(-30), ct);
        if (attachment?.TaskId is not Guid taskId) return NotFound();
        var task = await TaskAccess(taskId, true, ct);
        if (task is null) return NotFound();
        var userId = CurrentUser.Id(User);
        if (attachment.UploadedBy != userId && !await IsManager(task.ProjectId, userId, ct)) return Forbid();
        attachment.DeletedAt = null;
        await db.SaveChangesAsync(ct);
        await Publish(task.ProjectId, "collaboration", ct);
        return NoContent();
    }
    [HttpGet("/api/v1/notifications")]
    public async Task<IActionResult> Notifications(CancellationToken ct) => Ok(await db.Notifications.Where(x => x.UserId == CurrentUser.Id(User)).OrderByDescending(x => x.CreatedAt).Select(x => new { x.Id, x.Message, x.IsRead, x.CreatedAt, x.RelatedId, projectId = db.Tasks.Where(task => task.Id == x.RelatedId && task.DeletedAt == null && db.Projects.Any(project => project.Id == task.ProjectId && project.DeletedAt == null)).Select(task => (Guid?)task.ProjectId).FirstOrDefault() }).ToListAsync(ct));
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

    private async Task Publish(Guid projectId, string area, CancellationToken ct)
    {
        var organizationId = await db.Projects.AsNoTracking().Where(project => project.Id == projectId)
            .Select(project => project.OrganizationId).SingleAsync(ct);
        await realtime.ProjectChanged(organizationId, projectId, area, ct);
    }
}
public sealed record CommentRequest([Required, StringLength(10000)] string Content, [Required] IReadOnlyCollection<Guid> MentionedUserIds, Guid? ParentCommentId);
