using System.Collections;
using System.Reflection;
using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Pms.Api.Controllers.Rest.V1;
using Pms.Domain.Entities;
using Pms.Infrastructure.Persistence.EfCore;

namespace Pms.IntegrationTests;

public sealed class AdminProjectTaskAssigneeTests
{
    [Fact]
    public async Task ProjectTaskRowsReturnNamesOnlyForCurrentEligibleAssignees()
    {
        await using var database = await TestDatabase.Create();
        var organization = new Organization
        {
            Id = Guid.NewGuid(), Name = "Assignee Test Org", Slug = "assignee-test-org", Timezone = "UTC"
        };
        var project = new Project
        {
            Id = Guid.NewGuid(), OrganizationId = organization.Id, Name = "Assignee Test Project",
            OwnerId = Guid.NewGuid(), Status = "ACTIVE"
        };
        var active = NewUser("Maya", "Chen", "maya@example.test");
        var guest = NewUser("Guest", "Member", "guest@example.test");
        var inactiveOrganizationMember = NewUser("Inactive", "Organization", "inactive-org@example.test");
        var suspended = NewUser("Suspended", "Account", "suspended@example.test", "suspended");
        var inactiveProjectMember = NewUser("Inactive", "Project", "inactive-project@example.test");
        var inactiveAssignment = NewUser("Old", "Assignee", "old-assignee@example.test");
        var task = new WorkTask
        {
            Id = Guid.NewGuid(), ProjectId = project.Id, Title = "Prepare release", Status = "IN PROGRESS",
            CreatedBy = active.Id
        };
        var unassignedTask = new WorkTask
        {
            Id = Guid.NewGuid(), ProjectId = project.Id, Title = "Review release", Status = "TODO",
            CreatedBy = active.Id
        };
        var subtask = new WorkTask
        {
            Id = Guid.NewGuid(), ProjectId = project.Id, ParentTaskId = task.Id, Title = "Check notes",
            Status = "TODO", CreatedBy = active.Id
        };

        database.Context.Users.AddRange(active, guest, inactiveOrganizationMember, suspended,
            inactiveProjectMember, inactiveAssignment);
        database.Context.Organizations.Add(organization);
        database.Context.Projects.Add(project);
        database.Context.OrganizationMembers.AddRange(
            OrgMember(organization.Id, active.Id, "MEMBER"),
            OrgMember(organization.Id, guest.Id, "GUEST"),
            OrgMember(organization.Id, inactiveOrganizationMember.Id, "MEMBER", "inactive"),
            OrgMember(organization.Id, suspended.Id, "MEMBER"),
            OrgMember(organization.Id, inactiveProjectMember.Id, "MEMBER"),
            OrgMember(organization.Id, inactiveAssignment.Id, "MEMBER"));
        database.Context.ProjectMembers.AddRange(
            ProjectMember(project.Id, active.Id),
            ProjectMember(project.Id, guest.Id),
            ProjectMember(project.Id, inactiveOrganizationMember.Id),
            ProjectMember(project.Id, suspended.Id),
            ProjectMember(project.Id, inactiveProjectMember.Id, "inactive"),
            ProjectMember(project.Id, inactiveAssignment.Id));
        database.Context.Tasks.AddRange(task, unassignedTask, subtask);
        database.Context.TaskAssignees.AddRange(
            Assignment(task.Id, active.Id),
            Assignment(task.Id, guest.Id),
            Assignment(task.Id, inactiveOrganizationMember.Id),
            Assignment(task.Id, suspended.Id),
            Assignment(task.Id, inactiveProjectMember.Id),
            Assignment(task.Id, inactiveAssignment.Id, "inactive"));
        await database.Context.SaveChangesAsync();

        var controller = new AdminController(database.Context)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext
                {
                    User = new ClaimsPrincipal(new ClaimsIdentity([], "test"))
                }
            }
        };

        var result = await controller.GetProjectTasks(project.Id, 1, 50, default);

        var response = Assert.IsType<OkObjectResult>(result).Value!;
        var items = Property<IEnumerable>(response, "items").Cast<object>().ToArray();
        Assert.Equal(2, items.Length); // Top-level tasks only.
        var assignedTask = Assert.Single(items, item => Property<Guid>(item, "Id") == task.Id);
        Assert.Equal(new[] { "Maya Chen" }, Property<IEnumerable>(assignedTask, "effectiveAssignees").Cast<string>());
        Assert.Equal(1, Property<int>(assignedTask, "effectiveAssigneeCount"));
        Assert.DoesNotContain("guest@example.test", string.Join(',', Property<IEnumerable>(assignedTask, "effectiveAssignees")));
        Assert.DoesNotContain("suspended@example.test", string.Join(',', Property<IEnumerable>(assignedTask, "effectiveAssignees")));
        Assert.DoesNotContain("Email", string.Join(',', assignedTask.GetType().GetProperties().Select(property => property.Name)),
            StringComparison.OrdinalIgnoreCase);
        var unassigned = Assert.Single(items, item => Property<Guid>(item, "Id") == unassignedTask.Id);
        Assert.Empty(Property<IEnumerable>(unassigned, "effectiveAssignees"));
        Assert.Equal(0, Property<int>(unassigned, "effectiveAssigneeCount"));
    }

    private static User NewUser(string firstName, string lastName, string email, string status = "active") => new()
    {
        Id = Guid.NewGuid(), FirstName = firstName, LastName = lastName, Email = email,
        PasswordHash = "test-hash", Status = status
    };

    private static OrganizationMember OrgMember(Guid organizationId, Guid userId, string role, string status = "active") => new()
    {
        Id = Guid.NewGuid(), OrganizationId = organizationId, UserId = userId, Role = role, Status = status
    };

    private static ProjectMember ProjectMember(Guid projectId, Guid userId, string status = "active") => new()
    {
        Id = Guid.NewGuid(), ProjectId = projectId, UserId = userId, Role = "CONTRIBUTOR", Status = status
    };

    private static TaskAssignee Assignment(Guid taskId, Guid userId, string status = "active") => new()
    {
        Id = Guid.NewGuid(), TaskId = taskId, UserId = userId, Status = status
    };

    private static T Property<T>(object source, string name) =>
        (T)source.GetType().GetProperty(name, BindingFlags.Public | BindingFlags.Instance | BindingFlags.IgnoreCase)!
            .GetValue(source)!;

    private sealed class TestDatabase : IAsyncDisposable
    {
        private TestDatabase(SqliteConnection connection, PmsDbContext context)
        {
            Connection = connection;
            Context = context;
        }

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

        public async ValueTask DisposeAsync()
        {
            await Context.DisposeAsync();
            await Connection.DisposeAsync();
        }
    }
}
