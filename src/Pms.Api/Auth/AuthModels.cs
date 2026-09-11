using System.ComponentModel.DataAnnotations;
namespace Pms.Api.Auth;
public sealed record RegisterRequest([Required, StringLength(100)] string FirstName, [Required, StringLength(100)] string LastName, [Required, EmailAddress, StringLength(320)] string Email, [Required, StringLength(128, MinimumLength = 8)] string Password);
public sealed record LoginRequest([Required, EmailAddress] string Email, [Required] string Password);
public sealed record RefreshRequest([Required] string RefreshToken);
public sealed record AuthResponse(Guid UserId, string AccessToken, string RefreshToken, DateTime AccessTokenExpiresAt);
public sealed record LoginChallengeResponse(bool RequiresOtp, string Email);
public sealed record VerifyOtpRequest([Required, EmailAddress] string Email, [Required, StringLength(6, MinimumLength = 6)] string Code);
