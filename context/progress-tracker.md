# Progress tracker

## 2026-10-05

- Verified the admin activity UI matches the compact platform pattern in [apps/web/src/AdminPlatform.tsx](../apps/web/src/AdminPlatform.tsx): compact header, filter bar, range selector, and purple category pills.
- Verified the activity query logic clamps date bounds to valid values and rejects future or >366-day ranges.
- Verified the web build succeeds with `npm.cmd run build --prefix apps/web`.
- Known limitation: the live deployed API must be using the latest backend for the remote site; if the hosted API is older, its database migration status and validation logic can still differ from local verification.
- Fixed platform activity requests to omit the upper bound for live ranges and for custom ranges ending today, avoiding API rejection caused by client/server clock skew. Future custom dates are blocked in the UI.
