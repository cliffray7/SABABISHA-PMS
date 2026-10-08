using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Pms.Api.Controllers.Rest.V1;
using Pms.Api.MemberRemoval;
using Pms.Api.Realtime;
using Pms.Domain.Entities;
using Pms.Infrastructure.Persistence.EfCore;

namespace Pms.IntegrationTests;

public sealed class OrganizationMemberDeactivationResolutionTests
{
    [Fact]
    public async Task DeactivationResolvesTasksAcrossProjectsAtomically()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await SeedAsync(database.Db, 2, includeTasks: true);
        var controller = Controller(database.Db, fixture.ActorId);
        var preview = Assert.IsType<MemberRemovalPreview>(Assert.IsType<OkObjectResult>(
            await controller.PreviewMemberDeactivation(fixture.OrganizationId, fixture.TargetId, CancellationToken.None)).Value);
        var resolutions = fixture.TaskIds.Select(taskId => new MemberTaskResolution(taskId, "UNASSIGN", null)).ToArray();

        var result = await controller.ConfirmMemberDeactivation(fixture.OrganizationId, fixture.TargetId,
            new MemberRemovalRequest(preview.SnapshotHash, resolutions), CancellationToken.None);

        Assert.IsType<NoContentResult>(result);
        Assert.Equal("inactive", (await database.Db.OrganizationMembers.SingleAsync(item => item.UserId == fixture.TargetId)).Status);
        Assert.All(await database.Db.ProjectMembers.Where(item => item.UserId == fixture.TargetId).ToListAsync(),
            membership => Assert.Equal("inactive", membership.Status));
        Assert.All(await database.Db.TaskAssignees.Where(item => item.UserId == fixture.TargetId).ToListAsync(),
            assignment => Assert.Equal("inactive", assignment.Status));
        Assert.Equal(2, await database.Db.TaskAssignmentEvents.CountAsync());
        Assert.Single(await database.Db.AdminAuditEvents.ToListAsync());
    }

    [Fact]
    public async Task DeactivationIsBlockedWhenTargetOwnsAnyRetainedProject()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await SeedAsync(database.Db, 2, includeTasks: false, secondProjectOwnerIsTarget: true);
        var controller = Controller(database.Db, fixture.ActorId);
        var preview = Assert.IsType<MemberRemovalPreview>(Assert.IsType<OkObjectResult>(
            await controller.PreviewMemberDeactivation(fixture.OrganizationId, fixture.TargetId, CancellationToken.None)).Value);

        var result = await controller.ConfirmMemberDeactivation(fixture.OrganizationId, fixture.TargetId,
            new MemberRemovalRequest(preview.SnapshotHash, []), CancellationToken.None);

        AssertCode(result, "PROJECT_OWNER_TRANSFER_REQUIRED");
        Assert.Equal("active", (await database.Db.OrganizationMembers.SingleAsync(item => item.UserId == fixture.TargetId)).Status);
        Assert.Empty(await database.Db.AdminAuditEvents.ToListAsync());
        Assert.Empty(await database.Db.TaskAssignmentEvents.ToListAsync());
    }

    [Fact]
    public async Task ExpiredTrashOwnerAndManagerDoNotBlockOrganizationDeactivation()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await SeedAsync(database.Db, 1, includeTasks: true, secondProjectOwnerIsTarget: false);
        await database.Db.Projects.Where(project => project.Id == fixture.ProjectIds[0])
            .ExecuteUpdateAsync(update => update.SetProperty(project => project.OwnerId, fixture.TargetId)
                .SetProperty(project => project.DeletedAt, DateTime.UtcNow.AddDays(-31)));
        await database.Db.ProjectMembers.Where(member => member.ProjectId == fixture.ProjectIds[0]
                && member.UserId == fixture.TargetId)
            .ExecuteUpdateAsync(update => update.SetProperty(member => member.Role, "PROJECT_MANAGER"));
        var controller = Controller(database.Db, fixture.ActorId);
        var preview = Assert.IsType<MemberRemovalPreview>(Assert.IsType<OkObjectResult>(
            await controller.PreviewMemberDeactivation(fixture.OrganizationId, fixture.TargetId, CancellationToken.None)).Value);
        Assert.Single(preview.ExpiredTrashCleanup);

        var result = await controller.ConfirmMemberDeactivation(fixture.OrganizationId, fixture.TargetId,
            new MemberRemovalRequest(preview.SnapshotHash, []), CancellationToken.None);

        Assert.IsType<NoContentResult>(result);
        Assert.Equal("inactive", (await database.Db.OrganizationMembers.SingleAsync(item => item.UserId == fixture.TargetId)).Status);
        Assert.Equal("inactive", (await database.Db.TaskAssignees.SingleAsync(item => item.UserId == fixture.TargetId)).Status);
        var history = await database.Db.TaskAssignmentEvents.SingleAsync();
        Assert.Equal("LIFECYCLE_INACTIVATED", history.Action);
        Assert.Equal("PROJECT_TRASH_EXPIRED", history.ReasonCode);
    }

    private static async Task<Fixture> SeedAsync(PmsDbContext db, int projectCount, bool includeTasks,
        bool secondProjectOwnerIsTarget = false)
    {
        var organizationId = Guid.NewGuid(); var actorId = Guid.NewGuid(); var targetId = Guid.NewGuid();
        var projectIds = Enumerable.Range(0, projectCount).Select(_ => Guid.NewGuid()).ToArray();
        var taskIds = includeTasks ? projectIds.Select(_ => Guid.NewGuid()).ToArray() : [];
        db.Organizations.Add(new Organization { Id = organizationId, Name = "Org", Slug = $"org-{organizationId:N}" });
        db.Users.AddRange(User(actorId), User(targetId));
        db.OrganizationMembers.AddRange(
            new OrganizationMember { Id = Guid.NewGuid(), OrganizationId = organizationId, UserId = actorId, Role = "ADMIN" },
            new OrganizationMember { Id = Guid.NewGuid(), OrganizationId = organizationId, UserId = targetId, Role = "MEMBER" });
        for (var i = 0; i < projectIds.Length; i++)
        {
            var projectId = projectIds[i];
            db.Projects.Add(new Project
            {
                Id = projectId, OrganizationId = organizationId,
                OwnerId = secondProjectOwnerIsTarget && i == 1 ? targetId : actorId, Name = $"Project {i}"
            });
            db.ProjectMembers.AddRange(
                new ProjectMember { Id = Guid.NewGuid(), ProjectId = projectId, UserId = actorId, Role = "PROJECT_MANAGER" },
                new ProjectMember { Id = Guid.NewGuid(), ProjectId = projectId, UserId = targetId,
                    Role = secondProjectOwnerIsTarget && i == 1 ? "PROJECT_MANAGER" : "CONTRIBUTOR" });
            if (includeTasks)
            {
                db.Tasks.Add(new WorkTask { Id = taskIds[i], ProjectId = projectId, Title = $"Task {i}", Status = "TODO", CreatedBy = actorId });
                db.TaskAssignees.Add(new TaskAssignee { Id = Guid.NewGuid(), TaskId = taskIds[i], UserId = targetId });
            }
        }
        await db.SaveChangesAsync();
        return new Fixture(organizationId, actorId, targetId, projectIds, taskIds);
    }

    private static OrganizationsController Controller(PmsDbContext db, Guid actorId)
    {
        var controller = new OrganizationsController(db, null!, null!, new RealtimePublisher(new TestHubContext()));
        var context = new DefaultHttpContext
        {
            User = new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier, actorId.ToString())], "test"))
        };
        context.TraceIdentifier = Guid.NewGuid().ToString();
        controller.ControllerContext = new ControllerContext { HttpContext = context };
        return controller;
    }

    private static User User(Guid id) => new()
    {
        Id = id, FirstName = "Member", LastName = "Test", Email = $"{id:N}@example.test", PasswordHash = "hash"
    };

    private static void AssertCode(IActionResult result, string expected)
    {
        var response = Assert.IsType<ObjectResult>(result);
        Assert.Equal(expected, response.Value?.GetType().GetProperty("code")?.GetValue(response.Value));
    }

    private sealed record Fixture(Guid OrganizationId, Guid ActorId, Guid TargetId, Guid[] ProjectIds, Guid[] TaskIds);
    private sealed class TestHubContext : IHubContext<WorkspaceHub>
    {
        public IHubClients Clients { get; } = new TestHubClients();
        public IGroupManager Groups { get; } = new TestGroupManager();
    }
    private sealed class TestHubClients : IHubClients
    {
        private static readonly IClientProxy Proxy = new TestClientProxy();
        public IClientProxy All => Proxy;
        public IClientProxy AllExcept(IReadOnlyList<string> ids) => Proxy;
        public IClientProxy Client(string id) => Proxy;
        public IClientProxy Clients(IReadOnlyList<string> ids) => Proxy;
        public IClientProxy Group(string name) => Proxy;
        public IClientProxy GroupExcept(string name, IReadOnlyList<string> ids) => Proxy;
        public IClientProxy Groups(IReadOnlyList<string> names) => Proxy;
        public IClientProxy User(string id) => Proxy;
        public IClientProxy Users(IReadOnlyList<string> ids) => Proxy;
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
        private TestDatabase(SqliteConnection connection, PmsDbContext db) { Connection = connection; Db = db; }
        public SqliteConnection Connection { get; }
        public PmsDbContext Db { get; }
        public static async Task<TestDatabase> Create()
        {
            var connection = new SqliteConnection("Data Source=:memory:");
            await connection.OpenAsync();
            var db = new PmsDbContext(new DbContextOptionsBuilder<PmsDbContext>().UseSqlite(connection).Options);
            await db.Database.EnsureCreatedAsync();
            return new TestDatabase(connection, db);
        }
        public async ValueTask DisposeAsync() { await Db.DisposeAsync(); await Connection.DisposeAsync(); }
    }
}
