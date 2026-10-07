using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Pms.Api.Auth;
using Pms.Api.Activity;
using Pms.Domain.Entities;
using Pms.Infrastructure.Persistence.EfCore;
using Pms.Api.Realtime;
namespace Pms.Api.Controllers.Rest.V1;
[ApiController, Authorize, Route("api/v1/tasks")]
public sealed class TasksController(PmsDbContext db, AppMail mail, RealtimePublisher realtime) : ControllerBase
{
    private static readonly string[] Statuses = ["TO DO", "IN PROGRESS", "REVIEW", "DONE"];
    private static readonly string[] Priorities = ["URGENT", "HIGH", "MEDIUM", "LOW"];
    private Task<bool> Access(Guid id, bool write, CancellationToken ct) =>
        WorkspaceAuthorization.CanAccessProjectAsync(db, id, CurrentUser.Id(User), write, ct);
    [HttpGet]
    public async Task<IActionResult> List(Guid projectId, CancellationToken ct)
    {
        if (!await Access(projectId, false, ct)) return Forbid();
        return Ok(new { success = true, data = await db.Tasks.AsNoTracking().Where(x => x.ProjectId == projectId && x.ParentTaskId == null && x.DeletedAt == null).OrderBy(x => x.DueDate).Select(x => new { x.Id, x.ProjectId, x.ParentTaskId, x.Title, x.Description, x.Status, x.Priority, x.StartDate, x.DueDate, x.CreatedAt, x.CompletedAt, assigneeIds = x.Assignees.Select(a => a.UserId).ToArray(), subtaskCount = db.Tasks.Count(child => child.ParentTaskId == x.Id && child.DeletedAt == null), completedSubtaskCount = db.Tasks.Count(child => child.ParentTaskId == x.Id && child.DeletedAt == null && child.Status == "DONE") }).ToListAsync(ct) });
    }
    [HttpPost("/api/v1/projects/{projectId:guid}/tasks")]
    public async Task<IActionResult> Create(Guid projectId, CreateTaskRequest r, CancellationToken ct)
    {
        if (!await Access(projectId, true, ct)) return Forbid();
        if (string.IsNullOrWhiteSpace(r.Title) || !Statuses.Contains(r.Status ?? "TO DO") || !Priorities.Contains(r.Priority ?? "MEDIUM") || r.DueDate < r.StartDate) return BadRequest(new { message = "Check the title, status, priority, and dates." });
        var ids = r.AssigneeIds.Distinct().ToArray();
        if (await db.ProjectMembers.CountAsync(x => x.ProjectId == projectId && ids.Contains(x.UserId) && x.Status == "active", ct) != ids.Length) return BadRequest(new { message = "Assignees must be project members." });
        if (r.ParentTaskId is not null && !await db.Tasks.AnyAsync(x => x.Id == r.ParentTaskId && x.ProjectId == projectId && x.ParentTaskId == null && x.DeletedAt == null, ct)) return BadRequest(new { message = "The parent task is invalid." });
        var task = new WorkTask { Id = Guid.NewGuid(), ProjectId = projectId, ParentTaskId = r.ParentTaskId, Title = r.Title.Trim(), Description = r.Description, Status = r.Status ?? "TO DO", Priority = r.Priority ?? "MEDIUM", StartDate = r.StartDate, DueDate = r.DueDate, CreatedBy = CurrentUser.Id(User), CompletedAt = r.Status == "DONE" ? DateTime.UtcNow : null };
        foreach (var id in ids) { task.Assignees.Add(new TaskAssignee { Id = Guid.NewGuid(), UserId = id }); Notify(id, task); }
        db.Tasks.Add(task);
        await RecordActivityAsync(task, "Tasks", task.ParentTaskId is null ? "task.created" : "subtask.created", task.ParentTaskId is null ? $"created task \"{task.Title}\"" : $"added subtask \"{task.Title}\"", ct);
        foreach (var userId in ids)
        {
            var name = await db.Users.AsNoTracking().Where(user => user.Id == userId).Select(user => user.FirstName + " " + user.LastName).SingleAsync(ct);
            await RecordActivityAsync(task, "Tasks", "task.assigned", $"assigned task \"{task.Title}\" to {name}", ct);
        }
        await db.SaveChangesAsync(ct); await Publish(task.ProjectId, "tasks", ct); return Ok(new { task.Id });
    }
    [HttpGet("{id:guid}/subtasks")]
    public async Task<IActionResult> Subtasks(Guid id, CancellationToken ct)
    {
        var task = await db.Tasks.AsNoTracking().SingleOrDefaultAsync(x => x.Id == id && x.DeletedAt == null, ct);
        if (task is null) return NotFound();
        if (!await Access(task.ProjectId, false, ct)) return Forbid();
        return Ok(await db.Tasks.AsNoTracking().Where(x => x.ParentTaskId == id && x.DeletedAt == null).OrderBy(x => x.CreatedAt).Select(x => new { x.Id, x.Title, x.Status, x.CreatedAt, x.CompletedAt }).ToListAsync(ct));
    }
    [HttpGet("{id:guid}/activity")]
    public async Task<IActionResult> Activity(Guid id, CancellationToken ct)
    {
        var task = await db.Tasks.AsNoTracking().SingleOrDefaultAsync(x => x.Id == id && x.DeletedAt == null, ct);
        if (task is null) return NotFound();
        if (!await Access(task.ProjectId, false, ct)) return Forbid();
        var items = new List<TaskActivityItem> { new(task.CreatedAt, "Task created", null) };
        var comments = await db.Comments.AsNoTracking().Where(x => x.TaskId == id && x.DeletedAt == null).OrderByDescending(x => x.CreatedAt).Take(20).Select(x => new { x.CreatedAt, x.Content }).ToListAsync(ct);
        items.AddRange(comments.Select(x => new TaskActivityItem(x.CreatedAt, "Comment added", x.Content.Length > 140 ? x.Content[..140] + "…" : x.Content)));
        items.AddRange(await db.Tasks.AsNoTracking().Where(x => x.ParentTaskId == id && x.DeletedAt == null).Select(x => new TaskActivityItem(x.CreatedAt, "Subtask added", x.Title)).ToListAsync(ct));
        items.AddRange(await db.Tasks.AsNoTracking().Where(x => x.ParentTaskId == id && x.CompletedAt != null && x.DeletedAt == null).Select(x => new TaskActivityItem(x.CompletedAt!.Value, "Subtask completed", x.Title)).ToListAsync(ct));
        return Ok(items.OrderByDescending(x => x.CreatedAt).Take(30));
    }
    [HttpPost("{id:guid}/subtasks")]
    public async Task<IActionResult> CreateSubtask(Guid id, SubtaskRequest request, CancellationToken ct)
    {
        var parent = await db.Tasks.SingleOrDefaultAsync(x => x.Id == id && x.ParentTaskId == null && x.DeletedAt == null, ct);
        if (parent is null) return NotFound();
        if (!await Access(parent.ProjectId, true, ct)) return Forbid();
        if (string.IsNullOrWhiteSpace(request.Title)) return BadRequest(new { message = "Enter a subtask title." });
        var subtask = new WorkTask { Id = Guid.NewGuid(), ProjectId = parent.ProjectId, ParentTaskId = parent.Id, Title = request.Title.Trim(), Status = "TO DO", Priority = parent.Priority, CreatedBy = CurrentUser.Id(User) };
        db.Tasks.Add(subtask); parent.UpdatedAt = DateTime.UtcNow;
        await RecordActivityAsync(subtask, "Tasks", "subtask.created", $"added subtask \"{subtask.Title}\"", ct);
        await db.SaveChangesAsync(ct); await Publish(subtask.ProjectId, "tasks", ct); return Ok(new { subtask.Id });
    }
    [HttpPatch("{id:guid}/subtasks/{subtaskId:guid}")]
    public async Task<IActionResult> UpdateSubtask(Guid id, Guid subtaskId, SubtaskUpdateRequest request, CancellationToken ct)
    {
        var subtask = await db.Tasks.SingleOrDefaultAsync(x => x.Id == subtaskId && x.ParentTaskId == id && x.DeletedAt == null, ct);
        if (subtask is null) return NotFound();
        if (!await Access(subtask.ProjectId, true, ct)) return Forbid();
        subtask.Status = request.Done ? "DONE" : "TO DO"; subtask.CompletedAt = request.Done ? DateTime.UtcNow : null; subtask.UpdatedAt = DateTime.UtcNow;
        var parent = await db.Tasks.SingleAsync(x => x.Id == id, ct); parent.UpdatedAt = DateTime.UtcNow;
        await RecordActivityAsync(subtask, "Tasks", request.Done ? "subtask.completed" : "subtask.reopened", request.Done ? $"completed subtask \"{subtask.Title}\"" : $"reopened subtask \"{subtask.Title}\"", ct);
        await db.SaveChangesAsync(ct); await Publish(subtask.ProjectId, "tasks", ct); return NoContent();
    }
    [HttpPatch("{id:guid}")]
    public async Task<IActionResult> Update(Guid id, UpdateTaskRequest r, CancellationToken ct)
    {
        var task = await db.Tasks.Include(x => x.Assignees).SingleOrDefaultAsync(x => x.Id == id && x.DeletedAt == null, ct);
        if (task is null) return NotFound();
        if (!await Access(task.ProjectId, true, ct)) return Forbid();
        if (r.Title is not null && string.IsNullOrWhiteSpace(r.Title) || r.Status is not null && !Statuses.Contains(r.Status) || r.Priority is not null && !Priorities.Contains(r.Priority)) return BadRequest(new { message = "Check the title, status, and priority." });
        var oldTitle = task.Title; var oldStatus = task.Status; var oldPriority = task.Priority; var oldDueDate = task.DueDate;
        var oldAssigneeIds = task.Assignees.Select(x => x.UserId).ToHashSet();
        task.Title = r.Title?.Trim() ?? task.Title; task.Description = r.Description ?? task.Description; task.Status = r.Status ?? task.Status; task.Priority = r.Priority ?? task.Priority;
        task.DueDate = r.ClearDueDate ? null : r.DueDate ?? task.DueDate; task.StartDate = r.ClearStartDate ? null : r.StartDate ?? task.StartDate;
        if (task.DueDate < task.StartDate) return BadRequest(new { message = "Due date must be on or after the start date." });
        task.CompletedAt = task.Status == "DONE" ? task.CompletedAt ?? DateTime.UtcNow : null; task.UpdatedAt = DateTime.UtcNow;
        if (r.AssigneeIds is not null)
        {
            var ids = r.AssigneeIds.Distinct().ToArray();
            if (await db.ProjectMembers.CountAsync(x => x.ProjectId == task.ProjectId && ids.Contains(x.UserId) && x.Status == "active", ct) != ids.Length) return BadRequest(new { message = "Assignees must be project members." });
            foreach (var old in task.Assignees.Where(x => !ids.Contains(x.UserId)).ToArray()) db.TaskAssignees.Remove(old);
            foreach (var uid in ids.Where(uid => !task.Assignees.Any(a => a.UserId == uid))) { task.Assignees.Add(new TaskAssignee { Id = Guid.NewGuid(), UserId = uid }); Notify(uid, task); }
        }
        if (oldStatus != task.Status) await RecordActivityAsync(task, "Tasks", task.Status == "DONE" ? "task.completed" : task.Status == "TO DO" && oldStatus == "DONE" ? "task.reopened" : "task.status_changed", $"changed task \"{task.Title}\" status from {oldStatus} to {task.Status}", ct);
        if (oldPriority != task.Priority) await RecordActivityAsync(task, "Tasks", "task.priority_changed", $"changed task \"{task.Title}\" priority from {oldPriority} to {task.Priority}", ct);
        if (oldDueDate != task.DueDate) await RecordActivityAsync(task, "Tasks", "task.due_date_changed", $"changed the due date for task \"{task.Title}\"", ct);
        if (oldTitle != task.Title || r.Description is not null) await RecordActivityAsync(task, "Tasks", "task.updated", $"updated task \"{task.Title}\"", ct);
        if (r.AssigneeIds is not null)
        {
            var newIds = r.AssigneeIds.ToHashSet();
            foreach (var userId in oldAssigneeIds.Except(newIds))
            {
                var name = await db.Users.AsNoTracking().Where(user => user.Id == userId).Select(user => user.FirstName + " " + user.LastName).SingleAsync(ct);
                await RecordActivityAsync(task, "Tasks", "task.assignee_removed", $"removed {name} from task \"{task.Title}\"", ct);
            }
            foreach (var userId in newIds.Except(oldAssigneeIds))
            {
                var name = await db.Users.AsNoTracking().Where(user => user.Id == userId).Select(user => user.FirstName + " " + user.LastName).SingleAsync(ct);
                await RecordActivityAsync(task, "Tasks", "task.assigned", $"assigned task \"{task.Title}\" to {name}", ct);
            }
        }
        await db.SaveChangesAsync(ct); await Publish(task.ProjectId, "tasks", ct); return Ok(new { task.Id });
    }
    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id, CancellationToken ct)
    {
        var task = await db.Tasks.SingleOrDefaultAsync(x => x.Id == id && x.DeletedAt == null, ct); if (task is null) return NotFound();
        if (!await (from projectMember in db.ProjectMembers
            join project in db.Projects on projectMember.ProjectId equals project.Id
            join organizationMember in db.OrganizationMembers on project.OrganizationId equals organizationMember.OrganizationId
            where projectMember.ProjectId == task.ProjectId && projectMember.UserId == CurrentUser.Id(User) && projectMember.Status == "active"
                && organizationMember.UserId == CurrentUser.Id(User) && organizationMember.Status == "active" && organizationMember.Role != "GUEST"
                && project.ArchivedAt == null && project.DeletedAt == null
                && (projectMember.Role == "PROJECT_MANAGER" || projectMember.Role == "TEAM_LEAD")
            select projectMember).AnyAsync(ct)) return Forbid();
        task.DeletedAt = DateTime.UtcNow;
        await RecordActivityAsync(task, "Tasks", "task.deleted", $"deleted task \"{task.Title}\"", ct);
        await db.SaveChangesAsync(ct); await Publish(task.ProjectId, "tasks", ct); return NoContent();
    }
    [HttpPost("{id:guid}/restore")]
    public async Task<IActionResult> Restore(Guid id, CancellationToken ct)
    {
        var task = await db.Tasks.SingleOrDefaultAsync(x => x.Id == id && x.DeletedAt != null && x.DeletedAt >= DateTime.UtcNow.AddDays(-30), ct);
        if (task is null) return NotFound();
        if (!await (from projectMember in db.ProjectMembers
            join project in db.Projects on projectMember.ProjectId equals project.Id
            join organizationMember in db.OrganizationMembers on project.OrganizationId equals organizationMember.OrganizationId
            where projectMember.ProjectId == task.ProjectId && projectMember.UserId == CurrentUser.Id(User) && projectMember.Status == "active"
                && organizationMember.UserId == CurrentUser.Id(User) && organizationMember.Status == "active" && organizationMember.Role != "GUEST"
                && project.ArchivedAt == null && project.DeletedAt == null && (projectMember.Role == "PROJECT_MANAGER" || projectMember.Role == "TEAM_LEAD")
            select projectMember).AnyAsync(ct)) return Forbid();
        task.DeletedAt = null; task.UpdatedAt = DateTime.UtcNow;
        await RecordActivityAsync(task, "Tasks", "task.restored", $"restored task \"{task.Title}\"", ct);
        await db.SaveChangesAsync(ct); await Publish(task.ProjectId, "tasks", ct); return NoContent();
    }
    private async Task RecordActivityAsync(WorkTask task, string category, string action, string description, CancellationToken ct)
    {
        var project = await db.Projects.AsNoTracking().Where(x => x.Id == task.ProjectId)
            .Select(x => new { x.OrganizationId, x.Name }).SingleAsync(ct);
        await ActivityRecorder.RecordAsync(db, User, Request, project.OrganizationId, category, action,
            task.ParentTaskId is null ? "task" : "subtask", task.Id, task.Title,
            $"{description} in project \"{project.Name}\"", ct, task.ProjectId);
    }
    private async Task Publish(Guid projectId, string area, CancellationToken ct)
    {
        var organizationId = await db.Projects.AsNoTracking().Where(project => project.Id == projectId)
            .Select(project => project.OrganizationId).SingleAsync(ct);
        await realtime.ProjectChanged(organizationId, projectId, area, ct);
    }
    // Queues an in-app notification and fires a task-assigned email.
    // The user's email is looked up synchronously on the same DbContext call
    // that's already in scope, then the send is dispatched to a background
    // thread — so the HTTP response is never delayed and the DbContext is
    // never touched after the request ends.
    private void Notify(Guid uid, WorkTask task)
    {
        db.Notifications.Add(new Notification
        {
            Id = Guid.NewGuid(),
            UserId = uid,
            Type = "TASK_ASSIGNED",
            Message = $"You were assigned to {task.Title}.",
            EntityType = "TASK",
            RelatedId = task.Id
        });

        // Look up the assignee email NOW — DbContext is alive and in scope.
        var userEmail = db.Users
            .Where(u => u.Id == uid)
            .Select(u => new { u.Email, u.FirstName })
            .FirstOrDefault();

        if (userEmail is null) return;

        // Capture primitives so nothing from the request scope leaks into the thread.
        var toEmail   = userEmail.Email;
        var firstName = userEmail.FirstName;
        var taskTitle = task.Title;
        var projectId = task.ProjectId;
        var taskId    = task.Id;
        var appMail   = mail;

        // Fire-and-forget — AppMail handles all delivery failures internally.
        _ = Task.Run(() => appMail.SendTaskAssigned(toEmail, firstName, taskTitle, projectId, taskId));
    }
}
public sealed record CreateTaskRequest([Required, StringLength(300)] string Title, string? Description, string? Status, string? Priority, DateTime? DueDate, [Required] IReadOnlyCollection<Guid> AssigneeIds, DateTime? StartDate = null, Guid? ParentTaskId = null);
public sealed record UpdateTaskRequest([StringLength(300)] string? Title, string? Description, string? Status, string? Priority, DateTime? DueDate, IReadOnlyCollection<Guid>? AssigneeIds = null, DateTime? StartDate = null, bool ClearDueDate = false, bool ClearStartDate = false);
public sealed record SubtaskRequest([Required, StringLength(300)] string Title);
public sealed record SubtaskUpdateRequest(bool Done);
public sealed record TaskActivityItem(DateTime CreatedAt, string Action, string? Detail);
