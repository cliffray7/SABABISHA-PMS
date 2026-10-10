# Product Improvements: Pre-Implementation Review

**Status:** Slices 1 and 2 accepted for closure; Slice 3 product rules approved, technical design revised for owner review; security and notification follow-ups tracked separately
**Date:** 2026-10-08
**Owner decisions:** [Approved decision record](product-improvements-owner-decisions.md)
**Follow-ups:** [Security and notification follow-ups](security-follow-ups.md)

The initial review satisfied the approved requirement to inspect authorization, ownership, task assignment, progress/status, client, realtime, and compatibility behavior before implementation. Its source audit was read-only; the subsequently authorized Slice 1 code changes and verification results are recorded below.

The verification table below records the pre-Slice 1 baseline. The Slice 1 result section records which baseline gaps have since been closed.

## Verification findings

| Approved safeguard | Current behavior verified | Gap before implementation |
|---|---|---|
| Fixed-role authorization and tenant isolation | `WorkspaceAuthorization.CanAccessProjectAsync` requires active project and organization membership, rejects archived/trashed projects, and denies writes to project viewers and organization guests. Project-member add/remove uses the existing manager check; role update separately permits active organization owners/admins and project managers. Task APIs validate project access server-side. | Task assignment validation currently checks active `ProjectMember` rows but does not independently reject organization guests or inactive/suspended accounts as assignees. Organization-role changes to `GUEST` do not clamp existing project roles. Tests are needed for owner/guest demotion and guest assignment. |
| At least one authorized project manager | Project-member role changes and project-member removal count active project managers inside serializable transactions. The count requires active project membership, active organization membership, and active user account. The SQL Server race test covers two simultaneous manager demotions. | The count does not exclude an organization member whose role is `GUEST`. Organization-member deactivation bypasses the project-level manager guard while deactivating memberships across projects. Organization role demotion to guest can also leave project-manager membership rows. Owner demotion/removal is not covered by the manager guard. |
| Ownership transfer and owner removal | Project creation sets `Project.OwnerId` to the creator and creates an initial project-manager membership. Project list responses omit the owner; Web/Flutter project models do not expose it. | No ownership-transfer endpoint or UI exists. Project-member removal does not protect `OwnerId`; organization-member deactivation does not check project ownership. No owner-transfer concurrency or owner-invariant tests exist. The approved recipient must already be an active project manager; transfer must not promote roles. |
| Open-task resolution and historical attribution | Task create/update accepts multiple task assignees. Updates validate active project membership, change task-assignee rows, and write `task.assigned` / `task.assignee_removed` activity events. `TaskAssignee` has a status field. | Removing a project or organization member does not resolve their task assignments. Task reads currently return assignee IDs without filtering inactive assignment status. Existing update logic deletes assignment rows when removed, so implementation must use append-only activity to retain attribution and must not restore prior open-task assignments when a member rejoins. Organization deactivation needs a preflight across all affected projects and one transaction for owner resolution, open-task reassignment/clearing, membership updates, and audit/activity. |
| Server-authoritative progress and task isolation | `TasksController.List` returns active, non-deleted top-level tasks, excludes subtasks from the top-level collection, and includes subtask counts. The dashboard metrics route validates membership but does not return the dashboard completion percentage. Both clients calculate progress locally: admins/managers/leads see project tasks; other members see their assigned tasks. Empty sets display `0%`. | There is no shared server-side project-progress contract or calculation. Tests are needed for tenant scope, eligible-task denominator, `DONE` numerator, empty state, subtask exclusion, deletion, archived/trashed projects, and aggregate visibility without widening individual-task access. |
| Status mappings | Stored project values are `PLANNING`, `ACTIVE`, `ON_HOLD`, `COMPLETED`; stored task values are `TO DO`, `IN PROGRESS`, `REVIEW`, `DONE`. Project and task statuses are separate. | Display mappings are not centralized and vary by surface. Update labels only; retain stored values. Verify filters, forms, reports, accessibility labels, and older clients. No `PENDING` value exists or is approved. |
| Time zone for overdue work | `Organization.Timezone` exists and defaults to `UTC`; `Project` has no time-zone field. User profiles also have a timezone, which is not the approved fallback for project-level overdue counts. | Use project timezone only if a configured project value exists; otherwise use organization timezone, then documented UTC system default. No project-time-zone schema change is justified by current evidence. |
| Client behavior and realtime | Web uses project member controls and workspace refresh; Flutter has member controls and refresh via AppState/realtime. Both have project/task screens. Existing role-edit Web smoke/build and Flutter widget/API checks are recorded in the tracker. | Neither client has owner transfer or affected-task resolution UX. Both need loading, server-error, rollback, refresh, realtime invalidation, and previous-client compatibility checks for the new flows. |

## Test evidence

- Current baseline command: `dotnet test Sababisha.Pms.slnx --no-restore`.
- Result: UnitTests passed 1/1. IntegrationTests passed 35/35 runnable tests; the opt-in `SqlServerManagerRaceTests.ConcurrentManagerDemotions_CannotCommitManagerlessProject` was skipped in this ordinary run. Total: 36 tests, 35 passed, 1 skipped, 0 failed.
- The progress tracker records a previous opt-in SQL Server run of the concurrent manager-demotion race test passing 1/1 against a scratch database. The ordinary current run did not repeat that SQL Server test.
- Existing `ProjectMemberRoleUpdateTests` cover role authorization, manager guard, tenant lookups, no-op/audit behavior, and removal cases. There are no tests yet for ownership transfer, organization-member deactivation across multiple projects, task-assignee resolution during removal, shared progress calculation, or the approved display mappings.
- Existing client verification recorded in the tracker: Web production build and new project-role smoke passed; Flutter tests passed 11/11. Flutter analyze reports two unused-element warnings in the unchanged admin screen. The five legacy Web smoke scripts fail on both baseline and feature trees.

## Slice 1 implementation result

- Product-owner authorization received 2026-10-08 for Slice 1 only. Slices 2–6 remain unauthorized.
- Added owner protection to project-member role changes/removals and organization-member role changes/deactivation, including owner rows whose project membership is inactive.
- Unified active-manager eligibility across project and organization operations: active project membership, active non-guest organization membership, and active user account. Organization deactivation now validates all affected active projects before writes, and organization role demotion to guest clamps project roles to `VIEWER` only when owner/manager and assignment guards pass.
- Project-member removal and organization-member deactivation return stable conflicts while open task assignments remain unresolved. Guest demotion marks the member's task-assignment rows inactive, preserves those rows for history, records `task.assignee_inactivated` activity per affected task, and clamps project roles to `VIEWER` atomically. Task create/update validates every explicitly submitted assignee (including unchanged IDs) against active project membership, active non-guest organization membership, and active account status inside a serializable transaction for relational providers. An update omitting `AssigneeIds` preserves assignment rows. Effective assignee IDs and newly generated assignment-derived notifications exclude ineligible users; `TASK_ASSIGNED` notifications are hidden while the recipient is ineligible. Assignment email is dispatched only after commit.
- Removing a project or organization member marks retained task-assignment rows inactive and records append-only task activity after open-task guards pass, so restoring membership does not restore those assignments and active project members can review the attribution through the existing activity feed. A later explicit assignment update can reactivate a row only after eligibility validation succeeds.
- **Separate authorization finding:** task reads are authorized by project membership through `WorkspaceAuthorization.CanAccessProjectAsync`; assignee status does not independently grant task access. That check does not currently verify `User.Status`, so a suspended account with still-valid access credentials and active memberships may continue to read project data. This was documented, not changed, because fixing global suspended-account authorization exceeds this assignment-policy refinement.
- **Separate notification-history limitation:** new comment and attachment notifications use eligible assignees as recipients, and current `TASK_ASSIGNED` inbox entries are eligibility-filtered. Older `COMMENT` and `ATTACHMENT` notifications do not record why the recipient was selected (assignee, mention, task creator, or attachment uploader), so the API cannot safely distinguish stale assignment-derived entries from other legitimate notifications without a separate notification-provenance design. Existing rows are preserved.
- No schema migration, new endpoint, client, ownership-transfer workflow, task-resolution UI, progress calculation, or CRUD expansion was added.
- Follow-up targeted role/invariant tests: 52 passed, 0 failed, 0 skipped. Full backend suite with SQL Server opt-in configured: UnitTests 1/1 and IntegrationTests 70/70 passed; total 71 passed, 0 failed, 0 skipped. All four SQL Server races ran against isolated scratch databases. See `context/progress-tracker.md` for the exact command and results.
- Schema changes were unnecessary. Open-task task-resolution and ownership-transfer flows remain for later separately authorized slices. The pre-deployment historical guest-membership audit remains unrun against a named backup/replica.

## Final Slice 2 sign-off — 2026-10-08

The product owner accepted Slice 2 — Backend Project Ownership Transfer — for closure. This is product-level sign-off based on the reported code review and verification; the results below were not rerun during final review.

- Added authorized `PATCH /api/v1/projects/{projectId}/owner` with mandatory `ExpectedOwnerId`, active actor and recipient validation, same-organization/project checks, and stable conflict responses.
- Ownership changes are serialized and the expected-owner check prevents stale transfers. Archived projects and trashed projects within the 30-day retention period support ownership maintenance without lifecycle changes; expired trash is rejected.
- Owner update, administrative audit, and workspace activity persist atomically. Realtime publication occurs only after commit. No-op and failed transfers do not publish project-change events.
- No schema or client changes were made. Existing unrelated Flutter role-editing work remains outside the Slice 2 change boundary.
- Acceptance baseline: focused ownership-transfer tests 27/27 passed; SQL Server concurrency tests 7/7 passed; standard suite reported 94 passed with 7 opt-in SQL Server tests skipped, which subsequently passed separately; `git diff --check` passed. These are prior reported results, not fresh executions during this review.

Slice 2 is accepted and authorized for closure documentation and a scoped commit. The suspended-account authorization issue remains a separate security follow-up, and historical notification provenance remains deferred. Slice 3 product rules are approved, but implementation is not authorized pending review of the revised technical design. See [Slice 3 Member Removal and Open-Task Resolution Scope Review](product-improvements-slice-3-scope-review.md).

## Implementation sequence and acceptance gates

Implementation is authorized one slice at a time. Slices 1 and 2 are accepted for closure with the outstanding follow-up findings tracked separately. Slice 3 product rules are approved; implementation requires review and explicit authorization of the revised technical design.

### Slice 1 — Backend authorization and invariants

**Scope:** Protect existing operations and assignment validation. No ownership-transfer endpoint/UI, task-resolution UI, progress API, status-label changes, migrations, or client changes in this slice.

**Acceptance criteria:**

1. Project member removal and project-role changes cannot remove/demote `Project.OwnerId` from active `PROJECT_MANAGER` membership. Return a stable conflict/error code that explains ownership must be transferred first.
2. The active-manager predicate is consistent: project membership active, organization membership active and not `GUEST`, and user account active. Existing last-manager rejection remains server-side for role changes and project member removal.
3. Organization-member deactivation evaluates all active projects before any write, rejects owner deactivation until ownership is transferred, and rejects deactivation if it would leave any active project without an eligible manager. Until Slice 3 adds explicit task-resolution choices, reject deactivation when the member has open task assignments. All membership, token, audit/activity writes occur atomically; publish realtime only after commit. Concurrent operations use serializable protection and bounded retry/conflict handling.
4. Changing an organization member to `GUEST` cannot leave elevated project roles or manager/owner capability behind. Reject if owner/manager invariants cannot be preserved; otherwise clamp active project roles to `VIEWER` and mark existing task-assignment rows inactive in the same transaction, preserving history and preventing automatic reactivation on membership restoration.
5. Task creation and explicit assignment updates reject every submitted assignee who lacks active project and organization membership, has `GUEST` organization role, or has an inactive/suspended account, including unchanged IDs. Updates omitting `AssigneeIds` remain allowed and preserve existing rows. Ineligible assignments are excluded from effective assignee IDs and assignment-derived notification recipients. Keep endpoint shapes and write authorization unchanged.
6. Tests cover each rule, cross-tenant targets, all-project atomic rejection, and the allowed paths. SQL Server concurrency tests cover simultaneous project-member removal/role changes, organization deactivation affecting manager retention, and task assignment racing with guest demotion. Run the isolated opt-in SQL Server tests plus the complete backend suite.

**Proposed backend files:**

- `src/Pms.Api/Controllers/Rest/V1/ProjectsController.cs`
- `src/Pms.Api/Controllers/Rest/V1/OrganizationsController.cs`
- `src/Pms.Api/Controllers/Rest/V1/TasksController.cs`
- `tests/Pms.IntegrationTests/ProjectMemberRoleUpdateTests.cs`
- `tests/Pms.IntegrationTests/SliceOneAuthorizationTests.cs`
- `tests/Pms.IntegrationTests/SqlServerManagerRaceTests.cs`
- `docs/project-member-role-api-contract.md` only if stable error codes/contracts need documenting
- `context/progress-tracker.md`

**Checkpoint:** Slice 1 sign-off is recorded below. Review and authorize Slice 2 separately before any implementation begins.

### Slice 2 — Ownership transfer

Add an explicit authorized transfer operation, recipient eligibility checks, transaction/concurrency guard, and an append-only audit/activity record. A recipient must already be an active project manager; transfer must not promote them. Add SQL Server race coverage.

### Slice 3 — Member removal and task resolution

Add affected-open-task preview and explicit per-task reassignment or unassignment. Preserve completed-task attribution and make organization deactivation across projects atomic. Before client deletion of assignment rows is used for this flow, verify that original task/user attribution remains queryable; activity text alone is not accepted as proof of historical reporting. Add retrieval/history tests.

### Slice 4 — Server-authoritative progress

Define the additive API contract before implementation, including stable field names, `hasTasks`, nullable percentage, overdue date/time-zone boundary, aggregate authorization, tenant isolation, archived/trashed behavior, and compatibility with older clients. Both clients consume the same server-derived result.

### Slice 5 — Web and Flutter integration

Implement owner display/transfer, removal and task-resolution workflows, tracking UI, approved status labels, and refresh/realtime behavior in separate reviewable client changes.

### Slice 6 — CRUD verification

Check accepted CRUD actions against existing routes and both clients. Add only capabilities proven missing and included in the conditionally approved scope.

Slices 1 and 2 required no schema migration. The Slice 3 read-only design found that existing task-assignee/activity fields do not reliably capture assignment deactivation actor, time, outcome, and replacement identity; a nullable structured activity-details field is proposed for owner review. No migration is authorized. See the revised Slice 3 scope review for retention and legacy-history limitations.

### Slice 1 assignment-policy follow-up — 2026-10-08

The owner approved unrelated task edits when `AssigneeIds` is omitted, while requiring explicit submitted IDs (including unchanged IDs) to be validated. Assignment rows are retained as history but are marked inactive when guest demotion or member removal revokes eligibility; a task activity event records each revocation and restoring membership alone does not reactivate it. Explicit reassignment validates eligibility before reactivating a retained row. Task list `assigneeIds`, comment/attachment assignment-derived recipients, and visible `TASK_ASSIGNED` notifications use current eligibility.

Targeted tests cover omitted IDs with guest/suspended assignees, explicit unchanged ineligible IDs, rollback of assignment invalidation with a failed admin-audit write, effective assignee/notification filtering, and member restoration followed by explicit reassignment. The full backend suite and all four SQL Server race tests passed after this refinement. Remaining separate findings are suspended-user project reads through active membership and provenance ambiguity for older `COMMENT`/`ATTACHMENT` notifications; neither was changed here.

### Final Slice 1 sign-off — 2026-10-08

The product owner accepted Slice 1 for closure based on the reported code changes and verification; this is product-level sign-off, not an independent execution or inspection. Reported results: 71/71 backend tests passed, 52/52 focused tests passed, and all 4 SQL Server concurrency tests passed with no skips or failures; `git diff --check` passed. The two outstanding findings are tracked in `docs/security-follow-ups.md`. Slice 2 was subsequently accepted in the final Slice 2 sign-off above. Existing Flutter role-editing changes remain untouched.

## Readiness boundary

The approved product requirements, read-only source verification, Slice 1 and Slice 2 changes, and test results are recorded. Slice 3 rules are approved for specification only; implementation awaits review of the revised design and explicit authorization. Slices 4–6 remain unauthorized. Existing uncommitted Flutter role-editing changes are unrelated and remain untouched.
