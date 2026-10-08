using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.EntityFrameworkCore.Storage;
using Pms.Api.Auth;
using Pms.Api.Controllers.Rest.V1;
using Pms.Api.MemberRemoval;
using Pms.Api.Realtime;
using Pms.Domain.Entities;
using Pms.Infrastructure.Persistence.EfCore;

namespace Pms.IntegrationTests;

public sealed class ProjectMemberRemovalResolutionTests
{
    [Fact]
    public async Task Confirm_ReassignsOnlyDepartingMemberAndWritesHistoryAndAudit()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await SeedAsync(database.Db);
        var controller = Controller(database.Db, fixture.ActorId);
        var previewResult = Assert.IsType<OkObjectResult>(await controller.PreviewMemberRemoval(
            fixture.ProjectId, fixture.TargetId, CancellationToken.None));
        var preview = Assert.IsType<MemberRemovalPreview>(previewResult.Value);

        var result = await controller.ConfirmMemberRemoval(fixture.ProjectId, fixture.TargetId,
            new MemberRemovalRequest(preview.SnapshotHash,
                [new MemberTaskResolution(fixture.TaskId, "REASSIGN", fixture.ReplacementId)]), CancellationToken.None);

        Assert.IsType<NoContentResult>(result);
        Assert.Equal("inactive", (await database.Db.ProjectMembers.SingleAsync(item => item.UserId == fixture.TargetId)).Status);
        Assert.Equal("inactive", (await database.Db.TaskAssignees.SingleAsync(item => item.UserId == fixture.TargetId)).Status);
        Assert.Equal("active", (await database.Db.TaskAssignees.SingleAsync(item => item.UserId == fixture.ReplacementId)).Status);
        var history = await database.Db.TaskAssignmentEvents.SingleAsync();
        Assert.Equal("REASSIGNED", history.Action);
        Assert.Equal(fixture.ActorId, history.ActorUserId);
        Assert.Equal(fixture.ReplacementId, history.ReplacementUserId);
        Assert.Single(await database.Db.AdminAuditEvents.ToListAsync());
    }

    [Fact]
    public async Task Confirm_StaleSnapshotWritesNothing()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await SeedAsync(database.Db);
        var controller = Controller(database.Db, fixture.ActorId);
        var preview = Assert.IsType<MemberRemovalPreview>(Assert.IsType<OkObjectResult>(
            await controller.PreviewMemberRemoval(fixture.ProjectId, fixture.TargetId, CancellationToken.None)).Value);
        await database.Db.Tasks.Where(task => task.Id == fixture.TaskId)
            .ExecuteUpdateAsync(update => update.SetProperty(task => task.Status, "DONE"));

        var result = await controller.ConfirmMemberRemoval(fixture.ProjectId, fixture.TargetId,
            new MemberRemovalRequest(preview.SnapshotHash,
                [new MemberTaskResolution(fixture.TaskId, "UNASSIGN", null)]), CancellationToken.None);

        AssertCode(result, "MEMBER_REMOVAL_PREVIEW_STALE");
        Assert.Equal("active", (await database.Db.ProjectMembers.SingleAsync(item => item.UserId == fixture.TargetId)).Status);
        Assert.Equal("active", (await database.Db.TaskAssignees.SingleAsync(item => item.UserId == fixture.TargetId)).Status);
        Assert.Empty(await database.Db.TaskAssignmentEvents.ToListAsync());
        Assert.Empty(await database.Db.AdminAuditEvents.ToListAsync());
    }

    [Fact]
    public async Task Confirm_AuditFailureRollsBackMembershipAssignmentAndHistory()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await SeedAsync(database.Db);
        await using (var trigger = database.Connection.CreateCommand())
        {
            trigger.CommandText = "CREATE TRIGGER fail_removal_audit BEFORE INSERT ON admin_audit_events BEGIN SELECT RAISE(ABORT, 'audit failure'); END;";
            await trigger.ExecuteNonQueryAsync();
        }
        var controller = Controller(database.Db, fixture.ActorId);
        var preview = Assert.IsType<MemberRemovalPreview>(Assert.IsType<OkObjectResult>(
            await controller.PreviewMemberRemoval(fixture.ProjectId, fixture.TargetId, CancellationToken.None)).Value);

        await Assert.ThrowsAsync<DbUpdateException>(() => controller.ConfirmMemberRemoval(fixture.ProjectId,
            fixture.TargetId, new MemberRemovalRequest(preview.SnapshotHash,
                [new MemberTaskResolution(fixture.TaskId, "UNASSIGN", null)]), CancellationToken.None));

        database.Db.ChangeTracker.Clear();
        Assert.Equal("active", (await database.Db.ProjectMembers.SingleAsync(item => item.UserId == fixture.TargetId)).Status);
        Assert.Equal("active", (await database.Db.TaskAssignees.SingleAsync(item => item.UserId == fixture.TargetId)).Status);
        Assert.Empty(await database.Db.TaskAssignmentEvents.ToListAsync());
    }

    [Fact]
    public async Task Confirm_InactivatesCompletedAttributionWithoutResolution()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await SeedAsync(database.Db);
        await database.Db.Tasks.Where(task => task.Id == fixture.TaskId)
            .ExecuteUpdateAsync(update => update.SetProperty(task => task.Status, "DONE"));
        var controller = Controller(database.Db, fixture.ActorId);
        var preview = Assert.IsType<MemberRemovalPreview>(Assert.IsType<OkObjectResult>(
            await controller.PreviewMemberRemoval(fixture.ProjectId, fixture.TargetId, CancellationToken.None)).Value);
        var projectPreview = Assert.Single(preview.AffectedProjects);
        Assert.Empty(projectPreview.Tasks);
        Assert.Single(projectPreview.HistoricalAttributionsToInactivate);

        var result = await controller.ConfirmMemberRemoval(fixture.ProjectId, fixture.TargetId,
            new MemberRemovalRequest(preview.SnapshotHash, []), CancellationToken.None);

        Assert.IsType<NoContentResult>(result);
        Assert.Equal("inactive", (await database.Db.TaskAssignees.SingleAsync(item => item.UserId == fixture.TargetId)).Status);
        var history = await database.Db.TaskAssignmentEvents.SingleAsync();
        Assert.Equal("UNASSIGNED", history.Action);
        Assert.Null(history.ReplacementUserId);
        Assert.Equal(fixture.TargetId, history.DepartingUserId);

        // Restoring membership must not reactivate the historical assignment.
        await database.Db.ProjectMembers.Where(item => item.ProjectId == fixture.ProjectId && item.UserId == fixture.TargetId)
            .ExecuteUpdateAsync(update => update.SetProperty(item => item.Status, "active"));
        Assert.Equal("inactive", (await database.Db.TaskAssignees.SingleAsync(item => item.UserId == fixture.TargetId)).Status);
        Assert.Equal(fixture.TargetId, (await database.Db.TaskAssignmentEvents.SingleAsync()).DepartingUserId);
    }

    [Fact]
    public async Task Confirm_RetryExhaustionReturnsConflictAndRollsBackAllWritesAndEvents()
    {
        await using var database = await RetryTestDatabase.Create();
        var fixture = await SeedAsync(database.Db);
        var mail = TestMail();
        var controller = Controller(database.Db, fixture.ActorId, database.Hub, mail);
        var preview = Assert.IsType<MemberRemovalPreview>(Assert.IsType<OkObjectResult>(
            await controller.PreviewMemberRemoval(fixture.ProjectId, fixture.TargetId, CancellationToken.None)).Value);
        database.TransientFailure.Enabled = true;

        var result = await controller.ConfirmMemberRemoval(fixture.ProjectId, fixture.TargetId,
            new MemberRemovalRequest(preview.SnapshotHash,
                [new MemberTaskResolution(fixture.TaskId, "UNASSIGN", null)]), CancellationToken.None);

        AssertCode(result, "MEMBER_REMOVAL_CONFLICT");
        var conflict = Assert.IsType<ObjectResult>(result);
        Assert.Equal(StatusCodes.Status409Conflict, conflict.StatusCode);
        Assert.Equal(7, database.TransientFailure.SaveAttempts);
        database.Db.ChangeTracker.Clear();
        Assert.Equal("active", (await database.Db.ProjectMembers.SingleAsync(item => item.UserId == fixture.TargetId)).Status);
        Assert.Equal("active", (await database.Db.TaskAssignees.SingleAsync(item => item.UserId == fixture.TargetId)).Status);
        Assert.Empty(await database.Db.TaskAssignmentEvents.ToListAsync());
        Assert.Empty(await database.Db.AdminAuditEvents.ToListAsync());
        Assert.Empty(await database.Db.ActivityEvents.ToListAsync());
        Assert.Equal(0, database.Hub.SendCount);
        await Task.Delay(50);
        Assert.Empty(mail.Messages);
    }

    [Fact]
    public async Task Confirm_RetryRevalidatesOriginalSnapshotAndRejectsChangedState()
    {
        await using var database = await RetryTestDatabase.Create();
        var fixture = await SeedAsync(database.Db);
        var mail = TestMail();
        var controller = Controller(database.Db, fixture.ActorId, database.Hub, mail);
        var preview = Assert.IsType<MemberRemovalPreview>(Assert.IsType<OkObjectResult>(
            await controller.PreviewMemberRemoval(fixture.ProjectId, fixture.TargetId, CancellationToken.None)).Value);
        database.TransientFailure.Enabled = true;
        database.TransientFailure.AfterFirstFailure = () =>
        {
            database.Db.Database.ExecuteSqlRaw("UPDATE tasks SET status = 'DONE' WHERE id = {0}", fixture.TaskId);
        };

        var result = await controller.ConfirmMemberRemoval(fixture.ProjectId, fixture.TargetId,
            new MemberRemovalRequest(preview.SnapshotHash,
                [new MemberTaskResolution(fixture.TaskId, "UNASSIGN", null)]), CancellationToken.None);

        AssertCode(result, "MEMBER_REMOVAL_PREVIEW_STALE");
        Assert.Equal(1, database.TransientFailure.SaveAttempts);
        database.Db.ChangeTracker.Clear();
        Assert.Equal("DONE", (await database.Db.Tasks.SingleAsync(item => item.Id == fixture.TaskId)).Status);
        Assert.Equal("active", (await database.Db.ProjectMembers.SingleAsync(item => item.UserId == fixture.TargetId)).Status);
        Assert.Equal("active", (await database.Db.TaskAssignees.SingleAsync(item => item.UserId == fixture.TargetId)).Status);
        Assert.Empty(await database.Db.TaskAssignmentEvents.ToListAsync());
        Assert.Empty(await database.Db.AdminAuditEvents.ToListAsync());
        Assert.Empty(await database.Db.ActivityEvents.ToListAsync());
        Assert.Equal(0, database.Hub.SendCount);
        await Task.Delay(50);
        Assert.Empty(mail.Messages);
    }

    [Fact]
    public async Task Confirm_RejectsDepartingMemberAsTheirOwnReplacement()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await SeedAsync(database.Db);
        var controller = Controller(database.Db, fixture.ActorId);
        var preview = Assert.IsType<MemberRemovalPreview>(Assert.IsType<OkObjectResult>(
            await controller.PreviewMemberRemoval(fixture.ProjectId, fixture.TargetId, CancellationToken.None)).Value);

        var result = await controller.ConfirmMemberRemoval(fixture.ProjectId, fixture.TargetId,
            new MemberRemovalRequest(preview.SnapshotHash,
                [new MemberTaskResolution(fixture.TaskId, "REASSIGN", fixture.TargetId)]), CancellationToken.None);

        AssertCode(result, "MEMBER_REMOVAL_REPLACEMENT_INELIGIBLE");
        Assert.Equal("active", (await database.Db.ProjectMembers.SingleAsync(item => item.UserId == fixture.TargetId)).Status);
        Assert.Equal("active", (await database.Db.TaskAssignees.SingleAsync(item => item.UserId == fixture.TargetId)).Status);
        Assert.Empty(await database.Db.TaskAssignmentEvents.ToListAsync());
    }

    [Fact]
    public async Task Confirm_AllowsExactly100AffectedTasks()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await SeedAsync(database.Db);
        await AddAssignmentsAsync(database.Db, fixture, 99);
        var controller = Controller(database.Db, fixture.ActorId);
        var preview = Assert.IsType<MemberRemovalPreview>(Assert.IsType<OkObjectResult>(
            await controller.PreviewMemberRemoval(fixture.ProjectId, fixture.TargetId, CancellationToken.None)).Value);
        Assert.Equal(100, preview.AffectedTaskCount);
        var taskIds = preview.AffectedProjects.SelectMany(project => project.Tasks).Select(task => task.TaskId).ToArray();
        var resolutions = taskIds.Select(taskId => new MemberTaskResolution(taskId, "UNASSIGN", null)).ToArray();

        var result = await controller.ConfirmMemberRemoval(fixture.ProjectId, fixture.TargetId,
            new MemberRemovalRequest(preview.SnapshotHash, resolutions), CancellationToken.None);

        Assert.IsType<NoContentResult>(result);
        Assert.Equal(100, await database.Db.TaskAssignmentEvents.CountAsync());
    }

    [Fact]
    public async Task Preview_RejectsMoreThan100AffectedTasks()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await SeedAsync(database.Db);
        await AddAssignmentsAsync(database.Db, fixture, 100);

        var result = await Controller(database.Db, fixture.ActorId)
            .PreviewMemberRemoval(fixture.ProjectId, fixture.TargetId, CancellationToken.None);

        AssertCode(result, "MEMBER_RESOLUTION_LIMIT_EXCEEDED");
        Assert.Equal(StatusCodes.Status422UnprocessableEntity, Assert.IsType<ObjectResult>(result).StatusCode);
        Assert.Equal("active", (await database.Db.ProjectMembers.SingleAsync(item => item.UserId == fixture.TargetId)).Status);
    }

    private static async Task<Fixture> SeedAsync(PmsDbContext db)
    {
        var orgId = Guid.NewGuid(); var projectId = Guid.NewGuid(); var actorId = Guid.NewGuid();
        var targetId = Guid.NewGuid(); var replacementId = Guid.NewGuid(); var taskId = Guid.NewGuid();
        db.Organizations.Add(new Organization { Id = orgId, Name = "Org", Slug = $"org-{orgId:N}" });
        db.Projects.Add(new Project { Id = projectId, OrganizationId = orgId, OwnerId = actorId, Name = "Project" });
        db.Users.AddRange(User(actorId), User(targetId), User(replacementId));
        db.OrganizationMembers.AddRange(
            new OrganizationMember { Id = Guid.NewGuid(), OrganizationId = orgId, UserId = actorId, Role = "ADMIN" },
            new OrganizationMember { Id = Guid.NewGuid(), OrganizationId = orgId, UserId = targetId, Role = "MEMBER" },
            new OrganizationMember { Id = Guid.NewGuid(), OrganizationId = orgId, UserId = replacementId, Role = "MEMBER" });
        db.ProjectMembers.AddRange(
            new ProjectMember { Id = Guid.NewGuid(), ProjectId = projectId, UserId = actorId, Role = "PROJECT_MANAGER" },
            new ProjectMember { Id = Guid.NewGuid(), ProjectId = projectId, UserId = targetId, Role = "CONTRIBUTOR" },
            new ProjectMember { Id = Guid.NewGuid(), ProjectId = projectId, UserId = replacementId, Role = "CONTRIBUTOR" });
        db.Tasks.Add(new WorkTask { Id = taskId, ProjectId = projectId, Title = "Task", Status = "TODO", CreatedBy = actorId });
        db.TaskAssignees.Add(new TaskAssignee { Id = Guid.NewGuid(), TaskId = taskId, UserId = targetId });
        await db.SaveChangesAsync();
        return new Fixture(orgId, projectId, actorId, targetId, replacementId, taskId);
    }

    private static async Task AddAssignmentsAsync(PmsDbContext db, Fixture fixture, int additionalCount)
    {
        var additions = Enumerable.Range(0, additionalCount).Select(index =>
        {
            var taskId = Guid.NewGuid();
            return (Task: new WorkTask
            {
                Id = taskId, ProjectId = fixture.ProjectId, Title = $"Additional {index}",
                Status = "TO DO", CreatedBy = fixture.ActorId
            }, Assignment: new TaskAssignee { Id = Guid.NewGuid(), TaskId = taskId, UserId = fixture.TargetId });
        }).ToArray();
        db.Tasks.AddRange(additions.Select(item => item.Task));
        db.TaskAssignees.AddRange(additions.Select(item => item.Assignment));
        await db.SaveChangesAsync();
    }

    private static ProjectsController Controller(PmsDbContext db, Guid actorId, TestHubContext? hub = null, AppMail? mail = null)
    {
        var controller = new ProjectsController(db, new RealtimePublisher(hub ?? new TestHubContext()), mail);
        var context = new DefaultHttpContext
        {
            User = new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier, actorId.ToString())], "test"))
        };
        context.TraceIdentifier = Guid.NewGuid().ToString();
        controller.ControllerContext = new ControllerContext { HttpContext = context };
        return controller;
    }

    private static AppMail TestMail() => new(new ConfigurationBuilder().Build(), new TestHttpClientFactory(),
        NullLogger<AppMail>.Instance);

    private static User User(Guid id) => new()
    {
        Id = id, FirstName = "Member", LastName = "Test", Email = $"{id:N}@example.test", PasswordHash = "hash"
    };

    private static void AssertCode(IActionResult result, string expected)
    {
        var response = Assert.IsType<ObjectResult>(result);
        Assert.Equal(expected, response.Value?.GetType().GetProperty("code")?.GetValue(response.Value));
    }

    private sealed record Fixture(Guid OrganizationId, Guid ProjectId, Guid ActorId, Guid TargetId,
        Guid ReplacementId, Guid TaskId);

    private sealed class TestHubContext : IHubContext<WorkspaceHub>
    {
        private readonly TestClientProxy _proxy = new();
        public int SendCount => _proxy.SendCount;
        public IHubClients Clients => new TestHubClients(_proxy);
        public IGroupManager Groups { get; } = new TestGroupManager();
    }
    private sealed class TestHubClients : IHubClients
    {
        private readonly IClientProxy _proxy;
        public TestHubClients(IClientProxy proxy) => _proxy = proxy;
        public IClientProxy All => _proxy;
        public IClientProxy AllExcept(IReadOnlyList<string> ids) => _proxy;
        public IClientProxy Client(string id) => _proxy;
        public IClientProxy Clients(IReadOnlyList<string> ids) => _proxy;
        public IClientProxy Group(string name) => _proxy;
        public IClientProxy GroupExcept(string name, IReadOnlyList<string> ids) => _proxy;
        public IClientProxy Groups(IReadOnlyList<string> names) => _proxy;
        public IClientProxy User(string id) => _proxy;
        public IClientProxy Users(IReadOnlyList<string> ids) => _proxy;
    }
    private sealed class TestClientProxy : IClientProxy
    {
        public int SendCount { get; private set; }
        public Task SendCoreAsync(string method, object?[] args, CancellationToken cancellationToken = default)
        { SendCount++; return Task.CompletedTask; }
    }
    private sealed class TestGroupManager : IGroupManager
    {
        public Task AddToGroupAsync(string connectionId, string groupName, CancellationToken cancellationToken = default) => Task.CompletedTask;
        public Task RemoveFromGroupAsync(string connectionId, string groupName, CancellationToken cancellationToken = default) => Task.CompletedTask;
    }
    private sealed class TestHttpClientFactory : IHttpClientFactory
    {
        public HttpClient CreateClient(string name) => new();
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

    private sealed class RetryTestDatabase : IAsyncDisposable
    {
        private RetryTestDatabase(SqliteConnection connection, PmsDbContext db, ForcedTransientSaveChanges interceptor,
            TestHubContext hub, string connectionString)
        { Connection = connection; Db = db; TransientFailure = interceptor; Hub = hub; ConnectionString = connectionString; }
        public SqliteConnection Connection { get; }
        public PmsDbContext Db { get; }
        public ForcedTransientSaveChanges TransientFailure { get; }
        public TestHubContext Hub { get; }
        public string ConnectionString { get; }
        public static async Task<RetryTestDatabase> Create()
        {
            var connectionString = $"Data Source=member-removal-{Guid.NewGuid():N};Mode=Memory;Cache=Shared";
            var connection = new SqliteConnection(connectionString);
            await connection.OpenAsync();
            var interceptor = new ForcedTransientSaveChanges();
            var options = new DbContextOptionsBuilder<PmsDbContext>().UseSqlite(connection)
                .AddInterceptors(interceptor)
                .ReplaceService<IExecutionStrategyFactory, ForcedRetryStrategyFactory>().Options;
            var db = new PmsDbContext(options);
            await db.Database.EnsureCreatedAsync();
            return new RetryTestDatabase(connection, db, interceptor, new TestHubContext(), connectionString);
        }
        public async ValueTask DisposeAsync() { await Db.DisposeAsync(); await Connection.DisposeAsync(); }
    }

    private sealed class SyntheticTransientException(Action? afterFailure) : Exception
    {
        public Action? AfterFailure { get; } = afterFailure;
    }

    private sealed class ForcedTransientSaveChanges : SaveChangesInterceptor
    {
        public bool Enabled { get; set; }
        public int SaveAttempts { get; private set; }
        public Action? AfterFirstFailure { get; set; }
        public override ValueTask<InterceptionResult<int>> SavingChangesAsync(DbContextEventData eventData,
            InterceptionResult<int> result, CancellationToken cancellationToken = default)
        {
            if (Enabled)
            {
                SaveAttempts++;
                var afterFailure = SaveAttempts == 1 ? AfterFirstFailure : null;
                throw new SyntheticTransientException(afterFailure);
            }
            return ValueTask.FromResult(result);
        }
    }

    private sealed class ForcedRetryStrategyFactory(ExecutionStrategyDependencies dependencies) : IExecutionStrategyFactory
    {
        public IExecutionStrategy Create() => new ForcedRetryStrategy(dependencies);
    }

    private sealed class ForcedRetryStrategy(ExecutionStrategyDependencies dependencies)
        : ExecutionStrategy(dependencies, maxRetryCount: 6, maxRetryDelay: TimeSpan.Zero)
    {
        protected override bool ShouldRetryOn(Exception exception)
        {
            if (exception is not SyntheticTransientException transient) return false;
            transient.AfterFailure?.Invoke();
            return true;
        }
    }
}
