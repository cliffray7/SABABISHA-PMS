using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Pms.Api.Controllers.Rest.V1;
using Pms.Domain.Entities;
using Pms.Infrastructure.Persistence.EfCore;

namespace Pms.IntegrationTests;

public sealed class TaskAssignmentHistoryTests
{
    [Fact]
    public async Task HistoryReadRequiresCurrentProjectAccessAndMarksLegacyPeriodIncomplete()
    {
        await using var database = await TestDatabase.Create();
        var fixture = await SeedAsync(database.Db);
        var authorized = await Controller(database.Db, fixture.MemberId)
            .Get(fixture.ProjectId, fixture.TaskId, CancellationToken.None);
        var response = Assert.IsType<OkObjectResult>(authorized);
        Assert.Equal(false, response.Value?.GetType().GetProperty("legacyHistoryComplete")?.GetValue(response.Value));
        var events = response.Value?.GetType().GetProperty("events")?.GetValue(response.Value) as System.Collections.ICollection;
        Assert.NotNull(events);
        Assert.Single(events);

        var unauthorized = await Controller(database.Db, fixture.OutsiderId)
            .Get(fixture.ProjectId, fixture.TaskId, CancellationToken.None);
        Assert.IsType<ForbidResult>(unauthorized);
        var crossProject = await Controller(database.Db, fixture.MemberId)
            .Get(Guid.NewGuid(), fixture.TaskId, CancellationToken.None);
        Assert.IsType<NotFoundResult>(crossProject);
    }

    private static async Task<Fixture> SeedAsync(PmsDbContext db)
    {
        var organizationId = Guid.NewGuid(); var projectId = Guid.NewGuid();
        var memberId = Guid.NewGuid(); var outsiderId = Guid.NewGuid(); var taskId = Guid.NewGuid();
        var eventId = Guid.NewGuid();
        db.Organizations.Add(new Organization { Id = organizationId, Name = "Org", Slug = $"history-{organizationId:N}" });
        db.Users.AddRange(User(memberId), User(outsiderId));
        db.Projects.Add(new Project { Id = projectId, OrganizationId = organizationId, OwnerId = memberId, Name = "Project" });
        db.OrganizationMembers.Add(new OrganizationMember
        {
            Id = Guid.NewGuid(), OrganizationId = organizationId, UserId = memberId, Role = "MEMBER"
        });
        db.ProjectMembers.Add(new ProjectMember { Id = Guid.NewGuid(), ProjectId = projectId, UserId = memberId, Role = "VIEWER" });
        db.Tasks.Add(new WorkTask { Id = taskId, ProjectId = projectId, Title = "Task", Status = "DONE", CreatedBy = memberId });
        db.TaskAssignmentEvents.Add(new TaskAssignmentEvent
        {
            EventId = eventId, OperationId = Guid.NewGuid(), OrganizationId = organizationId, ProjectId = projectId,
            TaskId = taskId, DepartingUserId = memberId, ActorUserId = memberId,
            OccurredAtUtc = DateTime.UtcNow, Action = "UNASSIGNED"
        });
        await db.SaveChangesAsync();
        return new Fixture(projectId, taskId, memberId, outsiderId);
    }

    private static TaskAssignmentHistoryController Controller(PmsDbContext db, Guid userId)
    {
        var controller = new TaskAssignmentHistoryController(db);
        controller.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext
            {
                User = new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier, userId.ToString())], "test"))
            }
        };
        return controller;
    }

    private static User User(Guid id) => new()
    {
        Id = id, FirstName = "Member", LastName = "Test", Email = $"{id:N}@example.test", PasswordHash = "hash"
    };

    private sealed record Fixture(Guid ProjectId, Guid TaskId, Guid MemberId, Guid OutsiderId);
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
