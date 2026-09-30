# Project Overview

## 1. Product Name:
SABABISHA-PMS (TaskFlow)

Version: 1.0.0
Status: Active Development
Repository: SABABISHA-PMS

## 2. Problem Statement
What real-world problem does this system solve?
Provides a centralized, multi-tenant platform for organizations to manage projects and tasks efficiently, with built-in administrative controls and AI assistance.

## 3. Product Vision
What should this product eventually become?
A comprehensive Project Management System (PMS) that leverages AI to streamline task workflows, project tracking, and organizational productivity.

## 4. Target Users
- Super Admins (System-wide configuration, audit logging, and global user/org management)
- Organization Admins (Manage members and projects within their org)
- Users/Members (Create and complete tasks within projects)

## 5. User Roles

| Role          | Purpose                                  | Main Capabilities                                |
|---------------|------------------------------------------|--------------------------------------------------|
| SuperAdmin    | Platform oversight and configuration     | Manage all orgs, suspend users, view global analytics |
| OrgAdmin      | Organization-level management            | Manage users and projects for their org          |
| User          | Day-to-day project operations            | View projects, manage tasks                      |

## 6. Core User Journeys

### Registration
Visitor → Register/OTP → Create/join organization → Dashboard

### Project Workflow
Organization → Project → Task → Assignment → Work → Completion

## 7. Core Features
- Authentication (OTP/JWT)
- Multi-Tenant Organizations
- Project & Task Management
- SuperAdmin Dashboard & Analytics
- Administrative Audit Logging
- Tenant-scoped workspace Activity Center (separate from the administrative audit trail)
- AI-Assisted Workflows (Gemini)

## 8. Business Rules
- Data must be strictly isolated between organizations (tenants).
- Administrative actions (user suspension, deletion) must be securely audited.
- Refresh tokens can be revoked instantly; access tokens expire after 15 minutes.

## 9. In Scope
- Core backend APIs (.NET / Pms.Api)
- React Web App (`apps/web`)
- SuperAdmin console improvements (Phase 1 & 2)
- Strict server-side authorization

## 10. Out of Scope
- Time-limited support impersonation (unless explicitly built securely).
- Bypassing server authorization via frontend UI hiding.

## 11. Success Criteria
- Secure, isolated multi-tenant architecture.
- Full auditability for high-impact actions.
- Reliable separation of SuperAdmin, OrgAdmin, and User privileges.

## 12. Terminology
- **Organization**: A logical tenant grouping users and projects.
- **Project**: A collection of tasks within an organization.
- **Task**: An actionable item belonging to a project.
- **SuperAdmin**: Hardcoded platform administrators (defined in `Operations:AdminUserIds`).
