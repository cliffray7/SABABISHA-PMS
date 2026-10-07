# Safe Product Improvements Roadmap

**Status:** Planning proposal  
**Date:** 2026-10-07  
**Scope:** Improve CRUD coverage, role management, project assignment, and progress visibility without disrupting existing TaskFlow behavior.

## Purpose

This roadmap turns the user feedback into small, reversible steps. It is a planning document, not authorization to change the database or redefine permissions. Existing APIs and client behavior remain the baseline until each phase has a reviewed feature specification.

## Current implementation baseline

- Organizations support creation, listing, member/invitation management, role changes among fixed roles, member removal, and invitation revocation. Organization deletion/editing is not assumed to be required.
- Projects support create, list, detail, update, archive, restore, Trash/restore, and member add/remove. Project membership has fixed roles.
- Tasks support create, list, edit, assignment to multiple project members, subtasks, soft delete, and restore through Trash. Task status is `TO DO`, `IN PROGRESS`, `REVIEW`, or `DONE`.
- Project status is `PLANNING`, `ACTIVE`, `ON_HOLD`, or `COMPLETED`. Archive is separate from deletion.
- Existing access checks are server-side and depend on active organization/project membership and fixed role rules. Tenant boundaries, audit/activity events, and SignalR invalidation are part of the current behavior.
- The Web and Flutter clients both exist. Client parity must be checked per module; one client must not be considered complete based on the other.

This is a targeted baseline from the current API/domain review, not a guarantee that every screen exposes each endpoint. Phase 0 performs the full screen-to-endpoint inventory.

## Safety principles

1. Keep the current role and status behavior as the compatibility baseline until a separately reviewed change is approved.
2. Enforce every permission and tenant boundary in the API. Frontend visibility is presentation only.
3. Prefer additive API fields/endpoints and additive database migrations. Preserve existing role/status values and map them explicitly if new values are approved.
4. Keep archive, recoverable Trash, and permanent purge as distinct lifecycle actions. Do not turn audit/activity records into ordinary editable CRUD rows.
5. Record high-impact role, membership, assignment, and lifecycle changes in the appropriate append-only audit/activity trail.
6. Publish existing workspace change notifications after successful persistence; clients reload authoritative REST data.
7. Do not claim CRUD parity until both API behavior and Web/Flutter interaction are mapped and verified.
8. Release each meaningful slice behind a reviewable boundary, with migration and rollback notes before deployment.

## Phases and gates

### Phase 0 — Baseline inventory and acceptance criteria

Initial code inventory: [Product Improvements Phase 0 Inventory](product-improvements-inventory.md). Continue by confirming each action against the complete Web and Flutter flows, API authorization paths, and existing regression-test coverage. Include organizations, members/invitations, projects/members, tasks/subtasks/assignees, comments, attachments, notifications, and account/profile settings. Mark append-only/system-managed tables as lifecycle-managed rather than promising direct CRUD.

**Gate:** Product owner accepts the module scope and confirms what “CRUD for every table” means. No implementation or schema changes in this phase.

### Phase 1 — Close confirmed CRUD interaction gaps

For each accepted user-facing module, implement only missing UI/API interactions by reusing existing routes and lifecycle patterns. Preserve archive versus Trash semantics, 30-day recovery, validation, member constraints, and current role checks. Add missing endpoints only when the inventory proves the use case is absent and the contract is approved.

**Gate:** API contract and authorization matrix reviewed; Web and Flutter flows identified; existing flows have regression checks before edits.

### Phase 2 — Project assignment and ownership clarity

First surface existing project owner, project members/roles, and task assignees consistently. The current project has an `OwnerId`, project membership, and multiple task assignees. Decide whether “assign project to users” means project membership, a distinct assignment list, or both before adding a new relationship. Define behavior for removing a project member who still owns or is assigned tasks.

**Gate:** Assignment semantics and reassignment/notification behavior approved. Prefer current `ProjectMember` unless requirements demonstrate that it cannot represent the need.

### Phase 3 — Progress and status reporting

Start with a read-only project tracking view using existing project status, task statuses, due dates, subtasks, assignees, and current dashboard metrics where accurate. Propose progress as completed top-level tasks divided by all active top-level tasks; show “No tasks yet” when denominator is zero. Show outstanding and overdue counts separately. Keep this calculation server-authoritative and consistent across clients.

**Decision required:** Confirm whether progress is derived from tasks, weighted by subtasks, or manually entered. Also confirm whether the requested statuses map to existing statuses (for example Pending/To Do and Under Testing/Review) or require new persisted values.

**Gate:** Formula, status mapping, empty-project behavior, and archived/deleted task treatment approved before API/UI implementation.

### Phase 4 — Fixed-role management improvements

If the need is to assign existing roles, improve the member-management UI and guardrails for current organization/project roles. Preserve owner protections, self-change restrictions, guest restrictions, and server checks. This delivers role administration without creating a custom permissions engine.

First candidate slice spec: `context/feature-specs/project-member-role-management.md` (approved 2026-10-07; Slice 0 is committed and its tests passed).

Required implementation order:

1. **Slice 0 — guest write-check (completed 2026-10-07):** tests found reachable writes for legacy guest memberships above viewer; a shared authorization guard now denies guest writes, with viewer rejection preserved. Backend tests are green; see the progress tracker.
2. **Slice 1 API — project-member role update:** add the server endpoint, manager invariant, invitation-reactivation guest-role clamp and audit, and atomic admin audit entry. Provide the historical-data query; add an idempotent migration only if the read-only audit finds affected rows and the owner approves it.
3. **Slice 1 Web UI:** expose role editing after the API is deployed.
4. **Slice 1 Flutter UI:** expose role editing after the API is deployed.

Slice 1 must wait for Slice 0 completion and green backend tests. The AI task-suggestion guest gate is a small separate commit using the shared write-level authorization check and its own regression test. See the feature spec for the approved decisions and verification requirements.

**Gate:** Confirm fixed-role assignment meets the need. If so, stop here for role scope.

### Phase 5 — Optional custom roles and permissions (separate initiative)

Custom roles change the authorization model and may affect every protected API route, existing data, realtime membership checks, and both clients. Before implementation, produce an ADR and a dedicated spec defining permission vocabulary, role scope (organization/project/platform), default-role migration, owner/superadmin protections, permission evaluation strategy, cache/token freshness, audit events, and rollback. Avoid storing mutable permissions only in JWT claims; define revocation/freshness behavior.

**Gate:** Security review and explicit approval of the permission matrix, migration/backfill, compatibility behavior, and test plan. Do not bundle this with CRUD UI work.

## Verification and release strategy

Before each implementation slice, record current behavior and run the relevant existing checks to establish a baseline. Add targeted tests for the changed contract and authorization rules, then run API tests/build, Web typecheck/build, and Flutter analyze/tests/build as applicable. The repository’s current notes indicate some Flutter commands can stall; report that as inconclusive instead of success.

Minimum regression coverage for permission- or membership-affecting work:

- Same-tenant allowed access and cross-tenant denial.
- Owner/admin/manager/contributor/viewer/guest expectations for the changed action.
- Inactive organization/project membership and archived/deleted project behavior.
- Existing project/task create, update, assignment, archive/Trash, restore, activity, and realtime refresh flows touched by the slice.
- Web and Flutter clients parse additive API responses and handle denied/error responses without optimistic fake success.

Database work requires an additive migration, existing-row backfill plan, pre/post migration checks, supported rollback or forward-fix plan, and verification against SQL Server. Deployment order must keep old clients compatible with additive API changes; destructive/required contract changes need coordinated rollout and an explicit maintenance/release plan.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| “CRUD every table” accidentally exposes destructive operations on audit/system records | Define user-facing modules and lifecycle-managed records in Phase 0. |
| Custom permissions unintentionally widen tenant access | API policy matrix, tenant-isolation tests, security review, staged migration. |
| New statuses break existing clients, reports, or filters | Use explicit mapping and compatibility review before persisting new enum/string values. |
| Project member removal leaves assignments inconsistent | Decide reassignment/orphan policy and validate transactionally. |
| Progress differs between Web, mobile, and dashboards | One documented server-side formula and shared response contract. |
| Schema/UI changes disrupt current users | Additive migrations, backward-compatible API, regression checks, staged release. |
| Existing documentation describes stale stack/scope | Treat active `context/` docs and actual code as baseline; reconcile legacy docs only in scoped doc updates. |

## Decisions to record before implementation

1. Which modules are included in CRUD completion, and which entities are system-managed?
2. Are fixed roles sufficient, or are custom roles and permissions required?
3. Does project assignment mean membership, a separate assignment relationship, or both?
4. What is the progress formula and how are subtasks, deleted tasks, and empty projects handled?
5. Should Pending and Under Testing be display aliases or persisted statuses?
6. Which clients are release targets for each phase (Web, Flutter, or both)?

Until these are resolved, implementation can safely begin only with Phase 0 inventory and documentation/specification work.
