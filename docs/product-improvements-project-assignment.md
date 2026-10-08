# Proposed Project Assignment and Ownership

**Status:** Product decisions approved; Slice 2 backend accepted; Slice 3 member-removal scope review pending
**Date:** 2026-10-08
**Roadmap:** [Safe Product Improvements Roadmap](product-improvements-roadmap.md)
**Inventory:** [Product Improvements Phase 0 Inventory](product-improvements-inventory.md)
**Approval record:** [Product Improvements Owner Decision Record](product-improvements-owner-decisions.md)

## Slice 2 backend implementation status

The ownership-transfer route is implemented at `PATCH /api/v1/projects/{projectId}/owner`. It requires an expected current owner, rechecks actor and recipient eligibility transactionally, supports archived projects and trashed projects within retention without restoring them, and writes administrative audit and workspace activity atomically. The exact request, responses, lifecycle rules, and verification cases are in the [Project Owner Transfer API Contract](project-owner-transfer-api-contract.md).

Slice 2 was accepted for closure on 2026-10-08. Web/Flutter owner display and transfer controls, task-resolution workflows, progress/status changes, and CRUD expansion remain outside its scope. Member removal and task resolution are proposed separately in the [Slice 3 scope review](product-improvements-slice-3-scope-review.md); that proposal is not implementation authorization.

## Current model and behavior

- `Project.OwnerId` stores one user ID. Project creation sets it to the creator and creates that user as a `PROJECT_MANAGER` member.
- `ProjectMember` stores active project membership and a fixed project role. Existing API routes list, add, update the role of, and deactivate project members. Web and Flutter expose member management. This supports assigning a project to multiple people if “assignment” means project participation/access.
- `TaskAssignee` stores task-level assignments separately and supports multiple assignees per task. A project membership does not automatically assign every task to that person.
- The project list response includes the caller's role but not `OwnerId`; project detail returns the project entity, but the Web and Flutter project models do not currently expose the owner. The clients therefore do not consistently identify the accountable project owner.
- Project-member removal protects the owner and active-manager invariants and blocks removal while open task assignments remain unresolved. It does not transfer `Project.OwnerId` or reconcile task-assignee rows. Organization-member removal also deactivates project memberships only after its approved safeguards pass.

## Recommended meaning

Use the existing relationships; do not add a separate project-assignee table unless the product confirms that assignments must be independent of project membership.

1. **Project participants:** an active `ProjectMember` is an assigned project participant. Multiple participants are supported. The project role continues to govern project access and capabilities; it is not a workload estimate.
2. **Accountable owner:** `Project.OwnerId` identifies one accountable owner, initially the creator. Ownership is distinct from task assignment and from the broader participant list. The owner must be an eligible active project member in the same organization with the `PROJECT_MANAGER` role.
3. **Task assignees:** task assignment remains independent. Adding someone to a project does not assign existing or future tasks to them. Tasks continue to support multiple assignees.

## Approved behavior

| Decision | Recommended default | Reason / impact |
|---|---|---|
| Assignment data model | Treat active `ProjectMember` rows as project assignments; add no new table. | Existing API and both clients already support adding multiple members. Avoids duplicating membership and permission state. |
| Ownership meaning | Keep one accountable owner in `Project.OwnerId`; initialize it to the creator. Require the owner to be an active project manager. | Distinguishes responsibility from the set of collaborators and preserves a clear project lead. |
| Owner transfer | Allow the active current owner, an active organization owner/admin, or an active project manager to transfer ownership only to an eligible active project manager in the same project and organization. Require the expected current owner in the request. Do not promote the recipient or demote the previous owner. Record the transfer in activity/admin audit. | Expected-owner validation prevents stale concurrent requests from overwriting a newer transfer. |
| Archived/trashed ownership | Permit ownership maintenance on archived projects and projects in Trash retention. Do not reactivate or restore them. Reject trashed projects outside retention and purged projects. | Archived projects retain accountability; trashed projects may still be restored during retention. |
| Removing the owner | Require an explicit ownership transfer first; reject removal while the target is still `Project.OwnerId`. Apply the same rule to organization-member deactivation. | Prevents an ownerless project and stale references. It adds a user-visible prerequisite to existing removal flows. |
| Removing a project participant with open tasks | Before removal, require each open task assigned to that member to be reassigned to an eligible active project member. Do not offer silent clearing as the default. Preserve historical attribution in append-only activity/audit history; do not leave active assignee links to an inactive project member. | Keeps outstanding work accountable. This needs transactional validation and a client flow listing and resolving affected tasks before removal. |
| Re-adding a removed participant | Restore membership only; do not silently restore old task assignments. | Prevents historical work allocation from becoming active again unexpectedly. |
| Guest participants | Keep guests as viewer-only project members; do not allow them to own a project or receive task assignments. | Matches the current guest write restrictions and approved fixed-role policy. |

The product owner approved these ownership and assignment decisions on 2026-10-08. The backend ownership-transfer operation is implemented in Slice 2; member removal/task resolution remains a later slice. The independent decisions are recorded in `docs/product-improvements-owner-decisions.md`.

## Implementation boundaries

- Keep existing project-member routes for participant assignment and role management.
- Ownership transfer is available through the additive route in [Project Owner Transfer API Contract](project-owner-transfer-api-contract.md). The request uses an expected-owner precondition and validates actor and recipient eligibility on the server.
- Owner identity in the project list and Web/Flutter transfer controls remain client follow-up work. Existing response shapes were not changed in Slice 2.
- Make ownership transfer and participant removal transactional with their audit/activity entries and any required task-assignee changes.
- Update Web and Flutter to show the accountable owner separately from the participant list, provide the approved transfer/remove flow, and reload authoritative project/member/task data after success.
- Publish existing organization/project change notifications only after successful persistence.

No schema change was needed for Slice 2: `OwnerId`, `ProjectMember`, and the existing audit/activity tables represent the approved behavior. No migration was added.

## Required verification

- Same-organization assignment allowed; cross-tenant and inactive organization users rejected.
- Role matrix for owner/admin/project manager/team lead/contributor/viewer/guest on add, transfer, removal, and task reassignment.
- Suspended/deactivated owner and member handling; archived and trashed projects.
- Owner transfer and active-manager invariant under concurrent changes.
- Participant removal with no tasks, open tasks assigned, and completed tasks assigned.
- Task-assignee reads exclude inactive assignments while preserving the agreed historical display.
- Web and Flutter display, loading, rollback/error behavior, realtime invalidation, and backward compatibility with older clients.

## Owner decisions

- [x] Project assignment uses active project membership; no separate assignment table.
- [x] Exactly one accountable owner per project; owner must be an active project member with `PROJECT_MANAGER` role.
- [x] Current owner, authorized organization admin/owner, or existing project manager may transfer ownership to an eligible active project manager. Transfer does not promote the recipient.
- [x] Block owner removal until ownership is transferred; apply this to organization-member deactivation across all affected projects.
- [x] For every open task assigned to a removed member, require an explicit choice to reassign to an eligible active member or leave unassigned. Preserve completed-task attribution and record all changes in the activity trail.
- [x] Re-adding a member restores membership only; it does not restore old task assignments.
- [x] Guests cannot own projects or receive task assignments.
