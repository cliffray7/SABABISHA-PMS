using System.Net;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Pms.Api.Media;

namespace Pms.IntegrationTests;

public sealed class CloudinaryStorageTests
{
    [Fact]
    public async Task UploadAsyncSignsCanonicalParametersAndReturnsCloudinaryAsset()
    {
        HttpRequestMessage? capturedRequest = null;
        string? capturedBody = null;
        var handler = new RecordingHandler(async (request, cancellationToken) =>
        {
            capturedRequest = request;
            capturedBody = await request.Content!.ReadAsStringAsync(cancellationToken);
            return JsonResponse(
                """{"secure_url":"https://res.cloudinary.com/demo/image/upload/avatar.jpg","public_id":"taskflow/avatars/avatar","resource_type":"image"}""");
        });
        var storage = CreateStorage(handler, configured: true);
        using var content = new MemoryStream(Encoding.UTF8.GetBytes("image"));

        var uploaded = await storage.UploadAsync(
            content,
            "avatar.png",
            "taskflow/avatars/user",
            "image",
            CancellationToken.None);

        Assert.Equal("https://api.cloudinary.com/v1_1/demo/image/upload", capturedRequest!.RequestUri!.ToString());
        Assert.Contains("name=api_key", capturedBody);
        Assert.Contains("demo-api-key", capturedBody);
        Assert.Equal(
            new CloudinaryUpload(
                "https://res.cloudinary.com/demo/image/upload/avatar.jpg",
                "taskflow/avatars/avatar",
                "image"),
            uploaded);

        var folder = ReadMultipartValue(capturedBody!, "folder");
        var publicId = ReadMultipartValue(capturedBody!, "public_id");
        var timestamp = ReadMultipartValue(capturedBody!, "timestamp");
        var signature = ReadMultipartValue(capturedBody!, "signature");
        var canonical = $"folder={folder}&public_id={publicId}&timestamp={timestamp}test-secret";
        var expectedSignature = Convert.ToHexString(SHA1.HashData(Encoding.UTF8.GetBytes(canonical)))
            .ToLowerInvariant();
        Assert.Equal(expectedSignature, signature);
    }

    [Fact]
    public async Task DownloadAsyncRejectsNonCloudinaryHostsWithoutMakingRequest()
    {
        var handler = new RecordingHandler((_, _) =>
            Task.FromResult(JsonResponse("{}")));
        var storage = CreateStorage(handler, configured: true);

        await Assert.ThrowsAsync<CloudinaryStorageException>(() =>
            storage.DownloadAsync("https://example.com/private-file", CancellationToken.None));

        Assert.Equal(0, handler.RequestCount);
    }

    [Fact]
    public async Task UploadAsyncRejectsWhenCloudinaryIsNotConfigured()
    {
        var handler = new RecordingHandler((_, _) =>
            Task.FromResult(JsonResponse("{}")));
        var storage = CreateStorage(handler, configured: false);
        using var content = new MemoryStream(Encoding.UTF8.GetBytes("image"));

        await Assert.ThrowsAsync<InvalidOperationException>(() =>
            storage.UploadAsync(
                content,
                "avatar.png",
                "taskflow/avatars/user",
                "image",
                CancellationToken.None));

        Assert.Equal(0, handler.RequestCount);
    }

    private static CloudinaryStorage CreateStorage(RecordingHandler handler, bool configured)
    {
        var settings = configured
            ? new Dictionary<string, string?>
            {
                ["Cloudinary:CloudName"] = "demo",
                ["Cloudinary:ApiKey"] = "demo-api-key",
                ["Cloudinary:ApiSecret"] = "test-secret"
            }
            : new Dictionary<string, string?>();
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(settings)
            .Build();
        return new CloudinaryStorage(
            new HttpClient(handler),
            configuration,
            NullLogger<CloudinaryStorage>.Instance);
    }

    private static HttpResponseMessage JsonResponse(string json) => new(HttpStatusCode.OK)
    {
        Content = new StringContent(json, Encoding.UTF8, "application/json")
    };

    private static string ReadMultipartValue(string body, string name)
    {
        var match = System.Text.RegularExpressions.Regex.Match(
            body,
            $@"name=""?{System.Text.RegularExpressions.Regex.Escape(name)}""?\r\n\r\n([^\r\n]+)");
        Assert.True(match.Success, $"Multipart field '{name}' was not present.");
        return match.Groups[1].Value;
    }

    private sealed class RecordingHandler(
        Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> responseFactory)
        : HttpMessageHandler
    {
        public int RequestCount { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            RequestCount++;
            return responseFactory(request, cancellationToken);
        }
    }
}
