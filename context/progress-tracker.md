# Progress Tracker

## 2026-09-30 — Compact Activity first screen

- Reduced the Activity header, toolbar, category tabs, and first timeline group spacing. Kept custom dates collapsed behind More filters so activity appears higher on the first screen.
- Verification: `npm.cmd run build` succeeded (TypeScript and Vite production build). Vite emitted its existing large-chunk warning. No tests were run.

## 2026-09-30 — Activity toolbar order

- Matched the toolbar to the requested order: Search activity, Organization, Date range, More filters, Refresh. Moved manual refresh out of the header, and removed the redundant Search field label so the placeholder stays uncluttered.
- Verification: `npm.cmd run build` succeeded (TypeScript and Vite production build). Vite emitted its existing large-chunk warning. No tests were run.

## 2026-09-30 — Activity Center timeline refinements

- Matched the platform Activity view to the requested timeline workflow: 30-second live polling indicator, debounced search, organization and date presets, expandable custom dates, All/Projects/Tasks/People/Collaboration/System tabs, and day-grouped events with local time, relative time, actor-first descriptions, and organization → project → entity breadcrumbs.
- Added the project name to the SuperAdmin activity response using an optional project join, preserving events when a project row is no longer available. No schema changes.
- Verification: API `dotnet build` succeeded with 0 warnings/errors using isolated output because the running API process locks normal output. Frontend `npm.cmd run build` succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. No tests or live database calls were run.

## 2026-09-30 — Activity organization filter overflow

- Set Activity search, organization, and date controls to MUI full-width mode; constrained input roots and added ellipsis for long selected organization names. Kept named responsive grid areas so filters reflow cleanly at tablet and mobile widths.
- Verification: `npm.cmd run build` succeeded (TypeScript and Vite production build). Vite emitted the existing large JavaScript chunk warning. No tests were run.

## 2026-09-30 — Activity filter sizing fix

- Fixed the SuperAdmin Activity filter row so the organization selector and both date controls receive explicit grid areas and full-width form controls. Added intermediate and mobile grid layouts to prevent labels and selected values from being clipped as the content width changes.
- Verification: `npm.cmd run build` succeeded (TypeScript and Vite production build). Vite emitted its existing large-chunk warning. No tests were run.

## 2026-09-30 — SuperAdmin Activity page visual polish

- Refined the Activity page presentation with a clearer platform timeline header, balanced responsive filter layout, icon-led category controls, readable event cards with actor/time context, and an empty state that explains filter results and offers a reset when needed.
- Added responsive and dark-theme styling using existing TaskFlow design tokens. No activity API, authorization, or database behavior changed.
- Verification: `npm.cmd run build` succeeded (TypeScript and Vite production build). Vite reported the existing large JavaScript chunk warning. No tests were run.

## 2026-09-30 — SuperAdmin Activity Center fix

- Replaced the SuperAdmin Activity page's old audit-feed query with a new server-side query over `ActivityEvents`, authorized through the existing `SuperAdmin` policy. Added optional organization, category, search, date, and cursor pagination filters; results remain newest-first and are limited to stored workspace activity events.
- Kept the old audit page intact under a distinct **Audit Trail** route and label, still reading `/api/v1/admin/audit-events`.
- The SuperAdmin Activity page now polls every 30 seconds and supports organization selection, category/search/date filters, event details, refresh, and paging. It requires migration 003 and does not backfill actions performed before the migration or include admin account changes that are only in the audit table.
- Verification: web `npm.cmd run build` succeeded (TypeScript and Vite; existing large-chunk warning). The sandbox denied the first Vite build access to the repository root; the approved broader-filesystem retry succeeded. API `dotnet build` succeeded with 0 warnings/errors using isolated output at `.verification/api` because the already-running local API process locks its normal output assembly. An initial build to the normal output failed only on that file lock. No tests or live database calls were run.

## 2026-09-30 — SuperAdmin Activity page

- Completed: connected Activity view to the existing protected audit endpoint with action/date filters, cursor pagination, refresh, and loading/empty/error states.
- Improved event details to show actor and target identifiers, outcome, optional reason, timestamp, and correlation ID. Date filters now include both selected calendar dates and invalid ranges are surfaced before querying.
- Backend and database contract unchanged. Existing coverage remains limited to successful user creation, suspension, and permanent deletion.
- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build). Vite emitted its existing large-chunk warning. Initial sandbox build attempt was blocked by parent-directory access; approved broader filesystem run completed successfully.
- Scope note: `context/feature-specs/` is absent in this checkout. The existing SuperAdmin roadmap and API contract proposal were used as the activity behavior reference.

## 2026-09-30 — Activity empty-state diagnosis

- Confirmed the page calls the audit endpoint; server code writes events only after successful user creation, suspension, and permanent deletion. No historical backfill exists.
- Updated the empty-state guidance to distinguish a truly empty audit feed from setup checks: verify the frontend API target and apply migration 002 to that API's database.
- Local repository inspection cannot determine the deployed API target, whether its migration is applied, or whether its database contains events. No live API/database was queried or mutated.
- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. The sandboxed attempt was denied repository-root access, and the approved broader filesystem run completed successfully.

## 2026-09-30 — TypeScript baseUrl deprecation

- Removed deprecated `compilerOptions.baseUrl` from `apps/web/tsconfig.json`; retained the `@/*` alias paths mapping, which is resolved relative to the config.
- Verification: `npm.cmd run build` in `apps/web` succeeded with the existing TypeScript toolchain (TypeScript build and Vite production build); Vite emitted its existing large-chunk warning. The sandboxed Vite run was blocked from reading the repository root, while the approved broader filesystem run completed successfully. The alias also remains valid without `baseUrl` under the installed compiler.

## 2026-09-30 — Remove diamond from shared brand

- Removed the diamond mark from the shared signed-in TaskFlow brand component; retained the TaskFlow wordmark.
- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build). Vite emitted its existing large-chunk warning.

## 2026-09-30 — Tenant workspace Activity Center

- Added a distinct `ActivityEvent` entity/store, additive SQL migration 003, and authenticated `GET /api/v1/activity` with server-side active-organization and active-project membership filtering, search, category/date filters, bounded cursor pagination, and stable newest-first ordering.
- Successful existing project, task/subtask, assignment, comment/mention, attachment, organization membership, and invitation mutations queue activity in the same EF Core save as the business change. Event descriptions avoid comment bodies, attachment contents, credentials, and AI prompts.
- Added the workspace Activity page, polling every 30 seconds, category/search/date filters, event detail disclosure, navigation, and a five-event dashboard widget. Kept `/admin/activity` and `AdminAuditEvent` as the separate SuperAdmin audit trail.
- Added migration instructions to README and updated project, architecture, UI, and SuperAdmin roadmap context.
- Database migration 003 must be applied to the API database before deploying/using this feature. Existing activity is not backfilled. This first slice does not capture login/security failures, billing, AI operations, incidents, health/system operations, SuperAdmin-wide mutations, or every possible update field; it is not a claim that every system event is recorded. No SignalR exists, so the page uses polling.
- Verification: API project build succeeded with 0 warnings/errors using isolated output; web `npm.cmd run build` succeeded (existing large-chunk warning); `dotnet test Sababisha.Pms.slnx --no-restore` passed 1 unit and 1 integration test. Both current .NET tests are starter placeholders, so automated tenant-isolation and event-behavior coverage remains outstanding. No live database migration or data mutation was performed.
- Local runtime check (2026-09-30): web server on port 5173 and API live/readiness endpoints on port 5141 responded. The running API Swagger document lists the audit endpoint but not `/api/v1/activity`; direct request returns 404, so the running API is an older build and needs rebuilding/restarting. Readiness reports healthy but does not verify migration 003. No database mutation was attempted; Docker engine status was inaccessible in this session.
- Follow-up runtime check: `/api/v1/activity` is now registered in local Swagger; an unauthenticated request returns 401, which is expected for this protected endpoint. The pasted log contains successful admin project/analytics queries and HTTP 200, not an Activity or SQL failure. Migration 003's live database presence is still unverified.

## 2026-09-30 � Compact Activity toolbar

- Kept Search, Organization, Date range, More filters, and Refresh on a single compact row across desktop and typical tablet widths; moved the responsive two-row breakpoint to 900px and kept phone stacking.
- Updated the SuperAdmin Activity UI context to document toolbar behavior.
- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build). Vite emitted the existing large-chunk warning. The sandbox denied repository-root access on the first attempt; the approved broader-filesystem retry succeeded.

## 2026-09-30 � Activity toolbar cascade correction

- Corrected the toolbar grid selector specificity so the shared `.admin-activity-filters` flex rule no longer overrides the SuperAdmin Activity one-row grid.
- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. The sandbox again denied repository-root access initially; the approved broader-filesystem retry succeeded.

## 2026-09-30 � Activity typography and search styling

- Matched SuperAdmin Activity heading typography and filter control sizing, border, focus treatment, and muted search surface to the Organizations management page.
- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. The sandbox denied repository-root access initially; the approved broader-filesystem retry succeeded.

## 2026-09-30 � Audit Trail presentation alignment

- Matched Audit Trail page heading and refresh action typography to the Organizations management page and rebuilt its filters as a responsive compact toolbar with consistent field heights, muted surfaces, and focus styles.
- Kept audit actions, date bounds, page size, endpoint, and access rules unchanged.
- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. The sandbox denied repository-root access initially; the approved broader-filesystem retry succeeded.

## 2026-09-30 � Activity and Audit field text alignment

- Vertically centered input, select, date, and search adornment contents inside the shared 40px Activity and Audit filter fields.
- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. The sandbox denied repository-root access initially; the approved broader-filesystem retry succeeded.

## 2026-09-30 � Activity search coverage

- Expanded tenant and SuperAdmin Activity search to include entity type and status, and exact GUID matches for event, actor, entity, project, and (for the platform view) organization IDs. Existing authorization scopes are applied before results are returned; no schema change.
- Updated the Activity search placeholder and UI context.
- Verification: `dotnet build src/Pms.Api/Pms.Api.csproj --no-restore -p:BaseOutputPath=.verification/activity-search/bin/` succeeded with 0 warnings and 0 errors. The normal API output was locked by the running API process. Web `npm.cmd run build` succeeded; Vite emitted the existing large-chunk warning after the sandbox denied repository-root access on the first attempt and the approved retry succeeded. No tests were run.

## 2026-09-30 � Activity timeline typography

- Refined SuperAdmin Activity event typography with medium-weight action text, clearer line spacing, consistent 12px context/actor/time text, and a more readable day/time label hierarchy.
- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. The sandbox denied repository-root access on the first attempt; the approved broader-filesystem retry succeeded.

## 2026-09-30 � Reduce Activity timeline font sizes

- Reduced event, breadcrumb, actor/time, day label, and clock text sizes while preserving their visual hierarchy.
- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. The sandbox denied repository-root access on the first attempt; the approved broader-filesystem retry succeeded.

## 2026-09-30 � Activity toolbar visual alignment

- Matched Activity dropdowns to the Organizations filter style by replacing floating labels with vertically centered display values; removed the redundant toolbar frame and aligned the control gaps.
- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. The sandbox denied repository-root access on the first attempt; the approved broader-filesystem retry succeeded.

## 2026-09-30 � Audit filter bar alignment

- Matched the Audit Trail filter bar to Activity and Organizations: placeholder-style action selection, consistent control alignment, and removal of the enclosing frame. Preserved explicit accessible From/To labels.
- Verification pending.

## 2026-09-30 � Audit filter bar alignment

- Matched the Audit Trail filter bar to Activity and Organizations: placeholder-style action selection, consistent control alignment, and removal of the enclosing frame. Preserved explicit accessible From/To labels.
- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. The sandbox denied repository-root access on the first attempt; the approved broader-filesystem retry succeeded.

## 2026-09-30 � Global dropdown sizing

- Set shared MUI select values and menu options to a compact 14px/20px type scale with 40px minimum option rows, tighter list padding, and a 320px viewport-bounded menu height.
- Applied through the application theme so dropdowns stay consistent across Activity, Audit, Organizations, and other MUI select fields.
- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. The sandbox denied repository-root access on the first attempt; the approved broader-filesystem retry succeeded.

## 2026-09-30 � Tenant workspace visual alignment

- Aligned the authenticated user workspace with SuperAdmin visual patterns through scoped styling for the navigation shell, headings, buttons, controls, cards, dashboard, project board, members, settings, notifications, modals, and Activity.
- Added matching dark-mode tokens and responsive tablet/mobile layouts, retaining organization and project switchers on mobile. No API, permission, or workflow behavior changed; SuperAdmin styling is excluded from the new selectors.
- Updated UI context. Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. The sandbox denied repository-root access on the first attempt; the approved broader-filesystem retry succeeded.

## 2026-09-30 � Tenant sidebar alignment

- Matched tenant sidebar desktop width, padding, navigation row height, selected colors, and active edge indicator to the SuperAdmin navigation while retaining workspace links and responsive behavior.
- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. The sandbox denied repository-root access initially; the approved broader-filesystem retry succeeded.

## 2026-09-30 — Tenant sidebar matches SuperAdmin shell

- Replaced the tenant shell's custom flat navigation with the shared sidebar primitives used by SuperAdmin: brand header, grouped navigation, collapse trigger, profile/logout footer, and overlay drawer.
- Matched the fixed desktop sidebar/header geometry and persisted collapse preference. Added the same responsive drawer behavior for tablet/mobile while preserving tenant routes, organization/project selectors, notification controls, and organization creation.
- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build). Vite emitted the existing large JavaScript chunk warning. The sandbox blocked Vite's repository-root access; the approved retry completed successfully. No tests were run.

## 2026-09-30 — Operational tenant dashboard

- Replaced the large generic progress/deadline cards with compact summary metrics, actionable assigned-task priorities (overdue first), project health using existing status/progress/deadline/member data, and a compact recent activity feed beside team workload.
- Reduced card framing and spacing, added responsive layouts and status-focused color cues, title-cased displayed member/actor names, pluralized workload counts, and widened the project selector with a full-name tooltip. Renamed the tenant sidebar dashboard destination to Overview in the preceding sidebar alignment; the Board remains the dedicated task workspace.
- No API, database, or authorization changes. Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build). Vite emitted the existing large JavaScript chunk warning. No tests were run.

## 2026-09-30 — Tenant dashboard visual alignment

- Applied the SuperAdmin Overview visual system to the tenant dashboard: Geist hierarchy, compact bordered metric cards, matching purple/blue/orange/pink icon tiles, lightly bordered panels, consistent heading/label scale, and dark-theme surfaces.
- Kept the tenant dashboard's operational content and task interactions unchanged; adjusted metric/panel grids to the same responsive breakpoints. No API, database, or authorization changes.
- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build). Vite emitted the existing large JavaScript chunk warning. No tests were run.

## 2026-09-30 — Role-scoped tenant dashboard analytics

- Added a seven-day task creation/completion trend and current-status donut using existing task timestamps and states, with an explicit limitation note for current retained records.
- Made task summary cards navigate to filtered Board results. Added upcoming deadlines and retained actionable priorities/recent activity.
- Scoped summary, workload, deadlines, and health to personal tasks for members; owners/admins and project managers/team leads see team-level data. On-time percentage is limited to completed tasks with due dates and timestamps.
- No API, database, or permission changes. Verification: u001bnpm.cmd run build in pps/web succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. No tests were run.


## 2026-09-30 — Remove project tabs from dashboard

- Removed the Board/List/Timeline, Members, and Project settings row from the Overview dashboard; it now appears only on the Board route. The view switch still selects the active task view without navigating away from Board.
- Updated UI context. Verification pending.


- Verification: u001bnpm.cmd run build in pps/web succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. No tests were run.


## 2026-09-30 — Task form viewport fit

- Resized the tenant task create/edit modal for desktop and mobile viewports; the form body scrolls independently while Cancel/Create actions remain visible. Mobile paired fields stack vertically.
- No API or data behavior changes. Verification: u001bnpm.cmd run build in pps/web succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. No tests were run.


## 2026-09-30 — Near-real-time data refresh

- Added 15-second visible-tab refresh for workspace project tasks, project members, and dashboard metrics, with immediate refresh on focus and reconnect. Avoided repeatedly showing initial-load indicators during background refresh.
- Activity lists/widgets refresh every 10 seconds. SuperAdmin management and summary data refresh every 15–30 seconds; heavier analytics remain at 30 seconds. React Query refetches active data on focus/reconnect, and polling pauses while hidden.
- No SignalR/WebSocket/SSE infrastructure exists. This uses existing authenticated endpoints and authorization; it is near-real-time polling rather than push delivery. No API/schema changes.
- Verification pending.


- Verification: u001bnpm.cmd run build in pps/web succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. No tests were run.


## 2026-09-30 — Task conversation polish

- Unified task form and conversation scrolling so comments and attachments remain reachable within the viewport; kept task action buttons visible while scrolling.
- Added restrained comment surfaces and improved comment/composer spacing, typography, and teammate selector height. No API or behavior changes. Verification pending.


- Verification: u001bnpm.cmd run build in pps/web succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. No tests were run.


## 2026-09-30 — Board card and column polish

- Refined task cards to show existing priority, description, due/completion state, subtask progress, and assignee avatars/overflow. Improved column labels/counts, restrained status accents, spacing, and empty states.
- Preserved task editing and drag-and-drop behavior. No API, schema, or authorization changes. Verification pending.


- Follow-up: removed Board-specific priority color overrides so urgent/high/medium/low chips keep the previous shared colors. Final verification pending.


- Final verification: u001bnpm.cmd run build in pps/web succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. No tests were run.


- Follow-up: explicitly restored the original shared priority colors on Board cards (urgent red, high orange, medium yellow, low green) with white text. Verification pending.


- Final verification: u001bnpm.cmd run build in pps/web succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. No tests were run.


## 2026-09-30 — Expandable Board profile area

- Added a project-team avatar preview and expandable signed-in profile panel above the Board content. Panel includes current role and existing organization/project selectors; outside click/Escape dismiss it. Kept the top selectors and omitted Filter, Sort, and Add Task toolbar actions as requested.
- No API, schema, or authorization changes. Verification pending.


- Verification: u001bnpm.cmd run build in pps/web succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. No tests were run.


## 2026-09-30 — Align Board toolbar to reference image

- Moved the project member/profile row directly beneath project context and above the view tabs, matching the reference hierarchy. Removed the extra member-count caption; retained avatar overflow and expandable profile selectors.
- Existing board search/priority controls and workflows remain; no Filter/Sort/Add Task controls were added to the profile toolbar. No API/schema changes. Verification pending.


- Verification: u001bnpm.cmd run build in pps/web succeeded (TypeScript and Vite production build); Vite emitted its existing large-chunk warning. No tests were run.


## 2026-09-30 — Match team and profile positions to the reference

- Separated the project member avatar strip from the expandable profile menu. The avatar strip is positioned at the right side of the Board project heading, and the signed-in profile control is positioned at the far right of the global tenant top bar, after notifications and theme.
- The profile menu includes account identity, role, organization/project selectors, and an account settings shortcut. At narrow widths, the trigger reduces to the avatar and the menu remains anchored to the top-right control.
- No API, schema, or authorization changes. Verification pending.

- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build). Vite reported the existing large-chunk warning. No tests were run.

## 2026-09-30 — Replace workspace selectors with search

- Replaced the tenant top-bar organization/project selector area with a workspace search field. Search currently loaded project tasks, available organization projects, and organization members; selecting results opens the task, Board, or Members page respectively. Organization and project switching remains in the expandable profile menu.
- Results are capped at eight and scoped to data already returned by tenant-authorized APIs. No API, schema, or authorization changes. Verification pending.

- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build). Vite emitted the existing large-chunk warning. No tests were run.

## 2026-09-30 — SuperAdmin platform access failure handling

- Changed the initial account/admin access check so non-403 API failures leave the indefinite authentication spinner and show a retryable Platform unavailable state with the actual API error. A policy 403 still routes to the tenant workspace.
- Added retry/sign-out actions and documented the state. No authorization policy or API behavior changed. Verification pending.

- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build). Vite emitted the existing large-chunk warning. No tests were run. The initial sandboxed Vite config load was denied; the approved elevated retry succeeded.

## 2026-09-30 — Refine dark mode to match charcoal reference

- Updated global, tenant, and SuperAdmin dark palettes to use near-black shell surfaces, raised charcoal cards/inputs, quieter borders, readable neutral text, and restrained lavender active/focus states. Preserved the existing priority and semantic status colors; light mode is unchanged.
- Updated UI context. Verification pending.

- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. The initial sandboxed Vite config load was denied, and the approved elevated retry succeeded. No tests were run.

## 2026-09-30 — Polish task dialog hierarchy

- Raised the tenant task dialog above the fixed top bar/sidebar so its header and backdrop are not obscured. Reduced its desktop width, refined the header and AI draft card, tightened field spacing, and kept the bordered action footer visible. Preserved independent body scrolling and responsive sizing.
- No form behavior, API, or data changes. Verification pending.

- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. The initial sandboxed Vite config load was denied; the approved elevated retry succeeded. No tests were run.

## 2026-09-30 — Prevent logout on transient token-refresh failures

- Kept the 15-minute access token and 30-day rotating refresh-token policy. The web client no longer clears credentials when refresh fails because of network/5xx errors; it clears the session only when refresh is missing or definitively rejected (400/401).
- Coordinated refresh-token rotation across same-origin tabs using Web Locks when supported, while retaining the existing single in-tab refresh promise. Updated architecture context. Verification pending.

- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build). Vite emitted the existing large-chunk warning. The sandbox blocked Vite config loading initially; the approved elevated retry succeeded. No tests were run.

## 2026-09-30 — Clean up Board task search field

- Replaced the corrupted placeholder with “Search tasks...”, explicitly aligned the search icon and input text, and matched the field border/focus treatment to the workspace design. Fixed the filtered count to say “1 task” instead of “1 tasks”.
- Updated UI context. Verification pending.

- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. The sandboxed Vite config load was denied initially; the approved elevated retry succeeded. No tests were run.

## 2026-09-30 — Close profile menu after workspace selection

- Organization and project selector changes now close the expandable profile menu immediately after applying the selected value. Outside-click and Escape behavior remain unchanged. Verification pending.

- Verification: `npm.cmd run build` in `apps/web` succeeded (TypeScript and Vite production build); Vite emitted the existing large-chunk warning. The initial sandboxed Vite config load was denied; the approved elevated retry succeeded. No tests were run.
