# Slice 3 — Member Removal and Open-Task Resolution Scope Review

**Status:** Backend implementation complete; awaiting implementation review (2026-10-08)
**Date:** 2026-10-08
**Depends on:** Accepted Slice 1 authorization/invariants and Slice 2 ownership transfer
**Product decisions:** [Owner decision record](product-improvements-owner-decisions.md)
**Assignment proposal:** [Project assignment and ownership](product-improvements-project-assignment.md)
**Pre-implementation review:** [Product improvements pre-implementation review](product-improvements-pre-implementation-review.md)

## Objective

Make project-member removal and organization-member deactivation resolve open task assignments safely, across every affected project, while preserving historical task attribution and the owner/active-manager safeguards established in Slices 1 and 2.

The product owner approved the backend-only Slice 3 implementation on 2026-10-08. This scope excludes client changes, commits, pushes, deployment, and all later slices.

## Proposed scope

1. **Project-member removal:** Preview the target member's affected open tasks. In active, non-archived projects, require an explicit resolution for each affected task: reassign only that member's assignment to an eligible active project member, or leave that member's responsibility unassigned. Preserve all other eligible task assignees. Do not silently clear assignments.
2. **Organization-member deactivation:** Gather affected active, archived, and trashed-within-retention projects and open tasks first. Require task resolutions across all affected projects and validate every retained project's owner and active-manager invariant before making writes. If any project fails validation, make no membership, assignment, audit, activity, or token changes.
3. **Historical attribution:** Treat `REVIEW` as open and require its assignment to be resolved in active projects. Treat `DONE` as complete: preserve its historical attribution and do not require a task resolution. On member removal, completed or task-trashed active assignment rows are inactivated automatically while retaining their original task/user attribution; a typed `UNASSIGNED` event prevents membership restoration from making them effective again. Record new resolution events with typed task, departing member, optional replacement member, actor, timestamp, action, and organization/project identifiers. Events are append-only during the applicable retention period, tenant-scoped, and retrievable only by users authorized to access the project/task history.
4. **Atomic persistence:** Apply assignment resolution, assignment inactivation, membership deactivation, token revocation where currently part of the operation, and database audit/activity records in one transaction. Publish realtime events and send external notifications only after successful commit.
5. **Concurrency:** Recheck membership status, task status/assignment, recipient eligibility, owner identity, and active-manager counts within the write transaction. Return stable conflicts on stale requests; do not partially apply multi-project deactivation.

## Product rules already approved

- Every active, archived, or trashed-within-retention project retains the approved eligible active-manager invariant. The existing server-side definition from Slice 1 remains authoritative; permanent/expired Trash is logically unavailable and exempt from owner/manager blockers during organization deactivation cleanup.
- A project owner must complete ownership transfer before their membership can be removed or deactivated. Slice 2's transfer operation does not implicitly transfer ownership as a side effect of member deactivation.
- Tasks support multiple assignees. Resolve only the departing member's assignment; preserve the task's other eligible assignees.
- `REVIEW` is open. `DONE` is complete and keeps historical task/user attribution without requiring client resolution. Closed or task-trashed assignments are made inactive on membership removal so reactivation does not restore effective assignment access.
- Explicitly leaving the departing member's responsibility unassigned is allowed even when no replacement is selected. It does not remove other assignees.
- Completed-task attribution is preserved; membership restoration does not restore old assignments.
- Organization deactivation is all-or-nothing across affected projects.
- Active, non-archived projects use explicit per-task `REASSIGN` or `UNASSIGN` resolutions.
- Archived projects and trashed projects within the 30-day retention window allow membership removal but do not create or reactivate task assignments. For open assignments, only an explicit lifecycle-inactivation choice is allowed; the preview and confirmation identify the project lifecycle, affected tasks, and server-recorded reason (`PROJECT_ARCHIVED` or `PROJECT_TRASHED`). The persisted history action is `LIFECYCLE_INACTIVATED` with that reason. Existing assignment history is preserved until the applicable purge.
- A trashed project expires at `DeletedAt <= capturedNowUtc - 30 days`, matching the purger boundary. Expired projects are unavailable to direct member-management routes. Organization deactivation reports expired projects separately, automatically inactivates the departing member's open-task assignments and project membership in the same transaction, adds `LIFECYCLE_INACTIVATED` history with reason `PROJECT_TRASH_EXPIRED`, creates no replacement, and is not blocked by stale owner/manager state in those logically unavailable projects. The preview makes this side effect visible; expired cleanup tasks count toward the 100-task cap.
- Permanently purged projects are not operable. Their assignment-history rows are purged with task/project content.
- Ownership and active-manager invariants apply to every project still within retention, including archived and trashed projects. A project owner must transfer ownership before removal; removing a member must not leave a retained project without an active manager.
- Server checks are authoritative; client preview data may be stale and must be revalidated on submit.

## Read-only technical findings

### Historical attribution

The current model cannot reliably answer all approved history questions:

- `TaskAssignee` stores `TaskId`, `UserId`, `AssignedAt` for the current/most recent active assignment cycle, and current `Status`. Task update resets `AssignedAt` when an inactive row is reactivated. It has no deactivation timestamp, acting user, resolution outcome, or replacement user. Its unique `(TaskId, UserId)` key means reactivation reuses a row and overwrites the previous cycle's assignment time.
- `ActivityEvent` stores task/entity ID, organization/project, actor ID, and event time. Existing assignment changes identify the departing user and replacement, if any, only in a human-readable `Description`; they do not provide stable typed user IDs or an outcome field. The general activity endpoint is tenant/project filtered, but free-text descriptions are not a reliable assignment-history contract.
- Existing inactive assignment rows cannot be backfilled with an accurate deactivation time, actor, or reassignment outcome from the current schema. Preserve them and label those facts unknown; do not synthesize history from display names or timestamps unrelated to deactivation.

**Superseded proposal — do not implement:** add nullable `details_json NVARCHAR(MAX)` to append-only `activity_events`, then record versioned structured details for assignment lifecycle actions. Existing columns already provide `organization_id`, `project_id`, `entity_id` (task), `actor_user_id`, `action`, and `created_at_utc`; JSON details would carry `assigneeUserId`, `outcome` (`REASSIGNED`, `UNASSIGNED`, `MEMBERSHIP_REVOKED`, or `ASSIGNED`), and nullable `replacementUserId`. Add a task assignment-history read endpoint that filters by the same active membership/project authorization as task reads and returns structured events; do not expose events across tenants. Update task create/update, membership-removal, and organization-deactivation writers so each new assignment lifecycle change records a typed event in the same transaction. `TaskAssignee` remains the current effective-assignment state, and events are append-only history. This proposal is superseded by the dedicated-table decision below.

**Retention finding (owner decision applied):** task/project purge removes assignment rows but leaves `ActivityEvent` rows. Therefore structured assignment history belongs in the dedicated table, not in `ActivityEvent`. The purger must remove assignment-history children with task/project content in the same database transaction; existing generic activity retention remains unchanged. No legacy assignment facts are backfilled.

## Superseding owner decisions (2026-10-08)

These decisions supersede conflicting proposals elsewhere in this document. The proposed request/response, history schema, and error contract is in [`docs/member-removal-resolution-api-contract.md`](member-removal-resolution-api-contract.md).

- **Structured history:** The owner approved a dedicated assignment-history table/migration. Each append-only event records EventId, OperationId, organization, project, task, departing member, optional replacement, actor, UTC time, action (`REASSIGNED`, `UNASSIGNED`, or `LIFECYCLE_INACTIVATED`), and server-derived reason where applicable. Writes share a transaction with assignments, memberships, audit, and activity. Legacy rows remain incomplete; no facts are backfilled or inferred.
- **Retention:** Keep assignment events append-only while retained. Delete them with task/project content at permanent purge in the same database transaction. Do not add an indefinite-retention exception. Foreign keys use `NO ACTION` so purge explicitly removes child history first.
- **Lifecycle:** Active projects require explicit per-task reassignment/unassignment. Archived and trashed-within-30-day-retention projects require explicit lifecycle-inactivation acceptance and create no replacement assignments. Expired Trash is logically unavailable: direct project operations return not found, but organization deactivation reports it separately and automatically inactivates the target's open assignments/membership with reason `PROJECT_TRASH_EXPIRED`; it does not require task-level resolutions and does not block on that expired project's owner/manager state. Retained projects still enforce owner/manager invariants. Purged projects are not operable.
- **Limits:** The 100 affected-assignment cap and 64-KiB confirmation-body limit are enforced in application code. Tests cover the exact byte limit, streamed oversized bodies, 100 accepted affected assignments, and 101 rejected. One SQL Server 100-task confirm measured 3,683 ms. Verify the deployed proxy limit before release.
- **Concurrency:** `snapshotHash` remains a canonical server-derived freshness precondition, not a lock or authorization credential. Confirmation reauthorizes and revalidates in serializable SQL Server transactions. Actual EF key-range locking was inspected: the affected-assignee index reported `RangeS-U`. The opt-in SQL suite also exercised task-creation/removal, competing confirmations, organization deactivation, owner/manager/deactivation races; the full results are recorded below. Deadlock-retry exhaustion was not fault-injected.
- **History access:** Assignment events are retrievable only through the same tenant and project/task authorization that protects the underlying task history. Do not widen archived/trashed project read access as part of this slice.

### API contract proposal (see the shared contract; older draft below is superseded)

The following additive backend routes are authorized. Existing `DELETE` routes remain compatible for members with no unresolved open assignments; when resolution is required they return a stable `409` and direct the caller to preview/confirm. No existing response body changes are proposed.

**Preview project-member removal**

```http
GET /api/v1/projects/{projectId}/members/{userId}/removal-preview
```

Returns a read-only snapshot with `projectId`, `organizationId`, `memberId`, `snapshotHash`, affected open tasks and eligible replacement candidates. It also lists completed or task-Trash assignment rows that will be inactivated automatically to prevent membership restoration from making them effective again. `DONE` tasks are excluded from required resolutions; `REVIEW` and other non-`DONE` statuses are included. The route performs no writes or events.

**Confirm project-member removal**

```http
POST /api/v1/projects/{projectId}/members/{userId}/remove
Content-Type: application/json

{
  "snapshotHash": "<base64url-sha256 from preview>",
  "resolutions": [
    { "taskId": "<guid>", "action": "REASSIGN", "replacementUserId": "<eligible-member-guid>" },
    { "taskId": "<guid>", "action": "UNASSIGN", "replacementUserId": null }
  ]
}
```

Returns `204 No Content` only after all submitted resolutions, membership removal, audit/activity, and assignment-history events commit atomically. `REASSIGN` changes only the departing member's assignment; other active assignees remain. `UNASSIGN` inactivates only that member's effective assignment. Duplicate, missing, extra, or mismatched resolution IDs are rejected.

**Preview organization-member deactivation**

```http
GET /api/v1/organizations/{organizationId}/members/{userId}/deactivation-preview
```

Returns the same snapshot concepts across all affected projects, including project IDs, tasks, current assignees, and candidates grouped by project. It also reports owner-transfer and active-manager blockers before confirm. The route is read-only.

**Confirm organization-member deactivation**

```http
POST /api/v1/organizations/{organizationId}/members/{userId}/deactivate
```

Uses the same request body as project-member removal. An empty `resolutions` array is valid only when the current preview has no open assignments. On success, task resolutions, assignment history, project-membership deactivation, organization-membership deactivation, refresh-token revocation, and existing audit/activity actions commit in one transaction. A project owner must first be transferred with the Slice 2 endpoint; this route never transfers ownership implicitly.

**Snapshot precondition:** preview returns `snapshotHash`, a base64url SHA-256 digest over a canonical, sorted representation of operation/scope/target, target membership state, project owner/lifecycle/active-manager identities, affected task IDs/status/`UpdatedAt`, active assignee IDs/status/`AssignedAt`, and eligible replacement IDs. It is a freshness precondition, not an authorization credential. It has no expiry requirement: at confirm, recompute it inside the SQL Server transaction and require an exact match; independently reauthorize the actor and validate every task, replacement, owner, and manager invariant. Any relevant state change returns `409` and requires a fresh preview. A retry reuses the same hash and resolution set; it must never discover new tasks and silently apply an unreviewed resolution.

Preview response shape:

```json
{
  "projectId": "<guid-or-null-for-organization-scope>",
  "organizationId": "<guid>",
  "memberId": "<guid>",
  "snapshotHash": "<base64url-sha256>",
  "affectedProjects": [
    {
      "projectId": "<guid>",
      "ownerTransferRequired": false,
      "managerInvariantBlocked": false,
      "eligibleReplacementMembers": [
        { "userId": "<guid>", "displayName": "<name>" }
      ],
      "tasks": [
        {
          "taskId": "<guid>",
          "parentTaskId": "<guid-or-null>",
          "title": "<title>",
          "status": "REVIEW",
          "currentAssigneeIds": ["<departing-member-guid>", "<other-member-guid>"]
        }
      ]
    }
  ]
}
```

Project scope returns one `affectedProjects` entry. Organization scope returns all affected projects. The exact response envelope must be shared by both preview routes and documented before implementation.

All new-route errors use the existing `{ "code": "...", "message": "..." }` JSON envelope. Existing `DELETE` calls that encounter open assignments retain their existing codes (`project_member_open_tasks_require_resolution` and `organization_member_open_tasks_require_resolution`) and return `409`; the new message directs callers to preview/confirm. New-route codes proposed:

| HTTP | Code | Meaning |
|---|---|---|
| 400 | `MEMBER_RESOLUTION_REQUIRED` | Missing or malformed per-task decisions. |
| 400 | `MEMBER_RESOLUTION_INVALID` | Duplicate, extra, or non-affected task IDs; invalid action/payload combination. |
| 403 | `MEMBER_REMOVAL_FORBIDDEN` | Caller lacks current organization/project authority. |
| 404 | `MEMBER_NOT_FOUND` | Target not active in the caller's authorized scope. |
| 409 | `MEMBER_REMOVAL_PREVIEW_STALE` | Task set/status/assignment or relevant scope changed since preview. |
| 409 | `PROJECT_OWNER_TRANSFER_REQUIRED` | Target remains accountable owner of an affected project. |
| 409 | `PROJECT_MUST_RETAIN_MANAGER` | Resolution/removal would leave a project without an eligible active manager. |
| 409 | `MEMBER_REMOVAL_REPLACEMENT_INELIGIBLE` | Replacement is no longer an active eligible member of that project. |
| 409 | `MEMBER_REMOVAL_CONFLICT` | Bounded SQL Server transient retries exhausted; caller must refresh and retry. |
| 413 | `REQUEST_BODY_TOO_LARGE` | Confirmation body exceeds the endpoint's 64-KiB limit. |
| 422 | `MEMBER_RESOLUTION_LIMIT_EXCEEDED` | More than 100 affected assignment rows; there is no partial operation. |

The stable codes and response envelope are specified in the shared API contract and must be implemented as written.

### Request and response bounds

The deployed proxy request limit is not available from repository configuration. The endpoints enforce **100 affected assignment rows** and the confirmation middleware enforces **64 KiB**. Preview and confirm return `422 MEMBER_RESOLUTION_LIMIT_EXCEEDED` without partial writes when more than 100 rows would change. The 64-KiB middleware has known-length, streamed, exact-boundary, and unrelated-route tests. Proxy-side verification remains a release check.

The 100-row operation was measured against SQL Server using the actual EF confirmation path. One isolated run completed in 3,683 ms; this is a single acceptance measurement, not a production performance distribution. Application body limits are effective and tested; the deployed proxy limit remains unknown and must be checked before release.

## Proposed SQL Server transaction and locking strategy

Both confirm routes run under the configured EF SQL Server execution strategy and one `SERIALIZABLE` transaction. The configured retry policy allows at most six retries; Slice 3 caps the total request at 30 seconds across all attempts and retry waits, with retry exhaustion mapped to a stable `409`. Each retry clears tracked state and reruns the request against the original preview token and resolution body. If the snapshot is stale, stop with `409`; never refresh the resolution list automatically. Deadlock/retry exhaustion was not fault-injected in this checkpoint.

Within the transaction:

1. Acquire organization and actor/target organization-membership rows in `(organization_id,user_id)` order; perform preliminary tenant-scoped authorization.
2. Read and lock affected project rows in ascending ID order, including active, archived, and trashed-within-retention projects. Then reauthorize the actor and target against the locked state, verify the target is not `OwnerId`, and compute the active-manager count using the Slice 1 predicate. If any invariant fails, abort before writes. For Trash rows at or past the captured 30-day deadline, exclude them from retained-project invariants and ordinary resolutions. In organization deactivation, visibly include their cleanup in the snapshot and atomically inactivate the target membership/assignments with `PROJECT_TRASH_EXPIRED`; do not create replacement assignments.
3. Recompute affected open assignment set and snapshot. Require a one-to-one match between preview task IDs and supplied resolution IDs; confirm `REVIEW` remains open and `DONE` requires no reassignment.
4. Validate each replacement against active project membership, active non-guest organization membership, active account, and project scope. Preserve all other assignees. Archived/trashed-within-retention projects accept no new or reactivated task assignments and permit only explicit lifecycle inactivation. Expired Trash is handled only by the separate organization-deactivation cleanup described above.
5. Apply assignment inactivation, replacement assignment creation/reactivation for active projects only, structured history and existing audit/activity records, membership deactivation, and refresh-token revocation (organization removal) in the same transaction. Append one typed history event per departing assignment: `REASSIGNED`, `UNASSIGNED`, or `LIFECYCLE_INACTIVATED`, with stable event ID, operation ID, typed scope, actor/time, replacement when applicable, and server-derived lifecycle reason. Delete these history rows with their associated task/project purge.
6. Save once, commit, then publish project/organization realtime events. Send no notification to ineligible users. Rollback leaves no state or event records.

SQL Server `SERIALIZABLE` uses the named indexes for organization/project membership, task rows, and target-assignee ranges. A SQL Server test ran the actual EF load-state query in a serializable transaction and observed `RangeS-U` on `ix_task_assignees_user_status`. A concurrent task-create/removal test and competing-confirmation test also passed. No additional index migration was needed.

The Slice 3 confirmation lock order is organization membership, project rows, project membership and eligible users, task rows, target-assignee range, task-specific assignment rows, then event/audit/activity inserts. Project removal reads the organization ID before opening its transaction so it can follow that order. Owner-transfer and other task-write paths retain their existing entry order; overlap races were exercised with SQL Server and passed using bounded retry/revalidation. This does not establish that every unrelated route is globally deadlock-free.

## Required SQL Server race cases

- A task is created for, or newly assigned to, the departing member after preview: one operation serializes; confirm either covers the assignment represented by the snapshot or returns `MEMBER_REMOVAL_PREVIEW_STALE` without partial writes.
- A task moves `REVIEW` to `DONE` after preview: confirm returns stale and does not silently ignore it; a fresh preview then omits it from required resolutions.
- A replacement becomes inactive, suspended, a guest, or leaves the project after preview: confirm returns `MEMBER_REMOVAL_REPLACEMENT_INELIGIBLE`; no removal commits.
- Actor/target organization or project membership changes after preview, including guest demotion and member deactivation: confirmation reauthorizes and revalidates under locks, then either commits in a valid serial order or returns a stable forbidden/stale conflict without partial writes.
- Ownership transfer races with removal/deactivation: final project owner remains eligible and removal requires fresh preview/decision as applicable.
- Two admins attempt overlapping project removals or organization deactivations: only a serializable valid order commits; no duplicate resolution/history/audit, managerless project, or partial organization state.
- Deadlock/retry exhaustion returns a stable `409`; retry never applies task assignments discovered after the submitted preview.

All cases use isolated SQL Server scratch databases and assert final task-assignee/history, membership, owner/manager, audit/activity, and post-commit event state. SQLite remains useful for fast rule tests but is not evidence for SQL Server range-lock behavior.

## Acceptance criteria for Slice 3

1. A read-only preview identifies affected open tasks and eligible reassignment candidates within the caller's tenant and authorized project scope.
2. Project removal and organization deactivation reject missing, duplicate, cross-tenant, stale, or ineligible resolution inputs with stable, documented errors.
3. The departing member's assignment is inactive after either explicit resolution; other assignees remain unchanged. A task has no effective assignee only when no eligible assignments remain. Original attribution remains queryable to authorized users.
4. Open-task resolution and member removal are atomic. For organization deactivation, a validation or persistence failure in any affected project leaves all projects and the organization membership unchanged.
5. Existing owner-transfer and active-manager invariants cannot be bypassed through project removal or organization deactivation, including concurrent transfer, removal, demotion, or deactivation requests.
6. Notifications and realtime events are emitted only after successful persistence and do not target ineligible users.
7. Restoring a removed member does not restore prior task assignments.
8. Existing API response shapes remain compatible unless an additive contract is approved. Typed history uses the approved dedicated-table and migration design with purge-aligned retention; migration implementation is authorized only within this Slice 3 scope.
9. Tests verify history retrieval, tenant isolation, rollback, no partial cross-project effects, and SQL Server concurrency using isolated scratch databases.

## Transaction and concurrency review plan

Implementation review inspected project removal and organization deactivation transaction boundaries, audit/activity writes, refresh-token revocation, and post-commit notification/realtime publication. SQLite tests cover rule and rollback paths; the opt-in SQL Server suite covers actual transaction races and lock behavior.

Required race cases include:

- two concurrent resolutions/removals for the same project member;
- an assignment or task-status change racing with the resolution preview submission;
- organization deactivation racing with project-member removal;
- organization deactivation racing with owner transfer, manager demotion/removal, or another deactivation;
- two organization deactivations affecting overlapping project/task sets.

Each race must assert final membership/owner/manager/task-assignment state and that audit/activity entries match only committed state.

## Authorized backend file list

This is the authorized backend scope. The shared API contract contains the purpose of each item.

- `src/Pms.Api/Controllers/Rest/V1/ProjectsController.cs`
- `src/Pms.Api/Controllers/Rest/V1/OrganizationsController.cs`
- Shared member-removal snapshot/validation support under `src/Pms.Api/` to keep the project and organization flows consistent
- `src/Pms.Api/Controllers/Rest/V1/TaskAssignmentHistoryController.cs`
- `src/Pms.Domain/Entities/TaskAssignmentEvent.cs`
- `src/Pms.Infrastructure/Persistence/EfCore/PmsDbContext.cs`
- `database/sqlserver/migrations/006_task_assignment_events.sql` (authorized additive migration)
- `src/Pms.Api/Media/DeletedContentPurger.cs`
- Application-level 64-KiB body-limit/error handling in `src/Pms.Api/Program.cs` or an endpoint-specific middleware/filter, plus focused middleware/filter tests
- Focused project-removal, organization-deactivation, history-retention, and isolated SQL Server race tests under `tests/Pms.IntegrationTests/`
- `docs/member-removal-resolution-api-contract.md`, this scope review, and `context/progress-tracker.md`

No Web, Flutter, progress/status, CRUD, or suspended-account security-follow-up files are in scope.

## Implementation and release verification requirements

- The proposed backend file list now includes the dedicated typed-history table and additive migration. `NO ACTION` foreign keys, composite tenant/scope keys, indexes, history-read authorization, and same-transaction purge behavior are specified in the shared contract. Migration implementation is authorized only within this Slice 3 scope.
- Verify actual request-body handling and oversized-body error mapping at 64 KiB. The repository does not expose the deployed Render/proxy limit, so deployment-side verification remains required.
- The actual EF lock inspection observed `RangeS-U` on the affected-assignee index. The isolated SQL Server suite passed 13/13 after the final code changes: migration idempotence; EF range-lock inspection; organization confirmation; 100-task confirmation; competing removals; task-creation/removal; manager demotion/deactivation; owner transfer and membership races. The 100-task confirm measured 3,683 ms. Tests use unique scratch databases and drop them afterward; the application database was not targeted.
- The full backend run passed UnitTests 1/1 and IntegrationTests 109/109, with 13 opt-in SQL Server tests skipped in that ordinary run. The separate SQL Server run passed all 13/13. The application 64-KiB body cap and 100 affected-row limit have test coverage. Deadlock-retry exhaustion was not fault-injected; the retry budget/deadline behavior is implemented but that failure branch remains a verification gap. The deployed proxy limit remains unknown and must be verified before release.
- Expired Trash is specified as logically unavailable. Direct member operations return not found; organization deactivation visibly includes automatic membership/assignment inactivation in its atomic operation, with no new assignments and no owner/manager blocker for the expired project. History remains until physical purge.
- Preserve existing member-removal/deactivation admin audit categories unless inspection shows they cannot identify the committed action; justify any new category separately.
- Verify lock ordering and deadlock/retry behavior for overlap with Slice 2 owner transfer using SQL Server race tests.

## Review gate

**Final decision (2026-10-08): Slice 3 accepted for closure.** The product owner accepted the reported 10/10 focused tests, UnitTests 1/1, IntegrationTests 112/112, deterministic retry-exhaustion/stale-snapshot checks, rollback and no-side-effect assertions, membership-restoration behavior, and purge-history verification. The 13 SQL Server tests are accepted as prior evidence; they were not rerun during the final review because the SQL test connection was unavailable. `git diff --check` passed. A dedicated Slice 3 commit is authorized; push, deployment, and Slice 4 remain unauthorized.

Release checks remain: verify the deployed proxy's body-size limit, prepare database backup and migration rollout/rollback procedures, verify migration `006_task_assignment_events.sql` against a production-like database before production, and rerun SQL Server concurrency tests in the deployment pipeline when a test connection is available. The suspended-account authorization issue remains separate.

Slices 4–6, all Web/Flutter changes, and the separate suspended-account security follow-up remain out of scope.
