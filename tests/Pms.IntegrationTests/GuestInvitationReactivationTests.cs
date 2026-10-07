using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Pms.Api.Auth;
using Pms.Api.Controllers.Rest.V1;
using Pms.Api.Realtime;
using Pms.Domain.Entities;
using Pms.Infrastructure.Persistence.EfCore;

namespace Pms.IntegrationTests;

public sealed class GuestInvitationReactivationTests
{
    [Fact]
    public async Task AcceptGuestInvitation_ClampsElevatedReactivatedProjectRolesAndAuditsChanges()
    {
        await using var connection = new SqliteConnection("Data Source=:memory:");
        await connection.OpenAsync();
        var options = new DbContextOptionsBuilder<PmsDbContext>().UseSqlite(connection).Options;
        await using var db = new PmsDbContext(options);
        await db.Database.EnsureCreatedAsync();
        var userId = Guid.NewGuid(); var organizationId = Guid.NewGuid(); var projectId = Guid.NewGuid();
        var token = "invitation-token";
        var user = new User { Id = userId, FirstName = "Legacy", LastName = "Guest", Email = "guest@example.test", PasswordHash = "hash" };
        var organization = new Organization { Id = organizationId, Name = "Guest org", Slug = $"guest-{organizationId:N}" };
        var project = new Project { Id = projectId, OrganizationId = organizationId, OwnerId = userId, Name = "Guest project" };
        db.Users.Add(user);
        db.Organizations.Add(organization);
        db.Projects.Add(project);
        db.OrganizationMembers.Add(new OrganizationMember { Id = Guid.NewGuid(), OrganizationId = organizationId, UserId = userId, Role = "GUEST", Status = "inactive" });
        var elevated = new ProjectMember { Id = Guid.NewGuid(), ProjectId = projectId, UserId = userId, Role = "PROJECT_MANAGER", Status = "inactive" };
        db.ProjectMembers.Add(elevated);
        db.OrganizationInvitations.Add(new OrganizationInvitation
        {
            Id = Guid.NewGuid(), OrganizationId = organizationId, Email = user.Email, Role = "GUEST",
            TokenHash = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(token))),
            ExpiresAt = DateTime.UtcNow.AddDays(1)
        });
        await db.SaveChangesAsync();

        var tokens = new TokenService(Options.Create(new JwtOptions { Issuer = "issuer", Audience = "audience", SigningKey = "test-signing-key" }));
        var controller = new OrganizationsController(db, null!, tokens, new RealtimePublisher(new TestHubContext()));
        var http = new DefaultHttpContext
        {
            User = new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier, userId.ToString())], "test"))
        };
        http.TraceIdentifier = Guid.NewGuid().ToString();
        controller.ControllerContext = new ControllerContext { HttpContext = http };

        var result = await controller.Accept(new InvitationTokenRequest(token), CancellationToken.None);

        Assert.IsType<OkObjectResult>(result);
        Assert.Equal("VIEWER", (await db.ProjectMembers.SingleAsync()).Role);
        Assert.Equal("active", (await db.ProjectMembers.SingleAsync()).Status);
        var audit = await db.AdminAuditEvents.SingleAsync();
        Assert.Equal(userId, audit.ActorId);
        Assert.Equal(userId, audit.TargetId);
        Assert.Equal("project.member_guest_role_clamped", audit.Action);
        Assert.Contains($"project_id={projectId}", audit.Reason);
        Assert.Contains("old_role=PROJECT_MANAGER", audit.Reason);
        Assert.Contains("new_role=VIEWER", audit.Reason);
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
