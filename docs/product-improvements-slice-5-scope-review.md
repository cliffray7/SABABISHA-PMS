# Slice 5 — Web and Flutter Integration Scope Review

**Review status:** Scope approved with defined boundaries
**Implementation status:** Locally authorized; exact implementation file list pending approval
**Review date:** 2026-10-08
**Scope:** Read-only source audit and implementation proposal; no application code changed.

## 1. Purpose and approved foundation

Slice 5 is intended to make Web and Flutter consume the authoritative project progress contract introduced in Slice 4, remove conflicting client-side project-progress calculations, and display the approved project and task status labels consistently. It must preserve personal workload metrics as a separate concept.

The API dependency is `GET /api/v1/projects/{projectId}/progress`, documented in [project-progress-api-contract.md](project-progress-api-contract.md). The response contains `projectId`, `projectStatus`, `hasTasks`, `totalEligibleTasks`, `completedTasks`, nullable `progressPercent`, `outstandingTaskCount`, `overdueTaskCount`, and `timezoneIdUsed`.

The accepted calculation covers all eligible non-deleted top-level project tasks, regardless of assignee; only `DONE` tasks count as complete. Subtasks and deleted tasks are excluded. An empty project has `hasTasks: false`, zero counts, and `progressPercent: null`; a non-empty project with no completed tasks has 0%. Project lifecycle status stays independent of progress. Overdue means an outstanding task's due calendar date precedes the organization's current local date. Invalid or missing organization timezones resolve to UTC on the server.

Approved display labels from [product-improvements-progress-status.md](product-improvements-progress-status.md):

| Stored project status | Display label |
| --- | --- |
| `PLANNING` | Planned |
| `ACTIVE` | In Progress |
| `ON_HOLD` | On Hold |
| `COMPLETED` | Completed |

| Stored task status | Display label |
| --- | --- |
| `TO DO` | To Do |
| `IN PROGRESS` | In Progress |
| `REVIEW` | In Review |
| `DONE` | Done |

These are presentation mappings only. Stored status values and existing write contracts must not change.

## 2. Read-only findings

| Area | Web current behavior | Flutter current behavior | Slice 5 implication |
| --- | --- | --- | --- |
| Project progress | `Dashboard` in `apps/web/src/main.tsx` calculates progress from a role-dependent `scopeTasks` list. Team roles see project tasks; other contributors may see only their assignments. Empty scope currently appears as 0%. | `DashboardScreen` in `apps/mobile/lib/src/screens/dashboard_screen.dart` has the same project-vs-personal split and computes `done / scopeTasks.length`, using 0 for empty. | Project health must use the progress endpoint for every role, so assignee filtering cannot change project progress. Personal workload remains based on personal task data/metrics. |
| Personal metrics | `/dashboard/metrics` is loaded alongside task data and is used for dashboard/workload information. | `ApiClient.dashboardMetrics(projectId)` loads `/dashboard/metrics`; `DashboardMetrics` contains personal/task metric fields. | Keep this endpoint and its personal metrics contract unchanged. Do not replace personal counts with project aggregates. |
| Overdue totals | `overdue(task)` in `apps/web/src/api.ts` compares a due-date string with the browser's local date. Dashboard totals and task lists use that helper. | `Task.isOverdue` in `apps/mobile/lib/src/models/models.dart` compares parsed due date/time with device `DateTime.now()`. Dashboard totals and task lists use it. | The aggregate dashboard/project-health overdue number can use `overdueTaskCount`. Per-task overdue badges and filters cannot be made organization-timezone authoritative from this response alone. See the decision gate below. |
| Status labels | Task labels are assembled in the dashboard and task views; current wording includes variants such as “To do”, “In progress”, “Review”, and “Completed”. Project status is commonly lowercased/formatted ad hoc. | `common.dart` provides task status coloring; labels are also assembled inline (for example dashboard status distribution); project status often uses raw/lowercased values. | Centralize the approved display mapping in each client and reuse it for the relevant project/task status displays without altering stored values, filters, or API payloads. |
| Refresh | The Web app increments `liveDataVersion` for task/project workspace events, on reconnect, focus, and online events; its project-data effect reloads tasks, members, and dashboard metrics. | `AppState` refreshes project data on `workspaceChanged`; architecture also has reconnect/focus and periodic refresh behavior. `_loadProjectData` currently fetches tasks, project members, and dashboard metrics. | Add progress data to the same project-scoped loading/invalidation lifecycle. Ensure a task mutation and realtime refresh update the aggregate, and switching project IDs cannot show the prior project's response. |
| Loading/errors | A shared error state is populated on failed project-data loads; dashboard rendering should not silently substitute a locally calculated project percentage when the progress request fails. | `AppState` has `loadingTasks` and `error`; project dashboard is driven from that state. | Define visible loading, retry, and error behavior for the progress panel. A missing/failed aggregate must not be presented as a valid 0%. |
| Empty state | Local computation currently yields 0% for no tasks. | Local computation currently yields 0% for no tasks. | Render “No tasks” (or equivalent empty copy) with no progress percentage when `hasTasks` is false. Distinguish this from a non-empty 0% project. |

### Source locations audited

- Web fetch and refresh state: `apps/web/src/main.tsx` (`workspaceChanged` handling and project data loading effect).
- Web dashboard calculations and labels: `apps/web/src/main.tsx` (`Dashboard` and task/project rendering); `apps/web/src/api.ts` (`DashboardMetrics`, `projectStatuses`, and `overdue`).
- Flutter refresh and project data: `apps/mobile/lib/src/services/app_state.dart` (`workspaceChanged`, `_refreshFromRealtime`, and `_loadProjectData`).
- Flutter API and data models: `apps/mobile/lib/src/services/api_client.dart` (`dashboardMetrics`); `apps/mobile/lib/src/models/models.dart` (`Project`, `Task.isOverdue`, `DashboardMetrics`, and status constants).
- Flutter dashboard and shared task presentation: `apps/mobile/lib/src/screens/dashboard_screen.dart`, `apps/mobile/lib/src/screens/board_screen.dart`, and `apps/mobile/lib/src/widgets/common.dart`.
- Existing test setup: Web scripts in `apps/web/package.json` use Node smoke tests and `playwright-core`; Flutter has `flutter_test` and API client tests. No new package is proposed.

## 3. Proposed integration behavior

This section is a proposal for review, not implementation authorization.

1. Add typed progress-response parsing and a project-scoped fetch method in each client's existing API layer.
2. Fetch progress with the existing project data load and refresh it on the same project/task invalidation paths. Treat response identity as project-scoped; discard a late response if the user has switched projects.
3. Use `progressPercent`, `completedTasks`, `totalEligibleTasks`, `outstandingTaskCount`, and `overdueTaskCount` for project-wide health/progress displays for every active project role. Do not derive project progress from the visible or assigned task subset.
4. Keep personal workload panels and `/dashboard/metrics` semantics intact. Any personal progress display should remain explicitly personal and must not be labelled as project progress.
5. Render the empty-project state using `hasTasks`; render a numeric 0% only when tasks exist and the API says 0. If progress is unavailable because of an error, show a retryable error state rather than a calculated fallback.
6. Apply the approved display labels to project and task status text in the screens included in the approved implementation boundary. Preserve raw values for API writes, comparisons, and filters.
7. Keep the project lifecycle label independent from task progress. A project marked `COMPLETED` may display less than 100% and must not be automatically changed or reopened.
8. Use the authoritative overdue aggregate in project-level summary displays. Do not infer per-task organization-timezone overdue status from `timezoneIdUsed` on the client.

## 4. Recorded product decision and remaining questions

### A. Task-card overdue indicators — decision recorded

**Decision (2026-10-08):** Keep Slice 5 within the existing Slice 4 API contract for overdue data.

- Project dashboards consume `overdueTaskCount` from the authoritative progress endpoint.
- Task cards and filters retain their existing behavior temporarily. Those local calculations must not be presented as equivalent to the authoritative project overdue count.
- Do not infer a per-task organization-timezone flag from `timezoneIdUsed`; an aggregate count cannot identify which tasks are overdue.
- Record a separate backend/API follow-up proposing an additive server-computed `isOverdue` field for task responses, using the same organization-timezone rules as Slice 4. After separate approval and availability, Web and Flutter can use it for task badges and filters.

This decision does not authorize that backend/API enhancement as part of Slice 5.

### B. Progress endpoint rollout compatibility — decision recorded

Deploy the Slice 4 backend endpoint before deploying clients that require it. If a client reaches an older backend without the endpoint, show an explicit unavailable state. Never silently substitute locally calculated project progress.

### C. Status mapping coverage — decision recorded

Centralize the approved display mappings within the Slice 5 dashboard and task-board surfaces. Administrative screens and reports are outside this slice; broad label cleanup requires separate review. Unknown future values need a readable fallback. Keep stored codes unchanged for filtering, comparisons, and API writes.

## 4.1 Final implementation boundaries

The product owner approved local Web and Flutter implementation and verification, subject to exact file-list review. This does not authorize committing, pushing, deploying, or starting Slice 6.

- Project progress and project overdue totals use the authoritative endpoint for every authorized role.
- Personal workload metrics and `/dashboard/metrics` semantics remain unchanged and clearly distinct from project progress.
- Empty, numeric-zero, loading, unavailable, retry, refresh, and project-switch behavior follow the acceptance criteria below.
- Dashboard/task-board status labels use the approved mappings; raw status values stay unchanged.
- Task-card overdue badges and filters retain their current behavior temporarily and must not be described as organization-timezone authoritative. A server-computed task `isOverdue` field is a separate backend/API follow-up, not part of Slice 5.
- No backend, SQL, schema, stored-procedure, member screen, role-editing, admin/report, or unrelated documentation changes are authorized.

## 5. Proposed exact implementation file list

The product owner approved the scope boundaries and requested the concrete file list before coding. The following files are proposed; none of the application files below have been changed for Slice 5.

### Web

1. `apps/web/src/api.ts` — add the typed nine-field progress response, request helper, and approved project/task display-label helpers with readable unknown-value fallbacks.
2. `apps/web/src/main.tsx` — fetch/store progress by selected project; refresh through existing task/project invalidation paths; discard stale responses on project switch; consume aggregate values in project dashboard; show empty/unavailable/retry states; apply approved labels on dashboard and task-board surfaces. Preserve personal workload logic and keep unrelated screens unchanged.
3. `apps/web/tests/project-progress-smoke.mjs` — deterministic Playwright smoke coverage with route interception. Mock account, organization, project, task, personal-metrics, and progress requests; cover role-independent aggregate rendering, empty vs 0%, unavailable/retry, refresh, project switching, and status labels.
4. `apps/web/package.json` — register the focused smoke script only. Add no dependency.

### Flutter

5. `apps/mobile/lib/src/models/models.dart` — add the typed project progress model and approved status-label helpers with a readable fallback.
6. `apps/mobile/lib/src/services/api_client.dart` — add the progress endpoint request method. This file currently contains pre-existing, unrelated role-editing changes; preserve those edits and modify only the minimum required lines for progress.
7. `apps/mobile/lib/src/services/app_state.dart` — load progress with selected-project data, expose loading/error/retry behavior, refresh with current task/project refresh paths, and prevent stale responses replacing current-project data.
8. `apps/mobile/lib/src/screens/dashboard_screen.dart` — render backend project progress and counts, keep personal metrics separate, and handle empty/loading/unavailable/retry states.
9. `apps/mobile/lib/src/widgets/common.dart` — use approved task labels in shared dashboard/board presentation while preserving raw status values for behavior.
10. `apps/mobile/lib/src/screens/board_screen.dart` — apply approved task status display labels only. Preserve existing per-task overdue badge/filter behavior; do not claim it is timezone-authoritative.
11. `apps/mobile/test/project_progress_api_test.dart` — test response parsing (including nullable percentage), route, and API error propagation using existing mock HTTP support.
12. `apps/mobile/test/project_progress_widget_test.dart` — test dashboard empty vs 0%, authoritative aggregates independent of role/assignment scope, loading/error/retry, labels/fallback, and refresh/project-switch behavior where test seams permit.

No stylesheet change is planned; reuse existing loading, error, retry, and empty widgets/styles. If implementation proves a new style is necessary, return the additional file for approval before changing it.

### Explicit exclusions

- Backend, SQL, schema, or stored-procedure changes, including the separate per-task `isOverdue` enhancement.
- Changes to `/dashboard/metrics` or personal workload definitions.
- Changes to persisted project/task status values or existing write endpoints.
- Suspended-account authorization remediation, Slice 3 deployment work, CRUD expansion, and unrelated role-editing work.
- Changes to `apps/mobile/lib/src/screens/members_screen.dart` or unrelated existing Flutter role-editing modifications.
- Progress changes in PDF/admin reports already aligned in Slice 4.

## 6. Proposed acceptance and verification tests

### API client and data parsing

- Both clients deserialize all nine fields from the documented response, including `progressPercent: null` and `timezoneIdUsed`.
- Project IDs containing normal UUID values are URL-encoded/used safely in the route.
- HTTP 403/404 or a network failure is surfaced as unavailable/error, never as 0% or stale data.

### Progress and personal-metric separation

- A contributor's project summary uses project-wide aggregate values even when some eligible tasks are assigned to other users.
- A manager and contributor see the same project aggregate for the same project.
- Personal workload counts continue to use existing personal task/metrics semantics and do not change when the project aggregate is loaded.
- Completed project status remains displayed as Completed when progress is below 100%; no client-side status mutation occurs.

### Empty, zero, loading, and failure states

- Empty project: “No tasks” state, no percentage, and zero counts.
- Non-empty project at 0%: displays 0%, not the empty state.
- Loading progress: clear loading treatment without a temporary locally calculated value.
- Request failure: clear error/retry behavior and no misleading 0% fallback.
- On retry success, the correct project aggregate is shown.

### Refresh and project switching

- Task creation, completion, deletion/trash changes, and task status changes refresh the aggregate via the existing invalidation/realtime path.
- Reconnect/resume refreshes progress together with project data.
- A slow response for a previously selected project cannot overwrite the selected project's progress after switching.
- Project/member access failure clears or replaces prior progress data instead of retaining it under the new project.

### Status labels

- Unit/widget or smoke assertions cover all four approved project labels and all four approved task labels.
- Unknown future status values use a safe readable fallback and do not break rendering.
- Underlying values submitted to existing APIs remain unchanged.

### Overdue behavior

- Project-level overdue summary consumes `overdueTaskCount`, not client-recomputed counts.
- Per-task overdue badges and filters retain existing behavior temporarily and are not represented as timezone-authoritative; the separate `isOverdue` endpoint enhancement is excluded.
- Do not add client timezone tests as a substitute for the backend timezone contract.

### Test execution approach

- Web: use existing Node smoke scripts and Playwright route interception to mock the progress API deterministically; no seeded backend state or new test dependency.
- Flutter: use existing `flutter_test` and API client mock transport; add focused widget/state tests without new packages.
- Run the Web build and relevant/new Web smoke test(s), then `flutter analyze` and Flutter tests for the changed areas. Report actual results and skipped tests.

## 7. Dependencies, risks, and rollout

- **Backend availability:** Slice 4's endpoint is required. Deploy the endpoint before client rollout unless an explicit backward-compatibility behavior is approved.
- **Authorization:** The endpoint intentionally follows the existing project-read policy and returns aggregates without task details. This slice must not broaden access. The separately tracked suspended-account issue remains unresolved.
- **Overdue mismatch:** Project aggregates are authoritative; task-card indicators remain on existing behavior until a separate API enhancement is approved and available.
- **State consistency:** The aggregate and task list may refresh concurrently; avoid making one an implicit denominator for the other. The backend aggregate is authoritative for project-wide figures.
- **Empty vs unavailable:** Null progress is a valid empty-project result; missing progress due to a failed request is an error state.
- **Archived/trashed projects:** The progress endpoint follows the contract's existing access/lifecycle behavior. Clients must display the server response and must not fabricate active progress for inaccessible projects.
- **Existing working tree:** The current workspace has pre-existing Flutter role-editing and roadmap/progress documentation changes. Those are outside this review and must remain untouched and unstaged.

## 8. Approval checkpoint

The product owner has authorized Slice 5 local implementation within the stated boundaries, then explicitly required approval of the exact file list and planned tests before implementation. Await that approval for the 12 files in Section 5. After approval, the implementation checkpoint must report exact changed files, Web build and smoke-test results, Flutter analysis and focused-test results, remaining known inconsistencies, and `git diff --check`. No commit, push, deployment, or Slice 6 work is authorized.
