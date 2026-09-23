# Mobile Development — Sababisha PMS

Flutter client for the Sababisha PMS backend API. The app targets Android and iOS using a shared Dart codebase. It connects to the same `.NET 8` backend that serves the web frontend.

---

## Current state (Week 4 baseline)

Authentication is fully implemented. Every other screen is deferred and documented below as the planned feature set.

| Area | Status |
|---|---|
| Registration, login, email OTP verification | Done |
| Secure token persistence and session restore | Done |
| Refresh-token retry on `401` | Done |
| Logout (server-side token revocation + local clear) | Done |
| Organizations, projects, tasks, notifications | Planned |
| File attachments | Planned |
| AI task drafting | Planned |

---

## Repository location

```
apps/mobile/
├── lib/
│   ├── main.dart               # Entry point
│   └── src/
│       ├── app.dart            # Root widget, session restore, routing
│       ├── models/
│       │   └── auth_models.dart        # LoginChallenge, AuthSession, Account
│       └── services/
│           ├── api_client.dart         # HTTP layer, auth, token refresh
│           └── session_store.dart      # flutter_secure_storage wrapper
├── test/
│   ├── widget_test.dart
│   └── api_client_test.dart
└── pubspec.yaml
```

---

## Prerequisites

| Tool | Version |
|---|---|
| Flutter SDK | 3.x (Dart `>=3.3.0 <4.0.0`) |
| Android Studio / Xcode | Latest stable |
| Android emulator or physical device | API 21+ / iOS 12+ |
| Running Sababisha PMS API | `http://localhost:5141` |

---

## Getting started

```powershell
# 1. Install dependencies
cd apps/mobile
flutter pub get

# 2. Regenerate platform folders if they are missing
flutter create . --platforms=android,ios

# 3. Start an emulator or connect a device, then run
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5141/api/v1
```

`10.0.2.2` is the Android emulator alias for `localhost` on the host machine.
For a physical device substitute the LAN IP of the machine running the API:

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:5141/api/v1
```

The API does not enforce CORS on mobile clients, but ensure the machine firewall allows port `5141` when using a physical device.

---

## Environment and configuration

The API base URL is injected at compile time through `--dart-define`. The default value in `api_client.dart` is:

```
http://10.0.2.2:5141/api/v1
```

Override it for any target environment without modifying committed code:

| Environment | Command-line value |
|---|---|
| Android emulator | `http://10.0.2.2:5141/api/v1` |
| iOS simulator | `http://127.0.0.1:5141/api/v1` |
| Physical device (LAN) | `http://192.168.1.20:5141/api/v1` |
| Deployed API | `https://api.yourdomain.com/api/v1` |

---

## Dependencies

| Package | Version | Purpose |
|---|---|---|
| `flutter_secure_storage` | `^9.2.2` | Keychain/Keystore token storage |
| `http` | `^1.2.2` | HTTP client |
| `flutter_lints` | `^3.0.2` | Lint rules |

Add new dependencies to `pubspec.yaml` with exact or tightly bounded versions. Run `flutter pub get` after any change.

---

## Authentication flow

```
User opens app
  └─ SessionStore.read()
        ├─ No saved session → AuthPage (register / login)
        │     ├─ Register: POST /auth/register → email / password
        │     ├─ Login:    POST /auth/login    → email / password
        │     └─ OTP step: POST /auth/verify-otp → 6-digit code → tokens saved
        └─ Session found → ApiClient.account() → GET /account
              ├─ Success → HomePage
              └─ 401 (refresh fails) → SessionStore.clear() → AuthPage
```

On any `401` during a protected request, `ApiClient._authorized` calls `/auth/refresh` once, retries the original request, then clears the session and surfaces an error if the refresh itself fails.

---

## Planned feature set

### Organizations

- List organizations the signed-in user belongs to.
- Create an organization.
- Invite members by email (calls `POST /api/v1/organizations/{orgId}/invitations`).
- Display member list and roles.

### Projects

- List and search projects within the selected organization.
- Board, list, and timeline views (mirrors the web frontend).
- Create project with name, description, and member selection.
- Archive / restore a project.

### Tasks

- List tasks filtered by project, status, assignee, and priority.
- Create a task: title, description, status, priority, due date, multiple assignees.
- Edit and delete tasks with permission checks.
- Drag-to-reorder within a board column.
- Comments and @-mention support.

### Notifications

- Notification list with unread badge count.
- Mark individual or all notifications as read.
- Push deep-link from a notification into the relevant task.

### File attachments

- Upload a file (up to 10 MB) to a task from the device gallery or file picker.
- Download attachments through the authenticated endpoint, respecting project membership.

### AI task drafting (optional)

When the backend has `Gemini__ApiKey` configured, a "Draft with AI" button on the new-task form calls `POST /api/v1/ai/tasks/suggest`. The app displays the suggestion for review and pre-fills the form; it never submits automatically. If the endpoint returns `503`, the button is hidden.

---

## Routing plan

The app uses a simple named-route or go_router approach. Proposed top-level routes:

```
/               → redirect based on session
/auth           → AuthPage (register, login, OTP)
/home           → organization picker
/org/:orgId     → organization dashboard
/org/:orgId/projects → project list
/project/:projectId  → project board / list / timeline
/task/:taskId        → task detail, comments, attachments
/notifications       → notification list
/account             → account settings
```

---

## State management plan

The existing code uses `StatefulWidget` and `FutureBuilder` for simple auth state. For the full feature set, introduce a lightweight solution to avoid prop-drilling:

| Option | Rationale |
|---|---|
| **Riverpod 2.x** | Recommended. Compile-safe providers, no `BuildContext` dependency, good async support. |
| Provider | Simpler but less ergonomic for async/family providers. |
| Bloc/Cubit | Good for complex event-driven flows; heavier boilerplate for CRUD screens. |

Pair whichever solution is chosen with a repository layer (mirrors the backend pattern) so `ApiClient` calls are not scattered across widgets.

---

## Code organization target

```
lib/src/
├── models/               # Data classes (no business logic)
│   ├── auth_models.dart
│   ├── org_models.dart
│   ├── project_models.dart
│   ├── task_models.dart
│   └── notification_models.dart
├── services/
│   ├── api_client.dart       # HTTP transport + auth
│   └── session_store.dart    # Token persistence
├── repositories/             # Data access abstracted from widgets
│   ├── org_repository.dart
│   ├── project_repository.dart
│   ├── task_repository.dart
│   └── notification_repository.dart
├── screens/
│   ├── auth/
│   ├── home/
│   ├── organizations/
│   ├── projects/
│   ├── tasks/
│   └── notifications/
├── widgets/                  # Shared, reusable UI components
└── app.dart
```

---

## Testing

Run existing checks from `apps/mobile`:

```powershell
flutter analyze
flutter test
```

Test targets to add for the planned feature set:

- Unit tests for each repository method using a mock `ApiClient`.
- Widget tests for the task board and notification list.
- Integration test using `flutter_driver` or `integration_test` package against the local API, mirroring the web `test:browser` pattern.

---

## Build and release

### Android

```powershell
# Debug APK for testing
flutter build apk --debug --dart-define=API_BASE_URL=https://api.yourdomain.com/api/v1

# Release APK
flutter build apk --release --dart-define=API_BASE_URL=https://api.yourdomain.com/api/v1

# App Bundle for Play Store
flutter build appbundle --release --dart-define=API_BASE_URL=https://api.yourdomain.com/api/v1
```

Sign the release build by adding a `key.properties` file and configuring `android/app/build.gradle.kts`. Do not commit the keystore or `key.properties`.

### iOS

```powershell
flutter build ipa --release --dart-define=API_BASE_URL=https://api.yourdomain.com/api/v1
```

Requires Xcode on macOS and an Apple Developer account for distribution.

---

## Security notes

- Tokens are stored in the platform Keychain (iOS) and EncryptedSharedPreferences / Android Keystore (Android) via `flutter_secure_storage`. Do not log token values.
- The API base URL is baked in at compile time; do not use `--dart-define` to inject secrets. API keys such as `Gemini__ApiKey` live only on the server.
- The app communicates with the API over HTTPS in any non-development deployment. Ensure the release `API_BASE_URL` uses `https://`.
- Logout calls `POST /auth/logout` to revoke the refresh token server-side before clearing local storage.

---

## Known limitations

- The `android.incomplete-backup` directory is a leftover from an interrupted scaffold. It can be deleted once the `android/` folder has been verified working.
- Windows and web platform folders exist from the default `flutter create` scaffold. They are not a supported deployment target for this app; remove them if they cause confusion.
- There are no push notification integrations yet. The notification feature relies on polling `GET /api/v1/notifications`.
