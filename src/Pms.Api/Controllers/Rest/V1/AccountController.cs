using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using Pms.Api.Auth;
using Pms.Domain.Entities;
using Pms.Infrastructure.Persistence.EfCore;
namespace Pms.Api.Controllers.Rest.V1;

[ApiController, Route("api/v1")]
public sealed class AccountController(PmsDbContext db, TokenService tokens, IPasswordHasher<User> hasher, AppMail mail) : ControllerBase
{
    [HttpGet("auth/mail-mode")]
    public IActionResult MailMode() => Ok(new { local = mail.IsLocal });
    [HttpGet("dev/inbox")]
    public IActionResult Inbox() => mail.IsLocal ? Ok(mail.Messages) : NotFound();

    [HttpPost("auth/forgot-password"), EnableRateLimiting("auth")]
    public async Task<IActionResult> Forgot(EmailRequest request, CancellationToken ct)
    {
        var user = await db.Users.SingleOrDefaultAsync(x => x.Email == request.Email.Trim().ToLower(), ct);
        if (user is not null)
        {
            var token = tokens.CreateRefreshToken();
            db.PasswordResetTokens.Add(new PasswordResetToken { Id = Guid.NewGuid(), UserId = user.Id, TokenHash = tokens.HashRefreshToken(token), ExpiresAt = DateTime.UtcNow.AddMinutes(30) });
            await db.SaveChangesAsync(ct);
            await mail.Send(user.Email, "Reset your TaskFlow password", mail.Link("reset?token=" + Uri.EscapeDataString(token)));
        }
        return Ok(new { message = "If an account exists for that email, a reset link has been sent." });
    }
    [HttpPost("auth/reset-password"), EnableRateLimiting("auth")]
    public async Task<IActionResult> Reset(ResetPasswordRequest request, CancellationToken ct)
    {
        var strategy = db.Database.CreateExecutionStrategy();
        return await strategy.ExecuteAsync<IActionResult>(async () =>
        {
            await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct);
            var hash = tokens.HashRefreshToken(request.Token);
            var reset = await db.PasswordResetTokens.SingleOrDefaultAsync(x => x.TokenHash == hash && x.UsedAt == null && x.ExpiresAt > DateTime.UtcNow, ct);
            if (reset is null) return BadRequest(new { message = "This reset link is invalid or expired. Request a new one." });
            var user = await db.Users.SingleAsync(x => x.Id == reset.UserId, ct);
            user.PasswordHash = hasher.HashPassword(user, request.Password);
            user.UpdatedAt = DateTime.UtcNow;
            await db.PasswordResetTokens.Where(x => x.UserId == user.Id && x.UsedAt == null).ExecuteUpdateAsync(s => s.SetProperty(x => x.UsedAt, DateTime.UtcNow), ct);
            await db.RefreshTokens.Where(x => x.UserId == user.Id && x.RevokedAt == null).ExecuteUpdateAsync(s => s.SetProperty(x => x.RevokedAt, DateTime.UtcNow), ct);
            await db.SaveChangesAsync(ct); await tx.CommitAsync(ct);
            return Ok(new { message = "Password reset. You can now log in." });
        });
    }
    [Authorize, HttpGet("account")]
    public async Task<IActionResult> Me(CancellationToken ct) => Ok(await db.Users.Where(x => x.Id == CurrentUser.Id(User)).Select(x => new { x.Id, x.FirstName, x.LastName, x.Email, x.Timezone }).SingleAsync(ct));
    [Authorize, HttpPatch("account")]
    public async Task<IActionResult> Profile(ProfileRequest request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.FirstName) || string.IsNullOrWhiteSpace(request.LastName)) return BadRequest(new { message = "First and last names are required." });
        var user = await db.Users.SingleAsync(x => x.Id == CurrentUser.Id(User), ct);
        user.FirstName = request.FirstName.Trim(); user.LastName = request.LastName.Trim(); user.Timezone = request.Timezone; user.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct); return await Me(ct);
    }
    [Authorize, HttpPost("auth/logout")]
    public async Task<IActionResult> Logout(RefreshRequest request, CancellationToken ct)
    {
        var hash = tokens.HashRefreshToken(request.RefreshToken);
        await db.RefreshTokens.Where(x => x.UserId == CurrentUser.Id(User) && x.TokenHash == hash).ExecuteUpdateAsync(s => s.SetProperty(x => x.RevokedAt, DateTime.UtcNow), ct);
        return NoContent();
    }
}
public sealed record EmailRequest([Required, EmailAddress] string Email);
public sealed record ResetPasswordRequest([Required] string Token, [Required, StringLength(128, MinimumLength = 8)] string Password);
public sealed record ProfileRequest([Required, StringLength(100)] string FirstName, [Required, StringLength(100)] string LastName, [Required, StringLength(100)] string Timezone);
