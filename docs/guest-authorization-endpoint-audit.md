# Guest Authorization Audit: Mutating REST Endpoints

**Date:** 2026-10-07  
**Scope:** Read-only review of POST, PUT, PATCH, and DELETE actions under `src/Pms.Api/Controllers/Rest/V1/`, following the Slice 0 shared authorization change.  
**Shared project/task write check:** `WorkspaceAuthorization.CanAccessProjectAsync` rejects writes when either the project role is `VIEWER` or the active organization role is `GUEST`; read checks retain guest membership access.  
**Important:** This audit describes code paths; it is not a live production database review.

## Project and task workspace routes

| Route/action | Authorization path | Calls shared `CanAccessProjectAsync`? | Finding |
|---|---|---:|---|
| `POST /api/v1/projects` create | Requires active organization membership and rejects `GUEST`; creates project manager membership for actor. | No | Guest denied by route-specific organization-role check. |
| `PATCH /api/v1/projects/{id}` update project/status | `Manager`: active project membership, active organization membership, non-guest organization role, project manager/team lead. | No | Guest denied by route-specific manager check. |
| `DELETE /api/v1/projects/{id}` archive | Same `Manager` check. | No | Guest denied. |
| `POST /api/v1/projects/{id}/restore` | Archived restore uses `Manager`; Trash restore uses `CanManageDeletedProject`, which requires active manager/lead and non-guest organization role. | No | Guest denied by route-specific manager checks. |
| `DELETE /api/v1/projects/{id}/trash` | `Manager` check. | No | Guest denied. |
| `POST /api/v1/projects/{id}/members` add/reactivate | `Manager`; validates organization membership and allows guests only as `VIEWER`. Reactivation overwrites the project role with the requested role. | No | Guest actor denied. Target guest is constrained to viewer on this endpoint. |
| `DELETE /api/v1/projects/{id}/members/{userId}` remove | `Manager`; self-removal rejected. | No | Guest actor denied. |
| `POST /api/v1/projects/{projectId}/tasks` create task | `TasksController.Access(..., write: true)`. | Yes | Guest denied; viewer rejection retained. |
| `POST /api/v1/tasks/{id}/subtasks` create subtask | `Access(..., write: true)`. | Yes | Guest denied. |
| `PATCH /api/v1/tasks/{id}/subtasks/{subtaskId}` complete/reopen subtask | `Access(..., write: true)`. | Yes | Guest denied. |
| `PATCH /api/v1/tasks/{id}` update task/assignees | `Access(..., write: true)`. | Yes | Guest denied for task fields and assignee changes. |
| `DELETE /api/v1/tasks/{id}` move task to Trash | Custom query requires active PM/lead plus active non-guest organization membership. | No | Guest was already denied before Slice 0. |
| `POST /api/v1/tasks/{id}/restore` restore task | Custom query requires active PM/lead plus active non-guest organization membership. | No | Guest denied. |

## Collaboration and notifications

| Route/action | Authorization path | Calls shared `CanAccessProjectAsync`? | Finding |
|---|---|---:|---|
| `POST /api/v1/tasks/{id}/comments` create comment/reply | `TaskAccess(..., write: true)`; validates mentioned users are active project members. | Yes | Guest denied. Pre-fix vulnerability confirmed by endpoint test. |
| `DELETE /api/v1/tasks/{taskId}/comments/{commentId}` delete comment | `TaskAccess(..., write: true)` then author or manager/lead check. | Yes | Guest denied before actor check. |
| `POST /api/v1/tasks/{taskId}/comments/{commentId}/restore` restore comment | `TaskAccess(..., write: true)` then author or manager/lead check. | Yes | Guest denied before actor check. |
| `POST /api/v1/tasks/{id}/attachments` upload | `TaskAccess(..., write: true)` then storage configuration and upload. | Yes | Guest denied before storage. Pre-fix test showed request passed authorization and reached storage configuration. |
| `DELETE /api/v1/attachments/{id}` move attachment to Trash | `TaskAccess(..., write: true)` then uploader or manager/lead check. | Yes | Guest denied before actor check. |
| `POST /api/v1/attachments/{id}/restore` restore attachment | `TaskAccess(..., write: true)` then uploader or manager/lead check. | Yes | Guest denied before actor check. |
| `PATCH /api/v1/notifications/read-all` mark own notices read | Filters by `CurrentUser.Id`; no project scope. | No | Recipient-scoped personal action; not a project write. |
| `PATCH /api/v1/notifications/{id}/read` mark own notice read | Filters by notification ID and `CurrentUser.Id`. | No | Recipient-scoped personal action; not a project write. |

## Other REST mutations

| Route/action | Authorization path | Calls shared `CanAccessProjectAsync`? | Finding |
|---|---|---:|---|
| `POST /api/v1/organizations` create organization | Authenticated controller; creates organization with caller as owner. | No | Not project-scoped. |
| `PATCH /api/v1/organizations/{id}/members/{userId}` change organization role | `Admin`: active organization OWNER/ADMIN; owner and self role changes rejected. | No | Guest denied. |
| `DELETE /api/v1/organizations/{id}/members/{userId}` remove organization member | `Admin`; self/owner removal rejected; deactivates project memberships and revokes refresh tokens. | No | Guest denied. |
| `POST /api/v1/organizations/{id}/invitations` invite | `Admin`; role restricted to ADMIN/MEMBER/GUEST. | No | Guest denied. |
| `DELETE /api/v1/organizations/{id}/invitations/{invitationId}` revoke invite | `Admin`. | No | Guest denied. |
| `POST /api/v1/organizations/invitations/accept` accept invitation | Authenticated actor must match invited email; membership changes are transactional. Reactivates prior inactive project membership rows without changing their stored project role. | No | A guest can carry a legacy elevated project role after reactivation. Shared task/collaboration writes deny it; Slice 1 must clamp to viewer during reactivation. |
| `POST /api/v1/account/auth/forgot-password` | Public, rate-limited; creates reset token for a matching account. | No | Authentication lifecycle, not project-scoped. |
| `POST /api/v1/account/auth/reset-password` | Public, rate-limited; validates one-time token and rotates credentials transactionally. | No | Authentication lifecycle. |
| `PATCH /api/v1/account/account` update own profile | `[Authorize]`; selects current user ID from claims. | No | Self-scoped. |
| `POST /api/v1/account/account/avatar` upload own avatar | `[Authorize]`; selects current user ID from claims; validates file and storage. | No | Self-scoped. |
| `POST /api/v1/account/auth/logout` revoke own refresh token | `[Authorize]`; scopes update to current user ID. | No | Self-scoped. |
| `POST /api/v1/auth/register`, `/login`, `/verify-otp`, `/refresh` | Authentication, one-time-code, rate-limit, and refresh-token lifecycle checks in `AuthController`. | No | Authentication lifecycle, not project-scoped. |
| `POST /api/v1/admin/users` create platform user | `[Authorize(Policy = "SuperAdmin")]`; admin audit event is written atomically. | No | Platform-only. |
| `DELETE /api/v1/admin/users/{id}` suspend/permanently delete platform user | SuperAdmin policy; audit event; linked workspace data prevents permanent deletion. | No | Platform-only. |

## Non-mutating POST with a related guest check

`POST /api/v1/ai/tasks/suggest` does not persist a task. It reads project details and task titles and sends context to the configured AI service. Its former local authorization check did not reject organization role `GUEST`, so a legacy guest with a project role above viewer could trigger AI work. Decision: gate this authoring aid through `WorkspaceAuthorization.CanAccessProjectAsync(..., write: true, ...)`, with endpoint regression coverage, in a separate commit.

## Read-only historical data audit query

The following SQL Server query is provided for an authorized backup or read replica only. It is not to be run against production by the implementation agent. It returns two summary counts and a record-level result for review. The affected population is active organization guests with an active project membership above `VIEWER`; authored task/comment records are scoped to those memberships' project and organization.

```sql
WITH affected_guest_memberships AS (
    SELECT
        om.organization_id,
        pm.project_id,
        om.user_id
    FROM organization_members AS om
    INNER JOIN project_members AS pm ON pm.user_id = om.user_id
    INNER JOIN projects AS p ON p.id = pm.project_id AND p.organization_id = om.organization_id
    WHERE om.status = N'active'
      AND om.role = N'GUEST'
      AND pm.status = N'active'
      AND pm.role IN (N'PROJECT_MANAGER', N'TEAM_LEAD', N'CONTRIBUTOR')
),
authored_records AS (
    SELECT agm.organization_id, agm.project_id, t.created_by AS user_id,
           N'task' AS record_type, t.id AS record_id, t.title AS record_label
    FROM affected_guest_memberships AS agm
    INNER JOIN tasks AS t ON t.project_id = agm.project_id AND t.created_by = agm.user_id
    UNION ALL
    SELECT agm.organization_id, agm.project_id, c.user_id,
           N'comment' AS record_type, c.id AS record_id, LEFT(c.content, 300) AS record_label
    FROM affected_guest_memberships AS agm
    INNER JOIN tasks AS t ON t.project_id = agm.project_id
    INNER JOIN comments AS c ON c.task_id = t.id AND c.user_id = agm.user_id
)
SELECT
    N'guest_memberships_above_viewer' AS metric,
    COUNT_BIG(*) AS record_count
FROM affected_guest_memberships
UNION ALL
SELECT N'guest_authored_tasks_and_comments', COUNT_BIG(*)
FROM authored_records;

WITH affected_guest_memberships AS (
    SELECT om.organization_id, pm.project_id, om.user_id
    FROM organization_members AS om
    INNER JOIN project_members AS pm ON pm.user_id = om.user_id
    INNER JOIN projects AS p ON p.id = pm.project_id AND p.organization_id = om.organization_id
    WHERE om.status = N'active' AND om.role = N'GUEST'
      AND pm.status = N'active'
      AND pm.role IN (N'PROJECT_MANAGER', N'TEAM_LEAD', N'CONTRIBUTOR')
)
SELECT agm.organization_id, agm.project_id, agm.user_id,
       N'task' AS record_type, t.id AS record_id, t.title AS record_label
FROM affected_guest_memberships AS agm
INNER JOIN tasks AS t ON t.project_id = agm.project_id AND t.created_by = agm.user_id
UNION ALL
SELECT agm.organization_id, agm.project_id, agm.user_id,
       N'comment', c.id, LEFT(c.content, 300)
FROM affected_guest_memberships AS agm
INNER JOIN tasks AS t ON t.project_id = agm.project_id
INNER JOIN comments AS c ON c.task_id = t.id AND c.user_id = agm.user_id
ORDER BY organization_id, project_id, user_id, record_type, record_id;
```

## Labels, tags, and other project mutations

No labels/tags mutation routes were found in the V1 controllers. The Trash API is read-only; restore actions are on project/task/comment/attachment routes above.

## Operational limitation

No production or local SQL Server data audit was performed. Do not infer whether deployed organizations have affected memberships or whether any guest performed these actions from code/tests. Such checks require an authorized database query and deployment-owner review.
