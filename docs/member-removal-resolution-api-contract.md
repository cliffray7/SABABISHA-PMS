# Member Removal and Open-Task Resolution API Contract

**Status:** Backend implementation complete; implementation review checkpoint (2026-10-08)
**Date:** 2026-10-08
**Scope:** Backend project-member removal and organization-member deactivation only
**Related design:** [Slice 3 scope review](product-improvements-slice-3-scope-review.md)

This document records the owner-approved product and history architecture decisions and the authorized additive API shape. SQL query-plan, race, payload-capacity, and deployment-proxy verification remain implementation/release acceptance checks.

## Existing route compatibility

Existing member `DELETE` routes and their successful response shapes remain unchanged. If an existing route encounters unresolved open-task assignments, it returns its existing stable `409` code and directs the caller to preview and confirm. New routes are additive.

Preview and confirmation use the same server-side actor authorization and tenant-scoped target resolution as the corresponding existing project-member removal or organization-member deactivation operation. They must not authorize from client-supplied organization IDs, project IDs, roles, or preview contents.

## Project-member removal

### Preview

```http
GET /api/v1/projects/{projectId}/members/{userId}/removal-preview
```

Read-only. The response includes the project and organization identifiers, target member, lifecycle, `snapshotHash`, affected non-deleted open tasks, current assignee IDs, eligible replacement candidates, and `historicalAttributionsToInactivate` for completed or task-trashed assignments. `REVIEW` is open; `DONE` is complete and is not a required resolution. Closed/trashed rows do not require a client resolution, but are inactivated and recorded as typed `UNASSIGNED` events in the confirmation transaction so restoring membership cannot make an old assignment effective again. Their assignment rows retain the original user/task attribution. Preview performs no writes, audit/activity inserts, or realtime publication.

### Confirm

```http
POST /api/v1/projects/{projectId}/members/{userId}/remove
Content-Type: application/json
```

```json
{
  "snapshotHash": "<base64url-sha256-from-preview>",
  "resolutions": [
    { "taskId": "<guid>", "action": "REASSIGN", "replacementUserId": "<eligible-member-guid>" },
    { "taskId": "<guid>", "action": "UNASSIGN", "replacementUserId": null },
    { "taskId": "<guid>", "action": "ACCEPT_LIFECYCLE_INACTIVATION", "replacementUserId": null }
  ]
}
```

For an active, non-archived project, every affected task must have exactly one `REASSIGN` or `UNASSIGN` resolution. `REASSIGN` inactivates only the departing member's assignment and assigns the task to the selected eligible member. `UNASSIGN` inactivates only the departing member's assignment. Other eligible assignees are preserved. `ACCEPT_LIFECYCLE_INACTIVATION` is valid only for an archived or trashed-within-retention task listed with that exact required action in the preview. It creates no replacement and stores `LIFECYCLE_INACTIVATED` with a server-derived reason.

## Organization-member deactivation

### Preview

```http
GET /api/v1/organizations/{organizationId}/members/{userId}/deactivation-preview
```

Read-only. Returns the same snapshot concepts grouped by affected retained project. It reports ownership-transfer and active-manager blockers before confirmation and an `expiredTrashCleanup` section for expired projects and their automatic assignment-inactivation side effects. Expired-project work is visible but does not require per-task client resolutions; it is performed only as part of the confirmed organization deactivation.

### Confirm

```http
POST /api/v1/organizations/{organizationId}/members/{userId}/deactivate
Content-Type: application/json
```

Uses the same request body and per-task resolution rules for retained projects. It also performs the separately previewed `expiredTrashCleanup` atomically: inactivate active assignments on open, non-deleted tasks and the target's project membership, without replacement assignments or owner/manager blockers for those logically unavailable projects. Assignment-history rows, organization/project memberships, refresh-token revocation, and existing database audit/activity records commit or roll back together. No partial project batches are allowed. A project owner must first transfer ownership in any retained project; deactivation never transfers ownership implicitly.

### Preview response envelope

Both preview routes return this common envelope; organization scope additionally populates `expiredTrashCleanup`:

```json
{
  "projectId": "<guid-or-null-for-organization-scope>",
  "organizationId": "<guid>",
  "memberId": "<guid>",
  "snapshotHash": "<base64url-sha256>",
  "affectedTaskCount": 1,
  "affectedProjects": [
    {
      "projectId": "<guid>",
      "lifecycle": "ACTIVE | ARCHIVED | TRASHED_WITHIN_RETENTION",
      "ownerTransferRequired": false,
      "managerInvariantBlocked": false,
      "eligibleReplacementMembers": [
        { "userId": "<guid>", "displayName": "<name>" }
      ],
      "tasks": [
        {
          "taskId": "<guid>",
          "parentTaskId": null,
          "title": "<title>",
          "status": "REVIEW",
          "currentAssigneeIds": ["<departing-member-guid>"],
          "requiredResolution": "REASSIGN_OR_UNASSIGN"
        }
      ]
    }
  ],
  "expiredTrashCleanup": [
    {
      "projectId": "<guid>",
      "deletedAt": "<utc-timestamp>",
      "lifecycle": "EXPIRED_TRASH_PENDING_PURGE",
      "ownerManagerChecks": "NOT_APPLICABLE",
      "tasks": [
        {
          "taskId": "<guid>",
          "status": "IN PROGRESS",
          "currentAssigneeIds": ["<departing-member-guid>"],
          "actionOnConfirm": "LIFECYCLE_INACTIVATED"
        }
      ]
    }
  ]
}
```

Archived and trashed-within-retention tasks use `requiredResolution: "ACCEPT_LIFECYCLE_INACTIVATION"` and offer no replacement candidates. `affectedTaskCount` includes every active target assignment row that confirmation will change: required open-task resolutions, automatic closed/task-Trash inactivation, and expired-project cleanup. If that total is over 100, preview returns `422` and no hash/resolution list; confirm independently enforces the same cap.

Successful confirm returns `204 No Content`. Preview and confirm errors use the stable error envelope below. These response fields are the exact shared contract; clients are out of scope for this slice.

## Project lifecycle behavior

| Persisted project lifecycle | Removal/resolution behavior |
| --- | --- |
| Active and not archived | Require explicit `REASSIGN` or `UNASSIGN` for each affected open assignment. |
| Archived | Membership removal is allowed after all owner/manager checks. Existing assignments are not replaced or reactivated. The preview lists each affected open assignment and requires explicit `ACCEPT_LIFECYCLE_INACTIVATION`. |
| Trashed within 30-day retention | Same as archived: explicit lifecycle-inactivation acceptance, no new assignment, and owner/manager safeguards still apply. |
| Trashed beyond 30-day retention but not physically purged | Excluded from normal project resolution. Direct project operations are unavailable; organization deactivation uses the expired-project cleanup below and is not blocked. |
| Permanently purged | No operation is available. |

`ACCEPT_LIFECYCLE_INACTIVATION` is valid only when the server confirms the project is archived or trashed within retention. It inactivates the departing member's assignment without creating a replacement. The server records a `LIFECYCLE_INACTIVATED` history event and derives `PROJECT_ARCHIVED` or `PROJECT_TRASHED` as its reason; a client cannot supply or override this reason.

### Expired Trash during organization deactivation

Use one server-captured UTC time per preview/confirm and define a project as expired when `DeletedAt <= capturedNowUtc - 30 days`, matching the purge worker's `<=` boundary. Direct project-member removal on an expired-trash project returns `404 PROJECT_NOT_FOUND`; it does not change project membership, task assignments, ownership, or project state.

Organization-member deactivation must not be blocked by a project that is logically unavailable but awaiting physical purge. The organization preview reports these projects separately as `expiredTrashCleanup`, including project ID, deletion timestamp, and affected open-task IDs, statuses, and assignee IDs. They are excluded from ordinary per-task resolution and are never offered as replacement targets. On confirmed organization deactivation, the server atomically inactivates the target's project membership and each active assignment on a non-deleted, non-`DONE` task in these projects. It creates no replacement assignment and appends a `LIFECYCLE_INACTIVATED` event with reason `PROJECT_TRASH_EXPIRED` for each affected assignment.

Expired projects are outside the retained-project owner/manager invariant: their `OwnerId` is left unchanged, and an expired project's manager count does not block deactivation. The project is not restored or made operable. Active, archived, and trashed-within-retention projects continue to enforce ownership transfer and active-manager retention. The organization deactivation audit record and assignment events share one server-generated operation ID. Event identifiers remain stored only until physical task/project purge; purge removes them with their content in the same database transaction. The preview snapshot includes every expired project and cleanup assignment. If purge wins a race with confirmation, the snapshot changes and confirmation returns stale without writes; if deactivation wins, purge waits and then removes the rows.

Expired-project cleanup assignments count toward the 100-task operation limit even though they do not require ordinary resolutions. If ordinary resolutions plus expired-project cleanup exceed 100 affected tasks, reject the entire organization deactivation with `422 MEMBER_RESOLUTION_LIMIT_EXCEEDED`.

All projects still within retention enforce the project-owner transfer and active-manager invariants, including archived and trashed projects. The operation never restores a project or task.

## Assignment history and retention

Each new assignment-resolution event records typed organization ID, project ID, task ID, departing member ID, nullable replacement member ID, actor ID, UTC timestamp, action (`REASSIGNED`, `UNASSIGNED`, or `LIFECYCLE_INACTIVATED`), reason code when lifecycle-driven, stable event ID, and operation/correlation ID. Events are append-only during the applicable retention period and are readable only through tenant- and project/task-authorized history access. This slice does not widen existing read authorization.

Proposed history read route:

```http
GET /api/v1/projects/{projectId}/tasks/{taskId}/assignment-history
```

It returns only typed resolution events for that task and is authorized by the same server-side tenant/project/task read check already used for task history. The response must identify the legacy period as incomplete (for example, `legacyHistoryComplete: false`); an empty new-event list must never imply that no earlier assignment changes occurred. Archived, trashed, and expired projects receive no new read access from this route.

Response shape:

```json
{
  "taskId": "<guid>",
  "legacyHistoryComplete": false,
  "events": [
    {
      "eventId": "<guid>",
      "operationId": "<guid>",
      "organizationId": "<guid>",
      "projectId": "<guid>",
      "taskId": "<guid>",
      "departingMemberId": "<guid>",
      "replacementMemberId": "<guid-or-null>",
      "actorId": "<guid>",
      "occurredAtUtc": "<utc-timestamp>",
      "action": "REASSIGNED | UNASSIGNED | LIFECYCLE_INACTIVATED",
      "reason": "<reason-or-null>"
    }
  ]
}
```

Legacy assignment rows without these facts remain incomplete. Do not infer or backfill missing actor, time, action, or replacement facts.

The current `ActivityEvent` table is append-only and its assignment details are prose; its rows are not removed by task/project purge. Storing typed assignment history there would either fail the structured contract or retain personal identifiers beyond the approved purge policy. The migration-free approach is rejected. The approved design is a dedicated `task_assignment_events` table and an additive SQL migration. The owner authorized implementation on 2026-10-08, subject to the acceptance and verification gates in this contract.

### Proposed table and integrity constraints

| Column | SQL Server type | Rule |
| --- | --- | --- |
| `event_id` | `uniqueidentifier` | Primary key; stable event identity, generated by the API. |
| `operation_id` | `uniqueidentifier` | Required; one server-generated ID shared by all history and admin-audit writes in one confirmed operation, reused across retries. |
| `organization_id` | `uniqueidentifier` | Required tenant scope. |
| `project_id` | `uniqueidentifier` | Required project scope. |
| `task_id` | `uniqueidentifier` | Required task scope. |
| `departing_user_id` | `uniqueidentifier` | Required affected member. |
| `replacement_user_id` | `uniqueidentifier` | Nullable; required only for `REASSIGNED`. |
| `actor_user_id` | `uniqueidentifier` | Required authenticated actor. |
| `occurred_at_utc` | `datetime2(7)` | Required server UTC timestamp. |
| `action` | `nvarchar(32)` | `REASSIGNED`, `UNASSIGNED`, or `LIFECYCLE_INACTIVATED`. |
| `reason_code` | `nvarchar(40)` | Null for reassignment/explicit unassignment; lifecycle values are `PROJECT_ARCHIVED`, `PROJECT_TRASHED`, or `PROJECT_TRASH_EXPIRED`. |

Add a `CHECK` constraint enforcing: `REASSIGNED` requires a non-null replacement different from the departing user and null reason; `UNASSIGNED` requires null replacement and null reason; `LIFECYCLE_INACTIVATED` requires null replacement and one of the three lifecycle reasons. The API derives action/reason from persisted project lifecycle; clients cannot choose a lifecycle reason.

Use `ON DELETE NO ACTION` for every foreign key; do not use cascades or `SET NULL`. Enforce scope consistency with composite foreign keys `(project_id, organization_id) -> projects(id, organization_id)` and `(task_id, project_id) -> tasks(id, project_id)`, backed by unique parent keys if required by SQL Server. The composite project foreign key also proves organization scope through the project row. Add `departing_user_id`, `actor_user_id`, and nullable `replacement_user_id -> users(id)` references, also `NO ACTION`. This prevents orphaned or cross-tenant event references. Users are soft-deactivated in the current product; any future hard user deletion must wait until referencing assignment history has expired or be separately designed to de-identify it.

Recommended indexes:

- Unique parent keys `(projects.id, projects.organization_id)` and `(tasks.id, tasks.project_id)` for the composite foreign keys.
- `task_assignment_events(task_id, occurred_at_utc, event_id)` for authorized task history and task-purge lookup.
- `task_assignment_events(project_id, organization_id, task_id)` for tenant scope and project-purge lookup.
- `task_assignment_events(operation_id, event_id)` for operation-level audit correlation.
- Indexes for `departing_user_id`, `actor_user_id`, and filtered non-null `replacement_user_id` to support `NO ACTION` user references and permitted audit queries.
- Use the existing `ix_task_assignees_user_status(user_id, status)` for affected-member range seeks; verify its plan and key lookups. Adding `INCLUDE (task_id)` is conditional on actual plan evidence, not assumed necessary.

The purger explicitly deletes history rows for the selected task IDs before deleting tasks and includes project-scoped cleanup as a defensive check for project purge. Save history deletion and content deletion together in the same EF Core `SaveChanges` transaction. The `NO ACTION` foreign keys intentionally make purge fail atomically if history cleanup is omitted. Soft delete/restore does not delete history; restore does not reactivate an assignment. No display names, emails, or other unnecessary personal data are stored in these events.

## Snapshot and concurrency precondition

Preview returns a base64url SHA-256 `snapshotHash` over a canonical, server-controlled, deterministically sorted representation of operation/scope/target membership; every retained project's lifecycle, owner, and active-manager identities; every active target assignment's task ID/status/update/deletion time; active assignee IDs/status/assignment time; eligible replacement IDs; and lifecycle-inactivation reasons. Organization deactivation also includes expired-project IDs/deletion times, target project memberships, and every expired-project cleanup task/assignment in the snapshot. Use one captured server UTC time and the same `DeletedAt <= now - 30 days` boundary as the purge worker; a boundary change between preview and confirmation makes the token stale.

The hash is a stale-preview precondition, not an authorization credential or lock. At confirmation the server must independently reauthorize the actor and recompute/revalidate all state inside one SQL Server `SERIALIZABLE` transaction. The query must acquire and retain locks that prevent phantom assignments and relevant project/task/membership changes through commit. If the hash or any independent validation differs, return a conflict and write nothing. Retry the same original hash and resolution set; never add unseen tasks during retry.

### Lock order, indexes, retries, and time bound

Confirmation acquires target/actor organization-membership rows first, then project rows, project memberships and eligible users, task rows, the affected-member `(user_id,status)` assignment range, and task-specific assignee rows in deterministic order. It reauthorizes after locking and persists history/audit/activity last. The implementation uses separate deterministic queries and explicit SQL Server lock hints on the indexed predicates; lock acquisition order inside unrelated task-write and owner-transfer routes is not assumed from LINQ ordering.

Project removal reads the project's organization ID before its transaction, then locks membership before project rows; organization deactivation locks membership first. Owner transfer and task-write routes retain their established entry order. Their overlap with Slice 3 was exercised through isolated SQL Server races; all passed with bounded retry/revalidation. This evidence does not claim that every unrelated route is globally deadlock-free.

Use the existing task assignment index `ix_task_assignees_user_status(user_id,status)` for the affected-member active-assignment range, the task `(project_id,status)` index, and the existing unique project/organization member keys. Verify the actual EF SQL and execution plan and confirm `RangeS-S`/appropriate key-range locks under concurrent assignment insert. Add `INCLUDE(task_id)` or another narrow index only if the plan shows a need.

Retries are finite: the current EF SQL Server execution strategy permits at most six retries. Slice 3 confirmation uses one hard 30-second request deadline covering the initial attempt, retry waits, and every transaction attempt. Each retry clears tracked state, starts a new transaction, reauthorizes and recomputes the same preview snapshot, and reuses the same operation ID and client resolution set. The total deadline is never reset per retry. Deadline expiry, deadlock retry exhaustion, and transient conflict return `409 MEMBER_REMOVAL_CONFLICT`; cancellation rolls back all DB writes and emits no realtime event. One SQL Server 100-task confirmation completed in 3,683 ms; this is a single measurement, not a latency distribution or production target.

For organization deactivation, more than 100 total affected tasks rejects the complete operation, counting both ordinary resolutions and automatic expired-Trash cleanup. No independently committed batches or partial processing are permitted.

## Limits

- Maximum affected tasks per confirm request: **100**, including automatic expired-Trash cleanup tasks.
- Maximum confirmation body: **64 KiB**, enforced in application code before JSON binding/transaction start.
- Over 100 affected tasks: `422 MEMBER_RESOLUTION_LIMIT_EXCEEDED`, no writes; actionable message tells the administrator to resolve active-project assignments through existing task operations or complete Trash purge, then refresh the preview.
- Body over 64 KiB: `413 REQUEST_BODY_TOO_LARGE`, no writes, stable JSON code/message envelope.
- These are application-level limits, not existing hosting/proxy limits. Verify at the API endpoint with known-length and streamed bodies, at 100 items, and with the deployment proxy configuration before release. No partial processing is allowed.

## Error contract

All new route errors use `{ "code": "...", "message": "..." }`. Codes are stable and must not rely on message parsing.

| HTTP | Code | Meaning |
| --- | --- | --- |
| 400 | `MEMBER_RESOLUTION_REQUIRED` | Missing or incomplete per-task decisions. |
| 400 | `MEMBER_RESOLUTION_INVALID` | Duplicate, extra, non-affected task ID, or invalid action/payload pair. |
| 403 | `MEMBER_REMOVAL_FORBIDDEN` | Caller lacks current organization/project authority. |
| 404 | `MEMBER_NOT_FOUND` | Target is not active in the caller's authorized scope. |
| 404 | `PROJECT_NOT_FOUND` | Project is outside caller scope, permanently purged, or unavailable for this operation. |
| 409 | `MEMBER_REMOVAL_PREVIEW_STALE` | Relevant task, assignment, membership, owner, manager, lifecycle, or eligibility state changed. |
| 409 | `PROJECT_OWNER_TRANSFER_REQUIRED` | Target remains the owner of a retained project. |
| 409 | `ORGANIZATION_OWNER_CANNOT_BE_REMOVED` | The organization owner must transfer organization ownership before deactivation. |
| 409 | `PROJECT_MUST_RETAIN_MANAGER` | Removal would leave a retained project without an eligible active manager. |
| 409 | `MEMBER_REMOVAL_REPLACEMENT_INELIGIBLE` | Replacement is no longer an active eligible member of this project. |
| 409 | `MEMBER_REMOVAL_CONFLICT` | Bounded SQL Server retry exhausted; caller must obtain a fresh preview and retry. |
| 413 | `REQUEST_BODY_TOO_LARGE` | Confirmation request exceeds 64 KiB. |
| 422 | `MEMBER_RESOLUTION_LIMIT_EXCEEDED` | More than 100 affected task assignment rows; no partial operation is permitted. |

Existing `DELETE` routes retain their existing codes when open assignments require explicit resolution: `project_member_open_tasks_require_resolution` and `organization_member_open_tasks_require_resolution`.

## Verification status and implementation acceptance checks

The API-level middleware enforces 64 KiB before model binding; tests cover known-length and streamed bodies above the cap, the exact cap boundary, and unrelated routes. Controller integration tests cover 100 affected tasks accepted and 101 rejected. The application limit is effective; the deployed Render/reverse-proxy limit is not exposed in repository configuration and remains a pre-release infrastructure check.

Final verification on 2026-10-08: the ordinary full solution run passed UnitTests 1/1 and IntegrationTests 109/109; 13 opt-in SQL Server tests were skipped in that run. A separate run against unique scratch databases passed all 13 opt-in SQL Server tests, including migration idempotence, direct EF range-lock inspection, organization confirmation, competing removals, task creation racing removal, ownership/manager/deactivation races, and a 100-task confirmation. The measured 100-task confirmation took 3,683 ms, below the 30-second cap. The SQL Server migration test applied `006_task_assignment_events.sql` twice and verified all six `NO ACTION` foreign keys and six history indexes. The actual EF query held `RangeS-U` on `ix_task_assignees_user_status`. Focused member-removal/history/body-limit tests passed 18/18 (three SQL Server opt-in cases were skipped in that filtered run). `git diff --check` passed; only existing CRLF/LF notices were emitted. These are implementation tests, not verification of the deployed proxy configuration.

The authorized backend implementation file list is:

- `src/Pms.Api/Controllers/Rest/V1/ProjectsController.cs`
- `src/Pms.Api/Controllers/Rest/V1/OrganizationsController.cs`
- Shared member-removal snapshot/validation support under `src/Pms.Api/` to keep both preview/confirm flows on the same canonical rules
- `src/Pms.Api/Controllers/Rest/V1/TaskAssignmentHistoryController.cs` for authorized assignment-history retrieval; assignment events are written by the project/organization confirmation handlers, not task create/update.
- `src/Pms.Domain/Entities/TaskAssignmentEvent.cs`
- `src/Pms.Infrastructure/Persistence/EfCore/PmsDbContext.cs`
- `database/sqlserver/migrations/006_task_assignment_events.sql` (authorized additive migration; required for typed retention-aligned history)
- `src/Pms.Api/Media/DeletedContentPurger.cs`
- `src/Pms.Api/Program.cs` and endpoint-scoped request-body/error handling for the 64-KiB cap
- Focused project-removal, organization-deactivation, history-retention, request-limit, migration, and isolated SQL Server race tests under `tests/Pms.IntegrationTests/`
- This contract, `docs/product-improvements-slice-3-scope-review.md`, and `context/progress-tracker.md`

No Web, Flutter, progress/status, CRUD, or suspended-account follow-up files are in scope. Do not commit, push, deploy, or begin Slice 4 as part of this authorization.

### Final review verification (2026-10-08)

Deterministic retry tests exhausted six retries (seven total attempts) and verified the stable `409 MEMBER_REMOVAL_CONFLICT` response with no persisted membership, assignment, assignment-history, admin-audit, or activity changes, no outbound mail, and no realtime event. A transient first attempt that changed task status was followed by snapshot revalidation and returned `MEMBER_REMOVAL_PREVIEW_STALE` without applying the requested resolution. Membership restoration left the old assignment inactive and its historical departing-member attribution intact. A disposable SQLite integration test invoked the actual purge worker and verified typed history was deleted together with both an expired task and an expired project. The focused removal/purge set passed 10/10. The full solution passed UnitTests 1/1 and IntegrationTests 112/112, with 13 opt-in SQL Server tests skipped because `PMS_TEST_SQLSERVER_CONNECTION` was unavailable. The earlier SQL Server 13/13 run and idempotent migration test remain reported prior evidence, not rerun in this review. No production migration was applied. `git diff --check` passed with line-ending notices. The deployed proxy request-size limit remains a pre-deployment check.
