# SuperAdmin API Contract Proposal

**Status:** Contract recommendations consolidated for review. Account suspension authentication and the first administrative audit slice are implemented locally. Remaining contracts are not implemented.

**Scope:** API design plus a narrowly scoped account suspension correction. Existing routes and response shapes are preserved; deployment and all other backend changes require separate review.

## Existing API baseline

The current admin controller is mounted at `/api/v1/admin` and protected by the `SuperAdmin` authorization policy. The current policy is based on configured administrator user IDs; the browser UI is not an authorization boundary.

Current admin routes include:

| Route | Current behavior |
| --- | --- |
| `GET /users` | Returns all users and active organization counts. |
| `POST /users` | Creates an account. |
| `DELETE /users/{id}` | Suspends an account. |
| `DELETE /users/{id}?permanent=true` | Permanently deletes an account. |
| `GET /organizations` | Returns organizations with owner and summary counts. |
| `GET /projects` | Returns non-trashed projects with organization, task count, and dates. Optional `organizationId` scopes the list; `includeTrashed=true` includes retained soft-deleted projects. |
| `GET /activity-events` | Returns the platform-wide cursor-paged activity feed. Optional `organizationId`, `projectId`, `category`, `search`, `from`, and `to` filters are applied server-side. A project filter is validated against the selected organization and does not require the Super Admin to be a tenant member. |
| `GET /dashboard` | Returns platform totals. |
| `GET /analytics` | Returns growth and task aggregates, with optional date bounds. |
| `GET /reports?format=csv` | Downloads a broad current platform CSV report. |

Health endpoints currently include `/api/v1/health` and `/api/v1/ready`. The readiness check includes the database. These routes do not currently expose a general service inventory or a platform audit trail.

#### Super Admin Activity Explorer project drill-down

`GET /api/v1/admin/activity-events` remains the read-only platform activity endpoint and retains its existing response shape and cursor behavior. The optional `projectId` query parameter narrows events to that project; when combined with `organizationId`, the project must belong to the requested organization. An unknown project or organization/project mismatch returns `404 PROJECT_NOT_FOUND`. The endpoint remains protected by the existing `SuperAdmin` policy and deliberately does not require organization or project membership.

The existing `GET /api/v1/admin/projects` route accepts optional `organizationId` and `includeTrashed` query parameters for the Activity Explorer selector. Defaults preserve existing behavior by excluding trashed projects and returning all organizations' projects. Retained Trash projects are selectable and their events remain historical records; this does not restore the project or enable tenant mutations. Project activity details expose the IDs and available names already present in activity events. Event history is paged server-side and remains read-only.

#### Super Admin project details

The project detail view reuses the existing SuperAdmin policy and adds read-only routes: `GET /api/v1/admin/projects/{projectId}/details`, `/members?page=1&pageSize=50`, and `/tasks?page=1&pageSize=50`. Member/task pages are capped at 100 rows. The details response uses the shared project-progress calculation; member and task responses omit email addresses, task descriptions, and assignee identities. Task rows include only non-deleted top-level tasks and a count of effective assignees. None of these routes require workspace membership, mutate tenant data, or change the existing `/projects` and `/activity-events` response contracts. Unknown project IDs return 404; invalid page values return 400. Archived and retained-Trash project details are historical and read-only.

### Implementation facts that constrain new contracts

- Refresh credentials are stored as hashed rows with IDs, user IDs, creation/expiry timestamps, and revocation timestamps. Refresh rotates one row into another; there is no stable device/session identifier or client metadata to group those rows into user-facing sessions.
- The current local implementation of user suspension changes `User.Status` to `suspended`, revokes all active refresh-token rows, consumes unused OTP codes, and writes an audit event in one serializable transaction. Login and OTP verification reject suspended accounts, and refresh checks account status. Existing access JWTs are stateless and remain usable until expiry (15 minutes by default).
- The local `GET /api/v1/admin/audit-events` endpoint reads successful user creation, suspension, and permanent deletion events. It does not yet record denied attempts, other admin activity, or provide an export. Apply `database/sqlserver/migrations/002_admin_audit_events.sql` before deploying this API build.
- Organizations currently have no suspension state or suspension timestamp in the domain entity. Organization suspension requires a schema and authorization-behavior design, not only an endpoint.
- The current CSV report selects all users, organizations, projects, and tasks and materializes those collections before writing the file. It does not apply date or section filters or a row cap.
- Current admin list routes return complete arrays. Add paginated routes additively; changing these response shapes would break existing clients.

New contracts should be additive and versioned. Do not repurpose existing `DELETE /users/{id}` semantics or silently change existing list responses to paginated envelopes; introduce new routes or an explicitly versioned migration if that becomes necessary.

## Shared contract requirements

### Authorization

- Require the existing `SuperAdmin` policy for every proposed `/api/v1/admin/*` route.
- Enforce authorization on the server for each request. Client-side route guards, hidden buttons, and disabled controls are usability only.
- Do not add role assignment or temporary elevation until the server has an approved role matrix, authentication requirements, and recovery process.
- Deny by default and return a consistent `403` response for an authenticated caller without the required permission.

### Validation and errors

- Validate path IDs, enum values, date ranges, page limits, target state, and required reasons on the server.
- For high-impact commands, require a trimmed reason of 10–500 characters; tell operators not to enter passwords, tokens, or unnecessary personal data in a reason.
- Use stable machine-readable error codes and a safe human-readable message. Do not return stack traces, tokens, credentials, or raw provider responses.
- Recommended outcomes: `400` malformed input, `401` unauthenticated, `403` unauthorized, `404` target not found, `409` state conflict, `429` rate limit, and `5xx` unexpected service failure.
- For new routes, use RFC 9457 Problem Details with an additional stable `code` field. Preserve legacy error bodies on existing routes.
- Keep current endpoints' error shapes unchanged. Apply a consistent problem response to new endpoints and document it in OpenAPI.

### Pagination and filtering

- Use opaque cursor pagination for audit events and sessions. A page size defaults to 50 and is capped at 100.
- A cursor must be bound to the normalized filters and a stable ordering, and must not expose database keys or query internals.
- Return `{ items, nextCursor }`; `nextCursor: null` means there are no further results.
- Order audit events and sessions newest first with a stable ID tie-breaker. Treat expired or malformed cursors as `400 INVALID_CURSOR`.
- Use UTC ISO 8601 timestamps. Treat `from` as inclusive and `to` as exclusive. Require both or neither, reject a reversed or future range, and cap a requested range at 366 days. For audit queries, omitting both means the most recent 30 days.
- For mutations, use resource IDs and explicit action routes. Do not accept arbitrary entity patches from the SuperAdmin browser.

### Auditability and safe retries

- Persist a server-side audit event for every privileged mutation, including the actor, target, action, outcome, timestamp, correlation ID, and reason where required.
- Record rejected high-risk attempts where policy permits, without logging secrets or sensitive request bodies.
- Make command retries safe. Mutations should be idempotent where practical or support an idempotency key with a defined retention period.
- Send idempotency keys in an `Idempotency-Key` header rather than request-body fields. Scope keys to actor, route, and normalized request; retain results for at least 24 hours.
- Return the authoritative post-action state. The UI must not show success until the server confirms it.

## Proposed contracts

### 1. Append-only administrative audit history

#### Query

`GET /api/v1/admin/audit-events`

Proposed query parameters:

| Parameter | Meaning |
| --- | --- |
| `from`, `to` | Both omitted means the previous 30 days. If supplied, both are required; inclusive start/exclusive end, maximum 366 days, and neither may be in the future. |
| `actorId` | Filter by the administrator who initiated the action. |
| `action` | Filter by a documented action enum, such as `user.suspend`. |
| `targetType`, `targetId` | Filter by affected resource. |
| `outcome` | `succeeded`, `failed`, or `denied`. |
| `cursor`, `pageSize` | Opaque continuation and bounded page size. |

Proposed item shape:

```json
{
  "eventId": "opaque-id",
  "occurredAt": "2026-09-29T10:15:00Z",
  "actor": { "id": "...", "displayName": "..." },
  "action": "user.suspend",
  "target": { "type": "user", "id": "...", "displayName": "..." },
  "outcome": "succeeded",
  "reason": "Support request reference",
  "correlationId": "..."
}
```

Do not expose secrets, password data, session tokens, or unrestricted request payloads in event details. The local first slice writes records for user creation, suspension, and permanent deletion atomically with the account mutation; the current legacy routes do not collect a reason, so `reason` is null. Application code only inserts audit records; direct database write access, retention, and access review still need operational controls and security/privacy review. Broader event coverage and denied-attempt logging remain future work.

**Failure and scale:** Invalid filters return `400`; inaccessible endpoint returns `403`; transient storage failure returns `5xx` and does not return a partial page as complete. Apply a maximum time range and indexed server-side filters. Export should be a separate, explicitly permissioned capability with its own audit event. The local endpoint implements bounded date filters, action/actor/target/outcome filters, and cursor pages capped at 100.

### 2. Account sessions and revocation

#### List sessions

`GET /api/v1/admin/users/{userId}/sessions?cursor={cursor}&pageSize={n}`

The current refresh-token rows are not equivalent to user sessions: each rotation revokes one token and creates another, and there is no stable session ID or client metadata. Add a stable session identifier that is carried across refresh rotations before promising device-level session management. Populate an activity timestamp if the UI will report `lastSeenAt`; the existing `LastUsedAt` field must be verified and updated consistently.

Only return session metadata required for access review:

```json
{
  "items": [
    {
      "sessionId": "opaque-id",
      "createdAt": "2026-09-20T08:00:00Z",
      "lastSeenAt": "2026-09-29T09:45:00Z",
      "expiresAt": "2026-10-01T08:00:00Z",
      "revokedAt": null,
      "isCurrent": false,
      "clientLabel": "Browser"
    }
  ],
  "nextCursor": null
}
```

Never return access tokens, refresh tokens, full user-agent strings, or unnecessary IP history. Whether approximate location or IP metadata is needed must be reviewed for privacy and retention first.

#### Revoke a session

`POST /api/v1/admin/users/{userId}/sessions/{sessionId}/revoke`

Send the reason in the body and retry identity in the `Idempotency-Key` header:

```json
{ "reason": "Credential exposure reported" }
```

Require a trimmed reason of 10–500 characters. Return the session ID, `status: "revoked"`, `revokedAt`, and the effective access-token invalidation time. Repeating the request for an already revoked session should return the same effective state without creating additional effects. Return `404` for an unknown user or session, and `409` with `SELF_SESSION_REVOCATION` if the caller tries to revoke the active session they are using. Revoking sessions must invalidate server-side refresh capability; deleting a browser token alone is not sufficient.

The current access JWT is stateless and has a configured lifetime (15 minutes by default). Choose and document one revocation guarantee before implementation: either check session revocation on authenticated requests for immediate access-token invalidation, or explicitly state that existing access tokens can remain valid until their expiry. Do not claim immediate revocation without request-time enforcement. The access JWT should carry the stable session ID if the first option is selected.

The existing `DELETE /users/{id}` soft-suspension route has a local implementation that rejects login, OTP verification, and refresh for suspended accounts, and atomically revokes active refresh credentials plus unused login codes. Its URL and response shape are unchanged. Existing access JWTs are not revoked immediately; they remain valid until their configured expiration (15 minutes by default). This does not add session listing or per-session revocation.

### 3. Organization suspension, restoration, and ownership transfer

These are proposed state-changing operations and must not be simulated in the UI.

#### Suspend and restore

- `POST /api/v1/admin/organizations/{organizationId}/suspend`
- `POST /api/v1/admin/organizations/{organizationId}/restore`

Send the reason in the body and retry identity in the `Idempotency-Key` header:

```json
{ "reason": "Policy case reference" }
```

Recommended behavior: set the organization to `suspended`, preserve all stored records and memberships, deny access to that organization's workspace and project operations, and prevent new invitations. Do not disable a user's access to their other organizations. Restoration re-enables organization access but does not recreate canceled invitations. Store the actor and reason in the audit record; avoid duplicating free-text reasons on the organization row. Repeating the current-state action is idempotent; invalid transitions return `409`. Product/security owners must approve the access and invitation behavior before implementation.

#### Transfer ownership

`POST /api/v1/admin/organizations/{organizationId}/ownership-transfer`

Request:

```json
{ "newOwnerUserId": "...", "reason": "Approved ownership change" }
```

Require a trimmed reason of 10–500 characters and send retry identity in `Idempotency-Key`. Require the destination account to be active and an active member of the organization; otherwise return `409 DESTINATION_NOT_ELIGIBLE`. Atomically promote the destination to `OWNER` and demote the prior owner to `ADMIN`, preserving both memberships. Repeating a transfer to the current owner is idempotent. Return the resulting owner identity and record both prior and new owner IDs in the audit event. A concurrent state change returns `409`; notification failure must not silently roll back a committed transfer and must be separately observable/retryable.

### 4. Explicit health-check states

Current health and readiness routes remain unchanged. If the platform needs a service inventory, add an authenticated read route such as:

`GET /api/v1/admin/health/services`

Proposed response:

```json
{
  "checkedAt": "2026-09-29T10:15:00Z",
  "services": [
    { "name": "api", "status": "healthy", "checkedAt": "2026-09-29T10:15:00Z", "durationMs": 12 },
    { "name": "email", "status": "unknown", "checkedAt": null, "durationMs": null }
  ]
}
```

Status enum: `healthy`, `degraded`, `unhealthy`, `unknown`. Recommended semantics: `healthy` means all required probes succeeded within their timeout; `degraded` means the core service is available but a noncritical dependency or capability is impaired; `unhealthy` means a required probe completed and confirmed a critical failure; `unknown` means no reliable, sufficiently fresh result exists or the check is not configured. Probe timeout and freshness limits must be explicit per check. Do not include credentials, connection strings, or raw exception messages. `checkedAt` indicates when the probe ran, not when the UI rendered the response.

### 5. Bounded server-side report filters

The current `GET /api/v1/admin/reports?format=csv` returns a broad CSV. Keep that behavior stable while agreeing on an additive filtered form, for example:

`GET /api/v1/admin/reports?format=csv&from=...&to=...&sections=users,projects`

Contract decisions required:

- Which date field is filtered for each section (`createdAt`, task completion time, or another event time).
- Whether `from` and `to` are required and the maximum permitted range.
- Allowed sections and whether omitting `sections` preserves the current all-sections export.
- A maximum row count and clear behavior when the limit is exceeded. Never silently truncate a report.
- Whether a large report should become an asynchronous export job rather than a long-running request.

Recommended v1 filter semantics: apply the date range to each selected record's `CreatedAt`; omit both dates to preserve the current all-history behavior; require both dates together when filtering; and let omitted `sections` mean all four sections. This is a creation-date report, not a report of changes or task completions. A separate completion-date filter would need a separate contract.

Return CSV with an accurate filename and content type. Include generation time, selected sections, and applied date bounds in metadata. Invalid ranges/sections return `400`; never silently truncate. A proposed synchronous cap is 50,000 total rows, subject to load testing; exceeding it returns `413 REPORT_TOO_LARGE` with guidance to narrow the range or sections. Larger exports should use a separately designed asynchronous job contract. Audit who requested the export and its filters, but do not put sensitive row values in the audit event.

Browser-only filtering is not a privacy or access-control mechanism because the full report has already been delivered to the client.

### 6. Delegated administrator roles and temporary elevation

Do not define assignment routes until stakeholders approve the role matrix, allowed targets, MFA requirements, approval process, emergency access, expiry, and recovery procedures.

At minimum, the policy must answer:

- Which narrowly scoped roles exist and which actions each role may perform.
- Who may grant or revoke a role, and whether a second approver is required.
- Whether elevation expires automatically and what actions are allowed during elevation.
- How administrators can review current grants and upcoming/expired elevations.
- How emergency access is monitored and revoked.

The server must evaluate those grants on every protected operation. A React role selector or client-stored permission is never sufficient. Keep the current `SuperAdmin` policy unchanged until this security work has an explicit, reviewed implementation plan.

## Delivery and acceptance gates

Each contract is a proposal, not authorization to implement it. Before a backend task starts, review:

1. Data ownership, privacy classification, retention, and migrations.
2. Authorization policy and abuse cases, including self-targeting and concurrent requests.
3. Validation, stable errors, pagination limits, timeouts, and rate limits.
4. Audit event content, append-only guarantees, and mutation/audit consistency.
5. Idempotency, retry behavior, reversibility, and recovery/runbook steps.
6. OpenAPI examples and contract tests for success, validation, denied, missing, conflict, and service-failure cases.
7. Staging verification and deployment as a separately reviewed backend change.

Only after an endpoint is approved and deployed should the frontend add typed calls, loading/error/success states, confirmation for high-impact actions, and query invalidation. Until then, keep the associated UI unavailable or read-only.

## Contract decision register

The defaults below make the contracts concrete enough for review. They are recommendations, not stakeholder approval or deployment authorization. Phase 2 remains open until product, security, and operations owners record their decisions.

| Area | Recommended v1 decision | Owner approval still needed |
| --- | --- | --- |
| Audit history | Implemented locally for successful user create/suspend/permanent-delete actions; default last 30 days; maximum 366-day query; cursor pages of 50, maximum 100; no export. Expand to all privileged mutations and denied high-risk actions after review. | Retention period, event coverage beyond these user actions, denied-attempt capture, storage protection, and access to any later export. |
| User/session security | Suspension blocks login, OTP, and refresh, and atomically revokes active refresh credentials and unused OTP codes. Add stable session IDs before session listing or targeted revocation. Existing access JWTs expire naturally (15 minutes by default). | Accept expiry-based access-token behavior or fund request-time revocation checks; approve session metadata and retention. |
| Organization suspension | Preserve records and memberships; deny access only within that organization; stop new invitations; retain outstanding invitations but do not allow acceptance while suspended; restoration resumes access without recreating canceled invitations. | Confirm invitation policy and whether integrations or organization-scoped exports are also blocked. |
| Ownership transfer | Destination must be active and an active member; transfer atomically, promote destination to OWNER, demote prior owner to ADMIN; require reason and audit both identities. | Decide whether destination must already be ADMIN and which notifications are required. |
| Health checks | Four states (`healthy`, `degraded`, `unhealthy`, `unknown`); bounded per-check timeout; stale or unavailable signals are `unknown`; expose only named configured checks and no raw provider errors. | Service inventory, criticality, timeout and freshness values, and whether the endpoint is SuperAdmin-only. |
| Reports | Add creation-date filters; omitted dates preserve all-history behavior, require both bounds together, maximum 366 days; omitted sections means all; 50,000-row synchronous cap with `413`, never truncate; no async exports in v1. | Approve range and row limits after load testing and confirm all-history exports remain allowed. |
| Delegated access | Keep configured SuperAdmin allowlist unchanged; do not ship delegated roles or temporary elevation in this API tranche. | Any role matrix, grant/revoke approvers, MFA, duration, emergency access, and recovery require a separate security decision. |

### Approval record

The user explicitly authorized the local suspension correction on 2026-09-29; this is not deployment approval. No product, security, or operations approvals for the remaining contract decisions are recorded yet. Do not fill these fields on behalf of reviewers.

| Review area | Reviewer and role | Decision | Date | Notes / approved changes |
| --- | --- | --- | --- | --- |
| Product behavior | Pending | Pending | — | — |
| Security and privacy | Pending | Pending | — | — |
| Operations and capacity | Pending | Pending | — | — |

### Review checklist

Reviewers can approve a recommended default, reject it, or request a change. Record the decision above and update the relevant contract text before any implementation task is opened.

- **Product:** confirm organization suspension and invitation behavior, transfer eligibility and notifications, report section/date semantics, and whether delegated roles are in scope.
- **Security and privacy:** confirm audit event coverage, retention, append-only protections, reason handling, session metadata minimization, and whether existing access JWTs may remain valid until expiry.
- **Operations:** confirm audit storage and recovery, health-check inventory and timeouts, report range/row limits under load, and operational ownership for failures.

Phase 2 is complete only when these three review areas have recorded decisions and the proposal reflects any requested contract changes. Approval of the design is still separate from authorization to implement, deploy, or release backend changes.
## Relationship to the roadmap

This proposal expands Phase 2 of [the SuperAdmin console roadmap](./superadmin-console-roadmap.md). The suspension correction is an explicitly authorized, isolated exception to the Phase 1 frontend-only guardrail. Consolidating these recommendations prepares the remaining contracts for review; it does not approve or implement them.
