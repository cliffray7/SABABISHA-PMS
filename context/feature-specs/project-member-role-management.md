# Feature Specification: Project Member Role Management

**Status:** Approved  
**Created:** 2026-10-07  
**Owner sign-off:** 2026-10-07  
**Roadmap phase:** Phase 1 / fixed-role management (first candidate slice)  
**Related inventory:** `docs/product-improvements-inventory.md`  
**Related roadmap:** `docs/product-improvements-roadmap.md`

## 1. Goal

Allow authorized organization admins and project managers to change an existing project member's role using the existing fixed project roles, with consistent Web and Flutter controls and server-enforced authorization.

This proposal does not introduce custom roles or permissions, organization role changes, project assignment changes, status changes, or generic CRUD for database tables.

## 2. Current behavior

- `ProjectMember.Role` stores one of `PROJECT_MANAGER`, `TEAM_LEAD`, `CONTRIBUTOR`, or `VIEWER` in current controller validation.
- `POST /api/v1/projects/{id}/members` allows project managers/team leads to add an organization member with a role. Organization guests may only be added as `VIEWER`.
- `DELETE /api/v1/projects/{id}/members/{userId}` allows a project manager/team lead to deactivate another member; self-removal is rejected.
- `GET /api/v1/projects/{id}/members` returns role values to members.
- Neither client currently provides an edit control for an existing project member's role; roles are displayed and removal is available to managers/leads.
- Project/member changes are recorded in workspace activity and publish a project-scoped SignalR change after persistence.

## 3. Decisions

**Approved by owner on 2026-10-07.** These decisions supersede conflicting proposals elsewhere in this draft. Slice 0 is committed and its backend suite passed; the AI authorization follow-up is separately committed and its targeted test passed.

1. **Granting project manager:** Granting `PROJECT_MANAGER` is limited to active organization admins/owners and existing project managers. Team leads cannot promote anyone to project manager.
2. **At least one manager:** A project must always retain at least one active project manager. “Active” means the project membership has `Status == "active"`, the user has an active membership in the project's organization, and the user account is not suspended/deactivated. The API rejects any role change or member removal that would leave zero managers meeting this definition. This is enforced server-side; the UI only mirrors it. Role-change and removal endpoints must use the same predicate.
3. **Historical guest memberships:** Run a read-only audit for organization guests whose project role is above viewer, including inactive project memberships. Clamp roles to `VIEWER` when a guest membership is reactivated. Use a one-time migration to clamp existing affected rows only if the owner reviews the read-only audit results and authorizes that migration; do not flag rows for manual review as the default path.
4. **Audit destination:** Project-member role changes are recorded in the append-only admin audit trail. Workspace activity logging is optional and should be added only if the implementation is trivial and does not weaken atomicity or audit clarity.

## 4. Proposed behavior

### Actor permissions

- Only an active organization admin/owner or an active project manager with an active organization membership may change another member's project role. Organization guests cannot act as role administrators. Team leads cannot change roles through this endpoint.
- Users may not change their own project role through this action, except that a project manager may demote themselves when another active project manager will remain.
- The action may not create a project membership; the target must already be active in the same project and organization.
- Organization guests may only have the `VIEWER` project role. Changing a guest to a write-capable role is denied.
- Only an organization admin/owner or an existing project manager may grant `PROJECT_MANAGER`.
- Every role update and project-member removal must preserve at least one active project manager; the server is authoritative for this invariant.
- Role changes do not change a target member's organization role.
- Project role changes do not alter organization membership or role.

### Role values

The action accepts exactly the existing role values:

- `PROJECT_MANAGER`
- `TEAM_LEAD`
- `CONTRIBUTOR`
- `VIEWER`

No new or custom role values are introduced. No limit is set on the number of managers or team leads, except that at least one active project manager must remain.

### Data and side effects

- Update only the target active `ProjectMember.Role` and its update timestamp if one is added by an approved data design; no timestamp field currently exists on `ProjectMember`.
- Record an admin audit event with actor, target member, project, old role, and new role. Workspace activity may also be written only if trivial and consistent with the existing activity conventions.
- Publish the existing project `members` change notification only after a successful database save.
- Existing clients continue to receive the same member response fields and role strings.
- No schema migration is expected for the basic role update, unless review identifies a required audit field or database constraint.

### Client behavior

- Web and Flutter project-member views show a role selector only to authorized organization admins/owners and project managers. A project manager may also use it on their own row to demote themselves, subject to the server-enforced last-manager rule.
- The control uses the existing role list and current role as its value.
- On success, reload project member data from the API; do not rely on local-only role mutation.
- On failure, show the server error and retain the last confirmed role.
- Disable the control during the request. Preserve current add/remove behavior.

## 5. API contract proposal

The approved implementation contract is documented in [`docs/project-member-role-api-contract.md`](../../docs/project-member-role-api-contract.md).

Proposed additive route:

```http
PATCH /api/v1/projects/{projectId}/members/{userId}
Content-Type: application/json

{ "role": "CONTRIBUTOR" }
```

Expected responses:

- `204 No Content` on success.
- `400 Bad Request` with a stable `code` for an invalid role, disallowed self-role change, guest assigned a non-viewer role, or a role change that would leave zero active project managers.
- `403 Forbidden` with a stable `code` when actor lacks active organization admin/owner or project manager authority, or has guest organization membership; manager grants are separately coded.
- `404 Not Found` when project or target active membership is not available within the actor's authorized scope; do not leak cross-tenant membership existence.

Role-unchanged requests return `204 No Content` without writing an audit event. A project manager may demote themselves if another active manager remains; the same transactional manager guard rejects self-demotion of the last active manager. The route is additive and does not change existing endpoint response shapes.

## 6. Tenant and security requirements

- Resolve project, target membership, and actor's active organization membership in the same organization-scoped authorization path.
- Never authorize by client-supplied organization ID or UI state.
- Reject inactive actor project membership when authorization relies on project-manager role, inactive actor organization membership, archived/deleted projects, cross-tenant target IDs, guests as actors, and project roles other than project manager unless the actor is authorized as an organization admin/owner.
- Apply guest target restriction based on current active organization role at update time.
- Audit organization guests whose project role is above `VIEWER`. Clamp roles to `VIEWER` when reactivating a guest's project membership and record an audit event when an elevated role is changed. A historical-data migration is conditional on read-only audit results and owner approval.
- Enforce the at-least-one-manager invariant transactionally for role update and member removal to avoid concurrent changes leaving the project without a manager.
- Do not place mutable project roles in long-lived authorization claims; current server-side membership lookup remains authoritative.
- Add regression coverage for allowed and denied role transitions, manager invariant under concurrent changes, and organization guests with historical/reactivated project-member rows.

## 7. Compatibility and release

- Add an endpoint without changing existing response shapes or current routes.
- Deploy the API before clients that call the new endpoint; old clients continue to work unchanged.
- Existing persisted role values remain valid; run the read-only guest-role audit before rollout. A one-time clamp migration is conditional on affected rows and owner review; reactivation always clamps in code.
- No feature flag is required for the additive endpoint, but client controls should not be released before the API is deployed.
- Rollback: clients can be rolled back independently; if the API must be rolled back after clients ship, hide/disable the role-edit control in the client release or restore the additive endpoint. No data rollback is needed for role values already selected from the existing set, but reverting member roles requires an explicit audited correction.

## 8. Implementation order and verification plan

Implementation order is mandatory:

1. **Slice 0 — guest write-check:** reject organization guest project writes through shared authorization; handle invitation reactivation and the AI suggestion authorization follow-up in separate commits.
2. **Slice 1 API — project-member role update:** implement endpoint, manager invariant, guest role constraints, invitation reactivation clamp, and atomic admin audit.
3. **Slice 1 Web UI:** add role controls after the API is deployed.
4. **Slice 1 Flutter UI:** add role controls after the API is deployed.

Keep these changes in reviewable commits. Slice 1 is dependent on Slice 0 completion and green backend tests.

Before enabling Slice 1, audit affected existing memberships. The approved remediation is to clamp affected guest memberships to `VIEWER` in invitation reactivation code and with a one-time migration only if the read-only data audit finds affected rows. Do not add or run that migration before the owner reviews the read-only audit results. The AI suggestion endpoint now uses the shared write-level project access check; its test and fix are in a separate commit.

- Slice 0 API tests: for guest memberships at viewer and any legacy/reactivated role above viewer, verify every reachable task/collaboration write is denied; run relevant existing backend tests.
- Slice 1 API tests: organization admin/owner and project manager permitted for authorized changes; team leads and other unauthorized roles denied; manager self-demotion permitted only when another active manager remains; other self-changes denied; invalid/unknown role rejected; target guest remains viewer-only; no-op returns success without audit; zero-manager role change and removal rejected; inactive and cross-tenant memberships denied; archived/deleted project denied.
- Verify the admin audit event has actor, target member, project, old role, and new role, and is atomic with the membership change. Workspace activity is optional. Verify realtime `members` event occurs only after save.
- Web and Flutter checks: role selector visibility, loading/disabled state, success reload, API error retention, and no change to add/remove/invitation behavior.
- Run API tests/build, Web typecheck/build, Flutter analyze/tests/build, and `git diff --check`; report any inconclusive tool invocation accurately.
- Review SQL Server schema/index constraints; document explicitly if no migration is needed.

## 9. Approved rollout remediation

Clamp guest project roles to `VIEWER` when an inactive membership is reactivated, and record an audit event when this changes an elevated role. Run the provided read-only SQL audit against a backup or replica. Add an idempotent one-time migration only if that audit finds affected rows, after owner review of the results. No migration is authorized by this decision.
