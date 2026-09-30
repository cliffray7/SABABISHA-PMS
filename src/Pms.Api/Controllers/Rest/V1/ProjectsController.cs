using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Pms.Api.Auth;
using Pms.Api.Activity;
using Pms.Domain.Entities;
using Pms.Infrastructure.Persistence.EfCore;
namespace Pms.Api.Controllers.Rest.V1;
[ApiController, Authorize, Route("api/v1/projects")]
public sealed class ProjectsController(PmsDbContext db) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> List(Guid organizationId, CancellationToken ct) => Ok(await (from p in db.Projects join m in db.ProjectMembers on p.Id equals m.ProjectId join om in db.OrganizationMembers on p.OrganizationId equals om.OrganizationId where p.OrganizationId == organizationId && p.ArchivedAt == null && m.UserId == CurrentUser.Id(User) && m.Status == "active" && om.UserId == CurrentUser.Id(User) && om.Status == "active" select new { p.Id, p.OrganizationId, p.Name, p.Description, p.Status, p.StartDate, p.DueDate, m.Role }).ToListAsync(ct));
    [HttpPost]
    public async Task<IActionResult> Create(CreateProjectRequest request, CancellationToken ct)
    {
        if (!await db.OrganizationMembers.AnyAsync(x => x.OrganizationId == request.OrganizationId && x.UserId == CurrentUser.Id(User) && x.Status == "active" && x.Role != "GUEST", ct)) return Forbid();
        if (!Valid(request.Name, request.Status, request.StartDate, request.DueDate)) return BadRequest(new { message = "Enter a project name, valid status, and due date on or after the start date." });
        var p = new Project { Id = Guid.NewGuid(), OrganizationId = request.OrganizationId, OwnerId = CurrentUser.Id(User), Name = request.Name.Trim(), Description = request.Description, Status = request.Status, StartDate = request.StartDate, DueDate = request.DueDate };
        db.Projects.Add(p); db.ProjectMembers.Add(new ProjectMember { Id = Guid.NewGuid(), ProjectId = p.Id, UserId = CurrentUser.Id(User), Role = "PROJECT_MANAGER" });
        await ActivityRecorder.RecordAsync(db, User, Request, p.OrganizationId, "Projects", "project.created", "project", p.Id, p.Name, $"created project \"{p.Name}\"", ct, p.Id);
        await db.SaveChangesAsync(ct); return Ok(p);
    }
    [HttpGet("{id:guid}")]
    public async Task<IActionResult> Get(Guid id, CancellationToken ct)
    { if (!await Member(id, ct)) return Forbid(); return Ok(await db.Projects.SingleAsync(x => x.Id == id, ct)); }
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
        await db.SaveChangesAsync(ct); return Ok(p);
    }
    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Archive(Guid id, CancellationToken ct)
    {
        if (!await Manager(id, ct)) return Forbid();
        var project = await db.Projects.SingleAsync(x => x.Id == id, ct);
        project.ArchivedAt = DateTime.UtcNow;
        await ActivityRecorder.RecordAsync(db, User, Request, project.OrganizationId, "Projects", "project.archived", "project", project.Id, project.Name, $"archived project \"{project.Name}\"", ct, project.Id);
        await db.SaveChangesAsync(ct); return NoContent();
    }
    [HttpPost("{id:guid}/restore")]
    public async Task<IActionResult> Restore(Guid id, CancellationToken ct)
    {
        if (!await Manager(id, ct)) return Forbid();
        var project = await db.Projects.SingleOrDefaultAsync(x => x.Id == id && x.ArchivedAt != null, ct);
        if (project is null) return NotFound();
        project.ArchivedAt = null; project.UpdatedAt = DateTime.UtcNow;
        await ActivityRecorder.RecordAsync(db, User, Request, project.OrganizationId, "Projects", "project.restored", "project", project.Id, project.Name, $"restored project \"{project.Name}\"", ct, project.Id);
        await db.SaveChangesAsync(ct); return NoContent();
    }
    [HttpGet("{id:guid}/members")]
    public async Task<IActionResult> Members(Guid id, CancellationToken ct)
    {
        if (!await Member(id, ct)) return Forbid();
        return Ok(await (from m in db.ProjectMembers join u in db.Users on m.UserId equals u.Id where m.ProjectId == id && m.Status == "active" select new { m.Id, m.UserId, u.FirstName, u.LastName, u.Email, m.Role }).ToListAsync(ct));
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
        await db.SaveChangesAsync(ct); return NoContent();
    }
    [HttpDelete("{id:guid}/members/{userId:guid}")]
    public async Task<IActionResult> RemoveMember(Guid id, Guid userId, CancellationToken ct)
    {
        if (!await Manager(id, ct)) return Forbid();
        if (userId == CurrentUser.Id(User)) return BadRequest(new { message = "You cannot remove yourself from the project." });
        var member = await db.ProjectMembers.SingleOrDefaultAsync(x => x.ProjectId == id && x.UserId == userId && x.Status == "active", ct);
        if (member is null) return NotFound();
        member.Status = "inactive";
        var project = await db.Projects.SingleAsync(x => x.Id == id, ct);
        var removedUser = await db.Users.AsNoTracking().Where(x => x.Id == userId).Select(x => new { x.FirstName, x.LastName }).SingleAsync(ct);
        var removedName = $"{removedUser.FirstName} {removedUser.LastName}";
        await ActivityRecorder.RecordAsync(db, User, Request, project.OrganizationId, "People", "project.member_removed", "user", userId, removedName, $"removed {removedName} from project \"{project.Name}\"", ct, project.Id);
        await db.SaveChangesAsync(ct); return NoContent();
    }
    private Task<bool> Member(Guid id, CancellationToken ct) => (from projectMember in db.ProjectMembers
        join project in db.Projects on projectMember.ProjectId equals project.Id
        join organizationMember in db.OrganizationMembers on project.OrganizationId equals organizationMember.OrganizationId
        where projectMember.ProjectId == id && projectMember.UserId == CurrentUser.Id(User) && projectMember.Status == "active"
            && organizationMember.UserId == CurrentUser.Id(User) && organizationMember.Status == "active"
        select projectMember).AnyAsync(ct);
    private Task<bool> Manager(Guid id, CancellationToken ct) => (from projectMember in db.ProjectMembers
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
