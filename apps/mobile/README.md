# Sababisha PMS mobile

Flutter client for the Sababisha PMS API. The mobile app includes account access and the main project-management and administration screens; features depend on a reachable, configured API.

## Current features

- Registration, login, email OTP verification, forgot-password request, session restoration, secure token storage, refresh-and-retry, and logout.
- Organizations, organization members and invitations, project selection and management, and project membership.
- Project dashboard and board, list, and timeline task views, with search and priority filtering.
- Task create/edit, status and priority, assignees, comments, subtasks, and attachment upload/download.
- Notification list and read state, account settings, light/dark appearance, and super-admin screens for platform overview, analytics, users, organizations, projects, activity, health, and reports.

The mobile client communicates with the same REST API as the web client. Optional server features, such as email delivery and AI task suggestions, depend on API configuration. The repository includes Flutter widget and API-client tests; these are useful checks but do not constitute a full live-service integration suite.

## Requirements

- Flutter SDK with Dart `>=3.3.0 <4.0.0`
- Android Studio and an Android emulator/device, or Xcode and an iOS simulator/device
- A running Sababisha PMS API or a reachable deployed API

## Run

From this directory:

```powershell
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5141/api/v1
```

The default API URL is the deployed service configured in `lib/src/services/api_client.dart`. Pass `API_BASE_URL` explicitly to use a local instance or another environment.

| Target | Example API URL |
|---|---|
| Android emulator | `http://10.0.2.2:5141/api/v1` |
| iOS simulator | `http://127.0.0.1:5141/api/v1` |
| Physical device on local network | `http://192.168.1.20:5141/api/v1` (replace with the API host's LAN address) |
| Deployed API | `https://your-api-host/api/v1` |

The API host must be reachable from the target device. For local physical devices, allow the API port through the host firewall. Flutter mobile requests do not use browser CORS enforcement.

If platform files are missing, regenerate the required platform scaffolding from this directory:

```powershell
flutter create . --platforms=android,ios
```

## Authentication and session behavior

Registration and login return an OTP challenge. Enter the six-digit email code to verify the account and receive access and refresh tokens. Tokens are stored with `flutter_secure_storage`. On startup the app restores the account; protected API calls refresh once after a `401`, then retry the request. Logout attempts server-side refresh-token revocation and clears the local session even if the API request fails.

When running the API locally in Development without a configured email provider, use its Development inbox to retrieve OTP, reset, and invitation messages. The inbox is in-memory and only exposed to loopback requests on the API host, so it is not available directly from a phone. For testing OTP from a device, configure real email delivery or use a development setup that exposes an appropriate message flow.

## Checks

Run from this directory:

```powershell
flutter analyze
flutter test
```

The current tests cover basic widget construction and API-client behavior. They do not verify every screen or a complete session against a live backend.

## Related documentation

- [Repository setup and API overview](../../README.md)
- [Mobile development notes](../../docs/mobile-development.md)
- [Deployment notes](../../docs/deployment-vercel-railway-render.md)
