using System.Collections;
using System.Reflection;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Pms.Api.Controllers.Rest.V1;
using Pms.Domain.Entities;
using Pms.Infrastructure.Persistence.EfCore;

namespace Pms.IntegrationTests;

public sealed class AdminActivityExplorerTests
{
    [Fact]
    public async Task SuperAdminCanFilterPlatformWideActivityByOrganizationAndProjectWithoutMembership()
    {
        await using var database = await TestDatabase.Create();
        var ownerId = Guid.NewGuid();
        var organizationOne = NewOrganization("Explorer Org One");
        var organizationTwo = NewOrganization("Explorer Org Two");
        var projectOne = NewProject(organizationOne.Id, ownerId, "Explorer Project One");
        var projectTwo = NewProject(organizationTwo.Id, ownerId, "Explorer Project Two");
        var trashedProject = NewProject(organizationOne.Id, ownerId, "Explorer Trashed Project");
        trashedProject.DeletedAt = DateTime.UtcNow.AddDays(-2);
        database.Context.Users.Add(new User
        {
            Id = ownerId, FirstName = "Project", LastName = "Owner", Email = "owner@example.test",
            PasswordHash = "hash", Status = "active"
        });
        database.Context.Organizations.AddRange(organizationOne, organizationTwo);
        database.Context.Projects.AddRange(projectOne, projectTwo, trashedProject);
        database.Context.ActivityEvents.AddRange(NewEvent(organizationOne.Id, projectOne.Id, "Project one event"),
            NewEvent(organizationTwo.Id, projectTwo.Id, "Project two event"));
        await database.Context.SaveChangesAsync();

        var controller = CreateController(database.Context);
        var result = await controller.GetActivityEvents(organizationOne.Id, projectOne.Id, null, null,
            null, null, null, 50, default);

        var ok = Assert.IsType<OkObjectResult>(result);
        var responseItems = Property<IEnumerable>(ok.Value!, "items").Cast<object>().ToArray();
        Assert.Single(responseItems);
        Assert.Equal(projectOne.Id, Property<Guid?>(responseItems[0], "ProjectId"));
        Assert.Equal(organizationOne.Id, Property<Guid?>(responseItems[0], "OrganizationId"));

        var projectOnlyResult = await controller.GetActivityEvents(null, projectTwo.Id, null, null,
            null, null, null, 50, default);
        var projectOnlyItems = Property<IEnumerable>(Assert.IsType<OkObjectResult>(projectOnlyResult).Value!, "items")
            .Cast<object>().ToArray();
        Assert.Single(projectOnlyItems);
        Assert.Equal(projectTwo.Id, Property<Guid?>(projectOnlyItems[0], "ProjectId"));

        var projectsResult = await controller.GetProjects(organizationOne.Id, true, default);
        var projects = Assert.IsAssignableFrom<IEnumerable>(Assert.IsType<OkObjectResult>(projectsResult).Value)
            .Cast<object>().ToArray();
        Assert.Equal(2, projects.Length);
        Assert.Contains(projects, project => Property<Guid>(project, "Id") == projectOne.Id);
        Assert.Contains(projects, project => Property<Guid>(project, "Id") == trashedProject.Id);

        var activeProjectsResult = await controller.GetProjects(organizationOne.Id, false, default);
        var activeProjects = Assert.IsAssignableFrom<IEnumerable>(Assert.IsType<OkObjectResult>(activeProjectsResult).Value)
            .Cast<object>().ToArray();
        Assert.Single(activeProjects);

        var defaultsResult = await controller.GetProjects(null, false, default);
        var defaultProjects = Assert.IsAssignableFrom<IEnumerable>(Assert.IsType<OkObjectResult>(defaultsResult).Value)
            .Cast<object>().ToArray();
        Assert.Equal(2, defaultProjects.Length);

        var allProjectsResult = await controller.GetProjects(null, true, default);
        var allProjects = Assert.IsAssignableFrom<IEnumerable>(Assert.IsType<OkObjectResult>(allProjectsResult).Value)
            .Cast<object>().ToArray();
        Assert.Equal(3, allProjects.Length);

        var mismatch = await controller.GetActivityEvents(organizationTwo.Id, projectOne.Id, null, null,
            null, null, null, 50, default);
        var notFound = Assert.IsType<NotFoundObjectResult>(mismatch);
        Assert.Equal("PROJECT_NOT_FOUND", Property<string>(notFound.Value!, "Code"));
    }

    [Fact]
    public void ActivityExplorerEndpointRemainsProtectedBySuperAdminPolicy()
    {
        var authorization = typeof(AdminController).GetCustomAttribute<AuthorizeAttribute>();
        Assert.Equal("SuperAdmin", authorization?.Policy);
    }

    private static AdminController CreateController(PmsDbContext db)
    {
        var controller = new AdminController(db);
        controller.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext
            {
                User = new ClaimsPrincipal(new ClaimsIdentity([], "test"))
            }
        };
        return controller;
    }

    private static Organization NewOrganization(string name) => new()
    {
        Id = Guid.NewGuid(), Name = name, Slug = name.Replace(' ', '-').ToLowerInvariant(), Timezone = "UTC"
    };

    private static Project NewProject(Guid organizationId, Guid ownerId, string name) => new()
    {
        Id = Guid.NewGuid(), OrganizationId = organizationId, OwnerId = ownerId, Name = name, Status = "ACTIVE"
    };

    private static ActivityEvent NewEvent(Guid organizationId, Guid projectId, string name) => new()
    {
        Id = Guid.NewGuid(), OrganizationId = organizationId, ProjectId = projectId, ActorUserId = null,
        ActorName = "Workspace member", Category = "Projects", Action = "project.updated",
        EntityType = "project", EntityId = projectId, EntityName = name, Description = name,
        Status = "succeeded", CorrelationId = Guid.NewGuid().ToString("N"), CreatedAtUtc = DateTime.UtcNow
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
