using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Pms.Api.Auth;
using Pms.Api.Controllers.Rest.V1;
using Pms.Api.MemberReactivation;
using Pms.Api.Realtime;
using Pms.Domain.Entities;
using Pms.Infrastructure.Persistence.EfCore;

namespace Pms.IntegrationTests;

public sealed class OrganizationMemberReactivationTests
{
    private sealed record TestContext(
        PmsDbContext Db,
        OrganizationsController Controller,
        Guid OrganizationId,
        Guid OwnerId,
        Guid AdminId,
        Guid DeactivatedMemberId,
        Guid SuspendedMemberId,
        Guid ProjectId1,
        Guid ProjectId2
    );

    private static async Task<TestContext> CreateContextAsync()
    {
        var connection = new SqliteConnection("Data Source=:memory:");
        await connection.OpenAsync();
        var options = new DbContextOptionsBuilder<PmsDbContext>().UseSqlite(connection).Options;
        var db = new PmsDbContext(options);
        await db.Database.EnsureCreatedAsync();

        var orgId = Guid.NewGuid();
        var ownerId = Guid.NewGuid();
        var adminId = Guid.NewGuid();
        var deactivatedId = Guid.NewGuid();
        var suspendedId = Guid.NewGuid();
        var proj1Id = Guid.NewGuid();
        var proj2Id = Guid.NewGuid();

        db.Organizations.Add(new Organization { Id = orgId, Name = "Test Org", Slug = $"org-{orgId:N}" });

        db.Users.AddRange(
            new User { Id = ownerId, FirstName = "Owner", LastName = "User", Email = "owner@test.com", PasswordHash = "h", Status = "active" },
            new User { Id = adminId, FirstName = "Admin", LastName = "User", Email = "admin@test.com", PasswordHash = "h", Status = "active" },
            new User { Id = deactivatedId, FirstName = "Jane", LastName = "Doe", Email = "jane@test.com", PasswordHash = "h", Status = "active" },
            new User { Id = suspendedId, FirstName = "Suspended", LastName = "User", Email = "suspended@test.com", PasswordHash = "h", Status = "suspended" }
        );

        db.OrganizationMembers.AddRange(
            new OrganizationMember { Id = Guid.NewGuid(), OrganizationId = orgId, UserId = ownerId, Role = "OWNER", Status = "active" },
            new OrganizationMember { Id = Guid.NewGuid(), OrganizationId = orgId, UserId = adminId, Role = "ADMIN", Status = "active" },
            new OrganizationMember { Id = Guid.NewGuid(), OrganizationId = orgId, UserId = deactivatedId, Role = "MEMBER", Status = "inactive" },
            new OrganizationMember { Id = Guid.NewGuid(), OrganizationId = orgId, UserId = suspendedId, Role = "MEMBER", Status = "inactive" }
        );

        db.Projects.AddRange(
            new Project { Id = proj1Id, OrganizationId = orgId, OwnerId = ownerId, Name = "Project Alpha", Status = "ACTIVE" },
            new Project { Id = proj2Id, OrganizationId = orgId, OwnerId = ownerId, Name = "Project Beta", Status = "ACTIVE" }
        );

        db.ProjectMembers.AddRange(
            new ProjectMember { Id = Guid.NewGuid(), ProjectId = proj1Id, UserId = adminId, Role = "PROJECT_MANAGER", Status = "active" },
            // In project 2, admin is only a contributor (not a manager)
            new ProjectMember { Id = Guid.NewGuid(), ProjectId = proj2Id, UserId = adminId, Role = "CONTRIBUTOR", Status = "active" },
            // Target was previously PROJECT_MANAGER in Project 1
            new ProjectMember { Id = Guid.NewGuid(), ProjectId = proj1Id, UserId = deactivatedId, Role = "PROJECT_MANAGER", Status = "inactive" }
        );

        await db.SaveChangesAsync();

        var tokens = new TokenService(Options.Create(new JwtOptions { Issuer = "issuer", Audience = "audience", SigningKey = "test-signing-key" }));
        var controller = new OrganizationsController(db, null!, tokens, new RealtimePublisher(new TestHubContext()));

        return new TestContext(db, controller, orgId, ownerId, adminId, deactivatedId, suspendedId, proj1Id, proj2Id);
    }

    private static void SetActor(OrganizationsController controller, Guid actorId)
    {
        var http = new DefaultHttpContext
        {
            User = new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier, actorId.ToString())], "test"))
        };
        http.TraceIdentifier = Guid.NewGuid().ToString("N");
        controller.ControllerContext = new ControllerContext { HttpContext = http };
    }

    [Fact]
    public async Task GetDeactivatedMembers_ReturnsOnlyInactiveMembers()
    {
        var ctx = await CreateContextAsync();
        SetActor(ctx.Controller, ctx.AdminId);

        var result = await ctx.Controller.DeactivatedMembers(ctx.OrganizationId, CancellationToken.None);

        var ok = Assert.IsType<OkObjectResult>(result);
        var members = Assert.IsAssignableFrom<IEnumerable<DeactivatedMemberSummaryDto>>(ok.Value);
        var list = members.ToList();
        Assert.Equal(2, list.Count);
        Assert.Contains(list, m => m.UserId == ctx.DeactivatedMemberId && m.Email == "jane@test.com");
        Assert.Contains(list, m => m.UserId == ctx.SuspendedMemberId && m.Email == "suspended@test.com");
    }

    [Fact]
    public async Task Preview_GeneratesMemberSpecificSnapshotAndRestrictsAdminProjectAuthority()
    {
        var ctx = await CreateContextAsync();
        SetActor(ctx.Controller, ctx.AdminId);

        var result = await ctx.Controller.PreviewMemberReactivation(ctx.OrganizationId, ctx.DeactivatedMemberId, CancellationToken.None);

        var ok = Assert.IsType<OkObjectResult>(result);
        var preview = Assert.IsType<MemberReactivationPreview>(ok.Value);
        Assert.Equal(ctx.DeactivatedMemberId, preview.UserId);
        Assert.Equal("MEMBER", preview.AllowedMaxRole); // Admin cannot grant Admin
        Assert.NotEmpty(preview.SnapshotHash);

        var p1 = preview.EligibleProjects.Single(p => p.ProjectId == ctx.ProjectId1);
        Assert.True(p1.ActorCanRestoreProject); // Admin is manager of Project 1
        Assert.Equal("PROJECT_MANAGER", p1.PreviousProjectRole);

        var p2 = preview.EligibleProjects.Single(p => p.ProjectId == ctx.ProjectId2);
        Assert.False(p2.ActorCanRestoreProject); // Admin is NOT manager of Project 2
    }

    [Fact]
    public async Task Reactivate_OwnerDirectReactivation_RestoresSelectedProjectsAsContributorNotManager()
    {
        var ctx = await CreateContextAsync();
        SetActor(ctx.Controller, ctx.OwnerId);

        var previewResult = await ctx.Controller.PreviewMemberReactivation(ctx.OrganizationId, ctx.DeactivatedMemberId, CancellationToken.None);
        var preview = (MemberReactivationPreview)((OkObjectResult)previewResult).Value!;

        var request = new ReactivateMemberRequest(
            Role: "MEMBER",
            ProjectIds: [ctx.ProjectId1],
            SnapshotHash: preview.SnapshotHash,
            Reason: "Employee returning to duty"
        );

        var result = await ctx.Controller.ReactivateMember(ctx.OrganizationId, ctx.DeactivatedMemberId, request, CancellationToken.None);

        Assert.IsType<NoContentResult>(result);

        // Verify organization membership status
        var orgMember = await ctx.Db.OrganizationMembers.SingleAsync(m => m.UserId == ctx.DeactivatedMemberId);
        Assert.Equal("active", orgMember.Status);
        Assert.Equal("MEMBER", orgMember.Role);

        // Verify project membership was defaulted to CONTRIBUTOR, NOT previous PROJECT_MANAGER
        var projMember = await ctx.Db.ProjectMembers.SingleAsync(pm => pm.ProjectId == ctx.ProjectId1 && pm.UserId == ctx.DeactivatedMemberId);
        Assert.Equal("active", projMember.Status);
        Assert.Equal("CONTRIBUTOR", projMember.Role);

        // Verify audit event
        var audit = await ctx.Db.AdminAuditEvents.SingleAsync(a => a.Action == "organization.member_reactivated");
        Assert.Equal(ctx.OwnerId, audit.ActorId);
        Assert.Equal(ctx.DeactivatedMemberId, audit.TargetId);
        Assert.Contains("restored_projects=1", audit.Reason);
    }

    [Fact]
    public async Task Reactivate_AdminRestoringUnauthorizedProject_FailsWith403()
    {
        var ctx = await CreateContextAsync();
        SetActor(ctx.Controller, ctx.AdminId);

        var previewResult = await ctx.Controller.PreviewMemberReactivation(ctx.OrganizationId, ctx.DeactivatedMemberId, CancellationToken.None);
        var preview = (MemberReactivationPreview)((OkObjectResult)previewResult).Value!;

        // Admin attempts to restore Project 2, where they are only a Contributor
        var request = new ReactivateMemberRequest(
            Role: "MEMBER",
            ProjectIds: [ctx.ProjectId2],
            SnapshotHash: preview.SnapshotHash,
            Reason: "Attempted unauthorized project restore"
        );

        var result = await ctx.Controller.ReactivateMember(ctx.OrganizationId, ctx.DeactivatedMemberId, request, CancellationToken.None);

        var statusResult = Assert.IsType<ObjectResult>(result);
        Assert.Equal(StatusCodes.Status403Forbidden, statusResult.StatusCode);
    }

    [Fact]
    public async Task Reactivate_AdminEscalatingToAdminRole_FailsWith403()
    {
        var ctx = await CreateContextAsync();
        SetActor(ctx.Controller, ctx.AdminId);

        var previewResult = await ctx.Controller.PreviewMemberReactivation(ctx.OrganizationId, ctx.DeactivatedMemberId, CancellationToken.None);
        var preview = (MemberReactivationPreview)((OkObjectResult)previewResult).Value!;

        var request = new ReactivateMemberRequest(
            Role: "ADMIN",
            ProjectIds: [ctx.ProjectId1],
            SnapshotHash: preview.SnapshotHash,
            Reason: "Attempted admin escalation"
        );

        var result = await ctx.Controller.ReactivateMember(ctx.OrganizationId, ctx.DeactivatedMemberId, request, CancellationToken.None);

        var statusResult = Assert.IsType<ObjectResult>(result);
        Assert.Equal(StatusCodes.Status403Forbidden, statusResult.StatusCode);
    }

    [Fact]
    public async Task Reactivate_SuspendedUser_FailsWith403()
    {
        var ctx = await CreateContextAsync();
        SetActor(ctx.Controller, ctx.OwnerId);

        var previewResult = await ctx.Controller.PreviewMemberReactivation(ctx.OrganizationId, ctx.SuspendedMemberId, CancellationToken.None);
        var statusResult = Assert.IsType<ObjectResult>(previewResult);
        Assert.Equal(StatusCodes.Status403Forbidden, statusResult.StatusCode);
    }

    [Fact]
    public async Task Reactivate_StaleSnapshotHash_FailsWith409()
    {
        var ctx = await CreateContextAsync();
        SetActor(ctx.Controller, ctx.OwnerId);

        var request = new ReactivateMemberRequest(
            Role: "MEMBER",
            ProjectIds: [ctx.ProjectId1],
            SnapshotHash: "invalid_stale_hash",
            Reason: "Concurrency test"
        );

        var result = await ctx.Controller.ReactivateMember(ctx.OrganizationId, ctx.DeactivatedMemberId, request, CancellationToken.None);

        var statusResult = Assert.IsType<ObjectResult>(result);
        Assert.Equal(StatusCodes.Status409Conflict, statusResult.StatusCode);
    }

    [Fact]
    public async Task Reactivate_GuestRole_ClampsProjectRoleToViewer()
    {
        var ctx = await CreateContextAsync();
        SetActor(ctx.Controller, ctx.OwnerId);

        var previewResult = await ctx.Controller.PreviewMemberReactivation(ctx.OrganizationId, ctx.DeactivatedMemberId, CancellationToken.None);
        var preview = (MemberReactivationPreview)((OkObjectResult)previewResult).Value!;

        var request = new ReactivateMemberRequest(
            Role: "GUEST",
            ProjectIds: [ctx.ProjectId1],
            SnapshotHash: preview.SnapshotHash,
            Reason: "Reactivated as guest"
        );

        var result = await ctx.Controller.ReactivateMember(ctx.OrganizationId, ctx.DeactivatedMemberId, request, CancellationToken.None);

        Assert.IsType<NoContentResult>(result);
        var projMember = await ctx.Db.ProjectMembers.SingleAsync(pm => pm.ProjectId == ctx.ProjectId1 && pm.UserId == ctx.DeactivatedMemberId);
        Assert.Equal("VIEWER", projMember.Role);
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

