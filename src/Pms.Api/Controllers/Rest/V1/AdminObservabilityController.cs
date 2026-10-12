using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Pms.Api.Observability;

namespace Pms.Api.Controllers.Rest.V1;

[ApiController]
[Route("api/v1/admin/observability")]
[Authorize(Policy = "SuperAdmin")]
public sealed class AdminObservabilityController(GrafanaObservabilityService observability) : ControllerBase
{
    [HttpGet]
    [ProducesResponseType(typeof(GrafanaObservabilityResponse), StatusCodes.Status200OK)]
    public async Task<ActionResult<GrafanaObservabilityResponse>> Get(
        [FromQuery] string? range,
        CancellationToken cancellationToken)
    {
        var response = await observability.QueryAsync(range, cancellationToken);
        return Ok(response);
    }
}
