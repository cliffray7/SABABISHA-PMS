using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using Pms.Infrastructure.Persistence.EfCore;

namespace Pms.Api.Realtime;

[Authorize]
public sealed class WorkspaceHub(PmsDbContext db) : Hub
{
    public async Task JoinOrganization(string organizationId)
    {
        if (!Guid.TryParse(organizationId, out var id) || !await IsOrganizationMember(id))
            throw new HubException("Organization access denied.");
        await Groups.AddToGroupAsync(Context.ConnectionId, OrganizationGroup(id));
    }

    public async Task JoinProject(string projectId)
    {
        if (!Guid.TryParse(projectId, out var id)) throw new HubException("Project access denied.");
        var userId = UserId();
        var allowed = await (from member in db.ProjectMembers
                             join project in db.Projects on member.ProjectId equals project.Id
                             join orgMember in db.OrganizationMembers on project.OrganizationId equals orgMember.OrganizationId
                             where project.Id == id && member.UserId == userId && member.Status == "active"
                                   && orgMember.UserId == userId && orgMember.Status == "active"
                                   && project.ArchivedAt == null && project.DeletedAt == null
                             select member).AnyAsync();
        if (!allowed) throw new HubException("Project access denied.");
        await Groups.AddToGroupAsync(Context.ConnectionId, ProjectGroup(id));
    }

    public Task LeaveProject(string projectId) => Guid.TryParse(projectId, out var id)
        ? Groups.RemoveFromGroupAsync(Context.ConnectionId, ProjectGroup(id))
        : Task.CompletedTask;

    public static string OrganizationGroup(Guid id) => $"organization:{id:N}";
    public static string ProjectGroup(Guid id) => $"project:{id:N}";

    private Task<bool> IsOrganizationMember(Guid organizationId) => db.OrganizationMembers.AnyAsync(member =>
        member.OrganizationId == organizationId && member.UserId == UserId() && member.Status == "active");

    private Guid UserId()
    {
        var value = Context.User?.FindFirstValue("sub") ?? Context.User?.FindFirstValue(ClaimTypes.NameIdentifier);
        return Guid.TryParse(value, out var id) ? id : throw new HubException("Authentication required.");
    }
}
