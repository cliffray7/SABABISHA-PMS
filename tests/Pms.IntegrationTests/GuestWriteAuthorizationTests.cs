using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Pms.Api.Auth;
using Pms.Api.Controllers.Rest.V1;
using Pms.Api.Media;
using Pms.Api.Realtime;
using Pms.Domain.Entities;
using Pms.Infrastructure.Persistence.EfCore;

namespace Pms.IntegrationTests;

public sealed class GuestWriteAuthorizationTests
{
    [Theory]
    [InlineData("VIEWER")]
    [InlineData("CONTRIBUTOR")]
    [InlineData("TEAM_LEAD")]
    [InlineData("PROJECT_MANAGER")]
    public async Task GuestTaskWrites_AreDeniedForViewerAndLegacyElevatedProjectRoles(string projectRole)
    {
        await using var db = CreateDb();
        var fixture = Seed(db, "GUEST", projectRole);
        var controller = new TasksController(db, null!, null!) { ControllerContext = Context(fixture.UserId) };
        Assert.IsType<OkObjectResult>(await controller.List(fixture.ProjectId, default));

        if (projectRole == "VIEWER")
        {
            var create = await controller.Create(fixture.ProjectId,
                new CreateTaskRequest("new task", null, null, null, null, Array.Empty<Guid>()), default);
            Assert.IsType<ForbidResult>(create);
            var update = await controller.Update(fixture.TaskId,
                new UpdateTaskRequest("changed", null, null, null, null), default);
            Assert.IsType<ForbidResult>(update);
            var assign = await controller.Update(fixture.TaskId,
                new UpdateTaskRequest(null, null, null, null, null, new[] { fixture.UserId }), default);
            Assert.IsType<ForbidResult>(assign);
            var trash = await controller.Delete(fixture.TaskId, default);
            Assert.IsType<ForbidResult>(trash);
            var subtask = await controller.CreateSubtask(fixture.TaskId, new SubtaskRequest("child"), default);
            Assert.IsType<ForbidResult>(subtask);
            Assert.Empty(await db.Tasks.Where(x => x.ParentTaskId == fixture.TaskId).ToListAsync());
            Assert.Equal("original", (await db.Tasks.SingleAsync(x => x.Id == fixture.TaskId)).Title);
            return;
        }

        // Existing/reactivated legacy membership rows can carry write-capable project roles.
        // These actions should be denied before persistence, but current checks only reject VIEWER.
        await AssertDeniedOrUnchanged(async () => await controller.Create(fixture.ProjectId,
            new CreateTaskRequest("new task", null, null, null, null, Array.Empty<Guid>()), default), db);
        await AssertDeniedOrUnchanged(async () => await controller.Update(fixture.TaskId,
            new UpdateTaskRequest("changed", null, null, null, null), default), db);
        await AssertDeniedOrUnchanged(async () => await controller.Update(fixture.TaskId,
            new UpdateTaskRequest(null, null, null, null, null, new[] { fixture.UserId }), default), db);
        await AssertDeniedOrUnchanged(async () => await controller.Delete(fixture.TaskId, default), db);
        await AssertDeniedOrUnchanged(async () => await controller.CreateSubtask(fixture.TaskId,
            new SubtaskRequest("child"), default), db);
    }

    [Theory]
    [InlineData("VIEWER")]
    [InlineData("CONTRIBUTOR")]
    [InlineData("TEAM_LEAD")]
    [InlineData("PROJECT_MANAGER")]
    public async Task GuestCollaborationWrites_AreDeniedForViewerAndLegacyElevatedProjectRoles(string projectRole)
    {
        await using var db = CreateDb();
        var fixture = Seed(db, "GUEST", projectRole);
        var controller = CreateCollaboration(db);
        controller.ControllerContext = Context(fixture.UserId);
        Assert.IsType<OkObjectResult>(await controller.Comments(fixture.TaskId, default));
        Assert.IsType<OkObjectResult>(await controller.Attachments(fixture.TaskId, default));

        var commentResult = await controller.Comment(fixture.TaskId,
            new CommentRequest("guest write", Array.Empty<Guid>(), null), default);
        Assert.IsType<NotFoundResult>(commentResult);
        Assert.Equal(2, await db.Comments.CountAsync());

        Assert.IsType<NotFoundResult>(await controller.DeleteComment(fixture.TaskId, fixture.CommentId, default));
        Assert.IsType<NotFoundResult>(await controller.RestoreComment(fixture.TaskId, fixture.DeletedCommentId, default));
        Assert.Null((await db.Comments.SingleAsync(x => x.Id == fixture.CommentId)).DeletedAt);
        Assert.NotNull((await db.Comments.SingleAsync(x => x.Id == fixture.DeletedCommentId)).DeletedAt);

        var uploadResult = await controller.Upload(fixture.TaskId,
            new FormFile(new MemoryStream([1]), 0, 1, "file", "file.txt"), default);
        Assert.IsType<NotFoundResult>(uploadResult);
        Assert.IsType<NotFoundResult>(await controller.DeleteAttachment(fixture.AttachmentId, default));
        Assert.IsType<NotFoundResult>(await controller.RestoreAttachment(fixture.DeletedAttachmentId, default));
        Assert.Null((await db.Attachments.SingleAsync(x => x.Id == fixture.AttachmentId)).DeletedAt);
        Assert.NotNull((await db.Attachments.SingleAsync(x => x.Id == fixture.DeletedAttachmentId)).DeletedAt);
    }

    private static async Task AssertDeniedOrUnchanged(Func<Task<IActionResult>> action, PmsDbContext db)
    {
        var beforeTasks = await db.Tasks.CountAsync();
        var beforeComments = await db.Comments.CountAsync();
        IActionResult result;
        try { result = await action(); }
        catch (NullReferenceException) { result = new StatusCodeResult(599); }
        Assert.True(result is ForbidResult or NotFoundResult,
            $"Expected guest write denial, got {result.GetType().Name}.");
        Assert.Equal(beforeTasks, await db.Tasks.CountAsync());
        Assert.Equal(beforeComments, await db.Comments.CountAsync());
    }

    private static PmsDbContext CreateDb() => new(new DbContextOptionsBuilder<PmsDbContext>()
        .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);

    private static (Guid UserId, Guid ProjectId, Guid TaskId, Guid CommentId, Guid DeletedCommentId, Guid AttachmentId, Guid DeletedAttachmentId) Seed(PmsDbContext db, string orgRole, string projectRole)
    {
        var userId = Guid.NewGuid(); var orgId = Guid.NewGuid(); var projectId = Guid.NewGuid(); var taskId = Guid.NewGuid();
        var commentId = Guid.NewGuid(); var deletedCommentId = Guid.NewGuid(); var attachmentId = Guid.NewGuid(); var deletedAttachmentId = Guid.NewGuid();
        db.Users.Add(new User { Id = userId, FirstName = "Guest", LastName = "User", Email = $"{userId}@example.test", PasswordHash = "hash" });
        db.Organizations.Add(new Organization { Id = orgId, Name = "Org", Slug = $"org-{userId:N}" });
        db.OrganizationMembers.Add(new OrganizationMember { Id = Guid.NewGuid(), OrganizationId = orgId, UserId = userId, Role = orgRole });
        db.Projects.Add(new Project { Id = projectId, OrganizationId = orgId, OwnerId = userId, Name = "Project" });
        db.ProjectMembers.Add(new ProjectMember { Id = Guid.NewGuid(), ProjectId = projectId, UserId = userId, Role = projectRole });
        db.Tasks.Add(new WorkTask { Id = taskId, ProjectId = projectId, Title = "original", Status = "TO DO", CreatedBy = userId });
        db.Comments.Add(new Comment { Id = commentId, TaskId = taskId, UserId = userId, Content = "existing" });
        db.Comments.Add(new Comment { Id = deletedCommentId, TaskId = taskId, UserId = userId, Content = "deleted", DeletedAt = DateTime.UtcNow });
        db.Attachments.Add(new Attachment { Id = attachmentId, TaskId = taskId, UploadedBy = userId, FileName = "existing.txt", FileUrl = "https://example.test/file", FileSize = 1 });
        db.Attachments.Add(new Attachment { Id = deletedAttachmentId, TaskId = taskId, UploadedBy = userId, FileName = "deleted.txt", FileUrl = "https://example.test/deleted", FileSize = 1, DeletedAt = DateTime.UtcNow });
        db.SaveChanges();
        return (userId, projectId, taskId, commentId, deletedCommentId, attachmentId, deletedAttachmentId);
    }

    private static ControllerContext Context(Guid userId)
    {
        var http = new DefaultHttpContext();
        http.User = new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier, userId.ToString())], "test"));
        http.TraceIdentifier = Guid.NewGuid().ToString();
        return new ControllerContext { HttpContext = http };
    }

    private static CollaborationController CreateCollaboration(PmsDbContext db)
    {
        var media = new TestStorage();
        return new CollaborationController(db, new TestEnvironment(), new ConfigurationBuilder().Build(), media,
            NullLogger<CollaborationController>.Instance, null!);
    }

    private sealed class TestStorage : ICloudinaryStorage
    {
        public bool IsConfigured => false;
        public Task<CloudinaryUpload> UploadAsync(Stream content, string fileName, string folder, string resourceType, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task DeleteAsync(string publicId, string resourceType, CancellationToken cancellationToken) => throw new NotSupportedException();
        public Task<byte[]> DownloadAsync(string secureUrl, CancellationToken cancellationToken) => throw new NotSupportedException();
    }

    private sealed class TestEnvironment : Microsoft.AspNetCore.Hosting.IWebHostEnvironment
    {
        public string ApplicationName { get; set; } = "Tests";
        public Microsoft.Extensions.FileProviders.IFileProvider WebRootFileProvider { get; set; } = new Microsoft.Extensions.FileProviders.NullFileProvider();
        public string WebRootPath { get; set; } = "";
        public string EnvironmentName { get; set; } = "Testing";
        public string ContentRootPath { get; set; } = "";
        public Microsoft.Extensions.FileProviders.IFileProvider ContentRootFileProvider { get; set; } = new Microsoft.Extensions.FileProviders.NullFileProvider();
    }
}
