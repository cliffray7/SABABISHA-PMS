namespace Pms.Application.Ai;

public sealed record AiTaskSuggestionRequest(string ProjectName, string Prompt, IReadOnlyList<string> ExistingTaskTitles);
public sealed record AiTaskSuggestion(string Title, string Description, string Priority, IReadOnlyList<string> Subtasks);
public sealed record GeminiSettings(string? ApiKey, string? Model);

public interface IAiTaskService
{
    Task<AiTaskSuggestion> SuggestTaskAsync(AiTaskSuggestionRequest request, CancellationToken cancellationToken);
}

public sealed class AiUnavailableException(string message) : Exception(message);
