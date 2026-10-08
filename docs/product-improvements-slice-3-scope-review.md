# Slice 3 — Member Removal and Open-Task Resolution Scope Review

**Status:** Scope proposal only; implementation not authorized
**Date:** 2026-10-08
**Depends on:** Accepted Slice 1 authorization/invariants and Slice 2 ownership transfer
**Product decisions:** [Owner decision record](product-improvements-owner-decisions.md)
**Assignment proposal:** [Project assignment and ownership](product-improvements-project-assignment.md)
**Pre-implementation review:** [Product improvements pre-implementation review](product-improvements-pre-implementation-review.md)

## Objective

Make project-member removal and organization-member deactivation resolve open task assignments safely, across every affected project, while preserving historical task attribution and the owner/active-manager safeguards established in Slices 1 and 2.

This document is a review proposal. It does not authorize application code, API/schema changes, client changes, migration, staging, or commits for Slice 3.

## Proposed scope

1. **Project-member removal:** Preview the target member's affected open tasks. Require an explicit resolution for each affected task: reassign it to an eligible active project member, or leave it unassigned. Do not silently clear assignments.
2. **Organization-member deactivation:** Gather affected active projects and open tasks first. Require task resolutions across all projects and validate every project's owner and active-manager invariant before making writes. If any project fails validation, make no membership, assignment, audit, activity, or token changes.
3. **Historical attribution:** Preserve completed-task attribution. For resolved open assignments, retain the original task/user attribution in a queryable, authorized history record. Do not treat activity prose alone as sufficient; verify retrievability in tests. Rejoining restores membership only and must not reactivate prior assignments.
4. **Atomic persistence:** Apply assignment resolution, assignment inactivation, membership deactivation, token revocation where currently part of the operation, and database audit/activity records in one transaction. Publish realtime events and send external notifications only after successful commit.
5. **Concurrency:** Recheck membership status, task status/assignment, recipient eligibility, owner identity, and active-manager counts within the write transaction. Return stable conflicts on stale requests; do not partially apply multi-project deactivation.

## Product rules already approved

- An active project retains an eligible active project manager. The existing server-side definition from Slice 1 remains authoritative.
- A project owner must complete ownership transfer before their membership can be removed or deactivated. Slice 2's transfer operation does not implicitly transfer ownership as a side effect of member deactivation.
- Each open task assigned to a departing member requires an explicit choice to reassign to an eligible active project member or leave unassigned.
- Completed-task attribution is preserved; membership restoration does not restore old assignments.
- Organization deactivation is all-or-nothing across affected projects.
- Server checks are authoritative; client preview data may be stale and must be revalidated on submit.

## Acceptance criteria for Slice 3

1. A read-only preview identifies affected open tasks and eligible reassignment candidates within the caller's tenant and authorized project scope.
2. Project removal and organization deactivation reject missing, duplicate, cross-tenant, stale, or ineligible resolution inputs with stable, documented errors.
3. Explicitly unassigned tasks have no effective assignee after commit; reassigned tasks have only validated eligible assignees. Original attribution remains queryable to authorized users.
4. Open-task resolution and member removal are atomic. For organization deactivation, a validation or persistence failure in any affected project leaves all projects and the organization membership unchanged.
5. Existing owner-transfer and active-manager invariants cannot be bypassed through project removal or organization deactivation, including concurrent transfer, removal, demotion, or deactivation requests.
6. Notifications and realtime events are emitted only after successful persistence and do not target ineligible users.
7. Restoring a removed member does not restore prior task assignments.
8. Existing API response shapes remain compatible unless an additive contract is approved; no schema migration is introduced unless tests prove the approved history behavior cannot be represented with current data.
9. Tests verify history retrieval, tenant isolation, rollback, no partial cross-project effects, and SQL Server concurrency using isolated scratch databases.

## Transaction and concurrency review plan

Before implementation approval, inspect the current project-member removal and organization-member deactivation routes and identify transaction boundaries, audit/activity writes, refresh-token revocation, notification dispatch, and realtime publication. Propose the smallest atomic operation boundaries that include all affected projects. Confirm the SQL Server isolation/locking strategy protects task assignment rows, membership rows, owner references, and manager counts against concurrent changes; SQLite-only tests are insufficient for these races.

Required race cases include:

- two concurrent resolutions/removals for the same project member;
- an assignment or task-status change racing with the resolution preview submission;
- organization deactivation racing with project-member removal;
- organization deactivation racing with owner transfer, manager demotion/removal, or another deactivation;
- two organization deactivations affecting overlapping project/task sets.

Each race must assert final membership/owner/manager/task-assignment state and that audit/activity entries match only committed state.

## Candidate files to inspect during the scope review

These are investigation candidates, not an approved change list. Confirm actual routes and shared services before proposing implementation files:

- `src/Pms.Api/Controllers/Rest/V1/ProjectsController.cs` — project member removal and existing manager/owner checks.
- `src/Pms.Api/Controllers/Rest/V1/OrganizationsController.cs` — organization member deactivation and cross-project transaction.
- `src/Pms.Api/Controllers/Rest/V1/TasksController.cs` — task/assignee state and current eligibility rules.
- Task assignment, activity, audit, notification, and token services/entities used by those routes.
- `tests/Pms.IntegrationTests/` — focused removal/deactivation integration and opt-in SQL Server race coverage.
- `docs/project-member-role-api-contract.md`, `docs/project-owner-transfer-api-contract.md`, and `docs/project-management-system.md` — only if contract changes are proposed.
- `context/progress-tracker.md` and this proposal — scope decisions and verification evidence.

No Web or Flutter file is in the proposed backend Slice 3 scope. If preview/removal UI is needed, propose a separately reviewed client slice after the backend contract is approved.

## Decisions to confirm before implementation authorization

- Confirm whether one open task may have multiple assignees and whether reassignment replaces all departing-member assignments or adds a new assignee while resolving the old one. Proposed default: replace only the departing member's assignment; preserve other eligible assignees.
- Confirm treatment of tasks in `REVIEW` and `DONE`: proposed rule treats every status other than `DONE` as open, consistent with the approved task completion definition.
- Confirm whether unassignment is permitted for every open-task type or only when another accountable project manager remains. Proposed rule: explicit unassignment is permitted, but the project must still retain its owner and eligible active manager.
- Confirm whether request size needs batching for members assigned to many tasks. A batch must remain all-or-nothing for organization deactivation.
- Confirm which existing admin audit actions are required in addition to append-only task activity for reassignment/unassignment and member removal.

## Review gate

Review this scope, the candidate file list, error/response contract, history-retrieval approach, and SQL Server concurrency plan. Slice 3 implementation may begin only after explicit product-owner authorization of the scope and a final implementation file list. Slices 4–6 and the separate suspended-account security follow-up remain out of scope.
