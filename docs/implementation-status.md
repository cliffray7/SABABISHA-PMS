# Implementation Status

This repository is aligned to the web, backend, QA, and DevOps portions of the GTP 2026 recommendations. The Flutter mobile application is intentionally deferred and `apps/mobile` remains unchanged.

## Implemented

- .NET 8 ASP.NET Core Web API.
- EF Core 8 with SQL Server 2022 as the primary database.
- Dapper 2.x dashboard metrics repository calling `usp_GetDashboardMetrics`.
- HotChocolate GraphQL 14.3 with authenticated schema access.
- React 18.3, Vite 5, Material UI 6, Axios, Apollo Client, and TanStack Query.
- SQL Server schema, indexes, seed data, task-assignment and dashboard procedures.
- Postman collection and Newman-compatible environment.
- Docker Compose services for SQL Server, API, and web frontend.
- GitHub Actions build, test, frontend build, and coverage collection workflow.

## Deliberate decisions

- SQL Server 2022 is the Week 2 primary database. PostgreSQL is not added as an untested second provider.
- Vercel/Azure/Railway/Render credentials and project-specific deployment configuration belong in deployment environments; the repository provides container artifacts suitable for those platforms.
- Mobile implementation is deferred by request.

## Remaining project work

- Replace placeholder unit and integration tests with business-rule and database tests.
- Configure a real SQL Server integration service in CI and enforce the 80% coverage threshold after the test suite has meaningful coverage.
- Add the team's Figma, HackerRank, Jira, DBeaver, and UAT evidence to the project documentation.