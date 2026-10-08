using Microsoft.AspNetCore.Http;
using Pms.Api.MemberRemoval;

namespace Pms.IntegrationTests;

public sealed class MemberRemovalRequestLimitMiddlewareTests
{
    private static readonly string ConfirmPath = $"/api/v1/projects/{Guid.NewGuid()}/members/{Guid.NewGuid()}/remove";

    [Fact]
    public async Task RejectsKnownLengthBodyOver64KiBWithStableError()
    {
        var context = Context(ConfirmPath, new MemoryStream());
        context.Request.ContentLength = MemberRemovalResolutionSupport.MaxRequestBodyBytes + 1;
        var called = false;
        var middleware = new MemberRemovalRequestLimitMiddleware(_ => { called = true; return Task.CompletedTask; });

        await middleware.InvokeAsync(context);

        Assert.False(called);
        Assert.Equal(StatusCodes.Status413PayloadTooLarge, context.Response.StatusCode);
        context.Response.Body.Position = 0;
        using var json = await System.Text.Json.JsonDocument.ParseAsync(context.Response.Body);
        Assert.Equal("REQUEST_BODY_TOO_LARGE", json.RootElement.GetProperty("code").GetString());
    }

    [Fact]
    public async Task AllowsExactly64KiBAndRejectsChunkedBodyOverLimit()
    {
        var exactBody = new MemoryStream(new byte[MemberRemovalResolutionSupport.MaxRequestBodyBytes]);
        var exact = Context(ConfirmPath, exactBody);
        exact.Request.ContentLength = exactBody.Length;
        var nextCalled = false;
        await new MemberRemovalRequestLimitMiddleware(_ => { nextCalled = true; return Task.CompletedTask; }).InvokeAsync(exact);
        Assert.True(nextCalled);
        Assert.Equal(StatusCodes.Status200OK, exact.Response.StatusCode);

        var chunked = Context(ConfirmPath, new MemoryStream(new byte[MemberRemovalResolutionSupport.MaxRequestBodyBytes + 1]));
        chunked.Request.ContentLength = null;
        nextCalled = false;
        await new MemberRemovalRequestLimitMiddleware(_ => { nextCalled = true; return Task.CompletedTask; }).InvokeAsync(chunked);
        Assert.False(nextCalled);
        Assert.Equal(StatusCodes.Status413PayloadTooLarge, chunked.Response.StatusCode);
    }

    [Fact]
    public async Task DoesNotApplyMemberConfirmationLimitToOtherRoutes()
    {
        var context = Context($"/api/v1/projects/{Guid.NewGuid()}/members", new MemoryStream());
        context.Request.ContentLength = MemberRemovalResolutionSupport.MaxRequestBodyBytes + 1;
        var called = false;
        await new MemberRemovalRequestLimitMiddleware(_ => { called = true; return Task.CompletedTask; }).InvokeAsync(context);
        Assert.True(called);
    }

    private static DefaultHttpContext Context(string path, Stream body)
    {
        var context = new DefaultHttpContext();
        context.Request.Method = HttpMethods.Post;
        context.Request.Path = path;
        context.Request.Body = body;
        context.Response.Body = new MemoryStream();
        return context;
    }
}
