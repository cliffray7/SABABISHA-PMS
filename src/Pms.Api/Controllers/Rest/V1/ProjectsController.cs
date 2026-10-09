using System.ComponentModel.DataAnnotations;
using System.Data;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using Pms.Api.Auth;
using Pms.Api.Activity;
using Pms.Api.MemberRemoval;
using Pms.Domain.Entities;
using Pms.Infrastructure.Persistence.EfCore;
using Pms.Api.Realtime;
using Pms.Api.Progress;
namespace Pms.Api.Controllers.Rest.V1;

[ApiController, Authorize, Route("api/v1/projects")]
public sealed class ProjectsController(PmsDbContext db, RealtimePublisher realtime, AppMail? mail = null,
    ILogger<ProjectsController>? logger = null) : ControllerBase
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

    [HttpGet("{id:guid}/progress")]
    public async Task<IActionResult> GetProgress(Guid id, CancellationToken ct)
    {
        if (!await WorkspaceAuthorization.CanAccessProjectAsync(db, id, CurrentUser.Id(User), write: false, ct))
            return Forbid();

        var project = await (from candidate in db.Projects.AsNoTracking()
                             join organization in db.Organizations.AsNoTracking()
                                 on candidate.OrganizationId equals organization.Id
                             where candidate.Id == id && candidate.ArchivedAt == null && candidate.DeletedAt == null
                             select new { candidate.Id, candidate.Status, candidate.OrganizationId, organization.Timezone })
            .SingleOrDefaultAsync(ct);
        if (project is null) return Forbid();

        var tasks = await db.Tasks.AsNoTracking()
            .Where(task => task.ProjectId == id && task.ParentTaskId == null && task.DeletedAt == null)
            .Select(task => new ProjectProgressTask(task.Status, task.DueDate, null, null))
            .ToListAsync(ct);
        var calculatedAtUtc = DateTime.UtcNow;
        var result = ProjectProgressCalculator.Calculate(tasks, project.Timezone, calculatedAtUtc,
            project.OrganizationId, logger);

        return Ok(new
        {
            projectId = project.Id,
            projectStatus = project.Status,
            result.HasTasks,
            result.TotalEligibleTasks,
            result.CompletedTasks,
            result.ProgressPercent,
            result.OutstandingTaskCount,
            result.OverdueTaskCount,
            result.TimezoneIdUsed
        });
    }

    [HttpPatch("{id:guid}/owner")]
    public async Task<IActionResult> TransferOwner(Guid id, TransferProjectOwnerRequest request, CancellationToken ct)
    {
        var strategy = db.Database.CreateExecutionStrategy();
        try
        {
            return await strategy.ExecuteAsync<IActionResult>(async () =>
            {
                db.ChangeTracker.Clear();
                await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct);
                if (request.ExpectedOwnerId == Guid.Empty || request.NewOwnerId == Guid.Empty)
                    return TransferError(StatusCodes.Status400BadRequest, "PROJECT_OWNER_INVALID_REQUEST",
                        "Provide both the expected current owner and the new owner.");

                // Ownership maintenance remains available while a project is archived or within Trash retention.
                // It never changes ArchivedAt, DeletedAt, or the project's lifecycle status.
                var project = await db.Projects.SingleOrDefaultAsync(x => x.Id == id, ct);
                if (project is null || project.DeletedAt is not null
                    && project.DeletedAt < DateTime.UtcNow.AddDays(-30))
                    return NotFound();

                var actorId = CurrentUser.Id(User);
                var actor = await (from organizationMember in db.OrganizationMembers
                                   join user in db.Users on organizationMember.UserId equals user.Id
                                   where organizationMember.OrganizationId == project.OrganizationId
                                       && organizationMember.UserId == actorId
                                       && organizationMember.Status == "active"
                                       && organizationMember.Role != "GUEST"
                                       && user.Status == "active"
                                   select new { organizationMember.Role }).SingleOrDefaultAsync(ct);
                if (actor is null)
                    return TransferError(StatusCodes.Status403Forbidden, "PROJECT_OWNER_TRANSFER_FORBIDDEN",
                        "An active non-guest organization member account is required to transfer ownership.");

                var isCurrentOwner = project.OwnerId == actorId;
                var isOrganizationAdmin = actor.Role is "OWNER" or "ADMIN";
                var isProjectManager = await db.ProjectMembers.AnyAsync(x => x.ProjectId == id
                    && x.UserId == actorId && x.Status == "active" && x.Role == "PROJECT_MANAGER", ct);
                if (!isCurrentOwner && !isOrganizationAdmin && !isProjectManager)
                    return TransferError(StatusCodes.Status403Forbidden, "PROJECT_OWNER_TRANSFER_FORBIDDEN",
                        "Only the current owner, an organization owner/admin, or a project manager can transfer ownership.");

                if (project.OwnerId != request.ExpectedOwnerId)
                    return TransferError(StatusCodes.Status409Conflict, "PROJECT_OWNER_CHANGED",
                        "The project owner changed. Refresh project data before retrying.");

                var recipient = await (from projectMember in db.ProjectMembers
                                       join organizationMember in db.OrganizationMembers
                                           on projectMember.UserId equals organizationMember.UserId
                                       join user in db.Users on projectMember.UserId equals user.Id
                                       where projectMember.ProjectId == id
                                           && projectMember.UserId == request.NewOwnerId
                                           && projectMember.Status == "active"
                                           && projectMember.Role == "PROJECT_MANAGER"
                                           && organizationMember.OrganizationId == project.OrganizationId
                                           && organizationMember.Status == "active"
                                           && organizationMember.Role != "GUEST"
                                           && user.Status == "active"
                                       select new { user.FirstName, user.LastName }).SingleOrDefaultAsync(ct);
                if (recipient is null)
                    return TransferError(StatusCodes.Status409Conflict, "PROJECT_OWNER_RECIPIENT_NOT_ELIGIBLE",
                        "The new owner must be an active project manager in this organization with an active account.");

                if (request.NewOwnerId == project.OwnerId)
                {
                    await tx.CommitAsync(ct);
                    return NoContent();
                }

                var previousOwnerId = project.OwnerId;
                var previousOwnerName = await db.Users.AsNoTracking()
                    .Where(x => x.Id == previousOwnerId)
                    .Select(x => x.FirstName + " " + x.LastName)
                    .SingleOrDefaultAsync(ct) ?? "Unknown project owner";
                var newOwnerName = $"{recipient.FirstName} {recipient.LastName}";
                var now = DateTime.UtcNow;
                project.OwnerId = request.NewOwnerId;
                project.UpdatedAt = now;

                var correlationId = Request.Headers["X-Correlation-ID"].FirstOrDefault();
                if (string.IsNullOrWhiteSpace(correlationId) || correlationId.Length > 128)
                    correlationId = HttpContext.TraceIdentifier;
                db.AdminAuditEvents.Add(new AdminAuditEvent
                {
                    Id = Guid.NewGuid(),
                    ActorId = actorId,
                    ActorDisplayName = await db.Users.AsNoTracking().Where(x => x.Id == actorId)
                        .Select(x => x.FirstName + " " + x.LastName).SingleAsync(ct),
                    Action = "project.owner_transferred",
                    TargetType = "project",
                    TargetId = id,
                    TargetDisplayName = $"{project.Name}: {previousOwnerName} -> {newOwnerName}",
                    Outcome = "succeeded",
                    Reason = $"project_id={id}; old_owner_id={previousOwnerId}; new_owner_id={request.NewOwnerId}",
                    CorrelationId = correlationId,
                    OccurredAt = DateTimeOffset.UtcNow
                });
                await ActivityRecorder.RecordAsync(db, User, Request, project.OrganizationId, "Projects",
                    "project.owner_transferred", "project", id, project.Name,
                    $"transferred project \"{project.Name}\" ownership from {previousOwnerName} to {newOwnerName}", ct, id);
                await db.SaveChangesAsync(ct);
                await tx.CommitAsync(ct);

                await realtime.ProjectChanged(project.OrganizationId, project.Id, "projects", ct);
                return NoContent();
            });
        }
        catch (RetryLimitExceededException)
        {
            return TransferError(StatusCodes.Status409Conflict, "PROJECT_OWNER_TRANSFER_CONFLICT",
                "The project changed while ownership was being transferred. Refresh project data and retry.");
        }
    }

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

    [HttpGet("{id:guid}/members/{userId:guid}/removal-preview")]
    public async Task<IActionResult> PreviewMemberRemoval(Guid id, Guid userId, CancellationToken ct)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(ct);
        deadline.CancelAfter(TimeSpan.FromSeconds(30));
        try
        {
            var organizationId = await db.Projects.AsNoTracking().Where(item => item.Id == id)
                .Select(item => (Guid?)item.OrganizationId).SingleOrDefaultAsync(deadline.Token);
            if (organizationId is null) return RemovalError(StatusCodes.Status404NotFound,
                "PROJECT_NOT_FOUND", "The project is unavailable for member removal.");
            var strategy = db.Database.CreateExecutionStrategy();
            return await strategy.ExecuteAsync<IActionResult>(async operationToken =>
            {
                db.ChangeTracker.Clear();
                await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, operationToken);
                var now = DateTime.UtcNow;
                var state = await MemberRemovalResolutionSupport.LoadStateAsync(db, organizationId.Value,
                    userId, CurrentUser.Id(User), id, now, acquireLocks: false, operationToken);
                var projectState = state.Projects.SingleOrDefault(item => item.Project.Id == id);
                if (projectState is null || projectState.Lifecycle == "EXPIRED_TRASH_PENDING_PURGE")
                    return RemovalError(StatusCodes.Status404NotFound, "PROJECT_NOT_FOUND",
                        "The project is unavailable for member removal.");
                if (projectState.TargetMembership is not { Status: "active" }
                    || state.MemberOrganizationMembership is not { Status: "active" })
                    return RemovalError(StatusCodes.Status404NotFound, "MEMBER_NOT_FOUND",
                        "The member is not active in this project and organization.");
                if (!CanRemoveProjectMember(state, projectState))
                    return RemovalError(StatusCodes.Status403Forbidden, "MEMBER_REMOVAL_FORBIDDEN",
                        "You do not have permission to remove this project member.");
                if (state.AllAssignedTasks.Count > MemberRemovalResolutionSupport.MaxAffectedTasks)
                    return RemovalError(StatusCodes.Status422UnprocessableEntity, "MEMBER_RESOLUTION_LIMIT_EXCEEDED",
                        "This operation affects more than 100 task assignments. Resolve active-project assignments through existing task operations or complete Trash purge, then refresh the preview.");
                var response = state.ToPreview(id);
                await tx.CommitAsync(operationToken);
                return Ok(response);
            }, deadline.Token);
        }
        catch (RetryLimitExceededException)
        {
            return RemovalConflict();
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested && deadline.IsCancellationRequested)
        {
            return RemovalConflict();
        }
    }

    [HttpPost("{id:guid}/members/{userId:guid}/remove")]
    public async Task<IActionResult> ConfirmMemberRemoval(Guid id, Guid userId, [FromBody] MemberRemovalRequest? request,
        CancellationToken ct)
    {
        if (request is null || string.IsNullOrWhiteSpace(request.SnapshotHash) || request.Resolutions is null)
            return RemovalError(StatusCodes.Status400BadRequest, "MEMBER_RESOLUTION_REQUIRED",
                "Provide the preview snapshot and one resolution for every affected task.");

        var operationId = Guid.NewGuid();
        var changedOrganizationId = Guid.Empty;
        IReadOnlyList<AssignmentEmailRecipient> emailRecipients = [];
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(ct);
        deadline.CancelAfter(TimeSpan.FromSeconds(30));
        try
        {
            var organizationId = await db.Projects.AsNoTracking().Where(item => item.Id == id)
                .Select(item => (Guid?)item.OrganizationId).SingleOrDefaultAsync(deadline.Token);
            if (organizationId is null) return RemovalError(StatusCodes.Status404NotFound,
                "PROJECT_NOT_FOUND", "The project is unavailable for member removal.");
            var strategy = db.Database.CreateExecutionStrategy();
            var result = await strategy.ExecuteAsync<IActionResult>(async operationToken =>
            {
                db.ChangeTracker.Clear();
                emailRecipients = [];
                await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, operationToken);
                var now = DateTime.UtcNow;
                var state = await MemberRemovalResolutionSupport.LoadStateAsync(db, organizationId.Value,
                    userId, CurrentUser.Id(User), id, now, acquireLocks: true, operationToken);
                if (state.HasUnseenTargetAssignment) return RemovalConflict();
                var projectState = state.Projects.SingleOrDefault(item => item.Project.Id == id);
                if (projectState is null || projectState.Lifecycle == "EXPIRED_TRASH_PENDING_PURGE")
                    return RemovalError(StatusCodes.Status404NotFound, "PROJECT_NOT_FOUND",
                        "The project is unavailable for member removal.");
                var project = projectState.Project;
                if (!CanRemoveProjectMember(state, projectState))
                    return RemovalError(StatusCodes.Status403Forbidden, "MEMBER_REMOVAL_FORBIDDEN",
                        "You do not have permission to remove this project member.");
                if (!MemberRemovalResolutionSupport.SnapshotMatches(request.SnapshotHash, state.ToPreview(id).SnapshotHash))
                    return RemovalError(StatusCodes.Status409Conflict, "MEMBER_REMOVAL_PREVIEW_STALE",
                        "Project membership or task assignment state changed. Refresh the preview and try again.");
                if (projectState.TargetMembership is not { Status: "active" }
                    || state.MemberOrganizationMembership is not { Status: "active" })
                    return RemovalError(StatusCodes.Status409Conflict, "MEMBER_REMOVAL_PREVIEW_STALE",
                        "The target member is no longer active in this project. Refresh the preview.");
                if (state.AllAssignedTasks.Count > MemberRemovalResolutionSupport.MaxAffectedTasks
                    || request.Resolutions.Count > MemberRemovalResolutionSupport.MaxAffectedTasks)
                    return RemovalError(StatusCodes.Status422UnprocessableEntity, "MEMBER_RESOLUTION_LIMIT_EXCEEDED",
                        "This operation affects more than 100 tasks. Reduce the affected task count and refresh the preview.");
                if (projectState.Project.OwnerId == userId)
                    return RemovalError(StatusCodes.Status409Conflict, "PROJECT_OWNER_TRANSFER_REQUIRED",
                        "Transfer project ownership before removing its owner.");
                var targetIsActiveManager = projectState.ActiveManagerIds.Contains(userId);
                if (projectState.ActiveManagerIds.Count - (targetIsActiveManager ? 1 : 0) < 1)
                    return RemovalError(StatusCodes.Status409Conflict, "PROJECT_MUST_RETAIN_MANAGER",
                        "The project must retain at least one eligible active manager.");

                var validationError = MemberRemovalResolutionSupport.ValidateResolutions(state,
                    state.AffectedTasks, request.Resolutions, out var resolutions);
                if (validationError is not null)
                    return RemovalError(validationError.StatusCode, validationError.Code, validationError.Message);
                var validResolutions = resolutions!;
                emailRecipients = await MemberRemovalResolutionSupport.ApplyResolutionsAsync(db, state,
                    state.AffectedTasks, validResolutions,
                    User, Request, operationId, operationToken);
                await MemberRemovalResolutionSupport.ApplyHistoricalAttributionInactivationAsync(db, state,
                    User, Request, operationId, operationToken);
                projectState.TargetMembership!.Status = "inactive";
                var removedUser = state.Users.GetValueOrDefault(userId);
                var removedName = removedUser is null ? "Workspace member" : $"{removedUser.FirstName} {removedUser.LastName}";
                await ActivityRecorder.RecordAsync(db, User, Request, project.OrganizationId, "People",
                    "project.member_removed", "user", userId, removedName,
                    $"removed {removedName} from project \"{project.Name}\" after resolving open task assignments",
                    operationToken, project.Id);
                MemberRemovalResolutionSupport.AddRemovalAudit(db, state, operationId, "project.member_removed", "project member removal",
                    project.Id, $"project_id={project.Id}; resolved_tasks={validResolutions.Count}");
                await db.SaveChangesAsync(operationToken);
                await tx.CommitAsync(operationToken);
                changedOrganizationId = project.OrganizationId;
                return NoContent();
            }, deadline.Token);

                if (result is NoContentResult)
                {
                if (mail is not null)
                    foreach (var recipient in emailRecipients)
                        _ = Task.Run(() => mail.SendTaskAssigned(recipient.Email, recipient.FirstName,
                            recipient.TaskTitle, recipient.ProjectId, recipient.TaskId));
                await realtime.ProjectChanged(changedOrganizationId, id, "tasks", ct);
                await realtime.ProjectChanged(changedOrganizationId, id, "members", ct);
            }
            return result;
        }
        catch (RetryLimitExceededException)
        {
            return RemovalConflict();
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested && deadline.IsCancellationRequested)
        {
            return RemovalConflict();
        }
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
                var legacyOperationId = Guid.NewGuid();
                var legacyAssignments = await (from assignment in db.TaskAssignees
                                               join task in db.Tasks on assignment.TaskId equals task.Id
                                               where assignment.UserId == userId && assignment.Status == "active"
                                                   && task.ProjectId == id
                                               select new { Assignment = assignment, Task = task })
                    .ToListAsync(ct);
                MemberRemovalResolutionSupport.AddLegacyRemovalHistory(db,
                    legacyAssignments.Select(item => (item.Assignment, item.Task, id)),
                    project.OrganizationId, userId, CurrentUser.Id(User), DateTime.UtcNow, legacyOperationId);
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

    private bool CanRemoveProjectMember(MemberRemovalState state, MemberRemovalProjectState project) =>
        state.ActorId != state.MemberId
        && state.ActorOrganizationMembership is { Status: "active", Role: not "GUEST" }
        && project.Lifecycle is ("ACTIVE" or "ARCHIVED" or "TRASHED_WITHIN_RETENTION")
        && project.Memberships.Any(member => member.UserId == state.ActorId && member.Status == "active"
            && member.Role is ("PROJECT_MANAGER" or "TEAM_LEAD"))
        && state.MemberOrganizationMembership is { Status: "active" };

    private ObjectResult RemovalError(int statusCode, string code, string message) =>
        StatusCode(statusCode, new { code, message });

    private ObjectResult RemovalConflict() => RemovalError(StatusCodes.Status409Conflict,
        "MEMBER_REMOVAL_CONFLICT", "The project changed while removal was being processed. Refresh the preview and retry.");

    private ObjectResult RoleUpdateError(int statusCode, string code, string message) =>
        StatusCode(statusCode, new { code, message });

    private ObjectResult TransferError(int statusCode, string code, string message) =>
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
public sealed record TransferProjectOwnerRequest(Guid ExpectedOwnerId, Guid NewOwnerId);
