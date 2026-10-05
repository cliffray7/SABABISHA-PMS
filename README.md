# Sababisha PMS

Sababisha PMS is a project management system with an ASP.NET Core API, a React web client, and a Flutter mobile client. The main workflows cover account access, organizations and teams, projects, tasks, collaboration, notifications, and platform administration.

## Current implementation

- **API:** .NET 8 / ASP.NET Core, EF Core and SQL Server. REST endpoints are under `/api/v1`; GraphQL is exposed at `/graphql`.
- **Web:** React and Vite client in `apps/web`. It includes sign-in and registration with email OTP, organization and invitation management, project and member management, board/list/timeline task views, comments, mentions, attachments, notifications, account settings, and admin pages.
- **Mobile:** Flutter client in `apps/mobile`. It includes authentication, OTP verification, secure session storage and refresh, organization/project/task workflows, comments, subtasks, attachments, notifications, account settings, and admin screens. The mobile README has setup details.
- **Tests:** Web API/browser/team/notification/attachment smoke scripts, Flutter widget and API-client tests, .NET test projects, and Postman API requests are present. The .NET unit and integration test projects currently contain starter tests; the presence of test projects does not imply broad automated coverage.

The web and mobile clients use the same API. External services such as Brevo email and Gemini task drafting require API-side configuration. Local development can use the Development inbox for reset and invitation messages when real email is not configured.

## Repository layout

```text
src/                         .NET API, application, domain, infrastructure
apps/web/                    React + Vite web client and smoke scripts
apps/mobile/                 Flutter mobile client
database/sqlserver/          SQL Server schema, seed data, procedures, indexes
tests/                       .NET and Postman test projects
infrastructure/docker/       Docker Compose and container definitions
scripts/                     Local database setup helpers
docs/                        Implementation and deployment notes
```

## Run locally

### Prerequisites

- .NET 8 SDK
- Docker Desktop with Compose, or a reachable SQL Server 2022 instance
- Node.js 20 and npm 10 for the web client
- Flutter SDK 3.x for the mobile client

### Start API and SQL Server

From the repository root, create the Docker environment file and set a strong local SQL Server password:

```powershell
Copy-Item infrastructure/docker/.env.example infrastructure/docker/.env
# Edit infrastructure/docker/.env and set MSSQL_SA_PASSWORD
docker compose --env-file infrastructure/docker/.env -f infrastructure/docker/docker-compose.yml up --build
```

Compose publishes the API at `http://localhost:5141` and SQL Server at port `1433`. The API readiness endpoint is `http://localhost:5141/api/v1/ready`.

To run only the API outside Docker, start SQL Server first and run:

```powershell
dotnet run --project src/Pms.Api/Pms.Api.csproj --urls http://localhost:5141
```

The API reads its local database and JWT configuration from `appsettings.json`; environment variables such as `ConnectionStrings__PmsDatabase` and `Jwt__SigningKey` can override those values.

To send local development email to a real mailbox, copy `src/Pms.Api/.env.local.example` to an ignored local file and set `Brevo__ApiKey` to your Brevo API key and `Brevo__From` to a sender address verified in Brevo. Supply these values to the API process environment before starting it; ASP.NET Core does not load `.env` files automatically. For example, in PowerShell:

```powershell
$env:Brevo__ApiKey = 'your-brevo-api-key'
$env:Brevo__From = 'verified-sender@example.com'
$env:Brevo__FromName = 'TaskFlow'
dotnet run --project src/Pms.Api/Pms.Api.csproj --urls http://localhost:5141
```

When Brevo settings are absent in Development, messages are stored in the TaskFlow Development inbox instead of being sent externally. Keep production credentials in the API host environment.

Database changes are applied explicitly; the API does not auto-run SQL scripts. Before deploying this revision, apply `database/sqlserver/migrations/003_activity_events.sql` to the database used by the API. This creates the tenant-scoped workspace Activity Center store; it is separate from `002_admin_audit_events.sql` and does not backfill historical events.

### Start the web client

If using the Docker Compose web service, open `http://localhost:5173`. To run Vite directly:

```powershell
cd apps/web
npm ci
npm run dev -- --host 127.0.0.1
```

Open `http://127.0.0.1:5173`. Register and verify an account, create an organization, then create a project and tasks. Local reset and invitation email can be viewed in the Development inbox when the API is running in Development without an email provider configured.

### Run the mobile client

```powershell
cd apps/mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5141/api/v1
```

The URL above is for an Android emulator. For an iOS simulator use `http://127.0.0.1:5141/api/v1`; for a physical device use the development machine's LAN address. See [mobile setup and feature notes](apps/mobile/README.md).

## API and application behavior

- Protected API endpoints use bearer access tokens. The clients refresh a session after an authorization failure and retry the request once.
- Organization and project routes enforce membership and role checks.
- Tasks support multiple assignees, dates, priorities, status changes, comments, mentions, subtasks, and attachments. Web uploads are limited to 10 MB; files are stored by the API and downloaded through authenticated routes.
- Organization invitations require the invited email to accept and expire after seven days. OTP codes expire after ten minutes and are single-use.
- `GET /api/v1/live` checks that the API process is running; `GET /api/v1/ready` checks database readiness; `GET /api/v1/health` returns application health.
- Optional AI task suggestions use `POST /api/v1/ai/tasks/suggest`; suggestions are reviewed by the user and are not saved as tasks automatically. Configure `Gemini__ApiKey` on the API host to enable this feature.
- Email delivery can be configured with Brevo API settings on the API host. Without delivery settings in Development, supported messages are placed in the loopback-only in-memory Development inbox.

For deployment configuration see [deployment notes](docs/deployment-vercel-railway-render.md). The API exposes `/graphql` for GraphQL clients; the web and mobile workflows primarily use REST.

## Verification

Run the web build and configured smoke checks from `apps/web`:

```powershell
npm run build
npm run test:api
npm run test:browser
npm run test:team
npm run test:notifications
npm run test:attachments
```

The smoke checks require a running API and local development database. The browser check uses installed Microsoft Edge through `playwright-core`. Review the scripts before running them against any database containing data you need to keep; cleanup is intended for the local development database.

Run Flutter checks from `apps/mobile`:

```powershell
flutter analyze
flutter test
```

Run the .NET solution checks from the repository root:

```powershell
dotnet build Sababisha.Pms.slnx
dotnet test Sababisha.Pms.slnx
```

## Further documentation

- [Implementation status and technology decisions](docs/implementation-status.md)
- [Deployment notes](docs/deployment-vercel-railway-render.md)
- [Mobile development](docs/mobile-development.md)
