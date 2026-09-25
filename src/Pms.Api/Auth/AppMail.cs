using System.Collections.Concurrent;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace Pms.Api.Auth;

public sealed record LocalMail(Guid Id, string To, string Subject, string Link, DateTime CreatedAt, string? Body = null);

public sealed class AppMail(IConfiguration config, IHttpClientFactory httpClientFactory, ILogger<AppMail> logger)
{
    private readonly ConcurrentQueue<LocalMail> inbox = new();

    // Local mode when no Brevo API key is configured — falls back to in-memory inbox.
    public bool IsLocal => string.IsNullOrWhiteSpace(config["Brevo:ApiKey"]);

    public LocalMail[] Messages => inbox.Reverse().Take(50).ToArray();

    public string Link(string path) =>
        (config["FrontendUrl"] ?? "http://127.0.0.1:5173").TrimEnd('/') + "/#" + path;

    public async Task Send(string to, string subject, string link)
    {
        logger.LogInformation("Sending email to {To}: {Subject} -> {Link}", to, subject, link);
        var body = $"{subject}\n\nOpen this link: {link}\n\nIf you did not request this, ignore this message.";
        if (IsLocal)
        {
            Enqueue(new LocalMail(Guid.NewGuid(), to, subject, link, DateTime.UtcNow));
            return;
        }
        await SendViaBrevo(to, subject, body);
    }

    public async Task SendOtp(string to, string code)
    {
        const string subject = "Your TaskFlow verification code";
        var body = $"Your verification code is {code}. It expires in 10 minutes. If you did not try to log in, ignore this email.";
        logger.LogInformation("TaskFlow verification OTP for {To}: {Code}", to, code);
        if (IsLocal)
        {
            Enqueue(new LocalMail(Guid.NewGuid(), to, subject, Link("otp?email=" + Uri.EscapeDataString(to)), DateTime.UtcNow, body));
            return;
        }
        await SendViaBrevo(to, subject, body);
    }

    public async Task SendTaskAssigned(string to, string assigneeName, string taskTitle, Guid projectId, Guid taskId)
    {
        const string subject = "You have been assigned a task on TaskFlow";
        var link = Link($"project?id={projectId}&task={taskId}");
        var body = $"Hi {assigneeName},\n\nYou have been assigned to the task \"{taskTitle}\".\n\nOpen the task: {link}\n\nIf you were not expecting this, contact your project manager.";
        logger.LogInformation("Sending task-assigned email to {To} for task {TaskId}", to, taskId);
        if (IsLocal)
        {
            Enqueue(new LocalMail(Guid.NewGuid(), to, subject, link, DateTime.UtcNow, body));
            return;
        }
        await SendViaBrevo(to, subject, body);
    }

    private async Task SendViaBrevo(string to, string subject, string textBody)
    {
        try
        {
            var from = config["Brevo:From"] ?? "noreply@taskflow.app";
            var fromName = config["Brevo:FromName"] ?? "TaskFlow";

            var payload = new
            {
                sender = new { email = from, name = fromName },
                to = new[] { new { email = to } },
                subject,
                textContent = textBody
            };

            var json = JsonSerializer.Serialize(payload);
            var request = new HttpRequestMessage(HttpMethod.Post, "https://api.brevo.com/v3/smtp/email")
            {
                Content = new StringContent(json, Encoding.UTF8, "application/json")
            };
            request.Headers.Add("api-key", config["Brevo:ApiKey"]);
            request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));

            var client = httpClientFactory.CreateClient("Brevo");
            var response = await client.SendAsync(request);

            if (!response.IsSuccessStatusCode)
            {
                var error = await response.Content.ReadAsStringAsync();
                logger.LogError("Brevo API rejected email to {To}: {StatusCode} {Error}", to, response.StatusCode, error);
                Enqueue(new LocalMail(Guid.NewGuid(), to, subject, string.Empty, DateTime.UtcNow, $"Delivery failed: {error}"));
            }
            else
            {
                logger.LogInformation("Brevo delivered email to {To}", to);
            }
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to deliver email via Brevo HTTP API to {To}. Storing in fallback inbox.", to);
            Enqueue(new LocalMail(Guid.NewGuid(), to, subject, string.Empty, DateTime.UtcNow));
        }
    }

    private void Enqueue(LocalMail mail)
    {
        inbox.Enqueue(mail);
        while (inbox.Count > 50) inbox.TryDequeue(out _);
    }
}
