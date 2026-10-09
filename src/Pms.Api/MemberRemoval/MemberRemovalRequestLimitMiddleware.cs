using Microsoft.AspNetCore.Http;

namespace Pms.Api.MemberRemoval;

public sealed class MemberRemovalRequestLimitMiddleware(RequestDelegate next)
{
    public async Task InvokeAsync(HttpContext context)
    {
        var request = context.Request;
        if (!IsConfirmationRequest(request))
        {
            await next(context);
            return;
        }
        if (request.ContentLength > MemberRemovalResolutionSupport.MaxRequestBodyBytes)
        {
            await WriteTooLarge(context);
            return;
        }

        var boundedBody = new MemoryStream(MemberRemovalResolutionSupport.MaxRequestBodyBytes);
        var buffer = new byte[8192];
        var tooLarge = false;
        while (true)
        {
            var allowedRead = Math.Min(buffer.Length,
                MemberRemovalResolutionSupport.MaxRequestBodyBytes - (int)boundedBody.Length + 1);
            var read = await request.Body.ReadAsync(buffer.AsMemory(0, allowedRead), context.RequestAborted);
            if (read == 0) break;
            if (boundedBody.Length + read > MemberRemovalResolutionSupport.MaxRequestBodyBytes)
            {
                tooLarge = true;
                break;
            }
            await boundedBody.WriteAsync(buffer.AsMemory(0, read), context.RequestAborted);
        }

        if (tooLarge)
        {
            boundedBody.Dispose();
            await WriteTooLarge(context);
            return;
        }

        boundedBody.Position = 0;
        var originalBody = request.Body;
        request.Body = boundedBody;
        try { await next(context); }
        finally
        {
            request.Body = originalBody;
            await boundedBody.DisposeAsync();
        }
    }

    private static bool IsConfirmationRequest(HttpRequest request)
    {
        if (!HttpMethods.IsPost(request.Method)) return false;
        var segments = (request.Path.Value ?? string.Empty).Trim('/').Split('/');
        return segments.Length == 7
                && segments[0].Equals("api", StringComparison.OrdinalIgnoreCase)
                && segments[1].Equals("v1", StringComparison.OrdinalIgnoreCase)
                && segments[2].Equals("projects", StringComparison.OrdinalIgnoreCase)
                && Guid.TryParse(segments[3], out _)
                && segments[4].Equals("members", StringComparison.OrdinalIgnoreCase)
                && Guid.TryParse(segments[5], out _)
                && segments[6].Equals("remove", StringComparison.OrdinalIgnoreCase)
            || segments.Length == 7
                && segments[0].Equals("api", StringComparison.OrdinalIgnoreCase)
                && segments[1].Equals("v1", StringComparison.OrdinalIgnoreCase)
                && segments[2].Equals("organizations", StringComparison.OrdinalIgnoreCase)
                && Guid.TryParse(segments[3], out _)
                && segments[4].Equals("members", StringComparison.OrdinalIgnoreCase)
                && Guid.TryParse(segments[5], out _)
                && segments[6].Equals("deactivate", StringComparison.OrdinalIgnoreCase);
    }

    private static async Task WriteTooLarge(HttpContext context)
    {
        context.Response.StatusCode = StatusCodes.Status413PayloadTooLarge;
        context.Response.ContentType = "application/json";
        await context.Response.WriteAsJsonAsync(new
        {
            code = "REQUEST_BODY_TOO_LARGE",
            message = "The member-resolution request exceeds the 64-KiB limit. Reduce its size and refresh the preview."
        }, context.RequestAborted);
    }
}
