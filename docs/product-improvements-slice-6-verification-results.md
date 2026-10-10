# Slice 6 — CRUD Lifecycle Verification Results

**Status:** Verification pass complete; implementation not authorized
**Date:** 2026-10-09
**Commit under review:** `97d3870` (Slice 5)
**Scope:** Existing lifecycle behavior only; no source, test, schema, or production-data changes

## Summary

The backend integration suite passed **124 tests**, with **13 opt-in SQL Server tests skipped** and no failures. The focused member-removal, organization-deactivation, snapshot, assignment-history, and purge-history group passed **16/16**. Flutter's existing `flutter test` run produced no output for approximately 135 seconds and was interrupted; its result is **inconclusive**, not passed. Web browser smoke tests were not run because the existing scripts target a local development API and development inbox, and no isolated target was identified for this pass.

Two findings need attention before claiming client lifecycle parity:

1. Web and Flutter member-removal controls call the legacy direct `DELETE` routes instead of the approved preview/confirmation endpoints. The API correctly rejects unresolved open assignments, but the clients do not present the explicit resolution choices needed to complete removal.
2. The purge worker exits before selecting any expired database content when Cloudinary is unconfigured. README documents that expired-media purging is intentionally paused until Cloudinary is configured, but the reason and whether database-only aggregates could proceed are not specified. With that configuration, expired database records and assignment events remain past the retention threshold.

No fixes or new tests were made. Slice 6 implementation remains unauthorized.

## Lifecycle verification matrix

| Resource / operation | API state | Web state | Flutter state | Verification result |
|---|---|---|---|---|
| Organization create/read | Create and list routes exist. No organization detail route found. | Create/select and list flows exist. | Create/select and list flows exist. | Implemented by source inspection; runtime parity not verified. Organization profile update/delete are deferred product decisions. |
| Organization member role/invite | List, fixed-role update, invitation create/accept/cancel exist. | Role and invitation controls exist. | Role and invitation controls exist. | Existing behavior present; full authorization/error matrix not executed in clients. |
| Organization member removal/deactivation | Legacy direct `DELETE` exists. Preview `GET .../deactivation-preview` and confirm `POST .../deactivate` exist and enforce cross-project resolution. | Remove control calls direct `DELETE /organizations/{id}/members/{userId}`. No preview/confirm call found. | `_OrgTab._remove` calls `removeOrgMember`, which calls the same direct `DELETE`. No preview/confirm call found. | **Verified client integration defect.** See Finding 1. |
| Project create/read/update | Create, list, detail, and update routes exist. | Create/edit forms exist. | Create/edit flows exist. | Source-inspected; lifecycle UI runtime not verified. |
| Project archive/restore | Archive uses `DELETE /projects/{id}`; `POST /projects/{id}/restore` restores archive or retained Trash. Authorization differs by restore lifecycle. | Archive and Trash controls plus Trash restore UI exist. | Archive and Trash controls plus Trash restore UI exist. | Routes and controls found. No focused archive/restore API or client tests were found in the inspected test inventory; behavior remains unverified at runtime. |
| Project Trash/restore/purge | Trash route sets `DeletedAt`; restore is limited to 30 days; permanent deletion is worker-managed. Trash listing is authorization-filtered and capped at 200 combined items. | Move-to-Trash and restore controls exist. | Move-to-Trash and restore controls exist. | Core purge-history test passes, but boundary, storage failure, and client refresh behavior remain unverified. See Finding 2. |
| Project member add/read/role | Routes exist; manager/owner invariants and role rules are server-enforced. | List/add/role controls exist. | List/add/role controls exist. | Backend role and invariant tests are in the passing suite; client mutation paths were not browser/widget verified in this pass. |
| Project member removal | Legacy direct `DELETE` exists and rejects open assignments. Preview `GET .../removal-preview` and confirm `POST .../remove` accept `snapshotHash` and explicit resolutions. | Remove control calls direct `DELETE /projects/{id}/members/{userId}`. No preview/confirm call found. | `_ProjectTab._remove` calls `removeProjectMember`, which calls the same direct `DELETE`. No preview/confirm call found. | **Verified client integration defect.** See Finding 1. |
| Task create/read/update | Project task list and create routes; task update route. No standalone task GET route found. | Tasks come from selected project state and open from board/search/dashboard. | `AppState.getTask` searches cache then task lists for selected/known projects; no item GET call. | No direct-entry failure reproduced. Keep task GET as **unverified behavior**, not a verified defect or endpoint requirement. |
| Task Trash/restore | Soft-delete and restore routes exist; restore is time-limited and requires an eligible manager/lead on an active project. | Task detail exposes Move to Trash; Trash screen restores. | Task detail exposes Move to Trash; Trash screen restores. | Routes/controls found, but no focused end-to-end lifecycle test executed. |
| Subtask create/read/update/delete | Create/list/update routes exist. No `DELETE` subtask action route exists. | UI creates and completes/reopens subtasks; no delete control found. | UI creates and completes/reopens subtasks; no delete control found. `ApiClient.deleteSubtask` exists but has no caller. | **Missing capability / latent client contract mismatch.** Calling the unused method would not match a controller route; no current UI path reaches it. Product decision required before adding subtask delete or Trash behavior. |
| Comment create/read/update/delete/restore | List/create, soft-delete, and restore routes exist. No edit route found. | Create/view/delete/restore controls found. | Create/view/delete/restore flows found in source. | Edit remains explicitly deferred. Comment restore and authorization were not runtime-tested in this pass. |
| Attachment upload/read/delete/restore | Upload/list/download, soft-delete, and restore routes exist; purge deletes stored media. | Upload/download/remove and Trash restore controls found. | Upload/download/remove and Trash restore flows found. | Existing Cloudinary unit tests cover upload/download behavior, not the complete Trash/restore/purge lifecycle. Runtime lifecycle remains unverified. |
| Notifications | Recipient list and read/read-all operations exist; no dismiss/delete endpoint found. | List/read controls found. | List/read controls found. | Dismissal is deferred by product decision; no change indicated. |
| Activity, audit, assignment history | Read-only feeds/history; assignment events are purged with task/project content. | Activity surfaces exist; assignment-history UI parity not established. | Activity surfaces exist; assignment-history UI parity not established. | Append-only boundary preserved. Exact activity-event retention after content purge needs an explicit retention policy/review; do not infer a deletion rule. |
| Platform users | SuperAdmin create/list/suspend/permanent-delete routes exist. | Admin user-management surfaces exist. | Admin user-management surfaces exist. | Separate privileged lifecycle; no full client role/error runtime test in this pass. |

## Findings

### Finding 1 — Member removal UI bypasses required preview and confirmation

**Category:** Verified defect
**Severity:** High functional impact; server-side integrity safeguard remains effective
**Affected resources:** Project-member removal and organization-member deactivation
**Code change necessary:** Yes, in Web and Flutter integration, after separate implementation authorization. No backend rule change is proposed.

**Reproduction steps**

1. As an authorized project manager, select a project member who is assigned to an open task and choose Remove.
2. As an organization admin, select an organization member assigned to open tasks across a project and choose Remove.
3. Observe the client request path in the current implementation.

**Expected behavior**

The client requests the applicable removal/deactivation preview, displays affected open tasks and required per-task reassignment/unassignment choices, then submits the returned `snapshotHash` and explicit resolutions to the confirmation endpoint. A stale preview is rejected and refreshed without implying success.

**Actual behavior**

- Web `MembersPage` sends direct `DELETE /projects/{projectId}/members/{userId}` or `DELETE /organizations/{organizationId}/members/{userId}`.
- Flutter `_ProjectTab._remove` and `_OrgTab._remove` call API-client methods that send those same direct `DELETE` routes.
- No Web or Flutter call to `removal-preview`, `deactivation-preview`, `/remove`, or `/deactivate` was found.
- The direct backend paths reject unresolved open assignments with conflict responses. This protects data integrity, but the UI does not show the required task-resolution workflow and the user cannot complete the operation from those controls when open assignments exist.

**Test evidence**

- `ProjectMemberRemovalResolutionTests` verifies preview/confirm resolution, stale-snapshot rejection, and rollback behavior.
- `OrganizationMemberDeactivationResolutionTests` verifies organization-wide resolution across projects and atomicity.
- `SliceOneAuthorizationTests` verifies direct removal is blocked while open assignments remain.
- The 16 focused tests passed. No browser/widget test currently verifies that the clients call preview/confirm.

**Minimal future fix proposal**

Update only the Web and Flutter member-removal flows to consume the existing preview/confirm contracts, render explicit resolutions, and handle stale/limit errors. Keep server authorization and invariants authoritative. Add client tests after the exact files and fixtures are approved.

### Finding 2 — Purger halts all database cleanup when Cloudinary is unconfigured

**Category:** Documented intentional operational behavior; retention/failure semantics still need an owner decision
**Severity:** Medium operational/data-retention risk
**Affected resources:** Expired projects, tasks, comments, attachments, notifications, and task-assignment history
**Code change necessary:** Not established. No change is authorized in this verification pass.

**Reproduction / code path**

1. Configure `ICloudinaryStorage.IsConfigured` as false.
2. Invoke the purge worker's `PurgeExpiredAsync` path with expired records present.
3. `DeletedContentPurger.PurgeExpiredAsync` logs a warning and returns before querying or deleting any database content.

**Expected behavior**

Expired content follows the approved 30-day purge policy, with external media deletion and retry/failure behavior handled without silently retaining all database records indefinitely.

**Actual behavior and intent evidence**

When Cloudinary is unconfigured, the worker performs no database purge at all. It retries on its six-hour interval, but remains blocked until storage becomes configured. README explicitly says expired-media purging remains paused until Cloudinary is configured, so the pause is intentional operational behavior. Neither that note nor the code documents the precise safety rationale. Preserving database references while external asset deletion is unavailable is a reasonable inference, not a confirmed design requirement. The existing test uses configured fake storage and does not establish behavior under missing configuration or storage deletion failure.

**Test evidence**

- `DeletedContentPurgerHistoryTests.Purge_RemovesAssignmentHistoryWithExpiredTasksAndProjects` passed and verifies expired project/task rows and associated assignment history are removed with configured test storage.
- No test was found for `IsConfigured == false`, the exact 30-day cutoff, external deletion failure/retry, or all child-content ordering.
- The full integration suite passed 124, skipped 13 opt-in SQL Server tests, and failed 0.

**Next decision**

Confirm whether the documented Cloudinary configuration requirement is a deployment precondition for the entire purge worker or whether expired aggregates with no remote assets may be purged independently. A possible safe design is to defer only aggregates whose remote-media deletion is unavailable, keeping their asset IDs until deletion succeeds. `CloudinaryStorage.DeleteAsync` treats `ok` and `not found` as success, which appears to support retry after remote deletion but a later database save fails; this should be tested before any change. Do not modify the worker in Slice 6A.

### Finding 3 — Subtask deletion is not an implemented API lifecycle

**Category:** Missing product capability / latent client API mismatch
**Severity:** Low at present; no current UI caller found
**Affected resource:** Subtasks
**Code change necessary:** Only if the product owner decides subtask deletion is in scope.

The backend has subtask create/list/update routes but no subtask DELETE route or restore route. Flutter defines an unused `deleteSubtask` method that calls a route not implemented by `TasksController`; no screen calls that method. Current Web and Flutter screens can create and complete/reopen subtasks but do not expose deletion. No user-reachable failure was reproduced. Preserve this as a product decision; do not add a route merely to make the unused method succeed.

**Test evidence:** Route and caller search only. No test calls `deleteSubtask`; no test code was added.

### Finding 4 — Task detail direct-entry behavior remains unverified

**Category:** Unverified behavior
**Severity:** Unknown; no reproduced defect
**Affected resources:** Task detail navigation
**Code change necessary:** Not established.

No standalone task GET endpoint exists. Flutter `AppState.getTask` searches cached tasks and then lists tasks from the selected and known projects. Web opens task detail from the currently loaded project task data; no task-ID route was found. This review did not reproduce a supported navigation path that fails. Do not add a task GET endpoint unless a controlled client check demonstrates an actual supported entry point cannot load its task.

## Retention, history, and authorization evidence

- The full test run executed 137 tests: **124 passed, 13 skipped, 0 failed**. The skipped tests are opt-in SQL Server migration/concurrency tests because this run had no active SQL Server test connection.
- Focused removal/deactivation/snapshot/purge-history tests: **16 passed, 0 skipped, 0 failed**.
- The focused tests use SQLite/in-memory fixtures; they do not replace the skipped SQL Server concurrency evidence.
- Assignment history is explicitly removed by the purger when its task/project content is permanently purged. The existing purge test proves this for one expired task and one expired project.
- The purger does not delete `ActivityEvent` rows in its task-content removal routine. The approved record says history follows the established policy but this pass did not find a documented activity-event retention/purge rule. Do not change or backfill these records until that policy is clarified.
- Existing backend tests exercise important owner, manager, guest, eligibility, cross-tenant, and atomicity safeguards. A complete role-by-operation matrix for every archive/Trash/restore endpoint was not found or executed.

## Client and test execution limitations

- Web smoke helpers default to `http://localhost:5141/api/v1`, require the development inbox, create temporary accounts/data, and invoke a cleanup script. They were not run because the active API/database could not be confirmed as an isolated disposable environment.
- Flutter `flutter test` emitted no output for about 135 seconds and was interrupted. A single existing test, `flutter test test/api_client_test.dart --plain-name "uses the Android emulator API address by default" --reporter expanded`, also emitted no output for about 90 seconds before interruption. This reproduces the CLI stall with one test selected; neither run emitted test progress or an assertion, so both results are **inconclusive**. The environment was Windows NT 10.0.26200.0 / PowerShell using `C:\Users\Admin\flutter\bin\flutter.bat`; exact Flutter/Dart versions could not be retrieved because version commands did not return during the initial diagnostic. No Flutter source or test files were changed.
- No production service, database, or purge operation was invoked.
- No test files were modified. If client preview/confirmation coverage is required before implementation, propose exact additions to existing Web Playwright and Flutter widget/API test files and isolated mock/fixture boundaries for approval first.

## Recommended classification and next actions

| Category | Finding | Next action |
|---|---|---|
| Verified defect | Web and Flutter member-removal controls bypass required preview/confirmation | Review and authorize a narrow client-only fix with tests; preserve all server safeguards. |
| Documented intentional behavior requiring policy/operations decision | Purging stops globally when Cloudinary is unconfigured | Confirm whether configuration is a deployment precondition for all purge work or allow no-media aggregates to proceed while retaining remote asset references for retry. |
| Missing product capability | Subtask deletion route is absent; unused Flutter client method has no UI caller | Keep deferred unless deletion semantics and restore behavior are separately approved. |
| Unverified behavior | Task direct-entry flow, full archive/Trash/restore client flows, complete authorization matrix, purge failures/cutoff | Approve exact focused tests and isolated fixture boundaries before adding test code or running stateful client checks. |

## Authorization boundary

This document records verification only. No application or test code, schema, API contract, production data, commit, push, or deployment was changed or authorized. Existing unrelated Flutter role-editing and documentation changes remain untouched.

**Slice 6 implementation: not authorized.** The next decision is whether to authorize only the member-removal client workflow fix, and whether purge configuration behavior needs an operational requirement or a separately scoped design review.
