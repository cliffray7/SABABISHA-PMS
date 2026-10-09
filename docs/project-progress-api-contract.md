# Project Progress API Contract

**Status:** Approved for Slice 4 backend implementation
**Scope:** Additive authenticated read endpoint and aligned platform PDF progress. Web and Flutter consumption remains a later authorized slice.

## Endpoint

`GET /api/v1/projects/{projectId}/progress`

Returns project-wide aggregate data to a caller who can read the active project. The response contains no task-level information. It uses the existing project-read authorization predicate: project membership and organization membership must both be active, and the project must not be archived or in Trash. Organization guests retain the existing project read access. Inactive memberships, cross-tenant IDs, archived projects, trashed projects, and unavailable projects receive the existing forbidden response. An accessible project with no tasks returns `200` with `hasTasks: false`.

## Success response

```json
{
  "projectId": "00000000-0000-0000-0000-000000000001",
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

| Field | Type | Meaning |
|---|---|---|
| `projectId` | GUID | Requested project identifier. |
| `projectStatus` | string | Persisted lifecycle status, returned unchanged. Progress does not transition project status. |
| `hasTasks` | boolean | Whether at least one eligible task exists. |
| `totalEligibleTasks` | integer | Count of non-deleted top-level tasks, regardless of assignee or status. |
| `completedTasks` | integer | Eligible tasks whose status is `DONE`. |
| `progressPercent` | integer or null | Rounded completion percentage; null only for an empty eligible task set. |
| `outstandingTaskCount` | integer | Eligible tasks whose status is not `DONE`. |
| `overdueTaskCount` | integer | Outstanding eligible tasks with a non-null due calendar date before the organization's current local date. |
| `timezoneIdUsed` | string | Resolved timezone identifier used to compute the local date. Invalid/missing configuration is represented as `UTC`, never by its raw value. |

## Calculation rules

- Eligible tasks are all non-deleted top-level tasks belonging to the project. Subtasks and soft-deleted tasks do not contribute.
- `DONE` is the only completed task status. Assignees do not affect project progress.
- `progressPercent = RoundAwayFromZero(completedTasks * 100 / totalEligibleTasks)`. The ratio is non-negative; exact `.5` values round up to the next integer.
- `outstandingTaskCount = totalEligibleTasks - completedTasks`.
- `overdueTaskCount` counts only outstanding tasks with a due date. The stored due-date calendar date is compared with the organization's local calendar date. Due today, future due dates, missing due dates, and `DONE` tasks are not overdue.
- The backend captures the current UTC time once per calculation and converts it using `Organization.Timezone`; it never uses the server's local timezone. A missing or invalid organization timezone falls back to UTC and produces an internal diagnostic warning without exposing the invalid value to the caller.
- Empty result: `hasTasks: false`, `totalEligibleTasks: 0`, `completedTasks: 0`, `progressPercent: null`, and both outstanding/overdue counts `0`.
- Non-empty 0% result: `hasTasks: true`, positive `totalEligibleTasks`, `completedTasks: 0`, `progressPercent: 0`.
- A `COMPLETED` project remains `COMPLETED` regardless of task progress. For example, 8 completed out of 10 eligible tasks returns 80%; progress reaching 100% or later decreasing does not change lifecycle status.

## Status values

The response returns the existing stored `projectStatus` without changing it. Project values are `PLANNING`, `ACTIVE`, `ON_HOLD`, and `COMPLETED`; task values are `TO DO`, `IN PROGRESS`, `REVIEW`, and `DONE`. Approved user-facing labels are defined in [Project Progress and Status Rules](product-improvements-progress-status.md) and remain a client-integration responsibility. This endpoint does not add a `PENDING` state or rename persisted values.

## Platform PDF

The platform PDF retains archived projects as historical records and labels archived project rows `Historical (Archived)`. Its per-project progress uses the same non-deleted top-level-task predicate, `DONE`-only completion rule, and rounding function as this endpoint. An empty project displays `No tasks`, not `0%`. Raw CSV/XLSX project/task rows and the existing dashboard metrics procedure retain their existing scope and response semantics.

## Compatibility and security

- This is an additive route. Existing `/api/v1/dashboard/metrics`, stored procedure behavior, project/task DTOs, database schema, and stored statuses remain unchanged.
- Task details are never included. Aggregate data is returned to members who pass the existing project-read predicate, including roles that cannot view every task detail.
- The endpoint follows the existing shared project-read policy. Suspended-account access remains a separately tracked security follow-up and is not changed here.
- No migration, client edit, per-task overdue flag, or Web/Flutter status-label change is part of Slice 4.

## Verification requirements

Tests cover empty and non-empty 0% projects, mixed statuses, top-level/subtask/deleted task eligibility, exact-half rounding, completed lifecycle independence, yesterday/today/future/null due dates, organization timezone boundaries, invalid and missing timezone fallback with a warning, guest and inactive-membership authorization, inaccessible/cross-tenant and archived/trashed project behavior, and absence of task details. PDF tests verify shared progress semantics, historical archived labels, and `No tasks` for empty projects. The full backend suite and `git diff --check` are required at implementation review.
