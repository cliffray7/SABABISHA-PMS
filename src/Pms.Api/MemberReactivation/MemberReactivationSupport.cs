using System.Security.Cryptography;
using System.Text.Json;
using Pms.Domain.Entities;

namespace Pms.Api.MemberReactivation;

public sealed record DeactivatedMemberSummaryDto(
    Guid UserId,
    string FirstName,
    string LastName,
    string Email,
    string? AvatarUrl,
    string PreviousRole,
    DateTime JoinedAtUtc
);

public sealed record DeactivatedMemberEligibleProjectDto(
    Guid ProjectId,
    string Name,
    string Lifecycle,
    string? PreviousProjectRole,
    bool ActorCanRestoreProject
);

public sealed record MemberReactivationPreview(
    Guid OrganizationId,
    Guid UserId,
    string FirstName,
    string LastName,
    string Email,
    string? AvatarUrl,
    string PreviousOrganizationRole,
    string AllowedMaxRole,
    IReadOnlyList<DeactivatedMemberEligibleProjectDto> EligibleProjects,
    string SnapshotHash
);

public sealed record ReactivateMemberRequest(
    string Role,
    IReadOnlyList<Guid>? ProjectIds,
    string SnapshotHash,
    string? Reason
);

public static class MemberReactivationSupport
{
    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

    public static string CreateSnapshotHash(
        Guid organizationId,
        Guid targetUserId,
        string? targetOrgRole,
        string? targetOrgStatus,
        string? targetUserAccountStatus,
        Guid actorUserId,
        string? actorOrgRole,
        string? actorOrgStatus,
        IEnumerable<DeactivatedMemberEligibleProjectDto> eligibleProjects)
    {
        var payload = new ReactivationSnapshotPayload(
            "ORGANIZATION_MEMBER_REACTIVATION",
            organizationId,
            targetUserId,
            targetOrgRole,
            targetOrgStatus,
            targetUserAccountStatus,
            actorUserId,
            actorOrgRole,
            actorOrgStatus,
            eligibleProjects
                .OrderBy(p => p.ProjectId)
                .Select(p => new ReactivationSnapshotProject(p.ProjectId, p.Lifecycle, p.PreviousProjectRole, p.ActorCanRestoreProject))
                .ToArray()
        );

        var bytes = SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(payload, JsonOptions));
        return Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');
    }

    public static bool SnapshotMatches(string expectedBase64Url, string actualBase64Url)
    {
        try
        {
            var expected = Convert.FromBase64String(expectedBase64Url.Replace('-', '+').Replace('_', '/')
                .PadRight((expectedBase64Url.Length + 3) / 4 * 4, '='));
            var actual = Convert.FromBase64String(actualBase64Url.Replace('-', '+').Replace('_', '/')
                .PadRight((actualBase64Url.Length + 3) / 4 * 4, '='));
            return expected.Length == actual.Length && CryptographicOperations.FixedTimeEquals(expected, actual);
        }
        catch (FormatException)
        {
            return false;
        }
    }

    private sealed record ReactivationSnapshotPayload(
        string Operation,
        Guid OrganizationId,
        Guid TargetUserId,
        string? TargetOrgRole,
        string? TargetOrgStatus,
        string? TargetUserAccountStatus,
        Guid ActorUserId,
        string? ActorOrgRole,
        string? ActorOrgStatus,
        IReadOnlyList<ReactivationSnapshotProject> Projects
    );

    private sealed record ReactivationSnapshotProject(
        Guid ProjectId,
        string Lifecycle,
        string? PreviousProjectRole,
        bool ActorCanRestoreProject
    );
}

