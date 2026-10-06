# Architecture Context

## 1. Architecture Summary
Architecture style: Modular Monolith / Clean Architecture
Deployment model: Backend hosted on Render (or similar Cloud Provider), Frontend on Vercel, Database on Managed SQL Server.
Tenancy model: Multi-tenant (Organization-based logical isolation via Tenant ID columns).

## 2. Technology Stack

| Layer | Technology | Responsibility |
|------|------------|----------------|
| Web (Frontend) | React + Vite (TypeScript) | User Interface (TaskFlow PMS) |
| Backend API | ASP.NET Core (C#) | Business Logic & REST APIs (`Pms.Api`) |
| Database | Microsoft SQL Server | Relational Data Persistence |
| ORM | Entity Framework Core | Database Access and Migrations |
| Authentication | JWT (JSON Web Tokens) | Auth & Authorization |
| AI Integrations | Google Gemini 1.5 Flash | AI Task Assistance / Automation |
| Email Service | Brevo | Transactional Emails |

## 3. System Architecture

Workspace real-time updates: `Pms.Api` exposes an authenticated `/hubs/workspace` SignalR hub. Clients invoke `JoinOrganization` or `JoinProject`; the hub verifies active organization/project membership server-side before joining groups. Mutations publish area-only change notifications after persistence, and clients reload authoritative data through existing authenticated REST endpoints. The web app reconnects automatically and refreshes on focus/online. Flutter reconnects, refreshes workspace data on events, and uses a 20-second REST polling fallback while disconnected. Platform-wide SuperAdmin feeds continue to use their existing query refresh intervals.

Browser (React/Vite)
       ↓  (REST / HTTPS)
  API Controllers (`Pms.Api`)
       ↓
  Application Layer (CQRS/MediatR or Service classes)
       ↓
  Domain Layer (Entities: Users, Organizations, Projects, Tasks)
       ↓
Infrastructure (EF Core `PmsDb`, Brevo Client, Gemini Client)
       ↓
  SQL Server Database

## 4. Repository Structure
/apps
  /web            (React Frontend - Vite)
/src
  /Pms.Api        (ASP.NET Core Web API host)
/database
  /sqlserver      (SQL Migration Scripts, e.g., `002_admin_audit_events.sql`)
/docs             (Documentation, Roadmaps)
/context          (AI Context Files)

## 5. Backend Architecture (`Pms.Api`)

### API Layer
Responsibilities: Route requests, validate JWTs, enforce policy-based authorization (e.g., `SuperAdmin`), return standard HTTP JSON responses.

### Application & Domain Layer
Responsibilities: Core business entities (Organizations, Projects, Tasks, Users, AuditEvents).

### Infrastructure Layer
Responsibilities: Entity Framework Core `DbContext`, external integrations (Brevo for email, Gemini for AI).

## 6. Frontend Architecture (`apps/web`)
Build Tool: Vite
Deployment: Vercel (`https://taskflow-pms.vercel.app`)
Admin Dashboard components: `AdminDashboard.tsx`, `AdminAnalytics.tsx`, `AdminManagement.tsx`, `AdminPlatform.tsx`, `AdminReports.tsx`, `AdminNav.tsx`.

## 7. Database Architecture
Main entities: Organization, User, Project, Task, AdminAuditEvent, ActivityEvent.
Relationships: Users belong to Organizations. Projects belong to Organizations. Tasks belong to Projects.
Migration strategy: EF Core Migrations or raw SQL scripts (`database/sqlserver/migrations/`).
Audit Trail: `002_admin_audit_events.sql` implements an append-only administrative audit log.
Activity events are organization-scoped for workspace activity and may be platform-scoped for authentication events; platform events have no organization and are visible only in the SuperAdmin activity feed.

## 8. Authentication
Login: Custom Credentials / OTP.
Token strategy: Short-lived access token (15 mins), long-lived refresh token (30 days).
Revocation: Refresh credentials and unused login codes can be atomically revoked. Active JWTs remain valid until their 15-minute expiry.

## 9. Authorization
Policies: 
- `SuperAdmin` policy checks `Operations:AdminUserIds` configured in `appsettings.json`.
Server-Side Enforcement: Hiding frontend buttons is NOT security. All privileged actions (e.g., user suspension, project archival) are enforced on the server.

## 10. Multi-Tenancy
How tenants are identified: Organizations group Users, Projects, and Tasks.
How cross-tenant access is prevented: API routes and database queries must validate that the requested Project/Task belongs to the user's Organization.

## 11. External Services

| Service | Purpose | Failure Strategy |
|---------|---------|------------------|
| Brevo | Sending emails/OTP | Log failure, notify user |
| Gemini API | AI capabilities | Graceful degradation if AI is down |
| Cloudinary | Profile pictures and new task attachments | Server-side signed uploads; authenticated API download proxy; uploads and media purge require configured credentials |

New profile images and task attachments are stored in Cloudinary; older local-disk attachments remain downloadable through the legacy path. Cloudinary credentials are API-host secrets and are never sent to clients. Soft-deleted projects, tasks, comments, and attachments remain recoverable for 30 days, after which the hosted purge worker deletes their records and associated Cloudinary assets. Project archiving remains separate and has no automatic retention purge.

## 12. Security & Operational Boundaries
- Client is untrusted.
- Server authorization is the ultimate source of truth.
- Secrets (Brevo keys, Gemini keys, JWT signing keys) remain server-side in configuration/environment variables.
- Append-only audit logs track high-risk actions (suspensions, deletions).

## 13. Architectural Invariants
These rules MUST NEVER be violated:
- **Authorization must be enforced server-side.** Hiding a UI element does not replace a backend policy check.
- **Tenant data must remain isolated.** Users cannot access Projects or Tasks outside their Organization.
- **Do not expose API keys** or database credentials to the browser/frontend code.
- **Administrative actions must be logged** to the append-only audit trail once the capability is deployed.
- **Do not generate mock success states** for endpoints that are absent or denied.

