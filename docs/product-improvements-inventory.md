# Product Improvements: Phase 0 Inventory

**Date:** 2026-10-08
**Status:** Initial inventory reconciled with delivered role editing; three product decisions approved, verification pending
**Roadmap:** [Safe Product Improvements Roadmap](product-improvements-roadmap.md)
**Approval record:** [Product Improvements Owner Decision Record](product-improvements-owner-decisions.md)
**CRUD proposal:** [Proposed CRUD Scope](product-improvements-crud-scope.md)
**Assignment proposal:** [Project Assignment and Ownership](product-improvements-project-assignment.md)
**Progress proposal:** [Project Progress and Status Rules](product-improvements-progress-status.md)

This inventory records observable routes and screen ownership. “Present” means a route or UI surface exists in the inspected code; it does not by itself certify all role combinations, usability, or completeness. “Review” marks a follow-up verification item, not an approved feature request.

## Module matrix

| Module / entity | API capability observed | Web surface observed | Flutter surface observed | Access / lifecycle notes | Phase 0 review item |
|---|---|---|---|---|---|
| Organizations | List/create; member list, fixed-role update, remove; invitations list/create/cancel/accept. No general organization detail/update/delete route observed. | Workspace organization selection and member management are in `main.tsx`; organization creation/invitation flows exist. | `workspace_shell.dart`, `members_screen.dart`; `ApiClient` exposes create, member, invitation operations. | Member changes are organization-admin guarded; owner cannot be removed/demoted; removal deactivates project memberships and revokes refresh tokens. | Confirm whether organization edit/delete is a real requirement; account for dependent projects, audit, and tenant ownership before considering it. |
| Organization members / invitations | Read, invite, accept, cancel, role change, remove. | `MembersPage` exposes role change, removal, invitation and cancellation. | `MembersScreen` exposes role change, removal, invitation and cancellation; invite accept is handled by the auth/invitation flow. | Fixed roles `OWNER`, `ADMIN`, `MEMBER`, `GUEST`; owner/self protections and guest constraints apply. | Confirm role selector options match server roles and verify denied/error/refresh states. |
| Projects | List/create/detail/update/archive/restore; move to Trash; list/add/remove members. | Project selection/settings, edit, archive, Trash, member-management flows in `main.tsx`. | Workspace/project screens and `ApiClient` support create/update/archive, members; trash/restore wrappers exist. | Archive is indefinite and separate from Trash; project manager/team lead checks; project belongs to tenant. | Map project creation/edit/archive/trash/restore controls to screens and confirm owner/member presentation parity. |
| Project members / ownership | `Project.OwnerId` stores the creator; active `ProjectMember` links with fixed roles; add/remove and role-update routes. Project list omits owner identity. | Members page supports add/remove and editing existing project roles; project owner is not surfaced as a distinct accountable owner. | Members screen supports add/remove and editing existing project roles; project owner is not surfaced as a distinct accountable owner. | Roles: project manager, team lead, contributor, viewer; additions require active organization member; guest can only be viewer. Server add/remove checks require manager/lead; role update requires organization admin/owner or project manager. | Role editing is complete across API, Web, and Flutter. Multiple participants can be assigned through project membership; decide owner transfer/removal and task-assignee behavior. See `docs/product-improvements-project-assignment.md`. |
| Tasks | List/create/update/soft-delete/restore; assignee add/remove through update; subtasks create/list/update; task activity. No standalone item GET route observed. | Board, task detail/edit/create, assignees, Trash and restore; workspace refresh after task mutations. | `BoardScreen`, `TaskDetailScreen`, `EditTaskScreen`; task detail exposes edit and manager/lead-only Trash; restore is in Trash screen. | Project membership required; shared task write authorization rejects both VIEWER project memberships and GUEST organization memberships; deletion restricted to project manager/team lead; assignees must be project members. | Slice 0 guest write-check is complete with shared-path regression coverage. |
| Task assignees | Multiple assignees on task create/update; assignment notifications emitted. | Task create/edit controls and assignee display. | Task create/edit controls and assignee display. | Assignees must be active project members; assignment changes are activity-recorded and notify additions. | Verify reassignment/removal behavior and notifications after member removal; preserve existing contracts. |
| Comments / mentions | Comment list/create, soft delete, restore; mention entities exist. No comment update route observed. | Task detail supports comment create/read/delete affordances; deleted comments can be restored through Trash. | Task detail supports comment create/read/delete affordances; deleted comments can be restored through Trash. | Shared write authorization excludes VIEWER and organization GUEST. Delete/restore additionally require author or manager/lead. | Confirm whether comment editing is intentionally unsupported. Guest write-check is complete; retain regression coverage. |
| Attachments | List/upload/download proxy, soft delete, restore. | Task detail upload/download/Trash affordances; Trash restore. | Task detail upload/download/Trash affordances; Trash restore. | Shared task write authorization rejects viewer project roles and guest organization roles; delete/restore additionally require uploader or manager/lead. Max size and storage failures are API-enforced. | Verify uploader/manager delete behavior, restore/removal refresh, and download errors on both clients. |
| Notifications | List; mark one/read all. | Notification center/hook. | `NotificationsScreen`; client wrappers for read actions. | Recipient-scoped. | No generic CRUD expected; verify read/unread interactions and realtime refresh. |
| Account/profile | Read/update profile; avatar upload; logout; password-reset request/complete. | Settings page edits profile/avatar and password reset request. | `SettingsScreen`; account update/avatar/logout APIs. | Authenticated self-service; avatar MIME/size validation. | Verify field parity and error handling; reset flow includes unauthenticated token completion. |
| Activity / admin audit | Workspace activity is paged/read-only; admin audit is paged/read-only. | Workspace activity and SuperAdmin activity/audit screens. | Workspace activity and SuperAdmin Activity/Audit screens. | Activity and audit are records, not generic CRUD entities; admin audit is append-only. | Confirm filters/paging parity; preserve append-only policy. |
| Platform administration | SuperAdmin users create/suspend/delete and read users/orgs/projects/analytics/reports/audit/activity/health. No custom role/permission endpoints observed. | Admin dashboard and platform management components. | `admin_screen.dart` platform console. | SuperAdmin policy from configured admin IDs; high-impact operations audited. | Separate platform user lifecycle from tenant role management; verify destructive-user semantics and audit coverage. |
| System/auth entities | OTP/login/refresh/reset/invitation token operations. | Auth screens and account recovery. | Auth/launcher screens. | Tokens/codes are security-sensitive and lifecycle-managed, not editable CRUD. | Exclude secrets/tokens from generic CRUD scope. |

## Initial observations requiring review

1. **Client parity needs screen-level confirmation.** API wrappers exist for more lifecycle actions than a filename inventory proves are visible in mobile UI.
2. **Progress is client-derived and role-dependent in both workspace dashboards.** Web `main.tsx` and Flutter `dashboard_screen.dart` compute completion from top-level tasks loaded for the selected project for admins/managers/leads, but from only the signed-in user's assigned tasks for other members. Thus “Project health” is not consistently project-wide. The dashboard API is loaded, but this percentage is not sourced from its response. Decide the shared metric audience, subtask and empty-project handling, and make project-wide progress server-authoritative before exposing it consistently.
3. **Admin progress/analytics is not the same as project tracking.** Platform analytics endpoints and widgets report aggregates; they do not establish a per-project ownership/progress workflow.
4. **“CRUD for every table” needs exclusions.** Audit/activity events, tokens, notifications, assignment junctions, and system records have controlled lifecycle operations. They should not receive arbitrary edit/delete behavior by default.
5. **The status proposal needs mapping.** Existing project/task statuses differ from the feedback’s labels. No value should be persisted until aliases versus new states and transition rules are decided.
6. **Project-member role editing is implemented across API, Web, and Flutter.** The API contract permits organization admins/owners and project managers, preserves an active project manager, and writes an admin audit event. Both clients restrict the manager option to authorized grantors, display guests as viewer, reload authoritative membership on success, and surface stable errors.
7. **Existing tests are sparse for this scope.** The repository contains basic .NET test files, Web smoke scripts for registration, notifications, attachments, team, and API behavior, plus Flutter API-client/widget tests. A filename scan cannot confirm test coverage for every role/lifecycle scenario; map actual assertions before implementation.
8. **Slice 0 guest write-check is complete.** Pre-fix endpoint tests confirmed legacy guest project memberships above viewer could reach task create/edit/assignee update, subtask creation, and comment creation; attachment upload passed the access check and reached storage configuration handling. Viewer task writes were denied. Task Trash already had a direct guest exclusion. A shared project access check now rejects organization guests for shared-path writes and preserves viewer rejection. See the spec and progress tracker for test results.
9. **Follow-ups:** guest invitation reactivation now clamps project roles to `VIEWER` and audits any elevated role it changes. AI task suggestions now require the shared write-level project access check in a separate commit. Historical role cleanup remains conditional on the owner reviewing the provided read-only query results; no migration is included yet.

## Verification checklist for the next screen pass

- For each interactive Web and Flutter screen, record the exact action, endpoint, success refresh behavior, error behavior, and required role.
- Check creation/edit/deletion/restore controls on narrow and desktop layouts where relevant.
- Exercise same-tenant allowed access, cross-tenant denial, inactive membership, guest/viewer restrictions, archived project access, and deleted/trashed entity behavior using existing test/smoke infrastructure.
- Confirm whether current tests cover the behavior before proposing new test cases; do not treat undocumented coverage as present.

## Remaining product decisions and verification

- Verification of each accepted CRUD action across the API, Web, and Flutter before any missing endpoint is added.
- Whether fixed organization/project roles suffice or custom permissions are required.
- Verification of assignment, owner transfer/removal, all-project organization deactivation, and task-assignee history behavior.
- Implementation of the approved server-side progress calculation and tenant/access tests.
- Existing status values remain stored unchanged; verify approved display mappings across clients and reports.
- Web and Flutter are both approved release targets; verify parity before each slice is complete.

## Phase 0 outcome: candidate gaps and policy checks

These are findings for product/security review, not implementation approval:

The CRUD scope, ownership/reassignment policy, and progress/status rules require independent owner approval. Until the relevant decision is approved, only read-only inspection, documentation, gap identification, and test planning are allowed.

1. **Project member role update:** complete in API, Web, and Flutter with fixed roles and server-side authorization. This does not add custom roles or per-role permissions.
2. **Progress meaning and consistency:** both clients label a project-wide percentage for admins/managers/leads as “Project health” while other members see completion of their assigned tasks. Confirm the shared project metric audience and separate personal workload reporting. Proposed formula and status mapping are in `docs/product-improvements-progress-status.md`.
3. **Guest write authorization:** Slice 0 resolved this for task/collaboration writes through the shared server authorization path; regression tests cover viewer and legacy elevated guest project roles.
4. **Comment editing:** no update route or observed edit control. Confirm whether this is intentionally excluded from CRUD scope.
5. **Project assignment semantics:** multiple participants can be added through active project membership; task assignees are separate. `Project.OwnerId` is initialized to the creator but is not exposed as owner identity in the project list or client models. Project-member removal currently does not reconcile this owner reference or task-assignee links. See the assignment proposal for safe options; no behavior change is authorized.
6. **Task status vocabulary:** existing task statuses are `TO DO`, `IN PROGRESS`, `REVIEW`, `DONE`; proposed Pending and Under Testing could be labels or new states. Decide before changing persistence or reports.
7. **CRUD exclusions:** audit/activity, tokens, notifications, and junction/assignment rows remain managed through constrained lifecycle actions, not generic editable table screens.

Suggested next step: agree the user-facing CRUD scope and system-managed exclusions, then decide project-assignment semantics and the shared progress/status rules before starting those implementation slices. Keep custom permissions as a separate security initiative.
