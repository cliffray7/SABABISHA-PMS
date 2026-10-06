using System.Globalization;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Pms.Api.Media;

public sealed record CloudinaryUpload(string SecureUrl, string PublicId, string ResourceType);

public interface ICloudinaryStorage
{
    bool IsConfigured { get; }
    Task<CloudinaryUpload> UploadAsync(Stream content, string fileName, string folder, string resourceType, CancellationToken cancellationToken);
    Task DeleteAsync(string publicId, string resourceType, CancellationToken cancellationToken);
    Task<byte[]> DownloadAsync(string secureUrl, CancellationToken cancellationToken);
}

public sealed class CloudinaryStorage(
    HttpClient httpClient,
    IConfiguration configuration,
    ILogger<CloudinaryStorage> logger) : ICloudinaryStorage
{
    private readonly string? _cloudName = configuration["Cloudinary:CloudName"];
    private readonly string? _apiKey = configuration["Cloudinary:ApiKey"];
    private readonly string? _apiSecret = configuration["Cloudinary:ApiSecret"];

    public bool IsConfigured =>
        !string.IsNullOrWhiteSpace(_cloudName)
        && !string.IsNullOrWhiteSpace(_apiKey)
        && !string.IsNullOrWhiteSpace(_apiSecret);

    public async Task<CloudinaryUpload> UploadAsync(
        Stream content,
        string fileName,
        string folder,
        string resourceType,
        CancellationToken cancellationToken)
    {
        EnsureConfigured();
        var timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds()
            .ToString(CultureInfo.InvariantCulture);
        var publicId = Guid.NewGuid().ToString("N");
        if (resourceType == "raw")
            publicId += System.IO.Path.GetExtension(fileName).ToLowerInvariant();

        var parameters = new SortedDictionary<string, string>(StringComparer.Ordinal)
        {
            ["folder"] = folder,
            ["public_id"] = publicId,
            ["timestamp"] = timestamp
        };
        using var request = new HttpRequestMessage(
            HttpMethod.Post,
            $"https://api.cloudinary.com/v1_1/{Uri.EscapeDataString(_cloudName!)}/{resourceType}/upload");
        using var form = new MultipartFormDataContent();
        form.Add(new StringContent(_apiKey!), "api_key");
        form.Add(new StringContent(folder), "folder");
        form.Add(new StringContent(publicId), "public_id");
        form.Add(new StringContent(timestamp), "timestamp");
        form.Add(new StringContent(Sign(parameters)), "signature");
        var filePart = new StreamContent(content);
        filePart.Headers.ContentType = new MediaTypeHeaderValue("application/octet-stream");
        form.Add(filePart, "file", System.IO.Path.GetFileName(fileName));
        request.Content = form;

        using var response = await httpClient.SendAsync(request, cancellationToken);
        var body = await response.Content.ReadAsStringAsync(cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            logger.LogError("Cloudinary upload failed with status {StatusCode}: {Response}", response.StatusCode, body);
            throw new CloudinaryStorageException("The media storage service rejected the upload.");
        }

        var uploaded = JsonSerializer.Deserialize<UploadResponse>(body);
        if (uploaded is null || string.IsNullOrWhiteSpace(uploaded.SecureUrl)
            || string.IsNullOrWhiteSpace(uploaded.PublicId)
            || string.IsNullOrWhiteSpace(uploaded.ResourceType))
        {
            logger.LogError("Cloudinary returned an incomplete upload response.");
            throw new CloudinaryStorageException("The media storage service returned an invalid upload response.");
        }

        return new CloudinaryUpload(uploaded.SecureUrl, uploaded.PublicId, uploaded.ResourceType);
    }

    public async Task DeleteAsync(string publicId, string resourceType, CancellationToken cancellationToken)
    {
        EnsureConfigured();
        var timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds()
            .ToString(CultureInfo.InvariantCulture);
        var parameters = new SortedDictionary<string, string>(StringComparer.Ordinal)
        {
            ["public_id"] = publicId,
            ["timestamp"] = timestamp
        };
        using var request = new HttpRequestMessage(
            HttpMethod.Post,
            $"https://api.cloudinary.com/v1_1/{Uri.EscapeDataString(_cloudName!)}/{resourceType}/destroy");
        using var form = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["api_key"] = _apiKey!,
            ["public_id"] = publicId,
            ["timestamp"] = timestamp,
            ["signature"] = Sign(parameters)
        });
        request.Content = form;

        using var response = await httpClient.SendAsync(request, cancellationToken);
        var body = await response.Content.ReadAsStringAsync(cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            logger.LogError("Cloudinary delete failed with status {StatusCode}: {Response}", response.StatusCode, body);
            throw new CloudinaryStorageException("The media storage service could not delete the expired asset.");
        }
        var result = JsonSerializer.Deserialize<DeleteResponse>(body)?.Result;
        if (result is not ("ok" or "not found"))
        {
            logger.LogError("Cloudinary returned an unsuccessful delete response: {Response}", body);
            throw new CloudinaryStorageException("The media storage service could not delete the expired asset.");
        }
    }

    public async Task<byte[]> DownloadAsync(string secureUrl, CancellationToken cancellationToken)
    {
        if (!Uri.TryCreate(secureUrl, UriKind.Absolute, out var uri)
            || uri.Scheme != Uri.UriSchemeHttps
            || !string.Equals(uri.Host, "res.cloudinary.com", StringComparison.OrdinalIgnoreCase))
            throw new CloudinaryStorageException("The stored media URL is invalid.");

        using var response = await httpClient.GetAsync(uri, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            logger.LogError("Cloudinary download failed with status {StatusCode}.", response.StatusCode);
            throw new CloudinaryStorageException("The requested media is not available.");
        }

        return await response.Content.ReadAsByteArrayAsync(cancellationToken);
    }

    private string Sign(SortedDictionary<string, string> parameters)
    {
        EnsureConfigured();
        var canonical = string.Join("&", parameters.Select(pair => $"{pair.Key}={pair.Value}")) + _apiSecret;
        return Convert.ToHexString(SHA1.HashData(Encoding.UTF8.GetBytes(canonical)))
            .ToLowerInvariant();
    }

    private void EnsureConfigured()
    {
        if (!IsConfigured)
            throw new InvalidOperationException("Cloudinary CloudName, ApiKey, and ApiSecret must be configured.");
    }

    private sealed record UploadResponse(
        [property: JsonPropertyName("secure_url")] string? SecureUrl,
        [property: JsonPropertyName("public_id")] string? PublicId,
        [property: JsonPropertyName("resource_type")] string? ResourceType);
    private sealed record DeleteResponse([property: JsonPropertyName("result")] string? Result);
}

public sealed class CloudinaryStorageException(string message) : Exception(message)
{
}
