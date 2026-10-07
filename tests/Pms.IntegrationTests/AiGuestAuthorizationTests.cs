using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Pms.Application.Ai;
using Pms.Api.Controllers.Rest.V1;
using Pms.Domain.Entities;
using Pms.Infrastructure.Persistence.EfCore;

namespace Pms.IntegrationTests;

public sealed class AiGuestAuthorizationTests
{
    [Fact]
    public async Task SuggestTask_RejectsLegacyElevatedOrganizationGuestBeforeCallingAi()
    {
        await using var db = new PmsDbContext(new DbContextOptionsBuilder<PmsDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        var userId = Guid.NewGuid();
        var organizationId = Guid.NewGuid();
        var projectId = Guid.NewGuid();
        db.Users.Add(new User
        {
            Id = userId,
            FirstName = "Guest",
            LastName = "Member",
            Email = $"{userId}@example.test",
            PasswordHash = "test-hash"
        });
        db.Organizations.Add(new Organization
        {
            Id = organizationId,
            Name = "Guest organization",
            Slug = $"guest-{userId:N}"
        });
        db.OrganizationMembers.Add(new OrganizationMember
        {
            Id = Guid.NewGuid(),
            OrganizationId = organizationId,
            UserId = userId,
            Role = "GUEST"
        });
        db.Projects.Add(new Project
        {
            Id = projectId,
            OrganizationId = organizationId,
            OwnerId = userId,
            Name = "Guest project"
        });
        db.ProjectMembers.Add(new ProjectMember
        {
            Id = Guid.NewGuid(),
            ProjectId = projectId,
            UserId = userId,
            Role = "CONTRIBUTOR"
        });
        await db.SaveChangesAsync();

        var ai = new RecordingAiTaskService();
        var controller = new AiController(db, ai)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new Microsoft.AspNetCore.Http.DefaultHttpContext
                {
                    User = new ClaimsPrincipal(new ClaimsIdentity(
                        [new Claim(ClaimTypes.NameIdentifier, userId.ToString())], "test"))
                }
            }
        };

        var result = await controller.SuggestTask(
            new AiTaskSuggestionInput(projectId, "Draft a report"), CancellationToken.None);

        Assert.IsType<ForbidResult>(result);
        Assert.False(ai.WasCalled);
    }

    private sealed class RecordingAiTaskService : IAiTaskService
    {
        public bool WasCalled { get; private set; }

        public Task<AiTaskSuggestion> SuggestTaskAsync(
            AiTaskSuggestionRequest request,
            CancellationToken cancellationToken)
        {
            WasCalled = true;
            return Task.FromResult(new AiTaskSuggestion("Draft", "Description", "MEDIUM", []));
        }
    }
}
