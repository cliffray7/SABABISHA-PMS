# Product Improvements: Owner Decision Record

**Status:** Approved, subject to the verification gates below  
**Approved:** 2026-10-08  
**Roadmap:** [Safe Product Improvements Roadmap](product-improvements-roadmap.md)

The product owner selected all three approvals in the supplied decision text. The decisions are approved independently as recorded below. The safeguards are binding. This approval authorizes pre-implementation verification and planning; application changes must wait until the verification gate is satisfied and the implementation plan is reviewed.

## 1. CRUD scope

**Recommended approach:** Conditionally approve the proposed user-facing resource list, system-managed exclusions, and existing lifecycle behavior in [Proposed CRUD Scope](product-improvements-crud-scope.md). Verify each accepted action in the API, Web, and Flutter before adding an endpoint. Add only behavior that the verification proves is missing and the owner has approved.

**Approval:** Approved conditionally. Verify each accepted action in the API, Web, and Flutter before adding any endpoint. Add only behavior proven missing and explicitly included in the accepted scope.

## 2. Ownership and open-task reassignment

**Approved approach:** Require every active project to retain at least one active, authorized project manager, using the existing server-side active-manager definition. Before removing a member who is assigned to open tasks, require an explicit choice to reassign only that departing member's assignment to an eligible active project member or leave that member's responsibility unassigned. Preserve every other eligible assignee on the task. Treat `REVIEW` as open; `DONE` tasks retain historical attribution and require no reassignment. Explicit unassignment is allowed without a replacement. Record assignment changes in queryable append-only history. Resolve project ownership through the Slice 2 transfer endpoint before removing its accountable owner; organization deactivation does not implicitly transfer ownership. Organization-member deactivation must validate every affected project and apply assignment resolution, membership deactivation, and audit/activity writes transactionally across all affected projects.

An accountable owner must be the project's single `OwnerId`, an active project member with `PROJECT_MANAGER` role. Ownership transfer may be initiated by the current owner, an authorized organization admin/owner, or an existing project manager. The recipient must already be an eligible active project manager; transfer does not promote their role. Block removal of the accountable owner until ownership is transferred. Re-adding a member restores membership only and does not restore old task assignments. Guests cannot own projects or receive task assignments.

“Eligible active member” must be validated using current server-side organization/project membership and task-assignment rules. The API must enforce the approved policy; client checks are only guidance. The existing manager guard remains server-authoritative. Record all ownership, reassignment, clearing, and removal changes in the activity trail.

**Approval:** Product rules approved 2026-10-08. Slice 3 is approved for a backend-only specification/design pass; implementation remains unauthorized until the API contract, history-storage design, transaction/locking plan, request limits, and affected-file list receive separate approval. Client workflows are outside Slice 3 and require their own review. See [Slice 3 scope review](product-improvements-slice-3-scope-review.md).

## 3. Progress formula and status mappings

**Approved approach:** Use one documented, server-calculated progress definition and response shared by the API, Web, and Flutter. Do not change the meaning or persisted value of any existing status beyond the display-label mapping below.

Candidate formula, if task completion is selected:

```text
progress = completed eligible tasks / total eligible tasks * 100
```

Include all non-deleted top-level tasks regardless of assignee; count only `DONE` as completed; exclude subtasks; show “No tasks yet” when there are no eligible tasks. Keep personal workload completion separate. Active project members may see the aggregate while individual task details continue to follow existing access rules. Do not include archived or trashed projects in active tracking; show an archived project's historical summary only when current access policy permits it. Use project time zone when configured, otherwise organization time zone, then a documented system default. Current project records have no project-time-zone field; the organization time zone defaults to UTC. See [Project Progress and Status Rules](product-improvements-progress-status.md).

Approved display labels, with database values unchanged:

| Scope | Database value | Display label |
|---|---|---|
| Project | `PLANNING` | Planned |
| Project | `ACTIVE` | In Progress |
| Project | `ON_HOLD` | On Hold |
| Project | `COMPLETED` | Completed |
| Task | `TO DO` | To Do |
| Task | `IN PROGRESS` | In Progress |
| Task | `REVIEW` | In Review |
| Task | `DONE` | Done |

Do not introduce `PENDING`. Only `DONE` counts as task completion. Project lifecycle status remains separate from task workflow status.

**Approval:** Approved. Verify one server-side calculation, tenant isolation, client parity, refresh/realtime behavior, and backward compatibility before implementation.

## Pre-implementation verification gate

Before changing application behavior, verify the existing API authorization/fixed-role matrix; manager and owner invariants under concurrent transfers/removals; task reassignment and historical attribution; server-side progress calculation and tenant isolation; Web/Flutter loading, errors, refresh and realtime behavior; and backward compatibility. Record findings and tests in a reviewable implementation plan.

No schema migration is approved unless verification proves an approved requirement cannot be implemented safely with existing relationships. Do not change application code until the verification findings and implementation plan are complete.

## Slice 2 implementation authorization

The product owner conditionally authorized backend ownership transfer only after a recoverable Slice 1 checkpoint. That boundary is recorded in commit `5d19e4c` on `feat/slice-1-authorization-safeguards`; Slice 2 was accepted for closure in commit `d5c01ca` on `feat/slice-2-ownership-transfer`. See [Project Owner Transfer API Contract](project-owner-transfer-api-contract.md). This authorization does not cover Web/Flutter controls, member/task-resolution workflows, progress calculations, CRUD expansion, or schema changes.
