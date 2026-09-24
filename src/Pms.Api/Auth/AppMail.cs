using System.Net;
using System.Net.Mail;
using System.Collections.Concurrent;

namespace Pms.Api.Auth;

public sealed record LocalMail(Guid Id, string To, string Subject, string Link, DateTime CreatedAt, string? Body = null);
public sealed class AppMail(IConfiguration config, ILogger<AppMail> logger)
{
    private readonly ConcurrentQueue<LocalMail> inbox = new();
    public bool IsLocal => string.IsNullOrWhiteSpace(config["Smtp:Host"]);
    public LocalMail[] Messages => inbox.Reverse().Take(50).ToArray();
    public string Link(string path) => (config["FrontendUrl"] ?? "http://127.0.0.1:5173").TrimEnd('/') + "/#" + path;
    public async Task Send(string to, string subject, string link)
    {
        logger.LogInformation("Sending email to {To}: {Subject} -> {Link}", to, subject, link);
        if (IsLocal)
        {
            inbox.Enqueue(new LocalMail(Guid.NewGuid(), to, subject, link, DateTime.UtcNow));
            while (inbox.Count > 50) inbox.TryDequeue(out _);
            return;
        }
        try
        {
            using var client = new SmtpClient(config["Smtp:Host"], config.GetValue("Smtp:Port", 587)) { EnableSsl = config.GetValue("Smtp:EnableSsl", true) };
            if (!string.IsNullOrWhiteSpace(config["Smtp:Username"])) client.Credentials = new NetworkCredential(config["Smtp:Username"], config["Smtp:Password"]);
            using var message = new MailMessage(config["Smtp:From"] ?? "taskflow@localhost", to, subject, $"{subject}\n\nOpen this link: {link}\n\nIf you did not request this, ignore this message.");
            await client.SendMailAsync(message);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to deliver email via SMTP to {To}. Storing in fallback inbox.", to);
            inbox.Enqueue(new LocalMail(Guid.NewGuid(), to, subject, link, DateTime.UtcNow));
            while (inbox.Count > 50) inbox.TryDequeue(out _);
        }
    }
    public async Task SendOtp(string to, string code)
    {
        const string subject = "Your TaskFlow verification code";
        var body = $"Your verification code is {code}. It expires in 10 minutes. If you did not try to log in, ignore this email.";
        logger.LogInformation("TaskFlow verification OTP for {To}: {Code}", to, code);
        if (IsLocal)
        {
            inbox.Enqueue(new LocalMail(Guid.NewGuid(), to, subject, Link("otp?email=" + Uri.EscapeDataString(to)), DateTime.UtcNow, body));
            while (inbox.Count > 50) inbox.TryDequeue(out _);
            return;
        }
        try
        {
            using var client = new SmtpClient(config["Smtp:Host"], config.GetValue("Smtp:Port", 587)) { EnableSsl = config.GetValue("Smtp:EnableSsl", true) };
            if (!string.IsNullOrWhiteSpace(config["Smtp:Username"])) client.Credentials = new NetworkCredential(config["Smtp:Username"], config["Smtp:Password"]);
            using var message = new MailMessage(config["Smtp:From"] ?? "taskflow@localhost", to, subject, body);
            await client.SendMailAsync(message);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to deliver OTP via SMTP to {To}. Storing in fallback inbox.", to);
            inbox.Enqueue(new LocalMail(Guid.NewGuid(), to, subject, Link("otp?email=" + Uri.EscapeDataString(to)), DateTime.UtcNow, body));
            while (inbox.Count > 50) inbox.TryDequeue(out _);
        }
    }
}
