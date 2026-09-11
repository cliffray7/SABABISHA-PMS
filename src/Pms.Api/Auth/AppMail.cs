using System.Net;
using System.Net.Mail;
using System.Collections.Concurrent;

namespace Pms.Api.Auth;

public sealed record LocalMail(Guid Id, string To, string Subject, string Link, DateTime CreatedAt, string? Body = null);
public sealed class AppMail(IConfiguration config, IWebHostEnvironment environment)
{
    private readonly ConcurrentQueue<LocalMail> inbox = new();
    public bool IsLocal => environment.IsDevelopment() && string.IsNullOrWhiteSpace(config["Smtp:Host"]);
    public LocalMail[] Messages => inbox.Reverse().Take(50).ToArray();
    public string Link(string path) => (config["FrontendUrl"] ?? "http://127.0.0.1:5173").TrimEnd('/') + "/#" + path;
    public async Task Send(string to, string subject, string link)
    {
        if (IsLocal)
        {
            inbox.Enqueue(new LocalMail(Guid.NewGuid(), to, subject, link, DateTime.UtcNow));
            while (inbox.Count > 50) inbox.TryDequeue(out _);
            return;
        }
        if (string.IsNullOrWhiteSpace(config["Smtp:Host"])) throw new InvalidOperationException("Email delivery has not been configured.");
        using var client = new SmtpClient(config["Smtp:Host"], config.GetValue("Smtp:Port", 587)) { EnableSsl = config.GetValue("Smtp:EnableSsl", true) };
        if (!string.IsNullOrWhiteSpace(config["Smtp:Username"])) client.Credentials = new NetworkCredential(config["Smtp:Username"], config["Smtp:Password"]);
        using var message = new MailMessage(config["Smtp:From"] ?? "taskflow@localhost", to, subject, $"{subject}\n\nOpen this link: {link}\n\nIf you did not request this, ignore this message.");
        await client.SendMailAsync(message);
    }
    public async Task SendOtp(string to, string code)
    {
        const string subject = "Your TaskFlow verification code";
        var body = $"Your verification code is {code}. It expires in 10 minutes. If you did not try to log in, ignore this email.";
        if (IsLocal)
        {
            inbox.Enqueue(new LocalMail(Guid.NewGuid(), to, subject, Link("otp?email=" + Uri.EscapeDataString(to)), DateTime.UtcNow, body));
            while (inbox.Count > 50) inbox.TryDequeue(out _);
            return;
        }
        if (string.IsNullOrWhiteSpace(config["Smtp:Host"])) throw new InvalidOperationException("Email delivery has not been configured.");
        using var client = new SmtpClient(config["Smtp:Host"], config.GetValue("Smtp:Port", 587)) { EnableSsl = config.GetValue("Smtp:EnableSsl", true) };
        if (!string.IsNullOrWhiteSpace(config["Smtp:Username"])) client.Credentials = new NetworkCredential(config["Smtp:Username"], config["Smtp:Password"]);
        using var message = new MailMessage(config["Smtp:From"] ?? "taskflow@localhost", to, subject, body);
        await client.SendMailAsync(message);
    }
}
