# Super Admin System Health and Observability

## Status

Phase 1 implementation and focused verification are complete locally. Phase 2A secure logging and OpenTelemetry foundation is implemented locally. The user reports successful local Grafana Cloud ingestion and querying for Prometheus, Loki, and Tempo; production ingestion remains unverified. Phase 2B now adds a SuperAdmin-only read proxy and Web telemetry overview. The API reports overall status as unknown when SQL connectivity succeeds because email/AI delivery and SignalR/jobs are not actively measured; database failure reports degraded. This specification distinguishes current health signals from telemetry query results.

## Product intent

Give Super Admins an accurate view of which TaskFlow services are reachable or configured. Activity feeds remain user-action history; this page reports system signals. All checks are read-only and platform-wide.

## Phase 1 contract

- Add an authenticated `GET /api/v1/admin/system-health`, protected by the existing `SuperAdmin` policy.
- Return the check timestamp, overall status, and named component results. Never return configuration values, credentials, provider response bodies, exception messages, tenant data, or task/user identifiers.
- Probe SQL Server only when the Super Admin explicitly refreshes the page. Do not automatically poll the database; Azure SQL serverless/free-tier use makes periodic probes an avoidable cost.
- Report API availability only as the API response itself. Report Brevo/Gemini configuration as configured or not configured, not as provider availability.
- Report SignalR and background processing as not instrumented unless an existing signal can establish their runtime health. Do not label registration/configuration as delivery or job success.
- Web and Flutter use the same endpoint and present unavailable or uninstrumented states plainly. Do not display sample incidents or synthetic metrics.
- The existing unauthenticated `/api/v1/live` and `/api/v1/ready` probes keep their deployment behavior and response contracts.

## Explicitly deferred

Historical incident management, affected-user counts, frontend/mobile crash reporting, provider delivery events, job run history, alerting, and Sentry remain deferred. Grafana Cloud has been selected for the current read-only telemetry overview; the read API stays optional and does not become an application dependency.

## Security and cost

- Enforce Super Admin authorization on the API, independently of client navigation.
- Do not call provider APIs, send emails, or invoke Gemini as a health probe.
- Execute the database check only on explicit refresh.
- Bound the database health check to 10 seconds. Web health requests time out after 15 seconds; Flutter requests use the API client's 20-second timeout. Clients show failure and keep explicit retry available.
- Do not expose secrets or internal exception details.
- Grafana query access is server-side only. Use a distinct read-only access policy token with `metrics:read`, `logs:read`, and `traces:read`; never reuse the OTLP write token unless it independently has only the required read scopes.
- Query URLs, datasource user IDs, and the read token are server configuration. Require HTTPS endpoints and never return upstream error bodies or authorization details.
- Expose only fixed TaskFlow API queries, 15-minute/1-hour/6-hour/24-hour windows, at most 50 sanitized log summaries and 20 trace summaries. The API does not accept arbitrary PromQL, LogQL, TraceQL, upstream URLs, or tenant identifiers.
- Grafana configuration absence, query failure, and an empty result are distinct statuses. Telemetry status does not change the independent live health checks.

## Acceptance

- Non-Super-Admin callers cannot access the system-health endpoint.
- Super Admin receives API, database, email configuration, AI configuration, realtime observability, and background-job observability states.
- Database unavailable is distinguishable from an API health-page request failure.
- Missing provider configuration is distinguishable from provider connectivity, which is not tested in Phase 1.
- Web and Flutter display the same signal semantics and checked-at time.
- No fictional incident, chart, affected-user count, or provider uptime is shown.

## Phase 1 implementation checkpoint (2026-10-10)

- Added `GET /api/v1/admin/system-health` with the existing SuperAdmin policy.
- Updated Web and Flutter to consume its shared component contract.
- Removed periodic refresh from both clients; database connectivity is checked when the page loads or the administrator explicitly refreshes.
- API build passed with isolated output (normal output was locked by the running API); Web production build passed with existing SignalR annotation and bundle-size warnings.
- Flutter scoped analysis stalled after printing `Analyzing 3 items...`; it was stopped without a result. No tests were added or run in this checkpoint. `git diff --check` passed with line-ending notices.
- No migration, dependency, external telemetry provider, client crash SDK, or provider network probe was added.

## Phase 2B — Read-only Grafana overview (2026-10-12)

- Added SuperAdmin-only `GET /api/v1/admin/observability` with a fixed Grafana query allowlist, bounded range choices (15m/1h/6h/24h), eight-second upstream timeout, response limits, HTTPS-only datasource endpoints, and sanitized provider-failure states.
- Prometheus summary queries report request rate, 5xx rate/percentage, and p95 duration; Loki returns only sanitized timestamp/severity summaries; Tempo returns capped trace IDs, service name, start time, and duration. No raw log lines, upstream errors, task data, or Grafana credentials are returned.
- Web System Health now displays telemetry source status, metric summaries, sanitized log events, and trace summaries. Telemetry queries are manual/page-entry only and do not affect the existing health status.
- Server configuration keys: `Observability:Grafana:QueryToken`; per source, `Observability:Grafana:{Metrics|Logs|Traces}:Endpoint` and `...:User`. Use the datasource endpoint and user/instance ID from Grafana Cloud, and a separate read-only access policy token. For Render, set the matching double-underscore environment variable names as protected secrets/configuration.
- Focused backend tests passed 3/3. Web production build passed with existing SignalR annotation and >500 kB chunk warnings. The route-intercepted Web smoke passed with mocked telemetry states. A live Grafana read query remains pending because no separate read token or datasource query configuration was available in this implementation session; production monitoring is not verified.

## Phase 1 verification follow-up (2026-10-10)

- Added focused API tests for SuperAdmin policy metadata, the `unknown` overall state when only the database check passes, explicit configured/not-configured and uninstrumented statuses, and sanitized database failure output. A local SQL Server connection-refusal fixture also verifies `DatabaseHealthCheck` reports an unavailable result without throwing. `dotnet test tests/Pms.IntegrationTests/Pms.IntegrationTests.csproj --no-restore --configuration Release --filter FullyQualifiedName~AdminSystemHealthTests` passed 5/5.
- Added a Web smoke covering a timed-out request, an HTTP failure, explicit retry, and successful recovery. `npm.cmd run test:system-health` passed. The production build passed with the existing SignalR Rollup annotation and large-bundle warnings.
- Added Flutter parsing and AppState recovery coverage for timeout and HTTP failure, including stale status clearing. `flutter test test/admin_health_test.dart --reporter expanded` passed 2/2. Scoped analysis found no new issues; two existing unused-widget warnings remain in `admin_screen.dart` (`_RecentProjectRow`, `_HorizBar`).
- Database health is request-driven and has a 10-second check timeout. The Web call has a 15-second client timeout; Flutter uses the existing 20-second HTTP timeout. No SQL Server was contacted by the focused API tests.

## Phase 2A — Secure logging and OpenTelemetry foundation (2026-10-10)

- Added opt-in OTLP export for ASP.NET Core traces, built-in HTTP/runtime/server metrics, and warning/error logs. Export starts only when `Observability:Otlp:Enabled=true` and a valid endpoint is configured. Remote endpoints must use HTTPS; loopback HTTP is allowed for local testing. The application does not require the telemetry provider for startup or request processing.
- Traces use 5% ratio sampling by default, with a configurable finite ratio clamped to `[0,1]`. The trace and log batch queues are capped at 512 records, batches at 64, export timeouts at 5 seconds, and the metric export interval at 60 seconds. OTLP payloads are capped at 1 MiB. Queue overflow is allowed to drop telemetry rather than block application operations.
- Added export-time span redaction for raw URLs/paths/queries, authorization/cookie headers, SQL statements, exception messages, stack traces, and tag keys that look like credentials. Log export uses an allowlist of operational fields; rendered messages, raw log state, exception objects, and arbitrary attributes are removed before export. Correlation IDs, exception types, route templates, HTTP methods/status codes, and fixed email message kinds can remain.
- Removed sensitive existing log values: AppMail no longer logs recipients, subjects, links, OTPs, provider response bodies, or exception objects; SuperAdmin authorization no longer writes admin IDs or user claims to console; API request logs use route templates and correlation IDs rather than raw paths; Cloudinary/provider response bodies and selected exception messages/objects are no longer logged.
- The API overwrites inbound `X-Correlation-ID` with the active server trace ID (or a generated ID) and returns the same header. Exception traces record only the exception type; logs include the correlation ID and low-cardinality route template.
- Added `ObservabilityRedactionTests`: 5/5 focused tests passed, including an actual local OTLP/HTTP receiver accepting a synthetic exception event with a searchable correlation ID and no test secret/recipient. A refused local exporter did not throw into the application logging call. Full integration suite passed: 137 passed, 13 SQL Server tests skipped.
- Grafana Cloud ingestion was not independently verified at this checkpoint. No account credentials, deployment variables, collector service, dashboard, migration, or Error Explorer endpoint was added. Before enabling export, configure the Grafana OTLP endpoint and authorization header as deployment secrets, verify ingestion/retention/budget alerts in the account, and review historical Render logs separately; redaction only protects future logs.
- OTLP exporter endpoints are derived per signal from the configured base URL (`/v1/traces`, `/v1/metrics`, `/v1/logs`). This keeps the configured Grafana `/otlp` base path and avoids sending HTTP/protobuf exports to that base path without the required signal route.
- `dotnet list src/Pms.Api/Pms.Api.csproj package --vulnerable --include-transitive` reported one critical transitive package, `HotChocolate.Language` 14.3.0, from the existing HotChocolate dependency. No OpenTelemetry package was reported vulnerable. This unrelated dependency upgrade is not included in Phase 2A and should be reviewed separately.
- Remaining verification: this tests OTLP against a local receiver, not Grafana Cloud; an actual deployed HTTP authorization test for the Phase 1 health endpoint remains outstanding before deployment. Frontend/mobile crash reporting, historical incident grouping, tenant-level incident views, alerting, and Error Explorer remain Phase 2B/3 scope.

## Pre-release gate review (2026-10-12)

- Source inspection confirms `Observability:Otlp:Enabled` defaults to `false`; no Grafana endpoint or credentials are required when it is unset. This is source-level evidence only. The deployed Render environment still needs a configuration check before rollout.
- The critical HotChocolate parser advisory GHSA-qr3m-xw4c-jqw3 / CVE-2026-40324 applies to the resolved `HotChocolate.Language` 14.3.0 package. Direct HotChocolate references are now set to 14.3.1, the patched 14.x release. NuGet restore and a fresh vulnerability scan remain unverified because the network request was denied; existing local assets/cache still contain 14.3.0 until a successful restore.
- The logging review removed organization, project, and task IDs from timezone and purge log messages. The remaining application-authored messages use generic descriptions, exception types, HTTP status/method/route template, correlation ID, or fixed email message kinds. Historical Render logs have not been reviewed and are not retroactively redacted.
- Full HTTP-pipeline authorization integration coverage remains outstanding. Current health tests inspect authorization metadata and controller behavior but do not exercise anonymous, tenant-admin, and Super Admin requests through the hosted authentication/authorization pipeline. The integration project has no cached ASP.NET Core test host package, and package restore was not authorized.
- The health/OTLP and logging edits have not been isolated into a release commit. No final build/test run occurred after the 14.3.1 reference and log-message edits. Do not merge or deploy until restore, the HTTP authorization test, and final scoped verification pass.

## OTLP signal endpoint correction (2026-10-12)

- Updated the three HTTP/protobuf exporters to derive their signal-specific endpoint from the configured base URL, producing `/v1/traces`, `/v1/metrics`, and `/v1/logs` under the existing base path. This addresses the reported Grafana 404s at the bare `/otlp` path while preserving endpoint configuration, authentication headers, sanitization, timeouts, and queue limits.
- The API compiled successfully using an isolated output directory because a running local API held the default output files open. The user subsequently reported successful local ingestion and query results for Prometheus, Loki, and Tempo. This agent did not independently query the user's Grafana Cloud account.

## Pre-release verification follow-up (2026-10-12)

- Added hosted HTTP authorization tests for both `/api/v1/admin/system-health` and `/api/v1/admin/observability`: anonymous requests receive 401, authenticated non-SuperAdmin requests receive 403, and a configured SuperAdmin receives 200. The tests use the real JWT bearer and authorization middleware with a stub health check and no external database calls. Focused result: 3/3 passed.
- Restored the test host dependency and ran `dotnet list src/Pms.Api/Pms.Api.csproj package --vulnerable --include-transitive`; the API has no vulnerable packages with the current NuGet sources. HotChocolate resolves to the patched 14.3.1 release.
- Full solution verification passed: UnitTests 1/1 and IntegrationTests 143/143 passed, with 13 opt-in SQL Server tests skipped because no SQL Server test connection was configured. Web production build passed with existing SignalR annotation and large-chunk warnings. `git diff --check` passed with LF/CRLF notices.
- Deployment is still not verified. Grafana read access requires a separate read token and the Metrics, Logs, and Traces datasource endpoint/user values in the API host environment. OTLP write remains a separate opt-in setting. Do not call Grafana queries production-verified until Render has these settings and the deployed endpoint has been tested.
