# Project Owner Transfer API Contract

**Status:** Slice 2 backend implementation; awaiting review checkpoint
**Date:** 2026-10-08
**Product decisions:** [Project Assignment and Ownership](product-improvements-project-assignment.md)

## Route

```http
PATCH /api/v1/projects/{projectId}/owner
Content-Type: application/json
```

```json
{
  "expectedOwnerId": "current-owner-guid",
  "newOwnerId": "eligible-project-manager-guid"
}
```

Success returns `204 No Content`. A transfer to the current owner is a no-op only when `expectedOwnerId` matches the persisted owner; no audit, activity, or realtime event is written for a no-op.

## Authorization and eligibility

- The actor must have an active account and active, non-guest membership in the project's organization.
- The current accountable owner, an organization owner/admin, or an active project manager may transfer ownership. Team leads and other roles may not.
- The recipient must already have an active `PROJECT_MANAGER` membership in this project, active non-guest organization membership in the same organization, and an active account. Guests and cross-organization members are ineligible.
- The transfer does not promote the recipient or demote the previous owner.
- Eligibility and authorization are rechecked inside the serializable transaction.

## Project lifecycle

- Projects in any normal status may be transferred.
- Archived projects may be transferred for ownership maintenance only. The request does not clear `ArchivedAt` or change project status.
- Trashed projects may be transferred while `DeletedAt` is within the existing 30-day Trash retention window. The request does not clear `DeletedAt`, restore the project, or change project status.
- A missing project or trashed project outside retention returns `404 Not Found`. A permanently purged project has no row and also returns `404`.
- This route changes ownership only. It does not edit tasks, project members, project lifecycle state, or any other resource.

## Responses

| Status | Code | Meaning |
|---|---|---|
| `400` | `PROJECT_OWNER_INVALID_REQUEST` | Either owner ID is empty. |
| `403` | `PROJECT_OWNER_TRANSFER_FORBIDDEN` | Actor is inactive, a guest, cross-organization, or lacks transfer authority. |
| `404` | — | Project is absent or outside Trash retention. |
| `409` | `PROJECT_OWNER_CHANGED` | `expectedOwnerId` does not match the persisted owner. Refresh and retry with the current owner ID. |
| `409` | `PROJECT_OWNER_RECIPIENT_NOT_ELIGIBLE` | Recipient is not an eligible active project manager in the same organization. |
| `409` | `PROJECT_OWNER_TRANSFER_CONFLICT` | Bounded transient database retries were exhausted. Refresh project data and retry. |

## Atomicity, audit, and concurrency

The API updates `Project.OwnerId`, writes an `AdminAuditEvent`, and appends a workspace `ActivityEvent` in the same serializable transaction. Both audit records identify the project and actor; the administrative record includes previous and new owner IDs. Failure to persist any record rolls the owner update back. The project change event is published only after commit.

`expectedOwnerId` is compared with the persisted owner inside the transaction. This prevents stale concurrent requests from silently replacing a newer transfer. Execution-strategy retries are bounded; exhaustion maps to `409 PROJECT_OWNER_TRANSFER_CONFLICT`.

No schema change or existing response-shape change is required. Client display and transfer controls are out of scope for this backend slice.
