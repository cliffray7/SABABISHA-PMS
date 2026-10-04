# Progress Tracker

## 2026-09-30 â€” Compact Activity first screen

- Reduced the Activity header, toolbar, category tabs, and first timeline group spacing. Kept custom dates collapsed behind More filters so activity appears higher on the first screen.
- Verification: `npm.cmd run build` succeeded (TypeScript and Vite production build). Vite emitted its existing large-chunk warning. No tests were run.

## 2026-09-30 â€” Activity toolbar order

- Matched the toolbar to the requested order: Search activity, Organization, Date range, More filters, Refresh. Moved manual refresh out of the header, and removed the redundant Search field label so the placeholder stays uncluttered.
- Verification: `npm.cmd run build` succeeded (TypeScript and Vite production build). Vite emitted its existing large-chunk warning. No tests were run.

## 2026-09-30 â€” Activity Center timeline refinements

- Matched the platform Activity view to the requested timeline workflow: 30-second live polling indicator, debounced search, organization and date presets, expandable custom dates, All/Projects/Tasks/People/Collaboration/System tabs, and day-grouped events with local time, relative time, actor-first descriptions, and organization â†’ project â†’ entity breadcrumbs.
- Added the project name to the SuperAdmin activity response using an optional project join, preserving events when a project row is no longer available. No schema changes.
- Verification: API `dotnet build` succeeded with 0 warnings/errors using isolated output because the running API process locks normal output. Frontend `npm.cmd run build` succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. No tests or live database calls were run.

## 2026-09-30 â€” Activity organization filter overflow

- Set Activity search, organization, and date controls to MUI full-width mode; constrained input roots and added ellipsis for long selected organization names. Kept named responsive grid areas so filters reflow cleanly at tablet and mobile widths.
- Verification: `npm.cmd run build` succeeded (TypeScript and Vite production build). Vite emitted the existing large JavaScript chunk warning. No tests were run.

## 2026-09-30 â€” Activity filter sizing fix

- Fixed the SuperAdmin Activity filter row so the organization selector and both date controls receive explicit grid areas and full-width form controls. Added intermediate and mobile grid layouts to prevent labels and selected values from being clipped as the content width changes.
- Verification: `npm.cmd run build` succeeded (TypeScript and Vite production build). Vite emitted its existing large-chunk warning. No tests were run.

## 2026-09-30 â€” SuperAdmin Activity page visual polish

- Refined the Activity page presentation with a clearer platform timeline header, balanced responsive filter layout, icon-led category controls, readable event cards with actor/time context, and an empty state that explains filter results and offers a reset when needed.
- Added responsive and dark-theme styling using existing TaskFlow design tokens. No activity API, authorization, or database behavior changed.
- Verification: `npm.cmd run build` succeeded (TypeScript and Vite production build). Vite reported the existing large JavaScript chunk warning. No tests were run.

## 2026-09-30 â€” SuperAdmin Activity Center fix

- Replaced the SuperAdmin Activity page's old audit-feed query with a new server-side query over `ActivityEvents`, authorized through the existing `SuperAdmin` policy. Added optional organization, category, search, date, and cursor pagination filters; results remain newest-first and are limited to stored workspace activity events.
- Kept the old audit page intact under a distinct **Audit Trail** route and label, still reading `/api/v1/admin/audit-events`.
- The SuperAdmin Activity page now polls every 30 seconds and supports organization selection, category/search/date filters, event details, refresh, and paging. It requires migration 003 and does not backfill actions performed before the migration or include admin account changes that are only in the audit table.
- Verification: web `npm.cmd run build` succeeded (TypeScript and Vite; existing large-chunk warning). The sandbox denied the first Vite build access to the repository root; the approved broader-filesystem retry succeeded. API `dotnet build` succeeded with 0 warnings/errors using isolated output at `.verification/api` because the already-running local API process locks its normal output assembly. An initial build to the normal output failed only on that file lock. No tests or live database calls were run.

## 2026-09-30 â€” SuperAdmin Activity page

- Completed: connected Activity view to the existing protected audit endpoint with action/date filters, cursor pagination, refresh, and loading/empty/error states.
- Improved event details to show actor and target identifiers, outcome, optional reason, timestamp, and correlation ID. Date filters now include both selected calendar dates and invalid ranges are surfaced before querying.
- Backend and database contract unchanged. Existing coverage remains limited to successful user creation, suspension, and permanent deletion.
- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build). Vite emitted its existing large-chunk warning. Initial sandbox build attempt was blocked by parent-directory access; approved broader filesystem run completed successfully.
- Scope note: `context/feature-specs/` is absent in this checkout. The existing SuperAdmin roadmap and API contract proposal were used as the activity behavior reference.

## 2026-09-30 â€” Activity empty-state diagnosis

- Confirmed the page calls the audit endpoint; server code writes events only after successful user creation, suspension, and permanent deletion. No historical backfill exists.
- Updated the empty-state guidance to distinguish a truly empty audit feed from setup checks: verify the frontend API target and apply migration 002 to that API's database.
- Local repository inspection cannot determine the deployed API target, whether its migration is applied, or whether its database contains events. No live API/database was queried or mutated.
- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. The sandboxed attempt was denied repository-root access, and the approved broader filesystem run completed successfully.

## 2026-09-30 â€” TypeScript baseUrl deprecation

- Removed deprecated `compilerOptions.baseUrl` from `apps/web/tsconfig.json`; retained the `@/*` alias paths mapping, which is resolved relative to the config.
- Verification: `npm.cmd run build` in `apps/web` succeeded with the existing TypeScript toolchain (TypeScript build and Vite production build); Vite emitted its existing large-chunk warning. The sandboxed Vite run was blocked from reading the repository root, while the approved broader filesystem run completed successfully. The alias also remains valid without `baseUrl` under the installed compiler.

## 2026-09-30 â€” Remove diamond from shared brand

- Removed the diamond mark from the shared signed-in TaskFlow brand component; retained the TaskFlow wordmark.
- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build). Vite emitted its existing large-chunk warning.

## 2026-09-30 â€” Tenant workspace Activity Center

- Added a distinct `ActivityEvent` entity/store, additive SQL migration 003, and authenticated `GET /api/v1/activity` with server-side active-organization and active-project membership filtering, search, category/date filters, bounded cursor pagination, and stable newest-first ordering.
- Successful existing project, task/subtask, assignment, comment/mention, attachment, organization membership, and invitation mutations queue activity in the same EF Core save as the business change. Event descriptions avoid comment bodies, attachment contents, credentials, and AI prompts.
- Added the workspace Activity page, polling every 30 seconds, category/search/date filters, event detail disclosure, navigation, and a five-event dashboard widget. Kept `/admin/activity` and `AdminAuditEvent` as the separate SuperAdmin audit trail.
- Added migration instructions to README and updated project, architecture, UI, and SuperAdmin roadmap context.
- Database migration 003 must be applied to the API database before deploying/using this feature. Existing activity is not backfilled. This first slice does not capture login/security failures, billing, AI operations, incidents, health/system operations, SuperAdmin-wide mutations, or every possible update field; it is not a claim that every system event is recorded. No SignalR exists, so the page uses polling.
- Verification: API project build succeeded with 0 warnings/errors using isolated output; web `npm.cmd run build` succeeded (existing large-chunk warning); `dotnet test Sababisha.Pms.slnx --no-restore` passed 1 unit and 1 integration test. Both current .NET tests are starter placeholders, so automated tenant-isolation and event-behavior coverage remains outstanding. No live database migration or data mutation was performed.
- Local runtime check (2026-09-30): web server on port 5173 and API live/readiness endpoints on port 5141 responded. The running API Swagger document lists the audit endpoint but not `/api/v1/activity`; direct request returns 404, so the running API is an older build and needs rebuilding/restarting. Readiness reports healthy but does not verify migration 003. No database mutation was attempted; Docker engine status was inaccessible in this session.
- Follow-up runtime check: `/api/v1/activity` is now registered in local Swagger; an unauthenticated request returns 401, which is expected for this protected endpoint. The pasted log contains successful admin project/analytics queries and HTTP 200, not an Activity or SQL failure. Migration 003's live database presence is still unverified.

## 2026-09-30 — Compact Activity toolbar

- Kept Search, Organization, Date range, More filters, and Refresh on a single compact row across desktop and typical tablet widths; moved the responsive two-row breakpoint to 900px and kept phone stacking.
- Updated the SuperAdmin Activity UI context to document toolbar behavior.
- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build). Vite emitted the existing large-chunk warning. The sandbox denied repository-root access on the first attempt; the approved broader-filesystem retry succeeded.

## 2026-09-30 — Activity toolbar cascade correction

- Corrected the toolbar grid selector specificity so the shared `.admin-activity-filters` flex rule no longer overrides the SuperAdmin Activity one-row grid.
- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. The sandbox again denied repository-root access initially; the approved broader-filesystem retry succeeded.

## 2026-09-30 — Activity typography and search styling

- Matched SuperAdmin Activity heading typography and filter control sizing, border, focus treatment, and muted search surface to the Organizations management page.
- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. The sandbox denied repository-root access initially; the approved broader-filesystem retry succeeded.

## 2026-09-30 — Audit Trail presentation alignment

- Matched Audit Trail page heading and refresh action typography to the Organizations management page and rebuilt its filters as a responsive compact toolbar with consistent field heights, muted surfaces, and focus styles.
- Kept audit actions, date bounds, page size, endpoint, and access rules unchanged.
- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. The sandbox denied repository-root access initially; the approved broader-filesystem retry succeeded.

## 2026-09-30 — Activity and Audit field text alignment

- Vertically centered input, select, date, and search adornment contents inside the shared 40px Activity and Audit filter fields.
- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. The sandbox denied repository-root access initially; the approved broader-filesystem retry succeeded.

## 2026-09-30 — Activity search coverage

- Expanded tenant and SuperAdmin Activity search to include entity type and status, and exact GUID matches for event, actor, entity, project, and (for the platform view) organization IDs. Existing authorization scopes are applied before results are returned; no schema change.
- Updated the Activity search placeholder and UI context.
- Verification: `dotnet build src/Pms.Api/Pms.Api.csproj --no-restore -p:BaseOutputPath=.verification/activity-search/bin/` succeeded with 0 warnings and 0 errors. The normal API output was locked by the running API process. Web `npm.cmd run build` succeeded; Vite emitted the existing large-chunk warning after the sandbox denied repository-root access on the first attempt and the approved retry succeeded. No tests were run.

## 2026-09-30 — Activity timeline typography

- Refined SuperAdmin Activity event typography with medium-weight action text, clearer line spacing, consistent 12px context/actor/time text, and a more readable day/time label hierarchy.
- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. The sandbox denied repository-root access on the first attempt; the approved broader-filesystem retry succeeded.

## 2026-09-30 — Reduce Activity timeline font sizes

- Reduced event, breadcrumb, actor/time, day label, and clock text sizes while preserving their visual hierarchy.
- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. The sandbox denied repository-root access on the first attempt; the approved broader-filesystem retry succeeded.

## 2026-09-30 — Activity toolbar visual alignment

- Matched Activity dropdowns to the Organizations filter style by replacing floating labels with vertically centered display values; removed the redundant toolbar frame and aligned the control gaps.
- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. The sandbox denied repository-root access on the first attempt; the approved broader-filesystem retry succeeded.

## 2026-09-30 — Audit filter bar alignment

- Matched the Audit Trail filter bar to Activity and Organizations: placeholder-style action selection, consistent control alignment, and removal of the enclosing frame. Preserved explicit accessible From/To labels.
- Verification pending.

## 2026-09-30 — Audit filter bar alignment

- Matched the Audit Trail filter bar to Activity and Organizations: placeholder-style action selection, consistent control alignment, and removal of the enclosing frame. Preserved explicit accessible From/To labels.
- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. The sandbox denied repository-root access on the first attempt; the approved broader-filesystem retry succeeded.

## 2026-09-30 — Global dropdown sizing

- Set shared MUI select values and menu options to a compact 14px/20px type scale with 40px minimum option rows, tighter list padding, and a 320px viewport-bounded menu height.
- Applied through the application theme so dropdowns stay consistent across Activity, Audit, Organizations, and other MUI select fields.
- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. The sandbox denied repository-root access on the first attempt; the approved broader-filesystem retry succeeded.

## 2026-09-30 — Tenant workspace visual alignment

- Aligned the authenticated user workspace with SuperAdmin visual patterns through scoped styling for the navigation shell, headings, buttons, controls, cards, dashboard, project board, members, settings, notifications, modals, and Activity.
- Added matching dark-mode tokens and responsive tablet/mobile layouts, retaining organization and project switchers on mobile. No API, permission, or workflow behavior changed; SuperAdmin styling is excluded from the new selectors.
- Updated UI context. Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. The sandbox denied repository-root access on the first attempt; the approved broader-filesystem retry succeeded.

## 2026-09-30 — Tenant sidebar alignment

- Matched tenant sidebar desktop width, padding, navigation row height, selected colors, and active edge indicator to the SuperAdmin navigation while retaining workspace links and responsive behavior.
- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. The sandbox denied repository-root access initially; the approved broader-filesystem retry succeeded.

## 2026-09-30 â€” Tenant sidebar matches SuperAdmin shell

- Replaced the tenant shell's custom flat navigation with the shared sidebar primitives used by SuperAdmin: brand header, grouped navigation, collapse trigger, profile/logout footer, and overlay drawer.
- Matched the fixed desktop sidebar/header geometry and persisted collapse preference. Added the same responsive drawer behavior for tablet/mobile while preserving tenant routes, organization/project selectors, notification controls, and organization creation.
- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build). Vite emitted the existing large JavaScript chunk warning. The sandbox blocked Vite's repository-root access; the approved retry completed successfully. No tests were run.

## 2026-09-30 â€” Operational tenant dashboard

- Replaced the large generic progress/deadline cards with compact summary metrics, actionable assigned-task priorities (overdue first), project health using existing status/progress/deadline/member data, and a compact recent activity feed beside team workload.
- Reduced card framing and spacing, added responsive layouts and status-focused color cues, title-cased displayed member/actor names, pluralized workload counts, and widened the project selector with a full-name tooltip. Renamed the tenant sidebar dashboard destination to Overview in the preceding sidebar alignment; the Board remains the dedicated task workspace.
- No API, database, or authorization changes. Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build). Vite emitted the existing large JavaScript chunk warning. No tests were run.

## 2026-09-30 â€” Tenant dashboard visual alignment

- Applied the SuperAdmin Overview visual system to the tenant dashboard: Geist hierarchy, compact bordered metric cards, matching purple/blue/orange/pink icon tiles, lightly bordered panels, consistent heading/label scale, and dark-theme surfaces.
- Kept the tenant dashboard's operational content and task interactions unchanged; adjusted metric/panel grids to the same responsive breakpoints. No API, database, or authorization changes.
- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build). Vite emitted the existing large JavaScript chunk warning. No tests were run.

## 2026-09-30 â€” Role-scoped tenant dashboard analytics

- Added a seven-day task creation/completion trend and current-status donut using existing task timestamps and states, with an explicit limitation note for current retained records.
- Made task summary cards navigate to filtered Board results. Added upcoming deadlines and retained actionable priorities/recent activity.
- Scoped summary, workload, deadlines, and health to personal tasks for members; owners/admins and project managers/team leads see team-level data. On-time percentage is limited to completed tasks with due dates and timestamps.
- No API, database, or permission changes. Verification: u001bnpm.cmd run build in pps/web succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. No tests were run.


## 2026-09-30 â€” Remove project tabs from dashboard

- Removed the Board/List/Timeline, Members, and Project settings row from the Overview dashboard; it now appears only on the Board route. The view switch still selects the active task view without navigating away from Board.
- Updated UI context. Verification pending.


- Verification: u001bnpm.cmd run build in pps/web succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. No tests were run.


## 2026-09-30 â€” Task form viewport fit

- Resized the tenant task create/edit modal for desktop and mobile viewports; the form body scrolls independently while Cancel/Create actions remain visible. Mobile paired fields stack vertically.
- No API or data behavior changes. Verification: u001bnpm.cmd run build in pps/web succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. No tests were run.


## 2026-09-30 â€” Near-real-time data refresh

- Added 15-second visible-tab refresh for workspace project tasks, project members, and dashboard metrics, with immediate refresh on focus and reconnect. Avoided repeatedly showing initial-load indicators during background refresh.
- Activity lists/widgets refresh every 10 seconds. SuperAdmin management and summary data refresh every 15â€“30 seconds; heavier analytics remain at 30 seconds. React Query refetches active data on focus/reconnect, and polling pauses while hidden.
- No SignalR/WebSocket/SSE infrastructure exists. This uses existing authenticated endpoints and authorization; it is near-real-time polling rather than push delivery. No API/schema changes.
- Verification pending.


- Verification: u001bnpm.cmd run build in pps/web succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. No tests were run.


## 2026-09-30 â€” Task conversation polish

- Unified task form and conversation scrolling so comments and attachments remain reachable within the viewport; kept task action buttons visible while scrolling.
- Added restrained comment surfaces and improved comment/composer spacing, typography, and teammate selector height. No API or behavior changes. Verification pending.


- Verification: u001bnpm.cmd run build in pps/web succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. No tests were run.


## 2026-09-30 â€” Board card and column polish

- Refined task cards to show existing priority, description, due/completion state, subtask progress, and assignee avatars/overflow. Improved column labels/counts, restrained status accents, spacing, and empty states.
- Preserved task editing and drag-and-drop behavior. No API, schema, or authorization changes. Verification pending.


- Follow-up: removed Board-specific priority color overrides so urgent/high/medium/low chips keep the previous shared colors. Final verification pending.


- Final verification: u001bnpm.cmd run build in pps/web succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. No tests were run.


- Follow-up: explicitly restored the original shared priority colors on Board cards (urgent red, high orange, medium yellow, low green) with white text. Verification pending.


- Final verification: u001bnpm.cmd run build in pps/web succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. No tests were run.


## 2026-09-30 â€” Expandable Board profile area

- Added a project-team avatar preview and expandable signed-in profile panel above the Board content. Panel includes current role and existing organization/project selectors; outside click/Escape dismiss it. Kept the top selectors and omitted Filter, Sort, and Add Task toolbar actions as requested.
- No API, schema, or authorization changes. Verification pending.


- Verification: u001bnpm.cmd run build in pps/web succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. No tests were run.


## 2026-09-30 â€” Align Board toolbar to reference image

- Moved the project member/profile row directly beneath project context and above the view tabs, matching the reference hierarchy. Removed the extra member-count caption; retained avatar overflow and expandable profile selectors.
- Existing board search/priority controls and workflows remain; no Filter/Sort/Add Task controls were added to the profile toolbar. No API/schema changes. Verification pending.


- Verification: u001bnpm.cmd run build in pps/web succeeded (TypeScript and Vite production build); Vite emitted its existing large-chunk warning. No tests were run.


## 2026-09-30 â€” Match team and profile positions to the reference

- Separated the project member avatar strip from the expandable profile menu. The avatar strip is positioned at the right side of the Board project heading, and the signed-in profile control is positioned at the far right of the global tenant top bar, after notifications and theme.
- The profile menu includes account identity, role, organization/project selectors, and an account settings shortcut. At narrow widths, the trigger reduces to the avatar and the menu remains anchored to the top-right control.
- No API, schema, or authorization changes. Verification pending.

- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build). Vite reported the existing large-chunk warning. No tests were run.

## 2026-09-30 â€” Replace workspace selectors with search

- Replaced the tenant top-bar organization/project selector area with a workspace search field. Search currently loaded project tasks, available organization projects, and organization members; selecting results opens the task, Board, or Members page respectively. Organization and project switching remains in the expandable profile menu.
- Results are capped at eight and scoped to data already returned by tenant-authorized APIs. No API, schema, or authorization changes. Verification pending.

- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build). Vite emitted the existing large-chunk warning. No tests were run.

## 2026-09-30 â€” SuperAdmin platform access failure handling

- Changed the initial account/admin access check so non-403 API failures leave the indefinite authentication spinner and show a retryable Platform unavailable state with the actual API error. A policy 403 still routes to the tenant workspace.
- Added retry/sign-out actions and documented the state. No authorization policy or API behavior changed. Verification pending.

- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build). Vite emitted the existing large-chunk warning. No tests were run. The initial sandboxed Vite config load was denied; the approved elevated retry succeeded.

## 2026-09-30 â€” Refine dark mode to match charcoal reference

- Updated global, tenant, and SuperAdmin dark palettes to use near-black shell surfaces, raised charcoal cards/inputs, quieter borders, readable neutral text, and restrained lavender active/focus states. Preserved the existing priority and semantic status colors; light mode is unchanged.
- Updated UI context. Verification pending.

- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. The initial sandboxed Vite config load was denied, and the approved elevated retry succeeded. No tests were run.

## 2026-09-30 â€” Polish task dialog hierarchy

- Raised the tenant task dialog above the fixed top bar/sidebar so its header and backdrop are not obscured. Reduced its desktop width, refined the header and AI draft card, tightened field spacing, and kept the bordered action footer visible. Preserved independent body scrolling and responsive sizing.
- No form behavior, API, or data changes. Verification pending.

- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. The initial sandboxed Vite config load was denied; the approved elevated retry succeeded. No tests were run.

## 2026-09-30 â€” Prevent logout on transient token-refresh failures

- Kept the 15-minute access token and 30-day rotating refresh-token policy. The web client no longer clears credentials when refresh fails because of network/5xx errors; it clears the session only when refresh is missing or definitively rejected (400/401).
- Coordinated refresh-token rotation across same-origin tabs using Web Locks when supported, while retaining the existing single in-tab refresh promise. Updated architecture context. Verification pending.

- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build). Vite emitted the existing large-chunk warning. The sandbox blocked Vite config loading initially; the approved elevated retry succeeded. No tests were run.

## 2026-09-30 â€” Clean up Board task search field

- Replaced the corrupted placeholder with â€œSearch tasks...â€, explicitly aligned the search icon and input text, and matched the field border/focus treatment to the workspace design. Fixed the filtered count to say â€œ1 taskâ€ instead of â€œ1 tasksâ€.
- Updated UI context. Verification pending.

- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. The sandboxed Vite config load was denied initially; the approved elevated retry succeeded. No tests were run.

## 2026-09-30 â€” Close profile menu after workspace selection

- Organization and project selector changes now close the expandable profile menu immediately after applying the selected value. Outside-click and Escape behavior remain unchanged. Verification pending.

- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. The initial sandboxed Vite config load was denied; the approved elevated retry succeeded. No tests were run.

## 2026-10-01 â€” Mobile SuperAdmin Activity Center

- Replaced the Flutter SuperAdmin Activity placeholder with real GET /api/v1/admin/activity-events data. Added search, organization/category/date filters, inclusive custom date bounds, 50-event cursor pagination, event detail sheets, pull/manual refresh, and 15-second polling while the app is foregrounded.
- Matched the existing TaskFlow mobile visual language and semantic category colors while preserving the native drawer and card layout. Added activity response models and API client support; no backend or database changes.
- Updated the stale mobile API URL test to match the configured deployed endpoint and added activity response parsing coverage. Updated mobile UI and development documentation.
- Verification: flutter test --no-pub passed (3 tests). dart format completed. flutter analyze --no-pub reported informational lint issues across the existing mobile project; changed Activity code was adjusted for the reported const, deprecated dropdown value, and brace lints. Recheck analysis before release.
## 2026-10-01 — Align Flutter tenant experience with web

- Added a shared mobile design token/theme layer based on the web TaskFlow palette, spacing, typography, card surfaces, and control styling. Added a tenant shell with Overview, Board, Members, Activity, Notifications, and Settings navigation; authenticated startup now separates tenant accounts from platform admins and shows a retryable unavailable state when role verification fails.
- Updated tenant dashboard metrics to scope member data to the signed-in user and show team/project summaries for managers. Added tenant workspace activity from the existing activity endpoint, task activity in task details, and comment deletion through the API's existing authorization rules. Added a quick-create task entry point on the board and refreshed brand styling.
- Updated mobile UI/development documentation. Verification was attempted with `dart format lib test`, `flutter analyze`, and `flutter --version`; formatter completed, but Flutter commands hung without output in this environment and had to be stopped. No successful analyze, test, or Android build result is available.
## 2026-10-01 — Repair mobile build syntax after font fallback

- Fixed malformed Text style expressions in the mobile screens by restoring `TextStyle(...)` wrappers after removing unsupported GoogleFonts Geist calls. The pasted assembleDebug log's cascading parser errors originated from those broken style expressions. Removed the app-wide Geist lookup and kept the Flutter platform text theme.
- Added the missing imports for AuthSession, AppColors, and Google Fonts as reported in the prior build notes; the Google Fonts import is no longer needed after switching to the platform font.
- Verification: source search confirms no `style: fontSize:` or `GoogleFonts`/Geist runtime lookups remain. Flutter analyze/format could not be completed here: Dart commands stalled without output and were stopped. A successful Android build is still pending.


## 2026-10-01 — Bring Flutter dashboard closer to web

- Added a dashboard title and organization/project breadcrumb, web-matched metric card hierarchy and icon tiles, a seven-day task progress trend based on existing created/completed timestamps, and a status donut with matching category colors. Extended the Task model with optional createdAt for the existing API field. Mobile stacks dashboard panels for narrow screens.
- Verification: Dart format updated the source; its command reported a sandbox access error while attempting to touch the user-level telemetry session file after formatting. Dart analysis reported informational lint findings but no errors. Flutter analyze stalled without output; no Android build was completed.

## 2026-10-01 — Repair mobile dashboard navigation and Dart compile errors

- Repaired the dashboard shell syntax, removed a duplicate metric widget, connected the sidebar to existing Board, Members, Activity, and Settings screens, and fixed TaskPriority enum handling and TaskDetailScreen construction. Added the required theme tokens and kept SuperAdmin navigation gated by its confirmed access flag.
- Restored role-specific startup routing in `app.dart`. Tenant activity now uses the organization-scoped `/api/v1/activity` endpoint; SuperAdmin activity remains on `/api/v1/admin/activity-events`. Reconciled task form types and stale local/mock AppState mutations with existing API methods.
- Updated mobile UI context. Dart analysis reports 26 lint/info findings and zero analyzer errors in `lib`. `dart format lib test` formatted 23 Dart files but exited nonzero because the Dart analytics process could not update its user-level telemetry file. No Flutter tests or Android build were run.

## 2026-10-01 — Fix Task detail analyzer diagnostics

- Confirmed the screen uses the existing `AppState.getTaskById` API and guarded post-delete navigation with a mounted check after the asynchronous delete request.
- Verification: `dart analyze lib` reports zero errors; the project has 25 remaining lint/info findings. Formatting reported the file unchanged; Dart still emits a telemetry-file access error after formatting. No tests or Android build were run.

## 2026-10-01 — Add task lookup compatibility alias

- Added `AppState.getTask(String)` as a delegate to the existing `getTaskById(String)` so editor buffers using either method name resolve identically.
- Verification: targeted `dart analyze lib/src/screens/task_detail_screen.dart` reports no issues. Dart emits its existing user-level telemetry file access message after analysis; no tests or Android build were run.

- Follow-up: changed `AppState.getTask` to return `Future<Task?>` to match the editor diagnostic's `FutureBuilder.future` use. Targeted analysis of the saved task detail file still reports no issues.

## 2026-10-01 — Align mobile activity parser test with current model

- Replaced the obsolete `AdminActivityPage` fixture with a `PlatformActivityItem` fixture matching the model currently parsed by the SuperAdmin activity API method.
- Verification: targeted `dart analyze test/api_client_test.dart` reports no issues. No tests were run.

## 2026-10-01 — Revert mobile UI redesign

- Restored tracked Flutter app source and mobile UI documentation to the last committed versions and removed the untracked redesign screens/theme/sidebar. Preserved the separate Android Gradle build-directory change and the configured deployed API URL assertion in the API client test.
- The prior web-to-mobile visual alignment is no longer present in the Flutter UI. The mobile screens now match the committed baseline.

## 2026-10-01 — Add tenant mobile drawer from reference

- Added a tenant workspace shell with the left overlay drawer, grouped navigation, account footer, notification/theme actions, and links to existing Overview, Board, Members, Notifications, and Settings pages. Added organization-scoped Activity loading and New organization action, and routed confirmed SuperAdmins to their existing administration shell.
- Verification: targeted Dart analysis of the shell, app router, and API client reports no analyzer errors; it reports existing informational lints. Dart formatting completed, followed by its user-level telemetry file access message. No tests or Android build were run.

## 2026-10-01 - Match tenant mobile dashboard reference

- Reworked the mobile Overview into the supplied single-column dashboard order with task summary cards, created/completed trend chart, status distribution, user priorities, project health, upcoming deadlines, team workload, and organization activity. Added compact workspace search to the global top bar and connected dashboard shortcuts to Board and Activity.
- Added optional task creation timestamps to the mobile model so the trend chart uses API dates; added simple New project and New task dialogs using the existing authenticated endpoints. Project health calculates on-time completion only when dates are present.
- Verification: targeted `dart analyze` for the dashboard, shell, task model, and app state printed `No issues found!`. The process then exits nonzero because Dart cannot update the user-level telemetry session file. `dart format` formatted the changed Dart files and reports the same telemetry file access issue afterward. No tests or Android build were run.

## 2026-10-01 - Extend web workspace behavior to mobile

- Scoped dashboard metrics and charts by role, connected dashboard metric cards to filtered Board views, added the web-style Board heading/actions, profile organization/project switching, task search/detail navigation, and notification task routing through the authorized project.
- Expanded mobile Activity with tenant-web search, category/date filters, event details, manual/periodic refresh, cursor paging, and organization-switch reloads using the existing authorized activity API.
- Verification: `dart analyze` on the six changed Dart source files reported zero analyzer errors and 12 info-level lints. `dart format` completed formatting but both Dart commands exited nonzero afterward because Dart could not update its user-level telemetry session file. `git diff --check` passed. No tests or Android build were run.

## 2026-10-01 - Investigate undelivered email reports

- Removed the Brevo credential and sender address from tracked `appsettings.json`; delivery configuration remains environment-only as documented in Render deployment settings. Redacted OTP values from application logs and clarified that Brevo acceptance is not delivery confirmation.
- Restricted the Development email mode indicator and in-memory message inbox to Development. The inbox can contain OTPs and reset links and must not be accessible in production.
- Verification: API build succeeded with zero warnings/errors using a separate output directory because the running API held its normal build output open. `appsettings.json` parsed successfully and `git diff --check` passed. The Brevo credential previously present in source must be revoked and replaced in the API host configuration; local code changes cannot validate live Brevo account status or deliverability.

## 2026-10-02 - Match mobile dashboard to web reference

- Made the Flutter tenant dashboard responsive to the supplied wide reference: four large metric cards, paired analytics and lower panels, matching status colors, weekday chart labels/grid/area fills, and a larger centered distribution donut. Narrow phone layouts remain single-column.
- Verification: `dart analyze apps/mobile/lib/src/screens/dashboard_screen.dart` reported `No issues found!`; Dart then exited nonzero when telemetry could not update the user-level session file. `dart format` formatted the file and encountered the same telemetry-file permission error afterward. `git diff --check` passed. No data/API behavior was changed, and no Flutter build/device screenshot was run.
- Follow-up: changed phone-width task metrics to a two-column 2x2 grid, retaining the single-column layout for the remaining phone dashboard panels.

## 2026-10-02 - Match mobile task and project creation forms to web

- Kept the dashboard New project/New task actions in the web-style equal-width secondary/primary row. Expanded project creation to name, description, dates, and status; expanded task creation to project context, AI suggestion/use-draft, title/description, status/priority, dates, and assignee selection. Added mobile API parsing/call support for the existing authorized AI task suggestion endpoint.
- Verification: targeted `dart analyze` of the dashboard, models, and API client reported zero errors and two existing info-level brace lints in unrelated API client lines. `dart format` formatted the dashboard, model, and API client; it exited afterward with the existing permission error updating the user-level telemetry file. `git diff --check` passed. No backend behavior or endpoint was changed; no tests or Android build were run.

## 2026-10-02 - Improve SuperAdmin report export on mobile

- Changed the SuperAdmin Overview and Reports export actions to use the native file picker with the existing report CSV bytes, allowing Android/iOS users to select a visible save destination instead of writing into app-private temporary storage. Both actions share one export helper and display a save/cancel status.
- Verification: `dart analyze apps/mobile/lib/src/screens/admin_screen.dart` reported zero errors and eight existing `prefer_const_constructors` info lints. `dart format` completed. Both Dart commands printed the existing user-level telemetry-file access error afterward; `git diff --check` passed. No tests or device build were run.

## 2026-10-02 - Fix activity date range diagnostics

- Hardened web SuperAdmin Activity date bounds so custom inclusive dates cannot produce a future instant or exceed the API's 366-day limit. Made the migration 003 reminder conditional on an activity-schema error in both the platform and tenant Activity pages; date validation errors now show the API's actionable date message alone.
- Verification: `npm.cmd run build` in `apps/web` completed TypeScript and Vite production build successfully. `git diff --check` passed. No tests or API/database changes were made.

## 2026-10-02 - Fix mobile drawer context assertion

- Fixed the organization-create and sign-out drawer actions to read `AppState` before popping the drawer. Organization creation now opens its dialog from the root navigator context, avoiding inherited-widget lookups through a deactivated drawer context.
- Verification: targeted Dart analysis of `workspace_shell.dart` reported no errors and 10 existing info-level lints. Formatting completed; Dart emitted its existing user-level telemetry-file access message afterward. `git diff --check` passed. No device run or tests were performed.

## 2026-10-04 - Update retired Gemini model configuration

- Replaced the retired `gemini-1.5-flash` API default with the stable `gemini-3.8-flash` model, updated the unavailable-model response with the exact API-host setting, and documented that `Gemini__Model` environment overrides must be updated and redeployed separately.
- Verification: API build succeeded with zero warnings/errors using a temporary output directory because the normal API output DLL was locked by the running API process. `appsettings.json` parsed and its Gemini model value was checked; `git diff --check` passed. No credentials were read or changed. The deployed API host override still requires a manual variable update if `Gemini__Model` is set there.

## 2026-10-04 - Match mobile SuperAdmin pages to web phone reference

- Rebuilt the Flutter SuperAdmin header and left overlay drawer around the web mobile reference, including the Platform/section breadcrumb, search, theme, admin identity/sign-out, and Main/Tools/Help navigation. Restyled Overview with full-width metrics, live/greeting header, real trend sparklines, project growth, task status, and recent projects; Analytics now has 2x2 period summaries, line charts, and status/priority donuts. Added mobile API models/calls and pages for cross-tenant Activity and the separate administrative Audit Trail.
- Verification: Dart formatting completed for the three changed Dart files. `git diff --check` passed. `dart analyze` and `flutter analyze --no-pub` both stalled before producing diagnostics and were stopped; no tests or device build were run.

## 2026-10-04 - Fix SuperAdmin overview visibility and metric grid

- Changed the SuperAdmin Overview metrics from a full-width vertical list to a two-column responsive wrap with compact flexible-height cards. Verified the section already uses a `SingleChildScrollView` under the app bar; its content is therefore reachable by scrolling rather than constrained to the initial viewport.
- Verification: `dart format` and analyzer checks are pending; no tests or device build were run. `git diff --check` is run as final verification.

## 2026-10-04 - Scope and polish tenant web Activity Center

- Confirmed the regular workspace Activity page uses the authenticated tenant endpoint, separate from the SuperAdmin cross-tenant feed. Strengthened server filtering so active organization members see organization events, while project-linked events also require active membership in a project belonging to that organization. Added project names to event context.
- Reworked tenant Activity filters and timeline presentation: removed duplicate category controls, added date-bound validation, included all filters in the React Query cache key, fixed timeline cards to fill available width, and added responsive typography/layout. This also repairs malformed error-alert JSX in the previous page source.
- Verification: API build passed with zero warnings/errors using a temporary output directory because the running API locks its normal output files. `npm.cmd run build` completed TypeScript compilation but Vite could not read a parent directory due the environment's access restriction; no web bundle was produced. `git diff --check` passed. No tests were run.

## 2026-10-04 - Add distinct SuperAdmin report export formats

- Expanded the existing full-platform export to presentation PDF, analysis XLSX, and normalized raw CSV. The PDF includes a report ID, generated time, KPI summary, task status bars, project completion progress, and page footer. The workbook separates Summary and Data, freezes/filters the data header, and stores counts/dates as analysis-friendly values. CSV contains one header and data rows only. Added format selection and accurate privacy notes to the web Reports page; the web Overview quick export now downloads PDF. The mobile Reports page also offers all formats, and the mobile Overview quick export downloads PDF.
- Verification: API build passed with zero warnings/errors using a temporary output path because the running API locks normal build outputs. Web TypeScript compilation passed as part of `npm.cmd run build`, then Vite failed to read an ancestor directory under environment access restrictions. Dart formatting stalled without output and was stopped. `git diff --check` passed. No tests were run.

## 2026-10-04 - Document local Brevo email setup

- Added a placeholder-only Brevo environment template for local API email delivery and documented how to supply the variables to the API process. Kept credentials out of tracked appsettings; real sends require a verified sender and a valid Brevo key. `.env` files are ignored by Git.
- Verification: checked the template has no real credential, `.gitignore` ignores `.env`, and `git diff --check` passed. No tests or API build were run; actual email delivery requires user-provided Brevo credentials and sender verification.

## 2026-10-05 - Remove tracked API credentials before push

- Removed the database connection string and development JWT signing key from tracked appsettings. Docker Compose now takes the JWT key from its ignored local environment file, direct-run setup documents .NET User Secrets/environment configuration, and API startup rejects a missing or shorter-than-32-byte JWT signing key.
- Verification: appsettings JSON parses without ConnectionStrings or Jwt:SigningKey, Docker Compose wiring and example variables were inspected, and `git diff --check` passed. No tests or build were run. A push was initially blocked by automatic review for these tracked credentials; they have now been removed before retrying.
## 2026-10-05 - Make SuperAdmin creation captions live

- Replaced the mobile SuperAdmin Overview's 30-day creation captions with counts summed from the current seven UTC calendar days for users and projects. The Overview now refreshes dashboard totals and analytics every 30 seconds while open; 30-day growth charts remain on their existing period.
- Verification: `git diff --check` passed. `dart format`/`dart analyze` were attempted but stalled without output and were stopped; no tests or device build were run.