using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Pms.Api.MemberRemoval;
using Pms.Domain.Entities;
using Pms.Infrastructure.Persistence.EfCore;

namespace Pms.IntegrationTests;

public sealed class MemberRemovalSnapshotTests
{
    [Fact]
    public async Task PreviewSeparatesOpenResolutionsFromClosedAndTrashedHistoricalAssignments()
    {
        await using var connection = new SqliteConnection("Data Source=:memory:");
        await connection.OpenAsync();
        var options = new DbContextOptionsBuilder<PmsDbContext>().UseSqlite(connection).Options;
        await using var db = new PmsDbContext(options);
        await db.Database.EnsureCreatedAsync();
        var fixture = await SeedAsync(db);

        var state = await MemberRemovalResolutionSupport.LoadStateAsync(db, fixture.OrganizationId,
            fixture.TargetId, fixture.ActorId, null, DateTime.UtcNow, acquireLocks: true, CancellationToken.None);
        var preview = state.ToPreview(null);

        Assert.Equal(2, preview.AffectedTaskCount);
        var project = Assert.Single(preview.AffectedProjects);
        Assert.Single(project.Tasks);
        Assert.Equal("REASSIGN_OR_UNASSIGN", Assert.Single(project.Tasks).RequiredResolution);
        var historical = Assert.Single(project.HistoricalAttributionsToInactivate);
        Assert.True(historical.TaskInTrash);
        Assert.Equal("UNASSIGNED", historical.ActionOnConfirm);
        Assert.Single(state.AffectedTasks);
        Assert.Single(state.HistoricalAssignmentsToInactivate);
    }

    [Fact]
    public async Task SnapshotHashChangesWhenTargetAssignmentSetChanges()
    {
        await using var connection = new SqliteConnection("Data Source=:memory:");
        await connection.OpenAsync();
        var options = new DbContextOptionsBuilder<PmsDbContext>().UseSqlite(connection).Options;
        await using var db = new PmsDbContext(options);
        await db.Database.EnsureCreatedAsync();
        var fixture = await SeedAsync(db);

        var before = await MemberRemovalResolutionSupport.LoadStateAsync(db, fixture.OrganizationId,
            fixture.TargetId, fixture.ActorId, null, DateTime.UtcNow, acquireLocks: false, CancellationToken.None);
        var originalHash = before.ToPreview(null).SnapshotHash;
        var newTaskId = Guid.NewGuid();
        db.Tasks.Add(new WorkTask { Id = newTaskId, ProjectId = fixture.ProjectId, Title = "New task", Status = "TODO", CreatedBy = fixture.ActorId });
        db.TaskAssignees.Add(new TaskAssignee { Id = Guid.NewGuid(), TaskId = newTaskId, UserId = fixture.TargetId });
        await db.SaveChangesAsync();

        var after = await MemberRemovalResolutionSupport.LoadStateAsync(db, fixture.OrganizationId,
            fixture.TargetId, fixture.ActorId, null, DateTime.UtcNow, acquireLocks: false, CancellationToken.None);
        Assert.NotEqual(originalHash, after.ToPreview(null).SnapshotHash);
    }

    private static async Task<Fixture> SeedAsync(PmsDbContext db)
    {
        var orgId = Guid.NewGuid();
        var projectId = Guid.NewGuid();
        var actorId = Guid.NewGuid();
        var targetId = Guid.NewGuid();
        db.Organizations.Add(new Organization { Id = orgId, Name = "Org", Slug = $"org-{orgId:N}" });
        db.Users.AddRange(User(actorId), User(targetId));
        db.Projects.Add(new Project { Id = projectId, OrganizationId = orgId, OwnerId = actorId, Name = "Project" });
        db.OrganizationMembers.AddRange(
            new OrganizationMember { Id = Guid.NewGuid(), OrganizationId = orgId, UserId = actorId, Role = "ADMIN" },
            new OrganizationMember { Id = Guid.NewGuid(), OrganizationId = orgId, UserId = targetId, Role = "MEMBER" });
        db.ProjectMembers.AddRange(
            new ProjectMember { Id = Guid.NewGuid(), ProjectId = projectId, UserId = actorId, Role = "PROJECT_MANAGER" },
            new ProjectMember { Id = Guid.NewGuid(), ProjectId = projectId, UserId = targetId, Role = "CONTRIBUTOR" });
        var openTaskId = Guid.NewGuid();
        var trashedTaskId = Guid.NewGuid();
        db.Tasks.AddRange(
            new WorkTask { Id = openTaskId, ProjectId = projectId, Title = "Open", Status = "TODO", CreatedBy = actorId },
            new WorkTask { Id = trashedTaskId, ProjectId = projectId, Title = "Trashed", Status = "TODO", CreatedBy = actorId, DeletedAt = DateTime.UtcNow });
        db.TaskAssignees.AddRange(
            new TaskAssignee { Id = Guid.NewGuid(), TaskId = openTaskId, UserId = targetId },
            new TaskAssignee { Id = Guid.NewGuid(), TaskId = trashedTaskId, UserId = targetId });
        await db.SaveChangesAsync();
        return new Fixture(orgId, projectId, actorId, targetId);
    }

    private static User User(Guid id) => new()
    {
        Id = id, FirstName = "Test", LastName = "Member", Email = $"{id:N}@example.test", PasswordHash = "hash"
    };

    private sealed record Fixture(Guid OrganizationId, Guid ProjectId, Guid ActorId, Guid TargetId);
}
