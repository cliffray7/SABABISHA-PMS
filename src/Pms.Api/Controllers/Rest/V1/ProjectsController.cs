using System.ComponentModel.DataAnnotations;
using System.Data;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using Pms.Api.Auth;
using Pms.Api.Activity;
using Pms.Domain.Entities;
using Pms.Infrastructure.Persistence.EfCore;
using Pms.Api.Realtime;
namespace Pms.Api.Controllers.Rest.V1;

[ApiController, Authorize, Route("api/v1/projects")]
public sealed class ProjectsController(PmsDbContext db, RealtimePublisher realtime) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> List(Guid organizationId, CancellationToken ct) => Ok(await (from p in db.Projects join m in db.ProjectMembers on p.Id equals m.ProjectId join om in db.OrganizationMembers on p.OrganizationId equals om.OrganizationId where p.OrganizationId == organizationId && p.ArchivedAt == null && p.DeletedAt == null && m.UserId == CurrentUser.Id(User) && m.Status == "active" && om.UserId == CurrentUser.Id(User) && om.Status == "active" select new { p.Id, p.OrganizationId, p.Name, p.Description, p.Status, p.StartDate, p.DueDate, m.Role }).ToListAsync(ct));
    [HttpPost]
    public async Task<IActionResult> Create(CreateProjectRequest request, CancellationToken ct)
    {
        if (!await db.OrganizationMembers.AnyAsync(x => x.OrganizationId == request.OrganizationId && x.UserId == CurrentUser.Id(User) && x.Status == "active" && x.Role != "GUEST", ct)) return Forbid();
        if (!Valid(request.Name, request.Status, request.StartDate, request.DueDate)) return BadRequest(new { message = "Enter a project name, valid status, and due date on or after the start date." });
        var p = new Project { Id = Guid.NewGuid(), OrganizationId = request.OrganizationId, OwnerId = CurrentUser.Id(User), Name = request.Name.Trim(), Description = request.Description, Status = request.Status, StartDate = request.StartDate, DueDate = request.DueDate };
        db.Projects.Add(p); db.ProjectMembers.Add(new ProjectMember { Id = Guid.NewGuid(), ProjectId = p.Id, UserId = CurrentUser.Id(User), Role = "PROJECT_MANAGER" });
        await ActivityRecorder.RecordAsync(db, User, Request, p.OrganizationId, "Projects", "project.created", "project", p.Id, p.Name, $"created project \"{p.Name}\"", ct, p.Id);
        await db.SaveChangesAsync(ct); await realtime.OrganizationChanged(p.OrganizationId, "projects", ct); return Ok(p);
    }
    [HttpGet("{id:guid}")]
    public async Task<IActionResult> Get(Guid id, CancellationToken ct)
    { if (!await Member(id, ct)) return Forbid(); return Ok(await db.Projects.SingleAsync(x => x.Id == id && x.DeletedAt == null, ct)); }
    [HttpPatch("{id:guid}")]
    public async Task<IActionResult> Update(Guid id, ProjectDetails request, CancellationToken ct)
    {
        if (!await Manager(id, ct)) return Forbid();
        if (!Valid(request.Name, request.Status, request.StartDate, request.DueDate)) return BadRequest(new { message = "Check the name, status, and date range." });
        var p = await db.Projects.SingleAsync(x => x.Id == id, ct);
        var previousStatus = p.Status;
        p.Name = request.Name.Trim(); p.Description = request.Description; p.Status = request.Status; p.StartDate = request.StartDate; p.DueDate = request.DueDate; p.UpdatedAt = DateTime.UtcNow;
        var action = previousStatus == p.Status ? "project.updated" : "project.status_changed";
        await ActivityRecorder.RecordAsync(db, User, Request, p.OrganizationId, "Projects", action, "project", p.Id, p.Name, action == "project.status_changed" ? $"changed project \"{p.Name}\" status from {previousStatus} to {p.Status}" : $"updated project \"{p.Name}\"", ct, p.Id);
        await db.SaveChangesAsync(ct); await realtime.ProjectChanged(p.OrganizationId, p.Id, "projects", ct); return Ok(p);
    }
    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Archive(Guid id, CancellationToken ct)
    {
        if (!await Manager(id, ct)) return Forbid();
        var project = await db.Projects.SingleAsync(x => x.Id == id && x.DeletedAt == null, ct);
        project.ArchivedAt = DateTime.UtcNow;
        await ActivityRecorder.RecordAsync(db, User, Request, project.OrganizationId, "Projects", "project.archived", "project", project.Id, project.Name, $"archived project \"{project.Name}\"", ct, project.Id);
        await db.SaveChangesAsync(ct); await realtime.ProjectChanged(project.OrganizationId, project.Id, "projects", ct); return NoContent();
    }
    [HttpPost("{id:guid}/restore")]
    public async Task<IActionResult> Restore(Guid id, CancellationToken ct)
    {
        var project = await db.Projects.SingleOrDefaultAsync(x => x.Id == id
            && (x.DeletedAt != null ? x.DeletedAt >= DateTime.UtcNow.AddDays(-30) : x.ArchivedAt != null), ct);
        if (project is null) return NotFound();
        if (project.DeletedAt is not null)
        {
            if (!await CanManageDeletedProject(project.Id, ct)) return Forbid();
            project.DeletedAt = null;
        }
        else
        {
            if (!await Manager(id, ct)) return Forbid();
            project.ArchivedAt = null;
        }
        project.UpdatedAt = DateTime.UtcNow;
        await ActivityRecorder.RecordAsync(db, User, Request, project.OrganizationId, "Projects", "project.restored", "project", project.Id, project.Name, $"restored project \"{project.Name}\"", ct, project.Id);
        await db.SaveChangesAsync(ct); await realtime.ProjectChanged(project.OrganizationId, project.Id, "projects", ct); return NoContent();
    }
    [HttpDelete("{id:guid}/trash")]
    public async Task<IActionResult> MoveToTrash(Guid id, CancellationToken ct)
    {
        if (!await Manager(id, ct)) return Forbid();
        var project = await db.Projects.SingleOrDefaultAsync(x => x.Id == id && x.DeletedAt == null, ct);
        if (project is null) return NotFound();
        project.DeletedAt = DateTime.UtcNow;
        project.UpdatedAt = DateTime.UtcNow;
        await ActivityRecorder.RecordAsync(db, User, Request, project.OrganizationId, "Projects", "project.deleted", "project", project.Id, project.Name, $"moved project \"{project.Name}\" to Trash", ct, project.Id);
        await db.SaveChangesAsync(ct);
        await realtime.ProjectChanged(project.OrganizationId, project.Id, "projects", ct);
        return NoContent();
    }
    [HttpGet("{id:guid}/members")]
    public async Task<IActionResult> Members(Guid id, CancellationToken ct)
    {
        if (!await Member(id, ct)) return Forbid();
        return Ok(await (from m in db.ProjectMembers join u in db.Users on m.UserId equals u.Id where m.ProjectId == id && m.Status == "active" select new { m.Id, m.UserId, u.FirstName, u.LastName, u.Email, u.AvatarUrl, m.Role }).ToListAsync(ct));
    }
    [HttpPost("{id:guid}/members")]
    public async Task<IActionResult> AddMember(Guid id, AddProjectMemberRequest request, CancellationToken ct)
    {
        if (!await Manager(id, ct)) return Forbid();
        if (!new[] { "PROJECT_MANAGER", "TEAM_LEAD", "CONTRIBUTOR", "VIEWER" }.Contains(request.Role)) return BadRequest(new { message = "Invalid project role." });
        var project = await db.Projects.SingleAsync(x => x.Id == id, ct);
        var orgMember = await db.OrganizationMembers.SingleOrDefaultAsync(x => x.OrganizationId == project.OrganizationId && x.UserId == request.UserId && x.Status == "active", ct);
        if (orgMember is null || orgMember.Role == "GUEST" && request.Role != "VIEWER") return BadRequest(new { message = "Choose an organization member. Guests can only be viewers." });
        var existing = await db.ProjectMembers.SingleOrDefaultAsync(x => x.ProjectId == id && x.UserId == request.UserId, ct);
        if (existing?.Status == "active") return Conflict(new { message = "Already a project member." });
        if (existing is null) db.ProjectMembers.Add(new ProjectMember { Id = Guid.NewGuid(), ProjectId = id, UserId = request.UserId, Role = request.Role });
        else { existing.Status = "active"; existing.Role = request.Role; }
        var addedUser = await db.Users.AsNoTracking().Where(x => x.Id == request.UserId).Select(x => new { x.FirstName, x.LastName }).SingleAsync(ct);
        var addedName = $"{addedUser.FirstName} {addedUser.LastName}";
        await ActivityRecorder.RecordAsync(db, User, Request, project.OrganizationId, "People", "project.member_added", "user", request.UserId, addedName, $"added {addedName} to project \"{project.Name}\"", ct, project.Id);
        await db.SaveChangesAsync(ct); await realtime.ProjectChanged(project.OrganizationId, project.Id, "members", ct); return NoContent();
    }
    [HttpDelete("{id:guid}/members/{userId:guid}")]
    public async Task<IActionResult> RemoveMember(Guid id, Guid userId, CancellationToken ct)
    {
        var strategy = db.Database.CreateExecutionStrategy();
        try
        {
            return await strategy.ExecuteAsync<IActionResult>(async () =>
            {
                // A transient SQL Server deadlock retries this delegate on the same DbContext.
                // Discard tracked mutations from the rolled-back attempt before re-reading state.
                db.ChangeTracker.Clear();
                await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct);
                if (!await Manager(id, ct)) return Forbid();
                if (userId == CurrentUser.Id(User)) return BadRequest(new { message = "You cannot remove yourself from the project." });
                var member = await db.ProjectMembers.SingleOrDefaultAsync(x => x.ProjectId == id && x.UserId == userId && x.Status == "active", ct);
                if (member is null) return NotFound();
                var project = await db.Projects.SingleOrDefaultAsync(x => x.Id == id && x.ArchivedAt == null && x.DeletedAt == null, ct);
                if (project is null) return NotFound();
                if (project.OwnerId == userId)
                    return RoleUpdateError(StatusCodes.Status409Conflict, "project_owner_transfer_required",
                        "Transfer project ownership before removing its owner.");
                var activeManagers = await ActiveManagerCount(id, project.OrganizationId, ct);
                var removedManagerIsActive = member.Role == "PROJECT_MANAGER"
                    && await db.OrganizationMembers.AnyAsync(x => x.OrganizationId == project.OrganizationId
                        && x.UserId == userId && x.Status == "active" && x.Role != "GUEST", ct)
                    && await db.Users.AnyAsync(x => x.Id == userId && x.Status == "active", ct);
                if (activeManagers - (removedManagerIsActive ? 1 : 0) < 1)
                    return RoleUpdateError(StatusCodes.Status400BadRequest, "project_must_retain_manager",
                        "The project must retain at least one active project manager.");
                var hasOpenAssignments = await (from assignee in db.TaskAssignees
                                                 join task in db.Tasks on assignee.TaskId equals task.Id
                                                 where assignee.UserId == userId && assignee.Status == "active"
                                                     && task.ProjectId == id && task.DeletedAt == null && task.Status != "DONE"
                                                 select assignee.Id).AnyAsync(ct);
                if (hasOpenAssignments)
                    return RoleUpdateError(StatusCodes.Status409Conflict, "project_member_open_tasks_require_resolution",
                        "Reassign or clear this member's open task assignments before removing them.");
                member.Status = "inactive";
                var removedUser = await db.Users.AsNoTracking().Where(x => x.Id == userId).Select(x => new { x.FirstName, x.LastName }).SingleAsync(ct);
                var removedName = $"{removedUser.FirstName} {removedUser.LastName}";
                await ActivityRecorder.InactivateTaskAssignmentsAsync(db, User, Request, project.OrganizationId, userId,
                    removedName, "the project membership was removed", id, ct);
                await ActivityRecorder.RecordAsync(db, User, Request, project.OrganizationId, "People", "project.member_removed", "user", userId, removedName, $"removed {removedName} from project \"{project.Name}\"", ct, project.Id);
                await db.SaveChangesAsync(ct);
                await tx.CommitAsync(ct);
                await realtime.ProjectChanged(project.OrganizationId, project.Id, "members", ct);
                return NoContent();
            });
        }
        catch (RetryLimitExceededException)
        {
            return RoleRetryConflict();
        }
    }

    [HttpPatch("{id:guid}/members/{userId:guid}")]
    public async Task<IActionResult> UpdateMemberRole(Guid id, Guid userId, UpdateProjectMemberRoleRequest request, CancellationToken ct)
    {
        var strategy = db.Database.CreateExecutionStrategy();
        try
        {
            return await strategy.ExecuteAsync<IActionResult>(async () =>
            {
                db.ChangeTracker.Clear();
                await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct);
                var project = await db.Projects.SingleOrDefaultAsync(x => x.Id == id && x.ArchivedAt == null && x.DeletedAt == null, ct);
                if (project is null) return NotFound();
                var actorId = CurrentUser.Id(User);
                var actor = await (from organizationMember in db.OrganizationMembers
                                   join actorUser in db.Users on organizationMember.UserId equals actorUser.Id
                                   where organizationMember.OrganizationId == project.OrganizationId
                                       && organizationMember.UserId == actorId && organizationMember.Status == "active"
                                       && actorUser.Status == "active"
                                   select new { organizationMember.Role }).SingleOrDefaultAsync(ct);
                if (actor is null || actor.Role == "GUEST")
                    return RoleUpdateError(StatusCodes.Status403Forbidden, "project_role_update_forbidden",
                        "You do not have permission to change project member roles.");
                var organizationAdmin = actor.Role is "OWNER" or "ADMIN";
                var projectManager = await db.ProjectMembers.AnyAsync(x => x.ProjectId == id && x.UserId == actorId
                    && x.Status == "active" && x.Role == "PROJECT_MANAGER", ct);
                if (request.Role == "PROJECT_MANAGER" && !organizationAdmin && !projectManager)
                    return RoleUpdateError(StatusCodes.Status403Forbidden, "project_manager_grant_forbidden",
                        "Only organization admins or project managers can grant the project manager role.");
                if (!organizationAdmin && !projectManager)
                    return RoleUpdateError(StatusCodes.Status403Forbidden, "project_role_update_forbidden",
                        "You do not have permission to change project member roles.");
                if (!ProjectRoles.Contains(request.Role))
                    return RoleUpdateError(StatusCodes.Status400BadRequest, "invalid_project_role", "Invalid project role.");

                var target = await (from projectMember in db.ProjectMembers
                                    join organizationMember in db.OrganizationMembers on project.OrganizationId equals organizationMember.OrganizationId
                                    where projectMember.ProjectId == id && projectMember.UserId == userId && projectMember.Status == "active"
                                        && organizationMember.UserId == userId && organizationMember.Status == "active"
                                    select new { ProjectMember = projectMember, OrganizationRole = organizationMember.Role })
                    .SingleOrDefaultAsync(ct);
                if (target is null) return NotFound();
                if (project.OwnerId == userId && request.Role != "PROJECT_MANAGER")
                    return RoleUpdateError(StatusCodes.Status409Conflict, "project_owner_transfer_required",
                        "Transfer project ownership before changing the owner's project manager role.");
                if (target.OrganizationRole == "GUEST" && request.Role != "VIEWER")
                    return RoleUpdateError(StatusCodes.Status400BadRequest, "guest_project_role_must_be_viewer",
                        "Organization guests can only have the viewer project role.");
                var previousRole = target.ProjectMember.Role;
                if (previousRole == request.Role)
                {
                    await tx.CommitAsync(ct);
                    return NoContent();
                }
                if (userId == actorId && previousRole != "PROJECT_MANAGER")
                    return RoleUpdateError(StatusCodes.Status400BadRequest, "self_role_change_not_allowed",
                        "You may only demote yourself from project manager when another active manager remains.");
                var activeManagers = await ActiveManagerCount(id, project.OrganizationId, ct);
                var targetUserIsActive = await db.Users.AnyAsync(x => x.Id == userId && x.Status == "active", ct);
                var targetIsCountedManager = previousRole == "PROJECT_MANAGER" && target.OrganizationRole != "GUEST" && targetUserIsActive;
                var managerCountAfterChange = activeManagers - (targetIsCountedManager ? 1 : 0)
                    + (request.Role == "PROJECT_MANAGER" && targetUserIsActive ? 1 : 0);
                if (managerCountAfterChange < 1)
                    return RoleUpdateError(StatusCodes.Status400BadRequest, "project_must_retain_manager",
                        "The project must retain at least one active project manager.");

                target.ProjectMember.Role = request.Role;
                var targetUser = await db.Users.AsNoTracking().Where(x => x.Id == userId)
                    .Select(x => new { x.FirstName, x.LastName }).SingleAsync(ct);
                var actorName = await db.Users.AsNoTracking().Where(x => x.Id == actorId)
                    .Select(x => x.FirstName + " " + x.LastName).SingleAsync(ct);
                var correlationId = Request.Headers["X-Correlation-ID"].FirstOrDefault();
                if (string.IsNullOrWhiteSpace(correlationId) || correlationId.Length > 128)
                    correlationId = HttpContext.TraceIdentifier;
                db.AdminAuditEvents.Add(new AdminAuditEvent
                {
                    Id = Guid.NewGuid(),
                    ActorId = actorId,
                    ActorDisplayName = actorName,
                    Action = "project.member_role_changed",
                    TargetType = "user",
                    TargetId = userId,
                    TargetDisplayName = $"{targetUser.FirstName} {targetUser.LastName} in {project.Name}: {previousRole} -> {request.Role}",
                    Outcome = "succeeded",
                    Reason = $"project_id={project.Id}; old_role={previousRole}; new_role={request.Role}",
                    CorrelationId = correlationId,
                    OccurredAt = DateTimeOffset.UtcNow
                });
                await db.SaveChangesAsync(ct);
                await tx.CommitAsync(ct);
                await realtime.ProjectChanged(project.OrganizationId, project.Id, "members", ct);
                return NoContent();
            });
        }
        catch (RetryLimitExceededException)
        {
            return RoleRetryConflict();
        }
    }

    private static readonly string[] ProjectRoles = ["PROJECT_MANAGER", "TEAM_LEAD", "CONTRIBUTOR", "VIEWER"];

    private ObjectResult RoleUpdateError(int statusCode, string code, string message) =>
        StatusCode(statusCode, new { code, message });

    private ObjectResult RoleRetryConflict() => RoleUpdateError(StatusCodes.Status409Conflict,
        "project_role_update_conflict", "The project is busy. Refresh member data, then retry.");

    private Task<int> ActiveManagerCount(Guid projectId, Guid organizationId, CancellationToken ct) =>
        (from projectMember in db.ProjectMembers
         join organizationMember in db.OrganizationMembers on projectMember.UserId equals organizationMember.UserId
         join user in db.Users on projectMember.UserId equals user.Id
         where projectMember.ProjectId == projectId && projectMember.Role == "PROJECT_MANAGER"
             && projectMember.Status == "active" && organizationMember.OrganizationId == organizationId
             && organizationMember.Status == "active" && organizationMember.Role != "GUEST" && user.Status == "active"
         select projectMember.UserId).Distinct().CountAsync(ct);
    private Task<bool> Member(Guid id, CancellationToken ct) => (from projectMember in db.ProjectMembers
                                                                 join project in db.Projects on projectMember.ProjectId equals project.Id
                                                                 join organizationMember in db.OrganizationMembers on project.OrganizationId equals organizationMember.OrganizationId
                                                                 where projectMember.ProjectId == id && projectMember.UserId == CurrentUser.Id(User) && projectMember.Status == "active"
                                                                     && organizationMember.UserId == CurrentUser.Id(User) && organizationMember.Status == "active" && project.DeletedAt == null
                                                                 select projectMember).AnyAsync(ct);
    private Task<bool> Manager(Guid id, CancellationToken ct) => (from projectMember in db.ProjectMembers
                                                                  join project in db.Projects on projectMember.ProjectId equals project.Id
                                                                  join organizationMember in db.OrganizationMembers on project.OrganizationId equals organizationMember.OrganizationId
                                                                  where projectMember.ProjectId == id && projectMember.UserId == CurrentUser.Id(User) && projectMember.Status == "active"
                                                                      && organizationMember.UserId == CurrentUser.Id(User) && organizationMember.Status == "active"
                                                                      && organizationMember.Role != "GUEST" && project.DeletedAt == null && (projectMember.Role == "PROJECT_MANAGER" || projectMember.Role == "TEAM_LEAD")
                                                                  select projectMember).AnyAsync(ct);
    private Task<bool> CanManageDeletedProject(Guid id, CancellationToken ct) => (from projectMember in db.ProjectMembers
                                                                                  join project in db.Projects on projectMember.ProjectId equals project.Id
                                                                                  join organizationMember in db.OrganizationMembers on project.OrganizationId equals organizationMember.OrganizationId
                                                                                  where projectMember.ProjectId == id && projectMember.UserId == CurrentUser.Id(User) && projectMember.Status == "active"
                                                                                      && organizationMember.UserId == CurrentUser.Id(User) && organizationMember.Status == "active"
                                                                                      && organizationMember.Role != "GUEST" && (projectMember.Role == "PROJECT_MANAGER" || projectMember.Role == "TEAM_LEAD")
                                                                                  select projectMember).AnyAsync(ct);
    private static bool Valid(string name, string status, DateTime? start, DateTime? due) => !string.IsNullOrWhiteSpace(name) && new[] { "PLANNING", "ACTIVE", "ON_HOLD", "COMPLETED" }.Contains(status) && !(due < start);
}
public sealed record CreateProjectRequest(Guid OrganizationId, [Required, StringLength(200)] string Name, string? Description, DateTime? StartDate = null, DateTime? DueDate = null, string Status = "PLANNING");
public sealed record ProjectDetails([Required, StringLength(200)] string Name, string? Description, DateTime? StartDate, DateTime? DueDate, [Required] string Status);
public sealed record AddProjectMemberRequest(Guid UserId, [Required] string Role);
public sealed record UpdateProjectMemberRoleRequest([Required] string Role);
