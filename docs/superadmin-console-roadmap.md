# SuperAdmin Console: Current Capabilities and Safe Roadmap

## Purpose

This document describes what the TaskFlow SuperAdmin console can do today, which controls would make it more useful and safer, and how to improve it without destabilizing the existing backend.

The current scope is **frontend-first**. Existing API contracts and authorization remain authoritative. The UI must not imply that an action happened when there is no API capability to perform it.

## Current state

The web application has these SuperAdmin pages:

| Page | Current capability |
| --- | --- |
| Overview | Shows platform counts, recent projects, project growth, and task status. |
| Analytics | Shows user/project growth and task status/priority for a selected date range. |
| Users | Lists and creates accounts; the admin route can suspend or permanently delete accounts. Local suspension blocks login, OTP verification, and refresh, and atomically revokes active refresh credentials and unused login codes. Existing access JWTs remain usable until configured expiry (15 minutes by default). |
| Organizations | Lists organizations and summary counts. The page is read-only. |
| Projects | Lists projects and summary information. The page is read-only. |
| Activity | The tenant workspace Activity Center reads `/api/v1/activity` within the active organization. The SuperAdmin Activity Center reads `/api/v1/admin/activity-events` across organizations under the SuperAdmin policy. The separate Audit Trail reads `/api/v1/admin/audit-events` for successful user creation, suspension, and permanent deletion. Neither feed claims complete platform coverage. |
| System health | Checks API health and database readiness. |
| Reports | Downloads the current platform CSV report. |
| Platform settings | Shows informational values; it does not change runtime settings. |

The SuperAdmin API is under `api/v1/admin` and protected by the existing `SuperAdmin` authorization policy. That policy currently checks configured `Operations:AdminUserIds`; the console does not manage administrator roles. Keep this enforcement on the server. Hiding a button or route in React is not an authorization boundary.

Relevant source files:

- `apps/web/src/AdminDashboard.tsx`
- `apps/web/src/AdminAnalytics.tsx`
- `apps/web/src/AdminManagement.tsx`
- `apps/web/src/AdminPlatform.tsx`
- `apps/web/src/AdminReports.tsx`
- `apps/web/src/AdminNav.tsx`
- `src/Pms.Api/Controllers/Rest/V1/AdminController.cs`
- `src/Pms.Api/Program.cs`

## What a capable SuperAdmin console should provide

### 1. Audit history

Show real, searchable administrative and security events with:

- Actor, action, target, timestamp, outcome, and a useful reason or request reference.
- Filters for date range, actor, event type, target, and success/failure.
- A detail view and export for investigations.
- Clear retention and access rules; protect the log from modification by the same actor whose actions it records.

Keep the workspace Activity Center separate from the Audit Trail. The Activity Center is a human-readable product timeline; the audit endpoint is a restricted administrative compliance record. Neither page should claim full platform event coverage. Do not generate sample events or present ordinary application logs as an audit trail.

### 2. Safe account administration

Build a user detail view around existing user data and actions. Make account status clear and distinguish reversible suspension from permanent deletion. Add session revocation, sign-in review, and access review only when the server exposes those capabilities.

For high-impact actions, show the affected account, explain the consequence, require explicit confirmation, and display the server's result. Prefer a reversible action where product policy permits it. Record the action in the audit history when that facility exists.

### 3. Organization and project oversight

Make the current read-only views more useful with search, filtering, sorting, pagination, and detail panels using the data already returned by existing endpoints. Clearly label those views as read-only.

Organization suspension, ownership transfer, member changes, project archival, and restoration need explicit server-side APIs and authorization rules. Do not emulate these operations by hiding records or editing only local UI state.

### 4. Operational status

Keep health checks factual and timestamped. The current checks cover API and database readiness. Add other services, such as outbound email or background processing, only when there is a reliable health signal for them. Show an unavailable/unknown state distinctly from healthy.

### 5. Reports and data access

Explain what a report contains, its time range, and when it was generated. Add filtering or additional formats only when supported safely by the API. Avoid downloading broad data and filtering it only in the browser, because the full data has already reached the client.

### 6. Privileged access

Keep administrator access narrow and monitor use. Industry guidance recommends least privilege, strong authentication such as MFA, review of privileged accounts, and monitoring of privileged changes. If the product later introduces multiple admin roles or time-limited elevation, the server must enforce those roles and elevation rules; a frontend-only role selector is not sufficient.

## Safe delivery plan

### Phase 1: Improve the existing UI without API changes

This phase can be done in the web app alone:

1. Organize navigation by **Overview**, **Manage**, **Monitor**, and **Reports**; keep the existing destinations and routes.
2. Improve search, sort, filter, pagination, empty states, loading states, and table accessibility for data already returned by current endpoints.
3. Add clear read-only labels to Organizations and Projects.
4. Keep Activity tenant-scoped and show only events actually written by supported operations. The API requires active membership and migration 003.
5. Clarify the difference between current health checks and broader service monitoring.
6. Explain report scope before download without claiming that UI filters restrict server-side data.
7. Add confirmation and clear outcome messaging around existing user actions. Do not add new action buttons without a matching endpoint.

This phase must preserve the existing API URLs, request/response shapes, authentication flow, and authorization policy. It must not place secrets in frontend code or change `src/Pms.Api` files.

### Phase 2: Agree on backend contracts separately

**Progress:** The proposal records recommended defaults, a review checklist, and sign-off fields. The account suspension correction and an initial audit trail for user administration are implemented locally. The remaining Phase 2 review is open; this implementation does not approve other backend capabilities.

The audit endpoint requires the additive SQL migration `database/sqlserver/migrations/002_admin_audit_events.sql` before API deployment. Current coverage is limited to successful user creation, suspension, and permanent deletion; other admin mutations and denied attempts are not represented yet.

Some desired controls require information or actions the current API does not provide. Before building those UI controls, define and review separate API work for items such as:

- Append-only administrative audit events and a paginated/filterable audit query.
- Account session listing and revocation.
- Organization suspension/restoration and ownership transfer, if the product needs them.
- Additional health checks with explicit healthy, degraded, unhealthy, and unknown states.
- Server-side report filters and limits.
- Any delegated admin roles or temporary privilege elevation.

For every operation, define authorization, validation, pagination, failure semantics, audit events, and reversibility. Implement and deploy each additional capability as a separately reviewed backend task. Until then, the frontend should show it as unavailable or read-only.

### Phase 3: Connect UI to approved contracts

Once an endpoint exists and is deployed, add one page/action at a time:

1. Add or update typed frontend API models.
2. Add loading, empty, error, and success states.
3. Invalidate/refetch relevant queries after successful mutations.
4. Confirm destructive actions and make the affected target explicit.
5. Verify the UI against the live contract and confirm denied requests are handled cleanly.

Do not create a mock success state for an endpoint that is absent or denied.

## Guardrails

- Keep server authorization as the source of truth. Frontend routing and disabled controls are usability measures only.
- Do not expose API keys, database credentials, or deployment secrets to the browser.
- Do not claim auditability, session revocation, backups, billing controls, or organization suspension unless the system actually supports them.
- Treat permanent deletion, privilege changes, exports, and impersonation as high-risk features requiring explicit policy, server enforcement, and audit records.
- If support impersonation is ever considered, it should be time-limited, clearly visible, constrained to the task, and audited. It should not be added as an unlogged “view as user” shortcut.
- Keep the backend unchanged during the frontend-only phase. Backend work requires a distinct, explicit scope and review.

## Research basis

The recommendations follow established privileged-access and application-logging guidance:

- [Microsoft: Security operations for privileged accounts](https://learn.microsoft.com/en-us/entra/architecture/security-operations-privileged-accounts) — monitor privileged sign-ins and changes, use least privilege, protect privileged accounts with MFA, and consider time-limited elevation.
- [Microsoft: Overview of role-based access control](https://learn.microsoft.com/en-us/azure/active-directory/roles/custom-overview) — use granular roles and access reviews rather than assigning broad privileges by default.
- [OWASP: Logging Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html) — record attributable security-relevant events and enough context to investigate and reconstruct activity.

These are design references, not a claim that TaskFlow currently implements those controls.
