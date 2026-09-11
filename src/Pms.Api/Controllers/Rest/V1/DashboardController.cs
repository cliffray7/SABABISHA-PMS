using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Pms.Api.Auth;
using Pms.Infrastructure.Persistence.Dapper;
using Pms.Infrastructure.Persistence.EfCore;

namespace Pms.Api.Controllers.Rest.V1;

[ApiController, Authorize, Route("api/v1/dashboard")]
public sealed class DashboardController(PmsDbContext db, DashboardRepository dashboard) : ControllerBase
{
    [HttpGet("metrics")]
    public async Task<IActionResult> Metrics(Guid? projectId, CancellationToken ct)
    {
        if (projectId is Guid selectedProject && !await (from projectMember in db.ProjectMembers
                join project in db.Projects on projectMember.ProjectId equals project.Id
                join organizationMember in db.OrganizationMembers on project.OrganizationId equals organizationMember.OrganizationId
                where projectMember.ProjectId == selectedProject && projectMember.UserId == CurrentUser.Id(User)
                    && projectMember.Status == "active" && organizationMember.UserId == CurrentUser.Id(User)
                    && organizationMember.Status == "active" && project.ArchivedAt == null
                select projectMember).AnyAsync(ct)) return Forbid();

        return Ok(await dashboard.GetMetrics(CurrentUser.Id(User), projectId, ct));
    }
}