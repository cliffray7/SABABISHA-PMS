# TaskFlow — Slice A Project-Aware Invitation Backend Specification

**Status:** Finalized planning specification — implementation not authorized
**Date:** 2026-10-09
**Scope:** Backend invitation creation, acceptance, lifecycle, and retention
**Separate work:** Web/Flutter onboarding (Slice B) and Super Admin Activity Explorer (Slice C)

## 1. Goal and boundary

Extend the existing organization invitation flow to optionally provision a project membership after the invitee accepts. Keep organization and project membership distinct: selecting or inviting to a project must not grant access before acceptance, and a project-only invitation must not change an existing organization role.

This specification authorizes documentation and contract review only. It does not authorize source changes, SQL migration execution, test implementation, commits, pushes, or deployment.

The following remain outside Slice A:

- Web and Flutter onboarding UI.
- Super Admin activity filtering or navigation.
- The existing project-member add endpoint's team-lead/project-manager grant inconsistency. Track it as a separate security fix; invitation creation must still enforce the approved role rule.
- Custom roles, permission models, manual account/password creation, or changes to the registration/OTP flow.

## 2. Approved product decisions

- **Delivery:** `EMAIL` sends a targeted email invitation. `LINK` creates an email-bound link for the authorized creator to copy. Both use the same acceptance flow.
- **Consent:** An administrator never creates credentials or activates membership directly. The invitee signs in or registers, verifies through the existing OTP flow, then accepts.
- **Expiry:** Invitations expire seven days after creation, using server time.
- **Organization-only invite:** Requires an organization role and activates organization membership on acceptance.
- **Project-targeted invite:** Requires `projectId` and `projectRole`. If `organizationRole` is non-null, acceptance may create the organization membership and project membership atomically. If null, an active organization membership must exist at acceptance, and its role is preserved.
- **Project-only invite:** Must never use the legacy compatibility `role` value as an organization-role grant instruction.
- **Project roles:** Use existing values `PROJECT_MANAGER`, `TEAM_LEAD`, `CONTRIBUTOR`, `VIEWER`. Organization roles use `ADMIN`, `MEMBER`, `GUEST` (and the existing `OWNER` membership value where applicable; invitations must not grant ownership).
- **Lifecycle:** `PENDING` transitions once to `ACCEPTED`, `EXPIRED`, `REVOKED`, or `SUPERSEDED`. Terminal states cannot transition again.
- **Duplicate scope:** At most one pending invite per organization, normalized recipient email, and invitation scope. One organization-wide invite and a project-specific invite may coexist for the same email.
- **Project invitation authority:** Active organization owners/admins may invite to projects in their organization. Active project managers may invite to their projects. Active team leads may invite only to non-manager project roles, subject to existing restrictions. A team lead may never grant `PROJECT_MANAGER`.
- **Already-active project member:** Acceptance returns `409 PROJECT_MEMBER_ALREADY_ACTIVE`; it does not change the member's role or invitation/membership state.
- **Attribution:** Preserve immutable creator/revoker actor IDs and non-sensitive invitation context. Creator fields remain nullable for legacy rows. Do not add user foreign keys that erase actor IDs or block user deletion.
- **History API:** Preserve existing response fields and list behavior. Provide a separate paginated history route with consistent error envelopes.
- **Legacy records:** Do not invent creator attribution or reconstruct invitations already deleted by the old revoke route. A legacy pending invitation with no creator cannot be accepted directly; an authorized administrator must reissue it.
- **Retention:** Keep terminal invitation metadata for 12 months from the terminal transition. For `EXPIRED`, the retention clock starts at `ExpiresAt`, not when a worker observes it. After retention, remove or irreversibly de-identify recipient email and token hash; keep status/timestamps and non-sensitive attribution/context as permitted by applicable obligations.
- **Cleanup:** Use a dedicated daily invitation-retention service, separate from `DeletedContentPurger`. Use bounded batches and database-backed coordination when multiple API instances run. Do not log recipient emails or tokens.
- **Super Admin activity explorer:** Remains a separate, read-only Slice C.

## 3. Current repository contract verified

Current routes in `OrganizationsController`:

| Route | Existing behavior |
|---|---|
| `GET /api/v1/organizations/{id}/invitations` | Owner/admin only; returns unaccepted, unexpired rows with `id`, `email`, `role`, `expiresAt`. No lifecycle status or pagination. |
| `POST /api/v1/organizations/{id}/invitations` | Owner/admin only; accepts `{ email, role }`, normalizes email, creates a seven-day token hash, sends email, records workspace activity, returns invitation metadata. |
| `DELETE /api/v1/organizations/{id}/invitations/{invitationId}` | Owner/admin only; physically deletes an unaccepted invitation and records workspace activity. |
| `POST /api/v1/organizations/invitations/accept` | Authenticated invitee submits `{ token }`; checks authenticated email; creates/reactivates organization membership and marks invitation accepted. Current behavior overwrites the role of an existing membership and therefore must change for project-only invitations. |

Supporting implementation already present:

- `TokenService.CreateRefreshToken()` generates 64 random bytes; `HashRefreshToken()` stores a SHA-256 hash.
- `AppMail.Link()` and `AppMail.Send()` support invitation link construction and email delivery.
- The organization and project membership tables have unique `(organization_id, user_id)` and `(project_id, user_id)` indexes. Existing rows are reactivated rather than duplicated.
- The invitation table has an organization FK, unique token-hash index, and organization/email index. EF mapping disables SQL `OUTPUT` for this trigger-backed table; retain that setting.
- The existing cancellation route physically deletes invitation rows. A rollback to the old application would therefore bypass the retained `REVOKED` lifecycle unless the database migration protects rows from physical deletes.
- Invitation acceptance currently reactivates all inactive project memberships for the invitee in the organization. The new contract must activate only the project membership explicitly requested by the accepted invitation; organization-only acceptance must not restore unrelated project access.
- Project membership roles and guest restrictions are enforced in `ProjectsController`. Its add-member route currently allows team leads to grant `PROJECT_MANAGER`, contrary to the approved restriction. Invitation creation must enforce the approved rule; correcting the existing route remains a separate security fix.
- Registration and login issue usable access tokens after OTP verification. The acceptance endpoint must continue to require authentication and the exact invitation email match.

## 4. Proposed endpoint contract

Existing routes remain. The following shapes are proposed for review; no route change is implemented.

### 4.1 Create invitation

`POST /api/v1/organizations/{organizationId}/invitations`

Legacy request remains supported:

```json
{ "email": "member@example.com", "role": "MEMBER" }
```

New organization-plus-project invitation:

```json
{
  "email": "member@example.com",
  "organizationRole": "MEMBER",
  "projectId": "00000000-0000-0000-0000-000000000001",
  "projectRole": "CONTRIBUTOR",
  "deliveryMethod": "EMAIL"
}
```

Project-only invitation to an existing active organization member:

```json
{
  "email": "member@example.com",
  "organizationRole": null,
  "projectId": "00000000-0000-0000-0000-000000000001",
  "projectRole": "CONTRIBUTOR",
  "deliveryMethod": "LINK"
}
```

Validation:

- Legacy `role` is accepted only as the legacy organization invitation field. If both `role` and `organizationRole` are supplied, reject conflicting values.
- For compatibility rows written by the old application after migration, `organization_role` may be null while `project_id` is null; interpret the legacy `role` as the organization role only in this organization-only case. If `project_id` is non-null and `organization_role` is null, never interpret the compatibility `role` as an organization-role instruction.
- Organization-only invitations require an allowed `organizationRole`.
- A project invitation requires both `projectId` and `projectRole`.
- `organizationRole: null` is valid only if an active organization membership for the normalized email already exists when creating the invite. Acceptance rechecks this.
- The project must belong to the route organization and be eligible for new membership. Initial policy: only active, non-archived, non-deleted projects accept invitations.
- Existing active memberships must not be changed by invitation creation. Guests may only receive `VIEWER` project role. Invitations cannot grant organization ownership.
- Normalize email consistently before persistence and uniqueness checks.
- Authorization must be checked on creation and again at acceptance. Manager grants follow the approved fixed-role rule; team leads cannot grant `PROJECT_MANAGER`.

`EMAIL` sends the link after the database transaction commits. A delivery failure must not roll back committed invitation state. Return HTTP `502` with the stable error envelope and the non-secret invitation ID so the authorized creator can identify the committed record:

```json
{
  "code": "INVITATION_DELIVERY_FAILED",
  "message": "The invitation was created, but the email could not be delivered.",
  "invitationId": "invitation-uuid"
}
```

The response must not contain a raw token, token hash, or invitation link. The current design stores only a token hash, so retrying delivery of the same link is not supported. The supported recovery is the explicit reissue operation in §4.4: it supersedes the pending invitation, creates a new invitation and token, and sends a new link. The client must label this action as a reissue/new-link operation and disclose that the previous link is invalidated; it must not describe reissue as retrying delivery. Avoid holding a database transaction open during external mail calls.

`LINK` returns a link only in the successful creation response, over HTTPS, with `Cache-Control: no-store`. Do not return it from list or activity endpoints. Do not log it. The response must not be cached by intermediaries. The link is email-bound, single-use, and expires after seven days. Define client analytics/referrer handling so the token is not sent to third parties; the invite page should remove the token from the visible URL after safely reading it where feasible.

For backward compatibility, retain the legacy response fields (`id`, `email`, `role`) in creation and pending-list responses. New fields may include `organizationRole`, `projectId`, `projectRole`, `deliveryMethod`, `status`, and `expiresAt`. The raw link appears only in a `LINK` creation/reissue response, never in ordinary invitation retrieval.

### 4.2 Pending invitation list

`GET /api/v1/organizations/{organizationId}/invitations`

Owner/admin only. Preserve the current array response and existing fields for pending, unexpired invitations (`id`, `email`, `role`, `expiresAt`). Additive fields may include `organizationRole`, `projectId`, `projectRole`, `deliveryMethod`, `status`, and creator ID. Never return token hash or raw token. This route remains suitable for the existing client pending-invitation list.

### 4.3 Paginated invitation history

Add `GET /api/v1/organizations/{organizationId}/invitations/history?pageSize=50&cursor=...`.

- Owner/admin only.
- Return `{ items, nextCursor }`, with default page size 50 and maximum 100.
- Include lifecycle, scope/role, timestamps, immutable creator/revoker actor IDs, and email only before the 12-month de-identification deadline.
- Bind/validate cursors against organization and query filters; reject malformed or mismatched cursors with `400 INVALID_CURSOR`.
- Never return raw tokens or token hashes.

### 4.4 Reissue/resend

Proposed route: `POST /api/v1/organizations/{organizationId}/invitations/{invitationId}/reissue` with `{ "deliveryMethod": "EMAIL" | "LINK" }`.

- Owner/admin must be authorized to grant all roles in the replacement invitation.
- Reissuing a `PENDING` invitation atomically marks the old row `SUPERSEDED` and creates a new row with a new token/hash and creator attribution.
- A legacy pending invitation with null creator can be reissued by an authorized administrator. The old row becomes `SUPERSEDED`; no creator is backfilled.
- Terminal records are immutable. Reissuing an expired invitation creates a new invitation and leaves the old row `EXPIRED`; it does not transition a terminal row.
- `EMAIL` sends after commit; `LINK` returns the new raw link once with `no-store`.

An active project membership discovered at acceptance is not silently treated as success: return `409 PROJECT_MEMBER_ALREADY_ACTIVE`, leaving both the membership and invitation unchanged.

### 4.5 Revoke

Keep `DELETE /api/v1/organizations/{organizationId}/invitations/{invitationId}` for compatibility, but change its effect from physical deletion to a `PENDING` → `REVOKED` transition. Return the existing `204 No Content` shape. Repeating a revoke of an already `REVOKED` invitation returns `204`; attempting to revoke another terminal state returns `409 INVITATION_STATE_CONFLICT`.

### 4.6 Accept

Keep `POST /api/v1/organizations/invitations/accept` with `{ "token": "..." }` and existing organization ID response, adding `projectId` when a project assignment was activated.

Acceptance requires a serializable transaction and server-side revalidation of:

1. Token hash, `PENDING` status, and `ExpiresAt > server UTC now`.
2. Authenticated user is active and email matches the normalized invitation recipient; registration/sign-in OTP must have completed.
3. Invitation creator exists and is still authorized for each requested role. If missing or authority was lost, reject with a stable conflict and require authorized reissue. Do not substitute an unrecorded sponsor.
4. Organization exists and is eligible; requested roles remain valid.
5. For a project invitation, project remains in the same organization and is active/non-archived/non-deleted; guest and manager-grant rules still pass.
6. Existing organization memberships are preserved unless the invitation explicitly requested an organization role while creating/reactivating membership. A project-only invitation never changes that role.
7. If the requested project membership is already active, return `409 PROJECT_MEMBER_ALREADY_ACTIVE` without changing the role, invitation state, or membership state.
8. Add or reactivate only the memberships explicitly requested by this invitation. Organization-only acceptance must not reactivate old project memberships. A project invite may reactivate only its specifically requested inactive membership, subject to current eligibility; it must not restore other project memberships or task assignments.
9. Mark invitation `ACCEPTED` and record workspace activity in the same DB transaction. Publish realtime changes only after commit.

Any failure rolls back every requested membership mutation and the invitation-state change. A competing accept/revoke/reissue must result in one winner; losers receive stable conflict responses.

## 5. Authorization matrix

| Operation | Required actor |
|---|---|
| Create/revoke/reissue organization-only invitation | Active organization owner or admin |
| Create/revoke/reissue project-targeted invitation | Active organization owner/admin within that organization; or active project manager for that project; or active team lead for that project only when requested role is not `PROJECT_MANAGER` |
| Grant organization `ADMIN` | Active organization owner/admin, subject to current organization-role policy |
| Grant project `PROJECT_MANAGER` | Organization owner/admin or active project manager; never team lead |
| Grant project role to guest | Only `VIEWER` |
| Accept invitation | Authenticated active invitee whose verified sign-in email matches invitation email |
| List invitation history | Active organization owner/admin |

The invitation endpoints must enforce this matrix both at creation and acceptance. If the recorded creator no longer has the necessary authority, acceptance returns `409 INVITATION_SPONSOR_AUTHORITY_CHANGED`; reissue requires a currently authorized sponsor. The current `ProjectsController.AddMember` team-lead manager-grant inconsistency remains a separate security fix and is not changed by Slice A.

## 6. State and concurrency design

Transitions:

| Current | Event | Next | Terminal timestamp |
|---|---|---|---|
| `PENDING` | Successful acceptance | `ACCEPTED` | `AcceptedAt` |
| `PENDING` | Expiry observed or enforced | `EXPIRED` | `ExpiresAt` |
| `PENDING` | Authorized cancellation | `REVOKED` | `RevokedAt` |
| `PENDING` | Authorized replacement | `SUPERSEDED` | `SupersededAt` |
| Terminal | Any transition | Reject | Unchanged |

Always check expiry against server time during acceptance and create/reissue. A row that is expired by time but still says `PENDING` must not be accepted. Before inserting a replacement, transactionally transition matching expired pending rows to `EXPIRED`.

Use serializable transactions, appropriate indexed predicates/row locks, existing unique membership constraints, and the filtered pending-invitation index. Retry only bounded transient SQL failures; retries must re-read state and must not accept stale assumptions. Record activity in the same transaction; publish realtime and send email after commit.

The duplicate key is `(organization_id, normalized_email, project_id)` for `status = 'PENDING'`; SQL Server unique indexes treat null as a key value, so null `project_id` represents the organization-wide scope and a GUID represents project scope. This allows one organization invite and one pending invite per project for the same recipient. Expired-but-pending rows must be transitioned before replacement, so expiry does not permanently block invitations. Concurrent insert attempts must still be protected by the unique index.

Overlapping invitations may coexist across organization and project scopes. Acceptance must serialize membership checks and rely on unique membership indexes so no duplicate active membership is created. A project invitation that arrives after another flow has activated the organization membership preserves its current role. If the project membership is already active, return `409 PROJECT_MEMBER_ALREADY_ACTIVE` with no state changes.

## 7. Migration 007 design

Proposed new file: `database/sqlserver/migrations/007_project_scoped_invitations.sql`.

Keep the existing required `role` column during staged rollout. Add:

- `organization_role NVARCHAR(30) NULL` — authoritative new organization-role instruction; null means project-only.
- `normalized_email` — persisted computed value `LOWER(LTRIM(RTRIM(email)))`; deriving it in SQL also covers invitation inserts made by an older binary. It becomes null when recipient email is de-identified.
- `project_id UNIQUEIDENTIFIER NULL` and `project_role NVARCHAR(30) NULL` — optional project target. Validate organization/project relationship in application transactions. Do not cascade invitation history when a project is purged; store project ID as historical context without a restrictive FK (or provide equivalent purge-safe behavior).
- `delivery_method NVARCHAR(10) NOT NULL DEFAULT 'EMAIL'`.
- `status NVARCHAR(20) NOT NULL` with check constraint for the five lifecycle values.
- `created_by_user_id UNIQUEIDENTIFIER NULL`; legacy rows and rows written by the prior binary remain null. New rows require creator attribution in application validation. Preserve this immutable actor ID without a user FK so user deletion cannot erase it or be blocked by invitation history.
- `revoked_at` and `revoked_by_user_id UNIQUEIDENTIFIER NULL`, also preserved without a user FK. A database compatibility delete guard may leave `revoked_by_user_id` null when an old binary performs a delete because that binary does not pass actor context to SQL.
- `superseded_at`, `superseded_by_id` (self-reference only if deletion/de-identification behavior is defined).
- `terminal_at` or equivalent retention timestamp. For expiry use `ExpiresAt`; for accepted/revoked/superseded use the actual transition timestamp.

Make `token_hash` nullable for post-retention de-identification and replace/adjust its unique index with a filtered unique index for non-null values. Make recipient email nullable only if needed by de-identification; maintain old response compatibility by excluding de-identified terminal records from legacy clients or providing nullable-safe responses.

Backfill only reliable facts:

- `organization_role = role` for existing rows.
- `normalized_email = LOWER(LTRIM(RTRIM(email)))` while email is present.
- `delivery_method = 'EMAIL'` as a migration default; historical delivery mode is unknown.
- `status = 'ACCEPTED'` when `accepted_at` is non-null; otherwise `EXPIRED` when `expires_at <= SYSUTCDATETIME()`; otherwise `PENDING`.
- Existing `created_by_user_id` remains null; do not fabricate inviter identity.
- Previously deleted invitations cannot be reconstructed.

Add an idempotent filtered unique index on `(organization_id, normalized_email, project_id)` where status is `PENDING`, `accepted_at IS NULL`, and normalized email is not null. Including `accepted_at IS NULL` prevents an old binary's accepted row (whose new status column still says `PENDING`) from blocking another invitation. New code and the daily service must reconcile such rows to `ACCEPTED` using the reliable `accepted_at` timestamp. Add lookup indexes for organization/status/expiry and creator attribution as justified by query plans. Add check constraints requiring project ID and project role together and valid role/status/delivery values; do not add a constraint that rejects compatible old-binary writes.

New columns written by the old application must be nullable or have safe defaults. In particular, old-binary inserts omit `organization_role`, `project_id`, `project_role`, `created_by_user_id`, and `status`; such rows must default to organization-only `PENDING` behavior and be interpreted using the legacy `role` value only when `project_id` is null. The computed normalized email covers these rows. Do not introduce a check constraint that rejects these compatible inserts.

The migration must preserve the invitation table's existing audit trigger and EF `UseSqlOutputClause(false)` behavior. Register `007_project_scoped_invitations` in the established migration ledger pattern. Apply to representative existing data before production; production execution is not part of this slice authorization.

### Migration execution and registration gate

Repository inspection found that `scripts/setup-sqlserver.ps1` explicitly lists migrations 001–005 and does not list migration 006. The reason for that omission and the migration mechanism used in each deployed environment have not been established. Do not assume that adding migration 007 to this script, or adding a ledger row in the SQL file, means it will run everywhere.

Before implementation is authorized, document for each intended environment the actual migration executor and applied migration state, including the `__PmsMigrations` ledger where present. Determine why 006 is absent from the setup script and whether that script is authoritative for local, CI, staging, or production setup. Then specify exactly how 007 will be registered and executed in order after the existing migrations. The 007 migration must be idempotent and tested twice in a disposable SQL Server database with representative legacy rows and trigger definitions. No environment database may be inspected or changed until it is explicitly identified as disposable and authorized for that operation.

If resolving the execution path requires changing `scripts/setup-sqlserver.ps1` or another runner, that path is a conditional additional implementation file beyond the currently proposed 11-file boundary. Its inclusion requires review and approval after the actual runner and the omission of 006 are understood; do not silently expand the boundary.

### Legacy DELETE protection for rollback — verification required; trigger not approved

The current old-binary cancellation route issues a physical SQL `DELETE`. Migration 007 must not be assumed to protect history until a compatibility strategy is selected and tested. An `INSTEAD OF DELETE` trigger remains a candidate only; it is not approved for implementation. The deployed audit-trigger definition is absent from the repository, so inspect the actual trigger metadata and definition in a named disposable SQL Server database before deciding whether this candidate is safe.

The isolated verification must cover both the old direct `DELETE` statement and the old EF Core `Remove`/`SaveChanges` path against the actual audit-trigger behavior. Verify pending-row transition to retained `REVOKED` state, terminal-row retention, affected-row results, trigger recursion, and audit records. Include the physical-delete statement in `scripts/cleanup-smoke.ps1` in the compatibility review. If an `INSTEAD OF DELETE` trigger is selected later, prove it coexists with every existing invitation trigger and does not corrupt audit behavior.

There is an independent rollback risk in the old acceptance implementation: it may use the compatibility `role` as an organization-role instruction and reactivate unrelated inactive project memberships. A delete safeguard does not address this. Before project-aware invitations are enabled, either demonstrate a safe, tested rollback binary that rejects lifecycle-aware/project-targeted invitations or retains the new safe acceptance semantics, or explicitly prohibit rollback to the existing backend binary. If neither has been established, the release is blocked. A default “forward fix only / no rollback to the existing binary” policy is acceptable if recorded in the release procedure. Do not claim rollback compatibility without isolated tests covering both deletion and acceptance.

An additive migration alone does not make the old application behavior safe. No production migration or deployment is authorized by this specification.

### Foreign keys and purge behavior

- Keep the existing organization FK behavior non-cascading; invitation history must not silently disappear on organization deletion.
- Project targeting must not block the existing permanent project purge. Preserve the project GUID as historical context without a restrictive FK, or implement and test a retention-safe equivalent.
- Creator/revoker actor IDs must remain nullable for legacy rows and immutable where known. Do not add user FKs that erase them or block user deletion. Recipient email/token data follows the approved 12-month de-identification rule.
- If a self-FK is used for `superseded_by_id`, retain rows as de-identified tombstones rather than deleting referenced records, or use a purge-safe relationship strategy.

The exact project FK/index choices must be confirmed against project hard-delete code and SQL Server behavior before the migration is authored.

## 8. Dedicated retention service

Proposed exact paths:

- `src/Pms.Api/Invitations/InvitationRetentionService.cs`
- `Program.cs` — register separately with `AddHostedService<InvitationRetentionService>()`.
- `tests/Pms.IntegrationTests/InvitationRetentionServiceTests.cs`
- `tests/Pms.IntegrationTests/SqlServerOrganizationInvitationLifecycleTests.cs` — isolated SQL Server migration, concurrency, and legacy-delete rollback verification.

Run daily in bounded batches. Use a SQL Server database application lock (for example, `sp_getapplock` with a stable invitation-retention resource and transaction ownership) to prevent duplicate work across API instances. Process each batch in a short transaction. First reconcile reliable old-binary state (`accepted_at IS NOT NULL` to `ACCEPTED`) and expired pending rows to `EXPIRED` with terminal time equal to `ExpiresAt`; then find terminal rows whose retention deadline has passed and null/de-identify recipient email and token hash. The computed normalized email follows the email value. Preserve status, transition timestamps, immutable actor IDs, and permitted non-sensitive context. Do not touch unexpired `PENDING` records.

Log counts, duration, and failure category only; never log emails, raw tokens, token hashes, or invitation links. A failed batch must roll back and be retryable without affecting invitation endpoints.

## 9. Proposed exact file inventory

| File | Planned responsibility |
|---|---|
| `src/Pms.Api/Controllers/Rest/V1/OrganizationsController.cs` | Backward-compatible create/list/revoke/reissue/accept API and authorization/transaction coordination. |
| `src/Pms.Domain/Entities/OrganizationInvitation.cs` | New nullable project, lifecycle, creator, delivery, and retention fields. |
| `src/Pms.Infrastructure/Persistence/EfCore/PmsDbContext.cs` | Column limits, checks, indexes, filtered uniqueness, trigger-compatible mapping. |
| `database/sqlserver/migrations/007_project_scoped_invitations.sql` | Idempotent additive schema/backfill/index/constraint change. |
| `src/Pms.Api/Invitations/InvitationRetentionService.cs` | Daily expiry reconciliation and 12-month bounded de-identification. |
| `src/Pms.Api/Program.cs` | Register dedicated retention service. |
| `tests/Pms.IntegrationTests/OrganizationInvitationLifecycleTests.cs` | SQLite/API contract, validation, atomicity, authorization, legacy, and state tests. |
| `tests/Pms.IntegrationTests/InvitationRetentionServiceTests.cs` | Batching, retention cutoff, pending preservation, retry, and coordination tests. |
| `tests/Pms.IntegrationTests/SqlServerOrganizationInvitationLifecycleTests.cs` | Isolated SQL Server migration idempotence, real concurrency, trigger compatibility, and old-binary DELETE protection tests. |
| `docs/organization-invitation-api-contract.md` | Client-facing request/response/error contract. |
| `docs/organization-invitation-slice-a-implementation-spec.md` | This implementation boundary and design record. |

`TokenService.cs`, `AppMail.cs`, Web files, Flutter files, schema unrelated to invitations, and `DeletedContentPurger.cs` remain unchanged unless review identifies a concrete dependency. Any expansion beyond this list requires separate approval.

Conditional runner file: `scripts/setup-sqlserver.ps1` may need to be added if investigation confirms it is an authoritative migration executor that must register/apply migration 007. It is not currently part of the approved 11-file list; adding it requires explicit scope review. Do not change it before resolving why migration 006 is absent and how each environment currently applies migrations.

## 10. Test matrix

### API and authorization

- Legacy `{ email, role }` request remains accepted with existing response fields.
- New organization-only, organization-plus-project, and project-only requests validate required field pairs and actual role values.
- Organization-only invitation requires owner/admin; project invitation follows the final approved project authority matrix.
- Team lead cannot grant `PROJECT_MANAGER`; guest can only receive `VIEWER`.
- Cross-tenant project ID, nonexistent project, archived/completed/deleted project, invalid roles, invalid delivery method, and mismatched email are rejected with stable error codes.
- No membership activates at invitation creation; exact matching authenticated invitee acceptance activates only the requested memberships.
- Project-only acceptance preserves an existing `ADMIN` or `OWNER` organization role; it never uses the compatibility `role` column to overwrite it.
- Organization-plus-project acceptance creates both memberships atomically; any project failure rolls back organization activation and invitation status.
- Existing inactive membership reactivation honors current guest clamp and does not reactivate unrelated old project memberships.
- Missing legacy creator or creator who lost authority returns conflict; authorized reissue creates a new attributed invitation.

### Lifecycle, token, and compatibility

- Email mode sends one target-specific message after commit; link mode returns one link once with `no-store`.
- No list/activity/log response contains raw token or token hash.
- Seven-day boundary uses server UTC time; expired pending rows cannot be accepted even before worker reconciliation.
- Revoke, reissue, accept, expiry, and supersession follow the state table; terminal transitions are rejected or documented no-ops.
- Reissue rotates token, old hash cannot accept, and accepted/revoked/superseded rows remain retained.
- Org-wide and project-scoped invites coexist; duplicate pending same scope is rejected; expired pending row can be safely replaced.
- Existing clients tolerate new nullable response fields and old response fields remain intact.
- Old-binary inserts after migration receive safe organization-only defaults and remain readable by the new API.
- The migration executor and applied migration state are identified for each intended environment; migration 006's omission from `setup-sqlserver.ps1` is explained; migration 007 is registered and executed through the verified path and applies twice idempotently in an isolated SQL Server database.
- Legacy DELETE interception is not relied on unless direct SQL and EF `Remove` behavior pass isolated SQL Server tests with the deployed audit trigger; `cleanup-smoke.ps1` is included in that review.
- Rollback is either supported by a tested safe rollback binary covering both DELETE and acceptance behavior, or explicitly prohibited to the existing backend after project-aware invitations become available.
- Paginated history returns stable `items`/`nextCursor` responses, with malformed/filter-mismatched cursors rejected consistently.
- Already-active requested project membership returns `409 PROJECT_MEMBER_ALREADY_ACTIVE` with no role or invitation change.

### Concurrency and SQL Server

- Two simultaneous acceptances of one invitation: at most one success.
- Acceptance versus revocation and acceptance versus reissue: one transition wins; loser receives stable conflict.
- Concurrent same-scope invitation creates cannot bypass filtered unique index.
- Two overlapping invitations cannot create duplicate memberships or change an existing organization role unexpectedly.
- Project archive/state or inviter permission changes between create and accept are rejected.
- Migration 007 applies twice idempotently against an isolated SQL Server database with representative legacy rows and the actual/faithfully reproduced invitation audit trigger.
- Legacy direct DELETE, EF Core `Remove`/`SaveChanges`, and `cleanup-smoke.ps1` behavior are verified in isolation; no trigger design is presumed safe before the test.
- Rollback acceptance tests prove that a legacy binary cannot accept project-targeted invitations or reactivate unrelated memberships, or the release procedure explicitly prohibits rollback to that binary.
- Run the existing 13 opt-in SQL Server tests plus new invitation SQL Server tests using `PMS_TEST_SQLSERVER_CONNECTION`; report skipped cases explicitly.

### Retention service

- Expiry is reconciled from `ExpiresAt`, not worker observation time.
- Terminal records are retained through the 12-month boundary and de-identified only after it.
- Pending, unexpired invitations are never cleaned.
- A batch failure leaves retryable, consistent data; repeated cleanup is idempotent.
- Two service instances coordinate through the database lock; batch size and transaction duration remain bounded.
- Cleanup preserves required FK/history relationships and never logs personal email or token material.

### Regression

- Existing `GuestInvitationReactivationTests` passes.
- Existing organization/project member role, ownership-transfer, and member-removal tests pass.
- Full backend suite passes; new and existing SQL Server tests run against an isolated database.
- `git diff --check` passes.

## 11. Rollout and rollback

1. Verify the migration against a disposable SQL Server database with representative legacy rows, triggers, constraints, and indexes.
2. Apply the additive migration before deploying code that reads/writes new fields. Keep the legacy required `role` column and old request shape operational during the compatibility window.
3. Deploy backend with legacy/new request handling and safe status defaults. Verify invitation creation, email delivery, link no-store behavior, acceptance, and cleanup metrics in a non-production environment.
4. Deploy clients separately in Slice B. The current clients continue using legacy organization invitation requests until upgraded.
5. Monitor duplicate-invitation conflicts, acceptance failures, delivery failures, cleanup counts, and retention-job errors without logging PII or tokens.

Once new lifecycle records exist, rollback should be a forward fix. Do not drop lifecycle columns, indexes, or invitation history. The current old application physically deletes invitations in its cancellation route, so a rollback to that binary is unsafe unless migration 007 installs and verifies a database-level delete safeguard. Preferred design: an idempotent `INSTEAD OF DELETE` compatibility trigger converts legacy deletes of `PENDING` rows to `REVOKED` with server timestamp and null actor attribution; terminal rows are never physically removed. Because the table is already trigger-backed, inspect and test deployed trigger definitions and EF affected-row behavior before selecting this mechanism. If a safe trigger cannot coexist, prohibit rollback to the old binary and use a patched rollback binary or forward fix. Do not claim rollback compatibility without an isolated SQL Server test that executes the old DELETE statement and proves invitation history survives.

Rollback also must not let the old acceptance implementation process project-scoped invitations using the compatibility `role` value or reactivate unrelated project memberships. A rollback binary must reject lifecycle-aware/project-targeted invitations or include the new acceptance semantics. An additive migration alone does not make the old behavior safe.

No production migration, deployment, commit, or push is authorized by this specification.

## 12. Stable API errors and final implementation gate

All new validation and conflict failures use `{ "code": "...", "message": "..." }`:

| HTTP | Code | Use |
|---|---|---|
| 400 | `INVITATION_REQUEST_INVALID` | Invalid role combinations, delivery method, email, or scope fields. |
| 400 | `INVALID_CURSOR` | Malformed or filter-mismatched history cursor. |
| 403 | `INVITATION_FORBIDDEN` | Actor lacks current organization/project invitation authority. |
| 404 | `ORGANIZATION_NOT_FOUND` / `PROJECT_NOT_FOUND` | Resource is absent or outside the authorized organization scope. |
| 409 | `INVITATION_ALREADY_PENDING` | Pending invitation already exists for the same organization/email/scope. |
| 409 | `PROJECT_MEMBER_ALREADY_ACTIVE` | Requested project membership is already active; no changes are made. |
| 409 | `ORGANIZATION_MEMBER_ALREADY_ACTIVE` | Organization-only acceptance targets an already active organization member. |
| 409 | `INVITATION_STATE_CONFLICT` | Attempt to transition a terminal invitation or lose a revoke/reissue race. |
| 409 | `INVITATION_EXPIRED` | Token expiry reached according to server time. |
| 409 | `INVITATION_SPONSOR_AUTHORITY_CHANGED` | Creator no longer has permission to grant the requested membership. |
| 409 | `INVITATION_REISSUE_REQUIRED` | Legacy pending invitation has no attributable creator. |
| 409 | `INVITATION_MEMBERSHIP_CONFLICT` | Concurrent membership operation or uniqueness conflict. |
| 502 | `INVITATION_DELIVERY_FAILED` | Email delivery failed after invitation commit; response includes the authorized caller's non-secret `invitationId` only (no token, token hash, or link). Recovery uses explicit reissue, which supersedes the old pending invitation and creates a new token/link; same-link delivery retry is not supported by the hash-only token design. |

The product-owner decisions on project invitation authority, active-project-member conflict behavior, immutable actor attribution, link handling, legacy response compatibility, paginated history, and 12-month retention are finalized. The proposed 11-file boundary in Section 9 is conditionally approved; any expansion requires review before work begins.

Implementation remains unauthorized until a separate explicit approval. Before implementation, resolve the migration executor/ledger path and 006 omission, inspect the existing SQL Server table-trigger definitions, verify legacy DELETE compatibility and rollback acceptance behavior against an isolated database, and confirm the conditional runner-file boundary. Slice B/C remain separate.
