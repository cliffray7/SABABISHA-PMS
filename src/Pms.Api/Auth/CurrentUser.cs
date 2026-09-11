using System.Security.Claims;

namespace Pms.Api.Auth;

public static class CurrentUser
{
    public static Guid Id(ClaimsPrincipal principal) =>
        Guid.Parse(principal.FindFirstValue(ClaimTypes.NameIdentifier) ?? principal.FindFirstValue("sub")
            ?? throw new UnauthorizedAccessException("Authenticated user claim is missing."));
}
