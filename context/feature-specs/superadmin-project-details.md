# Super Admin Project Details

**Status:** Implemented locally; acceptance review pending
**Scope:** Read-only organization and project drill-down for platform Super Admins.

## User flow

Super Admins can open Organizations, move to that organization's projects, and open any project in the platform Projects page. A project details view has Overview, Members, Tasks, and Activity tabs. The existing Activity page remains the separate platform-wide explorer.

## Authorization and data

- All new project detail routes are under `/api/v1/admin/*` and inherit the existing `SuperAdmin` policy. They do not require tenant membership.
- Responses are read-only and omit credentials, project/task descriptions, member email addresses, and task assignment identities.
- Existing list defaults and the global activity contract remain unchanged.
- Project overview uses the shared progress calculator and reports aggregate counts. Archived and retained-Trash projects are clearly identified as historical.
- Member and task rows are paged, bounded at 100 per page, and scoped to the path project ID.
- Task rows include only non-deleted top-level tasks. Task cards do not change their existing per-task overdue behavior.
- Activity reuses `GET /api/v1/admin/activity-events?projectId=...` and its existing cursor paging.
- No tenant data mutation, schema change, or custom permission is introduced.

## New read contracts

- `GET /api/v1/admin/projects/{projectId}/details`: project/organization metadata, project owner display name, active member count, eligible top-level task aggregates, shared progress fields, and lifecycle timestamps.
- `GET /api/v1/admin/projects/{projectId}/members?page=1&pageSize=50`: `{ items, page, pageSize, totalCount }`, with display name, project role/status, organization membership status, and account status.
- `GET /api/v1/admin/projects/{projectId}/tasks?page=1&pageSize=50`: `{ items, page, pageSize, totalCount }`, with title, status, priority, due date, and effective assignee count.
- Invalid page sizes return `400`; unknown project IDs return `404`. `pageSize` is 1–100 and `page` is positive.

## Acceptance checks

- Web and Flutter Projects rows open project details; organization detail actions navigate to projects scoped to that organization.
- All four detail tabs load read-only data for a Super Admin without tenant membership.
- Project activity is project-scoped; the global Activity page continues to support platform-wide filtering.
- Direct API calls remain protected by the SuperAdmin policy, including cross-tenant project IDs.
- Loading, empty, and error states are visible, and no client-side fallback fabricates data.

## Verification record

- Backend API project build: passed with isolated output, zero warnings/errors. The normal output was locked by the running API process.
- Web production build: passed; existing SignalR annotation and >500 kB chunk warnings remain.
- Scoped Flutter analysis: zero errors; two existing unused private-widget warnings remain in `admin_screen.dart` (`_RecentProjectRow` and `_HorizBar`).
- Automated test suites were not added or run for this request. `git diff --check` passed with line-ending notices only; see the progress tracker for the final verification record.
