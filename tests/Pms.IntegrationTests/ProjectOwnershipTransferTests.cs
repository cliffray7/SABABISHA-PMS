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

public sealed class ProjectOwnershipTransferTests
{
    [Theory]
    [InlineData("ADMIN")]
    [InlineData("OWNER")]
    public async Task OrganizationOwnerOrAdminCanTransferToActiveManager_AndAuditsAtomically(string actorRole)
    {
        await using var database = await TestDatabase.Create();
        var fixture = await Seed(database.Context, actorOrganizationRole: actorRole);
        var before = await database.Context.Projects.SingleAsync(x => x.Id == fixture.ProjectId);

        var result = await Controller(database.Context, fixture.ActorId).TransferOwner(fixture.ProjectId,
            new TransferProjectOwnerRequest(fixture.CurrentOwnerId, fixture.NewOwnerId), default);

        Assert.IsType<NoContentResult>(result);
        var after = await database.Context.Projects.SingleAsync(x => x.Id == fixture.ProjectId);
        Assert.Equal(fixture.NewOwnerId, after.OwnerId);
        Assert.Equal(before.Status, after.Status);
        Assert.Equal(before.ArchivedAt, after.ArchivedAt);
        Assert.Equal(before.DeletedAt, after.DeletedAt);
        var audit = await database.Context.AdminAuditEvents.SingleAsync();
        Assert.Equal(fixture.ActorId, audit.ActorId);
        Assert.Equal("project.owner_transferred", audit.Action);
        Assert.Equal(fixture.ProjectId, audit.TargetId);
        Assert.Contains($"old_owner_id={fixture.CurrentOwnerId}", audit.Reason);
        Assert.Contains($"new_owner_id={fixture.NewOwnerId}", audit.Reason);
        var activity = await database.Context.ActivityEvents.SingleAsync();
        Assert.Equal(fixture.ActorId, activity.ActorUserId);
        Assert.Equal(fixture.ProjectId, activity.ProjectId);
        Assert.Equal("project.owner_transferred", activity.Action);
    }

    [Fact]
    public async Task ActiveProjectManagerCanTransferOwnership()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await Seed(database.Context, actorOrganizationRole: "MEMBER", actorProjectRole: "PROJECT_MANAGER");

        var result = await Controller(database.Context, fixture.ActorId).TransferOwner(fixture.ProjectId,
            new TransferProjectOwnerRequest(fixture.CurrentOwnerId, fixture.NewOwnerId), default);

        Assert.IsType<NoContentResult>(result);
        Assert.Equal(fixture.NewOwnerId, (await database.Context.Projects.SingleAsync()).OwnerId);
    }

    [Fact]
    public async Task CurrentOwnerCanTransferOwnership()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await Seed(database.Context, actorIsCurrentOwner: true, actorOrganizationRole: "MEMBER");

        var result = await Controller(database.Context, fixture.ActorId).TransferOwner(fixture.ProjectId,
            new TransferProjectOwnerRequest(fixture.CurrentOwnerId, fixture.NewOwnerId), default);

        Assert.IsType<NoContentResult>(result);
        Assert.Equal(fixture.NewOwnerId, (await database.Context.Projects.SingleAsync()).OwnerId);
    }

    [Fact]
    public async Task TransferToCurrentOwnerIsNoOpWithoutAudit_WhenExpectedOwnerMatches()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await Seed(database.Context, actorIsCurrentOwner: true);

        var result = await Controller(database.Context, fixture.ActorId).TransferOwner(fixture.ProjectId,
            new TransferProjectOwnerRequest(fixture.CurrentOwnerId, fixture.CurrentOwnerId), default);

        Assert.IsType<NoContentResult>(result);
        Assert.Empty(await database.Context.AdminAuditEvents.ToListAsync());
        Assert.Empty(await database.Context.ActivityEvents.ToListAsync());
    }

    [Fact]
    public async Task StaleExpectedOwnerReturnsProjectOwnerChangedWithoutWrites()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await Seed(database.Context);

        var result = await Controller(database.Context, fixture.ActorId).TransferOwner(fixture.ProjectId,
            new TransferProjectOwnerRequest(Guid.NewGuid(), fixture.NewOwnerId), default);

        AssertCode(result, "PROJECT_OWNER_CHANGED");
        Assert.Equal(fixture.CurrentOwnerId, (await database.Context.Projects.SingleAsync()).OwnerId);
        Assert.Empty(await database.Context.AdminAuditEvents.ToListAsync());
        Assert.Empty(await database.Context.ActivityEvents.ToListAsync());
    }

    [Theory]
    [InlineData(true, false)]
    [InlineData(false, true)]
    public async Task EmptyOwnerIdentifiersAreRejected(bool emptyExpectedOwner, bool emptyNewOwner)
    {
        await using var database = await TestDatabase.Create();
        var fixture = await Seed(database.Context);

        var result = await Controller(database.Context, fixture.ActorId).TransferOwner(fixture.ProjectId,
            new TransferProjectOwnerRequest(emptyExpectedOwner ? Guid.Empty : fixture.CurrentOwnerId,
                emptyNewOwner ? Guid.Empty : fixture.NewOwnerId), default);

        AssertCode(result, "PROJECT_OWNER_INVALID_REQUEST");
        Assert.Equal(fixture.CurrentOwnerId, (await database.Context.Projects.SingleAsync()).OwnerId);
        Assert.Empty(await database.Context.AdminAuditEvents.ToListAsync());
    }

    [Theory]
    [InlineData("team-lead", "MEMBER", "TEAM_LEAD", "active", "active")]
    [InlineData("contributor", "MEMBER", "CONTRIBUTOR", "active", "active")]
    [InlineData("viewer", "MEMBER", "VIEWER", "active", "active")]
    [InlineData("guest", "GUEST", "PROJECT_MANAGER", "active", "active")]
    [InlineData("inactive", "ADMIN", null, "inactive", "active")]
    [InlineData("suspended", "ADMIN", null, "active", "suspended")]
    public async Task IneligibleActorCannotTransfer(string _, string orgRole, string? projectRole,
        string membershipStatus, string accountStatus)
    {
        await using var database = await TestDatabase.Create();
        var fixture = await Seed(database.Context, actorOrganizationRole: orgRole, actorProjectRole: projectRole,
            actorIsCurrentOwner: false, actorOrganizationStatus: membershipStatus, actorStatus: accountStatus);

        var result = await Controller(database.Context, fixture.ActorId).TransferOwner(fixture.ProjectId,
            new TransferProjectOwnerRequest(fixture.CurrentOwnerId, fixture.NewOwnerId), default);

        AssertCode(result, "PROJECT_OWNER_TRANSFER_FORBIDDEN");
        Assert.Equal(fixture.CurrentOwnerId, (await database.Context.Projects.SingleAsync()).OwnerId);
        Assert.Empty(await database.Context.AdminAuditEvents.ToListAsync());
    }

    [Theory]
    [InlineData("team-lead")]
    [InlineData("guest")]
    [InlineData("inactive-membership")]
    [InlineData("inactive-organization-membership")]
    [InlineData("suspended-account")]
    [InlineData("inactive-account")]
    [InlineData("missing-project-membership")]
    [InlineData("cross-organization")]
    public async Task IneligibleRecipientIsRejected(string ineligibility)
    {
        await using var database = await TestDatabase.Create();
        var fixture = await Seed(database.Context);
        await MakeRecipientIneligible(database.Context, fixture, ineligibility);

        var result = await Controller(database.Context, fixture.ActorId).TransferOwner(fixture.ProjectId,
            new TransferProjectOwnerRequest(fixture.CurrentOwnerId, fixture.NewOwnerId), default);

        AssertCode(result, "PROJECT_OWNER_RECIPIENT_NOT_ELIGIBLE");
        Assert.Equal(fixture.CurrentOwnerId, (await database.Context.Projects.SingleAsync()).OwnerId);
        Assert.Empty(await database.Context.AdminAuditEvents.ToListAsync());
    }

    [Fact]
    public async Task CrossTenantActorCannotTransferAnotherOrganizationsProject()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await Seed(database.Context);
        var foreignActorId = Guid.NewGuid();
        var foreignOrganizationId = Guid.NewGuid();
        database.Context.Users.Add(User(foreignActorId, "Foreign actor"));
        database.Context.Organizations.Add(new Organization
        {
            Id = foreignOrganizationId, Name = "Foreign organization", Slug = $"foreign-{foreignOrganizationId:N}"
        });
        database.Context.OrganizationMembers.Add(new OrganizationMember
        {
            Id = Guid.NewGuid(), OrganizationId = foreignOrganizationId, UserId = foreignActorId, Role = "ADMIN"
        });
        await database.Context.SaveChangesAsync();

        var result = await Controller(database.Context, foreignActorId).TransferOwner(fixture.ProjectId,
            new TransferProjectOwnerRequest(fixture.CurrentOwnerId, fixture.NewOwnerId), default);

        AssertCode(result, "PROJECT_OWNER_TRANSFER_FORBIDDEN");
        Assert.Equal(fixture.CurrentOwnerId, (await database.Context.Projects.SingleAsync()).OwnerId);
    }

    [Theory]
    [InlineData("archived")]
    [InlineData("trashed")]
    public async Task ArchivedAndRetainedTrashedProjectsAllowOwnershipMaintenanceWithoutReactivation(string state)
    {
        await using var database = await TestDatabase.Create();
        var now = DateTime.UtcNow;
        var fixture = await Seed(database.Context,
            archivedAt: state == "archived" ? now : null,
            deletedAt: state == "trashed" ? now : null,
            projectStatus: "ON_HOLD");

        var result = await Controller(database.Context, fixture.ActorId).TransferOwner(fixture.ProjectId,
            new TransferProjectOwnerRequest(fixture.CurrentOwnerId, fixture.NewOwnerId), default);

        Assert.IsType<NoContentResult>(result);
        var project = await database.Context.Projects.SingleAsync();
        Assert.Equal(fixture.NewOwnerId, project.OwnerId);
        Assert.Equal("ON_HOLD", project.Status);
        Assert.Equal(state == "archived" ? now : null, project.ArchivedAt);
        Assert.Equal(state == "trashed" ? now : null, project.DeletedAt);
    }

    [Fact]
    public async Task TrashedProjectOutsideRetentionIsNotTransferable()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await Seed(database.Context, deletedAt: DateTime.UtcNow.AddDays(-31));

        var result = await Controller(database.Context, fixture.ActorId).TransferOwner(fixture.ProjectId,
            new TransferProjectOwnerRequest(fixture.CurrentOwnerId, fixture.NewOwnerId), default);

        Assert.IsType<NotFoundResult>(result);
        Assert.Equal(fixture.CurrentOwnerId, (await database.Context.Projects.SingleAsync()).OwnerId);
    }

    [Fact]
    public async Task OwnerAndAuditActivityRollbackTogether_WhenAuditInsertFails()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await Seed(database.Context);
        await using (var trigger = database.Connection.CreateCommand())
        {
            trigger.CommandText = "CREATE TRIGGER fail_owner_audit BEFORE INSERT ON admin_audit_events BEGIN SELECT RAISE(ABORT, 'audit failure'); END;";
            await trigger.ExecuteNonQueryAsync();
        }

        await Assert.ThrowsAsync<DbUpdateException>(() => Controller(database.Context, fixture.ActorId)
            .TransferOwner(fixture.ProjectId,
                new TransferProjectOwnerRequest(fixture.CurrentOwnerId, fixture.NewOwnerId), default));

        await using var verify = new PmsDbContext(new DbContextOptionsBuilder<PmsDbContext>()
            .UseSqlite(database.Connection).Options);
        Assert.Equal(fixture.CurrentOwnerId, (await verify.Projects.SingleAsync()).OwnerId);
        Assert.Empty(await verify.AdminAuditEvents.ToListAsync());
        Assert.Empty(await verify.ActivityEvents.ToListAsync());
    }

    private static async Task MakeRecipientIneligible(PmsDbContext db, Fixture fixture, string ineligibility)
    {
        var projectMember = await db.ProjectMembers.SingleAsync(x => x.ProjectId == fixture.ProjectId && x.UserId == fixture.NewOwnerId);
        var organizationMember = await db.OrganizationMembers.SingleAsync(x => x.UserId == fixture.NewOwnerId);
        var user = await db.Users.SingleAsync(x => x.Id == fixture.NewOwnerId);
        switch (ineligibility)
        {
            case "team-lead": projectMember.Role = "TEAM_LEAD"; break;
            case "guest": organizationMember.Role = "GUEST"; break;
            case "inactive-membership": projectMember.Status = "inactive"; break;
            case "inactive-organization-membership": organizationMember.Status = "inactive"; break;
            case "suspended-account": user.Status = "suspended"; break;
            case "inactive-account": user.Status = "inactive"; break;
            case "missing-project-membership": db.ProjectMembers.Remove(projectMember); break;
            case "cross-organization":
                var otherOrganizationId = Guid.NewGuid();
                db.Organizations.Add(new Organization
                {
                    Id = otherOrganizationId, Name = "Other organization", Slug = $"other-{otherOrganizationId:N}"
                });
                organizationMember.OrganizationId = otherOrganizationId;
                break;
        }
        await db.SaveChangesAsync();
    }

    private static async Task<Fixture> Seed(PmsDbContext db, string actorOrganizationRole = "ADMIN",
        string? actorProjectRole = null, bool actorIsCurrentOwner = false,
        string actorOrganizationStatus = "active", string actorStatus = "active",
        string targetOrganizationRole = "MEMBER", string targetProjectRole = "PROJECT_MANAGER",
        string targetOrganizationStatus = "active", string targetStatus = "active",
        string? targetProjectStatus = "active", DateTime? archivedAt = null,
        DateTime? deletedAt = null, string projectStatus = "ACTIVE")
    {
        var organizationId = Guid.NewGuid(); var projectId = Guid.NewGuid();
        var actorId = Guid.NewGuid(); var currentOwnerId = actorIsCurrentOwner ? actorId : Guid.NewGuid();
        var newOwnerId = Guid.NewGuid();
        db.Organizations.Add(new Organization
        {
            Id = organizationId, Name = "Transfer organization", Slug = $"transfer-{organizationId:N}"
        });
        db.Projects.Add(new Project
        {
            Id = projectId, OrganizationId = organizationId, OwnerId = currentOwnerId,
            Name = "Transfer project", Status = projectStatus, ArchivedAt = archivedAt, DeletedAt = deletedAt
        });
        var actor = User(actorId, "Actor");
        actor.Status = actorStatus;
        var newOwner = User(newOwnerId, "New owner");
        newOwner.Status = targetStatus;
        db.Users.AddRange(actor, newOwner);
        if (!actorIsCurrentOwner) db.Users.Add(User(currentOwnerId, "Current owner"));
        db.OrganizationMembers.AddRange(
            new OrganizationMember
            {
                Id = Guid.NewGuid(), OrganizationId = organizationId, UserId = actorId,
                Role = actorOrganizationRole, Status = actorOrganizationStatus
            },
            new OrganizationMember
            {
                Id = Guid.NewGuid(), OrganizationId = organizationId, UserId = newOwnerId,
                Role = targetOrganizationRole, Status = targetOrganizationStatus
            });
        if (!actorIsCurrentOwner)
            db.OrganizationMembers.Add(new OrganizationMember
            {
                Id = Guid.NewGuid(), OrganizationId = organizationId, UserId = currentOwnerId, Role = "MEMBER"
            });
        if (actorProjectRole is not null || actorIsCurrentOwner)
            db.ProjectMembers.Add(new ProjectMember
            {
                Id = Guid.NewGuid(), ProjectId = projectId, UserId = actorId,
                Role = actorProjectRole ?? "PROJECT_MANAGER"
            });
        if (!actorIsCurrentOwner)
            db.ProjectMembers.Add(new ProjectMember
            {
                Id = Guid.NewGuid(), ProjectId = projectId, UserId = currentOwnerId, Role = "PROJECT_MANAGER"
            });
        db.ProjectMembers.Add(new ProjectMember
        {
            Id = Guid.NewGuid(), ProjectId = projectId, UserId = newOwnerId,
            Role = targetProjectRole, Status = targetProjectStatus ?? "active"
        });
        await db.SaveChangesAsync();
        return new Fixture(organizationId, projectId, actorId, currentOwnerId, newOwnerId);
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

    private static void AssertCode(IActionResult result, string expectedCode)
    {
        var response = Assert.IsAssignableFrom<ObjectResult>(result);
        Assert.Equal(expectedCode, response.Value?.GetType().GetProperty("code")?.GetValue(response.Value));
    }

    private static User User(Guid id, string name) => new()
    {
        Id = id, FirstName = name, LastName = "Person", Email = $"{id}@example.test", PasswordHash = "hash"
    };

    private sealed record Fixture(Guid OrganizationId, Guid ProjectId, Guid ActorId, Guid CurrentOwnerId, Guid NewOwnerId);

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
