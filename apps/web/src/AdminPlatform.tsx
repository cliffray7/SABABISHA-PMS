import { Alert, Box, Button, Card, CardContent, CircularProgress, InputAdornment, MenuItem, TextField, Typography } from '@mui/material';
import { Activity, Blocks, ChevronRight, CircleHelp, Database, Filter, FolderKanban, HeartPulse, ListTodo, LockKeyhole, MessageSquare, Palette, RefreshCw, Search, Server, Users } from 'lucide-react';
import { useQuery } from '@tanstack/react-query';
import { useEffect, useState } from 'react';
import { api, errorMessage } from './api';

type AuditEvent = { eventId: string; occurredAt: string; actor: { id: string; displayName: string }; action: string; target: { type: string; id: string; displayName: string }; outcome: string; reason?: string | null; correlationId: string };
type AuditPage = { items: AuditEvent[]; nextCursor: string | null };

const actionLabels: Record<string, string> = {
  'user.create': 'Created user',
  'user.suspend': 'Suspended user',
  'user.delete.permanent': 'Permanently deleted user',
};

function auditDateBound(value: string, endOfDay = false) {
  if (!value) return undefined;
  // Convert local calendar dates to UTC instants, with the selected final day included.
  const date = new Date(`${value}T00:00:00`);
  if (endOfDay) date.setDate(date.getDate() + 1);
  return date.toISOString();
}

type PlatformActivityItem = { eventId: string; organizationId: string | null; organizationName: string; projectId: string | null; actorUserId: string | null; actorName: string; category: string; action: string; entityType: string; entityId: string; entityName: string; projectName: string | null; description: string; status: string; correlationId: string; createdAt: string };
type PlatformActivityPage = { items: PlatformActivityItem[]; nextCursor: string | null };
const activityCategories = ['All', 'Projects', 'Tasks', 'People', 'Collaboration', 'System'];
const activityCategoryIcon: Record<string, typeof Activity> = { Projects: FolderKanban, Tasks: ListTodo, People: Users, Collaboration: MessageSquare, System: Server };

type ActivityRange = 'today' | '7d' | '30d' | 'all' | 'custom';

function activityDateBounds(range: ActivityRange, from: string, to: string) {
  const now = new Date();
  if (range === 'all') return { from: undefined, to: undefined };
  if (range === 'custom') {
    const start = from ? new Date(`${from}T00:00:00`) : null;
    const end = to ? new Date(`${to}T00:00:00`) : null;
    if (end) {
      const isToday = end.getFullYear() === now.getFullYear() && end.getMonth() === now.getMonth() && end.getDate() === now.getDate();
      if (isToday) {
        if (start && now.getTime() - start.getTime() > 366 * 86_400_000) {
          start.setTime(now.getTime() - 366 * 86_400_000);
        }
        return { from: start?.toISOString(), to: undefined };
      }
      end.setDate(end.getDate() + 1);
    }
    if (start && end && end.getTime() - start.getTime() > 366 * 86_400_000) {
      start.setTime(end.getTime() - 366 * 86_400_000);
    }
    return { from: start?.toISOString(), to: end?.toISOString() };
  }
  const start = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  if (range === '7d') start.setDate(start.getDate() - 6);
  if (range === '30d') start.setDate(start.getDate() - 29);
  return { from: start.toISOString(), to: undefined };
}

function activityDayHeading(value: string) {
  const eventDate = new Date(value);
  const eventDay = new Date(eventDate.getFullYear(), eventDate.getMonth(), eventDate.getDate()).getTime();
  const today = new Date();
  const todayStart = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime();
  if (eventDay === todayStart) return 'Today';
  if (eventDay === todayStart - 86_400_000) return 'Yesterday';
  return eventDate.toLocaleDateString(undefined, { weekday: 'long', month: 'long', day: 'numeric' });
}

function relativeActivityTime(value: string) {
  const elapsedSeconds = Math.max(0, Math.floor((Date.now() - new Date(value).getTime()) / 1000));
  if (elapsedSeconds < 45) return 'just now';
  if (elapsedSeconds < 3600) return `${Math.floor(elapsedSeconds / 60)} min${Math.floor(elapsedSeconds / 60) === 1 ? '' : 's'} ago`;
  if (elapsedSeconds < 86_400) return `${Math.floor(elapsedSeconds / 3600)} hr${Math.floor(elapsedSeconds / 3600) === 1 ? '' : 's'} ago`;
  if (elapsedSeconds < 7 * 86_400) return `${Math.floor(elapsedSeconds / 86_400)} days ago`;
  return new Date(value).toLocaleDateString();
}

function groupActivityByDay(items: PlatformActivityItem[]) {
  const groups: Array<{ label: string; items: PlatformActivityItem[] }> = [];
  for (const item of items) {
    const label = activityDayHeading(item.createdAt);
    const existing = groups[groups.length - 1];
    if (existing?.label === label) existing.items.push(item);
    else groups.push({ label, items: [item] });
  }
  return groups;
}

export function AdminActivity({ projectId: scopedProjectId, organizationId: scopedOrganizationId, embedded = false }: { projectId?: string; organizationId?: string; embedded?: boolean } = {}) {
  const [category, setCategory] = useState('All');
  const [searchInput, setSearchInput] = useState('');
  const [search, setSearch] = useState('');
  const [organizationId, setOrganizationId] = useState(scopedOrganizationId ?? '');
  const [projectId, setProjectId] = useState(scopedProjectId ?? '');
  const [range, setRange] = useState<ActivityRange>('7d');
  const [filtersOpen, setFiltersOpen] = useState(false);
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [cursorStack, setCursorStack] = useState<Array<string | null>>([null]);
  const cursor = cursorStack[cursorStack.length - 1] ?? null;
  const organizations = useQuery({ queryKey: ['admin-activity-organizations'], queryFn: async () => (await api.get<Array<{ id: string; name: string }>>('/admin/organizations')).data, retry: false, enabled: !embedded });
  const projects = useQuery({
    queryKey: ['admin-activity-projects', organizationId],
    queryFn: async () => (await api.get<Array<{ id: string; name: string; status: string; archivedAt: string | null; deletedAt: string | null }>>('/admin/projects', { params: { organizationId, includeTrashed: true } })).data,
    enabled: !embedded && Boolean(organizationId),
    retry: false,
  });
  useEffect(() => {
    const timeout = window.setTimeout(() => { setSearch(searchInput.trim()); setCursorStack([null]); }, 300);
    return () => window.clearTimeout(timeout);
  }, [searchInput]);
  const now = new Date();
  const today = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
  const validationError = range === 'custom'
    ? from && to && from > to
      ? 'The start date must be on or before the end date.'
      : from > today || to > today
        ? 'Activity dates cannot be in the future.'
        : null
    : null;
  const query = useQuery({
    queryKey: ['admin-activity-events', category, search, organizationId, projectId, range, from, to, cursor],
    queryFn: async () => {
      const bounds = activityDateBounds(range, from, to);
      return (await api.get<PlatformActivityPage>('/admin/activity-events', { params: {
        category: category === 'All' ? undefined : category, search: search || undefined,
        organizationId: organizationId || undefined, projectId: projectId || undefined,
        ...bounds, cursor: cursor || undefined, pageSize: 50,
      } })).data;
    },
    enabled: !validationError,
    refetchInterval: 15_000,
    refetchIntervalInBackground: false,
    retry: false,
  });
  const queryErrorMessage = query.error ? errorMessage(query.error) : '';
  const missingActivitySchema = /ActivityEvent|activity_events/i.test(queryErrorMessage);
  const resetPage = () => setCursorStack([null]);
  const hasActiveFilters = Boolean(category !== 'All' || search || organizationId || projectId || range !== 'all');
  const clearFilters = () => { setCategory('All'); setOrganizationId(''); setProjectId(''); setRange('all'); setFrom(''); setTo(''); setSearch(''); setSearchInput(''); resetPage(); };
  const rangeLabels: Record<ActivityRange, string> = { today: 'today', '7d': 'the last 7 days', '30d': 'the last 30 days', all: 'all time', custom: 'the selected dates' };
  const lastUpdated = query.dataUpdatedAt ? relativeActivityTime(new Date(query.dataUpdatedAt).toISOString()) : '';
  return <Box className="admin-platform-page admin-activity-page admin-platform-activity">
    {!embedded && <header className="admin-platform-page-header admin-activity-compact-header"><div className="admin-activity-title-row"><Typography component="h1">Activity</Typography><span className={`admin-activity-live${query.error ? ' is-error' : ''}`}><i/>{query.error ? 'Unavailable' : query.isLoading ? 'Connecting' : 'Live'}<small>{lastUpdated ? `Updated ${lastUpdated}` : 'Checking for updates'}</small></span></div></header>}
    <Box className="admin-activity-filters admin-platform-activity-filters" aria-label="Filter activity">
      <TextField fullWidth className="admin-activity-search" size="small" placeholder="Search people, work, or IDs…" inputProps={{ 'aria-label': 'Search activity, people, work, or IDs' }} value={searchInput} onChange={event => setSearchInput(event.target.value)} InputProps={{ startAdornment: <InputAdornment position="start"><Search size={17}/></InputAdornment> }}/>
      {!embedded && <TextField fullWidth className="admin-activity-organization" select size="small" value={organizationId} SelectProps={{ displayEmpty: true, renderValue: selected => selected ? organizations.data?.find(organization => organization.id === selected)?.name ?? 'Organization' : 'All organizations' }} inputProps={{ 'aria-label': 'Filter by organization' }} onChange={event => { setOrganizationId(event.target.value); setProjectId(''); resetPage(); }}><MenuItem value="">All organizations</MenuItem>{organizations.data?.map(organization => <MenuItem key={organization.id} value={organization.id}>{organization.name}</MenuItem>)}</TextField>}
      {!embedded && <TextField fullWidth className="admin-activity-project" select size="small" value={projectId} disabled={!organizationId || projects.isLoading || Boolean(projects.error)} SelectProps={{ displayEmpty: true, renderValue: selected => selected ? projects.data?.find(project => project.id === selected)?.name ?? 'Project' : organizationId ? 'All projects' : 'Select an organization first' }} inputProps={{ 'aria-label': 'Filter by project' }} onChange={event => { setProjectId(event.target.value); resetPage(); }}><MenuItem value="">All projects</MenuItem>{projects.data?.map(project => <MenuItem key={project.id} value={project.id}>{project.name}{project.deletedAt ? ' · In Trash' : project.archivedAt ? ' · Archived' : ''}</MenuItem>)}</TextField>}
      <TextField fullWidth className="admin-activity-range" select size="small" value={range} SelectProps={{ displayEmpty: true, renderValue: selected => ({ today: 'Today', '7d': 'Last 7 days', '30d': 'Last 30 days', all: 'All time', custom: 'Custom range' } as Record<ActivityRange, string>)[selected as ActivityRange] ?? 'Date range' }} inputProps={{ 'aria-label': 'Filter by date range' }} onChange={event => { const nextRange = event.target.value as ActivityRange; setRange(nextRange); if (nextRange === 'custom') setFiltersOpen(true); resetPage(); }}><MenuItem value="today">Today</MenuItem><MenuItem value="7d">Last 7 days</MenuItem><MenuItem value="30d">Last 30 days</MenuItem><MenuItem value="all">All time</MenuItem><MenuItem value="custom">Custom range</MenuItem></TextField>
      <Button className="admin-activity-filter-toggle" variant="outlined" aria-expanded={filtersOpen} onClick={() => setFiltersOpen(open => !open)} startIcon={<Filter size={16}/>}>More filters</Button>
      <Button className="admin-activity-refresh" aria-label="Refresh activity" title="Refresh activity" variant="outlined" startIcon={query.isFetching ? <CircularProgress size={14}/> : <RefreshCw size={15}/>} disabled={query.isFetching} onClick={() => void query.refetch()}>Refresh</Button>
    </Box>
    {organizationId && projects.error && <Alert severity="error">Unable to load projects for this organization. <Button size="small" onClick={() => void projects.refetch()}>Retry</Button></Alert>}
    {filtersOpen && <Box className="admin-activity-advanced-filters" aria-label="Advanced activity filters"><div><strong>Date range</strong><span>Choose inclusive calendar dates.</span></div><TextField fullWidth type="date" size="small" label="From" value={from} inputProps={{ max: today }} InputLabelProps={{ shrink: true }} onChange={event => { setRange('custom'); setFrom(event.target.value); resetPage(); }}/><TextField fullWidth type="date" size="small" label="To" value={to} inputProps={{ max: today }} InputLabelProps={{ shrink: true }} onChange={event => { setRange('custom'); setTo(event.target.value); resetPage(); }}/></Box>}
    <nav className="activity-category-tabs admin-activity-category-tabs" aria-label="Activity category filters">{activityCategories.map(item => { const Icon = activityCategoryIcon[item] ?? Activity; return <button key={item} className={category === item ? 'active' : ''} aria-pressed={category === item} onClick={() => { setCategory(item); resetPage(); }}><Icon size={15}/>{item}</button>; })}</nav>
    {validationError && <Alert severity="warning" role="alert">{validationError}</Alert>}
    {!validationError && query.isLoading && <div className="admin-health-skeletons" role="status" aria-label="Loading activity"><span/><span/></div>}
    {!validationError && query.error && <Alert severity="error">Unable to load platform activity: {queryErrorMessage}{missingActivitySchema ? ' Confirm migrations 003 and 004 are applied to the API database.' : ''}</Alert>}
    {!validationError && query.data?.items.length === 0 && <section className="admin-activity-empty admin-platform-activity-empty"><span className="admin-activity-empty-icon"><Activity size={21}/></span><Typography component="h2">{hasActiveFilters ? 'No matching activity' : 'Nothing to show yet'}</Typography><p>{hasActiveFilters ? `No events were found for ${rangeLabels[range]}. Adjust your filters or view all activity.` : 'Activity will appear here as people create projects, update tasks, and collaborate.'}</p>{hasActiveFilters && <Button variant="text" onClick={clearFilters}>Clear filters</Button>}</section>}
    {!validationError && query.data && query.data.items.length > 0 && <>
      <div className="admin-activity-day-groups" aria-live="polite">
        {groupActivityByDay(query.data.items).map(group => <section className="admin-activity-day-group" key={group.label}>
          <h2>{group.label}</h2>
          <ol className="activity-timeline admin-platform-activity-timeline admin-platform-activity-day-timeline">
            {group.items.map(item => {
              const Icon = activityCategoryIcon[item.category] ?? Activity;
              const segments = [item.organizationName, item.projectName, item.entityType.toLowerCase() === 'project' ? null : `${item.entityType}: ${item.entityName}`].filter((value): value is string => Boolean(value));
              return <li key={item.eventId}>
                <time className="admin-activity-clock" dateTime={item.createdAt}>{new Date(item.createdAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</time>
                <span className={`activity-timeline-icon category-${item.category.toLowerCase()}`}><Icon size={17}/></span>
                <details className="activity-timeline-content">
                  <summary>
                    <strong>{item.actorName} {item.description}</strong>
                    <span className="admin-activity-event-context">{segments.map((segment, index) => <span className="admin-activity-breadcrumb" key={`${segment}-${index}`}>{index > 0 && <ChevronRight size={13}/>}<span>{segment}</span></span>)}</span>
                    <small><span className="admin-activity-actor-avatar">{item.actorName.split(' ').map(part => part[0]).slice(0, 2).join('').toUpperCase()}</span>{item.actorName}<i/><time dateTime={item.createdAt}>{relativeActivityTime(item.createdAt)}</time></small>
                    <span className="admin-activity-expand">Details</span>
                  </summary>
                  <div className="activity-event-details">
                    <span>{item.organizationId ? `Organization: ${item.organizationName} (${item.organizationId})` : 'Scope: Platform'}</span>
                    {(item.projectName || item.projectId) && <span>Project: {item.projectName ?? 'Unknown project'}{item.projectId ? ` (${item.projectId})` : ''}</span>}
                    <span>Actor: {item.actorName}{item.actorUserId ? ` (${item.actorUserId})` : ''}</span>
                    <span>Action: {item.action} · {item.status}</span>
                    <span>Target: {item.entityType} · {item.entityName}{item.entityId !== '00000000-0000-0000-0000-000000000000' ? ` (${item.entityId})` : ''}</span>
                    <span>Request: {item.correlationId}</span>
                  </div>
                </details>
              </li>;
            })}
          </ol>
        </section>)}
      </div>
      <div className="admin-activity-pagination"><span>Page {cursorStack.length} · {query.data.items.length} events</span><div><Button variant="text" disabled={cursorStack.length <= 1 || query.isFetching} onClick={() => setCursorStack(stack => stack.slice(0, -1))}>Previous</Button><Button variant="outlined" disabled={!query.data.nextCursor || query.isFetching} onClick={() => { if (query.data?.nextCursor) setCursorStack(stack => [...stack, query.data.nextCursor]); }}>Next page</Button></div></div>
    </>}
  </Box>;
}

export function AdminAuditTrail() {
  const [action, setAction] = useState('');
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [cursorStack, setCursorStack] = useState<Array<string | null>>([null]);
  const cursor = cursorStack[cursorStack.length - 1];
  const fromBound = auditDateBound(from);
  const toBound = auditDateBound(to, true);
  const query = useQuery({
    queryKey: ['admin-audit-events', action, from, to, cursor],
    queryFn: async () => (await api.get<AuditPage>('/admin/audit-events', { params: { action: action || undefined, from: fromBound, to: toBound, cursor: cursor || undefined, pageSize: 50 } })).data,
    retry: false,
  });
  const resetPage = () => setCursorStack([null]);
  const validationError = from && to && from > to ? 'The start date must be on or before the end date.' : null;
  const error = query.error ? errorMessage(query.error) : null;
  const updateFilter = (update: () => void) => { update(); resetPage(); };
  return <Box className="admin-platform-page admin-activity-page admin-audit-trail">
    <header className="admin-platform-page-header admin-audit-header"><div><Typography component="h1">Audit Trail</Typography><p>Recorded administrative account changes.</p></div><Button variant="outlined" className="admin-audit-refresh" startIcon={query.isFetching ? <CircularProgress size={14}/> : <RefreshCw size={15}/>} disabled={query.isFetching} onClick={() => void query.refetch()}>Refresh</Button></header>
    <Box className="admin-activity-filters admin-audit-filters" aria-label="Filter audit events">
      <TextField className="admin-audit-action" select size="small" value={action} SelectProps={{ displayEmpty: true, renderValue: selected => selected ? actionLabels[String(selected)] ?? String(selected) : 'All recorded actions' }} inputProps={{ 'aria-label': 'Filter by action' }} onChange={event => updateFilter(() => setAction(event.target.value))}>
        <MenuItem value="">All recorded actions</MenuItem><MenuItem value="user.create">User created</MenuItem><MenuItem value="user.suspend">User suspended</MenuItem><MenuItem value="user.delete.permanent">User permanently deleted</MenuItem>
      </TextField>
      <TextField className="admin-audit-date" type="date" size="small" label="From" inputProps={{ 'aria-label': 'From date' }} value={from} InputLabelProps={{ shrink: true }} onChange={event => updateFilter(() => setFrom(event.target.value))}/>
      <TextField className="admin-audit-date" type="date" size="small" label="To" inputProps={{ 'aria-label': 'To date' }} value={to} InputLabelProps={{ shrink: true }} onChange={event => updateFilter(() => setTo(event.target.value))}/>
      <span>Up to 50 events per page. The date range includes both selected dates.</span>
    </Box>
    {validationError && <Alert severity="warning" role="alert">{validationError}</Alert>}
    {!validationError && query.isLoading && <div className="admin-health-skeletons" role="status" aria-label="Loading activity"><span/><span/></div>}
    {!validationError && query.error && <Alert severity="error">Unable to load administrative activity{error ? `: ${error}` : '.'} If this is a deployment setup issue, confirm migration 002 is applied, then refresh.</Alert>}
    {!validationError && query.data?.items.length === 0 && <section className="admin-activity-empty"><span className="admin-activity-empty-icon"><Activity size={21}/></span><Typography component="h2">No matching activity</Typography><p>No recorded account changes match this date range and action.</p><span className="admin-activity-note"><CircleHelp size={14}/> Only successful user creation, suspension, and permanent deletion are recorded. To verify the setup, confirm the frontend uses the intended API and that migration 002 was applied to that API’s database. This audit feed does not backfill earlier actions.</span></section>}
    {!validationError && query.data && query.data.items.length > 0 && <>
      <div className="admin-activity-list" aria-live="polite">{query.data.items.map(event => <Card className="admin-activity-event" key={event.eventId}><CardContent>
        <span className="admin-activity-event-icon"><Activity size={17}/></span><div className="admin-activity-event-main"><strong>{actionLabels[event.action] ?? event.action}</strong><span>{event.target.displayName} <small>({event.target.type}: {event.target.id})</small></span><small>Outcome: {event.outcome}</small>{event.reason && <small>Reason: {event.reason}</small>}</div><div className="admin-activity-event-meta"><span>By {event.actor.displayName}</span><small>Administrator ID: {event.actor.id}</small><time dateTime={event.occurredAt}>{new Date(event.occurredAt).toLocaleString()}</time><small>Request {event.correlationId}</small></div>
      </CardContent></Card>)}</div>
      <div className="admin-activity-pagination"><span>Page {cursorStack.length} · {query.data.items.length} events</span><div><Button variant="text" disabled={cursorStack.length <= 1 || query.isFetching} onClick={() => setCursorStack(stack => stack.slice(0, -1))}>Previous</Button> <Button variant="outlined" disabled={!query.data.nextCursor || query.isFetching} onClick={() => { if (query.data?.nextCursor) setCursorStack(stack => [...stack, query.data!.nextCursor]); }}>Next page</Button></div></div>
    </>}
  </Box>;
}
export function AdminHealth() {
  const query = useQuery({
    queryKey: ['admin-health'],
    queryFn: async () => {
      const [apiResult, readyResult] = await Promise.allSettled([
        api.get<{ status: string }>('/health'),
        api.get<{ status: string; entries?: Record<string, { status: string }> }>('/ready'),
      ]);
      const apiStatus = apiResult.status === 'fulfilled' ? apiResult.value.data.status || 'Unknown' : 'Unavailable';
      const databaseStatus = readyResult.status === 'fulfilled'
        ? readyResult.value.data.entries?.database?.status ?? readyResult.value.data.status ?? 'Unknown'
        : 'Unavailable';
      return { api: apiStatus, database: databaseStatus, checkedAt: new Date().toISOString() };
    },
    retry: false,
    refetchInterval: 30_000, // refresh platform health every 30 seconds
  });

  const statusClass = (status: string) => {
    const normalized = status.toLowerCase();
    if (normalized === 'healthy' || normalized === 'ok') return 'healthy';
    if (normalized === 'degraded') return 'degraded';
    if (normalized === 'unhealthy') return 'unhealthy';
    return 'unknown';
  };

  return (
    <Box className="admin-platform-page admin-health-page">
      <header className="admin-platform-page-header"><div><Typography component="h1">System health</Typography><p>Current availability of TaskFlow services.</p></div>
        <Button className="admin-health-refresh" variant="outlined" onClick={() => void query.refetch()} disabled={query.isFetching}>{query.isFetching && <CircularProgress size={14}/>}Refresh</Button>
      </header>
      {query.error && (
        <Alert severity="error" className="admin-health-error">
          Unable to check the current health status.
        </Alert>
      )}
      {query.isLoading && <div className="admin-health-skeletons" role="status" aria-label="Checking service health"><span/><span/></div>}
      {query.data && (
        <Box className="admin-health-grid" aria-live="polite">
          {([['API', query.data.api], ['Database', query.data.database]] as [string, string][]).map(
            ([label, status]) => (
                <Card key={label} className={`admin-health-card ${statusClass(status)}`}>
                <CardContent className="admin-health-card-content">
                  <span className="admin-health-service-icon">{statusClass(status) === 'unknown' ? <CircleHelp size={18}/> : label === 'API' ? <HeartPulse size={18}/> : <Database size={18}/>}</span>
                  <div className="admin-health-service-copy"><span>{label}</span><strong>{status}</strong></div>
                  <span className="admin-health-indicator" aria-hidden="true"/>
                </CardContent>
              </Card>
            ),
          )}
        </Box>
      )}
      {query.data?.checkedAt && <Typography className="admin-health-checked">Last checked {new Date(query.data.checkedAt).toLocaleString()}</Typography>}
    </Box>
  );
}
export function AdminSettings() {
  const settings = [
    { label: 'Application', value: 'TaskFlow', detail: 'Platform workspace management', icon: Blocks },
    { label: 'Environment', value: import.meta.env.MODE, detail: 'Frontend build environment', icon: Server },
    { label: 'Appearance', value: 'Personal preference', detail: 'Theme is saved in this browser', icon: Palette },
    { label: 'Runtime access', value: 'Managed deployment-side', detail: 'Credentials are not exposed in this interface', icon: LockKeyhole },
  ];
  return <Box className="admin-platform-page admin-settings-page">
    <header className="admin-platform-page-header"><div><Typography component="h1">Platform settings</Typography><p>Application information and interface preferences.</p></div></header>
    <section className="admin-settings-grid" aria-label="Platform settings information">
      {settings.map(({ label, value, detail, icon: Icon }) => <Card key={label} className="admin-settings-card"><CardContent>
        <span className="admin-settings-icon"><Icon size={17}/></span><div className="admin-settings-copy"><span>{label}</span><strong>{value}</strong><small>{detail}</small></div>
      </CardContent></Card>)}
    </section>
    <p className="admin-settings-note">These settings are informational. Account security and runtime configuration are managed through their existing flows.</p>
  </Box>;
}
