using System.Reflection;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging.Abstractions;
using Pms.Api.Media;
using Pms.Domain.Entities;
using Pms.Infrastructure.Persistence.EfCore;

namespace Pms.IntegrationTests;

public sealed class DeletedContentPurgerHistoryTests
{
    [Fact]
    public async Task Purge_RemovesAssignmentHistoryWithExpiredTasksAndProjects()
    {
        var connectionString = $"Data Source=purge-history-{Guid.NewGuid():N};Mode=Memory;Cache=Shared";
        await using var keeper = new SqliteConnection(connectionString);
        await keeper.OpenAsync();
        var options = new DbContextOptionsBuilder<PmsDbContext>().UseSqlite(connectionString).Options;
        var orgId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var expiredProjectId = Guid.NewGuid();
        var activeProjectId = Guid.NewGuid();
        var expiredProjectTaskId = Guid.NewGuid();
        var expiredTaskId = Guid.NewGuid();
        await using (var seed = new PmsDbContext(options))
        {
            await seed.Database.EnsureCreatedAsync();
            seed.Organizations.Add(new Organization { Id = orgId, Name = "Org", Slug = $"purge-{orgId:N}" });
            seed.Users.Add(new User
            {
                Id = userId, FirstName = "Member", LastName = "Test", Email = $"{userId:N}@example.test", PasswordHash = "hash"
            });
            seed.Projects.AddRange(
                new Project { Id = expiredProjectId, OrganizationId = orgId, OwnerId = userId, Name = "Expired project", DeletedAt = DateTime.UtcNow.AddDays(-31) },
                new Project { Id = activeProjectId, OrganizationId = orgId, OwnerId = userId, Name = "Active project" });
            seed.Tasks.AddRange(
                new WorkTask { Id = expiredProjectTaskId, ProjectId = expiredProjectId, Title = "Project task", Status = "DONE", CreatedBy = userId },
                new WorkTask { Id = expiredTaskId, ProjectId = activeProjectId, Title = "Expired task", Status = "DONE", CreatedBy = userId, DeletedAt = DateTime.UtcNow.AddDays(-31) });
            seed.TaskAssignmentEvents.AddRange(
                History(orgId, expiredProjectId, expiredProjectTaskId, userId),
                History(orgId, activeProjectId, expiredTaskId, userId));
            await seed.SaveChangesAsync();
        }

        var services = new ServiceCollection();
        services.AddDbContext<PmsDbContext>(builder => builder.UseSqlite(connectionString));
        services.AddSingleton<ICloudinaryStorage, ConfiguredTestStorage>();
        await using var provider = services.BuildServiceProvider();
        var purger = new DeletedContentPurger(provider.GetRequiredService<IServiceScopeFactory>(),
            new ConfigurationBuilder().Build(), new TestHostEnvironment(), NullLogger<DeletedContentPurger>.Instance);
        var purge = typeof(DeletedContentPurger).GetMethod("PurgeExpiredAsync", BindingFlags.Instance | BindingFlags.NonPublic);
        Assert.NotNull(purge);
        await (Task)purge.Invoke(purger, [CancellationToken.None])!;

        await using var verify = new PmsDbContext(options);
        Assert.Empty(await verify.TaskAssignmentEvents.ToListAsync());
        Assert.Empty(await verify.Tasks.Where(task => task.Id == expiredProjectTaskId || task.Id == expiredTaskId).ToListAsync());
        Assert.DoesNotContain(await verify.Projects.ToListAsync(), project => project.Id == expiredProjectId);
        Assert.Contains(await verify.Projects.ToListAsync(), project => project.Id == activeProjectId);
    }

    private static TaskAssignmentEvent History(Guid organizationId, Guid projectId, Guid taskId, Guid userId) => new()
    {
        EventId = Guid.NewGuid(), OperationId = Guid.NewGuid(), OrganizationId = organizationId, ProjectId = projectId,
        TaskId = taskId, DepartingUserId = userId, ActorUserId = userId, OccurredAtUtc = DateTime.UtcNow, Action = "UNASSIGNED"
    };

    private sealed class ConfiguredTestStorage : ICloudinaryStorage
    {
        public bool IsConfigured => true;
        public Task<CloudinaryUpload> UploadAsync(Stream content, string fileName, string folder, string resourceType, CancellationToken cancellationToken) =>
            throw new NotSupportedException();
        public Task DeleteAsync(string publicId, string resourceType, CancellationToken cancellationToken) => Task.CompletedTask;
        public Task<byte[]> DownloadAsync(string secureUrl, CancellationToken cancellationToken) => throw new NotSupportedException();
    }

    private sealed class TestHostEnvironment : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = Environments.Development;
        public string ApplicationName { get; set; } = "Pms.IntegrationTests";
        public string ContentRootPath { get; set; } = Path.GetTempPath();
        public Microsoft.Extensions.FileProviders.IFileProvider ContentRootFileProvider { get; set; } =
            new Microsoft.Extensions.FileProviders.NullFileProvider();
    }
}
