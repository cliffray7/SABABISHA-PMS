# Slice 4 — Authoritative Backend Progress and Status: Scope Review

**Status:** Product-owner scope approved; backend implementation review checkpoint

**Reviewed:** 2026-10-08

**Implementation authorization:** Granted for the backend-only Slice 4 boundary below
**Product rules:** See the approved decisions in [Project Progress and Status Rules](product-improvements-progress-status.md).

The product owner approved dedicated `GET /api/v1/projects/{projectId}/progress`, the proposed response fields, historical labeling for archived projects in the platform PDF, deferral of per-task overdue flags, midpoint rounding away from zero, and a backend-only implementation boundary. The exact endpoint contract is recorded in [Project Progress API Contract](project-progress-api-contract.md). `TasksController.cs`, all Web/Flutter files, SQL stored procedures, and database migrations are excluded.

The initial scope audit inspected existing backend, SQL, Web, Flutter, and platform-report behavior before implementation. The implementation and verification record below documents the approved backend changes.

## Review summary

Before Slice 4, the repository had no server-authoritative project progress result. The Web and Flutter dashboards each calculate the displayed percentage from their locally loaded task list. Their task lists are currently top-level and non-deleted, but each client narrows that set differently by caller role: project managers/team leads and organization admins/owners see project tasks; other users see only tasks assigned to themselves. Both show `0%` for an empty set.

The existing `/api/v1/dashboard/metrics` endpoint is a personal assignment metric, not a project progress contract. It is backed by `usp_GetDashboardMetrics`, which counts active assignments, includes subtasks, compares due dates with UTC server time, and does not exclude archived projects. Its response shape should remain unchanged for compatibility. The platform PDF report also independently calculates per-project progress, using a different task set and terminal-status predicate, so it must be included in the shared-calculation review.

The approved product rule in `product-improvements-progress-status.md` resolves the core formula: count all non-deleted top-level tasks in the project, regardless of assignee; only `DONE` is completed; exclude subtasks and soft-deleted tasks; return an explicit empty state; derive overdue from the organization/project-local date. Existing project and task status values remain persisted as-is, with the owner-approved display labels from that specification.

## Existing behavior found

### Backend APIs and calculations

| Area | Current behavior | Consequence for Slice 4 |
|---|---|---|
| `GET /api/v1/tasks?projectId=...` | `TasksController.List` first checks read access, then returns non-deleted top-level tasks and subtask counts. Archived/trashed project access is rejected through shared project authorization. | This is the closest existing source set for eligible tasks, but the new aggregate must be computed on the server and must not rely on a client-filtered list. |
| `GET /api/v1/dashboard/metrics?projectId=...` | `DashboardController` checks active project and organization membership when a project ID is supplied, then calls Dapper `DashboardRepository` and `usp_GetDashboardMetrics`. Response fields are `myTasks`, `overdueTasks`, `completedTasks`, `inProgressTasks`, and `totalTasks`. | This is caller-assignment-centric. It does not provide project-wide completion, `hasTasks`, or a nullable percentage. Preserve its route and response contract. |
| `usp_GetDashboardMetrics` | Joins active `task_assignees`; filters soft-deleted tasks and projects; has no `parent_task_id IS NULL` or archived-project predicate; computes overdue using `due_date < SYSUTCDATETIME()`. | It can count subtasks, counts a date-only task as overdue during its due date after midnight UTC, and can include archived-project tasks. It does not use organization timezone. It is not a suitable query to reuse as project progress. |
| `GET /api/v1/admin/dashboard` | Platform-wide metrics count top-level, non-deleted tasks in non-deleted projects and count `DONE` tasks separately. The query does not exclude archived projects. | This is global administration data, not tenant/project progress. Keep its contract and policy separate. |
| Platform PDF report (`/api/v1/admin/reports?format=pdf`) | `AdminController` loads non-deleted projects and non-deleted tasks, including subtasks and tasks belonging to archived projects. `PlatformReportExport.Pdf` groups all loaded tasks by project, treats both `DONE` and `COMPLETED` as done, calculates `Math.Round(done / total * 100)`, and represents an empty project as `0%`. | This conflicts with the approved top-level-only denominator, `DONE`-only completion, explicit empty state, and project lifecycle visibility. If the report is intended to show archived history, it still needs the same task predicate and must label the result as historical; do not let its private formula become a second definition. CSV/XLSX export raw project/task records rather than a project progress percentage. |
| Project/task validation | `ProjectsController` accepts `PLANNING`, `ACTIVE`, `ON_HOLD`, `COMPLETED`; `TasksController` accepts `TO DO`, `IN PROGRESS`, `REVIEW`, `DONE`. Subtasks are currently created as `TO DO` and toggled between `TO DO` and `DONE`. | The stored status sets are fixed and already validated. Slice 4 should not add or rename persisted values. |

The domain has `Organization.Timezone`, defaulting to `UTC`, and `User.Timezone`. The account profile route writes the user timezone. The repository search did not find an organization-timezone update route or a project-timezone field. The approved fallback therefore currently resolves to the organization’s stored value, normally `UTC`; the source and validation of future organization timezone values should be confirmed before implementation.

### Web and Flutter consumers

| Surface | Current progress and task-set behavior | Current overdue/status behavior |
|---|---|---|
| Web workspace dashboard | `main.tsx` loads `/tasks`, `/projects/{id}/members`, and `/dashboard/metrics`. The dashboard computes completed count and percentage locally from `tasks`; project roles see the whole loaded list, other roles see their assigned subset. Empty is `0%`. The fetched `metrics` state is not used in the progress calculation. | `api.ts` compares the `YYYY-MM-DD` due-date prefix with the browser-local calendar date. Dashboard status labels are hand-mapped (`REVIEW` displays “Review”; `DONE` displays “Completed”). Project labels are generated from stored values (`PLANNING` displays “Planning”; `ACTIVE` displays “Active”). |
| Flutter workspace dashboard | `AppState._loadProjectData` fetches tasks, members, and `/dashboard/metrics`; `DashboardScreen` computes completion from local tasks using the same role split and shows `0%` for empty. Stored `metrics` are not used in its progress calculation. | `Task.isOverdue` parses `dueDate` and compares it with device `DateTime.now()`, which can mark a date-only due date overdue during that same calendar day. Dashboard charts label `DONE` as “Completed”; project chips lowercase the stored value, so `ON_HOLD` may display as `on_hold`. |
| Flutter workspace dashboard | `AppState._loadProjectData` fetches tasks, members, and `/dashboard/metrics`; `DashboardScreen` computes completion from local tasks using the same role split and shows `0%` for empty. Stored `metrics` are not used in its progress calculation. | `Task.isOverdue` parses `dueDate` and compares it with device `DateTime.now()`, which can mark a date-only due date overdue during that same calendar day. Dashboard charts label `DONE` as “Completed”; project chips lowercase the stored value, so `ON_HOLD` may display as `on_hold`. |
| Web and Flutter task boards | Boards show task counts by stored status and separate parent-task subtask counts; they do not calculate an overall project percentage. | Each client marks individual task cards overdue using its own browser/device clock. A project-level overdue count from a new endpoint would not by itself align those per-task badges. If board overdue labels must also be authoritative, the task response needs a timezone-resolved `isOverdue` field or an equivalent approved shared source. |
| Flutter platform admin reports/project lists | Platform dashboard shows total/completed tasks; project lists show task counts and status, not a separate project completion calculation. The downloaded platform PDF is generated by the backend path above. | Keep global counts distinct from tenant project progress. Flutter admin status labels are also not the same as the approved display table in all screens. |
| Web and Flutter task/project forms | Forms submit the existing fixed stored status values. | Forms and other views also display raw, title-cased, or locally transformed statuses; labels are not consistently centralized. |

The client-side progress differences are substantive: viewers/contributors currently see their personal assigned-task completion under the same general dashboard progress presentation that managers see as project completion. The new API result must be project-wide for every authorized active project member, per the approved rule; personal workload remains separately labelled and can continue using personal metrics.

### Approved status display table

The owner-approved mapping already recorded in `product-improvements-progress-status.md` is:

| Scope | Stored value (unchanged) | Approved display label |
|---|---|---|
| Project | `PLANNING` | Planned |
| Project | `ACTIVE` | In Progress |
| Project | `ON_HOLD` | On Hold |
| Project | `COMPLETED` | Completed |
| Task | `TO DO` | To Do |
| Task | `IN PROGRESS` | In Progress |
| Task | `REVIEW` | In Review |
| Task | `DONE` | Done |

`PENDING` is not an existing or approved value. Do not add it or reinterpret `REVIEW`. The current clients differ from several approved labels, but correcting visible labels belongs in a separately authorized client implementation boundary unless the owner explicitly combines it with Slice 4.

## Approved Slice 4 boundary

The approved implementation scope is a backend-only, additive project progress query. It must:

1. Use the approved eligible set: non-deleted top-level tasks for the requested project; include all assignees/statuses; only `DONE` is complete. Subtask counts remain separate task-detail information.
2. Return project-wide aggregate progress to active project members, including members whose role does not permit viewing all individual task details. The route must authorize the project and organization membership server-side and must not return task details. Reuse the existing read policy; do not broaden task access.
3. Keep project lifecycle status independent from task progress. A non-archived/non-trashed project whose status is `COMPLETED` still returns `projectStatus: "COMPLETED"` and a live task-derived percentage. For 8 of 10 eligible tasks in `DONE`, return 80%; do not auto-complete at 100%, reopen when progress falls, or add a lifecycle consistency indicator in this slice.
4. Exclude archived/trashed projects from active tracking as approved. Historical report inclusion is separate: if a platform report includes archived projects, label it as historical and calculate with the same eligible-task predicate. Do not mutate or backfill statuses.
5. Use `Organization.Timezone` for local calendar date. A project timezone field does not exist and would require separate approval. If the timezone is missing or invalid, use UTC and emit an internal diagnostic warning; do not expose configuration details in the API response. Count an outstanding task as overdue only when its due calendar date is before the resolved organization's local date; tasks due today and tasks with no due date are not overdue. Capture the clock once per calculation and expose only the resolved timezone identifier (for example, UTC) if that field is approved.
6. Calculate `RoundAwayFromZero(DONE eligible top-level tasks / all eligible top-level tasks * 100)`. Exact `.5` values round away from zero; return the rounded percentage so clients do not recompute or round it.
7. Return consistent counts: `outstandingTaskCount` is the eligible tasks whose stored status is not `DONE`; `overdueTaskCount` is the subset of outstanding eligible tasks with a due date before local today. For an empty project, return `hasTasks: false`, a null percentage, and zero counts; a non-empty project with no `DONE` tasks returns `hasTasks: true` and `progressPercent: 0`.
8. Keep `/api/v1/dashboard/metrics`, existing project/task fields, and persisted status values unchanged. Do not add a schema migration unless implementation discovers a verified requirement; current aggregate fields are derivable from existing columns.

### Approved additive response

The approved endpoint is `GET /api/v1/projects/{projectId}/progress`, with this response shape:

```json
{
  "projectId": "<guid>",
  "projectStatus": "ACTIVE",
  "hasTasks": true,
  "totalEligibleTasks": 10,
  "completedTasks": 4,
  "progressPercent": 40,
  "outstandingTaskCount": 6,
  "overdueTaskCount": 2,
  "timezoneIdUsed": "Africa/Nairobi"
}
```

For a `COMPLETED` project with 8 of 10 eligible tasks `DONE`, retain `projectStatus: "COMPLETED"` and return `progressPercent: 80`; no automatic status transition occurs. For an empty project, use `hasTasks: false`, `totalEligibleTasks: 0`, zero counts, and `progressPercent: null`; a non-empty project with 0 completed tasks uses `hasTasks: true` and `progressPercent: 0`. `outstandingTaskCount` and `overdueTaskCount` follow the predicates above. If timezone resolution falls back due to a missing/invalid organization timezone, use UTC and log internally; never return invalid raw configuration. The endpoint and response names are approved; see `docs/project-progress-api-contract.md` for the final contract.

The route uses the existing forbidden response for inaccessible, cross-tenant, inactive-member, archived, or trashed project reads; an accessible empty project returns 200 with `hasTasks: false`. Unauthenticated requests continue to use the existing 401 behavior.

## Compatibility and security

- No stored status values, existing endpoint response shapes, project/task authorization rules, or task-detail visibility should change.
- The aggregate is an additive authenticated read route. Verify cross-tenant project IDs, inactive organization/project memberships, guest membership, archived/trashed projects, and empty accessible projects.
- Existing suspended-account access is a separate accepted security follow-up. Do not silently implement that global change in Slice 4; call out that the new route must follow the same current project read policy and coordinate the separate security fix before production if required.
- The current `/dashboard/metrics` stored procedure and the admin dashboard are separate personal/platform metrics. Do not silently relabel either as project completion.
- No database migration is expected for the approved calculation. `Organization.Timezone` is already present. If timezone configuration, new statuses, or historical progress snapshots are required, stop and request separate approval.

## Verification coverage

Backend tests should cover:

- Empty project response (`hasTasks`, null percentage, zero counts).
- Non-empty project with 0% completion, distinguished from the empty state.
- A project stored as `COMPLETED` with incomplete tasks returns the unchanged status and actual task progress; reaching 100% or decreasing progress never changes project status.
- Mixed status tasks and percentage rounding boundaries; only `DONE` counts completed.
- Parent tasks with subtasks, proving subtasks do not enter the denominator or numerator.
- Soft-deleted tasks excluded; archived/trashed project behavior; a non-archived `COMPLETED` project according to the owner decision above.
- Due dates yesterday, today, tomorrow, and null under the organization timezone; UTC fallback; invalid timezone behavior; a timezone/date boundary case.
- Invalid timezone causes an internal warning and UTC-based local date calculation without exposing the invalid value to the client.
- Cross-tenant IDs, non-member, inactive organization/project membership, and allowed project-member aggregate access without task details.
- Consistency of the new result across roles and preservation of existing `/dashboard/metrics` response shape.
- Preserve the stored project/task status values in the API; display-label changes remain deferred to client integration.

The full backend suite should run. If the implementation uses SQL Server-specific aggregate behavior, run the focused test against an isolated SQL Server database. No production migration or production data query is needed for this derived read model.

Client verification belongs to a later authorized client slice: ensure Web and Flutter read the same response, remove role-dependent project-progress math, preserve separate personal workload metrics, and refresh on existing task/project SignalR invalidations. Determine whether board cards also require a server-computed per-task overdue flag; the aggregate count alone cannot correct each card's local-clock badge. Use the approved labels while retaining raw codes for forms, filters, and API writes. Do not declare dashboards aligned while they still show client-computed values.

The backend-generated platform PDF must be reviewed alongside the endpoint. Reuse the same shared task-progress calculator for each included project, or explicitly specify its historical-project scope with the same denominator/completion semantics. Do not leave `PlatformReportExport` with an independent progress formula.

## Approved implementation file boundary

### Implemented Slice 4 files

- `src/Pms.Api/Controllers/Rest/V1/ProjectsController.cs` — add the authenticated project-progress route using existing project-read authorization.
- `src/Pms.Api/Progress/ProjectProgressCalculator.cs` — shared task eligibility, completion, rounding, timezone, and overdue calculation; no persisted state or DI registration.
- `src/Pms.Api/Reports/PlatformReportExport.cs` — use the shared top-level/`DONE` calculation in PDF output, label archived rows as historical, and show `No tasks` for empty projects.
- `src/Pms.Api/Controllers/Rest/V1/AdminController.cs` — supply archived-project and task parent/deletion metadata required by PDF calculation; raw CSV/XLSX records and dashboard metrics remain unchanged.


- `tests/Pms.IntegrationTests/ProjectProgressTests.cs` — authorization, empty, denominator, status, timezone, rounding, and PDF consistency coverage.

- `docs/project-progress-api-contract.md` — approved route, response, errors, eligibility, timezone, and compatibility contract.
- `docs/product-improvements-slice-4-scope-review.md` and `context/progress-tracker.md` — record authorization and actual verification results.

No migration or `DashboardRepository`/`usp_GetDashboardMetrics` change is proposed. Web and Flutter files remain outside this backend-only slice, but their existing client calculations must be listed as a release dependency: before dashboards can be described as authoritative, a separately authorized client slice must consume this API. This is the approved implementation boundary; `TasksController.cs` and `Program.cs` are excluded.

### Consumer files inspected; no Slice 4 edits proposed

- Web: `apps/web/src/main.tsx`, `apps/web/src/api.ts`, `apps/web/src/Forms.tsx`, `apps/web/src/AdminDashboard.tsx`, `apps/web/src/AdminManagement.tsx`.
- Flutter: `apps/mobile/lib/src/services/app_state.dart`, `apps/mobile/lib/src/models/models.dart`, `apps/mobile/lib/src/screens/dashboard_screen.dart`, `apps/mobile/lib/src/screens/board_screen.dart`, `apps/mobile/lib/src/screens/task_detail_screen.dart`, `apps/mobile/lib/src/widgets/common.dart`, `apps/mobile/lib/src/screens/admin_screen.dart`.

The Web and Flutter consumers should be updated only in a separately authorized client slice. The approved API shape is recorded in `docs/project-progress-api-contract.md`.

## Implementation review checkpoint

Slice 4 implementation is complete at the review checkpoint. Focused tests passed 12/12; full `dotnet test Sababisha.Pms.slnx --no-restore` passed UnitTests 1/1 and IntegrationTests 124/124, with 13 opt-in SQL Server tests skipped because the SQL Server test connection was not configured. This slice introduces no SQL-specific progress behavior, migration, or SQL Server concurrency dependency. `git diff --check` passed; Git reported only existing LF/CRLF notices. Do not commit, push, deploy, or begin Slice 5. Preserve unrelated Flutter and roadmap changes. Web/Flutter progress consumption, task-board per-task overdue flags, and approved display-label changes remain a later client slice. The suspended-account security follow-up and Slice 3 deployment checks remain separate.