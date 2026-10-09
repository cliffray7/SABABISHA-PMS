# Security and notification follow-ups

These are tracked separately from the completed Slice 1 work. Neither item authorizes implementation, and neither is part of Slice 2.

## SEC-01 — Enforce suspended-account status on workspace requests

- **Status:** Open; separate owner authorization required
- **Priority:** Security follow-up before production deployment of the new functionality
- **Finding:** `WorkspaceAuthorization.CanAccessProjectAsync` checks active project and organization memberships but does not check `User.Status`. Suspending a user revokes refresh tokens, but an already-issued access token can remain usable until expiry; while both memberships remain active, project reads may still pass.
- **Required review before implementation:** Trace authentication and JWT validation, refresh-token revocation, active sessions, and administrative access. Define whether account status is checked on every authenticated request, at workspace authorization boundaries, or through token revocation/versioning. Ensure SuperAdmin and other administrative access semantics remain intentional. Add tests for existing access tokens after suspension, refresh attempts, suspended organization/project members, and authorized administrative operations.
- **Scope boundary:** Do not treat frontend hiding or token expiry alone as the fix. Keep this as a separately approved security change; do not fold it into Slice 2.

## NOTIF-01 — Historical notification recipient eligibility

- **Status:** Deferred; no cleanup or migration authorized
- **Finding:** New assignment-derived comment and attachment notifications filter current assignees by eligibility, and the notification API filters `TASK_ASSIGNED` notifications while their recipient is ineligible. Older `COMMENT` and `ATTACHMENT` notifications do not record whether a recipient was selected as an assignee, mention, task creator, or uploader, so their provenance cannot be safely inferred.
- **Decision:** Preserve existing notification history. Do not guess recipient eligibility or delete existing rows. If product requirements call for selective historical filtering, design explicit recipient-reason metadata and migration behavior in a separate review.
- **Scope boundary:** Not part of Slice 2 and not authorization to redesign notifications.
