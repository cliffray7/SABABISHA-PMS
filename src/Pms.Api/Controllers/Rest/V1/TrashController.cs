using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Pms.Api.Auth;
using Pms.Domain.Entities;
using Pms.Infrastructure.Persistence.EfCore;

namespace Pms.Api.Controllers.Rest.V1;

[ApiController, Authorize, Route("api/v1/trash")]
public sealed class TrashController(PmsDbContext db) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> List(Guid organizationId, CancellationToken ct)
    {
        var userId = CurrentUser.Id(User);
        var cutoff = DateTime.UtcNow.AddDays(-30);
        var managedProjects = from project in db.Projects.AsNoTracking()
            join projectMember in db.ProjectMembers on project.Id equals projectMember.ProjectId
            join organizationMember in db.OrganizationMembers on project.OrganizationId equals organizationMember.OrganizationId
            where project.OrganizationId == organizationId
                && projectMember.UserId == userId && projectMember.Status == "active"
                && organizationMember.UserId == userId && organizationMember.Status == "active"
                && organizationMember.Role != "GUEST"
                && (projectMember.Role == "PROJECT_MANAGER" || projectMember.Role == "TEAM_LEAD")
            select project;

        if (!await db.OrganizationMembers.AnyAsync(x => x.OrganizationId == organizationId && x.UserId == userId && x.Status == "active", ct))
            return Forbid();

        var projects = await managedProjects
            .Where(project => project.DeletedAt != null && project.DeletedAt >= cutoff)
            .Select(project => new TrashItem("project", project.Id, null, project.Id, project.Name, project.DeletedAt!.Value))
            .ToListAsync(ct);

        var tasks = await (from task in db.Tasks.AsNoTracking()
            join project in db.Projects on task.ProjectId equals project.Id
            where project.OrganizationId == organizationId && project.DeletedAt == null && project.ArchivedAt == null
                && task.DeletedAt != null && task.DeletedAt >= cutoff
                && managedProjects.Any(managed => managed.Id == project.Id)
            select new TrashItem(task.ParentTaskId == null ? "task" : "subtask", task.Id, task.ParentTaskId, project.Id, task.Title, task.DeletedAt!.Value))
            .ToListAsync(ct);

        var comments = await (from comment in db.Comments.AsNoTracking()
            join task in db.Tasks on comment.TaskId equals task.Id
            join project in db.Projects on task.ProjectId equals project.Id
            where project.OrganizationId == organizationId && project.DeletedAt == null && project.ArchivedAt == null
                && task.DeletedAt == null && comment.DeletedAt != null && comment.DeletedAt >= cutoff
                && (comment.UserId == userId || managedProjects.Any(managed => managed.Id == project.Id))
            select new TrashItem("comment", comment.Id, task.Id, project.Id, comment.Content, comment.DeletedAt!.Value))
            .ToListAsync(ct);

        var attachments = await (from attachment in db.Attachments.AsNoTracking()
            join task in db.Tasks on attachment.TaskId equals task.Id
            join project in db.Projects on task.ProjectId equals project.Id
            where project.OrganizationId == organizationId && project.DeletedAt == null && project.ArchivedAt == null
                && task.DeletedAt == null && attachment.DeletedAt != null && attachment.DeletedAt >= cutoff
                && (attachment.UploadedBy == userId || managedProjects.Any(managed => managed.Id == project.Id))
            select new TrashItem("attachment", attachment.Id, task.Id, project.Id, attachment.FileName, attachment.DeletedAt!.Value))
            .ToListAsync(ct);

        return Ok(projects.Concat(tasks).Concat(comments).Concat(attachments)
            .OrderByDescending(item => item.DeletedAt)
            .Take(200));
    }
}

public sealed record TrashItem(string Kind, Guid Id, Guid? ParentId, Guid ProjectId, string Name, DateTime DeletedAt);
