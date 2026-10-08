using System.Data;
using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.Logging.Abstractions;
using Pms.Api.Controllers.Rest.V1;
using Pms.Api.Realtime;
using Pms.Domain.Entities;
using Pms.Infrastructure.Persistence.EfCore;

namespace Pms.IntegrationTests;

public sealed class ProjectMemberRoleUpdateTests
{
    [Theory]
    [InlineData("ADMIN")]
    [InlineData("OWNER")]
    [InlineData("MEMBER")]
    [InlineData("GUEST")]
    public async Task RoleUpdate_EnforcesActorPolicyAndAuditsSuccess(string actorOrganizationRole)
    {
        await using var database = await TestDatabase.Create();
        var f = await Seed(database.Context, actorOrganizationRole, "PROJECT_MANAGER");
        var controller = Controller(database.Context, f.ActorId);

        var result = await controller.UpdateMemberRole(f.ProjectId, f.TargetId,
            new UpdateProjectMemberRoleRequest("CONTRIBUTOR"), CancellationToken.None);

        if (actorOrganizationRole is "ADMIN" or "OWNER" or "MEMBER")
        {
            Assert.IsType<NoContentResult>(result);
            Assert.Equal("CONTRIBUTOR", (await database.Context.ProjectMembers.SingleAsync(x => x.UserId == f.TargetId)).Role);
            var audit = await database.Context.AdminAuditEvents.SingleAsync();
            Assert.Equal(f.ActorId, audit.ActorId);
            Assert.Equal(f.TargetId, audit.TargetId);
            Assert.Equal("project.member_role_changed", audit.Action);
            Assert.Contains($"project_id={f.ProjectId}", audit.Reason);
            Assert.Contains("old_role=VIEWER", audit.Reason);
            Assert.Contains("new_role=CONTRIBUTOR", audit.Reason);
        }
        else
        {
            AssertError(result, "project_role_update_forbidden");
            Assert.Empty(await database.Context.AdminAuditEvents.ToListAsync());
        }
    }

    [Fact]
    public async Task RoleUpdate_ProjectManagerCanGrantManagerAndNoOpDoesNotAddAudit()
    {
        await using var database = await TestDatabase.Create();
        var f = await Seed(database.Context, "MEMBER", "PROJECT_MANAGER");
        var controller = Controller(database.Context, f.ActorId);
        Assert.IsType<NoContentResult>(await controller.UpdateMemberRole(f.ProjectId, f.TargetId,
            new UpdateProjectMemberRoleRequest("PROJECT_MANAGER"), CancellationToken.None));
        Assert.Single(await database.Context.AdminAuditEvents.ToListAsync());
        Assert.IsType<NoContentResult>(await controller.UpdateMemberRole(f.ProjectId, f.TargetId,
            new UpdateProjectMemberRoleRequest("PROJECT_MANAGER"), CancellationToken.None));
        Assert.Single(await database.Context.AdminAuditEvents.ToListAsync());
    }

    [Theory]
    [InlineData("ADMIN")]
    [InlineData("OWNER")]
    public async Task OrganizationAdminsCanGrantProjectManager(string organizationRole)
    {
        await using var database = await TestDatabase.Create();
        var f = await Seed(database.Context, organizationRole, "TEAM_LEAD");
        var result = await Controller(database.Context, f.ActorId).UpdateMemberRole(f.ProjectId, f.TargetId,
            new UpdateProjectMemberRoleRequest("PROJECT_MANAGER"), CancellationToken.None);
        Assert.IsType<NoContentResult>(result);
        Assert.Equal("PROJECT_MANAGER", (await database.Context.ProjectMembers.SingleAsync(x => x.UserId == f.TargetId)).Role);
        Assert.Single(await database.Context.AdminAuditEvents.ToListAsync());
    }

    [Theory]
    [InlineData("NO_SUCH_ROLE", "bad-request")]
    [InlineData("PROJECT_MANAGER", "forbid-team-lead")]
    public async Task RoleUpdate_RejectsInvalidRoleAndTeamLeadPromotion(string role, string expected)
    {
        await using var database = await TestDatabase.Create();
        var f = await Seed(database.Context, "MEMBER", expected == "bad-request" ? "PROJECT_MANAGER" : "TEAM_LEAD");
        var result = await Controller(database.Context, f.ActorId).UpdateMemberRole(f.ProjectId, f.TargetId,
            new UpdateProjectMemberRoleRequest(role), CancellationToken.None);
        if (expected == "bad-request") AssertError(result, "invalid_project_role");
        else AssertError(result, "project_manager_grant_forbidden");
        Assert.Empty(await database.Context.AdminAuditEvents.ToListAsync());
    }

    [Theory]
    [InlineData("PROJECT_MANAGER")]
    [InlineData("TEAM_LEAD")]
    [InlineData("CONTRIBUTOR")]
    public async Task RoleUpdate_RejectsGuestPromotionAboveViewer(string requestedRole)
    {
        await using var database = await TestDatabase.Create();
        var guest = await Seed(database.Context, "MEMBER", "PROJECT_MANAGER", targetOrganizationRole: "GUEST");
        var result = await Controller(database.Context, guest.ActorId).UpdateMemberRole(
            guest.ProjectId, guest.TargetId, new UpdateProjectMemberRoleRequest(requestedRole), CancellationToken.None);
        AssertError(result, "guest_project_role_must_be_viewer");
        Assert.Empty(await database.Context.AdminAuditEvents.ToListAsync());
    }

    [Fact]
    public async Task RoleUpdate_RejectsLastManagerDemotion()
    {
        await using var lastManagerDb = await TestDatabase.Create();
        var manager = await Seed(lastManagerDb.Context, "MEMBER", "TEAM_LEAD", targetRole: "PROJECT_MANAGER");
        var result = await Controller(lastManagerDb.Context, manager.TargetId).UpdateMemberRole(
            manager.ProjectId, manager.TargetId, new UpdateProjectMemberRoleRequest("TEAM_LEAD"), CancellationToken.None);
        AssertError(result, "project_must_retain_manager");
        Assert.Empty(await lastManagerDb.Context.AdminAuditEvents.ToListAsync());
    }

    [Fact]
    public async Task ProjectManagerMayDemoteThemselvesWhenAnotherActiveManagerRemains()
    {
        await using var database = await TestDatabase.Create();
        var f = await Seed(database.Context, "MEMBER", "PROJECT_MANAGER");
        var otherManagerId = Guid.NewGuid();
        database.Context.Users.Add(User(otherManagerId, "Other", $"{otherManagerId}@example.test"));
        var organizationId = await database.Context.Projects.Where(x => x.Id == f.ProjectId)
            .Select(x => x.OrganizationId).SingleAsync();
        database.Context.OrganizationMembers.Add(new OrganizationMember
        {
            Id = Guid.NewGuid(), OrganizationId = organizationId, UserId = otherManagerId, Role = "MEMBER"
        });
        database.Context.ProjectMembers.Add(new ProjectMember
        {
            Id = Guid.NewGuid(), ProjectId = f.ProjectId, UserId = otherManagerId, Role = "PROJECT_MANAGER"
        });
        await database.Context.Projects.Where(project => project.Id == f.ProjectId)
            .ExecuteUpdateAsync(update => update.SetProperty(project => project.OwnerId, otherManagerId));
        await database.Context.SaveChangesAsync();

        var result = await Controller(database.Context, f.ActorId).UpdateMemberRole(f.ProjectId, f.ActorId,
            new UpdateProjectMemberRoleRequest("CONTRIBUTOR"), CancellationToken.None);

        Assert.IsType<NoContentResult>(result);
        Assert.Equal("CONTRIBUTOR", (await database.Context.ProjectMembers.SingleAsync(x => x.UserId == f.ActorId)).Role);
        Assert.Equal(1, await database.Context.ProjectMembers.CountAsync(x => x.ProjectId == f.ProjectId
            && x.Role == "PROJECT_MANAGER" && x.Status == "active"));
        Assert.Single(await database.Context.AdminAuditEvents.ToListAsync());
    }

    [Fact]
    public async Task LowerRoleCannotDemoteAProjectManager()
    {
        await using var database = await TestDatabase.Create();
        var f = await Seed(database.Context, "MEMBER", "TEAM_LEAD", targetRole: "PROJECT_MANAGER");

        var result = await Controller(database.Context, f.ActorId).UpdateMemberRole(f.ProjectId, f.TargetId,
            new UpdateProjectMemberRoleRequest("CONTRIBUTOR"), CancellationToken.None);

        AssertError(result, "project_role_update_forbidden");
        Assert.Equal("PROJECT_MANAGER", (await database.Context.ProjectMembers.SingleAsync(x => x.UserId == f.TargetId)).Role);
    }

    [Fact]
    public async Task RoleUpdate_RejectsSelfAndCrossTenantTarget()
    {
        await using var database = await TestDatabase.Create();
        var f = await Seed(database.Context, "MEMBER", "PROJECT_MANAGER");
        var foreignOrganizationId = Guid.NewGuid();
        var foreignUserId = Guid.NewGuid();
        database.Context.Organizations.Add(new Organization
        {
            Id = foreignOrganizationId, Name = "Foreign organization", Slug = $"foreign-{foreignOrganizationId:N}"
        });
        database.Context.Users.Add(User(foreignUserId, "Foreign", $"{foreignUserId}@example.test"));
        database.Context.OrganizationMembers.Add(new OrganizationMember
        {
            Id = Guid.NewGuid(), OrganizationId = foreignOrganizationId, UserId = foreignUserId, Role = "MEMBER"
        });
        await database.Context.SaveChangesAsync();
        AssertError(await Controller(database.Context, f.ActorId).UpdateMemberRole(
            f.ProjectId, f.ActorId, new UpdateProjectMemberRoleRequest("CONTRIBUTOR"), CancellationToken.None),
            "project_owner_transfer_required");
        Assert.IsType<NotFoundResult>(await Controller(database.Context, f.ActorId).UpdateMemberRole(
            f.ProjectId, foreignUserId, new UpdateProjectMemberRoleRequest("CONTRIBUTOR"), CancellationToken.None));
        Assert.Empty(await database.Context.AdminAuditEvents.ToListAsync());
    }

    [Fact]
    public async Task NonManagerCannotChangeOwnRoleEvenWhenOrganizationAdmin()
    {
        await using var database = await TestDatabase.Create();
        var f = await Seed(database.Context, "ADMIN", "CONTRIBUTOR", targetRole: "CONTRIBUTOR");
        var ownerId = Guid.NewGuid();
        database.Context.Users.Add(User(ownerId, "Project", $"{ownerId}@example.test"));
        var organizationId = await database.Context.Projects.Where(project => project.Id == f.ProjectId)
            .Select(project => project.OrganizationId).SingleAsync();
        database.Context.OrganizationMembers.Add(new OrganizationMember
        {
            Id = Guid.NewGuid(), OrganizationId = organizationId, UserId = ownerId, Role = "MEMBER"
        });
        database.Context.ProjectMembers.Add(new ProjectMember
        {
            Id = Guid.NewGuid(), ProjectId = f.ProjectId, UserId = ownerId, Role = "PROJECT_MANAGER"
        });
        await database.Context.Projects.Where(project => project.Id == f.ProjectId)
            .ExecuteUpdateAsync(update => update.SetProperty(project => project.OwnerId, ownerId));
        await database.Context.SaveChangesAsync();
        var result = await Controller(database.Context, f.ActorId).UpdateMemberRole(f.ProjectId, f.ActorId,
            new UpdateProjectMemberRoleRequest("VIEWER"), CancellationToken.None);
        AssertError(result, "self_role_change_not_allowed");
        Assert.Equal("CONTRIBUTOR", (await database.Context.ProjectMembers.SingleAsync(x => x.UserId == f.ActorId)).Role);
    }

    [Fact]
    public async Task MemberRemoval_RejectsRemovingLastActiveManager()
    {
        await using var database = await TestDatabase.Create();
        var f = await Seed(database.Context, "MEMBER", "TEAM_LEAD", targetRole: "PROJECT_MANAGER");
        var result = await Controller(database.Context, f.ActorId).RemoveMember(f.ProjectId, f.TargetId, CancellationToken.None);
        AssertError(result, "project_must_retain_manager");
        Assert.Equal("active", (await database.Context.ProjectMembers.SingleAsync(x => x.UserId == f.TargetId)).Status);
    }

    [Theory]
    [InlineData("inactive-organization-membership")]
    [InlineData("suspended-user")]
    public async Task ManagerInvariant_DoesNotCountInactiveOrSuspendedManagers(string inactiveState)
    {
        await using var database = await TestDatabase.Create();
        var f = await Seed(database.Context, "MEMBER", "TEAM_LEAD", targetRole: "PROJECT_MANAGER");
        var inactiveManagerId = Guid.NewGuid();
        var inactiveManager = User(inactiveManagerId, "Other", $"{inactiveManagerId}@example.test");
        database.Context.Users.Add(inactiveManager);
        database.Context.OrganizationMembers.Add(new OrganizationMember
        {
            Id = Guid.NewGuid(), OrganizationId = await database.Context.Projects.Where(x => x.Id == f.ProjectId)
                .Select(x => x.OrganizationId).SingleAsync(), UserId = inactiveManagerId, Role = "MEMBER",
            Status = inactiveState == "inactive-organization-membership" ? "inactive" : "active"
        });
        database.Context.ProjectMembers.Add(new ProjectMember
        {
            Id = Guid.NewGuid(), ProjectId = f.ProjectId, UserId = inactiveManagerId, Role = "PROJECT_MANAGER"
        });
        if (inactiveState == "suspended-user")
            inactiveManager.Status = "suspended";
        await database.Context.SaveChangesAsync();

        var result = await Controller(database.Context, f.ActorId).RemoveMember(f.ProjectId, f.TargetId, CancellationToken.None);

        AssertError(result, "project_must_retain_manager");
        Assert.Equal("active", (await database.Context.ProjectMembers.SingleAsync(x => x.UserId == f.TargetId)).Status);
    }

    [Fact]
    public async Task RoleAndAuditRollbackTogether_WhenAuditInsertFails()
    {
        await using var connection = new SqliteConnection("Data Source=:memory:");
        await connection.OpenAsync();
        var options = new DbContextOptionsBuilder<PmsDbContext>().UseSqlite(connection).Options;
        await using (var setup = new PmsDbContext(options))
        {
            await setup.Database.EnsureCreatedAsync();
            var f = await Seed(setup, "ADMIN", "PROJECT_MANAGER");
            await setup.SaveChangesAsync();
            await using (var trigger = connection.CreateCommand())
            {
                trigger.CommandText = "CREATE TRIGGER fail_audit_insert BEFORE INSERT ON admin_audit_events BEGIN SELECT RAISE(ABORT, 'audit failure'); END;";
                await trigger.ExecuteNonQueryAsync();
            }

            await using var requestDb = new PmsDbContext(options);
            var result = await Assert.ThrowsAsync<DbUpdateException>(() => Controller(requestDb, f.ActorId)
                .UpdateMemberRole(f.ProjectId, f.TargetId, new UpdateProjectMemberRoleRequest("CONTRIBUTOR"), CancellationToken.None));
            Assert.Contains("audit failure", result.InnerException?.Message ?? result.Message);
        }
        await using var verify = new PmsDbContext(options);
        var membership = await verify.ProjectMembers.SingleAsync(x => x.Role == "VIEWER");
        Assert.Equal("VIEWER", membership.Role);
        Assert.Empty(await verify.AdminAuditEvents.ToListAsync());
    }

    private static ProjectsController Controller(PmsDbContext db, Guid actorId)
    {
        var controller = new ProjectsController(db, new RealtimePublisher(new TestHubContext()));
        var http = new DefaultHttpContext
        {
            User = new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier, actorId.ToString())], "test"))
        };
        http.TraceIdentifier = Guid.NewGuid().ToString();
        controller.ControllerContext = new ControllerContext { HttpContext = http };
        return controller;
    }

    private static void AssertError(IActionResult result, string expectedCode)
    {
        var response = Assert.IsType<ObjectResult>(result);
        Assert.Equal(expectedCode, response.Value?.GetType().GetProperty("code")?.GetValue(response.Value));
    }

    private static async Task<Fixture> Seed(PmsDbContext db, string actorOrganizationRole, string actorProjectRole,
        string targetOrganizationRole = "MEMBER", string targetRole = "VIEWER")
    {
        var organizationId = Guid.NewGuid(); var projectId = Guid.NewGuid();
        var actorId = Guid.NewGuid(); var targetId = Guid.NewGuid();
        db.Organizations.Add(new Organization { Id = organizationId, Name = "Organization", Slug = $"org-{organizationId:N}" });
        db.Projects.Add(new Project { Id = projectId, OrganizationId = organizationId, OwnerId = actorId, Name = "Project" });
        db.Users.AddRange(
            User(actorId, "Actor", $"{actorId}@example.test"),
            User(targetId, "Target", $"{targetId}@example.test"));
        db.OrganizationMembers.AddRange(
            new OrganizationMember { Id = Guid.NewGuid(), OrganizationId = organizationId, UserId = actorId, Role = actorOrganizationRole },
            new OrganizationMember { Id = Guid.NewGuid(), OrganizationId = organizationId, UserId = targetId, Role = targetOrganizationRole });
        db.ProjectMembers.AddRange(
            new ProjectMember { Id = Guid.NewGuid(), ProjectId = projectId, UserId = actorId, Role = actorProjectRole },
            new ProjectMember { Id = Guid.NewGuid(), ProjectId = projectId, UserId = targetId, Role = targetRole });
        await db.SaveChangesAsync();
        return new Fixture(actorId, targetId, projectId);
    }

    private static User User(Guid id, string firstName, string email) =>
        new() { Id = id, FirstName = firstName, LastName = "Person", Email = email, PasswordHash = "hash" };

    private sealed record Fixture(Guid ActorId, Guid TargetId, Guid ProjectId);

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
}
