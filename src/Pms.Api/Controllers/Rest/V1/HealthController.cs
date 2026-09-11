using Microsoft.AspNetCore.Mvc;

namespace Pms.Api.Controllers.Rest.V1;

[ApiController]
[Route("api/v1/health")]
public sealed class HealthController : ControllerBase
{
    [HttpGet]
    public IActionResult Get() => Ok(new
    {
        status = "healthy",
        service = "pms-api",
        timestamp = DateTime.UtcNow
    });
}
