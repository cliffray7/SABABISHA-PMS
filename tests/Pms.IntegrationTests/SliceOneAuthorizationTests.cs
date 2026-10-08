using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Pms.Api.Controllers.Rest.V1;
using Pms.Api.Realtime;
using Pms.Domain.Entities;
using Pms.Infrastructure.Persistence.EfCore;

namespace Pms.IntegrationTests;

public sealed class SliceOneAuthorizationTests
{
    [Theory]
    [InlineData("remove")]
    [InlineData("demote")]
    public async Task ProjectOwnerCannotLoseOwnerManagerMembershipBeforeTransfer(string action)
    {
        await using var database = await TestDatabase.Create();
        var fixture = await SeedProject(database.Context, "ADMIN", "PROJECT_MANAGER", "MEMBER", "PROJECT_MANAGER");
        await database.Context.Projects.Where(project => project.Id == fixture.ProjectId)
            .ExecuteUpdateAsync(update => update.SetProperty(project => project.OwnerId, fixture.TargetId));
        var controller = Projects(database.Context, fixture.ActorId);

        var result = action == "remove"
            ? await controller.RemoveMember(fixture.ProjectId, fixture.TargetId, default)
            : await controller.UpdateMemberRole(fixture.ProjectId, fixture.TargetId,
                new UpdateProjectMemberRoleRequest("CONTRIBUTOR"), default);

        AssertError(result, "project_owner_transfer_required");
        Assert.Equal("PROJECT_MANAGER", (await database.Context.ProjectMembers.SingleAsync(member => member.UserId == fixture.TargetId)).Role);
        Assert.Equal("active", (await database.Context.ProjectMembers.SingleAsync(member => member.UserId == fixture.TargetId)).Status);
    }

    [Theory]
    [InlineData("inactive")]
    [InlineData("suspended")]
    [InlineData("guest")]
    public async Task ManagerGuardDoesNotCountIneligibleOrganizationManagers(string state)
    {
        await using var database = await TestDatabase.Create();
        var fixture = await SeedProject(database.Context, "ADMIN", "TEAM_LEAD", "MEMBER", "PROJECT_MANAGER");
        await database.Context.Projects.Where(project => project.Id == fixture.ProjectId)
            .ExecuteUpdateAsync(update => update.SetProperty(project => project.OwnerId, fixture.ActorId));
        var targetOrgMember = await database.Context.OrganizationMembers.SingleAsync(member => member.UserId == fixture.TargetId);
        if (state == "inactive") targetOrgMember.Status = "inactive";
        if (state == "guest") targetOrgMember.Role = "GUEST";
        if (state == "suspended")
            (await database.Context.Users.SingleAsync(user => user.Id == fixture.TargetId)).Status = "suspended";
        await database.Context.SaveChangesAsync();

        var result = await Projects(database.Context, fixture.ActorId).RemoveMember(fixture.ProjectId, fixture.TargetId, default);

        AssertError(result, "project_must_retain_manager");
        Assert.Equal("active", (await database.Context.ProjectMembers.SingleAsync(member => member.UserId == fixture.TargetId)).Status);
    }

    [Fact]
    public async Task GuestLegacyManagerDoesNotCountAsManagerWhenAnotherManagerRemains()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await SeedProject(database.Context, "ADMIN", "TEAM_LEAD", "GUEST", "PROJECT_MANAGER");
        var alternateManagerId = await AddProjectMember(database.Context, fixture.OrganizationId, fixture.ProjectId, "PROJECT_MANAGER");
        await database.Context.Projects.Where(project => project.Id == fixture.ProjectId)
            .ExecuteUpdateAsync(update => update.SetProperty(project => project.OwnerId, alternateManagerId));

        var roleResult = await Projects(database.Context, fixture.ActorId).UpdateMemberRole(fixture.ProjectId, fixture.TargetId,
            new UpdateProjectMemberRoleRequest("VIEWER"), default);

        Assert.IsType<NoContentResult>(roleResult);
        Assert.Equal("VIEWER", (await database.Context.ProjectMembers.SingleAsync(member => member.UserId == fixture.TargetId)).Role);

        var removalResult = await Projects(database.Context, fixture.ActorId).RemoveMember(fixture.ProjectId, fixture.TargetId, default);

        Assert.IsType<NoContentResult>(removalResult);
        Assert.Equal("inactive", (await database.Context.ProjectMembers.SingleAsync(member => member.UserId == fixture.TargetId)).Status);
    }

    [Fact]
    public async Task OrganizationRoleDemotionToGuestClampsProjectRoleWhenManagerRemains()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await SeedProject(database.Context, "ADMIN", "PROJECT_MANAGER", "MEMBER", "TEAM_LEAD");
        var alternateManagerId = await AddProjectMember(database.Context, fixture.OrganizationId, fixture.ProjectId, "PROJECT_MANAGER");

        var result = await Organizations(database.Context, fixture.ActorId).Role(fixture.OrganizationId, fixture.TargetId,
            new UpdateRoleRequest("GUEST"), default);

        Assert.IsType<NoContentResult>(result);
        Assert.Equal("GUEST", (await database.Context.OrganizationMembers.SingleAsync(member => member.UserId == fixture.TargetId)).Role);
        Assert.Equal("VIEWER", (await database.Context.ProjectMembers.SingleAsync(member => member.UserId == fixture.TargetId)).Role);
        Assert.Equal("PROJECT_MANAGER", (await database.Context.ProjectMembers.SingleAsync(member => member.UserId == alternateManagerId)).Role);
        var clampEvent = await database.Context.ActivityEvents.SingleAsync(activity => activity.Action == "project.member_guest_role_clamped");
        Assert.Contains("TEAM_LEAD to VIEWER", clampEvent.Description);
        var audit = await database.Context.AdminAuditEvents.SingleAsync();
        Assert.Equal(fixture.ActorId, audit.ActorId);
        Assert.Equal(fixture.TargetId, audit.TargetId);
        Assert.Contains($"project_id={fixture.ProjectId}", audit.Reason);
        Assert.Contains("old_role=TEAM_LEAD", audit.Reason);
        Assert.Contains("new_role=VIEWER", audit.Reason);
    }

    [Fact]
    public async Task OrganizationRoleDemotionRejectsRemovingLastEligibleManager()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await SeedProject(database.Context, "ADMIN", "TEAM_LEAD", "MEMBER", "PROJECT_MANAGER");
        await database.Context.Projects.Where(project => project.Id == fixture.ProjectId)
            .ExecuteUpdateAsync(update => update.SetProperty(project => project.OwnerId, fixture.ActorId));

        var result = await Organizations(database.Context, fixture.ActorId).Role(fixture.OrganizationId, fixture.TargetId,
            new UpdateRoleRequest("GUEST"), default);

        AssertError(result, "organization_member_project_manager_required");
        Assert.Equal("MEMBER", (await database.Context.OrganizationMembers.SingleAsync(member => member.UserId == fixture.TargetId)).Role);
        Assert.Equal("PROJECT_MANAGER", (await database.Context.ProjectMembers.SingleAsync(member => member.UserId == fixture.TargetId)).Role);
    }

    [Fact]
    public async Task OrganizationRoleDemotionToGuestRevokesAssignmentWithoutDeletingHistory()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await SeedProject(database.Context, "ADMIN", "PROJECT_MANAGER", "MEMBER", "CONTRIBUTOR");
        var task = new WorkTask { Id = Guid.NewGuid(), ProjectId = fixture.ProjectId, Title = "Assigned", Status = "DONE", CreatedBy = fixture.ActorId };
        task.Assignees.Add(new TaskAssignee { Id = Guid.NewGuid(), UserId = fixture.TargetId });
        database.Context.Tasks.Add(task);
        await database.Context.SaveChangesAsync();

        var result = await Organizations(database.Context, fixture.ActorId).Role(fixture.OrganizationId, fixture.TargetId,
            new UpdateRoleRequest("GUEST"), default);

        Assert.IsType<NoContentResult>(result);
        Assert.Equal("GUEST", (await database.Context.OrganizationMembers.SingleAsync(member => member.UserId == fixture.TargetId)).Role);
        var historicalAssignment = await database.Context.TaskAssignees.SingleAsync();
        Assert.Equal(fixture.TargetId, historicalAssignment.UserId);
        Assert.Equal("inactive", historicalAssignment.Status);
        var assignmentHistory = await database.Context.ActivityEvents.SingleAsync(activity => activity.Action == "task.assignee_inactivated");
        Assert.Equal(task.Id, assignmentHistory.EntityId);
        Assert.Contains("Target Person's active assignment", assignmentHistory.Description);
    }

    [Fact]
    public async Task GuestRoleClampAndAdminAuditRollbackTogether()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await SeedProject(database.Context, "ADMIN", "PROJECT_MANAGER", "MEMBER", "TEAM_LEAD");
        await AddProjectMember(database.Context, fixture.OrganizationId, fixture.ProjectId, "PROJECT_MANAGER");
        var task = new WorkTask { Id = Guid.NewGuid(), ProjectId = fixture.ProjectId, Title = "Assigned", Status = "DONE", CreatedBy = fixture.ActorId };
        task.Assignees.Add(new TaskAssignee { Id = Guid.NewGuid(), UserId = fixture.TargetId });
        database.Context.Tasks.Add(task);
        await database.Context.SaveChangesAsync();
        await using (var trigger = database.Connection.CreateCommand())
        {
            trigger.CommandText = "CREATE TRIGGER fail_admin_audit BEFORE INSERT ON admin_audit_events BEGIN SELECT RAISE(ABORT, 'audit failure'); END;";
            await trigger.ExecuteNonQueryAsync();
        }

        await Assert.ThrowsAsync<DbUpdateException>(() => Organizations(database.Context, fixture.ActorId).Role(
            fixture.OrganizationId, fixture.TargetId, new UpdateRoleRequest("GUEST"), default));

        await using var verify = new PmsDbContext(new DbContextOptionsBuilder<PmsDbContext>()
            .UseSqlite(database.Connection).Options);
        Assert.Equal("MEMBER", (await verify.OrganizationMembers.SingleAsync(member => member.UserId == fixture.TargetId)).Role);
        Assert.Equal("TEAM_LEAD", (await verify.ProjectMembers.SingleAsync(member => member.UserId == fixture.TargetId)).Role);
        Assert.Equal("active", (await verify.TaskAssignees.SingleAsync()).Status);
        Assert.Empty(await verify.AdminAuditEvents.ToListAsync());
        Assert.Empty(await verify.ActivityEvents.ToListAsync());
    }

    [Fact]
    public async Task OrganizationRoleDemotionRejectsOwnerAndPreservesAllState()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await SeedProject(database.Context, "ADMIN", "PROJECT_MANAGER", "MEMBER", "PROJECT_MANAGER");
        await database.Context.Projects.Where(project => project.Id == fixture.ProjectId)
            .ExecuteUpdateAsync(update => update.SetProperty(project => project.OwnerId, fixture.TargetId));

        var result = await Organizations(database.Context, fixture.ActorId).Role(fixture.OrganizationId, fixture.TargetId,
            new UpdateRoleRequest("GUEST"), default);

        AssertError(result, "project_owner_transfer_required");
        Assert.Equal("MEMBER", (await database.Context.OrganizationMembers.SingleAsync(member => member.UserId == fixture.TargetId)).Role);
        Assert.Equal("PROJECT_MANAGER", (await database.Context.ProjectMembers.SingleAsync(member => member.UserId == fixture.TargetId)).Role);
    }

    [Fact]
    public async Task OrganizationRoleDemotionProtectsOwnerEvenWhenProjectMembershipIsInactive()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await SeedProject(database.Context, "ADMIN", "PROJECT_MANAGER", "MEMBER", "PROJECT_MANAGER");
        await database.Context.Projects.Where(project => project.Id == fixture.ProjectId)
            .ExecuteUpdateAsync(update => update.SetProperty(project => project.OwnerId, fixture.TargetId));
        await database.Context.ProjectMembers.Where(member => member.ProjectId == fixture.ProjectId && member.UserId == fixture.TargetId)
            .ExecuteUpdateAsync(update => update.SetProperty(member => member.Status, "inactive"));

        var result = await Organizations(database.Context, fixture.ActorId).Role(fixture.OrganizationId, fixture.TargetId,
            new UpdateRoleRequest("GUEST"), default);

        AssertError(result, "project_owner_transfer_required");
        Assert.Equal("MEMBER", (await database.Context.OrganizationMembers.SingleAsync(member => member.UserId == fixture.TargetId)).Role);
    }

    [Fact]
    public async Task OrganizationDeactivationValidatesAllProjectsBeforeChangingAnyState()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await SeedProject(database.Context, "ADMIN", "PROJECT_MANAGER", "MEMBER", "PROJECT_MANAGER");
        var secondProjectId = await AddProject(database.Context, fixture.OrganizationId, fixture.TargetId, "PROJECT_MANAGER");
        await AddProjectMember(database.Context, fixture.OrganizationId, secondProjectId, "CONTRIBUTOR", fixture.ActorId);
        await database.Context.Projects.Where(project => project.Id == fixture.ProjectId)
            .ExecuteUpdateAsync(update => update.SetProperty(project => project.OwnerId, fixture.ActorId));
        await database.Context.Projects.Where(project => project.Id == secondProjectId)
            .ExecuteUpdateAsync(update => update.SetProperty(project => project.OwnerId, fixture.ActorId));

        var result = await Organizations(database.Context, fixture.ActorId).RemoveMember(fixture.OrganizationId, fixture.TargetId, default);

        AssertError(result, "organization_member_project_manager_required");
        Assert.Equal("active", (await database.Context.OrganizationMembers.SingleAsync(member => member.UserId == fixture.TargetId)).Status);
        Assert.All(await database.Context.ProjectMembers.Where(member => member.UserId == fixture.TargetId).ToListAsync(),
            member => Assert.Equal("active", member.Status));
        Assert.Equal("active", (await database.Context.ProjectMembers.SingleAsync(member => member.ProjectId == secondProjectId && member.UserId == fixture.ActorId)).Status);
    }

    [Fact]
    public async Task OrganizationDeactivationRejectsOwnerUntilTransfer()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await SeedProject(database.Context, "ADMIN", "PROJECT_MANAGER", "MEMBER", "PROJECT_MANAGER");
        await database.Context.Projects.Where(project => project.Id == fixture.ProjectId)
            .ExecuteUpdateAsync(update => update.SetProperty(project => project.OwnerId, fixture.TargetId));

        var result = await Organizations(database.Context, fixture.ActorId).RemoveMember(fixture.OrganizationId, fixture.TargetId, default);

        AssertError(result, "project_owner_transfer_required");
        Assert.Equal("active", (await database.Context.OrganizationMembers.SingleAsync(member => member.UserId == fixture.TargetId)).Status);
    }

    [Fact]
    public async Task OrganizationDeactivationProtectsOwnerEvenWhenProjectMembershipIsInactive()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await SeedProject(database.Context, "ADMIN", "PROJECT_MANAGER", "MEMBER", "PROJECT_MANAGER");
        await database.Context.Projects.Where(project => project.Id == fixture.ProjectId)
            .ExecuteUpdateAsync(update => update.SetProperty(project => project.OwnerId, fixture.TargetId));
        await database.Context.ProjectMembers.Where(member => member.ProjectId == fixture.ProjectId && member.UserId == fixture.TargetId)
            .ExecuteUpdateAsync(update => update.SetProperty(member => member.Status, "inactive"));

        var result = await Organizations(database.Context, fixture.ActorId).RemoveMember(fixture.OrganizationId, fixture.TargetId, default);

        AssertError(result, "project_owner_transfer_required");
        Assert.Equal("active", (await database.Context.OrganizationMembers.SingleAsync(member => member.UserId == fixture.TargetId)).Status);
    }

    [Fact]
    public async Task OrganizationDeactivationRejectsOpenAssignmentsUntilTheyCanBeResolved()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await SeedProject(database.Context, "ADMIN", "PROJECT_MANAGER", "MEMBER", "CONTRIBUTOR");
        var task = new WorkTask { Id = Guid.NewGuid(), ProjectId = fixture.ProjectId, Title = "Open task", Status = "IN PROGRESS", CreatedBy = fixture.ActorId };
        task.Assignees.Add(new TaskAssignee { Id = Guid.NewGuid(), UserId = fixture.TargetId });
        database.Context.Tasks.Add(task);
        await database.Context.SaveChangesAsync();

        var result = await Organizations(database.Context, fixture.ActorId).RemoveMember(fixture.OrganizationId, fixture.TargetId, default);

        AssertError(result, "organization_member_open_tasks_require_resolution");
        Assert.Equal("active", (await database.Context.OrganizationMembers.SingleAsync(member => member.UserId == fixture.TargetId)).Status);
        Assert.Equal("active", (await database.Context.ProjectMembers.SingleAsync(member => member.UserId == fixture.TargetId)).Status);
        Assert.Equal("active", (await database.Context.TaskAssignees.SingleAsync()).Status);
    }

    [Fact]
    public async Task ProjectMemberRemovalRejectsOpenAssignmentsUntilTheyCanBeResolved()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await SeedProject(database.Context, "MEMBER", "PROJECT_MANAGER", "MEMBER", "CONTRIBUTOR");
        var task = new WorkTask { Id = Guid.NewGuid(), ProjectId = fixture.ProjectId, Title = "Open task", Status = "IN PROGRESS", CreatedBy = fixture.ActorId };
        task.Assignees.Add(new TaskAssignee { Id = Guid.NewGuid(), UserId = fixture.TargetId });
        database.Context.Tasks.Add(task);
        await database.Context.SaveChangesAsync();

        var result = await Projects(database.Context, fixture.ActorId).RemoveMember(fixture.ProjectId, fixture.TargetId, default);

        AssertError(result, "project_member_open_tasks_require_resolution");
        Assert.Equal("active", (await database.Context.ProjectMembers.SingleAsync(member => member.UserId == fixture.TargetId)).Status);
        Assert.Equal("active", (await database.Context.TaskAssignees.SingleAsync()).Status);
    }

    [Fact]
    public async Task OrganizationDeactivationCommitsAcrossProjectsWhenAllInvariantsHold()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await SeedProject(database.Context, "ADMIN", "PROJECT_MANAGER", "MEMBER", "CONTRIBUTOR");
        var secondProjectId = await AddProject(database.Context, fixture.OrganizationId, fixture.ActorId, "PROJECT_MANAGER");
        await AddProjectMember(database.Context, fixture.OrganizationId, secondProjectId, "CONTRIBUTOR", fixture.TargetId);
        var completedTask = new WorkTask { Id = Guid.NewGuid(), ProjectId = fixture.ProjectId, Title = "Completed", Status = "DONE", CreatedBy = fixture.ActorId };
        completedTask.Assignees.Add(new TaskAssignee { Id = Guid.NewGuid(), UserId = fixture.TargetId });
        database.Context.Tasks.Add(completedTask);
        database.Context.RefreshTokens.Add(new RefreshToken
        {
            Id = Guid.NewGuid(), UserId = fixture.TargetId, TokenHash = "refresh-hash", ExpiresAt = DateTime.UtcNow.AddDays(1)
        });
        await database.Context.SaveChangesAsync();

        var result = await Organizations(database.Context, fixture.ActorId).RemoveMember(fixture.OrganizationId, fixture.TargetId, default);

        Assert.IsType<NoContentResult>(result);
        Assert.Equal("inactive", (await database.Context.OrganizationMembers.SingleAsync(member => member.UserId == fixture.TargetId)).Status);
        Assert.All(await database.Context.ProjectMembers.Where(member => member.UserId == fixture.TargetId).ToListAsync(),
            member => Assert.Equal("inactive", member.Status));
        Assert.Equal("inactive", (await database.Context.TaskAssignees.SingleAsync()).Status);
        Assert.NotNull((await database.Context.RefreshTokens.SingleAsync()).RevokedAt);
        Assert.Single(await database.Context.ActivityEvents.Where(activity => activity.Action == "organization.member_removed").ToListAsync());
    }

    [Theory]
    [InlineData("guest")]
    [InlineData("inactive-org")]
    [InlineData("suspended")]
    [InlineData("inactive-project")]
    [InlineData("foreign-org-membership")]
    public async Task TaskCreationRejectsIneligibleAssignees(string ineligibility)
    {
        await using var database = await TestDatabase.Create();
        var fixture = await SeedProject(database.Context, "MEMBER", "PROJECT_MANAGER", "MEMBER", "CONTRIBUTOR");
        await MakeAssigneeIneligible(database.Context, fixture, ineligibility);

        var result = await Tasks(database.Context, fixture.ActorId).Create(fixture.ProjectId,
            new CreateTaskRequest("Task", null, null, null, null, [fixture.TargetId]), default);

        AssertErrorMessage(result, "eligible active project member");
        Assert.Empty(await database.Context.Tasks.ToListAsync());
    }

    [Theory]
    [InlineData("guest")]
    [InlineData("inactive-org")]
    [InlineData("suspended")]
    [InlineData("inactive-project")]
    [InlineData("foreign-org-membership")]
    public async Task TaskUpdateRejectsGuestAndInactiveAssignees(string ineligibility)
    {
        await using var database = await TestDatabase.Create();
        var fixture = await SeedProject(database.Context, "MEMBER", "PROJECT_MANAGER", "MEMBER", "CONTRIBUTOR");
        var task = new WorkTask { Id = Guid.NewGuid(), ProjectId = fixture.ProjectId, Title = "Existing", Status = "TO DO", CreatedBy = fixture.ActorId };
        task.Assignees.Add(new TaskAssignee { Id = Guid.NewGuid(), UserId = fixture.TargetId });
        database.Context.Tasks.Add(task);
        await database.Context.SaveChangesAsync();
        await MakeAssigneeIneligible(database.Context, fixture, ineligibility);

        var result = await Tasks(database.Context, fixture.ActorId).Update(task.Id,
            new UpdateTaskRequest(null, null, null, null, null, [fixture.TargetId]), default);

        AssertErrorMessage(result, "eligible active project member");
        var retainedAssignment = await database.Context.TaskAssignees.SingleAsync();
        Assert.Equal(fixture.TargetId, retainedAssignment.UserId);
        Assert.Equal("active", retainedAssignment.Status);
    }

    [Theory]
    [InlineData("guest")]
    [InlineData("suspended")]
    public async Task TaskUpdateWithoutAssigneeIdsPreservesHistoryButHidesIneligibleAssigneeAndNotifications(string ineligibility)
    {
        await using var database = await TestDatabase.Create();
        var fixture = await SeedProject(database.Context, "ADMIN", "PROJECT_MANAGER", "MEMBER", "CONTRIBUTOR");
        var task = new WorkTask { Id = Guid.NewGuid(), ProjectId = fixture.ProjectId, Title = "Before", Status = "TO DO", CreatedBy = fixture.ActorId };
        task.Assignees.Add(new TaskAssignee { Id = Guid.NewGuid(), UserId = fixture.TargetId });
        database.Context.Tasks.Add(task);
        database.Context.Notifications.Add(new Notification
        {
            Id = Guid.NewGuid(), UserId = fixture.TargetId, Type = "TASK_ASSIGNED", Message = "You were assigned.", EntityType = "TASK", RelatedId = task.Id
        });
        await database.Context.SaveChangesAsync();
        if (ineligibility == "guest")
        {
            var demotion = await Organizations(database.Context, fixture.ActorId).Role(fixture.OrganizationId, fixture.TargetId,
                new UpdateRoleRequest("GUEST"), default);
            Assert.IsType<NoContentResult>(demotion);
        }
        else
        {
            (await database.Context.Users.SingleAsync(user => user.Id == fixture.TargetId)).Status = "suspended";
            await database.Context.SaveChangesAsync();
        }

        var update = await Tasks(database.Context, fixture.ActorId).Update(task.Id,
            new UpdateTaskRequest("After", null, null, null, null), default);

        Assert.IsType<OkObjectResult>(update);
        Assert.Equal("After", (await database.Context.Tasks.SingleAsync(item => item.Id == task.Id)).Title);
        var historicalAssignment = await database.Context.TaskAssignees.SingleAsync();
        Assert.Equal(fixture.TargetId, historicalAssignment.UserId);
        Assert.Equal(ineligibility == "guest" ? "inactive" : "active", historicalAssignment.Status);

        var list = Assert.IsType<OkObjectResult>(await Tasks(database.Context, fixture.ActorId).List(fixture.ProjectId, default));
        var data = list.Value!.GetType().GetProperty("data")!.GetValue(list.Value) as System.Collections.IEnumerable;
        var row = data!.Cast<object>().Single();
        var effectiveAssignees = (Guid[])row.GetType().GetProperty("assigneeIds")!.GetValue(row)!;
        Assert.Empty(effectiveAssignees);

        var collaboration = Collaboration(database.Context, fixture.ActorId);
        var commentResult = await collaboration.Comment(task.Id, new CommentRequest("A comment", [], null), default);
        Assert.IsType<OkObjectResult>(commentResult);
        Assert.Empty(await database.Context.Notifications.Where(notification => notification.UserId == fixture.TargetId
            && notification.Type == "COMMENT").ToListAsync());

        var notifications = Collaboration(database.Context, fixture.TargetId);
        var response = Assert.IsType<OkObjectResult>(await notifications.Notifications(default));
        var visibleNotifications = Assert.IsAssignableFrom<System.Collections.IEnumerable>(response.Value);
        Assert.Empty(visibleNotifications.Cast<object>());
    }

    [Fact]
    public async Task RestoringProjectMemberDoesNotRestoreOldAssignmentUntilExplicitlyReassigned()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await SeedProject(database.Context, "ADMIN", "PROJECT_MANAGER", "MEMBER", "CONTRIBUTOR");
        var task = new WorkTask { Id = Guid.NewGuid(), ProjectId = fixture.ProjectId, Title = "Done", Status = "DONE", CreatedBy = fixture.ActorId };
        task.Assignees.Add(new TaskAssignee { Id = Guid.NewGuid(), UserId = fixture.TargetId });
        database.Context.Tasks.Add(task);
        await database.Context.SaveChangesAsync();

        var removal = await Projects(database.Context, fixture.ActorId).RemoveMember(fixture.ProjectId, fixture.TargetId, default);
        Assert.IsType<NoContentResult>(removal);
        Assert.Equal("inactive", (await database.Context.TaskAssignees.SingleAsync()).Status);
        Assert.Contains(await database.Context.ActivityEvents.ToListAsync(), activity => activity.Action == "task.assignee_inactivated"
            && activity.EntityId == task.Id && activity.Description.Contains("Target Person's active assignment"));

        await database.Context.ProjectMembers.Where(member => member.ProjectId == fixture.ProjectId && member.UserId == fixture.TargetId)
            .ExecuteUpdateAsync(update => update.SetProperty(member => member.Status, "active"));
        var list = Assert.IsType<OkObjectResult>(await Tasks(database.Context, fixture.ActorId).List(fixture.ProjectId, default));
        var rows = (System.Collections.IEnumerable)list.Value!.GetType().GetProperty("data")!.GetValue(list.Value)!;
        var row = rows.Cast<object>().Single();
        Assert.Empty((Guid[])row.GetType().GetProperty("assigneeIds")!.GetValue(row)!);

        var reassignment = await Tasks(database.Context, fixture.ActorId).Update(task.Id,
            new UpdateTaskRequest(null, null, null, null, null, [fixture.TargetId]), default);
        Assert.IsType<OkObjectResult>(reassignment);
        Assert.Equal("active", (await database.Context.TaskAssignees.SingleAsync()).Status);
    }

    private static async Task<Fixture> SeedProject(PmsDbContext db, string actorOrgRole, string actorProjectRole,
        string targetOrgRole, string targetProjectRole)
    {
        var organizationId = Guid.NewGuid(); var projectId = Guid.NewGuid();
        var actorId = Guid.NewGuid(); var targetId = Guid.NewGuid();
        db.Organizations.Add(new Organization { Id = organizationId, Name = "Organization", Slug = $"org-{organizationId:N}" });
        db.Projects.Add(new Project { Id = projectId, OrganizationId = organizationId, OwnerId = actorId, Name = "Project" });
        db.Users.AddRange(User(actorId, "Actor"), User(targetId, "Target"));
        db.OrganizationMembers.AddRange(
            new OrganizationMember { Id = Guid.NewGuid(), OrganizationId = organizationId, UserId = actorId, Role = actorOrgRole },
            new OrganizationMember { Id = Guid.NewGuid(), OrganizationId = organizationId, UserId = targetId, Role = targetOrgRole });
        db.ProjectMembers.AddRange(
            new ProjectMember { Id = Guid.NewGuid(), ProjectId = projectId, UserId = actorId, Role = actorProjectRole },
            new ProjectMember { Id = Guid.NewGuid(), ProjectId = projectId, UserId = targetId, Role = targetProjectRole });
        await db.SaveChangesAsync();
        return new Fixture(organizationId, projectId, actorId, targetId);
    }

    private static async Task MakeAssigneeIneligible(PmsDbContext db, Fixture fixture, string ineligibility)
    {
        var targetOrgMember = await db.OrganizationMembers.SingleAsync(member => member.UserId == fixture.TargetId);
        if (ineligibility == "guest") targetOrgMember.Role = "GUEST";
        if (ineligibility == "inactive-org") targetOrgMember.Status = "inactive";
        if (ineligibility == "suspended")
            (await db.Users.SingleAsync(user => user.Id == fixture.TargetId)).Status = "suspended";
        if (ineligibility == "inactive-project")
            (await db.ProjectMembers.SingleAsync(member => member.ProjectId == fixture.ProjectId && member.UserId == fixture.TargetId)).Status = "inactive";
        if (ineligibility == "foreign-org-membership")
        {
            var foreignOrganizationId = Guid.NewGuid();
            db.Organizations.Add(new Organization { Id = foreignOrganizationId, Name = "Foreign", Slug = $"foreign-{foreignOrganizationId:N}" });
            targetOrgMember.OrganizationId = foreignOrganizationId;
        }
        await db.SaveChangesAsync();
    }

    private static async Task<Guid> AddProject(PmsDbContext db, Guid organizationId, Guid ownerId, string managerRole)
    {
        var projectId = Guid.NewGuid();
        db.Projects.Add(new Project { Id = projectId, OrganizationId = organizationId, OwnerId = ownerId, Name = "Second project" });
        db.ProjectMembers.Add(new ProjectMember { Id = Guid.NewGuid(), ProjectId = projectId, UserId = ownerId, Role = managerRole });
        await db.SaveChangesAsync();
        return projectId;
    }

    private static async Task<Guid> AddProjectMember(PmsDbContext db, Guid organizationId, Guid projectId, string role, Guid? userId = null)
    {
        var id = userId ?? Guid.NewGuid();
        if (userId is null)
        {
            db.Users.Add(User(id, "Additional"));
            db.OrganizationMembers.Add(new OrganizationMember { Id = Guid.NewGuid(), OrganizationId = organizationId, UserId = id, Role = "MEMBER" });
        }
        db.ProjectMembers.Add(new ProjectMember { Id = Guid.NewGuid(), ProjectId = projectId, UserId = id, Role = role });
        await db.SaveChangesAsync();
        return id;
    }

    private static ProjectsController Projects(PmsDbContext db, Guid actorId)
    {
        var controller = new ProjectsController(db, new RealtimePublisher(new TestHubContext()));
        SetContext(controller, actorId);
        return controller;
    }

    private static OrganizationsController Organizations(PmsDbContext db, Guid actorId)
    {
        var controller = new OrganizationsController(db, null!, null!, new RealtimePublisher(new TestHubContext()));
        SetContext(controller, actorId);
        return controller;
    }

    private static TasksController Tasks(PmsDbContext db, Guid actorId)
    {
        var controller = new TasksController(db, null!, new RealtimePublisher(new TestHubContext()));
        SetContext(controller, actorId);
        return controller;
    }

    private static CollaborationController Collaboration(PmsDbContext db, Guid actorId)
    {
        var controller = new CollaborationController(db, null!, null!, null!,
            Microsoft.Extensions.Logging.Abstractions.NullLogger<CollaborationController>.Instance,
            new RealtimePublisher(new TestHubContext()));
        SetContext(controller, actorId);
        return controller;
    }

    private static void SetContext(ControllerBase controller, Guid actorId)
    {
        var http = new DefaultHttpContext
        {
            User = new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier, actorId.ToString())], "test"))
        };
        http.TraceIdentifier = Guid.NewGuid().ToString();
        controller.ControllerContext = new ControllerContext { HttpContext = http };
    }

    private static void AssertError(IActionResult result, string code)
    {
        var response = Assert.IsAssignableFrom<ObjectResult>(result);
        Assert.Equal(code, response.Value?.GetType().GetProperty("code")?.GetValue(response.Value));
    }

    private static void AssertErrorMessage(IActionResult result, string messagePart)
    {
        var response = Assert.IsType<BadRequestObjectResult>(result);
        Assert.Contains(messagePart, response.Value?.GetType().GetProperty("message")?.GetValue(response.Value)?.ToString());
    }

    private static User User(Guid id, string name) => new()
    {
        Id = id, FirstName = name, LastName = "Person", Email = $"{id}@example.test", PasswordHash = "hash"
    };

    private sealed record Fixture(Guid OrganizationId, Guid ProjectId, Guid ActorId, Guid TargetId);

    private sealed class TestDatabase : IAsyncDisposable
    {
        private TestDatabase(SqliteConnection connection, PmsDbContext context) { Connection = connection; Context = context; }
        public SqliteConnection Connection { get; }
        public PmsDbContext Context { get; }
        public static async Task<TestDatabase> Create()
        {
            var connection = new SqliteConnection("Data Source=:memory:");
            await connection.OpenAsync();
            var context = new PmsDbContext(new DbContextOptionsBuilder<PmsDbContext>().UseSqlite(connection).Options);
            await context.Database.EnsureCreatedAsync();
            return new TestDatabase(connection, context);
        }
        public async ValueTask DisposeAsync() { await Context.DisposeAsync(); await Connection.DisposeAsync(); }
    }

    private sealed class TestHubContext : IHubContext<WorkspaceHub>
    {
        public IHubClients Clients { get; } = new TestHubClients();
        public IGroupManager Groups { get; } = new TestGroupManager();
    }
    private sealed class TestHubClients : IHubClients
    {
        private static readonly IClientProxy Proxy = new TestClientProxy();
        public IClientProxy All => Proxy;
        public IClientProxy AllExcept(IReadOnlyList<string> excludedConnectionIds) => Proxy;
        public IClientProxy Client(string connectionId) => Proxy;
        public IClientProxy Clients(IReadOnlyList<string> connectionIds) => Proxy;
        public IClientProxy Group(string groupName) => Proxy;
        public IClientProxy GroupExcept(string groupName, IReadOnlyList<string> excludedConnectionIds) => Proxy;
        public IClientProxy Groups(IReadOnlyList<string> groupNames) => Proxy;
        public IClientProxy User(string userId) => Proxy;
        public IClientProxy Users(IReadOnlyList<string> userIds) => Proxy;
    }
    private sealed class TestClientProxy : IClientProxy
    {
        public Task SendCoreAsync(string method, object?[] args, CancellationToken cancellationToken = default) => Task.CompletedTask;
    }
    private sealed class TestGroupManager : IGroupManager
    {
        public Task AddToGroupAsync(string connectionId, string groupName, CancellationToken cancellationToken = default) => Task.CompletedTask;
        public Task RemoveFromGroupAsync(string connectionId, string groupName, CancellationToken cancellationToken = default) => Task.CompletedTask;
    }
}
