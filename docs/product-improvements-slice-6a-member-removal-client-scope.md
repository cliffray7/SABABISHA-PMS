# Slice 6A — Member-Removal Client Correction Scope

**Status:** Proposal for product-owner review; implementation not authorized
**Date:** 2026-10-09
**Parent verification:** [Slice 6 Verification Results](product-improvements-slice-6-verification-results.md)
**Scope review:** [Slice 6 CRUD Lifecycle Verification](product-improvements-slice-6-scope-review.md)

## Goal

Connect the existing Web and Flutter member-removal controls to the backend's established preview/confirmation contract. This corrects the verified client workflow gap without adding or changing a deletion endpoint and without weakening backend safeguards.

This proposal is limited to project-member removal and organization-member deactivation in Web and Flutter. The API already implements the preview/confirm operations, assignment validation, snapshot precondition, transaction, audit/history, and post-commit event behavior.

## Existing endpoints and authorization

| Operation | Preview | Confirmation |
|---|---|---|
| Remove a project member | `GET /api/v1/projects/{projectId}/members/{userId}/removal-preview` | `POST /api/v1/projects/{projectId}/members/{userId}/remove` |
| Deactivate an organization member | `GET /api/v1/organizations/{organizationId}/members/{userId}/deactivation-preview` | `POST /api/v1/organizations/{organizationId}/members/{userId}/deactivate` |

The current direct `DELETE` routes remain unchanged for compatibility, but Slice 6A client controls must not call them. Server authorization and invariant checks remain authoritative:

- Project removal requires an active, non-guest organization member with an active project manager or team-lead membership. Self-removal is rejected. The target must be active. Owner transfer and active-manager retention are enforced.
- Organization deactivation requires an active organization owner/admin. Self-deactivation and removal of the organization owner are rejected. All affected retained projects are validated atomically.
- Preview/confirm calls are tenant-scoped by the backend. Client-side role checks only control presentation; they do not replace API checks.

## Existing request and response contract

### Preview response

The API serializes these records using camel-case JSON:

- Top level: `projectId` (nullable for organization scope), `organizationId`, `memberId`, `snapshotHash`, `affectedTaskCount`, `affectedProjects`, and `expiredTrashCleanup`.
- Each `affectedProjects` item: `projectId`, `lifecycle`, `ownerTransferRequired`, `managerInvariantBlocked`, `eligibleReplacementMembers`, `tasks`, and `historicalAttributionsToInactivate`.
- Each task requiring a decision: `taskId`, `parentTaskId`, `title`, `status`, `currentAssigneeIds`, and `requiredResolution`.
- Historical rows and expired-Trash cleanup rows are also present in the preview. They describe lifecycle-driven inactivation and must not be displayed as requiring an arbitrary replacement.

`eligibleReplacementMembers` contains `{ userId, displayName }` candidates. The preview is informational and time-bound; confirmation re-reads the database and validates the snapshot inside its transaction.

### Confirmation request

```json
{
  "snapshotHash": "<value returned by preview>",
  "resolutions": [
    {
      "taskId": "<task ID from preview>",
      "action": "REASSIGN",
      "replacementUserId": "<eligible member ID>"
    }
  ]
}
```

`MemberRemovalRequest` is `{ snapshotHash, resolutions }`; each `MemberTaskResolution` is `{ taskId, action, replacementUserId }`.

For each affected task in an active project, the API requires exactly one resolution:

- `REASSIGN` with an eligible active project member as `replacementUserId`; or
- `UNASSIGN` with `replacementUserId: null`.

For archived or retained-Trash projects, the preview specifies `ACCEPT_LIFECYCLE_INACTIVATION`; no replacement is allowed. Expired-Trash cleanup is reported separately and resolved by the existing backend lifecycle rule. Completed and task-Trash historical assignments are inactivated without being presented as open-task reassignment choices.

The backend allows at most 100 affected assignments and enforces a 64-KiB request-body limit. These are application limits; do not infer proxy limits.

### Responses and stable errors to handle

Successful confirmation returns `204 No Content`. The UI must not remove the member or show success before receiving this response.

The existing contract includes these response cases (exact wording should continue to use the server message when present, with a concise fallback):

| HTTP / code | Client behavior |
|---|---|
| `403 MEMBER_REMOVAL_FORBIDDEN` | Keep member and dialog state; show permission error. |
| `404 PROJECT_NOT_FOUND`, `MEMBER_NOT_FOUND` | Keep current state; explain the project/member is no longer available and refresh the relevant list. |
| `400 MEMBER_RESOLUTION_REQUIRED`, `MEMBER_RESOLUTION_INVALID` | Keep the preview open; identify missing, duplicate, unsupported, or extraneous task choices. |
| `409 MEMBER_REMOVAL_PREVIEW_STALE` | Discard the stale preview and its choices, fetch a new preview, and require the user to review/confirm again. Never silently resubmit the old choices against a new snapshot. |
| `409 MEMBER_REMOVAL_REPLACEMENT_INELIGIBLE` | Keep the operation incomplete; refresh preview/candidates and require a new explicit choice. |
| `409 PROJECT_OWNER_TRANSFER_REQUIRED`, `PROJECT_MUST_RETAIN_MANAGER` | Keep the member unchanged and explain the owner/manager invariant. |
| `409 MEMBER_REMOVAL_CONFLICT` | Keep the member unchanged; offer refresh-preview and retry. |
| `422 MEMBER_RESOLUTION_LIMIT_EXCEEDED` | Keep the member unchanged; show the server's actionable limit message. No client-side batching. |
| Network/other `5xx` | Keep the member unchanged; show retry state. Do not imply partial success. |

Organization deactivation uses the same resolution and stale/limit errors, plus `409 ORGANIZATION_OWNER_CANNOT_BE_REMOVED` when applicable.

## Proposed UI flow

1. The existing Remove control opens a dialog/sheet and requests the correct scope-specific preview.
2. Show the target member and all projects/tasks represented by the preview. Show owner-transfer or manager-invariant blockers clearly; do not enable confirmation when the preview says an invariant cannot be met.
3. For active-project tasks, require one explicit choice per listed task: reassign to one of that project's eligible candidates or leave unassigned. Do not clear or replace any other existing assignees.
4. For archived/retained-Trash tasks, show that the departing assignment will be inactivated because of project lifecycle; do not offer a replacement. Clearly label expired-Trash cleanup and historical attribution handling as automatic lifecycle actions described by the server.
5. Disable confirmation while loading or posting. Submit exactly the preview `snapshotHash` and one resolution for each task requiring a choice. Organization deactivation submits one atomic request for the organization's complete preview; never split requests into independently committed project batches.
6. On `204`, close the dialog and reload organization/project membership from the existing state/API path. On any error, retain the member in the list, keep the dialog open where safe, show the error, and do not present a success toast or optimistic removal.
7. On stale snapshot, discard selections and obtain a fresh preview; require a new user confirmation. Do not auto-confirm after refreshing.

## Exact proposed file boundary

No files are approved for modification yet. If this proposal is authorized, the bounded candidate list is:

| File | Proposed purpose |
|---|---|
| `apps/web/src/api.ts` | Add typed preview/confirmation DTOs and typed API helpers for the four existing routes. |
| `apps/web/src/main.tsx` | Replace the two direct-DELETE member-removal controls in `MembersPage` with the preview/choice/confirm flow; keep all unrelated screens untouched. |
| `apps/web/tests/member-removal-smoke.mjs` (new) | Add deterministic Playwright coverage for project removal and organization deactivation using route interception only. No live backend, inbox, or seeded database. |
| `apps/web/package.json` | Add only a script to run the new smoke test; no dependency changes. |
| `apps/mobile/lib/src/models/models.dart` | Add typed DTO parsing for preview, project/task choices, eligible candidates, and expired-Trash summaries. |
| `apps/mobile/lib/src/services/api_client.dart` | Add typed preview and confirmation calls for the existing endpoints. Keep the pre-existing role-editing changes intact; the old direct-removal methods must no longer be used by these screens. |
| `apps/mobile/lib/src/screens/members_screen.dart` | Replace project and organization direct-removal UI flows with the preview/choice/confirm interactions and existing refresh paths. Preserve the pre-existing role-editing UI hunks. |
| `apps/mobile/test/member_removal_flow_test.dart` (new) | Add widget/API tests using the existing injected `http.Client`/`MockClient` pattern, without live services. |

No `app_state.dart` change is proposed: current member screens already reload organization/project data after successful actions. No backend, database, migration, new endpoint, package, stylesheet, role-editing, or purge-worker changes are included.

## Proposed acceptance tests

### Web Playwright with mocked routes

- Project member with an open task: preview is requested, no direct DELETE is sent, task choice is required, and confirm body contains the exact snapshot and resolution.
- Organization member with tasks across multiple projects: all choices appear in one confirmation request; the UI does not issue per-project confirmation batches.
- Reassignment candidates are limited to the preview's eligible members; unassignment sends null replacement.
- Archived/retained-Trash preview requires lifecycle acknowledgement and exposes no replacement option; historical/expired-Trash rows are labelled as server-directed cleanup.
- Stale snapshot response causes a new preview and requires another explicit confirmation; old choices are not auto-submitted.
- `403`, permission/invariant conflicts, `422` limit, network failure, and `5xx` keep the member visible and show an error; no false success state.
- `204` closes the flow, shows no partial intermediate state, and reloads membership.
- Route assertions fail the test if either UI invokes the legacy direct-DELETE route.

### Flutter widget/API tests with `MockClient`

- The project and organization controls request their respective preview routes and render per-task choices.
- Confirmation request JSON exactly matches the selected preview snapshot and resolution values.
- A member is retained until `204`; then membership reloads through existing state methods.
- Stale preview triggers a second GET and explicit reconfirmation; no silent retry of confirmation.
- Permission, owner/manager, replacement-ineligible, conflict, 422 limit, and transport failures leave membership unchanged and display an error.
- Archived/Trash and historical rows render the server-provided lifecycle action without a replacement selector.
- Requests never call the direct member-delete API methods.

Use existing Playwright and Flutter test dependencies. If a missing fixture seam prevents these deterministic tests, stop and request approval for a specific additional file before expanding scope.

## Explicit exclusions

- No backend behavior or route changes; no direct DELETE weakening/removal.
- No changes to owner transfer, manager retention, guest eligibility, snapshot generation, assignment rules, history, audit, notifications, or transaction behavior.
- No permanent purge or Cloudinary changes.
- No organization profile/delete, comment edit, notification dismissal, task GET, or subtask-delete capability.
- No new dependencies, database/schema/migration changes, commits, pushes, or deployments.
- No unrelated Flutter role-editing or roadmap/progress-tracker changes.

## Separate follow-ups from this proposal

### Purge configuration behavior

The Cloudinary pause is documented as intentional operational behavior: README states expired-media purging remains paused until Cloudinary is configured, and the worker logs the pause before returning. The repository does not explicitly state the design rationale. The likely safety reason—that database references should remain while referenced remote assets cannot be deleted—is an inference, not a documented decision.

Possible bounded design for separate approval: let the worker process expired aggregates that have no Cloudinary-backed assets, while deferring any task/comment/project aggregate with remote asset IDs until deletion succeeds. Retain each `CloudinaryPublicId` in the database until the remote delete succeeds, then perform the existing database cleanup. `CloudinaryStorage.DeleteAsync` accepts both `ok` and `not found`, which supports retry after a remote delete succeeded but the later database save failed. Validate this with disposable tests for no-media cleanup, missing credentials with a media-backed aggregate, partial media-delete failure, and retry. Do not alter purge behavior as part of Slice 6A.

### Flutter subtask delete method

Repository-wide search finds `ApiClient.deleteSubtask` only at its declaration. There is no backend DELETE subtask action and no Web/Flutter UI caller. The current supported subtask lifecycle is create/list/status update; no user-reachable failure is established. Propose removing the unused client method as a separate cleanup only if its removal is desired; do not add an endpoint.

### Flutter test-run stall

Observed in this verification session:

- Full command: `flutter test` from `C:\Users\Admin\SABABISHA-PMS\apps\mobile`; no output for approximately 135 seconds; interrupted with Ctrl+C, exit code 1. This does not establish a test failure.
- Targeted command: `flutter test test/api_client_test.dart --plain-name "uses the Android emulator API address by default" --reporter expanded`, same working directory; no output for approximately 90 seconds; interrupted with Ctrl+C, exit code 1. The stall reproduces with one test selected.
- Environment: Microsoft Windows NT 10.0.26200.0, PowerShell, Flutter executable `C:\Users\Admin\flutter\bin\flutter.bat`, Dart executable `C:\Users\Admin\flutter\bin\dart.bat`. `flutter --version` and `dart --version` did not return output when attempted during the initial concurrent diagnostic; exact SDK versions remain unknown.
- Last output for both test attempts: none. No test name, progress, or assertion was emitted before interruption.

The next diagnostic should run one Flutter CLI process at a time and capture verbose startup output (`flutter test -v ...`) and process state. Do not infer that the widget tests themselves hang until the runner reaches test execution.

## Decision requested

Please approve, revise, or reject this exact client-only file/test proposal. Until a decision is recorded, no Slice 6A implementation or new test files will be created.
