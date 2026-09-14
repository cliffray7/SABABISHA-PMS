# Sababisha PMS

Project management system organized for the GTP 2026 Bootcamp. This repository is currently structured for the backend, web, QA, and DevOps portions of the programme. The Flutter mobile application is intentionally deferred.

## Week 2 technology decisions

- Backend: .NET 8 LTS and ASP.NET Core Web API.
- ORM and data access: Entity Framework Core 8 for schema/migrations and Dapper 2.x for optimized reads and stored procedures
- Primary database: SQL Server 2022
- API styles: versioned REST under `/api/v1` and HotChocolate GraphQL 14+
- Testing: xUnit-ready test projects, Postman collection, Newman-compatible environment, and CI coverage collection

See [docs/implementation-status.md](docs/implementation-status.md) for the current recommendation alignment and deliberate technology decisions.

The original sequence diagram labels PostgreSQL. The bootcamp addendum requires SQL Server implementation in Week 2, so SQL Server is the primary database here. PostgreSQL can be added later as an explicit alternative; it is not silently mixed into the Week 2 implementation.

## Repository structure

```text
SABABISHA-PMS/
├── src/
│   ├── Pms.Api/                         # ASP.NET Core entry point
│   │   ├── Controllers/Rest/V1/         # REST endpoints: auth, orgs, projects, tasks
│   │   ├── GraphQL/Queries/              # Read operations
│   │   ├── GraphQL/Mutations/            # Write operations
│   │   └── GraphQL/Types/                # HotChocolate schema types
│   ├── Pms.Application/                  # Use cases, commands, queries, DTOs, validators
│   │   └── Features/                     # Auth, organizations, projects, tasks, collaboration
│   ├── Pms.Domain/                       # Business model independent of infrastructure
│   │   ├── Entities/                     # ERD entities
│   │   ├── Enums/                        # Roles, statuses, priorities, notification types
│   │   └── Interfaces/                   # Repository and service contracts
│   └── Pms.Infrastructure/               # External systems and persistence
│       ├── Persistence/EfCore/           # DbContext, configurations, migrations
│       ├── Persistence/Dapper/           # Repositories and optimized SQL queries
│       └── Services/                     # Authentication, files, notifications
├── database/
│   └── sqlserver/
│       ├── schema/                       # SQL Server tables and constraints
│       ├── stored-procedures/            # Task creation, dashboard, bulk operations
│       ├── indexes/                      # Query-performance indexes
│       └── seed/                         # Development/reference data
├── tests/
│   ├── Pms.UnitTests/                    # Domain and application business rules
│   ├── Pms.IntegrationTests/             # EF Core, Dapper, and SQL Server integration
│   └── Pms.ApiTests/                     # Contract/API tests
│       ├── postman/                      # Collections and environments
│       └── newman/                       # CLI execution scripts and reports
├── apps/
│   ├── web/                              # Week 3 React + Vite frontend
│   └── mobile/                           # Week 4 Flutter application
├── infrastructure/
│   ├── docker/                           # SQL Server and API containers
│   ├── ci/                               # GitHub Actions workflows
│   └── deployment/                       # Vercel/Azure/Railway/Render configuration
├── docs/week-2/                          # API, database, and implementation notes
└── scripts/                              # Database and local development scripts
```

## ERD ownership

| ERD entities | Owning area |
|---|---|
| `users`, `refresh_tokens` | `Pms.Domain/Entities`, `Pms.Application/Features/Auth` |
| `organizations`, `organization_members`, `organization_invitations` | `Pms.Application/Features/Organizations` |
| `projects`, `project_members` | `Pms.Application/Features/Projects` |
| `task_statuses`, `tasks`, `task_assignees` | `Pms.Application/Features/Tasks` |
| `comments`, `comment_mentions`, `attachments` | `Pms.Application/Features/Collaboration` |
| `notifications` | `Pms.Application/Features/Notifications` |
| Tables, keys, indexes, and procedures | `database/sqlserver` and `Pms.Infrastructure/Persistence` |

## Week 2 implementation order

1. Create the .NET solution and projects under `src/` and `tests/`.
2. Model the MVP ERD in `Pms.Domain/Entities` and configure EF Core mappings.
3. Implement SQL Server schema, foreign keys, constraints, indexes, and seed data.
4. Add stored procedures for task creation with multiple assignees, dashboard metrics, and high-value queries.
5. Add Dapper repositories for optimized reads and bulk operations.
6. Expose `/api/v1` REST controllers and the HotChocolate GraphQL schema.
7. Add Postman/Newman coverage for authentication, authorization, task assignment, validation, and error responses.

## API boundary

REST controllers belong in `src/Pms.Api/Controllers/Rest/V1`, while GraphQL resolvers belong in `src/Pms.Api/GraphQL`. Business rules stay in `Pms.Application`; neither transport layer should access SQL Server directly. EF Core and Dapper access is isolated in `Pms.Infrastructure`.

## Implemented backend endpoints

- `POST /api/v1/auth/register`, `/login`, and `/refresh`
- `POST /api/v1/organizations`, organization member listing, and role updates
- `POST /api/v1/projects`, project member management, and project lookup
- `POST /api/v1/projects/{projectId}/tasks`
- `GET /api/v1/tasks?projectId={projectId}`
- `PATCH` and `DELETE /api/v1/tasks/{taskId}`
- `POST` and `GET /api/v1/tasks/{taskId}/comments`, including replies and mentions
- `POST /api/v1/tasks/{taskId}/attachments`
- `GET /api/v1/notifications` and `PATCH /api/v1/notifications/{notificationId}/read`
- `GET /api/v1/health`, `/live`, and `/ready`; and `POST /graphql`

All non-authentication routes require a bearer access token and enforce organization/project membership. Replace the development JWT signing key and SQL Server password in environment-specific configuration before deployment.

## Operational checks and request tracing

- `GET /api/v1/live` confirms that the API process is running.
- `GET /api/v1/ready` confirms that the API can reach SQL Server.
- `GET /api/v1/health` retains the simple application status response used by local tooling.
- API logs are emitted as structured JSON. Every response includes an `X-Correlation-ID`; clients may send one to trace a request across their own logs.
- Authentication endpoints use a per-IP sliding-window limit of 30 requests per minute. A `429` response means the caller should wait and retry.

## Start SQL Server locally

Docker Desktop is required. From the repository root:

```powershell
Copy-Item infrastructure/docker/.env.example infrastructure/docker/.env
# Edit infrastructure/docker/.env and set a strong MSSQL_SA_PASSWORD
./scripts/setup-sqlserver.ps1
```

Then start the API:

```powershell
dotnet run --project src/Pms.Api/Pms.Api.csproj --urls http://localhost:5141
```

The API reads the `ConnectionStrings__PmsDatabase` environment variable when supplied, so local or deployment secrets can override `appsettings.json` without editing committed files.

## Functional web application

The React app now uses saved API data for organizations, projects, tasks, members,
notifications, and account settings. The supplied remaining-screen reference is
implemented as the reset-password screen and the create-project dialog, with shared
form, button, badge, and task-card styling.

Start the database and API from the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\setup-sqlserver.ps1
dotnet run --project src/Pms.Api/Pms.Api.csproj --urls http://localhost:5141
```

Start the frontend in another terminal:

```powershell
cd apps/web
npm run dev -- --host 127.0.0.1
```

Open http://127.0.0.1:5173. Register an account, create an organization, then create
a project. Add teammates using organization invitations and project membership.
Projects have board, list, and dated timeline views. Tasks support status changes
by dragging or editing, multiple assignees, comments, mentions, and file uploads
up to 10 MB. Project deletion in the UI archives the project and preserves data.
Successful file uploads notify the task creator and active assignees who remain
active project members, excluding the uploader. Attachment notifications open the
task so recipients can download the file. Rejected uploads create no notifications.

### Local email and password reset

Registration and login both require email OTP verification before issuing access
and refresh tokens. Submit the six-digit code to `POST /api/v1/auth/verify-otp`.
Codes expire after 10 minutes, are single-use, and are invalidated after five
incorrect attempts. If registration verification is interrupted or email delivery
fails, log in with the registered credentials to request a fresh code.

When the API runs in Development without `Smtp:Host`, reset links and invitations
appear in **Development inbox**. This inbox is only served to loopback requests;
it is not real email delivery. Its messages are held in memory until API restart.
Reset tokens are stored hashed in SQL Server, expire after 30 minutes, and can be
used once. Invitation links expire after seven days and require the invited email
address to accept them. Resetting a password revokes refresh tokens; existing
access tokens expire according to the configured JWT lifetime.

To use SMTP, configure `Smtp__Host`, `Smtp__Port` (default 587),
`Smtp__EnableSsl` (default true), `Smtp__From`, `Smtp__Username`, and
`Smtp__Password` in the API environment. Set `FrontendUrl` to the frontend origin
used for email links. The development inbox is disabled when SMTP is configured.
Uploaded files are stored under `src/Pms.Api/.data/uploads` and downloaded through
an authenticated endpoint that checks project membership.

### Frontend state and routing

The web app uses hash routes so it can be deployed as a static Vite build without server rewrite rules. Routes are checked before rendering: unauthenticated users see the sign-in flow, while expired sessions are cleared and returned to sign-in. Access tokens and refresh tokens are stored locally for the current browser and Axios attaches the access token automatically. On one `401` for a protected request, Axios refreshes the token, retries the request once, and signs out if refresh fails.

Local component state owns transient UI such as dialogs, selection, and the mobile menu. TanStack Query owns notification server state; the URL hash owns the current screen; and browser storage preserves the selected organization and project between reloads.

### Optional AI task drafting

`POST /api/v1/ai/tasks/suggest` returns a suggested title, description, priority, and subtasks for an authorized project. It never writes a task; the user must review and submit the normal task form. To enable it, set `Gemini__ApiKey` and `Gemini__Model` (recommended: `gemini-3.5-flash`) only in the API environment. Do not place an AI key in frontend variables or source control. If these settings are absent, the endpoint returns `503` and the normal task workflow remains available.

### Verification

With the API, SQL Server, and frontend running, execute from `apps/web`:

```powershell
npm run build
npm run test:api
npm run test:browser
npm run test:team
npm run test:notifications
npm run test:attachments
```

The browser test uses installed Microsoft Edge through `playwright-core`; it does
not download another browser. Tests create uniquely named local accounts and
organizations and clean up their records and attachments afterward. The cleanup
script uses the local API connection in `appsettings.json`, so run these tests only
against this local development database. Screenshots are saved to
`apps/web/test-results`.
