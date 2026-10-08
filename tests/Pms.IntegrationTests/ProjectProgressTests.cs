using System.Security.Claims;
using System.Text;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Pms.Api.Controllers.Rest.V1;
using Pms.Api.Progress;
using Pms.Api.Realtime;
using Pms.Api.Reports;
using Pms.Domain.Entities;
using Pms.Infrastructure.Persistence.EfCore;

namespace Pms.IntegrationTests;

public sealed class ProjectProgressTests
{
    [Fact]
    public async Task ProgressEndpointReturnsProjectWideAggregateAndKeepsCompletedLifecycleStatus()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await Seed(database.Context, projectStatus: "COMPLETED");
        var eligible = Enumerable.Range(0, 8)
            .Select(_ => NewTask(fixture.ProjectId, "DONE", dueDate: DateTime.UtcNow.Date.AddDays(-3)))
            .Concat(Enumerable.Range(0, 2)
                .Select(_ => NewTask(fixture.ProjectId, "IN PROGRESS", dueDate: DateTime.UtcNow.Date.AddDays(-3))))
            .ToArray();
        database.Context.Tasks.AddRange(eligible);
        database.Context.Tasks.AddRange(
            NewTask(fixture.ProjectId, "DONE", parentTaskId: eligible[0].Id),
            NewTask(fixture.ProjectId, "DONE", deletedAt: DateTime.UtcNow));
        await database.Context.SaveChangesAsync();

        var result = await Controller(database.Context, fixture.ActorId).GetProgress(fixture.ProjectId, default);

        var response = Assert.IsType<OkObjectResult>(result).Value!;
        Assert.Equal("COMPLETED", Property<string>(response, "projectStatus"));
        Assert.True(Property<bool>(response, "hasTasks"));
        Assert.Equal(10, Property<int>(response, "totalEligibleTasks"));
        Assert.Equal(8, Property<int>(response, "completedTasks"));
        Assert.Equal(80, Property<int?>(response, "progressPercent"));
        Assert.Equal(2, Property<int>(response, "outstandingTaskCount"));
        Assert.Equal(2, Property<int>(response, "overdueTaskCount"));
        Assert.Equal("COMPLETED", await database.Context.Projects.Where(project => project.Id == fixture.ProjectId)
            .Select(project => project.Status).SingleAsync());
    }

    [Fact]
    public async Task EmptyAccessibleProjectIsDifferentFromInaccessibleProject()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await Seed(database.Context);

        var accessible = await Controller(database.Context, fixture.ActorId).GetProgress(fixture.ProjectId, default);
        var inaccessible = await Controller(database.Context, Guid.NewGuid()).GetProgress(fixture.ProjectId, default);

        var response = Assert.IsType<OkObjectResult>(accessible).Value!;
        Assert.False(Property<bool>(response, "hasTasks"));
        Assert.Null(Property<int?>(response, "progressPercent"));
        Assert.Equal(0, Property<int>(response, "totalEligibleTasks"));
        Assert.Equal(0, Property<int>(response, "completedTasks"));
        Assert.Equal(0, Property<int>(response, "outstandingTaskCount"));
        Assert.Equal(0, Property<int>(response, "overdueTaskCount"));
        Assert.IsType<ForbidResult>(inaccessible);
    }

    [Fact]
    public async Task NonEmptyProjectWithNoDoneTasksReportsZeroPercentAndAggregateHasNoTaskDetails()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await Seed(database.Context);
        database.Context.Tasks.Add(NewTask(fixture.ProjectId, "IN PROGRESS"));
        await database.Context.SaveChangesAsync();

        var result = await Controller(database.Context, fixture.ActorId).GetProgress(fixture.ProjectId, default);

        var response = Assert.IsType<OkObjectResult>(result).Value!;
        Assert.True(Property<bool>(response, "hasTasks"));
        Assert.Equal(0, Property<int?>(response, "progressPercent"));
        Assert.Equal(1, Property<int>(response, "totalEligibleTasks"));
        Assert.Equal(9, response.GetType().GetProperties().Length);
        Assert.DoesNotContain("Title", string.Join(',', response.GetType().GetProperties().Select(property => property.Name)),
            StringComparison.OrdinalIgnoreCase);
    }

    [Theory]
    [InlineData("guest", "active", "active", false)]
    [InlineData("member", "inactive", "active", true)]
    [InlineData("member", "active", "suspended", false)]
    public async Task ProgressEndpointUsesExistingProjectReadAuthorization(string orgRole, string membershipStatus,
        string accountStatus, bool forbidden)
    {
        await using var database = await TestDatabase.Create();
        var fixture = await Seed(database.Context, actorOrganizationRole: orgRole,
            organizationMembershipStatus: membershipStatus, accountStatus: accountStatus);

        var result = await Controller(database.Context, fixture.ActorId).GetProgress(fixture.ProjectId, default);

        if (forbidden) Assert.IsType<ForbidResult>(result);
        else Assert.IsType<OkObjectResult>(result);
    }

    [Fact]
    public async Task ArchivedAndTrashedProjectsAreNotExposedByProgressEndpoint()
    {
        await using var database = await TestDatabase.Create();
        var archived = await Seed(database.Context, archivedAt: DateTime.UtcNow);
        var trashed = await Seed(database.Context, deletedAt: DateTime.UtcNow);

        Assert.IsType<ForbidResult>(await Controller(database.Context, archived.ActorId)
            .GetProgress(archived.ProjectId, default));
        Assert.IsType<ForbidResult>(await Controller(database.Context, trashed.ActorId)
            .GetProgress(trashed.ProjectId, default));
    }

    [Fact]
    public async Task InactiveProjectMembershipCannotReadProgress()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await Seed(database.Context);
        var membership = await database.Context.ProjectMembers.SingleAsync(member => member.ProjectId == fixture.ProjectId);
        membership.Status = "inactive";
        await database.Context.SaveChangesAsync();

        var result = await Controller(database.Context, fixture.ActorId).GetProgress(fixture.ProjectId, default);

        Assert.IsType<ForbidResult>(result);
    }

    [Fact]
    public async Task MemberOfAnotherTenantCannotReadProjectProgress()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await Seed(database.Context);
        var foreignOrganizationId = Guid.NewGuid();
        var foreignProjectId = Guid.NewGuid();
        var foreignUserId = Guid.NewGuid();
        database.Context.Users.Add(new User
        {
            Id = foreignUserId, FirstName = "Foreign", LastName = "Member", Email = $"{foreignUserId}@example.test",
            PasswordHash = "hash"
        });
        database.Context.Organizations.Add(new Organization
        {
            Id = foreignOrganizationId, Name = $"Foreign Org {foreignOrganizationId:N}",
            Slug = $"foreign-{foreignOrganizationId:N}"
        });
        database.Context.OrganizationMembers.Add(new OrganizationMember
        {
            Id = Guid.NewGuid(), OrganizationId = foreignOrganizationId, UserId = foreignUserId, Role = "MEMBER"
        });
        database.Context.Projects.Add(new Project
        {
            Id = foreignProjectId, OrganizationId = foreignOrganizationId, Name = "Foreign project", OwnerId = foreignUserId
        });
        database.Context.ProjectMembers.Add(new ProjectMember
        {
            Id = Guid.NewGuid(), ProjectId = foreignProjectId, UserId = foreignUserId, Role = "CONTRIBUTOR"
        });
        await database.Context.SaveChangesAsync();

        var result = await Controller(database.Context, foreignUserId).GetProgress(fixture.ProjectId, default);

        Assert.IsType<ForbidResult>(result);
    }

    [Fact]
    public void CalculatorUsesOrganizationCalendarDateAndUtcFallbackWithDiagnostic()
    {
        var tasks = new[]
        {
            new ProjectProgressTask("IN PROGRESS", new DateTime(2026, 1, 1)),
            new ProjectProgressTask("IN PROGRESS", new DateTime(2026, 1, 2)),
            new ProjectProgressTask("DONE", new DateTime(2026, 1, 1)),
            new ProjectProgressTask("IN PROGRESS", null)
        };
        var now = new DateTime(2026, 1, 1, 23, 30, 0, DateTimeKind.Utc);
        var valid = ProjectProgressCalculator.Calculate(tasks, "Africa/Nairobi", now, Guid.NewGuid());
        var logger = new CapturingLogger();
        var fallback = ProjectProgressCalculator.Calculate(tasks, "not-a-real-timezone", now, Guid.NewGuid(), logger);
        var missing = ProjectProgressCalculator.Calculate(tasks, null, now, Guid.NewGuid(), logger);

        Assert.Equal("Africa/Nairobi", valid.TimezoneIdUsed);
        Assert.Equal(1, valid.OverdueTaskCount); // Nairobi is already on Jan 2.
        Assert.Equal("UTC", fallback.TimezoneIdUsed);
        Assert.Equal(0, fallback.OverdueTaskCount); // UTC is still on Jan 1; due Jan 1 is not overdue yet.
        Assert.Equal("UTC", missing.TimezoneIdUsed);
        Assert.Contains(logger.Messages, message => message.Level == LogLevel.Warning);
        Assert.DoesNotContain(logger.Messages, message => message.Message.Contains("not-a-real-timezone", StringComparison.Ordinal));
    }

    [Fact]
    public void CalculatorRoundsExactHalfAwayFromZeroAndTreatsOnlyDoneAsComplete()
    {
        var tasks = Enumerable.Range(0, 8)
            .Select(index => new ProjectProgressTask(index == 0 ? "DONE" : "TODO", null))
            .ToArray();
        var result = ProjectProgressCalculator.Calculate(tasks, "UTC", DateTime.UtcNow, Guid.NewGuid());
        var completedStatus = ProjectProgressCalculator.CalculateCompletion(
            [new ProjectProgressTask("COMPLETED", null)]);

        Assert.Equal(13, result.ProgressPercent); // 12.5 rounds away from zero.
        Assert.Equal(0, completedStatus.Completed);
        Assert.Equal(0, completedStatus.Percent);
    }

    [Fact]
    public void PlatformPdfUsesSharedTopLevelDoneProgressAndLabelsArchivedAndEmptyProjects()
    {
        var activeId = Guid.NewGuid();
        var archivedId = Guid.NewGuid();
        var emptyId = Guid.NewGuid();
        var report = new PlatformReportData("RPT-TEST", DateTime.UtcNow, [], [],
            [
                new PlatformProjectReport(activeId, Guid.NewGuid(), "Active Project", "ACTIVE", DateTime.UtcNow),
                new PlatformProjectReport(archivedId, Guid.NewGuid(), "Archived Project", "COMPLETED", DateTime.UtcNow, true),
                new PlatformProjectReport(emptyId, Guid.NewGuid(), "Empty Project", "PLANNING", DateTime.UtcNow)
            ],
            [
                new PlatformTaskReport(Guid.NewGuid(), activeId, "Done", "DONE", "LOW", null, DateTime.UtcNow),
                new PlatformTaskReport(Guid.NewGuid(), activeId, "Open", "TODO", "LOW", null, DateTime.UtcNow),
                new PlatformTaskReport(Guid.NewGuid(), activeId, "Subtask", "DONE", "LOW", null, DateTime.UtcNow,
                    Guid.NewGuid()),
                new PlatformTaskReport(Guid.NewGuid(), archivedId, "Legacy completed code", "COMPLETED", "LOW", null,
                    DateTime.UtcNow)
            ]);

        var pdf = Encoding.ASCII.GetString(PlatformReportExport.Pdf(report));

        Assert.Contains("50%", pdf);
        Assert.Contains("Historical \\(Archived\\)", pdf);
        Assert.Contains("No tasks", pdf);
        Assert.DoesNotContain("100%", pdf);
    }

    private static async Task<Fixture> Seed(PmsDbContext db, string projectStatus = "ACTIVE",
        string actorOrganizationRole = "MEMBER", string organizationMembershipStatus = "active",
        string accountStatus = "active", DateTime? archivedAt = null, DateTime? deletedAt = null)
    {
        var organizationId = Guid.NewGuid();
        var projectId = Guid.NewGuid();
        var actorId = Guid.NewGuid();
        db.Users.Add(new User
        {
            Id = actorId, FirstName = "Actor", LastName = "Test", Email = $"{actorId}@example.test",
            PasswordHash = "hash", Status = accountStatus
        });
        db.Organizations.Add(new Organization
        {
            Id = organizationId, Name = $"Progress Org {organizationId:N}", Slug = $"progress-{organizationId:N}", Timezone = "UTC"
        });
        db.OrganizationMembers.Add(new OrganizationMember
        {
            Id = Guid.NewGuid(), OrganizationId = organizationId, UserId = actorId,
            Role = actorOrganizationRole, Status = organizationMembershipStatus
        });
        db.Projects.Add(new Project
        {
            Id = projectId, OrganizationId = organizationId, Name = "Progress Project", OwnerId = actorId,
            Status = projectStatus, ArchivedAt = archivedAt, DeletedAt = deletedAt
        });
        db.ProjectMembers.Add(new ProjectMember
        {
            Id = Guid.NewGuid(), ProjectId = projectId, UserId = actorId, Role = "CONTRIBUTOR"
        });
        await db.SaveChangesAsync();
        return new Fixture(projectId, actorId);
    }

    private static WorkTask NewTask(Guid projectId, string status, Guid? parentTaskId = null,
        DateTime? dueDate = null, DateTime? deletedAt = null) => new()
    {
        Id = Guid.NewGuid(), ProjectId = projectId, ParentTaskId = parentTaskId, Title = "Progress task",
        Status = status, Priority = "MEDIUM", CreatedBy = Guid.NewGuid(), DueDate = dueDate, DeletedAt = deletedAt
    };

    private static ProjectsController Controller(PmsDbContext db, Guid actorId)
    {
        var controller = new ProjectsController(db, new RealtimePublisher(new TestHubContext()));
        var http = new DefaultHttpContext
        {
            User = new ClaimsPrincipal(new ClaimsIdentity(
                [new Claim(ClaimTypes.NameIdentifier, actorId.ToString())], "test"))
        };
        controller.ControllerContext = new ControllerContext { HttpContext = http };
        return controller;
    }

    private static T Property<T>(object source, string name) =>
        (T)source.GetType().GetProperty(name, System.Reflection.BindingFlags.Public
            | System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.IgnoreCase)!.GetValue(source)!;

    private sealed record Fixture(Guid ProjectId, Guid ActorId);

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

    private sealed class CapturingLogger : ILogger
    {
        public List<(LogLevel Level, string Message)> Messages { get; } = [];
        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;
        public bool IsEnabled(LogLevel logLevel) => true;
        public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception,
            Func<TState, Exception?, string> formatter) => Messages.Add((logLevel, formatter(state, exception)));
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
