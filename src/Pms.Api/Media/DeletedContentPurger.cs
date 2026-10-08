using Microsoft.EntityFrameworkCore;
using Pms.Domain.Entities;
using Pms.Infrastructure.Persistence.EfCore;

namespace Pms.Api.Media;

public sealed class DeletedContentPurger(
    IServiceScopeFactory scopeFactory,
    IConfiguration configuration,
    IHostEnvironment environment,
    ILogger<DeletedContentPurger> logger) : BackgroundService
{
    private static readonly TimeSpan Interval = TimeSpan.FromHours(6);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(Interval);
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await PurgeExpiredAsync(stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception error)
            {
                logger.LogError(error, "The 30-day deleted-content purge failed; it will retry on the next interval.");
            }

            try
            {
                if (!await timer.WaitForNextTickAsync(stoppingToken)) break;
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
        }
    }

    private async Task PurgeExpiredAsync(CancellationToken cancellationToken)
    {
        await using var scope = scopeFactory.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<PmsDbContext>();
        var media = scope.ServiceProvider.GetRequiredService<ICloudinaryStorage>();
        if (!media.IsConfigured)
        {
            logger.LogWarning("Deleted media purge is paused because Cloudinary is not configured.");
            return;
        }

        var cutoff = DateTime.UtcNow.AddDays(-30);
        var projects = await db.Projects.Where(project => project.DeletedAt != null && project.DeletedAt <= cutoff)
            .OrderBy(project => project.DeletedAt).Take(20).ToListAsync(cancellationToken);
        foreach (var project in projects)
        {
            try { await PurgeProjectAsync(db, media, project, cancellationToken); }
            catch (Exception error) when (!cancellationToken.IsCancellationRequested)
            {
                logger.LogError(error, "Could not permanently purge deleted project {ProjectId}.", project.Id);
            }
        }

        var expiredTasks = await db.Tasks
            .Where(task => task.DeletedAt != null && task.DeletedAt <= cutoff
                && db.Projects.Any(project => project.Id == task.ProjectId && project.DeletedAt == null))
            .OrderBy(task => task.DeletedAt).Take(20).ToListAsync(cancellationToken);
        foreach (var task in expiredTasks)
        {
            try { await PurgeTaskAsync(db, media, task, cancellationToken); }
            catch (Exception error) when (!cancellationToken.IsCancellationRequested)
            {
                logger.LogError(error, "Could not permanently purge deleted task {TaskId}.", task.Id);
            }
        }

        var expiredComments = await db.Comments
            .Where(comment => comment.DeletedAt != null && comment.DeletedAt <= cutoff
                && db.Tasks.Any(task => task.Id == comment.TaskId && task.DeletedAt == null
                    && db.Projects.Any(project => project.Id == task.ProjectId && project.DeletedAt == null)))
            .OrderBy(comment => comment.DeletedAt).Take(50).ToListAsync(cancellationToken);
        foreach (var comment in expiredComments)
        {
            try { await PurgeCommentAsync(db, media, comment, cancellationToken); }
            catch (Exception error) when (!cancellationToken.IsCancellationRequested)
            {
                logger.LogError(error, "Could not permanently purge deleted comment {CommentId}.", comment.Id);
            }
        }

        var expiredAttachments = await db.Attachments
            .Where(attachment => attachment.DeletedAt != null && attachment.DeletedAt <= cutoff
                && (attachment.TaskId == null || db.Tasks.Any(task => task.Id == attachment.TaskId && task.DeletedAt == null
                    && db.Projects.Any(project => project.Id == task.ProjectId && project.DeletedAt == null))))
            .OrderBy(attachment => attachment.DeletedAt).Take(50).ToListAsync(cancellationToken);
        foreach (var attachment in expiredAttachments)
        {
            try
            {
                await DeleteMediaAsync(media, [attachment], cancellationToken);
                RemoveLegacyUpload(attachment.Id);
                db.Attachments.Remove(attachment);
                await db.SaveChangesAsync(cancellationToken);
            }
            catch (Exception error) when (!cancellationToken.IsCancellationRequested)
            {
                logger.LogError(error, "Could not permanently purge deleted attachment {AttachmentId}.", attachment.Id);
            }
        }
    }

    private async Task PurgeProjectAsync(PmsDbContext db, ICloudinaryStorage media, Project project, CancellationToken ct)
    {
        var tasks = await db.Tasks.Where(task => task.ProjectId == project.Id).ToListAsync(ct);
        var taskIds = tasks.Select(task => task.Id).ToHashSet();
        var comments = await db.Comments.Where(comment => taskIds.Contains(comment.TaskId)).ToListAsync(ct);
        var commentIds = comments.Select(comment => comment.Id).ToHashSet();
        var attachments = await db.Attachments.Where(attachment =>
            attachment.TaskId != null && taskIds.Contains(attachment.TaskId.Value)
            || attachment.CommentId != null && commentIds.Contains(attachment.CommentId.Value)).ToListAsync(ct);

        await DeleteMediaAsync(media, attachments, ct);
        foreach (var attachment in attachments) RemoveLegacyUpload(attachment.Id);
        await RemoveTaskContentAsync(db, tasks, comments, attachments, ct);
        db.ProjectMembers.RemoveRange(await db.ProjectMembers.Where(member => member.ProjectId == project.Id).ToListAsync(ct));
        db.Projects.Remove(project);
        await db.SaveChangesAsync(ct);
        logger.LogInformation("Permanently purged project {ProjectId} and its content after retention.", project.Id);
    }

    private async Task PurgeTaskAsync(PmsDbContext db, ICloudinaryStorage media, WorkTask root, CancellationToken ct)
    {
        var projectTasks = await db.Tasks.Where(task => task.ProjectId == root.ProjectId).ToListAsync(ct);
        var taskIds = CollectTaskDescendants(root.Id, projectTasks);
        var tasks = projectTasks.Where(task => taskIds.Contains(task.Id)).ToList();
        var comments = await db.Comments.Where(comment => taskIds.Contains(comment.TaskId)).ToListAsync(ct);
        var commentIds = comments.Select(comment => comment.Id).ToHashSet();
        var attachments = await db.Attachments.Where(attachment =>
            attachment.TaskId != null && taskIds.Contains(attachment.TaskId.Value)
            || attachment.CommentId != null && commentIds.Contains(attachment.CommentId.Value)).ToListAsync(ct);

        await DeleteMediaAsync(media, attachments, ct);
        foreach (var attachment in attachments) RemoveLegacyUpload(attachment.Id);
        await RemoveTaskContentAsync(db, tasks, comments, attachments, ct);
        await db.SaveChangesAsync(ct);
        logger.LogInformation("Permanently purged task {TaskId} and its content after retention.", root.Id);
    }

    private async Task PurgeCommentAsync(PmsDbContext db, ICloudinaryStorage media, Comment root, CancellationToken ct)
    {
        var taskComments = await db.Comments.Where(comment => comment.TaskId == root.TaskId).ToListAsync(ct);
        var commentIds = CollectCommentDescendants(root.Id, taskComments);
        var comments = taskComments.Where(comment => commentIds.Contains(comment.Id)).ToList();
        var attachments = await db.Attachments.Where(attachment =>
            attachment.CommentId != null && commentIds.Contains(attachment.CommentId.Value)).ToListAsync(ct);
        await DeleteMediaAsync(media, attachments, ct);
        foreach (var attachment in attachments) RemoveLegacyUpload(attachment.Id);
        db.CommentMentions.RemoveRange(await db.CommentMentions.Where(mention => commentIds.Contains(mention.CommentId)).ToListAsync(ct));
        db.Attachments.RemoveRange(attachments);
        db.Comments.RemoveRange(comments);
        await db.SaveChangesAsync(ct);
    }

    private static async Task RemoveTaskContentAsync(
        PmsDbContext db,
        IReadOnlyCollection<WorkTask> tasks,
        IReadOnlyCollection<Comment> comments,
        IReadOnlyCollection<Attachment> attachments,
        CancellationToken ct)
    {
        var taskIds = tasks.Select(task => task.Id).ToArray();
        var commentIds = comments.Select(comment => comment.Id).ToArray();
        db.Notifications.RemoveRange(await db.Notifications.Where(notification =>
            notification.RelatedId != null && taskIds.Contains(notification.RelatedId.Value)).ToListAsync(ct));
        db.TaskAssignmentEvents.RemoveRange(await db.TaskAssignmentEvents
            .Where(item => taskIds.Contains(item.TaskId)).ToListAsync(ct));
        db.CommentMentions.RemoveRange(await db.CommentMentions.Where(mention => commentIds.Contains(mention.CommentId)).ToListAsync(ct));
        db.TaskAssignees.RemoveRange(await db.TaskAssignees.Where(assignee => taskIds.Contains(assignee.TaskId)).ToListAsync(ct));
        db.Attachments.RemoveRange(attachments);
        db.Comments.RemoveRange(comments);
        db.Tasks.RemoveRange(tasks);
    }

    private static HashSet<Guid> CollectTaskDescendants(Guid rootId, IReadOnlyCollection<WorkTask> tasks)
    {
        var ids = new HashSet<Guid> { rootId };
        var pending = new Queue<Guid>();
        pending.Enqueue(rootId);
        while (pending.TryDequeue(out var parentId))
        {
            foreach (var child in tasks.Where(task => task.ParentTaskId == parentId))
            {
                if (ids.Add(child.Id)) pending.Enqueue(child.Id);
            }
        }
        return ids;
    }

    private static HashSet<Guid> CollectCommentDescendants(Guid rootId, IReadOnlyCollection<Comment> comments)
    {
        var ids = new HashSet<Guid> { rootId };
        var pending = new Queue<Guid>();
        pending.Enqueue(rootId);
        while (pending.TryDequeue(out var parentId))
        {
            foreach (var child in comments.Where(comment => comment.ParentCommentId == parentId))
            {
                if (ids.Add(child.Id)) pending.Enqueue(child.Id);
            }
        }
        return ids;
    }

    private static async Task DeleteMediaAsync(ICloudinaryStorage media, IEnumerable<Attachment> attachments, CancellationToken ct)
    {
        foreach (var attachment in attachments)
        {
            if (!string.IsNullOrWhiteSpace(attachment.CloudinaryPublicId))
                await media.DeleteAsync(attachment.CloudinaryPublicId, attachment.CloudinaryResourceType ?? "raw", ct);
        }
    }

    private void RemoveLegacyUpload(Guid attachmentId)
    {
        var configuredPath = configuration["Uploads:Path"];
        var folder = string.IsNullOrWhiteSpace(configuredPath)
            ? System.IO.Path.Combine(environment.ContentRootPath, ".data", "uploads")
            : System.IO.Path.GetFullPath(configuredPath, environment.ContentRootPath);
        var path = System.IO.Path.Combine(folder, attachmentId.ToString());
        if (File.Exists(path)) File.Delete(path);
    }
}
