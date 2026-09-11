using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Pms.Api.Auth;
using Pms.Domain.Entities;
using Pms.Infrastructure.Persistence.EfCore;

namespace Pms.Api.Controllers.Rest.V1;

[ApiController]
[Microsoft.AspNetCore.RateLimiting.EnableRateLimiting("auth")]
[Route("api/v1/auth")]
public sealed class AuthController(PmsDbContext db, IPasswordHasher<User> passwordHasher, TokenService tokens, AppMail mail, Microsoft.Extensions.Options.IOptions<JwtOptions> jwtOptions) : ControllerBase
{
    [HttpPost("register")]
    public async Task<ActionResult<AuthResponse>> Register(RegisterRequest request, CancellationToken cancellationToken)
    {
        var email = request.Email.Trim().ToLowerInvariant();
        if (string.IsNullOrWhiteSpace(request.FirstName) || string.IsNullOrWhiteSpace(request.LastName)) return BadRequest(new { message = "First and last names are required." });
        if (await db.Users.AnyAsync(user => user.Email == email, cancellationToken))
            return Conflict(new { success = false, error = new { code = "EMAIL_EXISTS", message = "Email is already registered." } });

        var user = new User
        {
            Id = Guid.NewGuid(), FirstName = request.FirstName.Trim(), LastName = request.LastName.Trim(),
            Email = email, PasswordHash = string.Empty
        };
        user.PasswordHash = passwordHasher.HashPassword(user, request.Password);
        db.Users.Add(user);
        var response = await IssueTokens(user, cancellationToken);
        await db.SaveChangesAsync(cancellationToken);
        return Ok(response);
    }

    [HttpPost("login")]
    public async Task<ActionResult<LoginChallengeResponse>> Login(LoginRequest request, CancellationToken cancellationToken)
    {
        var user = await db.Users.SingleOrDefaultAsync(candidate => candidate.Email == request.Email.Trim().ToLower(), cancellationToken);
        if (user is null || passwordHasher.VerifyHashedPassword(user, user.PasswordHash, request.Password) == PasswordVerificationResult.Failed)
            return Unauthorized(new { success = false, error = new { code = "INVALID_CREDENTIALS", message = "Invalid email or password." } });

        await db.LoginOtpCodes.Where(code => code.UserId == user.Id && code.UsedAt == null)
            .ExecuteUpdateAsync(update => update.SetProperty(code => code.UsedAt, DateTime.UtcNow), cancellationToken);
        var otp = tokens.CreateOtp();
        db.LoginOtpCodes.Add(new LoginOtpCode
        {
            Id = Guid.NewGuid(), UserId = user.Id, CodeHash = tokens.HashOtp(otp),
            ExpiresAt = DateTime.UtcNow.AddMinutes(10), CreatedAt = DateTime.UtcNow
        });
        await db.SaveChangesAsync(cancellationToken);
        await mail.SendOtp(user.Email, otp);
        return Ok(new LoginChallengeResponse(true, user.Email));
    }

    [HttpPost("verify-otp")]
    public async Task<ActionResult<AuthResponse>> VerifyOtp(VerifyOtpRequest request, CancellationToken cancellationToken)
    {
        var email = request.Email.Trim().ToLowerInvariant();
        var strategy = db.Database.CreateExecutionStrategy();
        return await strategy.ExecuteAsync<ActionResult<AuthResponse>>(async () =>
        {
            await using var tx = await db.Database.BeginTransactionAsync(System.Data.IsolationLevel.Serializable, cancellationToken);
            var user = await db.Users.SingleOrDefaultAsync(candidate => candidate.Email == email, cancellationToken);
            if (user is null) return BadRequest(new { message = "The verification code is invalid or expired." });
            var otp = await db.LoginOtpCodes.OrderByDescending(code => code.CreatedAt).FirstOrDefaultAsync(code => code.UserId == user.Id && code.UsedAt == null && code.ExpiresAt > DateTime.UtcNow, cancellationToken);
            if (otp is null) return BadRequest(new { message = "The verification code is invalid or expired." });
            if (!string.Equals(otp.CodeHash, tokens.HashOtp(request.Code), StringComparison.Ordinal))
            {
                otp.AttemptCount++;
                if (otp.AttemptCount >= 5) otp.UsedAt = DateTime.UtcNow;
                await db.SaveChangesAsync(cancellationToken);
                return BadRequest(new { message = otp.UsedAt is null ? "The verification code is incorrect." : "Too many incorrect codes. Log in again to request a new code." });
            }
            otp.UsedAt = DateTime.UtcNow;
            var response = await IssueTokens(user, cancellationToken);
            await db.SaveChangesAsync(cancellationToken);
            await tx.CommitAsync(cancellationToken);
            return Ok(response);
        });
    }

    [HttpPost("refresh")]
    public async Task<ActionResult<AuthResponse>> Refresh(RefreshRequest request, CancellationToken cancellationToken)
    {
        var hash = tokens.HashRefreshToken(request.RefreshToken);
        var stored = await db.RefreshTokens.SingleOrDefaultAsync(token => token.TokenHash == hash, cancellationToken);
        if (stored is null || stored.RevokedAt is not null || stored.ExpiresAt <= DateTime.UtcNow)
            return Unauthorized(new { success = false, error = new { code = "INVALID_REFRESH_TOKEN", message = "Refresh token is invalid or expired." } });

        stored.RevokedAt = DateTime.UtcNow;
        var user = await db.Users.FindAsync([stored.UserId], cancellationToken);
        if (user is null) return Unauthorized();
        var response = await IssueTokens(user, cancellationToken);
        await db.SaveChangesAsync(cancellationToken);
        return Ok(response);
    }

    private async Task<AuthResponse> IssueTokens(User user, CancellationToken cancellationToken)
    {
        var access = tokens.CreateAccessToken(user);
        var refresh = tokens.CreateRefreshToken();
        db.RefreshTokens.Add(new RefreshToken
        {
            Id = Guid.NewGuid(), UserId = user.Id, TokenHash = tokens.HashRefreshToken(refresh),
            ExpiresAt = DateTime.UtcNow.AddDays(jwtOptions.Value.RefreshTokenDays)
        });
        await Task.CompletedTask;
        return new AuthResponse(user.Id, access.Token, refresh, access.ExpiresAt);
    }
}
