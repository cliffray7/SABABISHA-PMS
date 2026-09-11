using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Pms.Api.Auth;
using Pms.Domain.Entities;
using Pms.Infrastructure.Persistence.EfCore;
namespace Pms.Api.Controllers.Rest.V1;
[ApiController, Authorize, Route("api/v1/tasks")]
public sealed class TasksController(PmsDbContext db) : ControllerBase
{
    private static readonly string[] Statuses = ["TO DO", "IN PROGRESS", "REVIEW", "DONE"];
    private static readonly string[] Priorities = ["URGENT", "HIGH", "MEDIUM", "LOW"];
    private Task<bool> Access(Guid id, bool write, CancellationToken ct) => (from projectMember in db.ProjectMembers
        join project in db.Projects on projectMember.ProjectId equals project.Id
        join organizationMember in db.OrganizationMembers on project.OrganizationId equals organizationMember.OrganizationId
        where projectMember.ProjectId == id && projectMember.UserId == CurrentUser.Id(User) && projectMember.Status == "active"
            && organizationMember.UserId == CurrentUser.Id(User) && organizationMember.Status == "active"
            && project.ArchivedAt == null && (!write || projectMember.Role != "VIEWER")
        select projectMember).AnyAsync(ct);
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
        db.Tasks.Add(task); await db.SaveChangesAsync(ct); return Ok(new { task.Id });
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
        await db.SaveChangesAsync(ct); return Ok(new { subtask.Id });
    }
    [HttpPatch("{id:guid}/subtasks/{subtaskId:guid}")]
    public async Task<IActionResult> UpdateSubtask(Guid id, Guid subtaskId, SubtaskUpdateRequest request, CancellationToken ct)
    {
        var subtask = await db.Tasks.SingleOrDefaultAsync(x => x.Id == subtaskId && x.ParentTaskId == id && x.DeletedAt == null, ct);
        if (subtask is null) return NotFound();
        if (!await Access(subtask.ProjectId, true, ct)) return Forbid();
        subtask.Status = request.Done ? "DONE" : "TO DO"; subtask.CompletedAt = request.Done ? DateTime.UtcNow : null; subtask.UpdatedAt = DateTime.UtcNow;
        var parent = await db.Tasks.SingleAsync(x => x.Id == id, ct); parent.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct); return NoContent();
    }
    [HttpPatch("{id:guid}")]
    public async Task<IActionResult> Update(Guid id, UpdateTaskRequest r, CancellationToken ct)
    {
        var task = await db.Tasks.Include(x => x.Assignees).SingleOrDefaultAsync(x => x.Id == id && x.DeletedAt == null, ct);
        if (task is null) return NotFound();
        if (!await Access(task.ProjectId, true, ct)) return Forbid();
        if (r.Title is not null && string.IsNullOrWhiteSpace(r.Title) || r.Status is not null && !Statuses.Contains(r.Status) || r.Priority is not null && !Priorities.Contains(r.Priority)) return BadRequest(new { message = "Check the title, status, and priority." });
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
        await db.SaveChangesAsync(ct); return Ok(new { task.Id });
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
                && (projectMember.Role == "PROJECT_MANAGER" || projectMember.Role == "TEAM_LEAD")
            select projectMember).AnyAsync(ct)) return Forbid();
        task.DeletedAt = DateTime.UtcNow; await db.SaveChangesAsync(ct); return NoContent();
    }
    [HttpPost("{id:guid}/restore")]
    public async Task<IActionResult> Restore(Guid id, CancellationToken ct)
    {
        var task = await db.Tasks.SingleOrDefaultAsync(x => x.Id == id && x.DeletedAt != null, ct);
        if (task is null) return NotFound();
        if (!await (from projectMember in db.ProjectMembers
            join project in db.Projects on projectMember.ProjectId equals project.Id
            join organizationMember in db.OrganizationMembers on project.OrganizationId equals organizationMember.OrganizationId
            where projectMember.ProjectId == task.ProjectId && projectMember.UserId == CurrentUser.Id(User) && projectMember.Status == "active"
                && organizationMember.UserId == CurrentUser.Id(User) && organizationMember.Status == "active" && organizationMember.Role != "GUEST"
                && project.ArchivedAt == null && (projectMember.Role == "PROJECT_MANAGER" || projectMember.Role == "TEAM_LEAD")
            select projectMember).AnyAsync(ct)) return Forbid();
        task.DeletedAt = null; task.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct); return NoContent();
    }
    private void Notify(Guid uid, WorkTask task) => db.Notifications.Add(new Notification { Id = Guid.NewGuid(), UserId = uid, Type = "TASK_ASSIGNED", Message = $"You were assigned to {task.Title}.", EntityType = "TASK", RelatedId = task.Id });
}
public sealed record CreateTaskRequest([Required, StringLength(300)] string Title, string? Description, string? Status, string? Priority, DateTime? DueDate, [Required] IReadOnlyCollection<Guid> AssigneeIds, DateTime? StartDate = null, Guid? ParentTaskId = null);
public sealed record UpdateTaskRequest([StringLength(300)] string? Title, string? Description, string? Status, string? Priority, DateTime? DueDate, IReadOnlyCollection<Guid>? AssigneeIds = null, DateTime? StartDate = null, bool ClearDueDate = false, bool ClearStartDate = false);
public sealed record SubtaskRequest([Required, StringLength(300)] string Title);
public sealed record SubtaskUpdateRequest(bool Done);
public sealed record TaskActivityItem(DateTime CreatedAt, string Action, string? Detail);
