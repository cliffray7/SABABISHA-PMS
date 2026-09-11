using System.ComponentModel.DataAnnotations;
using System.Data;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Pms.Api.Auth;
using Pms.Domain.Entities;
using Pms.Infrastructure.Persistence.EfCore;
namespace Pms.Api.Controllers.Rest.V1;

[ApiController, Authorize, Route("api/v1/organizations")]
public sealed class OrganizationsController(PmsDbContext db, AppMail mail, TokenService tokens) : ControllerBase
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
        db.Organizations.Add(organization); await db.SaveChangesAsync(ct);
        return Ok(new { organization.Id, organization.Name, organization.Slug, role = "OWNER" });
    }
    [HttpGet("{id:guid}/members")]
    public async Task<IActionResult> Members(Guid id, CancellationToken ct)
    {
        if (!await Member(id, ct)) return Forbid();
        return Ok(await (from m in db.OrganizationMembers join u in db.Users on m.UserId equals u.Id where m.OrganizationId == id && m.Status == "active" select new { m.Id, m.UserId, u.FirstName, u.LastName, u.Email, m.Role }).ToListAsync(ct));
    }
    [HttpPatch("{id:guid}/members/{userId:guid}")]
    public async Task<IActionResult> Role(Guid id, Guid userId, UpdateRoleRequest request, CancellationToken ct)
    {
        if (!await Admin(id, ct)) return Forbid();
        if (!new[] { "ADMIN", "MEMBER", "GUEST" }.Contains(request.Role)) return BadRequest(new { message = "Invalid organization role." });
        var member = await db.OrganizationMembers.SingleOrDefaultAsync(x => x.OrganizationId == id && x.UserId == userId, ct);
        if (member is null) return NotFound();
        if (member.Role == "OWNER" || userId == CurrentUser.Id(User)) return BadRequest(new { message = "You cannot change the owner's role or your own role." });
        member.Role = request.Role; await db.SaveChangesAsync(ct); return NoContent();
    }
    [HttpDelete("{id:guid}/members/{userId:guid}")]
    public async Task<IActionResult> RemoveMember(Guid id, Guid userId, CancellationToken ct)
    {
        if (!await Admin(id, ct)) return Forbid();
        if (userId == CurrentUser.Id(User)) return BadRequest(new { message = "You cannot remove yourself." });
        var member = await db.OrganizationMembers.SingleOrDefaultAsync(x => x.OrganizationId == id && x.UserId == userId && x.Status == "active", ct);
        if (member is null) return NotFound();
        if (member.Role == "OWNER") return BadRequest(new { message = "The organization owner cannot be removed." });
        member.Status = "inactive";
        await db.ProjectMembers.Where(x => x.UserId == userId && db.Projects.Any(project => project.Id == x.ProjectId && project.OrganizationId == id))
            .ExecuteUpdateAsync(setters => setters.SetProperty(x => x.Status, "inactive"), ct);
        await db.RefreshTokens.Where(x => x.UserId == userId && x.RevokedAt == null)
            .ExecuteUpdateAsync(setters => setters.SetProperty(x => x.RevokedAt, DateTime.UtcNow), ct);
        await db.SaveChangesAsync(ct); return NoContent();
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
        db.OrganizationInvitations.Add(invitation); await db.SaveChangesAsync(ct);
        await mail.Send(email, "Join your team on TaskFlow", mail.Link("invite?token=" + Uri.EscapeDataString(token)));
        return Ok(new { invitation.Id, invitation.Email, invitation.Role });
    }
    [HttpDelete("{id:guid}/invitations/{invitationId:guid}")]
    public async Task<IActionResult> CancelInvite(Guid id, Guid invitationId, CancellationToken ct)
    {
        if (!await Admin(id, ct)) return Forbid();
        await db.OrganizationInvitations.Where(x => x.OrganizationId == id && x.Id == invitationId && x.AcceptedAt == null).ExecuteDeleteAsync(ct);
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
            await db.ProjectMembers.Where(x => x.UserId == user.Id && x.Status == "inactive" && db.Projects.Any(project => project.Id == x.ProjectId && project.OrganizationId == invitation.OrganizationId))
                .ExecuteUpdateAsync(setters => setters.SetProperty(x => x.Status, "active"), ct);
            invitation.AcceptedAt = DateTime.UtcNow; await db.SaveChangesAsync(ct); await tx.CommitAsync(ct);
            return Ok(new { invitation.OrganizationId });
        });
    }
    private Task<bool> Member(Guid id, CancellationToken ct) => db.OrganizationMembers.AnyAsync(x => x.OrganizationId == id && x.UserId == CurrentUser.Id(User) && x.Status == "active", ct);
    private Task<bool> Admin(Guid id, CancellationToken ct) => db.OrganizationMembers.AnyAsync(x => x.OrganizationId == id && x.UserId == CurrentUser.Id(User) && x.Status == "active" && (x.Role == "OWNER" || x.Role == "ADMIN"), ct);
}
public sealed record CreateOrganizationRequest([Required, StringLength(200)] string Name, [Required, StringLength(200)] string Slug);
public sealed record UpdateRoleRequest([Required] string Role);
public sealed record InviteRequest([Required, EmailAddress] string Email, [Required] string Role);
public sealed record InvitationTokenRequest([Required] string Token);
