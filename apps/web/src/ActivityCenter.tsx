import { Alert, Button, CircularProgress, MenuItem, TextField } from '@mui/material';
import { Activity, ArrowRight, RefreshCw, Search } from 'lucide-react';
import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { api, errorMessage, formatDisplayName } from './api';

type ActivityItem = {
  eventId: string; organizationId: string; organizationName: string; actorUserId: string; actorName: string;
  category: string; action: string; entityType: string; entityId: string;
  entityName: string; description: string; status: string; correlationId: string; createdAt: string;
};
type ActivityPage = { items: ActivityItem[]; nextCursor: string | null };

const categories = ['All', 'Projects', 'Tasks', 'People', 'Collaboration'];

export default function ActivityCenter({ organizationId }: { organizationId: string }) {
  const [category, setCategory] = useState('All');
  const [searchInput, setSearchInput] = useState('');
  const [search, setSearch] = useState('');
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [cursorStack, setCursorStack] = useState<Array<string | null>>([null]);
  const cursor = cursorStack[cursorStack.length - 1] ?? null;
  const fromBound = from ? new Date(`${from}T00:00:00Z`).toISOString() : undefined;
  const toBound = to ? new Date(`${to}T00:00:00Z`).toISOString() : undefined;
  const query = useQuery({
    queryKey: ['activity-center', organizationId, category, search, cursor],
    enabled: Boolean(organizationId),
    queryFn: async () => (await api.get<ActivityPage>('/activity', { params: {
      organizationId, category: category === 'All' ? undefined : category,
      search: search || undefined, from: fromBound,
      to: toBound,
      cursor: cursor || undefined, pageSize: 30,
    } })).data,
    refetchInterval: 10_000,
    refetchIntervalInBackground: false,
    retry: false,
  });

  const resetPages = () => setCursorStack([null]);
  const applySearch = () => { setSearch(searchInput.trim()); resetPages(); };
  return <section className="activity-center">
    <header className="activity-center-header">
      <div><h1>Activity</h1><p>See important actions and changes across your workspace.</p></div>
      <Button variant="outlined" startIcon={query.isFetching ? <CircularProgress size={14}/> : <RefreshCw size={15}/>} disabled={query.isFetching} onClick={() => void query.refetch()}>Refresh</Button>
    </header>
    <div className="activity-center-controls">
      <label className="search-field"><Search size={17}/><input aria-label="Search activity" placeholder="Search activity…" value={searchInput} onChange={event => setSearchInput(event.target.value)} onKeyDown={event => { if (event.key === 'Enter') applySearch(); }}/></label>
      <Button variant="outlined" onClick={applySearch}>Search</Button>
      <TextField select size="small" label="Category" value={category} onChange={event => { setCategory(event.target.value); resetPages(); }} sx={{ minWidth: 170 }}>
        {categories.map(item => <MenuItem key={item} value={item}>{item}</MenuItem>)}
      </TextField>
      <TextField type="date" size="small" label="From" value={from} InputLabelProps={{ shrink: true }} onChange={event => { setFrom(event.target.value); resetPages(); }}/>
      <TextField type="date" size="small" label="To" value={to} InputLabelProps={{ shrink: true }} onChange={event => { setTo(event.target.value); resetPages(); }}/>
      <span>Latest first · refreshes every 10 seconds</span>
    </div>
    <nav className="activity-category-tabs" aria-label="Activity category filters">
      {categories.map(item => <button key={item} className={category === item ? 'active' : ''} aria-pressed={category === item} onClick={() => { setCategory(item); resetPages(); }}>{item}</button>)}
    </nav>
    {query.isLoading && <div className="activity-center-state" role="status">Loading workspace activity…</div>}
    {query.error && <Alert severity="error">Unable to load activity: {errorMessage(query.error)} Confirm migration 003 is applied to the API database, then refresh.</Alert>}
    {query.data?.items.length === 0 && <div className="activity-center-empty"><Activity size={23}/><h2>No activity yet</h2><p>Project, task, collaboration, and member changes will appear here as they happen.</p></div>}
    {query.data && query.data.items.length > 0 && <>
      <ol className="activity-timeline" aria-live="polite">
        {query.data.items.map(item => <li key={item.eventId}>
          <span className="activity-timeline-icon"><Activity size={17}/></span>
          <details className="activity-timeline-content"><summary><strong>{item.description}</strong><span>{item.category} · {item.organizationName} · {item.entityType}: {item.entityName}</span><small>{item.actorName} · {new Date(item.createdAt).toLocaleString()}</small></summary><div className="activity-event-details"><span>Actor: {item.actorName} ({item.actorUserId})</span><span>Organization: {item.organizationName} ({item.organizationId})</span><span>Event: {item.action} · {item.status}</span><span>Target: {item.entityType} · {item.entityId}</span><span>Request: {item.correlationId}</span></div></details>
        </li>)}
      </ol>
      <div className="activity-center-pagination"><span>Page {cursorStack.length} · {query.data.items.length} events</span><div><Button disabled={cursorStack.length <= 1 || query.isFetching} onClick={() => setCursorStack(stack => stack.slice(0, -1))}>Previous</Button><Button variant="outlined" disabled={!query.data.nextCursor || query.isFetching} onClick={() => { if (query.data?.nextCursor) setCursorStack(stack => [...stack, query.data.nextCursor]); }}>Next page</Button></div></div>
    </>}
  </section>;
}

export function ActivityWidget({ organizationId, navigate }: { organizationId: string; navigate: (route: string) => void }) {
  const query = useQuery({
    queryKey: ['activity-center-widget', organizationId],
    enabled: Boolean(organizationId),
    queryFn: async () => (await api.get<ActivityPage>('/activity', { params: { organizationId, pageSize: 5 } })).data,
    refetchInterval: 10_000,
    refetchIntervalInBackground: false,
  });
  return <section className="activity-widget">
    <header><h2>Recent activity</h2><button className="link-button" onClick={() => navigate('activity')}>View all <ArrowRight size={14}/></button></header>
    {query.data?.items.length ? query.data.items.map(item => {
      const actorName = formatDisplayName(item.actorName);
      const startsWithActor = item.description.slice(0, item.actorName.length).toLocaleLowerCase() === item.actorName.toLocaleLowerCase();
      const description = startsWithActor ? actorName + item.description.slice(item.actorName.length) : item.description;
      return <article key={item.eventId}><strong>{description}</strong><small>{actorName} · {new Date(item.createdAt).toLocaleString()}</small></article>;
    }) : <p className="muted">{query.isLoading ? 'Loading activity…' : query.error ? 'Activity is temporarily unavailable.' : 'No recent activity yet.'}</p>}
  </section>;
}
