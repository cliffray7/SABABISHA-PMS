using System.ComponentModel.DataAnnotations;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Pms.Api.Auth;
using Pms.Application.Ai;
using Pms.Infrastructure.Persistence.EfCore;

namespace Pms.Api.Controllers.Rest.V1;

[ApiController, Authorize, Route("api/v1/ai")]
public sealed class AiController(PmsDbContext db, IAiTaskService tasks) : ControllerBase
{
    [HttpPost("tasks/suggest")]
    public async Task<IActionResult> SuggestTask(AiTaskSuggestionInput input, CancellationToken cancellationToken)
    {
        if (!await WorkspaceAuthorization.CanAccessProjectAsync(
                db, input.ProjectId, CurrentUser.Id(User), write: true, cancellationToken)) return Forbid();
        var project = await db.Projects.AsNoTracking()
            .SingleOrDefaultAsync(candidate => candidate.Id == input.ProjectId
                && candidate.ArchivedAt == null && candidate.DeletedAt == null, cancellationToken);
        if (project is null) return Forbid();

        var titles = await db.Tasks.AsNoTracking().Where(task => task.ProjectId == project.Id && task.DeletedAt == null)
            .OrderByDescending(task => task.UpdatedAt).Select(task => task.Title).Take(30).ToListAsync(cancellationToken);
        try
        {
            return Ok(await tasks.SuggestTaskAsync(new AiTaskSuggestionRequest(project.Name, input.Prompt.Trim(), titles), cancellationToken));
        }
        catch (AiUnavailableException exception)
        {
            return StatusCode(StatusCodes.Status503ServiceUnavailable, new { message = exception.Message });
        }
    }
}

public sealed record AiTaskSuggestionInput([Required] Guid ProjectId, [Required, StringLength(2000, MinimumLength = 3)] string Prompt);
