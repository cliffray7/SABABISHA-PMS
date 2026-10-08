using System.Data.Common;
using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Options;
using Pms.Api.Controllers.Rest.V1;
using Pms.Api.Realtime;
using Pms.Api.Auth;
using Pms.Domain.Entities;
using Pms.Infrastructure.Persistence.EfCore;

namespace Pms.IntegrationTests;

public sealed class SqlServerManagerRaceTests
{
    [SqlServerFact]
    public async Task ConcurrentOrganizationDemotionAndDeactivation_CannotRemoveLastActiveManager()
    {
        var configuredConnection = Environment.GetEnvironmentVariable("PMS_TEST_SQLSERVER_CONNECTION")!;
        var scratchDatabase = $"PmsOrgGuardRace_{Guid.NewGuid():N}";
        var masterConnection = new SqlConnectionStringBuilder(configuredConnection) { InitialCatalog = "master" }.ConnectionString;
        var scratchConnection = new SqlConnectionStringBuilder(configuredConnection) { InitialCatalog = scratchDatabase }.ConnectionString;
        await using (var connection = new SqlConnection(masterConnection))
        {
            await connection.OpenAsync();
            await using var command = connection.CreateCommand();
            command.CommandText = $"CREATE DATABASE [{scratchDatabase}]";
            await command.ExecuteNonQueryAsync();
        }

        try
        {
            var options = new DbContextOptionsBuilder<PmsDbContext>().UseSqlServer(scratchConnection,
                sql => sql.EnableRetryOnFailure(3, TimeSpan.FromSeconds(2), null)).Options;
            var projectId = Guid.NewGuid(); var organizationId = Guid.NewGuid();
            var adminId = Guid.NewGuid(); var managerA = Guid.NewGuid(); var managerB = Guid.NewGuid();
            await using (var seed = new PmsDbContext(options))
            {
                await seed.Database.EnsureCreatedAsync();
                seed.Organizations.Add(new Organization { Id = organizationId, Name = "Organization race", Slug = $"org-race-{organizationId:N}" });
                seed.Projects.Add(new Project { Id = projectId, OrganizationId = organizationId, OwnerId = adminId, Name = "Organization race project" });
                seed.Users.AddRange(User(adminId, "Admin"), User(managerA, "Manager A"), User(managerB, "Manager B"));
                seed.OrganizationMembers.AddRange(
                    new OrganizationMember { Id = Guid.NewGuid(), OrganizationId = organizationId, UserId = adminId, Role = "ADMIN" },
                    new OrganizationMember { Id = Guid.NewGuid(), OrganizationId = organizationId, UserId = managerA, Role = "MEMBER" },
                    new OrganizationMember { Id = Guid.NewGuid(), OrganizationId = organizationId, UserId = managerB, Role = "MEMBER" });
                seed.ProjectMembers.AddRange(
                    new ProjectMember { Id = Guid.NewGuid(), ProjectId = projectId, UserId = managerA, Role = "PROJECT_MANAGER" },
                    new ProjectMember { Id = Guid.NewGuid(), ProjectId = projectId, UserId = managerB, Role = "PROJECT_MANAGER" });
                await seed.SaveChangesAsync();
            }

            var results = await Task.WhenAll(
                DeactivateOrganizationMember(options, adminId, organizationId, managerA),
                DemoteOrganizationMemberToGuest(options, adminId, organizationId, managerB))
                .WaitAsync(TimeSpan.FromSeconds(45));

            await using var verify = new PmsDbContext(options);
            var remainingManagers = await (from projectMember in verify.ProjectMembers
                                            join organizationMember in verify.OrganizationMembers on projectMember.UserId equals organizationMember.UserId
                                            join user in verify.Users on projectMember.UserId equals user.Id
                                            where projectMember.ProjectId == projectId && projectMember.Role == "PROJECT_MANAGER"
                                                && projectMember.Status == "active" && organizationMember.OrganizationId == organizationId
                                                && organizationMember.Status == "active" && organizationMember.Role != "GUEST"
                                                && user.Status == "active"
                                            select projectMember.UserId).Distinct().CountAsync();
            Assert.True(remainingManagers >= 1, "Concurrent organization changes must leave an eligible active project manager.");
            Assert.Single(results.OfType<NoContentResult>());
            Assert.Single(results.OfType<ObjectResult>().Where(result => result.StatusCode == StatusCodes.Status409Conflict));
        }
        finally
        {
            await using var connection = new SqlConnection(masterConnection);
            await connection.OpenAsync();
            await using var command = connection.CreateCommand();
            command.CommandText = $"ALTER DATABASE [{scratchDatabase}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{scratchDatabase}]";
            await command.ExecuteNonQueryAsync();
        }
    }

    [SqlServerFact]
    public async Task ConcurrentProjectMemberRemovalAndRoleChange_PreserveOwnerManager()
    {
        var configuredConnection = Environment.GetEnvironmentVariable("PMS_TEST_SQLSERVER_CONNECTION")!;
        var scratchDatabase = $"PmsMemberOpsRace_{Guid.NewGuid():N}";
        var masterConnection = new SqlConnectionStringBuilder(configuredConnection) { InitialCatalog = "master" }.ConnectionString;
        var scratchConnection = new SqlConnectionStringBuilder(configuredConnection) { InitialCatalog = scratchDatabase }.ConnectionString;
        await using (var connection = new SqlConnection(masterConnection))
        {
            await connection.OpenAsync();
            await using var command = connection.CreateCommand();
            command.CommandText = $"CREATE DATABASE [{scratchDatabase}]";
            await command.ExecuteNonQueryAsync();
        }

        try
        {
            var options = new DbContextOptionsBuilder<PmsDbContext>().UseSqlServer(scratchConnection,
                sql => sql.EnableRetryOnFailure(3, TimeSpan.FromSeconds(2), null)).Options;
            var projectId = Guid.NewGuid(); var organizationId = Guid.NewGuid();
            var adminId = Guid.NewGuid(); var managerA = Guid.NewGuid(); var managerB = Guid.NewGuid();
            await using (var seed = new PmsDbContext(options))
            {
                await seed.Database.EnsureCreatedAsync();
                seed.Organizations.Add(new Organization { Id = organizationId, Name = "Member operation race", Slug = $"member-ops-{organizationId:N}" });
                seed.Projects.Add(new Project { Id = projectId, OrganizationId = organizationId, OwnerId = adminId, Name = "Member operation project" });
                seed.Users.AddRange(User(adminId, "Admin"), User(managerA, "Manager A"), User(managerB, "Manager B"));
                seed.OrganizationMembers.AddRange(
                    new OrganizationMember { Id = Guid.NewGuid(), OrganizationId = organizationId, UserId = adminId, Role = "ADMIN" },
                    new OrganizationMember { Id = Guid.NewGuid(), OrganizationId = organizationId, UserId = managerA, Role = "MEMBER" },
                    new OrganizationMember { Id = Guid.NewGuid(), OrganizationId = organizationId, UserId = managerB, Role = "MEMBER" });
                seed.ProjectMembers.AddRange(
                    new ProjectMember { Id = Guid.NewGuid(), ProjectId = projectId, UserId = adminId, Role = "PROJECT_MANAGER" },
                    new ProjectMember { Id = Guid.NewGuid(), ProjectId = projectId, UserId = managerA, Role = "PROJECT_MANAGER" },
                    new ProjectMember { Id = Guid.NewGuid(), ProjectId = projectId, UserId = managerB, Role = "PROJECT_MANAGER" });
                await seed.SaveChangesAsync();
            }

            var results = await Task.WhenAll(
                RemoveProjectMember(options, adminId, projectId, managerB),
                ChangeRole(options, adminId, projectId, managerA))
                .WaitAsync(TimeSpan.FromSeconds(45));
            Assert.All(results, result => Assert.True(result is NoContentResult
                || result is ObjectResult { StatusCode: StatusCodes.Status409Conflict },
                $"Unexpected concurrent result: {result.GetType().Name}"));

            await using var verify = new PmsDbContext(options);
            var remainingManagers = await (from projectMember in verify.ProjectMembers
                                            join organizationMember in verify.OrganizationMembers on projectMember.UserId equals organizationMember.UserId
                                            join user in verify.Users on projectMember.UserId equals user.Id
                                            where projectMember.ProjectId == projectId && projectMember.Role == "PROJECT_MANAGER"
                                                && projectMember.Status == "active" && organizationMember.OrganizationId == organizationId
                                                && organizationMember.Status == "active" && organizationMember.Role != "GUEST"
                                                && user.Status == "active"
                                            select projectMember.UserId).Distinct().CountAsync();
            Assert.True(remainingManagers >= 1);
        }
        finally
        {
            await using var connection = new SqlConnection(masterConnection);
            await connection.OpenAsync();
            await using var command = connection.CreateCommand();
            command.CommandText = $"ALTER DATABASE [{scratchDatabase}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{scratchDatabase}]";
            await command.ExecuteNonQueryAsync();
        }
    }

    [SqlServerFact]
    public async Task ConcurrentTaskAssignmentAndGuestDemotion_CannotLeaveGuestAssigned()
    {
        var configuredConnection = Environment.GetEnvironmentVariable("PMS_TEST_SQLSERVER_CONNECTION")!;
        var scratchDatabase = $"PmsAssignmentRace_{Guid.NewGuid():N}";
        var masterConnection = new SqlConnectionStringBuilder(configuredConnection) { InitialCatalog = "master" }.ConnectionString;
        var scratchConnection = new SqlConnectionStringBuilder(configuredConnection) { InitialCatalog = scratchDatabase }.ConnectionString;
        await using (var connection = new SqlConnection(masterConnection))
        {
            await connection.OpenAsync();
            await using var command = connection.CreateCommand();
            command.CommandText = $"CREATE DATABASE [{scratchDatabase}]";
            await command.ExecuteNonQueryAsync();
        }

        try
        {
            var options = new DbContextOptionsBuilder<PmsDbContext>().UseSqlServer(scratchConnection,
                sql => sql.EnableRetryOnFailure(3, TimeSpan.FromSeconds(2), null)).Options;
            var projectId = Guid.NewGuid(); var organizationId = Guid.NewGuid();
            var adminId = Guid.NewGuid(); var targetId = Guid.NewGuid(); var removalTargetId = Guid.NewGuid();
            await using (var seed = new PmsDbContext(options))
            {
                await seed.Database.EnsureCreatedAsync();
                seed.Organizations.Add(new Organization { Id = organizationId, Name = "Assignment race", Slug = $"assignment-race-{organizationId:N}" });
                seed.Projects.Add(new Project { Id = projectId, OrganizationId = organizationId, OwnerId = adminId, Name = "Assignment race project" });
                seed.Users.AddRange(User(adminId, "Admin"), User(targetId, "Target"), User(removalTargetId, "Removal target"));
                seed.OrganizationMembers.AddRange(
                    new OrganizationMember { Id = Guid.NewGuid(), OrganizationId = organizationId, UserId = adminId, Role = "ADMIN" },
                    new OrganizationMember { Id = Guid.NewGuid(), OrganizationId = organizationId, UserId = targetId, Role = "MEMBER" },
                    new OrganizationMember { Id = Guid.NewGuid(), OrganizationId = organizationId, UserId = removalTargetId, Role = "MEMBER" });
                seed.ProjectMembers.AddRange(
                    new ProjectMember { Id = Guid.NewGuid(), ProjectId = projectId, UserId = adminId, Role = "PROJECT_MANAGER" },
                    new ProjectMember { Id = Guid.NewGuid(), ProjectId = projectId, UserId = targetId, Role = "CONTRIBUTOR" },
                    new ProjectMember { Id = Guid.NewGuid(), ProjectId = projectId, UserId = removalTargetId, Role = "CONTRIBUTOR" });
                await seed.SaveChangesAsync();
            }

            var results = await Task.WhenAll(
                CreateAssignedTask(options, adminId, projectId, targetId),
                DemoteOrganizationMemberToGuest(options, adminId, organizationId, targetId))
                .WaitAsync(TimeSpan.FromSeconds(45));
            var taskCreated = results[0] is OkObjectResult;
            var demotionCompleted = results[1] is NoContentResult;
            Assert.True(taskCreated || demotionCompleted, "At least one serialized request should complete.");

            await using var verify = new PmsDbContext(options);
            var guest = await verify.OrganizationMembers.SingleAsync(member => member.UserId == targetId);
            var activeAssignments = await (from assignee in verify.TaskAssignees
                                            join task in verify.Tasks on assignee.TaskId equals task.Id
                                            where assignee.UserId == targetId && assignee.Status == "active" && task.DeletedAt == null
                                            select assignee.Id).CountAsync();
            if (guest.Role == "GUEST")
                Assert.Equal(0, activeAssignments);

            var removalRace = await Task.WhenAll(
                CreateAssignedTask(options, adminId, projectId, removalTargetId),
                RemoveProjectMember(options, adminId, projectId, removalTargetId))
                .WaitAsync(TimeSpan.FromSeconds(45));
            var removalTaskCreated = removalRace[0] is OkObjectResult;
            var memberRemoved = removalRace[1] is NoContentResult;
            Assert.False(removalTaskCreated && memberRemoved,
                "Task assignment and project-member removal must not both commit against stale membership state.");
            Assert.True(removalTaskCreated || memberRemoved, "At least one serialized request should complete.");
            await using var verifyRemoval = new PmsDbContext(options);
            var removedMember = await verifyRemoval.ProjectMembers.SingleAsync(member => member.ProjectId == projectId && member.UserId == removalTargetId);
            var removalTargetAssignments = await (from assignee in verifyRemoval.TaskAssignees
                                                  join task in verifyRemoval.Tasks on assignee.TaskId equals task.Id
                                                  where assignee.UserId == removalTargetId && assignee.Status == "active" && task.DeletedAt == null
                                                  select assignee.Id).CountAsync();
            Assert.False(removedMember.Status != "active" && removalTargetAssignments > 0,
                "A removed project member must not retain an active task assignment.");
        }
        finally
        {
            await using var connection = new SqlConnection(masterConnection);
            await connection.OpenAsync();
            await using var command = connection.CreateCommand();
            command.CommandText = $"ALTER DATABASE [{scratchDatabase}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{scratchDatabase}]";
            await command.ExecuteNonQueryAsync();
        }
    }

    [SqlServerFact]
    public async Task ConcurrentManagerDemotions_CannotCommitManagerlessProject()
    {
        var configuredConnection = Environment.GetEnvironmentVariable("PMS_TEST_SQLSERVER_CONNECTION")!;
        var scratchDatabase = $"PmsRoleRace_{Guid.NewGuid():N}";
        var masterConnection = new SqlConnectionStringBuilder(configuredConnection) { InitialCatalog = "master" }.ConnectionString;
        var scratchConnection = new SqlConnectionStringBuilder(configuredConnection) { InitialCatalog = scratchDatabase }.ConnectionString;
        await using (var connection = new SqlConnection(masterConnection))
        {
            await connection.OpenAsync();
            await using var command = connection.CreateCommand();
            command.CommandText = $"CREATE DATABASE [{scratchDatabase}]";
            await command.ExecuteNonQueryAsync();
        }

        try
        {
            var barrier = new ManagerCountReadBarrier();
            var options = new DbContextOptionsBuilder<PmsDbContext>().UseSqlServer(scratchConnection,
                    sql => sql.EnableRetryOnFailure(3, TimeSpan.FromSeconds(5), null))
                .AddInterceptors(barrier).Options;
            var projectId = Guid.NewGuid(); var organizationId = Guid.NewGuid(); var adminId = Guid.NewGuid();
            var managerA = Guid.NewGuid(); var managerB = Guid.NewGuid();
            await using (var seed = new PmsDbContext(options))
            {
                await seed.Database.EnsureCreatedAsync();
                seed.Organizations.Add(new Organization { Id = organizationId, Name = "Race test", Slug = $"race-{organizationId:N}" });
                seed.Projects.Add(new Project { Id = projectId, OrganizationId = organizationId, OwnerId = adminId, Name = "Race project" });
                seed.Users.AddRange(User(adminId, "Admin"), User(managerA, "Manager A"), User(managerB, "Manager B"));
                seed.OrganizationMembers.AddRange(
                    new OrganizationMember { Id = Guid.NewGuid(), OrganizationId = organizationId, UserId = adminId, Role = "ADMIN" },
                    new OrganizationMember { Id = Guid.NewGuid(), OrganizationId = organizationId, UserId = managerA, Role = "MEMBER" },
                    new OrganizationMember { Id = Guid.NewGuid(), OrganizationId = organizationId, UserId = managerB, Role = "MEMBER" });
                seed.ProjectMembers.AddRange(
                    new ProjectMember { Id = Guid.NewGuid(), ProjectId = projectId, UserId = managerA, Role = "PROJECT_MANAGER" },
                    new ProjectMember { Id = Guid.NewGuid(), ProjectId = projectId, UserId = managerB, Role = "PROJECT_MANAGER" });
                await seed.SaveChangesAsync();
            }

            var first = ChangeRole(options, adminId, projectId, managerA);
            var second = ChangeRole(options, adminId, projectId, managerB);
            var results = await Task.WhenAll(first, second).WaitAsync(TimeSpan.FromSeconds(45));
            Assert.True(barrier.Arrivals >= 2, $"Expected two simultaneous manager-count reads, observed {barrier.Arrivals}.");
            Assert.Single(results.OfType<NoContentResult>());
            Assert.Single(results.OfType<ObjectResult>().Where(result => result.StatusCode == StatusCodes.Status400BadRequest
                && result.Value?.GetType().GetProperty("code")?.GetValue(result.Value)?.ToString() == "project_must_retain_manager"));

            await using var verify = new PmsDbContext(options);
            var remainingManagers = await (from projectMember in verify.ProjectMembers
                                           join organizationMember in verify.OrganizationMembers on projectMember.UserId equals organizationMember.UserId
                                           join user in verify.Users on projectMember.UserId equals user.Id
                                           where projectMember.ProjectId == projectId && projectMember.Role == "PROJECT_MANAGER"
                                               && projectMember.Status == "active" && organizationMember.OrganizationId == organizationId
                                               && organizationMember.Status == "active" && user.Status == "active"
                                           select projectMember.UserId).Distinct().CountAsync();
            Assert.Equal(1, remainingManagers);
        }
        finally
        {
            await using var connection = new SqlConnection(masterConnection);
            await connection.OpenAsync();
            await using var command = connection.CreateCommand();
            command.CommandText = $"ALTER DATABASE [{scratchDatabase}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{scratchDatabase}]";
            await command.ExecuteNonQueryAsync();
        }
    }

    private static async Task<IActionResult> ChangeRole(DbContextOptions<PmsDbContext> options, Guid actorId, Guid projectId, Guid targetId)
    {
        await using var db = new PmsDbContext(options);
        var controller = new ProjectsController(db, new RealtimePublisher(new TestHubContext()));
        var http = new DefaultHttpContext
        {
            User = new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier, actorId.ToString())], "race-test"))
        };
        http.TraceIdentifier = Guid.NewGuid().ToString();
        controller.ControllerContext = new ControllerContext { HttpContext = http };
        return await controller.UpdateMemberRole(projectId, targetId,
            new UpdateProjectMemberRoleRequest("CONTRIBUTOR"), CancellationToken.None);
    }

    private static async Task<IActionResult> RemoveProjectMember(DbContextOptions<PmsDbContext> options,
        Guid actorId, Guid projectId, Guid targetId)
    {
        await using var db = new PmsDbContext(options);
        var controller = new ProjectsController(db, new RealtimePublisher(new TestHubContext()));
        var http = new DefaultHttpContext
        {
            User = new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier, actorId.ToString())], "race-test"))
        };
        http.TraceIdentifier = Guid.NewGuid().ToString();
        controller.ControllerContext = new ControllerContext { HttpContext = http };
        return await controller.RemoveMember(projectId, targetId, CancellationToken.None);
    }

    private static async Task<IActionResult> DeactivateOrganizationMember(DbContextOptions<PmsDbContext> options,
        Guid actorId, Guid organizationId, Guid targetId)
    {
        await using var db = new PmsDbContext(options);
        var controller = OrganizationController(db, actorId);
        return await controller.RemoveMember(organizationId, targetId, CancellationToken.None);
    }

    private static async Task<IActionResult> DemoteOrganizationMemberToGuest(DbContextOptions<PmsDbContext> options,
        Guid actorId, Guid organizationId, Guid targetId)
    {
        await using var db = new PmsDbContext(options);
        var controller = OrganizationController(db, actorId);
        return await controller.Role(organizationId, targetId, new UpdateRoleRequest("GUEST"), CancellationToken.None);
    }

    private static async Task<IActionResult> CreateAssignedTask(DbContextOptions<PmsDbContext> options,
        Guid actorId, Guid projectId, Guid assigneeId)
    {
        await using var db = new PmsDbContext(options);
        var controller = new TasksController(db, CreateMail(), new RealtimePublisher(new TestHubContext()));
        var http = new DefaultHttpContext
        {
            User = new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier, actorId.ToString())], "race-test"))
        };
        http.TraceIdentifier = Guid.NewGuid().ToString();
        controller.ControllerContext = new ControllerContext { HttpContext = http };
        return await controller.Create(projectId,
            new CreateTaskRequest("Race task", null, null, null, null, [assigneeId]), CancellationToken.None);
    }

    private static AppMail CreateMail() => new(new ConfigurationBuilder().Build(), new TestHttpClientFactory(),
        Microsoft.Extensions.Logging.Abstractions.NullLogger<AppMail>.Instance);

    private static OrganizationsController OrganizationController(PmsDbContext db, Guid actorId)
    {
        var controller = new OrganizationsController(db, null!, null!, new RealtimePublisher(new TestHubContext()));
        var http = new DefaultHttpContext
        {
            User = new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier, actorId.ToString())], "race-test"))
        };
        http.TraceIdentifier = Guid.NewGuid().ToString();
        controller.ControllerContext = new ControllerContext { HttpContext = http };
        return controller;
    }

    private static User User(Guid id, string firstName) => new()
    {
        Id = id, FirstName = firstName, LastName = "Race", Email = $"{id}@example.test", PasswordHash = "hash"
    };

    private sealed class TestHttpClientFactory : IHttpClientFactory
    {
        public HttpClient CreateClient(string name) => new();
    }

    private sealed class ManagerCountReadBarrier : DbCommandInterceptor
    {
        private readonly TaskCompletionSource gate = new(TaskCreationOptions.RunContinuationsAsynchronously);
        private int arrivals;
        public int Arrivals => Volatile.Read(ref arrivals);

        public override async ValueTask<InterceptionResult<DbDataReader>> ReaderExecutingAsync(
            DbCommand command, CommandEventData eventData, InterceptionResult<DbDataReader> result,
            CancellationToken cancellationToken = default)
        {
            if (command.CommandText.Contains("COUNT", StringComparison.OrdinalIgnoreCase)
                && command.CommandText.Contains("project_members", StringComparison.OrdinalIgnoreCase)
                && command.CommandText.Contains("organization_members", StringComparison.OrdinalIgnoreCase)
                && command.CommandText.Contains("users", StringComparison.OrdinalIgnoreCase))
            {
                var arrival = Interlocked.Increment(ref arrivals);
                if (arrival == 2) gate.TrySetResult();
                if (arrival <= 2) await gate.Task.WaitAsync(TimeSpan.FromSeconds(15), cancellationToken);
            }
            return result;
        }
    }

    public sealed class SqlServerFactAttribute : FactAttribute
    {
        public SqlServerFactAttribute()
        {
            if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("PMS_TEST_SQLSERVER_CONNECTION")))
                Skip = "Set PMS_TEST_SQLSERVER_CONNECTION to opt in to the isolated SQL Server race test.";
        }
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
