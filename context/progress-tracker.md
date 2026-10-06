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
- Replaced mojibake ellipses and em dash in `apps/web/src/main.tsx`; verified the web source has no remaining `â` sequences and the production build passes.
- Aligned Flutter login, registration, and OTP presentation/copy with the web auth flow. Auth file diagnostics are clear; widget test and Chrome launch remain blocked by unrelated existing task-detail compile errors, including a missing `edit_task_screen.dart`.
- Added the TaskFlow brand mark to the mobile auth screen using a dedicated SVG asset and brand-aligned purple treatment in `apps/mobile/lib/src/screens/auth_screen.dart`.
- Replaced the hand-built web mark with the supplied Figma `Primary lockup.svg` and `Mobile launcher.svg` assets across landing, auth/admin/workspace surfaces, development email preview, and favicon; `npm.cmd run build --prefix apps/web` passes (with the existing large-chunk warning).

## 2026-10-06

- Set the Android app launcher display name to TaskFlow and replaced the Flutter starter icon with a TaskFlow adaptive icon plus density-specific legacy icons. Android debug APK build verification passed; iOS runner metadata is not present in the checked-in mobile project.
- Restored the missing mobile `EditTaskScreen` using the existing `Task` model, Provider `AppState`, task status/priority options, project members, and server-side PATCH contract. Editing supports task fields and explicit date clearing.
- Standardized task detail access on Provider and removed unsupported `state:` arguments from board/dashboard callers. Task lookup uses cached data first, then authenticated task lists for known projects; the backend has no item-level GET task endpoint.
- Added `AppState.updateTask()` and backend-backed `deleteTask()`. Corrected create/update client methods to match the backend's ID-only/no-content responses, and added `ApiClient.suggestTask()` for the existing authenticated `POST /api/v1/ai/tasks/suggest` endpoint and `AiTaskSuggestion` DTO.
- Added API contract tests for AI suggestion parsing and date-clearing PATCH requests; `flutter pub get`, `dart format lib`, `flutter analyze`, `flutter test`, and `flutter build apk --debug` all completed successfully. The APK build still emits the existing Java native-access and AGP 8.11.1 warnings; Android Gradle configuration was not changed.
