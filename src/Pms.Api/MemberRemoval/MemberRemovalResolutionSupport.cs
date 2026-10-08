using System.Security.Cryptography;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using Pms.Api.Activity;
using Pms.Api.Auth;
using Pms.Domain.Entities;
using Pms.Infrastructure.Persistence.EfCore;

namespace Pms.Api.MemberRemoval;

public sealed record MemberTaskResolution(Guid TaskId, string? Action, Guid? ReplacementUserId);
public sealed record MemberRemovalRequest(string? SnapshotHash, IReadOnlyCollection<MemberTaskResolution>? Resolutions);
public sealed record ReplacementMember(Guid UserId, string DisplayName);
public sealed record RemovalTaskPreview(Guid TaskId, Guid? ParentTaskId, string Title, string Status,
    IReadOnlyList<Guid> CurrentAssigneeIds, string RequiredResolution);
public sealed record RemovalProjectPreview(Guid ProjectId, string Lifecycle, bool OwnerTransferRequired,
    bool ManagerInvariantBlocked, IReadOnlyList<ReplacementMember> EligibleReplacementMembers,
    IReadOnlyList<RemovalTaskPreview> Tasks,
    IReadOnlyList<HistoricalAttributionPreview> HistoricalAttributionsToInactivate);
public sealed record HistoricalAttributionPreview(Guid TaskId, string Status, bool TaskInTrash,
    IReadOnlyList<Guid> CurrentAssigneeIds, string ActionOnConfirm);
public sealed record ExpiredTrashTaskPreview(Guid TaskId, string Status, IReadOnlyList<Guid> CurrentAssigneeIds,
    string ActionOnConfirm);
public sealed record ExpiredTrashProjectPreview(Guid ProjectId, DateTime DeletedAt, string Lifecycle,
    string OwnerManagerChecks, IReadOnlyList<ExpiredTrashTaskPreview> Tasks);
public sealed record MemberRemovalPreview(Guid? ProjectId, Guid OrganizationId, Guid MemberId,
    string SnapshotHash, int AffectedTaskCount, IReadOnlyList<RemovalProjectPreview> AffectedProjects,
    IReadOnlyList<ExpiredTrashProjectPreview> ExpiredTrashCleanup);
public sealed record MemberRemovalValidationError(int StatusCode, string Code, string Message);

public sealed class MemberRemovalState
{
    public required Guid OrganizationId { get; init; }
    public required Guid MemberId { get; init; }
    public required Guid ActorId { get; init; }
    public required DateTime CapturedNowUtc { get; init; }
    public required OrganizationMember? MemberOrganizationMembership { get; init; }
    public required OrganizationMember? ActorOrganizationMembership { get; init; }
    public required IReadOnlyList<MemberRemovalProjectState> Projects { get; init; }
    public required IReadOnlyList<WorkTask> Tasks { get; init; }
    public required IReadOnlyList<TaskAssignee> TargetActiveAssignments { get; init; }
    public required IReadOnlyList<TaskAssignee> TaskAssignmentRows { get; init; }
    public required IReadOnlyList<TaskAssignee> ActiveTaskAssignments { get; init; }
    public required IReadOnlyDictionary<Guid, OrganizationMember> OrganizationMemberships { get; init; }
    public required IReadOnlyDictionary<Guid, User> Users { get; init; }
    public required bool HasUnseenTargetAssignment { get; init; }

    public IReadOnlyList<MemberRemovalTaskState> AllAssignedTasks =>
        (from task in Tasks
         join assignment in TargetActiveAssignments on task.Id equals assignment.TaskId
         join project in Projects on task.ProjectId equals project.Project.Id
         select new MemberRemovalTaskState(task, project, assignment,
             ActiveTaskAssignments.Where(item => item.TaskId == task.Id).ToArray()))
        .OrderBy(item => item.Project.Project.Id).ThenBy(item => item.Task.Id).ToArray();

    public IReadOnlyList<MemberRemovalTaskState> AffectedTasks => AllAssignedTasks
        .Where(item => item.Task.DeletedAt is null && item.Task.Status != "DONE").ToArray();

    public IReadOnlyList<MemberRemovalTaskState> HistoricalAssignmentsToInactivate => AllAssignedTasks
        .Where(item => item.Task.DeletedAt is not null || item.Task.Status == "DONE").ToArray();

    public IReadOnlyList<MemberRemovalTaskState> ExpiredTrashAssignmentsToInactivate => AllAssignedTasks
        .Where(item => item.Project.Lifecycle == "EXPIRED_TRASH_PENDING_PURGE").ToArray();

    public IReadOnlyList<MemberRemovalProjectState> RetainedProjects =>
        Projects.Where(project => project.Lifecycle is "ACTIVE" or "ARCHIVED" or "TRASHED_WITHIN_RETENTION").ToArray();

    public IReadOnlyList<MemberRemovalProjectState> ExpiredProjects =>
        Projects.Where(project => project.Lifecycle == "EXPIRED_TRASH_PENDING_PURGE").ToArray();

    public MemberRemovalPreview ToPreview(Guid? projectId)
    {
        var retained = RetainedProjects.Where(project => projectId is null || project.Project.Id == projectId)
            .Where(project => projectId is not null || project.Project.OwnerId == MemberId
                || project.TargetMembership is { Status: "active" }
                || AllAssignedTasks.Any(task => task.Project.Project.Id == project.Project.Id))
            .Select(project =>
            {
                var affected = AffectedTasks.Where(item => item.Project.Project.Id == project.Project.Id).ToArray();
                var lifecycleResolution = project.Lifecycle != "ACTIVE";
                return new RemovalProjectPreview(project.Project.Id, project.Lifecycle,
                    project.Project.OwnerId == MemberId,
                    project.TargetMembership is { Status: "active" }
                        && project.ActiveManagerIds.Count
                            - (project.ActiveManagerIds.Contains(MemberId) ? 1 : 0) < 1,
                    lifecycleResolution ? [] : project.EligibleReplacementMembers,
                    affected.Select(item => new RemovalTaskPreview(item.Task.Id, item.Task.ParentTaskId,
                        item.Task.Title, item.Task.Status,
                        item.CurrentAssignments.Select(assignment => assignment.UserId).Distinct().Order().ToArray(),
                        lifecycleResolution ? "ACCEPT_LIFECYCLE_INACTIVATION" : "REASSIGN_OR_UNASSIGN")).ToArray(),
                    HistoricalAssignmentsToInactivate.Where(item => item.Project.Project.Id == project.Project.Id)
                        .Select(item => new HistoricalAttributionPreview(item.Task.Id, item.Task.Status,
                            item.Task.DeletedAt is not null,
                            item.CurrentAssignments.Select(assignment => assignment.UserId).Distinct().Order().ToArray(),
                            "UNASSIGNED")).ToArray());
            }).OrderBy(project => project.ProjectId).ToArray();

        var expired = projectId is null
            ? ExpiredProjects.Where(project => project.TargetMembership is { Status: "active" }
                    || AllAssignedTasks.Any(task => task.Project.Project.Id == project.Project.Id))
                .OrderBy(project => project.Project.Id).Select(project => new ExpiredTrashProjectPreview(
                project.Project.Id, project.Project.DeletedAt!.Value, project.Lifecycle, "NOT_APPLICABLE",
                AllAssignedTasks.Where(item => item.Project.Project.Id == project.Project.Id)
                    .Select(item => new ExpiredTrashTaskPreview(item.Task.Id, item.Task.Status,
                        item.CurrentAssignments.Select(assignment => assignment.UserId).Distinct().Order().ToArray(),
                        item.Task.DeletedAt is null && item.Task.Status != "DONE"
                            ? "LIFECYCLE_INACTIVATED" : "UNASSIGNED")).ToArray())).ToArray()
            : [];

        return new MemberRemovalPreview(projectId, OrganizationId, MemberId,
            MemberRemovalResolutionSupport.CreateSnapshotHash(this, projectId),
            AllAssignedTasks.Count(item => projectId is null || item.Project.Project.Id == projectId), retained, expired);
    }
}

public sealed record MemberRemovalProjectState(Project Project, string Lifecycle,
    IReadOnlyList<ProjectMember> Memberships, ProjectMember? TargetMembership,
    IReadOnlyList<Guid> ActiveManagerIds, IReadOnlyList<ReplacementMember> EligibleReplacementMembers);

public sealed record MemberRemovalTaskState(WorkTask Task, MemberRemovalProjectState Project,
    TaskAssignee TargetAssignment, IReadOnlyList<TaskAssignee> CurrentAssignments);

public static class MemberRemovalResolutionSupport
{
    public const int MaxAffectedTasks = 100;
    public const int MaxRequestBodyBytes = 64 * 1024;
    private static readonly JsonSerializerOptions SnapshotJson = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

    public static async Task<MemberRemovalState> LoadStateAsync(PmsDbContext db, Guid organizationId,
        Guid memberId, Guid actorId, Guid? projectScopeId, DateTime capturedNowUtc, bool acquireLocks,
        CancellationToken cancellationToken)
    {
        var isSqlServer = db.Database.IsSqlServer();
        var organizationMembershipIds = new[] { actorId, memberId }.Distinct().Order().ToArray();
        var scopeMemberships = await QueryOrganizationMemberships(db, organizationId,
            organizationMembershipIds, acquireLocks && isSqlServer, cancellationToken);

        List<Project> projectRows;
        if (acquireLocks && isSqlServer)
        {
            var lockedProjectQuery = projectScopeId is null
                ? db.Projects.FromSqlInterpolated($"SELECT * FROM projects WITH (UPDLOCK,HOLDLOCK) WHERE organization_id = {organizationId} ORDER BY id")
                : db.Projects.FromSqlInterpolated($"SELECT * FROM projects WITH (UPDLOCK,HOLDLOCK) WHERE organization_id = {organizationId} AND id = {projectScopeId.Value}");
            // Execute the ordered lock query directly; composing another OrderBy
            // over this raw SQL would wrap its ORDER BY in a SQL Server subquery.
            projectRows = await lockedProjectQuery.ToListAsync(cancellationToken);
            projectRows.Sort((left, right) => left.Id.CompareTo(right.Id));
        }
        else
        {
            projectRows = await db.Projects.Where(project => project.OrganizationId == organizationId
                    && (projectScopeId == null || project.Id == projectScopeId))
                .OrderBy(project => project.Id).ToListAsync(cancellationToken);
        }
        var lifecycleByProject = projectRows.ToDictionary(project => project.Id,
            project => Lifecycle(project, capturedNowUtc));

        var membershipRows = new List<ProjectMember>();
        foreach (var project in projectRows.OrderBy(project => project.Id))
        {
            var query = acquireLocks && isSqlServer
                ? db.ProjectMembers.FromSqlInterpolated($"SELECT * FROM project_members WITH (UPDLOCK,HOLDLOCK,INDEX(uq_project_members)) WHERE project_id = {project.Id} ORDER BY user_id")
                : db.ProjectMembers.Where(member => member.ProjectId == project.Id).OrderBy(member => member.UserId);
            membershipRows.AddRange(await query.ToListAsync(cancellationToken));
        }

        var relevantUserIds = membershipRows.Select(member => member.UserId)
            .Append(memberId).Append(actorId).Distinct().Order().ToArray();
        var missingOrganizationUserIds = relevantUserIds.Where(id => scopeMemberships.All(member => member.UserId != id)).ToArray();
        var relevantOrganizationMemberships = scopeMemberships.Concat(
            await QueryOrganizationMemberships(db, organizationId, missingOrganizationUserIds,
                acquireLocks && isSqlServer, cancellationToken)).ToDictionary(member => member.UserId);

        var users = new Dictionary<Guid, User>();
        foreach (var relevantUserId in relevantUserIds.Order())
        {
            var userQuery = acquireLocks && isSqlServer
                ? db.Users.FromSqlInterpolated($"SELECT * FROM users WITH (UPDLOCK,HOLDLOCK) WHERE id = {relevantUserId}")
                : db.Users.Where(user => user.Id == relevantUserId);
            var user = await userQuery.SingleOrDefaultAsync(cancellationToken);
            if (user is not null) users.Add(user.Id, user);
        }

        var taskIds = new List<Guid>();
        foreach (var project in projectRows.OrderBy(project => project.Id))
        {
            if (acquireLocks && isSqlServer)
            {
                var projectTaskIds = await db.Database.SqlQuery<Guid>($"SELECT id AS Value FROM tasks WITH (UPDLOCK,HOLDLOCK,INDEX(ix_tasks_project_status)) WHERE project_id = {project.Id}")
                    .ToListAsync(cancellationToken);
                taskIds.AddRange(projectTaskIds);
            }
            else
            {
                taskIds.AddRange(await db.Tasks.Where(task => task.ProjectId == project.Id)
                    .Select(task => task.Id).ToListAsync(cancellationToken));
            }
        }
        var taskIdSet = taskIds.ToHashSet();

        IQueryable<TaskAssignee> targetAssignmentsQuery = db.TaskAssignees;
        if (acquireLocks && isSqlServer)
            targetAssignmentsQuery = db.TaskAssignees.FromSqlInterpolated($"SELECT * FROM task_assignees WITH (UPDLOCK,HOLDLOCK,INDEX(ix_task_assignees_user_status)) WHERE user_id = {memberId} AND status = 'active'");
        else
            targetAssignmentsQuery = targetAssignmentsQuery.Where(assignee => assignee.UserId == memberId && assignee.Status == "active");
        var targetAssignments = await targetAssignmentsQuery.OrderBy(assignee => assignee.TaskId)
            .ToListAsync(cancellationToken);
        var targetAssignmentsInScope = targetAssignments.Where(assignment => taskIdSet.Contains(assignment.TaskId)).ToArray();
        var affectedTaskIds = targetAssignmentsInScope
            .Select(assignment => assignment.TaskId).Distinct().Order().ToArray();
        var unscannedAssignmentTaskIds = targetAssignments.Where(assignment => !taskIdSet.Contains(assignment.TaskId))
            .Select(assignment => assignment.TaskId).Distinct().ToArray();
        var projectIds = projectRows.Select(project => project.Id).ToArray();
        var hasUnseenTargetAssignment = unscannedAssignmentTaskIds.Length > 0 && await db.Tasks.AsNoTracking()
            .AnyAsync(task => unscannedAssignmentTaskIds.Contains(task.Id) && projectIds.Contains(task.ProjectId), cancellationToken);

        var tasks = affectedTaskIds.Length == 0
            ? []
            : await db.Tasks.Where(task => affectedTaskIds.Contains(task.Id))
                .OrderBy(task => task.ProjectId).ThenBy(task => task.Id).ToListAsync(cancellationToken);

        var assignmentRows = new List<TaskAssignee>();
        foreach (var affectedTaskId in affectedTaskIds.Order())
        {
            var assignmentQuery = acquireLocks && isSqlServer
                ? db.TaskAssignees.FromSqlInterpolated($"SELECT * FROM task_assignees WITH (UPDLOCK,HOLDLOCK,INDEX(uq_task_assignees)) WHERE task_id = {affectedTaskId} ORDER BY user_id")
                : db.TaskAssignees.Where(assignee => assignee.TaskId == affectedTaskId).OrderBy(assignee => assignee.UserId);
            assignmentRows.AddRange(await assignmentQuery.ToListAsync(cancellationToken));
        }
        var currentAssignments = assignmentRows.Where(assignee => assignee.Status == "active").ToArray();

        var projectStates = projectRows.Select(project =>
        {
            var projectMemberships = membershipRows.Where(member => member.ProjectId == project.Id).ToArray();
            var activeManagers = projectMemberships
                .Where(member => member.Status == "active" && member.Role == "PROJECT_MANAGER")
                .Where(member => relevantOrganizationMemberships.TryGetValue(member.UserId, out var organizationMember)
                    && organizationMember.Status == "active" && organizationMember.Role != "GUEST")
                .Where(member => users.TryGetValue(member.UserId, out var user) && user.Status == "active")
                .Select(member => member.UserId).Distinct().Order().ToArray();
            var candidates = projectMemberships.Where(member => member.Status == "active" && member.UserId != memberId)
                .Where(member => relevantOrganizationMemberships.TryGetValue(member.UserId, out var organizationMember)
                    && organizationMember.Status == "active" && organizationMember.Role != "GUEST")
                .Where(member => users.TryGetValue(member.UserId, out var user) && user.Status == "active")
                .Select(member => new ReplacementMember(member.UserId,
                    users[member.UserId].FirstName + " " + users[member.UserId].LastName))
                .OrderBy(candidate => candidate.UserId).ToArray();
            return new MemberRemovalProjectState(project, lifecycleByProject[project.Id], projectMemberships,
                projectMemberships.SingleOrDefault(member => member.UserId == memberId), activeManagers, candidates);
        }).OrderBy(project => project.Project.Id).ToArray();

        return new MemberRemovalState
        {
            OrganizationId = organizationId,
            MemberId = memberId,
            ActorId = actorId,
            CapturedNowUtc = capturedNowUtc,
            MemberOrganizationMembership = relevantOrganizationMemberships.GetValueOrDefault(memberId),
            ActorOrganizationMembership = relevantOrganizationMemberships.GetValueOrDefault(actorId),
            Projects = projectStates,
            Tasks = tasks,
            TargetActiveAssignments = targetAssignmentsInScope,
            TaskAssignmentRows = assignmentRows,
            ActiveTaskAssignments = currentAssignments,
            OrganizationMemberships = relevantOrganizationMemberships,
            Users = users,
            HasUnseenTargetAssignment = hasUnseenTargetAssignment
        };
    }

    public static string Lifecycle(Project project, DateTime capturedNowUtc)
    {
        if (project.DeletedAt is not null)
            return project.DeletedAt.Value <= capturedNowUtc.AddDays(-30)
                ? "EXPIRED_TRASH_PENDING_PURGE" : "TRASHED_WITHIN_RETENTION";
        return project.ArchivedAt is null ? "ACTIVE" : "ARCHIVED";
    }

    public static bool IsEligible(MemberRemovalState state, Guid projectId, Guid userId)
    {
        var project = state.Projects.SingleOrDefault(item => item.Project.Id == projectId);
        return userId != state.MemberId && project is not null
            && project.Memberships.Any(member => member.UserId == userId && member.Status == "active")
            && state.OrganizationMemberships.TryGetValue(userId, out var organizationMember)
            && organizationMember.Status == "active" && organizationMember.Role != "GUEST"
            && state.Users.TryGetValue(userId, out var user) && user.Status == "active";
    }

    public static MemberRemovalValidationError? ValidateResolutions(MemberRemovalState state,
        IReadOnlyList<MemberRemovalTaskState> affectedTasks, IReadOnlyCollection<MemberTaskResolution> resolutions,
        out IReadOnlyDictionary<Guid, MemberTaskResolution>? validated)
    {
        validated = null;
        if (resolutions.Any(item => item is null))
            return new(StatusCodes.Status400BadRequest, "MEMBER_RESOLUTION_INVALID",
                "Each task resolution must include a task ID and an action.");
        var expectedTasks = affectedTasks.Where(item => item.Project.Lifecycle != "EXPIRED_TRASH_PENDING_PURGE").ToArray();
        var supplied = resolutions.ToArray();
        if (supplied.Select(item => item.TaskId).Distinct().Count() != supplied.Length)
            return new(StatusCodes.Status400BadRequest, "MEMBER_RESOLUTION_INVALID",
                "A task may appear only once in the resolution list.");
        var expectedIds = expectedTasks.Select(item => item.Task.Id).ToHashSet();
        if (supplied.Any(item => !expectedIds.Contains(item.TaskId)))
            return new(StatusCodes.Status400BadRequest, "MEMBER_RESOLUTION_INVALID",
                "The resolution list contains a task that is not in the current preview.");
        if (supplied.Length != expectedIds.Count)
            return new(StatusCodes.Status400BadRequest, "MEMBER_RESOLUTION_REQUIRED",
                "Provide exactly one resolution for every affected open task.");

        var map = supplied.ToDictionary(item => item.TaskId);
        foreach (var affected in expectedTasks)
        {
            var resolution = map[affected.Task.Id];
            if (affected.Project.Lifecycle == "ACTIVE")
            {
                if (resolution.Action == "UNASSIGN" && resolution.ReplacementUserId is null) continue;
                if (resolution.Action != "REASSIGN" || resolution.ReplacementUserId is null)
                    return new(StatusCodes.Status400BadRequest, "MEMBER_RESOLUTION_INVALID",
                        "Active projects require REASSIGN with an eligible replacement, or UNASSIGN with no replacement.");
                if (!IsEligible(state, affected.Project.Project.Id, resolution.ReplacementUserId.Value))
                    return new(StatusCodes.Status409Conflict, "MEMBER_REMOVAL_REPLACEMENT_INELIGIBLE",
                        "The replacement must be an active, non-guest project member. Refresh the preview and choose another member.");
            }
            else if (resolution.Action != "ACCEPT_LIFECYCLE_INACTIVATION" || resolution.ReplacementUserId is not null)
                return new(StatusCodes.Status400BadRequest, "MEMBER_RESOLUTION_INVALID",
                    "Archived or retained Trash projects require ACCEPT_LIFECYCLE_INACTIVATION and do not accept replacements.");
        }
        validated = map;
        return null;
    }

    public static async Task<IReadOnlyList<AssignmentEmailRecipient>> ApplyResolutionsAsync(PmsDbContext db,
        MemberRemovalState state, IReadOnlyList<MemberRemovalTaskState> affectedTasks,
        IReadOnlyDictionary<Guid, MemberTaskResolution> resolutions,
        ClaimsPrincipal actor, HttpRequest request, Guid operationId, CancellationToken cancellationToken)
    {
        var notifications = new List<AssignmentEmailRecipient>();
        foreach (var affected in affectedTasks)
        {
            var resolution = resolutions[affected.Task.Id];
            var lifecycle = affected.Project.Lifecycle;
            var replacementUserId = resolution.Action == "REASSIGN" ? resolution.ReplacementUserId : null;
            var action = lifecycle == "ACTIVE"
                ? resolution.Action == "REASSIGN" ? "REASSIGNED" : "UNASSIGNED"
                : "LIFECYCLE_INACTIVATED";
            var reasonCode = action == "LIFECYCLE_INACTIVATED" ? lifecycle switch
            {
                "ARCHIVED" => "PROJECT_ARCHIVED",
                "TRASHED_WITHIN_RETENTION" => "PROJECT_TRASHED",
                "EXPIRED_TRASH_PENDING_PURGE" => "PROJECT_TRASH_EXPIRED",
                _ => throw new InvalidOperationException("Unexpected lifecycle for assignment inactivation.")
            } : null;

            affected.TargetAssignment.Status = "inactive";
            if (replacementUserId is Guid replacementId)
            {
                var replacementAssignment = state.TaskAssignmentRows.SingleOrDefault(item =>
                    item.TaskId == affected.Task.Id && item.UserId == replacementId);
                if (replacementAssignment is null)
                {
                    replacementAssignment = new TaskAssignee
                    {
                        Id = Guid.NewGuid(), TaskId = affected.Task.Id, UserId = replacementId,
                        AssignedAt = state.CapturedNowUtc, Status = "active"
                    };
                    db.TaskAssignees.Add(replacementAssignment);
                    AddAssignmentNotification(db, replacementId, affected.Task);
                    if (state.Users.TryGetValue(replacementId, out var replacementUser))
                        notifications.Add(new AssignmentEmailRecipient(replacementUser.Email, replacementUser.FirstName,
                            affected.Task.Title, affected.Project.Project.Id, affected.Task.Id));
                }
                else if (replacementAssignment.Status != "active")
                {
                    replacementAssignment.Status = "active";
                    replacementAssignment.AssignedAt = state.CapturedNowUtc;
                    AddAssignmentNotification(db, replacementId, affected.Task);
                    if (state.Users.TryGetValue(replacementId, out var replacementUser))
                        notifications.Add(new AssignmentEmailRecipient(replacementUser.Email, replacementUser.FirstName,
                            affected.Task.Title, affected.Project.Project.Id, affected.Task.Id));
                }
            }

            db.TaskAssignmentEvents.Add(new TaskAssignmentEvent
            {
                EventId = StableEventId(operationId, affected.Task.Id),
                OperationId = operationId,
                OrganizationId = state.OrganizationId,
                ProjectId = affected.Project.Project.Id,
                TaskId = affected.Task.Id,
                DepartingUserId = state.MemberId,
                ReplacementUserId = replacementUserId,
                ActorUserId = state.ActorId,
                OccurredAtUtc = state.CapturedNowUtc,
                Action = action,
                ReasonCode = reasonCode
            });

            var actionLabel = action switch
            {
                "REASSIGNED" => "reassigned",
                "UNASSIGNED" => "unassigned",
                _ => "inactivated"
            };
            var targetName = state.Users.TryGetValue(state.MemberId, out var targetUser)
                ? $"{targetUser.FirstName} {targetUser.LastName}" : "the member";
            await ActivityRecorder.RecordAsync(db, actor, request, state.OrganizationId, "Tasks",
                "task.assignment_" + action.ToLowerInvariant(), "task", affected.Task.Id,
                affected.Task.Title,
                $"{actionLabel} {targetName}'s assignment on task \"{affected.Task.Title}\"",
                cancellationToken, affected.Project.Project.Id);
        }
        return notifications;
    }

    public static async Task ApplyExpiredTrashCleanupAsync(PmsDbContext db, MemberRemovalState state,
        IReadOnlyList<MemberRemovalTaskState> affectedTasks, ClaimsPrincipal actor, HttpRequest request,
        Guid operationId, CancellationToken cancellationToken)
    {
        foreach (var affected in affectedTasks.Where(item => item.Project.Lifecycle == "EXPIRED_TRASH_PENDING_PURGE"))
        {
            affected.TargetAssignment.Status = "inactive";
            db.TaskAssignmentEvents.Add(new TaskAssignmentEvent
            {
                EventId = StableEventId(operationId, affected.Task.Id),
                OperationId = operationId,
                OrganizationId = state.OrganizationId,
                ProjectId = affected.Project.Project.Id,
                TaskId = affected.Task.Id,
                DepartingUserId = state.MemberId,
                ReplacementUserId = null,
                ActorUserId = state.ActorId,
                OccurredAtUtc = state.CapturedNowUtc,
                Action = "LIFECYCLE_INACTIVATED",
                ReasonCode = "PROJECT_TRASH_EXPIRED"
            });
            var targetName = state.Users.TryGetValue(state.MemberId, out var targetUser)
                ? $"{targetUser.FirstName} {targetUser.LastName}" : "the member";
            await ActivityRecorder.RecordAsync(db, actor, request, state.OrganizationId, "Tasks",
                "task.assignment_lifecycle_inactivated", "task", affected.Task.Id,
                affected.Task.Title,
                $"inactivated {targetName}'s assignment because project Trash retention expired",
                cancellationToken, affected.Project.Project.Id);
        }
    }

    // Completed and task-trashed assignment rows are historical attribution, not a
    // resolution prompt. Inactivate them when removing the member so restoring the
    // membership later cannot make an old assignment effective again.
    public static async Task ApplyHistoricalAttributionInactivationAsync(PmsDbContext db,
        MemberRemovalState state, ClaimsPrincipal actor, HttpRequest request, Guid operationId,
        CancellationToken cancellationToken)
    {
        foreach (var historical in state.HistoricalAssignmentsToInactivate)
        {
            historical.TargetAssignment.Status = "inactive";
            db.TaskAssignmentEvents.Add(new TaskAssignmentEvent
            {
                EventId = StableEventId(operationId, historical.Task.Id),
                OperationId = operationId,
                OrganizationId = state.OrganizationId,
                ProjectId = historical.Project.Project.Id,
                TaskId = historical.Task.Id,
                DepartingUserId = state.MemberId,
                ReplacementUserId = null,
                ActorUserId = state.ActorId,
                OccurredAtUtc = state.CapturedNowUtc,
                Action = "UNASSIGNED"
            });
            var targetName = state.Users.TryGetValue(state.MemberId, out var targetUser)
                ? $"{targetUser.FirstName} {targetUser.LastName}" : "the member";
            await ActivityRecorder.RecordAsync(db, actor, request, state.OrganizationId, "Tasks",
                "task.assignment_unassigned", "task", historical.Task.Id, historical.Task.Title,
                $"inactivated {targetName}'s historical assignment on task \"{historical.Task.Title}\"",
                cancellationToken, historical.Project.Project.Id);
        }
    }

    public static void AddRemovalAudit(PmsDbContext db, MemberRemovalState state, Guid operationId,
        string action, string targetType, Guid targetId, string reason)
    {
        var actor = state.Users.GetValueOrDefault(state.ActorId);
        var target = state.Users.GetValueOrDefault(targetId);
        db.AdminAuditEvents.Add(new AdminAuditEvent
        {
            Id = Guid.NewGuid(), ActorId = state.ActorId,
            ActorDisplayName = actor is null ? "Workspace administrator" : $"{actor.FirstName} {actor.LastName}",
            Action = action, TargetType = targetType, TargetId = targetId,
            TargetDisplayName = target is null ? "Workspace member" : $"{target.FirstName} {target.LastName}",
            Outcome = "succeeded", Reason = reason.Length > 500 ? reason[..500] : reason,
            CorrelationId = operationId.ToString("N"), OccurredAt = new DateTimeOffset(state.CapturedNowUtc, TimeSpan.Zero)
        });
    }

    public static void AddAssignmentNotification(PmsDbContext db, Guid userId, WorkTask task) =>
        db.Notifications.Add(new Notification
        {
            Id = Guid.NewGuid(), UserId = userId, Type = "TASK_ASSIGNED",
            Message = $"You were assigned to {task.Title}.", EntityType = "TASK", RelatedId = task.Id
        });

    public static void AddLegacyRemovalHistory(PmsDbContext db,
        IEnumerable<(TaskAssignee Assignment, WorkTask Task, Guid ProjectId)> assignments,
        Guid organizationId, Guid memberId, Guid actorId, DateTime occurredAtUtc, Guid operationId)
    {
        foreach (var item in assignments)
        {
            item.Assignment.Status = "inactive";
            db.TaskAssignmentEvents.Add(new TaskAssignmentEvent
            {
                EventId = StableEventId(operationId, item.Task.Id),
                OperationId = operationId,
                OrganizationId = organizationId,
                ProjectId = item.ProjectId,
                TaskId = item.Task.Id,
                DepartingUserId = memberId,
                ActorUserId = actorId,
                OccurredAtUtc = occurredAtUtc,
                Action = "UNASSIGNED"
            });
        }
    }

    public static string CreateSnapshotHash(MemberRemovalState state, Guid? projectScopeId)
    {
        var payload = new SnapshotPayload(
            projectScopeId is null ? "ORGANIZATION_MEMBER_DEACTIVATION" : "PROJECT_MEMBER_REMOVAL",
            state.OrganizationId, projectScopeId, state.MemberId,
            state.MemberOrganizationMembership?.Role, state.MemberOrganizationMembership?.Status,
            state.ActorId, state.ActorOrganizationMembership?.Role, state.ActorOrganizationMembership?.Status,
            state.Projects.Where(project => projectScopeId is null || project.Project.Id == projectScopeId)
                .Select(project => new SnapshotProject(project.Project.Id, project.Lifecycle,
                    project.Project.OwnerId, UtcTicks(project.Project.DeletedAt), UtcTicks(project.Project.ArchivedAt),
                    project.Memberships.OrderBy(member => member.UserId).Select(member =>
                        new SnapshotMembership(member.UserId, member.Role, member.Status,
                            state.OrganizationMemberships.GetValueOrDefault(member.UserId)?.Role,
                            state.OrganizationMemberships.GetValueOrDefault(member.UserId)?.Status,
                            state.Users.GetValueOrDefault(member.UserId)?.Status)).ToArray(),
                    project.ActiveManagerIds,
                    project.EligibleReplacementMembers.Select(candidate => candidate.UserId).Order().ToArray(),
                    state.AllAssignedTasks.Where(task => task.Project.Project.Id == project.Project.Id)
                        .Select(task => new SnapshotTask(task.Task.Id, task.Task.Status, UtcTicks(task.Task.UpdatedAt),
                            task.CurrentAssignments.OrderBy(assignment => assignment.UserId).Select(assignment =>
                                new SnapshotAssignment(assignment.Id, assignment.UserId, assignment.Status,
                                    UtcTicks(assignment.AssignedAt))).ToArray(), UtcTicks(task.Task.DeletedAt),
                            project.Lifecycle switch
                            {
                                "ARCHIVED" => "PROJECT_ARCHIVED",
                                "TRASHED_WITHIN_RETENTION" => "PROJECT_TRASHED",
                                "EXPIRED_TRASH_PENDING_PURGE" => "PROJECT_TRASH_EXPIRED",
                                _ => null
                            })).OrderBy(task => task.TaskId).ToArray()))
                .OrderBy(project => project.ProjectId).ToArray());
        var bytes = SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(payload, SnapshotJson));
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
        catch (FormatException) { return false; }
    }

    public static Guid StableEventId(Guid operationId, Guid taskId)
    {
        Span<byte> input = stackalloc byte[32];
        operationId.TryWriteBytes(input[..16]);
        taskId.TryWriteBytes(input[16..]);
        Span<byte> digest = stackalloc byte[32];
        SHA256.HashData(input, digest);
        return new Guid(digest[..16]);
    }

    private static long? UtcTicks(DateTime? value) => value is null ? null : UtcTicks(value.Value);
    private static long UtcTicks(DateTime value) => value.ToUniversalTime().Ticks;

    private static async Task<List<OrganizationMember>> QueryOrganizationMemberships(PmsDbContext db,
        Guid organizationId, IReadOnlyCollection<Guid> userIds, bool acquireLocks, CancellationToken cancellationToken)
    {
        var rows = new List<OrganizationMember>();
        foreach (var userId in userIds.Order())
        {
            var query = acquireLocks
                ? db.OrganizationMembers.FromSqlInterpolated($"SELECT * FROM organization_members WITH (UPDLOCK,HOLDLOCK,INDEX(uq_organization_members)) WHERE organization_id = {organizationId} AND user_id = {userId}")
                : db.OrganizationMembers.Where(member => member.OrganizationId == organizationId && member.UserId == userId);
            var row = await query.SingleOrDefaultAsync(cancellationToken);
            if (row is not null) rows.Add(row);
        }
        return rows;
    }

    private sealed record SnapshotPayload(string Operation, Guid OrganizationId, Guid? ProjectScopeId,
        Guid TargetMemberId, string? TargetOrganizationRole, string? TargetOrganizationStatus,
        Guid ActorId, string? ActorOrganizationRole, string? ActorOrganizationStatus,
        IReadOnlyList<SnapshotProject> Projects);
    private sealed record SnapshotProject(Guid ProjectId, string Lifecycle, Guid OwnerId,
        long? DeletedAtUtcTicks, long? ArchivedAtUtcTicks, IReadOnlyList<SnapshotMembership> Memberships,
        IReadOnlyList<Guid> ActiveManagerIds, IReadOnlyList<Guid> EligibleReplacementIds,
        IReadOnlyList<SnapshotTask> Tasks);
    private sealed record SnapshotMembership(Guid UserId, string Role, string Status,
        string? OrganizationRole, string? OrganizationStatus, string? AccountStatus);
    private sealed record SnapshotTask(Guid TaskId, string Status, long UpdatedAtUtcTicks,
        IReadOnlyList<SnapshotAssignment> ActiveAssignments, long? DeletedAtUtcTicks, string? LifecycleReason);
    private sealed record SnapshotAssignment(Guid AssignmentId, Guid UserId, string Status, long AssignedAtUtcTicks);
}

public sealed record AssignmentEmailRecipient(string Email, string FirstName, string TaskTitle,
    Guid ProjectId, Guid TaskId);
