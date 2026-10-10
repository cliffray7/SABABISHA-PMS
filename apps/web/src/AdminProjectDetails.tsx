import { useState, type ReactNode } from 'react';
import { Alert, Box, Button, Card, CardContent, Chip, CircularProgress, Table, TableBody, TableCell, TableHead, TableRow, Tabs, Tab, Typography } from '@mui/material';
import { ArrowLeft, Building2, Clock3, FolderKanban, ListTodo, Users } from 'lucide-react';
import { useQuery } from '@tanstack/react-query';
import { api, dateLabel } from './api';
import type { AdminProjectDetails as ProjectDetailsData, AdminProjectMember, AdminProjectPage, AdminProjectTask } from './types/admin';
import { AdminActivity } from './AdminPlatform';

function errorText(error: unknown) {
  return (error as { response?: { data?: { message?: string } } })?.response?.data?.message ?? 'The project data could not be loaded.';
}

function PageState({ error, retry }: { error: unknown; retry: () => void }) {
  return <Alert severity="error" action={<Button color="inherit" size="small" onClick={retry}>Retry</Button>}>{errorText(error)}</Alert>;
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
  const project = details.data;
  const lifecycleLabel = project?.deletedAt ? 'In Trash · historical' : project?.archivedAt ? 'Archived · historical' : project?.status ?? 'Project';
  const returnOrganizationId = project?.organizationId ?? organizationIdHint;
  const projectsRoute = `admin/projects${returnOrganizationId ? `?organizationId=${encodeURIComponent(returnOrganizationId)}` : ''}`;

  return <Box className="admin-platform-page admin-project-details">
    <Button startIcon={<ArrowLeft size={16}/>} onClick={() => navigate(projectsRoute)} sx={{ mb: 1 }}>Back to projects</Button>
    {details.isLoading && <Box sx={{ py: 8, display: 'flex', justifyContent: 'center' }}><CircularProgress size={28}/></Box>}
    {details.error && <PageState error={details.error} retry={() => void details.refetch()}/>}
    {project && <>
      <header className="admin-platform-page-header"><Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 2, flexWrap: 'wrap' }}><Box><Typography variant="h4" component="h1">{project.name}</Typography><Button size="small" startIcon={<Building2 size={14}/>} onClick={() => navigate(`admin/projects?organizationId=${encodeURIComponent(project.organizationId)}`)}>{project.organizationName}</Button></Box><Chip label={lifecycleLabel} color={project.deletedAt ? 'default' : project.archivedAt ? 'default' : 'success'} variant="outlined"/></Box></header>
      <Tabs value={tab} onChange={(_, value: number) => setTab(value)} aria-label="Project detail sections" sx={{ borderBottom: 1, borderColor: 'divider', mb: 2 }}>
        <Tab label="Overview"/><Tab label={`Members (${project.memberCount})`}/><Tab label={`Tasks (${project.totalEligibleTasks})`}/><Tab label="Activity"/>
      </Tabs>
      {tab === 0 && <>
        {(project.archivedAt || project.deletedAt) && <Alert severity="info" sx={{ mb: 2 }}>This is a historical project record. Viewing it does not restore or change its lifecycle.</Alert>}
        <Box sx={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: 1.5, mb: 2 }}>
          <Metric icon={<Users size={17}/>} label="Active members" value={project.memberCount.toLocaleString()}/>
          <Metric icon={<ListTodo size={17}/>} label="Tasks" value={project.hasTasks ? project.totalEligibleTasks.toLocaleString() : 'No tasks'}/>
          <Metric icon={<FolderKanban size={17}/>} label="Progress" value={project.progressPercent == null ? '—' : `${project.progressPercent}%`}/>
          <Metric icon={<Clock3 size={17}/>} label="Overdue" value={project.overdueTaskCount.toLocaleString()}/>
        </Box>
        <Card><CardContent><Typography variant="h6" sx={{ mb: 1 }}>Project overview</Typography><Box component="dl" sx={{ display: 'grid', gridTemplateColumns: 'minmax(120px, 180px) 1fr', gap: 1, m: 0, '& dt': { color: 'text.secondary' }, '& dd': { m: 0, fontWeight: 500 } }}>
          <dt>Organization</dt><dd>{project.organizationName}</dd><dt>Owner</dt><dd>{project.ownerName ?? 'No owner listed'}</dd><dt>Status</dt><dd>{lifecycleLabel}</dd><dt>Completed tasks</dt><dd>{project.completedTasks} of {project.totalEligibleTasks}</dd><dt>Outstanding tasks</dt><dd>{project.outstandingTaskCount}</dd><dt>Due date</dt><dd>{project.dueDate ? dateLabel(project.dueDate) : 'No due date'}</dd><dt>Created</dt><dd>{dateLabel(project.createdAt)}</dd>
        </Box></CardContent></Card>
      </>}
      {tab === 1 && <Card><CardContent><Typography variant="h6" sx={{ mb: 1 }}>Project members</Typography>{members.isLoading && <CircularProgress size={22}/ >}{members.error && <PageState error={members.error} retry={() => void members.refetch()}/ >}{members.data && (members.data.items.length ? <><Table size="small" aria-label="Project members"><TableHead><TableRow><TableCell>Member</TableCell><TableCell>Project role</TableCell><TableCell>Membership</TableCell><TableCell>Account</TableCell><TableCell>Joined</TableCell></TableRow></TableHead><TableBody>{members.data.items.map((member, index) => <TableRow key={`${member.displayName}-${index}`}><TableCell>{member.displayName}</TableCell><TableCell>{member.projectRole.replace(/_/g, ' ')}</TableCell><TableCell>{member.projectMembershipStatus}{member.organizationMembershipStatus ? ` · organization ${member.organizationMembershipStatus}` : ''}</TableCell><TableCell>{member.accountStatus}</TableCell><TableCell>{dateLabel(member.joinedAt)}</TableCell></TableRow>)}</TableBody></Table><PageButtons page={memberPage} total={members.data.totalCount} pageSize={members.data.pageSize} loading={members.isFetching} onPage={setMemberPage}/></> : <Typography color="text.secondary">No project members are recorded.</Typography>)}</CardContent></Card>}
      {tab === 2 && <Card><CardContent><Typography variant="h6" sx={{ mb: 1 }}>Project tasks</Typography>{tasks.isLoading && <CircularProgress size={22}/ >}{tasks.error && <PageState error={tasks.error} retry={() => void tasks.refetch()}/ >}{tasks.data && (tasks.data.items.length ? <><Table size="small" aria-label="Project tasks"><TableHead><TableRow><TableCell>Task</TableCell><TableCell>Status</TableCell><TableCell>Priority</TableCell><TableCell>Assignees</TableCell><TableCell>Due date</TableCell></TableRow></TableHead><TableBody>{tasks.data.items.map(task => <TableRow key={task.id}><TableCell>{task.title}</TableCell><TableCell>{task.status.replace(/_/g, ' ')}</TableCell><TableCell>{task.priority}</TableCell><TableCell>{task.effectiveAssigneeCount}</TableCell><TableCell>{task.dueDate ? dateLabel(task.dueDate) : 'No due date'}</TableCell></TableRow>)}</TableBody></Table><PageButtons page={taskPage} total={tasks.data.totalCount} pageSize={tasks.data.pageSize} loading={tasks.isFetching} onPage={setTaskPage}/></> : <Typography color="text.secondary">No non-deleted top-level tasks are recorded.</Typography>)}</CardContent></Card>}
      {tab === 3 && <Card><CardContent><Typography variant="h6" sx={{ mb: 1 }}>Project activity</Typography><AdminActivity projectId={project.projectId} organizationId={project.organizationId} embedded/></CardContent></Card>}
    </>}
  </Box>;
}

function Metric({ icon, label, value }: { icon: ReactNode; label: string; value: string }) {
  return <Card><CardContent sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}><Box sx={{ color: 'primary.main' }}>{icon}</Box><Box><Typography variant="caption" color="text.secondary">{label}</Typography><Typography variant="h6">{value}</Typography></Box></CardContent></Card>;
}

function PageButtons({ page, total, pageSize, loading, onPage }: { page: number; total: number; pageSize: number; loading: boolean; onPage: (page: number) => void }) {
  const pages = Math.max(1, Math.ceil(total / pageSize));
  return <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', pt: 1 }}><Typography variant="caption">Page {page} of {pages} · {total} records</Typography><Box><Button disabled={page <= 1 || loading} onClick={() => onPage(page - 1)}>Previous</Button><Button disabled={page >= pages || loading} onClick={() => onPage(page + 1)}>Next</Button></Box></Box>;
}
