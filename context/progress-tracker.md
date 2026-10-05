# Progress tracker

## 2026-10-05

- Verified the admin activity UI matches the compact platform pattern in [apps/web/src/AdminPlatform.tsx](../apps/web/src/AdminPlatform.tsx): compact header, filter bar, range selector, and purple category pills.
- Verified the activity query logic clamps date bounds to valid values and rejects future or >366-day ranges.
- Verified the web build succeeds with `npm.cmd run build --prefix apps/web`.
- Known limitation: the live deployed API must be using the latest backend for the remote site; if the hosted API is older, its database migration status and validation logic can still differ from local verification.
- Fixed platform activity requests to omit the upper bound for live ranges and for custom ranges ending today, avoiding API rejection caused by client/server clock skew. Future custom dates are blocked in the UI.
- Added platform activity records for registration, sign-in challenge/success, and failed login/OTP attempts. Platform events omit tenant scope, avoid recording email addresses or OTP values, and are shown only in the SuperAdmin feed.
- Added migration `004_platform_auth_activity.sql` and included migrations 001-004 in the local SQL Server setup script. API and web builds passed; the PowerShell setup script parses successfully. The production database still needs migration 004 applied before auth events can be written there.
- Declared `Gemini__ApiKey` (secret) and `Gemini__Model` in the Render Blueprint. The production API still requires the real Gemini key to be entered in Render and redeployed; task suggestions return 503 until configured or if Gemini rejects the key/model/quota.
