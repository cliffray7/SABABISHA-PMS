# UI Context

## SuperAdmin Activity and Audit pages

The SuperAdmin Activity Center in `apps/web/src/AdminPlatform.tsx` reads authenticated SuperAdmin-only `GET /api/v1/admin/activity-events`. It displays tenant workspace `ActivityEvent` records across organizations, with organization/category/search/date filters, cursor pagination, polling, and event details. It exposes only the fields already stored in the human-readable activity table; it is limited to actions recorded after migration 003 and does not include platform-wide user suspension/deletion actions.

The SuperAdmin Activity Center uses the shared TaskFlow palette and supports dark mode and narrow viewports. Its compact toolbar order is Search, Organization, Date range, More filters, Refresh. Custom date fields are hidden until More filters is opened, leaving the category tabs and timeline near the page heading. It shows a 30-second polling indicator, debounced search, time presets (today, 7 days, 30 days, all time, and custom), and category tabs. Events are grouped by local day with local clock time, relative time, actor-led descriptions, and organization/project/entity breadcrumbs. Project names are included when the related project remains available. Search covers actor, organization, project, entity name/type, action, description, status, correlation ID, and exact GUID matches for event, actor, entity, organization, and project IDs. These controls do not change activity coverage or authorization.

Activity filter controls use explicit responsive grid areas and full-width MUI form fields so the organization selector and date labels do not collapse at intermediate viewport sizes. Search, Organization, Date range, More filters, and Refresh stay on one compact row at desktop widths; a compact two-row layout is used below 900px, with a stacked layout reserved for phones. The organization and date selectors use placeholder-style values (matching the Organizations page) without floating labels, and the toolbar has no extra enclosing card border.
The organization select's value is constrained to its field width with ellipsis; the grid uses dedicated tablet/mobile arrangements to keep the controls usable.

The separate SuperAdmin Audit Trail reads authenticated `GET /api/v1/admin/audit-events` and records successful user creation, suspension, and permanent deletion. It remains the restricted compliance record and must not be merged with workspace activity. Its action selector uses a centered placeholder-style value, and its filter row shares the clean, unframed style of the Organizations management filters; date labels remain explicit for accessibility.

The tenant workspace Activity Center in `apps/web/src/ActivityCenter.tsx` reads authenticated `GET /api/v1/activity?organizationId=...`. The API requires active organization membership and applies the organization filter before search, category filters, and cursor pagination. The UI polls every 30 seconds and also exposes manual refresh, search, category/date filters, event details, and a five-event dashboard widget. Migration `003_activity_events.sql` is required. Current event coverage: organization creation, member role/removal, invitations created/accepted; project create/update/status/archive/restore and project membership changes; task create/update/status/priority/due-date/assignment/delete/restore and subtask create/completion/reopen; comment create/mention/delete and attachment upload/delete. Event records are inserted with successful business writes; comment text, attachment contents, authentication secrets, and AI prompts are not copied to metadata. There is no historical backfill. This is not yet a complete feed of authentication, operations, billing, AI, or SuperAdmin platform events.

MUI dropdowns use the shared theme sizing: 14px option text, 20px line height, 40px minimum option height, compact list padding, and a viewport-bounded menu height.

## Tenant workspace visual system

The authenticated tenant workspace (`.shell` without `.admin-platform-shell`) follows the SuperAdmin visual language while retaining its existing navigation and workflows: Geist typography, a neutral page surface, white lightly bordered cards, restrained purple active/focus states, 36–40px controls, compact navigation, and responsive spacing. The tenant sidebar follows the SuperAdmin sidebar's 250px desktop width, 42px nav rows, selected background/text treatment, and slim active indicator, with its workspace role and tenant routes retained. Shared styling covers the workspace shell, dashboard, project board and cards, members, settings, notifications, modals, and Activity. Dark mode uses matching neutral surfaces and purple accents. These styles are scoped to tenant pages and do not alter SuperAdmin layouts or behavior.

The tenant workspace shell now uses the same shared `SidebarProvider`, `Sidebar`, `SidebarHeader`, grouped navigation, `SidebarFooter`, `SidebarTrigger`, and overlay components as the SuperAdmin shell. It has matching fixed desktop sidebar/header geometry, persisted desktop collapse, profile/logout footer, and responsive drawer behavior. Tenant-specific route groups, organization creation, organization/project selectors, notifications, and role context remain in the tenant shell. Sidebar collapse preference is stored separately as `taskflow.workspaceSidebarCollapsed`.

The tenant dashboard uses an operational layout with compact inline task metrics, a task-priority list that opens the existing task editor, a project-health section based on project status/task completion/deadline/member data, and a compact organization-scoped recent activity feed beside team workload. Names are consistently title-cased for display. The project selector allows more room for long names and exposes the selected name as a tooltip. Dashboard links route to the existing Board and Members pages; no new API or sample data is introduced.

The tenant dashboard now uses the SuperAdmin Overview card language: compact metric cards with the same icon tiles and restrained tones, lightly bordered white panels, matching heading/label hierarchy, and the same dark-mode surface tokens. Its task priorities, project health, recent activity, and workload content remain tenant-specific and retain their existing navigation/actions. Metric and panel grids follow the SuperAdmin responsive breakpoints.

## Tenant dashboard analytics

The tenant dashboard now includes a seven-day created/completed area chart and a current task-status donut built from the selected project's existing task records. Trend counts are explicitly limited to currently retained tasks and can undercount past work when tasks were reopened or deleted; no historical series is fabricated. KPI cards link to Board views filtered to matching task states. Members see their assigned-task counts, personal workload, priorities, and assigned deadlines. Organization owners/admins and project managers/team leads additionally see project health, team workload, and project-wide deadlines. Project health shows an on-time percentage only for completed tasks with due dates and completion timestamps. The dashboard retains its SuperAdmin-matched card palette, restrained chart colors, responsive layout, and dark-theme surfaces.


The tenant dashboard omits the Board/List/Timeline navigation row to keep the overview focused. Those project task-view tabs appear on the Board route only; Members and Project settings remain available from that row on the Board page.


The tenant task create/edit modal is viewport-bounded, uses a wider desktop layout, scrolls the form body independently, and keeps its action footer visible. On narrow screens it nearly fills the viewport and stacks paired form fields. The behavior is scoped to .task-form; other dialogs are unchanged.

The tenant task dialog is layered above the fixed top bar and sidebar so its title and full backdrop remain visible. It uses a more compact 720px desktop width, a restrained AI-draft panel, lighter form spacing, and a sticky bordered footer; its body remains independently scrollable and mobile behavior remains viewport-bounded.

The Board task search uses plain ASCII placeholder text to avoid encoding mojibake. Its icon is centered independently of the input text, with explicit left padding, consistent field height, and the shared light/dark focus treatment. The filtered task count uses singular/plural labels correctly.

Selecting an organization or project in the expandable tenant profile menu applies the choice and closes the menu immediately. Outside click and Escape dismissal remain supported.


## Live data refresh behavior

Workspace task lists, project members, and dashboard metrics update from the existing API every 15 seconds while a project is selected and the tab is visible. Activity views and widgets refresh every 10 seconds. Active query data refreshes immediately on browser focus/reconnect, and user mutations continue to trigger immediate local reloads. SuperAdmin management and summary views refresh every 15–30 seconds; heavier analytics use 30 seconds. Background-tab polling is disabled. The UI uses the existing authenticated APIs, so each refresh is tenant/policy scoped server-side. Updates are near-real-time polling, not instantaneous push notifications.


Task details uses one bounded, scrollable editor region for fields, comments, attachments, and subtasks, with task actions sticky at the bottom. Comment entries use compact bordered surfaces and clearer author/date/body hierarchy; the comment composer and teammate notification selector are visually compact and remain functionally unchanged.


The tenant Board cards now surface existing task data in a compact hierarchy: priority chip, title, optional description, due/completion date, subtask progress, and up to three assignee avatars with an overflow count. Columns use title-case status labels, task counts, subtle status accents, and a clearer empty state. Card click/edit and drag-to-change-status behavior are preserved; no task category field or API data was added.


Board priority chips retain the shared existing urgent/high/medium/low color palette; Board card-specific pastel color overrides are not used.


The Board's task priority chips retain the existing shared colors: urgent red (#e13030), high orange (#e97c21), medium yellow (#c8a80d), and low green (#42986e), with white text.


The Board has a compact profile/team toolbar below its view tabs. It shows up to five project member initials with an overflow count and an expandable account control. The panel shows the signed-in user, project/workspace role, and the existing organization/project selectors; outside click and Escape close it. The existing top selectors remain available. No filter, sort, or add-task actions were added to this toolbar.


Board hierarchy aligned to the supplied inspiration: project heading/summary, a compact member-avatar and expandable profile row, then Board/List/Timeline tabs and the existing task search/priority controls. The team row uses avatars with overflow only, without an extra count label. The Profile panel retains account/role and organization/project selectors; Filter, Sort, and a toolbar Add Task action are omitted.

The Board reference's controls occupy two separate positions: project member avatars sit at the far right of the project heading row, while the signed-in profile control sits in the global top bar after notifications and theme. The profile control expands to show account details, organization/project selectors, and an account settings shortcut. On narrow screens the profile trigger collapses to its avatar and the project member avatars remain aligned with the heading actions.

The tenant top bar uses a workspace search field in place of the organization/project selector controls. Search results include currently loaded project tasks, projects available in the selected organization, and organization members; selecting a task opens it on the Board, a project opens its Board, and a person opens Members. Organization/project switching remains in the expandable profile menu. Search results are bounded to eight items and stay within the signed-in user's already-authorized workspace data.

Dark mode follows the supplied charcoal reference across tenant and SuperAdmin shells: near-black page/sidebar/topbar surfaces, subtly raised charcoal cards and fields, restrained borders, readable neutral text, and a soft lavender active/focus accent. Task priority colors and semantic status colors remain unchanged; light mode is unchanged.

If account loading or the initial SuperAdmin authorization check fails for a reason other than a denied admin policy, the app displays a retryable Platform unavailable state with the API error instead of leaving the user on an indefinite authentication spinner. A policy denial still routes to the tenant workspace as before.
