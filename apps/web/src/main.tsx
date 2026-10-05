import { StrictMode, useEffect, useRef, useState, type ReactNode } from 'react';
import { createRoot } from 'react-dom/client';
import { ApolloProvider } from '@apollo/client/react';
import { QueryClientProvider } from '@tanstack/react-query';
import { CssBaseline, ThemeProvider, createTheme } from '@mui/material';
import { Activity, AlertTriangle, ArrowRight, Bell, CalendarDays, ChevronDown, Circle, CirclePlus, Clock3, LayoutDashboard, List, ListTodo, LogOut, Moon, Search, Settings, Sun, Users, X } from 'lucide-react';
import { Area, AreaChart, CartesianGrid, Cell, Pie, PieChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import axios from 'axios';
import { api, clearAuth, DashboardMetrics, dateLabel, errorMessage, formatDisplayName, graphqlClient, initials, Invitation, Member, Notice, Organization, overdue, Person, priorities, Project, queryClient, signedIn, statuses, Task } from './api';
import { Auth, Inbox } from './Auth';
import AdminDashboard from './AdminDashboard';
import AdminAnalytics from './AdminAnalytics';
import AdminReports from './AdminReports';
import AdminNav from './AdminNav';
import { Input } from './components/ui/input';
import { useIsFetching } from '@tanstack/react-query';
import { RefreshingIndicator } from './components/AdminLoading';
import { Sidebar, SidebarContent, SidebarFooter, SidebarGroup, SidebarGroupLabel, SidebarMenu, SidebarMenuButton, SidebarHeader, SidebarOverlay, SidebarProvider, SidebarTrigger } from './components/ui/sidebar';
import AdminManagement from './AdminManagement';
import { AdminActivity, AdminAuditTrail, AdminHealth, AdminSettings } from './AdminPlatform';
import ActivityCenter, { ActivityWidget } from './ActivityCenter';
import LandingPage from './LandingPage';
import { OrganizationModal, ProjectForm, TaskForm } from './Forms';
import { Brand, Empty, Feedback, Form, Modal, useAction, value } from './ui';
import './styles.css';
import { useNotifications } from './useNotifications';

type ColorMode = 'light' | 'dark';
const theme = (mode: ColorMode) => createTheme({
  typography: { fontFamily: '"Geist Variable", "Geist", ui-sans-serif, system-ui, sans-serif' },
  shape: { borderRadius: 8 },
  palette: { mode, primary: { main: '#6659ef' }, secondary: { main: '#ef8354' } },
  components: {
    MuiMenu: { styleOverrides: { list: { paddingTop: 4, paddingBottom: 4 }, paper: { maxHeight: 'min(320px, calc(100% - 32px))' } } },
    MuiMenuItem: { styleOverrides: { root: { minHeight: 40, paddingTop: 8, paddingBottom: 8, fontSize: 14, lineHeight: '20px' } } },
    MuiSelect: { styleOverrides: { select: { fontSize: 14, lineHeight: '20px' } } }
  }
});

type AdminAccessState = 'checking' | 'admin' | 'user' | 'unavailable';
const adminRoutes = new Set(['admin', 'admin/analytics', 'admin/users', 'admin/organizations', 'admin/projects', 'admin/activity', 'admin/audit', 'admin/health', 'admin/reports', 'admin/settings']);

function App({ mode, toggleTheme }: { mode: ColorMode; toggleTheme: () => void }) {
  const [route,setRoute] = useState(location.hash.slice(1) || 'landing'); const [authenticated,setAuthenticated] = useState(signedIn());
  const [adminAccess, setAdminAccess] = useState<AdminAccessState>(authenticated ? 'checking' : 'user');
  const [localMail,setLocalMail] = useState(false); const [version,setVersion] = useState(0); const refresh = () => setVersion(v => v+1);
  const [liveDataVersion,setLiveDataVersion] = useState(0);
  const projectLoadedFor = useRef('');
  const { notices, error: notificationError, reload: reloadNotifications, markRead } = useNotifications(authenticated && adminAccess === 'user', version);
  const [person,setPerson] = useState<Person>(); const [organizations,setOrganizations] = useState<Organization[]>([]); const [organizationId,setOrganizationId] = useState(localStorage.getItem('taskflow.organizationId') ?? '');
  const [projects,setProjects] = useState<Project[]>([]); const [projectId,setProjectId] = useState(localStorage.getItem('taskflow.projectId') ?? '');
  const [members,setMembers] = useState<Member[]>([]); const [projectMembers,setProjectMembers] = useState<Member[]>([]); const [tasks,setTasks] = useState<Task[]>([]); const [metrics,setMetrics] = useState<DashboardMetrics>(); const [invitations,setInvitations] = useState<Invitation[]>([]);
  const [loading,setLoading] = useState(true); const [projectLoading,setProjectLoading] = useState(false); const [error,setError] = useState(''); const [search,setSearch] = useState(''); const [priority,setPriority] = useState('');
  const [dashboardTaskFilter,setDashboardTaskFilter] = useState('');
  const [mobile,setMobile] = useState(false); const [tenantSidebarCollapsed,setTenantSidebarCollapsed] = useState(() => localStorage.getItem('taskflow.workspaceSidebarCollapsed') === 'true'); const [bell,setBell] = useState(false); const [modal,setModal] = useState(''); const [selected,setSelected] = useState<Task>(); const [pendingTask,setPendingTask] = useState('');
  const action = useAction(); const organization = organizations.find(o => o.id === organizationId); const project = projects.find(p => p.id === projectId); const admin = ['OWNER','ADMIN'].includes(organization?.role ?? '');
  useEffect(() => { document.documentElement.dataset.theme = mode; }, [mode]);
  useEffect(() => { if (route.startsWith('invite?')) sessionStorage.setItem('taskflow.invitation',route); }, [route]);
  useEffect(() => {
    if (!authenticated || adminAccess !== 'user' || !projectId) return;
    const refreshVisibleProject = () => { if (document.visibilityState === 'visible' && navigator.onLine) setLiveDataVersion(current => current + 1); };
    const timer = window.setInterval(refreshVisibleProject, 15_000);
    window.addEventListener('focus', refreshVisibleProject);
    window.addEventListener('online', refreshVisibleProject);
    return () => { window.clearInterval(timer); window.removeEventListener('focus', refreshVisibleProject); window.removeEventListener('online', refreshVisibleProject); };
  }, [authenticated, adminAccess, projectId]);
  useEffect(() => { if (authenticated && ['landing','login','register'].includes(route)) { location.hash = 'dashboard'; setRoute('dashboard'); } }, [authenticated,route]);
  const navigate = (next: string) => { location.hash = next; setRoute(next); setMobile(false); setBell(false); setModal(''); };
  const chooseOrg = (id: string) => { setOrganizationId(id); localStorage.setItem('taskflow.organizationId',id); setProjects([]); setTasks([]); setMetrics(undefined); setMembers([]); setInvitations([]); setProjectId(''); localStorage.removeItem('taskflow.projectId'); };
  const chooseProject = (id: string) => { setProjectId(id); localStorage.setItem('taskflow.projectId',id); setTasks([]); setMetrics(undefined); setProjectMembers([]); };
  useEffect(() => { const hash = () => { setRoute(location.hash.slice(1) || 'landing'); setModal(''); }; const expired = () => { setAuthenticated(false); navigate('landing'); }; window.addEventListener('hashchange',hash); window.addEventListener('session-expired',expired); return () => { window.removeEventListener('hashchange',hash); window.removeEventListener('session-expired',expired); }; }, []);
  useEffect(() => { if (['login','register','forgot','reset','otp','inbox'].includes(route.split('?')[0])) api.get('/auth/mail-mode').then(response => setLocalMail(response.data.local)).catch(() => {}); }, [route]);
  useEffect(() => {
    if (!authenticated) { setAdminAccess('user'); setLoading(false); return; }
    let cancelled = false; setLoading(true); setError(''); setAdminAccess('checking');
    Promise.all([api.get<Person>('/account'), api.get('/admin/dashboard').then(() => 'admin' as const).catch(error => {
      if (axios.isAxiosError(error) && error.response?.status === 403) return 'user' as const;
      throw error;
    })]).then(([user, access]) => {
      if (cancelled) return;
      setPerson(user.data); setAdminAccess(access);
    }).catch(error => { if (!cancelled) { setError(errorMessage(error)); setAdminAccess('unavailable'); } }).finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, [authenticated, version]);
  useEffect(() => {
    if (!authenticated || adminAccess !== 'user') return;
    let cancelled = false;
    api.get<Organization[]>('/organizations').then(response => {
      if (cancelled) return;
      setOrganizations(response.data);
      const nextOrganizationId = response.data.some(item => item.id === organizationId) ? organizationId : response.data[0]?.id ?? '';
      setOrganizationId(nextOrganizationId);
      if (nextOrganizationId !== organizationId) { setProjectId(''); localStorage.removeItem('taskflow.projectId'); }
    }).catch(error => { if (!cancelled) setError(errorMessage(error)); });
    return () => { cancelled = true; };
  }, [authenticated, adminAccess, version]);
  useEffect(() => {
    if (!authenticated || adminAccess !== 'user' || !organizationId) return; let cancelled = false; setProjectLoading(true);
    Promise.all([api.get<Project[]>('/projects',{params:{organizationId}}),api.get<Member[]>(`/organizations/${organizationId}/members`),admin ? api.get<Invitation[]>(`/organizations/${organizationId}/invitations`) : Promise.resolve({data:[] as Invitation[]})]).then(([p,m,i]) => { if (cancelled) return; setProjects(p.data); setMembers(m.data); setInvitations(i.data); setProjectId(current => p.data.some(x => x.id === current) ? current : p.data[0]?.id ?? ''); }).catch(e => { if (!cancelled) setError(errorMessage(e)); }).finally(() => { if (!cancelled) setProjectLoading(false); });
    return () => { cancelled = true; };
  }, [authenticated,adminAccess,organizationId,admin,version]);
  useEffect(() => {
    if (!authenticated || adminAccess !== 'user' || !projectId) { setTasks([]); setMetrics(undefined); setProjectMembers([]); return; } let cancelled = false;
    const isInitialProjectLoad = projectLoadedFor.current !== projectId;
    if (isInitialProjectLoad) { projectLoadedFor.current = projectId; setProjectLoading(true); }
    Promise.all([api.get<{data:Task[]}>('/tasks',{params:{projectId}}),api.get<Member[]>(`/projects/${projectId}/members`),api.get<DashboardMetrics>('/dashboard/metrics',{params:{projectId}})]).then(([t,m,d]) => { if (cancelled) return; setTasks(t.data.data); setProjectMembers(m.data); setMetrics(d.data); }).catch(e => { if (!cancelled) setError(errorMessage(e)); }).finally(() => { if (!cancelled) setProjectLoading(false); });
    return () => { cancelled = true; };
  }, [authenticated,adminAccess,projectId,version,liveDataVersion]);
  useEffect(() => {
    if (adminAccess === 'checking') return;
    if (adminAccess === 'admin' && !adminRoutes.has(route.split('?')[0])) navigate('admin');
    if (adminAccess === 'user' && adminRoutes.has(route.split('?')[0])) navigate('dashboard');
  }, [adminAccess, route]);
  useEffect(() => { if (route === 'notifications') void reloadNotifications(); }, [route, reloadNotifications]);
  useEffect(() => { if (pendingTask) { const task = tasks.find(t => t.id === pendingTask); if (task) { setSelected(task); setModal('task'); setPendingTask(''); } } }, [tasks,pendingTask]);
  const logout = () => void action.run(async () => { try { await api.post('/auth/logout',{refreshToken:localStorage.getItem('taskflow.refreshToken')}); } finally { clearAuth(); setAuthenticated(false); setAdminAccess('user'); setPerson(undefined); setOrganizations([]); setProjects([]); setTasks([]); setOrganizationId(''); setProjectId(''); navigate('landing'); } });
  const openNotice = (n: Notice) => void action.run(async () => { await markRead(n.id); setBell(false); if (n.projectId && n.relatedId) { const p = (await api.get<Project>('/projects/' + n.projectId)).data; if (p.organizationId !== organizationId) chooseOrg(p.organizationId); setProjectId(p.id); setPendingTask(n.relatedId); navigate('board'); refresh(); } });
  const readAll = () => void action.run(async () => { await markRead(); });
  const openTask = (t?: Task) => { setSelected(t); setModal('task'); };
  const authMode = route.split('?')[0];
  if (!authenticated && (authMode === 'landing' || authMode === '')) return <LandingPage navigate={navigate} mode={mode} toggleTheme={toggleTheme}/>;
  if (['reset','forgot','otp','login','register'].includes(authMode) || !authenticated) return <Auth key={route} localMail={localMail} route={['login','register','reset','forgot','otp'].includes(authMode) ? route : 'login'} navigate={navigate} onLogin={() => { setAuthenticated(true); const invitation = sessionStorage.getItem('taskflow.invitation') || (authMode === 'invite' ? route : ''); navigate(invitation || 'dashboard'); refresh(); }}/ >;
  if (authMode === 'inbox') return <Inbox navigate={navigate}/>;
  if (adminAccess === 'checking' || loading) return <main className="auth-page"><div className="auth-card" style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: '64px 32px', textAlign: 'center' }}><Brand/><div style={{ margin: '40px 0 24px', width: 28, height: 28, border: '3px solid #f3f4f6', borderTopColor: '#5141e8', borderRadius: '50%', animation: 'spinner 0.65s linear infinite' }} /><p role="status" style={{ color: '#6b7280', fontSize: 14, fontWeight: 500, margin: 0, letterSpacing: '-0.01em' }}>Authenticating your workspace…</p></div></main>;
  if (adminAccess === 'unavailable') return <main className="auth-page"><section className="auth-card platform-access-error"><Brand/><h1>Platform unavailable</h1><p className="muted">TaskFlow couldn’t verify platform access or load your account.</p><Feedback error={error}/><div className="button-row"><button className="primary" onClick={() => { setError(''); refresh(); }}>Try again</button><button className="secondary" onClick={logout}>Sign out</button></div></section></main>;
  if (adminAccess === 'admin') return <PlatformShell route={authMode} navigate={navigate} logout={logout} busy={action.busy} person={person} mode={mode} toggleTheme={toggleTheme}>{authMode === 'admin/analytics' ? <AdminAnalytics /> : authMode === 'admin/users' ? <AdminManagement page="users"/> : authMode === 'admin/organizations' ? <AdminManagement page="organizations"/> : authMode === 'admin/projects' ? <AdminManagement page="projects"/> : authMode === 'admin/activity' ? <AdminActivity/> : authMode === 'admin/audit' ? <AdminAuditTrail/> : authMode === 'admin/health' ? <AdminHealth/> : authMode === 'admin/reports' ? <AdminReports /> : authMode === 'admin/settings' ? <AdminSettings/> : <AdminDashboard person={person} />}</PlatformShell>;
  if (authMode === 'invite') return <main className="auth-page"><div className="auth-card"><Brand/><h1>Join your team</h1><p className="muted">You are signed in as {person?.email}. Accept this invitation to access your organization.</p><Feedback error={action.error}/><button className="primary" disabled={action.busy} onClick={() => void action.run(async () => { const token = new URLSearchParams(route.split('?')[1]).get('token'); const response = await api.post('/organizations/invitations/accept',{token}); sessionStorage.removeItem('taskflow.invitation'); chooseOrg(response.data.organizationId); navigate('dashboard'); refresh(); })}>Accept invitation</button><button className="text-button" onClick={() => { sessionStorage.setItem('taskflow.invitation',route); logout(); }}>Use a different account</button><button className="text-button" onClick={() => navigate('dashboard')}>Back to workspace</button></div></main>;
  const filtered = tasks.filter(t => (t.title + ' ' + (t.description ?? '')).toLowerCase().includes(search.toLowerCase()) && (!priority || t.priority === priority) && (!dashboardTaskFilter || (dashboardTaskFilter === 'OPEN' ? t.status !== 'DONE' : dashboardTaskFilter === 'OVERDUE' ? overdue(t) : dashboardTaskFilter === 'COMPLETED' ? t.status === 'DONE' : t.assigneeIds.includes(person?.id ?? ''))));
  const manager = ['PROJECT_MANAGER','TEAM_LEAD'].includes(project?.role ?? ''); const writable = Boolean(project && project.role !== 'VIEWER');
  const sidebarIsCollapsed = tenantSidebarCollapsed && !mobile;
  const toggleTenantSidebar = () => { const next = !tenantSidebarCollapsed; setTenantSidebarCollapsed(next); localStorage.setItem('taskflow.workspaceSidebarCollapsed', String(next)); };
  return <SidebarProvider collapsed={sidebarIsCollapsed} mobileOpen={mobile} toggleCollapsed={toggleTenantSidebar} toggleMobile={() => setMobile(open => !open)}><div className={'shell tenant-workspace-shell' + (sidebarIsCollapsed ? ' sidebar-collapsed' : '')}><a className="skip-link" href="#main-content">Skip to main content</a><header className="topbar"><SidebarTrigger mobile/><WorkspaceSearch projects={projects} tasks={tasks} members={members} openTask={task => { if (task.projectId !== projectId) chooseProject(task.projectId); setPendingTask(task.id); navigate("board"); refresh(); }} chooseProject={id => { chooseProject(id); navigate("board"); }} navigate={navigate}/><div className="top-actions"><button className="icon-button notification-button" aria-label="Notifications" aria-expanded={bell} onClick={() => { setBell(!bell); void reloadNotifications(); }}><Bell size={19}/>{notices.some(n => !n.isRead) && <span className="unread-dot"/>}</button><ThemeToggle mode={mode} toggle={toggleTheme}/><WorkspaceProfileMenu person={person} organization={organization} project={project} organizations={organizations} projects={projects} chooseOrg={chooseOrg} chooseProject={chooseProject} navigate={navigate}/></div>{bell && <div className="notification-panel"><div className="panel-heading"><h3>Notifications</h3><button className="link-button" onClick={readAll}>Mark all read</button></div>{notices.length ? notices.slice(0,4).map(n => <button className={'notification-row '+(!n.isRead?'unread':'')} key={n.id} onClick={() => openNotice(n)}><Bell size={17}/><div><strong>{n.message}</strong><small>{new Date(n.createdAt).toLocaleString()}</small></div></button>) : <p className="empty-small">You're all caught up.</p>}<button className="panel-footer" onClick={() => navigate('notifications')}>View all notifications</button></div>}</header>
    <SidebarOverlay/><Sidebar><SidebarHeader><div className="tenant-sidebar-brand"><Brand/><small>{organization?.role?.toLowerCase() ?? 'Workspace'}</small></div><SidebarTrigger/></SidebarHeader><SidebarContent><TenantNav route={route} navigate={navigate} createOrganization={() => setModal('organization')} showDevelopmentInbox={localMail}/></SidebarContent><SidebarFooter>{person && <div className="admin-overview-profile"><span className="admin-overview-profile-avatar">{initials(person.firstName,person.lastName)}</span><span className="admin-overview-profile-copy"><strong>{formatDisplayName(person.firstName,person.lastName)}</strong><small>{organization?.role?.toLowerCase().replace(/_/g,' ') ?? 'Workspace member'}</small></span><button className="admin-overview-profile-logout" aria-label="Log out" title="Log out" disabled={action.busy} onClick={logout}><LogOut size={15}/></button></div>}</SidebarFooter></Sidebar>
    <main className="content" id="main-content" tabIndex={-1}><Feedback error={error || action.error || notificationError}/>{error && <button className="secondary" onClick={refresh}>Retry loading</button>}{loading && !person ? <Empty title="Loading your workspace…"/> : !organization && !error ? <Empty title="Welcome to TaskFlow"><p>Create your organization to start planning projects, or accept an invitation from your team.</p><button className="primary" onClick={() => setModal('organization')}>Create organization</button></Empty> : <>
      {['board','dashboard'].includes(route) && <><div className="page-heading"><div><p className="eyebrow">{organization?.name ?? 'WORKSPACE'} / {route === 'dashboard' ? 'OVERVIEW' : 'PROJECT'}</p><h1>{route === 'dashboard' ? `Welcome back, ${person ? formatDisplayName(person.firstName,person.lastName) : ''}` : project?.name ?? 'Your projects'}</h1><p className="muted">{route === 'dashboard' ? 'A clear view of your team\'s work.' : project?.description || 'Plan, track, and deliver together.'}</p></div><div className="button-row">{route === 'board' && <BoardTeamAvatars members={projectMembers}/ >}{organization?.role !== 'GUEST' && <button className="secondary" onClick={() => setModal('project')}>New project</button>}{writable && <button className="primary" onClick={() => openTask()}><CirclePlus size={18}/>New task</button>}</div></div>
      {project ? <>{route === 'board' && <div className="view-tabs">{['board','list','timeline'].map(v => <button className={(sessionStorage.getItem('taskflow.boardView')||'board')===v?'active':''} key={v} onClick={() => { sessionStorage.setItem('taskflow.boardView',v); refresh(); }}>{v[0].toUpperCase()+v.slice(1)}</button>)}<button onClick={() => navigate('members')}>Members</button>{manager && <button onClick={() => setModal('project-settings')}>Project settings</button>}</div>}{projectLoading && <p role="status" className="loading-line">Refreshing project…</p>}{route === 'dashboard' ? <><Dashboard tasks={tasks} project={project} members={projectMembers} userId={person?.id ?? ''} organizationId={organization?.id ?? ''} canSeeTeamData={admin || manager} navigate={navigate} openTask={openTask} onMetricFilter={filter => { setDashboardTaskFilter(filter); navigate('board'); }}/></> : <><div className="filter-bar"><label className="search-field"><Search size={17}/><input aria-label="Search tasks" placeholder="Search tasks..." value={search} onChange={e => setSearch(e.target.value)}/></label><select aria-label="Filter priority" value={priority} onChange={e => setPriority(e.target.value)}><option value="">All priorities</option>{priorities.map(p => <option key={p}>{p}</option>)}</select><span>{filtered.length} {filtered.length === 1 ? 'task' : 'tasks'}</span>{(priority || search || dashboardTaskFilter) && <button className="link-button" onClick={() => { setPriority(''); setSearch(''); setDashboardTaskFilter(''); }}>Clear filters</button>}</div><TaskViews tasks={filtered} members={projectMembers} mode={sessionStorage.getItem('taskflow.boardView')||'board'} openTask={openTask} writable={writable} move={(id,status) => void action.run(async () => { await api.patch('/tasks/'+id,{status}); refresh(); })}/></>}</> : <Empty title={projectLoading ? 'Loading projects…' : 'No project selected'}><p>{projects.length ? 'Choose a project from the menu above.' : 'Create a project, or ask your project manager to add you to one.'}</p>{projects.map(p => <button key={p.id} className="secondary" onClick={() => chooseProject(p.id)}>{p.name}</button>)}</Empty>}</>}
      {route === 'dashboard' && organization && !project && <ActivityWidget organizationId={organization.id} navigate={navigate}/>}
      {route === 'members' && organization && <MembersPage organization={organization} project={project} members={members} projectMembers={projectMembers} invitations={invitations} refresh={refresh} userId={person?.id ?? ''}/>}
      {route === 'activity' && organization && <ActivityCenter organizationId={organization.id}/>}
      {route === 'notifications' && <><div className="page-heading"><h1>Notifications</h1><button className="secondary" disabled={action.busy || !notices.some(n => !n.isRead)} onClick={readAll}>Mark all read</button></div><section className="notifications-page">{notices.length ? notices.map(n => <button key={n.id} className={'notification-row '+(!n.isRead?'unread':'')} onClick={() => openNotice(n)}><span className="notification-icon"><Bell size={18}/></span><div><strong>{n.message}</strong><small>{new Date(n.createdAt).toLocaleString()} · {n.isRead?'Read':'Unread'}</small></div></button>) : <Empty title="You're all caught up"><p>Task assignments, comments, and mentions will appear here.</p></Empty>}</section></>}
      {route === 'settings' && person && <SettingsPage person={person} project={project} refresh={refresh} editProject={() => setModal('project-settings')} archive={() => { if (project && window.confirm('Archive this project? Its data will be preserved, but it will leave the active project list.')) void action.run(async () => { await api.delete('/projects/'+project.id); chooseProject(''); refresh(); }); }}/ >}
    </>}</main>
    {modal === 'organization' && <OrganizationModal close={() => setModal('')} saved={id => { chooseOrg(id); setModal(''); refresh(); }}/ >}
    {(modal === 'project' || modal === 'project-settings') && organization && <ProjectForm organizationId={organization.id} project={modal==='project-settings'?project:undefined} close={() => setModal('')} saved={id => { setProjectId(id); localStorage.setItem('taskflow.projectId',id); setModal(''); navigate('board'); refresh(); }}/ >}
    {modal === 'task' && project && <TaskForm task={selected} project={project} members={projectMembers} close={() => setModal('')} saved={() => { setModal(''); refresh(); }} changed={refresh}/ >}
  </div></SidebarProvider>;
}

function TenantNav({ route, navigate, createOrganization, showDevelopmentInbox }: { route:string; navigate:(route:string)=>void; createOrganization:()=>void; showDevelopmentInbox:boolean }) {
  const sections = [
    { label: 'Main', items: [{ id: 'dashboard', label: 'Overview', icon: LayoutDashboard }, { id: 'board', label: 'Board', icon: List }, { id: 'members', label: 'Members', icon: Users }] },
    { label: 'Tools', items: [{ id: 'activity', label: 'Activity', icon: Activity }, { id: 'notifications', label: 'Notifications', icon: Bell }] },
    { label: 'Help', items: [{ id: 'settings', label: 'Settings', icon: Settings }] },
  ];
  return <>{sections.map(section => <SidebarGroup key={section.label} aria-label={section.label}><SidebarGroupLabel>{section.label}</SidebarGroupLabel><SidebarMenu>{section.items.map(item => <SidebarMenuButton key={item.id} isActive={route === item.id} tooltip={item.label} aria-current={route === item.id ? 'page' : undefined} onClick={() => navigate(item.id)}><item.icon size={18} strokeWidth={1.7}/><span className="admin-nav-label">{item.label}</span></SidebarMenuButton>)}</SidebarMenu></SidebarGroup>)}<SidebarGroup aria-label="Organization"><SidebarGroupLabel>Organization</SidebarGroupLabel><SidebarMenu><SidebarMenuButton tooltip="New organization" onClick={createOrganization}><CirclePlus size={18} strokeWidth={1.7}/><span className="admin-nav-label">New organization</span></SidebarMenuButton>{showDevelopmentInbox && <SidebarMenuButton tooltip="Development inbox" isActive={route === 'inbox'} aria-current={route === 'inbox' ? 'page' : undefined} onClick={() => navigate('inbox')}><Bell size={18} strokeWidth={1.7}/><span className="admin-nav-label">Development inbox</span></SidebarMenuButton>}</SidebarMenu></SidebarGroup></>;
}

function ThemeToggle({ mode, toggle }: { mode:ColorMode; toggle:()=>void }) {
  const nextMode = mode === 'dark' ? 'light' : 'dark';
  return <button className="icon-button" aria-label={`Switch to ${nextMode} mode`} title={`Switch to ${nextMode} mode`} onClick={toggle}>{mode === 'dark' ? <Sun size={19}/> : <Moon size={19}/>}</button>;
}

function BoardTeamAvatars({ members }: { members:Member[] }) {
  if (!members.length) return null;
  return <div className="board-team-preview" aria-label={`${members.length} project ${members.length === 1 ? 'member' : 'members'}`}>
    <div className="board-team-avatars">{members.slice(0,5).map(member=><span className="board-team-avatar" key={member.userId} title={`${formatDisplayName(member.firstName,member.lastName)} ? ${member.role.toLowerCase().replace(/_/g,' ')}`}>{initials(member.firstName,member.lastName)}</span>)}</div>
    {members.length > 5 && <span className="board-team-overflow">+{members.length-5}</span>}
  </div>;
}

function WorkspaceProfileMenu({ person, organization, project, organizations, projects, chooseOrg, chooseProject, navigate }: { person?:Person; organization?:Organization; project?:Project; organizations:Organization[]; projects:Project[]; chooseOrg:(id:string)=>void; chooseProject:(id:string)=>void; navigate:(route:string)=>void }) {
  const [expanded,setExpanded] = useState(false);
  const container = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const handlePointer = (event:PointerEvent) => { if (!container.current?.contains(event.target as Node)) setExpanded(false); };
    const handleKey = (event:KeyboardEvent) => { if (event.key === 'Escape') setExpanded(false); };
    document.addEventListener('pointerdown',handlePointer);
    document.addEventListener('keydown',handleKey);
    return () => { document.removeEventListener('pointerdown',handlePointer); document.removeEventListener('keydown',handleKey); };
  },[]);
  const role = (project?.role || organization?.role || 'Member').toLowerCase().replace(/_/g,' ').replace(/\b\w/g,letter=>letter.toUpperCase());
  const displayName = person ? formatDisplayName(person.firstName,person.lastName) : 'Account';
  return <div className="workspace-profile-menu" ref={container}>
    <button type="button" className="workspace-profile-trigger" aria-expanded={expanded} aria-controls="workspace-profile-panel" onClick={()=>setExpanded(value=>!value)}>
      <span className="board-profile-avatar">{person ? initials(person.firstName,person.lastName) : 'U'}</span>
      <span className="board-profile-copy"><strong>{displayName}</strong><small>{role}</small></span>
      <ChevronDown size={15} className={expanded?'is-expanded':''}/>
    </button>
    {expanded && <section className="workspace-profile-panel" id="workspace-profile-panel" aria-label="Profile and workspace selectors">
      <div className="board-profile-panel-person"><span className="board-profile-avatar">{person ? initials(person.firstName,person.lastName) : 'U'}</span><span><strong>{displayName}</strong><small>{person?.email}</small></span></div>
      <label>Organization<select aria-label="Organization" value={organization?.id ?? ''} onChange={event=>{chooseOrg(event.target.value);setExpanded(false);}}>{organizations.map(item=><option key={item.id} value={item.id}>{item.name}</option>)}</select></label>
      <label>Project<select aria-label="Project" value={project?.id ?? ''} onChange={event=>{chooseProject(event.target.value);setExpanded(false);}}><option value="">Choose project</option>{projects.map(item=><option key={item.id} value={item.id}>{item.name}</option>)}</select></label>
      <button type="button" className="workspace-profile-settings" onClick={()=>{setExpanded(false);navigate('settings');}}>Account settings</button>
    </section>}
  </div>;
}
function WorkspaceSearch({ projects, tasks, members, openTask, chooseProject, navigate }: { projects:Project[]; tasks:Task[]; members:Member[]; openTask:(task:Task)=>void; chooseProject:(id:string)=>void; navigate:(route:string)=>void }) {
  const [query,setQuery] = useState('');
  const [open,setOpen] = useState(false);
  const container = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const handlePointer = (event:PointerEvent) => { if (!container.current?.contains(event.target as Node)) setOpen(false); };
    const handleKey = (event:KeyboardEvent) => { if (event.key === 'Escape') setOpen(false); };
    document.addEventListener('pointerdown',handlePointer);
    document.addEventListener('keydown',handleKey);
    return () => { document.removeEventListener('pointerdown',handlePointer); document.removeEventListener('keydown',handleKey); };
  },[]);
  const term = query.trim().toLowerCase();
  const results = term ? [
    ...tasks.filter(task => `${task.title} ${task.description ?? ''}`.toLowerCase().includes(term)).slice(0,5).map(task => ({ type:'Task', title:task.title, detail:`${projects.find(item=>item.id===task.projectId)?.name ?? 'Project'} ? ${task.status.toLowerCase().replace(/_/g,' ')}`, select:()=>openTask(task) })),
    ...projects.filter(item => `${item.name} ${item.description ?? ''}`.toLowerCase().includes(term)).slice(0,4).map(item => ({ type:'Project', title:item.name, detail:item.description || 'Open project board', select:()=>chooseProject(item.id) })),
    ...members.filter(member => `${member.firstName} ${member.lastName} ${member.email}`.toLowerCase().includes(term)).slice(0,4).map(member => ({ type:'Person', title:formatDisplayName(member.firstName,member.lastName), detail:member.email, select:()=>navigate('members') }))
  ].slice(0,8) : [];
  return <div className="workspace-search" ref={container}>
    <Search size={18} aria-hidden="true"/>
    <input aria-label="Search workspace" placeholder="Search tasks, projects, people..." value={query} onChange={event=>{setQuery(event.target.value);setOpen(true);}} onFocus={()=>setOpen(true)} onKeyDown={event=>{if(event.key==='Enter'&&results[0]){results[0].select();setOpen(false);}}}/>
    {query && <button type="button" className="workspace-search-clear" aria-label="Clear search" onClick={()=>{setQuery('');setOpen(true);}}><X size={15}/></button>}
    {open && term && <div className="workspace-search-results" role="listbox" aria-label="Search results">{results.length ? results.map((result,index)=><button type="button" role="option" aria-selected="false" className="workspace-search-result" key={`${result.type}-${result.title}-${index}`} onClick={()=>{result.select();setOpen(false);setQuery('');}}><span className="workspace-search-result-type">{result.type}</span><span className="workspace-search-result-copy"><strong>{result.title}</strong><small>{result.detail}</small></span></button>) : <p className="workspace-search-empty">No matching tasks, projects, or people.</p>}</div>}
  </div>;
}

function PlatformShell({ route, navigate, logout, busy, person, mode, toggleTheme, children }: { route:string; navigate:(route:string)=>void; logout:()=>void; busy:boolean; person?:Person; mode:ColorMode; toggleTheme:()=>void; children:ReactNode }) {
  const overview = route === 'admin';
  const platformAdmin = route.startsWith('admin');
  const [navSearch, setNavSearch] = useState('');
  const [mobileNavOpen, setMobileNavOpen] = useState(false);
  const [sidebarCollapsed, setSidebarCollapsed] = useState(() => localStorage.getItem('taskflow.adminSidebarCollapsed') === 'true');
  useEffect(() => {
    if (!platformAdmin) return;
    const focusSearch = (event: KeyboardEvent) => {
      if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'k') {
        event.preventDefault();
        document.querySelector<HTMLInputElement>('.admin-command-search input')?.focus();
      }
    };
    window.addEventListener('keydown', focusSearch);
    return () => window.removeEventListener('keydown', focusSearch);
  }, [platformAdmin]);
  const adminPageTitle:Record<string,string> = { 'admin/analytics':'Analytics','admin/users':'Users','admin/organizations':'Organizations','admin/projects':'Projects','admin/activity':'Activity','admin/audit':'Audit Trail','admin/health':'System health','admin/reports':'Reports','admin/settings':'Settings' };
  const sidebarIsCollapsed = platformAdmin && sidebarCollapsed && !mobileNavOpen;
  const isRefreshing = useIsFetching() > 0;
  const setSidebarCollapsedPersisted = () => {
    const next = !sidebarCollapsed;
    setSidebarCollapsed(next);
    localStorage.setItem('taskflow.adminSidebarCollapsed', String(next));
  };
  return <SidebarProvider collapsed={sidebarIsCollapsed} mobileOpen={mobileNavOpen} toggleCollapsed={setSidebarCollapsedPersisted} toggleMobile={() => setMobileNavOpen(open => !open)}><div className={'shell platform-shell' + (platformAdmin ? ' admin-platform-shell' : '') + (overview ? ' admin-overview-shell' : '') + (sidebarIsCollapsed ? ' sidebar-collapsed' : '')}>
    <a className="skip-link" href="#main-content">Skip to main content</a>
    <header className="topbar">
        {platformAdmin && <SidebarTrigger mobile/>}
        {overview ? <>
        <div className="platform-overview-title"><span>Platform</span><b>/</b> Overview</div>
        </> : <div className="crumb platform-title">Platform <span>/</span> {adminPageTitle[route] ?? 'Administration'}</div>}
        {platformAdmin && <label className="admin-command-search"><Search size={17} aria-hidden="true"/><Input aria-label="Search platform pages" value={navSearch} onChange={event => setNavSearch(event.target.value)} onKeyDown={event => { if (event.key === 'Escape') setNavSearch(''); }} placeholder="Search pages and tools…"/>{navSearch && <button type="button" className="admin-command-clear" aria-label="Clear search" onClick={() => setNavSearch('')}><X size={14}/></button>}<kbd>Ctrl</kbd><kbd>K</kbd></label>}
      <div className="top-actions"><ThemeToggle mode={mode} toggle={toggleTheme}/><button className="avatar" aria-label="Account settings" onClick={() => navigate('admin')}>{person ? initials(person.firstName,person.lastName) : '…'}</button></div>
    </header>
    <SidebarOverlay/>
    <Sidebar>
      <SidebarHeader><Brand/><SidebarTrigger/></SidebarHeader>
      <SidebarContent><AdminNav route={route} navigate={(next) => { navigate(next); setMobileNavOpen(false); setNavSearch(''); }} filter={platformAdmin ? navSearch : ''} inspiration={platformAdmin} collapsed={sidebarIsCollapsed}/></SidebarContent>
      <SidebarFooter>{platformAdmin && person ? <div className="admin-overview-profile"><span className="admin-overview-profile-avatar">{initials(person.firstName,person.lastName)}</span><span className="admin-overview-profile-copy"><strong>{formatDisplayName(person.firstName,person.lastName)}</strong><small>Super admin</small></span><button className="admin-overview-profile-logout" aria-label="Log out" title="Log out" disabled={busy} onClick={logout}><LogOut size={15}/></button></div> : <div className="sidebar-bottom"><button className="nav-item" disabled={busy} onClick={logout}><LogOut size={18}/>Log out</button></div>}</SidebarFooter>
    </Sidebar>
    <main className="content" id="main-content" tabIndex={-1} aria-busy={isRefreshing || undefined}>{isRefreshing && <RefreshingIndicator label="Refreshing page data"/>}{children}</main>
  </div></SidebarProvider>;
}

function TaskViews({ tasks, members, mode, openTask, writable, move }: { tasks:Task[]; members:Member[]; mode:string; openTask:(task:Task)=>void; writable:boolean; move:(id:string,status:string)=>void }) {
  const card = (t:Task) => <button draggable={writable} onDragStart={e => e.dataTransfer.setData('text/plain',t.id)} className="task-card" key={t.id} onClick={() => openTask(t)}><span className="task-card-top"><b className={'priority '+t.priority.toLowerCase()}>{t.priority.toLowerCase()}</b>{Boolean(t.subtaskCount) && <small className="subtask-summary">{t.completedSubtaskCount ?? 0}/{t.subtaskCount} subtasks</small>}</span><span className="task-title">{t.title}</span>{t.description && <span className="task-card-description">{t.description}</span>}<span className="task-meta"><span className={'task-due '+(overdue(t)?'is-overdue':'')}>{t.status==='DONE' ? <><Circle size={13}/> Completed</> : t.dueDate ? <><CalendarDays size={13}/>{dateLabel(t.dueDate)}</> : <><CalendarDays size={13}/>No due date</>}</span></span><span className="assignee-chips">{t.assigneeIds.length ? <>{t.assigneeIds.slice(0,3).map(id => { const m = members.find(x=>x.userId===id); return <span className="task-assignee" key={id} title={m?formatDisplayName(m.firstName,m.lastName):'Assigned teammate'}>{m?initials(m.firstName,m.lastName):'?'}</span>; })}{t.assigneeIds.length > 3 && <small className="task-assignee-overflow">+{t.assigneeIds.length - 3}</small>}</> : <small className="task-unassigned">Unassigned</small>}</span></button>;
  if (mode==='list') return <section className="list-panel">{tasks.length ? tasks.map(t=><div className="task-list-entry" key={t.id}>{card(t)}<span className="status-tag">{t.status}</span></div>) : <Empty title="No tasks match this view"/>}</section>;
  if (mode==='timeline') return <section className="list-panel timeline"><h2>Project timeline</h2><p className="muted">Tasks ordered by due date. Open a task to adjust its schedule.</p>{[...tasks].sort((a,b)=>(a.dueDate||'9999').localeCompare(b.dueDate||'9999')).map(t=><div className="timeline-entry" key={t.id}><div><strong>{dateLabel(t.dueDate)}</strong><small>Start: {dateLabel(t.startDate)}</small></div>{card(t)}</div>)}{!tasks.length && <Empty title="No tasks scheduled yet"/>}</section>;
  return <div className="board">{statuses.map(s=>{ const columnTasks=tasks.filter(t=>t.status===s); const heading=s.toLowerCase().replace(/\b\w/g,letter=>letter.toUpperCase()); return <section className={'column column-'+s.toLowerCase().replace(/\s+/g,'-')} key={s} onDragOver={e=>{if(writable)e.preventDefault();}} onDrop={e=>{e.preventDefault();const id=e.dataTransfer.getData('text/plain');if(writable && tasks.some(t=>t.id===id && t.status!==s))move(id,s);}}><div className="column-title"><div><h2>{heading}</h2><small>{columnTasks.length} {columnTasks.length===1?'task':'tasks'}</small></div><span aria-label={`${columnTasks.length} tasks`}>{columnTasks.length}</span></div>{columnTasks.length ? columnTasks.map(card) : <p className="empty-column">No tasks in {heading.toLowerCase()}</p>}</section>;})}</div>;
}
function Dashboard({ tasks, project, members, userId, organizationId, canSeeTeamData, navigate, openTask, onMetricFilter }: { tasks:Task[]; project:Project; members:Member[]; userId:string; organizationId:string; canSeeTeamData:boolean; navigate:(route:string)=>void; openTask:(task:Task)=>void; onMetricFilter:(filter:string)=>void }) {
  const mine = tasks.filter(task => task.assigneeIds.includes(userId));
  const scopeTasks = canSeeTeamData ? tasks : mine;
  const completed = scopeTasks.filter(task => task.status === 'DONE').length;
  const overdueTasks = scopeTasks.filter(overdue);
  const progress = scopeTasks.length ? Math.round(completed / scopeTasks.length * 100) : 0;
  const openTasks = scopeTasks.filter(task => task.status !== 'DONE').length;
  const priorityTasks = [...mine].filter(task => task.status !== 'DONE').sort((a, b) => Number(overdue(b)) - Number(overdue(a)) || (a.dueDate ?? '9999').localeCompare(b.dueDate ?? '9999')).slice(0, 4);
  const today = new Date();
  const todayKey = localDateKey(today);
  const tomorrow = new Date(today);
  tomorrow.setDate(tomorrow.getDate() + 1);
  const tomorrowKey = localDateKey(tomorrow);
  const dueLabel = (task:Task) => {
    if (overdue(task)) return 'Overdue';
    if (!task.dueDate) return 'No due date';
    const key = task.dueDate.slice(0, 10);
    if (key === todayKey) return 'Today';
    if (key === tomorrowKey) return 'Tomorrow';
    return `Due ${dateLabel(task.dueDate)}`;
  };
  const metricCards = [
    { label: canSeeTeamData ? 'Total tasks' : 'My tasks', count: scopeTasks.length, filter: canSeeTeamData ? '' : 'MINE', icon: ListTodo, tone: 'violet' },
    { label: canSeeTeamData ? 'Open' : 'My open', count: openTasks, filter: 'OPEN', icon: Circle, tone: 'blue' },
    { label: canSeeTeamData ? 'Overdue' : 'My overdue', count: overdueTasks.length, filter: 'OVERDUE', icon: AlertTriangle, tone: 'pink' },
    { label: 'Completed', count: completed, filter: 'COMPLETED', icon: Clock3, tone: 'orange' },
  ];
  const statusLabel = project.status.toLowerCase().replace(/_/g, ' ').replace(/\b\w/g, letter => letter.toUpperCase());
  const workload = (canSeeTeamData ? members : members.filter(member => member.userId === userId)).map(member => ({ member, count: scopeTasks.filter(task => task.status !== 'DONE' && task.assigneeIds.includes(member.userId)).length }));
  const workloadMax = Math.max(1, ...workload.map(item => item.count));
  const statusCounts = statuses.map((status, index) => ({ name: status === 'TO DO' ? 'To do' : status === 'IN PROGRESS' ? 'In progress' : status === 'REVIEW' ? 'Review' : 'Completed', value: scopeTasks.filter(task => task.status === status).length, color: ['#8074e8','#4d83c6','#e5a23c','#45a28c'][index] }));
  const days = Array.from({ length: 7 }, (_, index) => { const day = new Date(); day.setHours(0,0,0,0); day.setDate(day.getDate() - (6 - index)); return day; });
  const trendData = days.map(day => { const key = localDateKey(day); return { date: day.toLocaleDateString(undefined, { weekday:'short' }), created: scopeTasks.filter(task => task.createdAt?.slice(0,10) === key).length, completed: scopeTasks.filter(task => task.status === 'DONE' && task.completedAt?.slice(0,10) === key).length }; });
  const hasTrendData = trendData.some(day => day.created || day.completed);
  const deadlines = [...scopeTasks].filter(task => task.status !== 'DONE' && task.dueDate).sort((a,b) => (a.dueDate ?? '').localeCompare(b.dueDate ?? '')).slice(0,4);
  const onTimeTasks = scopeTasks.filter(task => task.status === 'DONE' && task.dueDate);
  const onTimeCount = onTimeTasks.filter(task => task.completedAt && task.completedAt.slice(0,10) <= (task.dueDate ?? '').slice(0,10)).length;
  const onTimeRate = onTimeTasks.length ? Math.round(onTimeCount / onTimeTasks.length * 100) : undefined;

  return <div className="dashboard-operations">
    <div className="dashboard-metrics" aria-label="Task summary">
    {metricCards.map(({ label, count, filter, icon:Icon, tone }) => <button className="admin-overview-metric dashboard-metric dashboard-metric-button" key={label} onClick={() => onMetricFilter(filter)} aria-label={`${label}: ${count}. View matching tasks`}><div className="admin-overview-metric-top"><span>{label}</span><span className={'admin-overview-icon ' + tone}><Icon size={16} strokeWidth={1.8}/></span></div><strong className={label.toLowerCase().includes('overdue') && count > 0 ? 'dashboard-metric-alert' : ''}>{count}</strong><small>View tasks <ArrowRight size={12}/></small></button>)}
    </div>

    <div className="dashboard-chart-grid">
      <section className="admin-overview-panel dashboard-panel dashboard-chart-panel" aria-labelledby="dashboard-trend-title">
        <header className="admin-overview-panel-heading dashboard-section-heading"><div><h2 id="dashboard-trend-title">Task progress</h2><p>Created and completed · last 7 days</p></div><span className="dashboard-chart-legend"><i className="created"/>Created <i className="completed"/>Completed</span></header>
        {hasTrendData ? <div className="dashboard-chart"><ResponsiveContainer width="100%" height="100%"><AreaChart data={trendData} margin={{ top: 8, right: 10, left: -22, bottom: 0 }}><CartesianGrid strokeDasharray="3 3" vertical={false} stroke="var(--overview-border)"/><XAxis dataKey="date" tickLine={false} axisLine={false} tick={{ fill:'var(--overview-muted)', fontSize:11 }}/><YAxis allowDecimals={false} tickLine={false} axisLine={false} tick={{ fill:'var(--overview-muted)', fontSize:10 }}/><Tooltip contentStyle={{ border:'1px solid var(--overview-border)', borderRadius:8, background:'var(--overview-card)', color:'var(--overview-ink)', fontSize:12 }}/><Area type="monotone" dataKey="created" name="Created" stroke="#8278e3" fill="#8278e3" fillOpacity={0.1} strokeWidth={2}/><Area type="monotone" dataKey="completed" name="Completed" stroke="#45a28c" fill="#45a28c" fillOpacity={0.1} strokeWidth={2}/></AreaChart></ResponsiveContainer></div> : <p className="dashboard-chart-empty">No task creation or completion dates are available for the last 7 days.</p>}
        <p className="dashboard-data-note">Based on current tasks still in this project; reopened or deleted tasks may not appear in past counts.</p>
      </section>
      <section className="admin-overview-panel dashboard-panel dashboard-chart-panel" aria-labelledby="dashboard-status-title">
        <header className="admin-overview-panel-heading dashboard-section-heading"><div><h2 id="dashboard-status-title">Task distribution</h2><p>{canSeeTeamData ? 'Current status across the project' : 'Status of your assigned tasks'}</p></div></header>
        {scopeTasks.length ? <div className="dashboard-status-chart-wrap"><div className="dashboard-donut"><ResponsiveContainer width="100%" height="100%"><PieChart><Pie data={statusCounts} dataKey="value" nameKey="name" innerRadius="68%" outerRadius="92%" paddingAngle={2} stroke="none">{statusCounts.map(item => <Cell key={item.name} fill={item.color}/>)}</Pie><Tooltip contentStyle={{ border:'1px solid var(--overview-border)', borderRadius:8, background:'var(--overview-card)', color:'var(--overview-ink)', fontSize:12 }}/></PieChart></ResponsiveContainer><span><strong>{scopeTasks.length}</strong><small>tasks</small></span></div><div className="dashboard-status-legend">{statusCounts.map(item => <div key={item.name}><i style={{ background:item.color }}/><span>{item.name}</span><strong>{item.value}</strong></div>)}</div></div> : <p className="dashboard-chart-empty">Tasks will appear here as they are added to the project.</p>}
      </section>
    </div>

    <div className="dashboard-primary-grid">
      <section className="admin-overview-panel dashboard-panel dashboard-priorities" aria-labelledby="dashboard-priorities-title">
        <header className="admin-overview-panel-heading dashboard-section-heading"><div><h2 id="dashboard-priorities-title">My priorities</h2><p>Assigned work that needs your attention</p></div><button className="dashboard-text-action" onClick={() => navigate('board')}>Open board <ArrowRight size={14}/></button></header>
        {priorityTasks.length ? <div className="dashboard-priority-list">{priorityTasks.map(task => <button className="dashboard-priority-row" key={task.id} onClick={() => openTask(task)}><span className={'dashboard-priority-marker ' + (overdue(task) ? 'is-overdue' : '')}>{overdue(task) ? <AlertTriangle size={16}/> : <Circle size={15}/>}</span><span className="dashboard-priority-copy"><strong title={task.title}>{task.title}</strong><small>{task.priority.toLowerCase()} priority · {task.status.toLowerCase()}</small></span><span className={'dashboard-due-chip ' + (overdue(task) ? 'is-overdue' : '')}>{dueLabel(task)}</span></button>)}</div> : <p className="dashboard-empty-copy">No open tasks are assigned to you.</p>}
      </section>

      <section className="admin-overview-panel dashboard-panel dashboard-project-health" aria-labelledby="dashboard-health-title">
        <header className="admin-overview-panel-heading dashboard-section-heading"><div><h2 id="dashboard-health-title">{canSeeTeamData ? 'Project health' : 'My workload'}</h2><p title={project.name}>{canSeeTeamData ? project.name : 'Your assigned work'}</p></div>{canSeeTeamData && <span className="dashboard-status-chip">{statusLabel}</span>}</header>
        <div className="dashboard-progress-copy"><strong>{progress}%</strong><span>{completed} of {scopeTasks.length} tasks complete</span></div>
        <div className="dashboard-health-track" role="progressbar" aria-label={canSeeTeamData ? 'Project completion' : 'My task completion'} aria-valuemin={0} aria-valuemax={100} aria-valuenow={progress}><span style={{ width: `${progress}%` }}/></div>
        <div className="dashboard-health-meta">{canSeeTeamData ? <><span><CalendarDays size={15}/><span>Deadline <strong>{project.dueDate ? dateLabel(project.dueDate) : 'Not set'}</strong></span></span><span><Users size={15}/><span><strong>{members.length}</strong> {members.length === 1 ? 'member' : 'members'}</span></span><span><Circle size={15}/><span>On time <strong>{onTimeRate === undefined ? '—' : `${onTimeRate}%`}</strong></span></span></> : <span><AlertTriangle size={15}/><span>Overdue <strong>{overdueTasks.length}</strong></span></span>}</div>
      </section>
    </div>

    <div className="dashboard-secondary-grid">
      <section className="admin-overview-panel dashboard-panel dashboard-deadlines" aria-labelledby="dashboard-deadlines-title">
        <header className="admin-overview-panel-heading dashboard-section-heading"><div><h2 id="dashboard-deadlines-title">Upcoming deadlines</h2><p>{canSeeTeamData ? 'Open project tasks due soon' : 'Your open tasks due soon'}</p></div><button className="dashboard-text-action" onClick={() => navigate('board')}>All tasks <ArrowRight size={14}/></button></header>
        {deadlines.length ? <div className="dashboard-priority-list">{deadlines.map(task => <button className="dashboard-priority-row" key={task.id} onClick={() => openTask(task)}><span className={'dashboard-priority-marker ' + (overdue(task) ? 'is-overdue' : '')}>{overdue(task) ? <AlertTriangle size={15}/> : <CalendarDays size={15}/>}</span><span className="dashboard-priority-copy"><strong title={task.title}>{task.title}</strong><small>{task.assigneeIds.length ? `${task.assigneeIds.length} assigned` : 'Unassigned'} · {task.priority.toLowerCase()} priority</small></span><span className={'dashboard-due-chip ' + (overdue(task) ? 'is-overdue' : '')}>{dueLabel(task)}</span></button>)}</div> : <p className="dashboard-empty-copy">No upcoming deadlines. Tasks without due dates are not included.</p>}
      </section>
      <div className="dashboard-secondary-stack">
      {canSeeTeamData && <section className="admin-overview-panel dashboard-panel dashboard-workload" aria-labelledby="dashboard-workload-title">
        <header className="admin-overview-panel-heading dashboard-section-heading"><div><h2 id="dashboard-workload-title">Team workload</h2><p>Open tasks by project member</p></div><button className="dashboard-text-action" onClick={() => navigate('members')}>Team <ArrowRight size={14}/></button></header>
        {workload.length ? <div className="dashboard-workload-list">{workload.map(({ member, count }) => <div className="dashboard-workload-row" key={member.userId}><span className="dashboard-member-avatar" aria-hidden="true">{initials(member.firstName, member.lastName)}</span><strong title={formatDisplayName(member.firstName,member.lastName)}>{formatDisplayName(member.firstName,member.lastName)}</strong><span className="dashboard-workload-track"><i style={{ width: `${Math.round(count / workloadMax * 100)}%` }}/></span><small>{count} open {count === 1 ? 'task' : 'tasks'}</small></div>)}</div> : <p className="dashboard-empty-copy">No project members to show.</p>}
      </section>}
      {!canSeeTeamData && <section className="admin-overview-panel dashboard-panel dashboard-workload" aria-labelledby="dashboard-my-workload-title"><header className="admin-overview-panel-heading dashboard-section-heading"><div><h2 id="dashboard-my-workload-title">My workload</h2><p>Open tasks assigned to you</p></div></header>{workload.length ? <div className="dashboard-workload-list">{workload.map(({ member, count }) => <div className="dashboard-workload-row" key={member.userId}><span className="dashboard-member-avatar" aria-hidden="true">{initials(member.firstName, member.lastName)}</span><strong>{formatDisplayName(member.firstName,member.lastName)}</strong><span className="dashboard-workload-track"><i style={{ width: `${Math.round(count / workloadMax * 100)}%` }}/></span><small>{count} open</small></div>)}</div> : <p className="dashboard-empty-copy">No open tasks assigned to you.</p>}</section>}
      <div className="admin-overview-panel dashboard-panel dashboard-recent-activity"><ActivityWidget organizationId={organizationId} navigate={navigate}/></div>
      </div>
    </div>
  </div>;
}

function localDateKey(date:Date) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}

function MembersPage({organization,project,members,projectMembers,invitations,refresh,userId}:{organization:Organization;project?:Project;members:Member[];projectMembers:Member[];invitations:Invitation[];refresh:()=>void;userId:string}) {
  const [tab,setTab]=useState('organization');const [modal,setModal]=useState('');const action=useAction();const admin=['OWNER','ADMIN'].includes(organization.role);const manager=['PROJECT_MANAGER','TEAM_LEAD'].includes(project?.role??'');
  const shown=tab==='organization'?members:projectMembers;
  return <><div className="page-heading"><div><p className="eyebrow">{organization.name} / PEOPLE</p><h1>{tab==='organization'?'Organization':'Project'} members</h1><p className="muted">{shown.length} members</p></div>{tab==='organization'&&admin&&<button className="primary" onClick={()=>setModal('invite')}>Invite teammate</button>}{tab==='project'&&manager&&<button className="primary" onClick={()=>setModal('add')}>Add project member</button>}</div><div className="view-tabs"><button className={tab==='organization'?'active':''} onClick={()=>setTab('organization')}>Organization</button><button disabled={!project} className={tab==='project'?'active':''} onClick={()=>setTab('project')}>{project?.name??'Select a project'}</button></div><Feedback error={action.error}/><section className="members-panel">{shown.map(m=><div className="member-row" key={m.userId}><div className="avatar soft">{initials(m.firstName,m.lastName)}</div><div><strong>{formatDisplayName(m.firstName,m.lastName)}</strong><small>{m.email}</small></div>{tab==='organization'&&admin&&m.role!=='OWNER'&&m.userId!==userId?<select aria-label={'Role for '+m.firstName} value={m.role} disabled={action.busy} onChange={e=>{const role=e.target.value;void action.run(async()=>{await api.patch(`/organizations/${organization.id}/members/${m.userId}`,{role});refresh();});}}>{['ADMIN','MEMBER','GUEST'].map(r=><option key={r}>{r}</option>)}</select>:<span>{m.role}</span>}{tab==='organization'&&admin&&m.role!=='OWNER'&&m.userId!==userId&&<button className="danger member-remove" disabled={action.busy} onClick={()=>{if(window.confirm(`Remove ${formatDisplayName(m.firstName,m.lastName)} from this workspace? Their tasks and comments will be kept.`))void action.run(async()=>{await api.delete(`/organizations/${organization.id}/members/${m.userId}`);refresh();});}}>Remove</button>}{tab==='project'&&manager&&m.userId!==userId&&<button className="danger member-remove" disabled={action.busy} onClick={()=>{if(window.confirm(`Remove ${formatDisplayName(m.firstName,m.lastName)} from this project? Their past work will be kept.`))void action.run(async()=>{await api.delete(`/projects/${project?.id}/members/${m.userId}`);refresh();});}}>Remove</button>}</div>)}</section>{tab==='organization'&&admin&&<section className="list-panel"><h2>Pending invitations</h2>{invitations.length?invitations.map(i=><div className="member-row" key={i.id}><div><strong>{i.email}</strong><small>{i.role} · Expires {dateLabel(i.expiresAt)}</small></div><button className="link-button" disabled={action.busy} onClick={()=>void action.run(async()=>{await api.delete(`/organizations/${organization.id}/invitations/${i.id}`);refresh();})}>Cancel invitation</button></div>):<p className="muted">No pending invitations.</p>}</section>}
  {modal&&<Modal title={modal==='invite'?'Invite teammate':'Add project member'} close={()=>setModal('')}><Form onSubmit={data=>void action.run(async()=>{if(modal==='invite')await api.post(`/organizations/${organization.id}/invitations`,{email:value(data,'email'),role:value(data,'role')});else await api.post(`/projects/${project?.id}/members`,{userId:value(data,'userId'),role:value(data,'role')});setModal('');refresh();})}><div className="modal-body">{modal==='invite'?<label>Email address<input type="email" name="email" required placeholder="teammate@company.com"/></label>:<label>Organization member<select aria-label="Organization member" name="userId" required><option value="">Choose a person</option>{members.filter(m=>!projectMembers.some(p=>p.userId===m.userId)).map(m=><option key={m.userId} value={m.userId}>{formatDisplayName(m.firstName,m.lastName)} ({m.role})</option>)}</select></label>}<label>Role<select aria-label="Role" name="role" defaultValue={modal==='invite'?'MEMBER':'CONTRIBUTOR'}>{(modal==='invite'?['ADMIN','MEMBER','GUEST']:['PROJECT_MANAGER','TEAM_LEAD','CONTRIBUTOR','VIEWER']).map(r=><option key={r}>{r}</option>)}</select></label><Feedback error={action.error}/></div><div className="modal-foot"><button type="button" className="secondary" onClick={()=>setModal('')}>Cancel</button><button className="primary" disabled={action.busy}>{modal==='invite'?'Send invitation':'Add member'}</button></div></Form></Modal>}
  </>;
}
function SettingsPage({person,project,refresh,editProject,archive}:{person:Person;project?:Project;refresh:()=>void;editProject:()=>void;archive:()=>void}) {
  const action=useAction();const [message,setMessage]=useState('');
  return <><div className="page-heading"><h1>Settings</h1></div><section className="list-panel settings-panel"><h2>Your account</h2><Form onSubmit={data=>void action.run(async()=>{await api.patch('/account',{firstName:value(data,'firstName'),lastName:value(data,'lastName'),timezone:value(data,'timezone')});setMessage('Profile saved.');refresh();})}><div className="two-col"><label>First name<input name="firstName" required maxLength={100} defaultValue={person.firstName}/></label><label>Last name<input name="lastName" required maxLength={100} defaultValue={person.lastName}/></label></div><label>Email address<input value={person.email} disabled/></label><label>Timezone<input name="timezone" required maxLength={100} defaultValue={person.timezone} placeholder="Africa/Nairobi"/></label><Feedback error={action.error}/>{message&&<p className="success-message" role="status">{message}</p>}<button className="primary" disabled={action.busy}>Save profile</button></Form><hr/><h3>Password</h3><p>Request a secure reset link to change your password.</p><button className="secondary" disabled={action.busy} onClick={()=>void action.run(async()=>{await api.post('/auth/forgot-password',{email:person.email});setMessage('Password reset requested. Check your email or the development inbox.');})}>Send password reset link</button></section>{project&&['PROJECT_MANAGER','TEAM_LEAD'].includes(project.role)&&<section className="list-panel settings-panel"><h2>Project settings</h2><p>{project.name} · {project.status}</p><div className="button-row"><button className="secondary" onClick={editProject}>Edit project</button><button className="danger" onClick={archive}>Archive project</button></div></section>}</>;
}
function Root() {
  const [mode, setMode] = useState<ColorMode>(() => localStorage.getItem('taskflow.colorMode') === 'dark' ? 'dark' : 'light');
  const toggleTheme = () => setMode(current => { const next = current === 'dark' ? 'light' : 'dark'; localStorage.setItem('taskflow.colorMode', next); return next; });
  return <ThemeProvider theme={theme(mode)}><CssBaseline/><ApolloProvider client={graphqlClient}><QueryClientProvider client={queryClient}><App mode={mode} toggleTheme={toggleTheme}/></QueryClientProvider></ApolloProvider></ThemeProvider>;
}
createRoot(document.getElementById('root')!).render(<StrictMode><Root/></StrictMode>);
