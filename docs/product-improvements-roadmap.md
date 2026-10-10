# Safe Product Improvements Roadmap

**Status:** Approved; pre-implementation verification pending
**Date:** 2026-10-08
**Approval record:** [Product Improvements Owner Decision Record](product-improvements-owner-decisions.md)
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

Candidate meaning of “CRUD for every table,” including the system-managed exclusions and observed API gaps, is recorded in [Proposed CRUD Scope](product-improvements-crud-scope.md). It remains pending product-owner acceptance. The concrete open items are comment editing/authority, organization profile editing, notification dismissal, standalone task retrieval, attachment metadata editing, and confirmed Web/Flutter parity.

**Gate:** CRUD scope is conditionally approved. Verify every accepted action in the API, Web, and Flutter before adding any endpoint. No implementation or schema changes before that verification.

### Phase 1 — Close confirmed CRUD interaction gaps

For each accepted user-facing module, implement only missing UI/API interactions by reusing existing routes and lifecycle patterns. Preserve archive versus Trash semantics, 30-day recovery, validation, member constraints, and current role checks. Add missing endpoints only when the inventory proves the use case is absent and the contract is approved.

**Gate:** API contract and authorization matrix reviewed; Web and Flutter flows identified; existing flows have regression checks before edits.

### Phase 2 — Project assignment and ownership clarity

Current model findings and proposed semantics are recorded in [Project Assignment and Ownership](product-improvements-project-assignment.md). The candidate approach uses active `ProjectMember` rows for multiple project participants, keeps `Project.OwnerId` as one accountable owner, and keeps task assignees separate. The project list and client models currently omit owner identity; removal does not reconcile the owner reference or task-assignee rows. Resolve the listed owner/removal decisions before implementation.

**Gate:** Product owner approves assignment semantics, owner transfer/removal rules, open-task reassignment policy, and notification/audit behavior independently of the CRUD and progress/status decisions. Prefer current `ProjectMember` unless requirements demonstrate that it cannot represent the need.

### Phase 3 — Progress and status reporting

The current behavior, formula proposal, status mapping, and owner decisions are in [Project Progress and Status Rules](product-improvements-progress-status.md). Keep project lifecycle status separate from task workflow status, and make any shared project progress calculation server-authoritative. Do not change persisted statuses until the owner accepts the mapping or transition rules.

**Decision required:** Accept or edit the formula, empty-project behavior, audience, overdue date boundary, and status wording. Define “Pending” before considering a persisted value.

**Gate:** Formula, status mapping, empty-project behavior, audience, and archived/deleted task treatment approved independently of CRUD and assignment decisions before API/UI implementation.

### Phase 4 — Fixed-role management improvements

If the need is to assign existing roles, improve the member-management UI and guardrails for current organization/project roles. Preserve owner protections, self-change restrictions, guest restrictions, and server checks. This delivers role administration without creating a custom permissions engine.

First candidate slice spec: `context/feature-specs/project-member-role-management.md` (approved 2026-10-07; Slice 0 and Slice 1 API/Web/Flutter implementation are complete).

Required implementation order:

1. **Slice 0 — guest write-check (completed 2026-10-07):** tests found reachable writes for legacy guest memberships above viewer; a shared authorization guard now denies guest writes, with viewer rejection preserved. Backend tests are green; see the progress tracker.
2. **Slice 1 API - project-member role update (complete):** server endpoint, manager invariant, invitation-reactivation guest-role clamp and audit, and atomic admin audit entry are implemented. A historical-data query is provided; add an idempotent migration only if the read-only audit finds affected rows and the owner approves it.
3. **Slice 1 Web UI (complete):** authorized role editing is implemented against the additive API.
4. **Slice 1 Flutter UI (complete):** authorized role editing is implemented against the additive API. Flutter tests pass; analyzer reports two existing unused-element warnings in `admin_screen.dart`.

Slice 1 followed Slice 0 and green backend tests. The AI task-suggestion guest gate was committed separately using the shared write-level authorization check and its own regression test. See the feature spec and progress tracker for the approved decisions and verification results.

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

## Implementation authorization

The CRUD scope, ownership/reassignment policy, and progress/status rules were approved independently on 2026-10-08. Their exact decisions are recorded in `docs/product-improvements-owner-decisions.md`.

Before changing application behavior, verify the existing API authorization/fixed-role matrix; manager and owner invariants under concurrent transfers/removals; task reassignment and historical attribution; server-side progress calculation and tenant isolation; Web/Flutter loading, errors, refresh and realtime behavior; and backward compatibility. Document findings and a reviewable implementation plan. Until this verification is complete, do not change business rules, database schemas, API contracts, or client behavior for these improvements. No schema migration is approved unless verification proves an accepted requirement cannot be implemented safely with existing relationships.

Role editing is complete. The historical guest data audit remains a pre-deployment operational task. Existing uncommitted Flutter role-editing changes were made under the prior approved Prompt E and are separate from these pending improvement decisions.
