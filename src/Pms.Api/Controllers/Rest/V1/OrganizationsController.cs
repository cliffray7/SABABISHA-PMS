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

[ApiController, Authorize, Route("api/v1/organizations")]
public sealed class OrganizationsController(PmsDbContext db, AppMail mail, TokenService tokens, RealtimePublisher realtime) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> List(CancellationToken ct) => Ok(await (from o in db.Organizations join m in db.OrganizationMembers on o.Id equals m.OrganizationId where m.UserId == CurrentUser.Id(User) && m.Status == "active" select new { o.Id, o.Name, o.Slug, m.Role }).ToListAsync(ct));
    [HttpPost]
    public async Task<IActionResult> Create(CreateOrganizationRequest request, CancellationToken ct)
    {
        var name = request.Name.Trim(); var slug = request.Slug.Trim().ToLowerInvariant();
        if (name.Length == 0 || !System.Text.RegularExpressions.Regex.IsMatch(slug, "^[a-z0-9]+(?:-[a-z0-9]+)*$")) return BadRequest(new { message = "Enter a name and a slug using lowercase letters, numbers, and hyphens." });
        if (await db.Organizations.AnyAsync(x => x.Name == name || x.Slug == slug, ct)) return Conflict(new { message = "An organization with this name or slug already exists." });
        var organization = new Organization { Id = Guid.NewGuid(), Name = name, Slug = slug };
        organization.Members.Add(new OrganizationMember { Id = Guid.NewGuid(), UserId = CurrentUser.Id(User), Role = "OWNER" });
        db.Organizations.Add(organization);
        await ActivityRecorder.RecordAsync(db, User, Request, organization.Id, "People", "organization.created", "organization", organization.Id, organization.Name, $"created organization \"{organization.Name}\"", ct);
        await db.SaveChangesAsync(ct);
        await realtime.OrganizationChanged(organization.Id, "members", ct);
        return Ok(new { organization.Id, organization.Name, organization.Slug, role = "OWNER" });
    }
    [HttpGet("{id:guid}/members")]
    public async Task<IActionResult> Members(Guid id, CancellationToken ct)
    {
        if (!await Member(id, ct)) return Forbid();
        return Ok(await (from m in db.OrganizationMembers join u in db.Users on m.UserId equals u.Id where m.OrganizationId == id && m.Status == "active" select new { m.Id, m.UserId, u.FirstName, u.LastName, u.Email, u.AvatarUrl, m.Role }).ToListAsync(ct));
    }
    [HttpPatch("{id:guid}/members/{userId:guid}")]
    public async Task<IActionResult> Role(Guid id, Guid userId, UpdateRoleRequest request, CancellationToken ct)
    {
        if (!new[] { "ADMIN", "MEMBER", "GUEST" }.Contains(request.Role)) return BadRequest(new { message = "Invalid organization role." });
        try
        {
            var strategy = db.Database.CreateExecutionStrategy();
            return await strategy.ExecuteAsync<IActionResult>(async () =>
            {
                db.ChangeTracker.Clear();
                await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct);
                if (!await Admin(id, ct)) return Forbid();
                var member = await db.OrganizationMembers.SingleOrDefaultAsync(x => x.OrganizationId == id && x.UserId == userId, ct);
                if (member is null) return NotFound();
                if (member.Role == "OWNER" || userId == CurrentUser.Id(User)) return BadRequest(new { message = "You cannot change the owner's role or your own role." });

                var previousRole = member.Role;
                var changedMemberships = new List<(ProjectMember Member, Guid ProjectId, string ProjectName, string OldRole)>();
                if (request.Role == "GUEST")
                {
                    if (await db.Projects.AnyAsync(project => project.OrganizationId == id && project.OwnerId == userId, ct))
                        return MemberInvariantError(StatusCodes.Status409Conflict, "project_owner_transfer_required",
                            "Transfer project ownership before changing this organization member to a guest.");
                    var memberships = await (from projectMember in db.ProjectMembers
                                             join project in db.Projects on projectMember.ProjectId equals project.Id
                                             where projectMember.UserId == userId && projectMember.Status == "active"
                                                 && project.OrganizationId == id
                                             select new { Member = projectMember, project.Id, project.Name, project.OwnerId,
                                                 project.ArchivedAt, project.DeletedAt })
                        .ToListAsync(ct);
                    foreach (var item in memberships.Where(item => item.ArchivedAt == null && item.DeletedAt == null
                                 && item.Member.Role == "PROJECT_MANAGER"))
                    {
                        var activeManagers = await ActiveManagerCount(item.Id, id, ct);
                        var userIsActive = member.Status == "active" && member.Role != "GUEST"
                            && await db.Users.AnyAsync(user => user.Id == userId && user.Status == "active", ct);
                        if (activeManagers - (userIsActive ? 1 : 0) < 1)
                            return MemberInvariantError(StatusCodes.Status409Conflict, "organization_member_project_manager_required",
                                "The project must retain at least one active project manager before this member can become a guest.");
                    }

                    changedMemberships = memberships.Where(item => item.Member.Role != "VIEWER")
                        .Select(item => (Member: item.Member, ProjectId: item.Id, ProjectName: item.Name, OldRole: item.Member.Role)).ToList();
                    foreach (var changed in changedMemberships) changed.Member.Role = "VIEWER";
                }

                member.Role = request.Role;
                var organization = await db.Organizations.SingleAsync(x => x.Id == id, ct);
                var changedUser = await db.Users.AsNoTracking().Where(x => x.Id == userId).Select(x => new { x.FirstName, x.LastName }).SingleAsync(ct);
                var actorId = CurrentUser.Id(User);
                var actorName = await db.Users.AsNoTracking().Where(x => x.Id == actorId)
                    .Select(x => x.FirstName + " " + x.LastName).SingleAsync(ct);
                var changedName = $"{changedUser.FirstName} {changedUser.LastName}";
                if (request.Role == "GUEST")
                    await ActivityRecorder.InactivateTaskAssignmentsAsync(db, User, Request, id, userId, changedName,
                        "the organization member became a guest", null, ct);
                foreach (var changed in changedMemberships)
                {
                    var correlationId = Request.Headers["X-Correlation-ID"].FirstOrDefault();
                    if (string.IsNullOrWhiteSpace(correlationId) || correlationId.Length > 128)
                        correlationId = HttpContext.TraceIdentifier;
                    db.AdminAuditEvents.Add(new AdminAuditEvent
                    {
                        Id = Guid.NewGuid(),
                        ActorId = actorId,
                        ActorDisplayName = actorName,
                        Action = "project.member_guest_role_clamped",
                        TargetType = "user",
                        TargetId = userId,
                        TargetDisplayName = $"{changedName} in {changed.ProjectName}: {changed.OldRole} -> VIEWER",
                        Outcome = "succeeded",
                        Reason = $"project_id={changed.ProjectId}; old_role={changed.OldRole}; new_role=VIEWER; cause=organization_role_guest_demotion",
                        CorrelationId = correlationId,
                        OccurredAt = DateTimeOffset.UtcNow
                    });
                    await ActivityRecorder.RecordAsync(db, User, Request, id, "People", "project.member_guest_role_clamped", "user", userId,
                        changedName, $"changed {changedName}'s project role from {changed.OldRole} to VIEWER in project \"{changed.ProjectName}\"", ct, changed.ProjectId);
                }
                await ActivityRecorder.RecordAsync(db, User, Request, id, "People", "organization.member_role_changed", "user", userId,
                    changedName, $"changed {changedName}'s role from {previousRole} to {request.Role} in organization \"{organization.Name}\"", ct);
                await db.SaveChangesAsync(ct);
                await tx.CommitAsync(ct);
                await realtime.OrganizationChanged(id, "members", ct);
                return NoContent();
            });
        }
        catch (RetryLimitExceededException)
        {
            return MemberInvariantError(StatusCodes.Status409Conflict, "organization_member_update_conflict",
                "The organization changed while this request was being processed. Refresh member data and retry.");
        }
    }
    [HttpDelete("{id:guid}/members/{userId:guid}")]
    public async Task<IActionResult> RemoveMember(Guid id, Guid userId, CancellationToken ct)
    {
        try
        {
            var strategy = db.Database.CreateExecutionStrategy();
            return await strategy.ExecuteAsync<IActionResult>(async () =>
            {
                db.ChangeTracker.Clear();
                await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct);
                if (!await Admin(id, ct)) return Forbid();
                if (userId == CurrentUser.Id(User)) return BadRequest(new { message = "You cannot remove yourself." });
                var member = await db.OrganizationMembers.SingleOrDefaultAsync(x => x.OrganizationId == id && x.UserId == userId && x.Status == "active", ct);
                if (member is null) return NotFound();
                if (member.Role == "OWNER") return BadRequest(new { message = "The organization owner cannot be removed." });
                if (await db.Projects.AnyAsync(project => project.OrganizationId == id && project.OwnerId == userId, ct))
                    return MemberInvariantError(StatusCodes.Status409Conflict, "project_owner_transfer_required",
                        "Transfer project ownership before removing this organization member.");

                var projects = await (from project in db.Projects
                                      join projectMember in db.ProjectMembers on project.Id equals projectMember.ProjectId
                                      where project.OrganizationId == id && projectMember.UserId == userId
                                          && projectMember.Status == "active" && project.ArchivedAt == null && project.DeletedAt == null
                                      select new { project.Id, projectMember.Role })
                    .ToListAsync(ct);
                foreach (var project in projects.Where(project => project.Role == "PROJECT_MANAGER"))
                {
                    var activeManagers = await ActiveManagerCount(project.Id, id, ct);
                    var userIsActive = await db.Users.AnyAsync(user => user.Id == userId && user.Status == "active", ct);
                    if (activeManagers - (userIsActive ? 1 : 0) < 1)
                        return MemberInvariantError(StatusCodes.Status409Conflict, "organization_member_project_manager_required",
                            "This member is the last active project manager for at least one project.");
                }

                var hasOpenAssignments = await (from assignee in db.TaskAssignees
                                                 join task in db.Tasks on assignee.TaskId equals task.Id
                                                 join project in db.Projects on task.ProjectId equals project.Id
                                                 where assignee.UserId == userId && assignee.Status == "active"
                                                     && project.OrganizationId == id
                                                     && task.DeletedAt == null && task.Status != "DONE"
                                                 select assignee.Id).AnyAsync(ct);
                if (hasOpenAssignments)
                    return MemberInvariantError(StatusCodes.Status409Conflict, "organization_member_open_tasks_require_resolution",
                        "Reassign or clear this member's open task assignments before removing them.");

                member.Status = "inactive";
                var organization = await db.Organizations.SingleAsync(x => x.Id == id, ct);
                var removedUser = await db.Users.AsNoTracking().Where(x => x.Id == userId).Select(x => new { x.FirstName, x.LastName }).SingleAsync(ct);
                var removedName = $"{removedUser.FirstName} {removedUser.LastName}";
                await ActivityRecorder.InactivateTaskAssignmentsAsync(db, User, Request, id, userId, removedName,
                    "the organization membership was removed", null, ct);
                await ActivityRecorder.RecordAsync(db, User, Request, id, "People", "organization.member_removed", "user", userId,
                    removedName, $"removed {removedName} from organization \"{organization.Name}\"", ct);
                await db.ProjectMembers.Where(x => x.UserId == userId && db.Projects.Any(project => project.Id == x.ProjectId && project.OrganizationId == id))
                    .ExecuteUpdateAsync(setters => setters.SetProperty(x => x.Status, "inactive"), ct);
                await db.RefreshTokens.Where(x => x.UserId == userId && x.RevokedAt == null)
                    .ExecuteUpdateAsync(setters => setters.SetProperty(x => x.RevokedAt, DateTime.UtcNow), ct);
                await db.SaveChangesAsync(ct);
                await tx.CommitAsync(ct);
                await realtime.OrganizationChanged(id, "members", ct);
                return NoContent();
            });
        }
        catch (RetryLimitExceededException)
        {
            return MemberInvariantError(StatusCodes.Status409Conflict, "organization_member_update_conflict",
                "The organization changed while this request was being processed. Refresh member data and retry.");
        }
    }
    [HttpGet("{id:guid}/invitations")]
    public async Task<IActionResult> Invitations(Guid id, CancellationToken ct)
    {
        if (!await Admin(id, ct)) return Forbid();
        return Ok(await db.OrganizationInvitations.Where(x => x.OrganizationId == id && x.AcceptedAt == null && x.ExpiresAt > DateTime.UtcNow).Select(x => new { x.Id, x.Email, x.Role, x.ExpiresAt }).ToListAsync(ct));
    }
    [HttpPost("{id:guid}/invitations")]
    public async Task<IActionResult> Invite(Guid id, InviteRequest request, CancellationToken ct)
    {
        if (!await Admin(id, ct)) return Forbid();
        if (!new[] { "ADMIN", "MEMBER", "GUEST" }.Contains(request.Role)) return BadRequest(new { message = "Invalid role." });
        var email = request.Email.Trim().ToLowerInvariant();
        if (await (from m in db.OrganizationMembers join u in db.Users on m.UserId equals u.Id where m.OrganizationId == id && m.Status == "active" && u.Email == email select m).AnyAsync(ct)) return Conflict(new { message = "This person is already a member." });
        var token = tokens.CreateRefreshToken();
        var invitation = new OrganizationInvitation { Id = Guid.NewGuid(), OrganizationId = id, Email = email, Role = request.Role, TokenHash = tokens.HashRefreshToken(token), ExpiresAt = DateTime.UtcNow.AddDays(7) };
        db.OrganizationInvitations.Add(invitation);
        var organization = await db.Organizations.SingleAsync(x => x.Id == id, ct);
        await ActivityRecorder.RecordAsync(db, User, Request, id, "People", "organization.invitation_created", "organization", id, organization.Name, $"invited a person to organization \"{organization.Name}\" as {request.Role}", ct);
        await db.SaveChangesAsync(ct);
        await realtime.OrganizationChanged(id, "invitations", ct);
        await mail.Send(email, "Join your team on TaskFlow", mail.Link("invite?token=" + Uri.EscapeDataString(token)));
        return Ok(new { invitation.Id, invitation.Email, invitation.Role });
    }
    [HttpDelete("{id:guid}/invitations/{invitationId:guid}")]
    public async Task<IActionResult> CancelInvite(Guid id, Guid invitationId, CancellationToken ct)
    {
        if (!await Admin(id, ct)) return Forbid();
        var invitation = await db.OrganizationInvitations.SingleOrDefaultAsync(x => x.OrganizationId == id && x.Id == invitationId && x.AcceptedAt == null, ct);
        if (invitation is null) return NoContent();
        db.OrganizationInvitations.Remove(invitation);
        var organization = await db.Organizations.SingleAsync(x => x.Id == id, ct);
        await ActivityRecorder.RecordAsync(db, User, Request, id, "People", "organization.invitation_revoked", "organization", id, organization.Name, $"revoked an invitation to organization \"{organization.Name}\"", ct);
        await db.SaveChangesAsync(ct);
        await realtime.OrganizationChanged(id, "invitations", ct);
        return NoContent();
    }
    [HttpPost("invitations/accept")]
    public async Task<IActionResult> Accept(InvitationTokenRequest request, CancellationToken ct)
    {
        var strategy = db.Database.CreateExecutionStrategy();
        return await strategy.ExecuteAsync<IActionResult>(async () =>
        {
            await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct);
            var hash = tokens.HashRefreshToken(request.Token);
            var invitation = await db.OrganizationInvitations.SingleOrDefaultAsync(x => x.TokenHash == hash && x.AcceptedAt == null && x.ExpiresAt > DateTime.UtcNow, ct);
            if (invitation is null) return BadRequest(new { message = "This invitation is invalid or expired." });
            var user = await db.Users.SingleAsync(x => x.Id == CurrentUser.Id(User), ct);
            if (!string.Equals(user.Email, invitation.Email, StringComparison.OrdinalIgnoreCase)) return BadRequest(new { message = "Log in with the email address this invitation was sent to." });
            var membership = await db.OrganizationMembers.SingleOrDefaultAsync(x => x.OrganizationId == invitation.OrganizationId && x.UserId == user.Id, ct);
            if (membership is null) db.OrganizationMembers.Add(new OrganizationMember { Id = Guid.NewGuid(), OrganizationId = invitation.OrganizationId, UserId = user.Id, Role = invitation.Role });
            else { membership.Status = "active"; membership.Role = invitation.Role; }
            var reactivatedMemberships = await (from projectMember in db.ProjectMembers
                                                join project in db.Projects on projectMember.ProjectId equals project.Id
                                                where projectMember.UserId == user.Id && projectMember.Status == "inactive"
                                                    && project.OrganizationId == invitation.OrganizationId
                                                select new { Member = projectMember, project.Name, project.Id })
                .ToListAsync(ct);
            foreach (var reactivated in reactivatedMemberships)
            {
                var oldRole = reactivated.Member.Role;
                reactivated.Member.Status = "active";
                if (invitation.Role == "GUEST" && oldRole != "VIEWER")
                {
                    reactivated.Member.Role = "VIEWER";
                    var actorName = $"{user.FirstName} {user.LastName}";
                    var correlationId = Request.Headers["X-Correlation-ID"].FirstOrDefault();
                    if (string.IsNullOrWhiteSpace(correlationId) || correlationId.Length > 128)
                        correlationId = HttpContext.TraceIdentifier;
                    db.AdminAuditEvents.Add(new AdminAuditEvent
                    {
                        Id = Guid.NewGuid(),
                        ActorId = user.Id,
                        ActorDisplayName = actorName,
                        Action = "project.member_guest_role_clamped",
                        TargetType = "user",
                        TargetId = user.Id,
                        TargetDisplayName = $"{actorName} in {reactivated.Name}: {oldRole} -> VIEWER",
                        Outcome = "succeeded",
                        Reason = $"project_id={reactivated.Id}; organization invitation reactivation; old_role={oldRole}; new_role=VIEWER",
                        CorrelationId = correlationId,
                        OccurredAt = DateTimeOffset.UtcNow
                    });
                }
            }
            invitation.AcceptedAt = DateTime.UtcNow;
            var organization = await db.Organizations.SingleAsync(x => x.Id == invitation.OrganizationId, ct);
            await ActivityRecorder.RecordAsync(db, User, Request, invitation.OrganizationId, "People", "organization.invitation_accepted", "organization", organization.Id, organization.Name, $"joined organization \"{organization.Name}\"", ct);
            await db.SaveChangesAsync(ct); await tx.CommitAsync(ct);
            await realtime.OrganizationChanged(invitation.OrganizationId, "members", ct);
            return Ok(new { invitation.OrganizationId });
        });
    }
    private Task<bool> Member(Guid id, CancellationToken ct) => db.OrganizationMembers.AnyAsync(x => x.OrganizationId == id && x.UserId == CurrentUser.Id(User) && x.Status == "active", ct);
    private Task<bool> Admin(Guid id, CancellationToken ct) => db.OrganizationMembers.AnyAsync(x => x.OrganizationId == id && x.UserId == CurrentUser.Id(User) && x.Status == "active" && (x.Role == "OWNER" || x.Role == "ADMIN"), ct);
    private Task<int> ActiveManagerCount(Guid projectId, Guid organizationId, CancellationToken ct) =>
        (from projectMember in db.ProjectMembers
         join organizationMember in db.OrganizationMembers on projectMember.UserId equals organizationMember.UserId
         join user in db.Users on projectMember.UserId equals user.Id
         where projectMember.ProjectId == projectId && projectMember.Role == "PROJECT_MANAGER"
             && projectMember.Status == "active" && organizationMember.OrganizationId == organizationId
             && organizationMember.Status == "active" && organizationMember.Role != "GUEST" && user.Status == "active"
         select projectMember.UserId).Distinct().CountAsync(ct);
    private ObjectResult MemberInvariantError(int statusCode, string code, string message) => StatusCode(statusCode, new { code, message });
}
public sealed record CreateOrganizationRequest([Required, StringLength(200)] string Name, [Required, StringLength(200)] string Slug);
public sealed record UpdateRoleRequest([Required] string Role);
public sealed record InviteRequest([Required, EmailAddress] string Email, [Required] string Role);
public sealed record InvitationTokenRequest([Required] string Token);
