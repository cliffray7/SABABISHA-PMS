# Proposed CRUD Scope

**Status:** Conditionally approved; verify before adding endpoints  
**Date:** 2026-10-08  
**Roadmap:** [Safe Product Improvements Roadmap](product-improvements-roadmap.md)  
**Inventory:** [Product Improvements Phase 0 Inventory](product-improvements-inventory.md)  
**Approval record:** [Product Improvements Owner Decision Record](product-improvements-owner-decisions.md)

## Goal

Define the CRUD promise for user-facing product resources without treating every database table as an editable record. “Delete” follows the existing lifecycle: reversible removal, archive, recipient dismissal, or system purge as appropriate. Audit records, tokens, junction rows, and generated records are not general-purpose CRUD resources.

This is a proposed scope based on the current V1 route inventory. It is not approval to add endpoints, alter retention, change role checks, or introduce schema changes. Screen-level parity and role/error behavior still require targeted verification before implementation.

## Candidate user-facing scope

| Resource | Candidate user actions | Existing API support observed | Candidate gap / policy decision |
|---|---|---|---|
| Organizations | Create, list/view; possibly edit basic display fields | List/create; no organization detail, update, or delete route observed | Decide whether organization profile editing is needed. Do not add hard delete by default because organizations own projects and historical activity. |
| Organization members and invitations | View members/invitations, invite, accept, revoke invitation, update fixed role, remove member | These lifecycle routes exist; fixed organization-role management is available | Keep invite acceptance token-driven. Treat member removal as deactivation/revocation, not deleting historical work. Verify Web/Flutter flow parity and denied/error states. |
| Projects | Create, list/view, edit, archive, restore archive, move to Trash, restore from Trash | List/create/detail/update/archive/restore/Trash routes exist | No user-facing hard delete is proposed; permanent purge remains the retention worker's responsibility. Verify all actions are surfaced consistently in both clients. |
| Project members | Add, list/view, update fixed project role, remove | Add/list/remove and role-update routes exist; role editing is implemented in API, Web, and Flutter | Removal deactivates membership and must preserve the active-manager invariant. Project assignment semantics are handled separately in Phase 2. |
| Tasks and subtasks | Create, list/view, edit, change status/priority/dates, assign members, trash, restore | Task and subtask list/create/update/Trash/restore routes exist; task retrieval is through project task listing and task detail data | No standalone task GET was observed. Validate that both clients can open any task from supported entry points and that Trash lifecycle actions are clear. Permanent purge remains system-managed. |
| Comments and mentions | Create/view comments; soft-delete and restore; mentions are generated from comment content | Comment list/create/delete/restore routes exist; no comment update route observed | Decide whether authors may edit their own comments (and whether managers may edit others). If comment editing is required, specify edit window, audit/activity behavior, and mention recalculation before adding an endpoint. |
| Attachments | Upload, list/view, download, soft-delete, restore | These routes exist | Treat uploaded file bytes as immutable. Replacing a file means uploading a new attachment; permanent asset purge remains system-managed. Decide separately whether attachment display-name metadata needs editing. |
| Notifications | View recipient's notifications and mark one/all read | List and read-state updates exist | Notifications are system-generated and recipient-scoped. Do not allow arbitrary create/edit. Decide whether “delete” means dismiss/archive; no generic delete route was observed. |
| Account/profile | View and update own profile, upload/replace avatar, request/complete password reset | Self-service profile and avatar routes and password-reset flow exist | Password, token, and authentication records are security flows, not CRUD screens. Verify field and error parity between clients. |
| Platform users | SuperAdmin create, view/list, suspend, and delete users | Create/list/delete and suspension actions exist | Suspension and deletion are privileged lifecycle actions with audit requirements, not ordinary edit/delete. Do not expose organization-role editing as custom platform roles. |
| Activity and audit | View/filter/paginate | Read-only workspace activity and admin audit routes exist | Append-only records: no update or delete. Preserve audit retention and access boundaries. |

## Explicit exclusions from generic CRUD

- Refresh tokens, OTP codes, password-reset tokens, invitation secrets, and other credentials: lifecycle-managed by authentication flows.
- Activity and administrative audit records: append-only and read-only to users.
- Task-assignee, project-member, and mention junction/generated records: manage through their parent workflow and enforce parent permissions.
- Notifications: created by system events and owned by the recipient; only supported read-state actions are in candidate scope until dismissal is specified.
- Soft-deleted resources and Cloudinary assets: restore or purge through existing retention workflows; no direct database editing.
- Physical organization/project deletion: not assumed. Archive, Trash, and retention purge remain distinct actions.

## Recommended acceptance boundary

1. Accept the resource list and exclusions above as the meaning of “CRUD for every table.”
2. Keep existing lifecycle actions; do not add hard deletion where the system already uses soft delete, archive, revocation, or purge.
3. Treat comment editing, organization profile editing, notification dismissal, task standalone retrieval, and attachment metadata editing as explicit gaps requiring a product decision before implementation.
4. For each accepted gap, record the API authorization matrix, Web and Flutter flow, audit/activity effects, error behavior, and regression cases before code changes.

## Verification needed before claiming CRUD parity

- Map each accepted action to its API route, exact Web and Flutter control, success refresh behavior, error display, and allowed roles.
- Verify tenant isolation, inactive membership, guest/viewer restrictions, archived/trashed states, and append-only boundaries where relevant.
- Reuse current API routes where possible; add only the endpoint that an accepted requirement proves is missing.
- Keep API additions backward-compatible and follow the existing archive, Trash, restore, and 30-day purge behavior.

## Owner decisions

- [x] Conditionally approve the candidate user-facing resource list, system-managed exclusions, and existing lifecycle behavior. Verify current API, Web, and Flutter actions before adding any endpoint.
- [ ] Decide whether comment editing is required and who may edit comments.
- [ ] Decide whether organization profile fields, notification dismissal, task detail retrieval, or attachment metadata editing are required.
- [x] Web and Flutter are both release targets for accepted gaps.
