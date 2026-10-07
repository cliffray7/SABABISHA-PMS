# Project Member Role Update API Contract

**Status:** Approved for Slice 1 API implementation (2026-10-07)
**Specification:** [Project member role management](../context/feature-specs/project-member-role-management.md)

## Route

```http
PATCH /api/v1/projects/{projectId}/members/{userId}
Content-Type: application/json

{ "role": "CONTRIBUTOR" }
```

The request accepts exactly `PROJECT_MANAGER`, `TEAM_LEAD`, `CONTRIBUTOR`, and `VIEWER`. The operation updates an existing active project membership; it never creates a membership. A role-unchanged request is a successful no-op.

## Authorization and tenant scope

- The project must be active (not archived or in Trash).
- The actor must have an active organization membership in the project's organization, and the actor account must be active.
- Active organization owners/admins and existing active project managers can change project-member roles. Team leads and all other actors are denied.
- Only organization owners/admins and existing project managers can grant `PROJECT_MANAGER`.
- The target must have an active project membership and active organization membership in the same project organization. Guests may only have `VIEWER`.
- Self-role changes are rejected. Cross-tenant and absent targets return `404` without exposing membership existence.

## Responses

- `204 No Content`: role changed or already matched.
- `400 Bad Request`: unknown role, self-change, guest assigned above viewer, or the resulting project would have no active manager.
- `403 Forbidden`: actor lacks the required organization-admin or project-manager permission, has a guest organization role, or has an inactive account/membership.
- `404 Not Found`: project or target membership is not available within the authorized tenant scope.

## Manager invariant

After every role change and project-member removal, at least one project manager must still meet all these conditions:

- Project membership status is `active` and role is `PROJECT_MANAGER`.
- Organization membership in the project's organization is `active`.
- User account status is `active` (suspended/deactivated users do not count).

Both endpoints evaluate the resulting count inside a SQL Server serializable transaction. The API enforces the invariant; clients only mirror the server response.

## Audit and atomicity

An actual role change adds one `admin_audit_events` entry in the same transaction as the role update. No-op requests do not create an audit row. The event uses:

- `actor_id`: acting user.
- `target_type` / `target_id`: `user` / affected member user ID.
- `action`: `project.member_role_changed`.
- `reason`: project ID plus old and new role values.
- `outcome`: `succeeded`; `correlation_id` follows the existing request correlation convention.

If either database write fails, both the role change and audit event roll back. The existing project `members` realtime notification is sent only after transaction commit.

When invitation acceptance reactivates an existing project membership for a guest, it sets the role to `VIEWER`. If this changes an elevated role, it writes `project.member_guest_role_clamped` to the same append-only audit table in the invitation transaction. No historical-data migration is part of this change. A read-only SQL audit is supplied in [the guest authorization endpoint audit](guest-authorization-endpoint-audit.md); the owner will review its results before authorizing any idempotent cleanup migration.

## Compatibility

This is an additive route. Existing endpoints, payloads, and response shapes remain unchanged. Web and Flutter changes are separate follow-on slices.
