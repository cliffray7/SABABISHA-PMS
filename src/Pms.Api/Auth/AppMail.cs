using System.Collections.Concurrent;
using System.Net.Http.Headers;
using System.Net;
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
        logger.LogInformation("Sending TaskFlow verification OTP to {To}", to);
        if (IsLocal)
        {
            Enqueue(new LocalMail(Guid.NewGuid(), to, subject, Link("otp?email=" + Uri.EscapeDataString(to)), DateTime.UtcNow, body));
            return;
        }
        await SendViaBrevo(to, subject, body, BuildOtpHtml(code));
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

    private static string BuildOtpHtml(string code)
    {
        var safeCode = WebUtility.HtmlEncode(code);

        return $"""
            <!doctype html>
            <html lang="en">
            <head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
            <body style="margin:0;padding:32px 14px;background:#f4f5f9;font-family:Arial,Helvetica,sans-serif;color:#18181b;">
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0"><tr><td align="center">
                <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width:520px;border:1px solid #e7e8ef;border-radius:16px;background:#ffffff;overflow:hidden;">
                  <tr><td style="height:5px;background:#4f46e5;font-size:0;line-height:0;">&nbsp;</td></tr>
                  <tr><td style="padding:24px 30px 0;">
                    <table role="presentation" cellspacing="0" cellpadding="0" border="0"><tr>
                      <td width="34" height="34" align="center" valign="middle" style="width:34px;height:34px;border-radius:10px;background:#eeebff;color:#5146d8;font-size:16px;font-weight:700;">T</td>
                      <td style="padding-left:10px;color:#272637;font-size:16px;font-weight:700;letter-spacing:-.2px;">TaskFlow</td>
                    </tr></table>
                  </td></tr>
                  <tr><td style="padding:31px 30px 8px;color:#6258d7;font-size:11px;font-weight:700;letter-spacing:1.1px;text-transform:uppercase;">Secure sign in</td></tr>
                  <tr><td style="padding:0 30px;color:#20202b;font-size:25px;font-weight:700;line-height:1.25;letter-spacing:-.5px;">Your verification code</td></tr>
                  <tr><td style="padding:12px 30px 0;color:#686978;font-size:14px;line-height:1.65;">Use this one-time code to securely sign in to your TaskFlow account.</td></tr>
                  <tr><td style="padding:23px 30px 0;">
                    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="border:1px solid #e7e5fb;border-radius:12px;background:#f7f6ff;"><tr><td align="center" style="padding:19px 10px 8px;color:#77758c;font-size:11px;font-weight:600;letter-spacing:.5px;text-transform:uppercase;">Verification code</td></tr><tr><td align="center" style="padding:0 10px 11px;"><span aria-label="Verification code {safeCode}" style="display:inline-block;color:#26243a;font-family:Arial,Helvetica,sans-serif;font-size:36px;font-weight:700;line-height:1.35;letter-spacing:9px;-webkit-user-select:all;user-select:all;">{safeCode}</span></td></tr><tr><td align="center" style="padding:0 10px 18px;color:#77758c;font-size:11px;line-height:1.5;">Select the code to copy it</td></tr></table>
                  </td></tr>
                  <tr><td style="padding:19px 30px 0;color:#555665;font-size:13px;line-height:1.65;">This code expires in <strong style="color:#292837;">10 minutes</strong>. For your security, never share it with anyone.</td></tr>
                  <tr><td style="padding:11px 30px 27px;color:#777887;font-size:12px;line-height:1.6;">If you didn’t request a sign-in code, you can safely ignore this email. Your account remains secure.</td></tr>
                  <tr><td style="padding:16px 30px;border-top:1px solid #ececf1;background:#fafafd;color:#898a98;font-size:11px;line-height:1.5;">TaskFlow · Projects, people, and progress</td></tr>
                </table>
              </td></tr></table>
            </body>
            </html>
            """;
    }

    private async Task SendViaBrevo(string to, string subject, string textBody, string? htmlBody = null)
    {
        try
        {
            var from = config["Brevo:From"] ?? "noreply@taskflow.app";
            var fromName = config["Brevo:FromName"] ?? "TaskFlow";

            var payload = new Dictionary<string, object?>
            {
                ["sender"] = new { email = from, name = fromName },
                ["to"] = new[] { new { email = to } },
                ["subject"] = subject,
                ["textContent"] = textBody
            };
            if (htmlBody is not null) payload["htmlContent"] = htmlBody;

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
                logger.LogInformation("Brevo accepted email for {To}", to);
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
