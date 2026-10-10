import { useState, type ReactNode } from 'react';
import { Alert, Avatar, Box, Button, Card, CardContent, Chip, CircularProgress, Divider, LinearProgress, Table, TableBody, TableCell, TableHead, TableRow, Tabs, Tab, Typography } from '@mui/material';
import { Activity, AlertTriangle, ArrowLeft, Building2, CalendarDays, CheckCircle2, Clock3, FolderKanban, ListTodo, RefreshCw, Users } from 'lucide-react';
import { useQuery } from '@tanstack/react-query';
import { api, dateLabel } from './api';
import type { AdminProjectDetails as ProjectDetailsData, AdminProjectMember, AdminProjectPage, AdminProjectTask } from './types/admin';
import { AdminActivity } from './AdminPlatform';

type ProjectActivityItem = { eventId: string; actorName: string; description: string; category: string; createdAt: string; projectName: string | null };
type ProjectActivityPage = { items: ProjectActivityItem[]; nextCursor: string | null };

function errorText(error: unknown) {
  return (error as { response?: { data?: { message?: string } } })?.response?.data?.message ?? 'The project data could not be loaded.';
}

function PageState({ error, retry }: { error: unknown; retry: () => void }) {
  return <Alert severity="error" action={<Button color="inherit" size="small" onClick={retry}>Retry</Button>}>{errorText(error)}</Alert>;
}

function displayStatus(value: string) {
  return value.replace(/_/g, ' ').toLowerCase().replace(/\b\w/g, letter => letter.toUpperCase());
}

function initials(value: string) {
  return value.split(/\s+/).filter(Boolean).slice(0, 2).map(part => part[0]).join('').toUpperCase() || '?';
}

export default function AdminProjectDetails({ projectId, organizationIdHint, navigate }: { projectId: string; organizationIdHint?: string; navigate: (route: string) => void }) {
  const [tab, setTab] = useState(0);
  const [memberPage, setMemberPage] = useState(1);
  const [taskPage, setTaskPage] = useState(1);
  const details = useQuery({
    queryKey: ['admin-project-details', projectId],
    queryFn: async () => (await api.get<ProjectDetailsData>(`/admin/projects/${projectId}/details`)).data,
    refetchInterval: 15_000,
  });
  const project = details.data;
  const members = useQuery({
    queryKey: ['admin-project-members', projectId, memberPage],
    queryFn: async () => (await api.get<AdminProjectPage<AdminProjectMember>>(`/admin/projects/${projectId}/members`, { params: { page: memberPage, pageSize: 50 } })).data,
    enabled: tab === 1,
  });
  const tasks = useQuery({
    queryKey: ['admin-project-tasks', projectId, taskPage],
    queryFn: async () => (await api.get<AdminProjectPage<AdminProjectTask>>(`/admin/projects/${projectId}/tasks`, { params: { page: taskPage, pageSize: 50 } })).data,
    enabled: tab === 2,
  });
  const activityPreview = useQuery({
    queryKey: ['admin-project-activity-preview', projectId],
    queryFn: async () => (await api.get<ProjectActivityPage>('/admin/activity-events', { params: { organizationId: project?.organizationId, projectId, pageSize: 4 } })).data,
    enabled: Boolean(project),
    refetchInterval: 15_000,
  });
  const lifecycleLabel = project?.deletedAt ? 'In Trash · historical' : project?.archivedAt ? 'Archived · historical' : project ? displayStatus(project.status) : 'Project';
  const isHistorical = Boolean(project?.archivedAt || project?.deletedAt);
  const returnOrganizationId = project?.organizationId ?? organizationIdHint;
  const projectsRoute = `admin/projects${returnOrganizationId ? `?organizationId=${encodeURIComponent(returnOrganizationId)}` : ''}`;

  return <Box className="admin-platform-page admin-project-details">
    <Button className="admin-project-back" startIcon={<ArrowLeft size={16}/>} onClick={() => navigate(projectsRoute)}>Back to projects</Button>
    {details.isLoading && <Box className="admin-project-loading"><CircularProgress size={28}/><Typography color="text.secondary">Loading project details…</Typography></Box>}
    {details.error && <PageState error={details.error} retry={() => void details.refetch()}/>}
    {project && <>
      <header className="admin-project-hero">
        <div className="admin-project-hero-topline"><span className="admin-project-eyebrow"><FolderKanban size={14}/> PROJECT DETAILS</span><Button className="admin-project-refresh" variant="outlined" startIcon={details.isFetching ? <CircularProgress size={14}/> : <RefreshCw size={14}/>} disabled={details.isFetching} onClick={() => void details.refetch()}>Refresh</Button></div>
        <div className="admin-project-hero-main">
          <div className="admin-project-mark"><FolderKanban size={24}/></div>
          <div className="admin-project-heading-copy">
            <Typography variant="h4" component="h1">{project.name}</Typography>
            <Button className="admin-project-org-link" startIcon={<Building2 size={14}/>} onClick={() => navigate(projectsRoute)}>{project.organizationName}</Button>
          </div>
          <Chip className={`admin-project-status${isHistorical ? ' is-historical' : ''}`} label={lifecycleLabel} icon={isHistorical ? <Clock3 size={14}/> : <CheckCircle2 size={14}/>} />
        </div>
        {isHistorical && <Alert className="admin-project-history-note" severity="info">Historical project · viewing does not restore or change its lifecycle.</Alert>}
      </header>

      <Box className="admin-project-metrics">
        <Metric icon={<Users size={18}/>} label="Active members" value={project.memberCount.toLocaleString()} detail="Current project access" tone="violet" />
        <Metric icon={<ListTodo size={18}/>} label="Eligible tasks" value={project.hasTasks ? project.totalEligibleTasks.toLocaleString() : 'No tasks'} detail={project.hasTasks ? `${project.completedTasks.toLocaleString()} completed` : 'No task activity yet'} tone="blue" />
        <Metric icon={<FolderKanban size={18}/>} label="Progress" value={project.progressPercent == null ? '—' : `${project.progressPercent}%`} detail={project.hasTasks ? `${project.outstandingTaskCount.toLocaleString()} outstanding` : 'Awaiting first task'} tone="green" progress={project.progressPercent} />
        <Metric icon={<AlertTriangle size={18}/>} label="Overdue" value={project.overdueTaskCount.toLocaleString()} detail="Based on organization timezone" tone={project.overdueTaskCount ? 'amber' : 'neutral'} />
      </Box>

      <Tabs className="admin-project-tabs" value={tab} onChange={(_, value: number) => setTab(value)} aria-label="Project detail sections" variant="scrollable" scrollButtons="auto">
        <Tab label="Overview"/><Tab label={`Members${project.memberCount ? ` · ${project.memberCount}` : ''}`}/><Tab label={`Tasks${project.totalEligibleTasks ? ` · ${project.totalEligibleTasks}` : ''}`}/><Tab label="Activity"/>
      </Tabs>

      {tab === 0 && <Box className="admin-project-overview-grid">
        <Card className="admin-project-info-card">
          <CardContent>
            <div className="admin-project-section-heading"><div><Typography variant="h6">Project overview</Typography><Typography variant="body2">Key ownership and lifecycle information</Typography></div><span className="admin-project-section-icon"><CalendarDays size={17}/></span></div>
            <Divider/>
            <dl className="admin-project-facts">
              <div><dt>Organization</dt><dd>{project.organizationName}</dd></div>
              <div><dt>Project owner</dt><dd>{project.ownerName ?? 'No owner listed'}</dd></div>
              <div><dt>Status</dt><dd><Chip size="small" label={lifecycleLabel}/></dd></div>
              <div><dt>Task completion</dt><dd>{project.hasTasks ? `${project.completedTasks.toLocaleString()} of ${project.totalEligibleTasks.toLocaleString()} completed` : 'No tasks'}</dd></div>
              <div><dt>Due date</dt><dd>{project.dueDate ? dateLabel(project.dueDate) : 'No due date'}</dd></div>
              <div><dt>Created</dt><dd>{dateLabel(project.createdAt)}</dd></div>
            </dl>
          </CardContent>
        </Card>
        <Card className="admin-project-activity-card">
          <CardContent>
            <div className="admin-project-section-heading"><div><Typography variant="h6">Recent activity</Typography><Typography variant="body2">Latest recorded changes in this project</Typography></div><Button size="small" endIcon={<ArrowLeft className="admin-project-view-all-icon" size={14}/>} onClick={() => setTab(3)}>View all</Button></div>
            {activityPreview.isLoading && <div className="admin-project-activity-state"><CircularProgress size={20}/><span>Loading activity…</span></div>}
            {activityPreview.error && <PageState error={activityPreview.error} retry={() => void activityPreview.refetch()}/>}
            {activityPreview.data && (activityPreview.data.items.length ? <ol className="admin-project-activity-preview">{activityPreview.data.items.slice(0, 4).map(event => <li key={event.eventId}><span className={`admin-project-event-mark category-${event.category.toLowerCase()}`}><Activity size={15}/></span><div><strong>{event.actorName} {event.description}</strong><span>{event.projectName ?? project.name}</span></div><time dateTime={event.createdAt}>{new Date(event.createdAt).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' })}</time></li>)}</ol> : <div className="admin-project-activity-empty"><Activity size={19}/><span>No activity has been recorded for this project yet.</span></div>)}
          </CardContent>
        </Card>
      </Box>}

      {tab === 1 && <Card className="admin-project-data-card"><CardContent>
        <SectionHeading title="Project members" subtitle="Read-only membership and access overview" count={members.data?.totalCount ?? project.memberCount}/>
        {members.isLoading && <div className="admin-project-table-state"><CircularProgress size={22}/></div>}
        {members.error && <PageState error={members.error} retry={() => void members.refetch()}/>}
        {members.data && (members.data.items.length ? <><div className="admin-project-table-wrap"><Table size="small" aria-label="Project members"><TableHead><TableRow><TableCell>Member</TableCell><TableCell>Project role</TableCell><TableCell>Membership</TableCell><TableCell>Account</TableCell><TableCell>Joined</TableCell></TableRow></TableHead><TableBody>{members.data.items.map((member, index) => <TableRow key={`${member.displayName}-${index}`}><TableCell><span className="admin-project-person"><Avatar>{initials(member.displayName)}</Avatar><strong>{member.displayName}</strong></span></TableCell><TableCell><Chip size="small" className="admin-project-role-chip" label={displayStatus(member.projectRole)}/></TableCell><TableCell>{displayStatus(member.projectMembershipStatus)}{member.organizationMembershipStatus ? ` · organization ${displayStatus(member.organizationMembershipStatus)}` : ''}</TableCell><TableCell><span className={`admin-project-account-status ${member.accountStatus.toLowerCase()}`}><i/>{displayStatus(member.accountStatus)}</span></TableCell><TableCell>{dateLabel(member.joinedAt)}</TableCell></TableRow>)}</TableBody></Table></div><PageButtons page={memberPage} total={members.data.totalCount} pageSize={members.data.pageSize} loading={members.isFetching} onPage={setMemberPage}/></> : <EmptyState title="No project members" detail="No membership records are available for this project."/>)}
      </CardContent></Card>}

      {tab === 2 && <Card className="admin-project-data-card"><CardContent>
        <SectionHeading title="Project tasks" subtitle="Non-deleted top-level tasks" count={tasks.data?.totalCount ?? project.totalEligibleTasks}/>
        {tasks.isLoading && <div className="admin-project-table-state"><CircularProgress size={22}/></div>}
        {tasks.error && <PageState error={tasks.error} retry={() => void tasks.refetch()}/>}
        {tasks.data && (tasks.data.items.length ? <><div className="admin-project-table-wrap"><Table size="small" aria-label="Project tasks"><TableHead><TableRow><TableCell>Task</TableCell><TableCell>Status</TableCell><TableCell>Priority</TableCell><TableCell>Assignees</TableCell><TableCell>Due date</TableCell></TableRow></TableHead><TableBody>{tasks.data.items.map(task => <TableRow key={task.id}><TableCell><strong className="admin-project-task-title">{task.title}</strong></TableCell><TableCell><Chip size="small" className={`admin-project-task-status ${task.status.toLowerCase().replace(/_/g, '-')}`} label={displayStatus(task.status)}/></TableCell><TableCell>{displayStatus(task.priority)}</TableCell><TableCell>{task.effectiveAssigneeCount.toLocaleString()}</TableCell><TableCell>{task.dueDate ? dateLabel(task.dueDate) : 'No due date'}</TableCell></TableRow>)}</TableBody></Table></div><PageButtons page={taskPage} total={tasks.data.totalCount} pageSize={tasks.data.pageSize} loading={tasks.isFetching} onPage={setTaskPage}/></> : <EmptyState title="No tasks yet" detail="Non-deleted top-level tasks will appear here."/>)}
      </CardContent></Card>}

      {tab === 3 && <Card className="admin-project-data-card admin-project-full-activity"><CardContent><SectionHeading title="Project activity" subtitle="A chronological record of activity for this project"/><AdminActivity projectId={project.projectId} organizationId={project.organizationId} embedded/></CardContent></Card>}
    </>}
  </Box>;
}

function Metric({ icon, label, value, detail, tone, progress }: { icon: ReactNode; label: string; value: string; detail: string; tone: string; progress?: number | null }) {
  return <Card className={`admin-project-metric tone-${tone}`}><CardContent><div className="admin-project-metric-top"><span className="admin-project-metric-icon">{icon}</span><Typography variant="caption">{label}</Typography></div><strong className="admin-project-metric-value">{value}</strong><span className="admin-project-metric-detail">{detail}</span>{progress != null && <LinearProgress className="admin-project-progress-line" variant="determinate" value={progress}/>}</CardContent></Card>;
}

function SectionHeading({ title, subtitle, count }: { title: string; subtitle: string; count?: number }) {
  return <div className="admin-project-section-heading"><div><Typography variant="h6">{title}</Typography><Typography variant="body2">{subtitle}</Typography></div>{count != null && <Chip size="small" label={`${count.toLocaleString()} ${count === 1 ? 'record' : 'records'}`}/>}</div>;
}

function EmptyState({ title, detail }: { title: string; detail: string }) {
  return <div className="admin-project-empty"><span><FolderKanban size={20}/></span><strong>{title}</strong><p>{detail}</p></div>;
}

function PageButtons({ page, total, pageSize, loading, onPage }: { page: number; total: number; pageSize: number; loading: boolean; onPage: (page: number) => void }) {
  const pages = Math.max(1, Math.ceil(total / pageSize));
  return <div className="admin-project-pagination"><Typography variant="caption">Page {page} of {pages} · {total.toLocaleString()} records</Typography><div><Button size="small" disabled={page <= 1 || loading} onClick={() => onPage(page - 1)}>Previous</Button><Button size="small" variant="outlined" disabled={page >= pages || loading} onClick={() => onPage(page + 1)}>Next</Button></div></div>;
}
