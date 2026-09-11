using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Pms.Application.Ai;

namespace Pms.Infrastructure.Ai;

public sealed class GeminiTaskService(HttpClient httpClient, GeminiSettings settings, ILogger<GeminiTaskService> logger) : IAiTaskService
{
    public async Task<AiTaskSuggestion> SuggestTaskAsync(AiTaskSuggestionRequest request, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(settings.ApiKey) || string.IsNullOrWhiteSpace(settings.Model))
            throw new AiUnavailableException("AI drafting is not configured. Set Gemini__ApiKey and Gemini__Model on the API server.");

        var titles = string.Join("\n", request.ExistingTaskTitles.Select(title => $"- {title}"));
        var payload = new
        {
            systemInstruction = new { parts = new[] { new { text = "You draft concise, practical project-management tasks. Do not claim to perform work or access data outside the supplied context." } } },
            contents = new[] { new { parts = new[] { new { text = $"Project: {request.ProjectName}\nExisting task titles:\n{titles}\n\nUser goal:\n{request.Prompt}" } } } },
            generationConfig = new
            {
                responseMimeType = "application/json",
                responseJsonSchema = new
                {
                    type = "object",
                    additionalProperties = false,
                    properties = new
                    {
                        title = new { type = "string" },
                        description = new { type = "string" },
                        priority = new { type = "string", @enum = new[] { "URGENT", "HIGH", "MEDIUM", "LOW" } },
                        subtasks = new { type = "array", items = new { type = "string" } }
                    },
                    required = new[] { "title", "description", "priority", "subtasks" }
                }
            }
        };

        var url = $"https://generativelanguage.googleapis.com/v1beta/models/{Uri.EscapeDataString(settings.Model)}:generateContent";
        using var message = new HttpRequestMessage(HttpMethod.Post, url)
        {
            Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json")
        };
        message.Headers.Add("x-goog-api-key", settings.ApiKey);
        using var response = await httpClient.SendAsync(message, cancellationToken);
        var body = await response.Content.ReadAsStringAsync(cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            logger.LogWarning("Gemini task drafting request failed with status code {StatusCode}", (int)response.StatusCode);
            throw new AiUnavailableException(response.StatusCode switch
            {
                System.Net.HttpStatusCode.Unauthorized or System.Net.HttpStatusCode.Forbidden => "Gemini credentials were rejected. Check the API key and its project access.",
                System.Net.HttpStatusCode.NotFound => "The configured Gemini model is unavailable to this API key. Check Gemini__Model.",
                System.Net.HttpStatusCode.TooManyRequests => "Gemini's free quota is currently exhausted. Try again later or review its usage limits.",
                _ => "AI drafting is temporarily unavailable. Please try again later."
            });
        }

        try
        {
            using var document = JsonDocument.Parse(body);
            var output = document.RootElement.GetProperty("candidates")[0].GetProperty("content").GetProperty("parts")[0].GetProperty("text").GetString();
            var draft = JsonSerializer.Deserialize<AiTaskSuggestion>(output ?? string.Empty, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            return draft is null || string.IsNullOrWhiteSpace(draft.Title) ? throw new JsonException() : draft;
        }
        catch (JsonException)
        {
            throw new AiUnavailableException("AI drafting returned an invalid response. Please try again.");
        }
    }
}
