using Microsoft.EntityFrameworkCore;
using Pms.Infrastructure.Persistence.EfCore;

namespace Pms.Api.Auth;

/// <summary>Shared tenant and project membership authorization for workspace reads and writes.</summary>
public static class WorkspaceAuthorization
{
    public static Task<bool> CanAccessProjectAsync(
        PmsDbContext db,
        Guid projectId,
        Guid userId,
        bool write,
        CancellationToken cancellationToken = default) =>
        (from projectMember in db.ProjectMembers
         join project in db.Projects on projectMember.ProjectId equals project.Id
         join organizationMember in db.OrganizationMembers on project.OrganizationId equals organizationMember.OrganizationId
         where projectMember.ProjectId == projectId && projectMember.UserId == userId
             && projectMember.Status == "active"
             && organizationMember.UserId == userId && organizationMember.Status == "active"
             && project.ArchivedAt == null && project.DeletedAt == null
             && (!write || (projectMember.Role != "VIEWER" && organizationMember.Role != "GUEST"))
         select projectMember).AnyAsync(cancellationToken);
}
