using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Pms.Api.Activity;
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
    public async Task<ActionResult<LoginChallengeResponse>> Register(RegisterRequest request, CancellationToken cancellationToken)
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
        ActivityRecorder.RecordPlatform(db, Request, user.Id, $"{user.FirstName} {user.LastName}",
            "auth.registration.started", user.Id, "Account", "Started registration", "pending");
        return Ok(await IssueOtp(user, cancellationToken));
    }

    [HttpPost("login")]
    public async Task<ActionResult<LoginChallengeResponse>> Login(LoginRequest request, CancellationToken cancellationToken)
    {
        var user = await db.Users.SingleOrDefaultAsync(candidate => candidate.Email == request.Email.Trim().ToLower(), cancellationToken);
        if (user is null || passwordHasher.VerifyHashedPassword(user, user.PasswordHash, request.Password) == PasswordVerificationResult.Failed)
        {
            ActivityRecorder.RecordPlatform(db, Request, null, "Unverified account", "auth.login.failed",
                Guid.Empty, "Sign-in", "Failed sign-in attempt", "failed");
            await db.SaveChangesAsync(cancellationToken);
            return Unauthorized(new { success = false, error = new { code = "INVALID_CREDENTIALS", message = "Invalid email or password." } });
        }
        if (!IsActive(user.Status))
        {
            ActivityRecorder.RecordPlatform(db, Request, null, "Unverified account", "auth.login.failed",
                Guid.Empty, "Sign-in", "Failed sign-in attempt", "failed");
            await db.SaveChangesAsync(cancellationToken);
            return Unauthorized(new { success = false, error = new { code = "INVALID_CREDENTIALS", message = "Invalid email or password." } });
        }

        var strategy = db.Database.CreateExecutionStrategy();
        var challenge = await strategy.ExecuteAsync(async () =>
        {
            db.ChangeTracker.Clear();
            await using var transaction = await db.Database.BeginTransactionAsync(System.Data.IsolationLevel.Serializable, cancellationToken);
            var currentUser = await db.Users.SingleOrDefaultAsync(candidate => candidate.Id == user.Id, cancellationToken);
            if (currentUser is null || !IsActive(currentUser.Status))
            {
                await transaction.RollbackAsync(cancellationToken);
                return (Challenge: (LoginChallengeResponse?)null, Email: user.Email);
            }

            await db.LoginOtpCodes.Where(code => code.UserId == currentUser.Id && code.UsedAt == null)
                .ExecuteUpdateAsync(update => update.SetProperty(code => code.UsedAt, DateTime.UtcNow), cancellationToken);
            ActivityRecorder.RecordPlatform(db, Request, currentUser.Id, $"{currentUser.FirstName} {currentUser.LastName}",
                "auth.login.challenge_issued", currentUser.Id, "Account", "Requested sign-in verification", "pending");
            var issued = await IssueOtp(currentUser, cancellationToken);
            await transaction.CommitAsync(cancellationToken);
            return (Challenge: issued, Email: currentUser.Email);
        });

        if (challenge.Challenge is null)
            return Unauthorized(new { success = false, error = new { code = "INVALID_CREDENTIALS", message = "Invalid email or password." } });
        return Ok(challenge.Challenge);
    }

    private async Task<LoginChallengeResponse> IssueOtp(User user, CancellationToken cancellationToken)
    {
        var otp = tokens.CreateOtp();
        db.LoginOtpCodes.Add(new LoginOtpCode
        {
            Id = Guid.NewGuid(), UserId = user.Id, CodeHash = tokens.HashOtp(otp),
            ExpiresAt = DateTime.UtcNow.AddMinutes(10), CreatedAt = DateTime.UtcNow
        });
        await db.SaveChangesAsync(cancellationToken);
        await mail.SendOtp(user.Email, otp);
        return new LoginChallengeResponse(true, user.Email);
    }

    [HttpPost("verify-otp")]
    public async Task<ActionResult<AuthResponse>> VerifyOtp(VerifyOtpRequest request, CancellationToken cancellationToken)
    {
        var email = request.Email.Trim().ToLowerInvariant();
        var strategy = db.Database.CreateExecutionStrategy();
        return await strategy.ExecuteAsync<ActionResult<AuthResponse>>(async () =>
        {
            db.ChangeTracker.Clear();
            await using var tx = await db.Database.BeginTransactionAsync(System.Data.IsolationLevel.Serializable, cancellationToken);
            var user = await db.Users.SingleOrDefaultAsync(candidate => candidate.Email == email, cancellationToken);
            if (user is null)
            {
                ActivityRecorder.RecordPlatform(db, Request, null, "Unverified account", "auth.otp.failed",
                    Guid.Empty, "Sign-in", "Failed verification attempt", "failed");
                await db.SaveChangesAsync(cancellationToken);
                await tx.CommitAsync(cancellationToken);
                return BadRequest(new { message = "The verification code is invalid or expired." });
            }
            if (!IsActive(user.Status))
            {
                ActivityRecorder.RecordPlatform(db, Request, null, "Unverified account", "auth.otp.failed",
                    Guid.Empty, "Sign-in", "Failed verification attempt", "failed");
                await db.SaveChangesAsync(cancellationToken);
                await tx.CommitAsync(cancellationToken);
                return Unauthorized(new { success = false, error = new { code = "INVALID_CREDENTIALS", message = "The verification code is invalid or expired." } });
            }
            var otp = await db.LoginOtpCodes.OrderByDescending(code => code.CreatedAt).FirstOrDefaultAsync(code => code.UserId == user.Id && code.UsedAt == null && code.ExpiresAt > DateTime.UtcNow, cancellationToken);
            if (otp is null)
            {
                ActivityRecorder.RecordPlatform(db, Request, null, "Unverified account", "auth.otp.failed",
                    Guid.Empty, "Sign-in", "Failed verification attempt", "failed");
                await db.SaveChangesAsync(cancellationToken);
                await tx.CommitAsync(cancellationToken);
                return BadRequest(new { message = "The verification code is invalid or expired." });
            }
            if (!string.Equals(otp.CodeHash, tokens.HashOtp(request.Code), StringComparison.Ordinal))
            {
                otp.AttemptCount++;
                if (otp.AttemptCount >= 5) otp.UsedAt = DateTime.UtcNow;
                ActivityRecorder.RecordPlatform(db, Request, null, "Unverified account", "auth.otp.failed",
                    Guid.Empty, "Sign-in", "Failed verification attempt", "failed");
                await db.SaveChangesAsync(cancellationToken);
                await tx.CommitAsync(cancellationToken);
                return BadRequest(new { message = otp.UsedAt is null ? "The verification code is incorrect." : "Too many incorrect codes. Log in again to request a new code." });
            }
            otp.UsedAt = DateTime.UtcNow;
            var response = await IssueTokens(user, cancellationToken);
            ActivityRecorder.RecordPlatform(db, Request, user.Id, $"{user.FirstName} {user.LastName}",
                "auth.login.succeeded", user.Id, "Account", "Signed in", "succeeded");
            await db.SaveChangesAsync(cancellationToken);
            await tx.CommitAsync(cancellationToken);
            return Ok(response);
        });
    }

    [HttpPost("refresh")]
    public async Task<ActionResult<AuthResponse>> Refresh(RefreshRequest request, CancellationToken cancellationToken)
    {
        var hash = tokens.HashRefreshToken(request.RefreshToken);
        var strategy = db.Database.CreateExecutionStrategy();
        return await strategy.ExecuteAsync<ActionResult<AuthResponse>>(async () =>
        {
            db.ChangeTracker.Clear();
            await using var transaction = await db.Database.BeginTransactionAsync(System.Data.IsolationLevel.Serializable, cancellationToken);
            var stored = await db.RefreshTokens.SingleOrDefaultAsync(token => token.TokenHash == hash, cancellationToken);
            if (stored is null || stored.RevokedAt is not null || stored.ExpiresAt <= DateTime.UtcNow)
                return Unauthorized(new { success = false, error = new { code = "INVALID_REFRESH_TOKEN", message = "Refresh token is invalid or expired." } });

            var user = await db.Users.FindAsync([stored.UserId], cancellationToken);
            if (user is null || !IsActive(user.Status))
            {
                stored.RevokedAt = DateTime.UtcNow;
                await db.SaveChangesAsync(cancellationToken);
                await transaction.CommitAsync(cancellationToken);
                return Unauthorized(new { success = false, error = new { code = "INVALID_REFRESH_TOKEN", message = "Refresh token is invalid or expired." } });
            }

            stored.RevokedAt = DateTime.UtcNow;
            var response = await IssueTokens(user, cancellationToken);
            await db.SaveChangesAsync(cancellationToken);
            await transaction.CommitAsync(cancellationToken);
            return Ok(response);
        });
    }

    private static bool IsActive(string status) => string.Equals(status, "active", StringComparison.OrdinalIgnoreCase);

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
