import { useMemo, useState } from 'react';
import {
  Alert,
  Box,
  Button,
  Chip,
  CircularProgress,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  IconButton,
  InputAdornment,
  MenuItem,
  Paper,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TablePagination,
  TableRow,
  TableSortLabel,
  TextField,
  Tooltip,
  Typography,
} from '@mui/material';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { ChevronRight, Download, FolderKanban, Search, UserPlus, UserX, Trash2, X, Eye } from 'lucide-react';
import { api, dateLabel } from './api';
import type { AdminCreateUserRequest, AdminOrganization, AdminProject, AdminUser } from './types/admin';
import { ManagementTableLoading } from './components/AdminLoading';

/* =========================================================
   PAGE CONFIG
========================================================= */

type Page = 'users' | 'organizations' | 'projects';

const copy: Record<Page, { title: string; description: string; endpoint: string }> = {
  users:         { title: 'Users',         description: 'Review registered accounts and manage account access.', endpoint: '/admin/users' },
  organizations: { title: 'Organizations', description: 'Review organization ownership, membership, and project totals.', endpoint: '/admin/organizations' },
  projects:      { title: 'Projects',      description: 'Review project status, task volume, and due dates across workspaces.', endpoint: '/admin/projects' },
};

/* =========================================================
   SEARCH HELPERS
========================================================= */

function matchesSearch(fields: (string | number | null | undefined)[], term: string): boolean {
  if (!term) return true;
  const lower = term.toLowerCase();
  return fields.some(f => f != null && String(f).toLowerCase().includes(lower));
}

function exportOrganizations(records: AdminOrganization[]) {
  const csv = [
    ['Organization', 'Slug', 'Owner', 'Members', 'Projects', 'Created'],
    ...records.map(org => [org.name, org.slug, org.owner ?? '', org.memberCount, org.projectCount, org.createdAt]),
  ].map(row => row.map(value => `"${String(value).replace(/"/g, '""')}"`).join(',')).join('\r\n');
  const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }));
  const link = document.createElement('a');
  link.href = url;
  link.download = 'organizations.csv';
  link.click();
  window.setTimeout(() => URL.revokeObjectURL(url), 1000);
}

/* =========================================================
   CREATE USER DIALOG
========================================================= */

interface CreateUserDialogProps {
  open: boolean;
  onClose: () => void;
  onCreated: () => void;
}

function CreateUserDialog({ open, onClose, onCreated }: CreateUserDialogProps) {
  const [form, setForm] = useState<AdminCreateUserRequest>({
    firstName: '', lastName: '', email: '', password: '', timezone: 'UTC',
  });
  const [error, setError] = useState('');

  const mutation = useMutation({
    mutationFn: (data: AdminCreateUserRequest) =>
      api.post('/admin/users', data).then(r => r.data),
    onSuccess: () => {
      setForm({ firstName: '', lastName: '', email: '', password: '', timezone: 'UTC' });
      setError('');
      onCreated();
      onClose();
    },
    onError: (err: unknown) => {
      const msg =
        (err as { response?: { data?: { message?: string } } })?.response?.data?.message ??
        'Failed to create user. Please try again.';
      setError(msg);
    },
  });

  const field = (key: keyof AdminCreateUserRequest) => ({
    value: form[key] ?? '',
    onChange: (e: React.ChangeEvent<HTMLInputElement>) =>
      setForm(prev => ({ ...prev, [key]: e.target.value })),
  });

  return (
    <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth className="admin-create-user-dialog">
      <DialogTitle>Create user account</DialogTitle>
      <DialogContent sx={{ display: 'flex', flexDirection: 'column', gap: 2, pt: 2 }}>
        <Box sx={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 2 }}>
          <TextField label="First name" required size="small" {...field('firstName')} />
          <TextField label="Last name"  required size="small" {...field('lastName')} />
        </Box>
        <TextField label="Email address" type="email" required size="small" {...field('email')} />
        <TextField
          label="Temporary password"
          type="password"
          required
          size="small"
          helperText="Minimum 8 characters. User can reset this via forgot-password."
          {...field('password')}
        />
        <TextField
          label="Timezone"
          size="small"
          placeholder="Africa/Nairobi"
          helperText="Optional — defaults to UTC."
          {...field('timezone')}
        />
        {error && <Alert severity="error">{error}</Alert>}
      </DialogContent>
      <DialogActions sx={{ px: 3, pb: 2 }}>
        <Button onClick={onClose} disabled={mutation.isPending}>Cancel</Button>
        <Button
          variant="contained"
          disabled={mutation.isPending}
          onClick={() => mutation.mutate(form)}
        >
          {mutation.isPending ? <CircularProgress size={18} color="inherit" /> : 'Create user'}
        </Button>
      </DialogActions>
    </Dialog>
  );
}

/* =========================================================
   MAIN COMPONENT
========================================================= */

export default function AdminManagement({ page }: { page: Page }) {
  const [search, setSearch]           = useState('');
  const [statusFilter, setStatusFilter] = useState('');
  const [ownerFilter, setOwnerFilter] = useState('');
  const [selectedOrganization, setSelectedOrganization] = useState<AdminOrganization | null>(null);
  const [selectedProject, setSelectedProject] = useState<AdminProject | null>(null);
  const [createOpen, setCreateOpen]   = useState(false);
  const [pageIndex, setPageIndex] = useState(0);
  const [pageSize, setPageSize] = useState(10);
  const [sortBy, setSortBy] = useState(() => page === 'projects' ? 'dueDate' : 'createdAt');
  const [sortDirection, setSortDirection] = useState<'asc' | 'desc'>('desc');
  const info = copy[page];
  const queryClient = useQueryClient();

  const query = useQuery<AdminUser[] | AdminOrganization[] | AdminProject[]>({
    queryKey: ['admin', page],
    queryFn: () => api.get(info.endpoint).then(r => r.data),
    staleTime: 20_000,
    refetchInterval: 15_000, // keep platform records fresh while this page is open
  });

  const filteredRows = useMemo(() => {
    const data = query.data ?? [];
    return data.filter(row => {
      const term = search.trim();
      if (page === 'users') {
        const u = row as AdminUser;
        return matchesSearch([u.firstName, u.lastName, u.email, u.id, u.status], term);
      }
      if (page === 'organizations') {
        const o = row as AdminOrganization;
        return matchesSearch([o.name, o.slug, o.owner], term) && (!ownerFilter || o.owner === ownerFilter);
      }
      const proj = row as AdminProject;
      return (
        matchesSearch([proj.name, proj.organizationName, proj.status], term) &&
        (!statusFilter || proj.status === statusFilter)
      );
    });
  }, [query.data, search, statusFilter, ownerFilter, page]);

  const sortedRows = useMemo(() => {
    const valueFor = (row: AdminUser | AdminOrganization | AdminProject): string | number | null => {
      if (page === 'users') {
        const user = row as AdminUser;
        return ({ user: `${user.firstName} ${user.lastName}`, email: user.email, status: user.status, organizations: user.organizationCount, createdAt: user.createdAt } as Record<string, string | number>)[sortBy] ?? '';
      }
      if (page === 'organizations') {
        const org = row as AdminOrganization;
        return ({ organization: org.name, owner: org.owner ?? '', members: org.memberCount, projects: org.projectCount, createdAt: org.createdAt } as Record<string, string | number>)[sortBy] ?? '';
      }
      const project = row as AdminProject;
      return ({ project: project.name, organization: project.organizationName ?? '', status: project.archivedAt ? 'Archived' : project.status, tasks: project.taskCount, dueDate: project.dueDate ?? '' } as Record<string, string | number>)[sortBy] ?? '';
    };
    return [...filteredRows].sort((left, right) => {
      const a = valueFor(left); const b = valueFor(right);
      const comparison = typeof a === 'number' && typeof b === 'number' ? a - b : String(a).localeCompare(String(b), undefined, { numeric: true, sensitivity: 'base' });
      return sortDirection === 'asc' ? comparison : -comparison;
    });
  }, [filteredRows, page, sortBy, sortDirection]);
  const rows = sortedRows.slice(pageIndex * pageSize, pageIndex * pageSize + pageSize);
  const sort = (field: string) => {
    setPageIndex(0);
    if (sortBy === field) setSortDirection(direction => direction === 'asc' ? 'desc' : 'asc');
    else { setSortBy(field); setSortDirection('asc'); }
  };
  const clearFilters = () => { setSearch(''); setStatusFilter(''); setOwnerFilter(''); setPageIndex(0); };

  const invalidate = () => void queryClient.invalidateQueries({ queryKey: ['admin', page] });

  return (
    <Box className={`admin-management-page admin-management-${page}`}>
      {/* HEADER */}
      <Box className="admin-management-header" sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', mb: 1 }}>
        <Box>
          <div className="admin-management-title-line">
            <Typography variant="h4" component="h1" className="admin-management-title">{info.title}</Typography>
            {page !== 'users' && <Tooltip title="Records on this page cannot be edited from platform administration"><Chip size="small" variant="outlined" icon={<Eye size={13} />} label="View only" className="admin-management-view-only" /></Tooltip>}
          </div>
          <Typography color="text.secondary" className="admin-management-description" sx={{ mt: 0.5, mb: 1 }}>{info.description}</Typography>
        </Box>
        <Box className="admin-management-actions">
          {page === 'users' && <Button
            variant="contained"
            className="admin-management-add-user"
            startIcon={<UserPlus size={16} />}
            onClick={() => setCreateOpen(true)}
          >
            Add user
          </Button>}
        </Box>
      </Box>

      {/* FILTERS */}
      <Box className="admin-management-filters" sx={{ mb: 2 }}>
        <div className="admin-management-filter-controls">
        <TextField
          size="small"
          inputProps={{ 'aria-label': `Search ${info.title.toLowerCase()}` }}
          placeholder={page === 'users' ? 'Search by name, email, or account status' : page === 'organizations' ? 'Search organizations by name, slug, or owner' : 'Search projects by name, organization, or status'}
          value={search}
          onChange={e => { setSearch(e.target.value); setPageIndex(0); }}
          InputProps={{
            startAdornment: <InputAdornment position="start"><Search size={16} className="admin-management-search-icon" /></InputAdornment>,
            endAdornment: search ? <InputAdornment position="end"><IconButton size="small" aria-label="Clear search" onClick={() => { setSearch(''); setPageIndex(0); }}><X size={15} /></IconButton></InputAdornment> : undefined,
          }}
          className="admin-management-search"
        />
        {page === 'organizations' && query.data && (
          <TextField select size="small" value={ownerFilter} className="admin-management-owner-filter" SelectProps={{ displayEmpty: true, renderValue: selected => selected ? String(selected) : 'All owners' }} inputProps={{ 'aria-label': 'Filter organizations by owner' }} onChange={e => { setOwnerFilter(e.target.value); setPageIndex(0); }}>
            <MenuItem value="">All owners</MenuItem>
            {[...new Set((query.data as AdminOrganization[]).map(org => org.owner).filter((owner): owner is string => Boolean(owner)))].sort().map(owner => <MenuItem key={owner} value={owner}>{owner}</MenuItem>)}
          </TextField>
        )}
        {page === 'projects' && (
          <TextField
            select size="small" className="admin-management-status-filter"
            SelectProps={{ displayEmpty: true, renderValue: selected => selected ? String(selected).replace(/_/g, ' ').replace(/\b\w/g, letter => letter.toUpperCase()) : 'All project statuses' }}
            inputProps={{ 'aria-label': 'Filter projects by status' }}
            value={statusFilter} onChange={e => { setStatusFilter(e.target.value); setPageIndex(0); }}
          >
            <MenuItem value="">All project statuses</MenuItem>
            {['PLANNING', 'ACTIVE', 'ON_HOLD', 'COMPLETED'].map(v => (
              <MenuItem value={v} key={v}>{v === 'ON_HOLD' ? 'On hold' : v.charAt(0) + v.slice(1).toLowerCase()}</MenuItem>
            ))}
          </TextField>
        )}
        {(search || statusFilter || ownerFilter) && <Button className="admin-management-clear-filters" startIcon={<X size={14} />} onClick={clearFilters}>Clear</Button>}
        {query.isFetching && !query.isLoading && (
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
            <CircularProgress size={14} />
            <Typography variant="caption" color="text.secondary">Refreshing…</Typography>
          </Box>
        )}
        <span className="admin-management-filter-count"><strong>{filteredRows.length.toLocaleString()}</strong> of {(query.data?.length ?? 0).toLocaleString()} records</span>
        {page === 'organizations' && <Button className="admin-management-export" startIcon={<Download size={14} />} onClick={() => exportOrganizations(filteredRows as AdminOrganization[])} disabled={!filteredRows.length}>Export CSV</Button>}
        </div>
      </Box>

      {/* STATES */}
      {query.isLoading && <ManagementTableLoading label={info.title.toLowerCase()} />}
      {query.error    && <Alert severity="error">Unable to load {info.title.toLowerCase()}.</Alert>}
      {!query.isLoading && !query.error && filteredRows.length === 0 && (
        <div className="admin-management-empty"><strong>{query.data?.length ? `No ${info.title.toLowerCase()} match your search` : `No ${info.title.toLowerCase()} are available yet`}</strong><span>{search ? `No results for “${search}”. Adjust your search or clear the filters.` : 'Try adjusting the selected filters.'}</span>{(search || statusFilter || ownerFilter) && <Button size="small" onClick={clearFilters}>Clear filters</Button>}</div>
      )}

      {/* TABLE */}
      {rows.length > 0 && (
        <TableContainer component={Paper} className="admin-management-table-wrap">
          <Table size="small" aria-label={`${info.title} table`} className="admin-management-table">
            <TableHead>
              <TableRow>
                {page === 'users' ? (
                  <>
                    <TableCell><TableSortLabel active={sortBy === 'user'} direction={sortBy === 'user' ? sortDirection : 'asc'} onClick={() => sort('user')}>User</TableSortLabel></TableCell>
                    <TableCell><TableSortLabel active={sortBy === 'email'} direction={sortBy === 'email' ? sortDirection : 'asc'} onClick={() => sort('email')}>Email</TableSortLabel></TableCell>
                    <TableCell><TableSortLabel active={sortBy === 'status'} direction={sortBy === 'status' ? sortDirection : 'asc'} onClick={() => sort('status')}>Status</TableSortLabel></TableCell>
                    <TableCell><TableSortLabel active={sortBy === 'organizations'} direction={sortBy === 'organizations' ? sortDirection : 'asc'} onClick={() => sort('organizations')}>Organizations</TableSortLabel></TableCell>
                    <TableCell><TableSortLabel active={sortBy === 'createdAt'} direction={sortBy === 'createdAt' ? sortDirection : 'asc'} onClick={() => sort('createdAt')}>Registered</TableSortLabel></TableCell>
                    <TableCell align="right">Actions</TableCell>
                  </>
                ) : page === 'organizations' ? (
                  <>
                    <TableCell><TableSortLabel aria-label="Sort by organization name" active={sortBy === 'organization'} direction={sortBy === 'organization' ? sortDirection : 'asc'} onClick={() => sort('organization')}>Organization</TableSortLabel></TableCell>
                    <TableCell><TableSortLabel aria-label="Sort by owner" active={sortBy === 'owner'} direction={sortBy === 'owner' ? sortDirection : 'asc'} onClick={() => sort('owner')}>Owner</TableSortLabel></TableCell>
                    <TableCell><TableSortLabel aria-label="Sort by member count" active={sortBy === 'members'} direction={sortBy === 'members' ? sortDirection : 'asc'} onClick={() => sort('members')}>Members</TableSortLabel></TableCell>
                    <TableCell><TableSortLabel aria-label="Sort by project count" active={sortBy === 'projects'} direction={sortBy === 'projects' ? sortDirection : 'asc'} onClick={() => sort('projects')}>Projects</TableSortLabel></TableCell>
                    <TableCell><TableSortLabel aria-label="Sort by creation date" active={sortBy === 'createdAt'} direction={sortBy === 'createdAt' ? sortDirection : 'asc'} onClick={() => sort('createdAt')}>Created</TableSortLabel></TableCell>
                    <TableCell align="right">Details</TableCell>
                  </>
                ) : (
                  <>
                    <TableCell><TableSortLabel aria-label="Sort by project name" active={sortBy === 'project'} direction={sortBy === 'project' ? sortDirection : 'asc'} onClick={() => sort('project')}>Project</TableSortLabel></TableCell>
                    <TableCell><TableSortLabel aria-label="Sort by organization" active={sortBy === 'organization'} direction={sortBy === 'organization' ? sortDirection : 'asc'} onClick={() => sort('organization')}>Organization</TableSortLabel></TableCell>
                    <TableCell><TableSortLabel aria-label="Sort by project status" active={sortBy === 'status'} direction={sortBy === 'status' ? sortDirection : 'asc'} onClick={() => sort('status')}>Status</TableSortLabel></TableCell>
                    <TableCell><TableSortLabel aria-label="Sort by task count" active={sortBy === 'tasks'} direction={sortBy === 'tasks' ? sortDirection : 'asc'} onClick={() => sort('tasks')}>Tasks</TableSortLabel></TableCell>
                    <TableCell><TableSortLabel aria-label="Sort by due date" active={sortBy === 'dueDate'} direction={sortBy === 'dueDate' ? sortDirection : 'asc'} onClick={() => sort('dueDate')}>Due date</TableSortLabel></TableCell>
                    <TableCell align="right">Details</TableCell>
                  </>
                )}
              </TableRow>
            </TableHead>
            <TableBody>
              {rows.map(row =>
                page === 'users' ? (
                  <UserRow key={row.id} row={row as AdminUser} onAction={invalidate} />
                ) : page === 'organizations' ? (
                  <OrganizationRow key={row.id} row={row as AdminOrganization} onView={setSelectedOrganization} />
                ) : (
                  <ProjectRow key={row.id} row={row as AdminProject} onView={setSelectedProject} />
                )
              )}
            </TableBody>
          </Table>
          <TablePagination component="div" count={sortedRows.length} page={pageIndex} rowsPerPage={pageSize} rowsPerPageOptions={[10, 25, 50]} onPageChange={(_, nextPage) => setPageIndex(nextPage)} onRowsPerPageChange={event => { setPageSize(Number(event.target.value)); setPageIndex(0); }} />
        </TableContainer>
      )}

      {/* CREATE USER DIALOG */}
      <CreateUserDialog
        open={createOpen}
        onClose={() => setCreateOpen(false)}
        onCreated={invalidate}
      />
      <Dialog open={Boolean(selectedOrganization)} onClose={() => setSelectedOrganization(null)} maxWidth="xs" fullWidth>
        {selectedOrganization && <>
          <DialogTitle>{selectedOrganization.name}</DialogTitle>
          <DialogContent dividers className="admin-record-summary">
            <p>Organization summary</p>
            <dl><dt>Workspace slug</dt><dd>{selectedOrganization.slug}</dd><dt>Owner</dt><dd>{selectedOrganization.owner ?? 'No owner listed'}</dd><dt>Members</dt><dd>{selectedOrganization.memberCount.toLocaleString()} {selectedOrganization.memberCount === 1 ? 'member' : 'members'}</dd><dt>Projects</dt><dd>{selectedOrganization.projectCount.toLocaleString()} {selectedOrganization.projectCount === 1 ? 'project' : 'projects'}</dd><dt>Created</dt><dd>{dateLabel(selectedOrganization.createdAt)}</dd></dl>
            <span>This view shows organization totals only. Member details and activity are unavailable here.</span>
          </DialogContent>
          <DialogActions><Button onClick={() => setSelectedOrganization(null)}>Close</Button></DialogActions>
        </>}
      </Dialog>
      <Dialog open={Boolean(selectedProject)} onClose={() => setSelectedProject(null)} maxWidth="xs" fullWidth>
        {selectedProject && <>
          <DialogTitle>{selectedProject.name}</DialogTitle>
          <DialogContent dividers className="admin-record-summary">
            <p>Project summary</p>
            <dl><dt>Organization</dt><dd>{selectedProject.organizationName ?? 'No organization listed'}</dd><dt>Status</dt><dd>{selectedProject.archivedAt ? 'Archived' : selectedProject.status.toLowerCase().replace(/_/g, ' ').replace(/\b\w/g, letter => letter.toUpperCase())}</dd><dt>Tasks</dt><dd>{selectedProject.taskCount.toLocaleString()} {selectedProject.taskCount === 1 ? 'task' : 'tasks'}</dd><dt>Due date</dt><dd>{selectedProject.dueDate ? dateLabel(selectedProject.dueDate) : 'No due date'}</dd><dt>Created</dt><dd>{dateLabel(selectedProject.createdAt)}</dd></dl>
            <span>Task details and project activity are not included in the current platform project data.</span>
          </DialogContent>
          <DialogActions><Button onClick={() => setSelectedProject(null)}>Close</Button></DialogActions>
        </>}
      </Dialog>
    </Box>
  );
}

/* =========================================================
   USER ROW — with suspend + delete actions
========================================================= */

function UserRow({ row, onAction }: { row: AdminUser; onAction: () => void }) {
  const [actionError, setActionError] = useState('');

  const suspend = useMutation({
    mutationFn: () => api.delete(`/admin/users/${row.id}`),
    onSuccess: onAction,
    onError: (err: unknown) => {
      const msg =
        (err as { response?: { data?: { message?: string } } })?.response?.data?.message ??
        'Failed to suspend user.';
      setActionError(msg);
    },
  });

  const remove = useMutation({
    mutationFn: () => api.delete(`/admin/users/${row.id}?permanent=true`),
    onSuccess: onAction,
    onError: (err: unknown) => {
      const msg =
        (err as { response?: { data?: { message?: string } } })?.response?.data?.message ??
        'Failed to delete user.';
      setActionError(msg);
    },
  });

  const isBusy = suspend.isPending || remove.isPending;
  const isSuspended = row.status === 'suspended';

  return (
    <>
      <TableRow sx={isSuspended ? { opacity: 0.6 } : undefined}>
        <TableCell><span className="admin-management-user"><span className="admin-management-user-avatar" aria-hidden="true">{row.firstName.charAt(0)}{row.lastName.charAt(0)}</span><strong>{row.firstName} {row.lastName}</strong></span></TableCell>
        <TableCell>{row.email}</TableCell>
        <TableCell>
          <Chip
            label={row.status}
            size="small"
            className={`admin-management-status ${row.status.toLowerCase()}`}
            color={row.status === 'active' ? 'success' : 'default'}
          />
        </TableCell>
        <TableCell>{row.organizationCount}</TableCell>
        <TableCell>{dateLabel(row.createdAt)}</TableCell>
        <TableCell align="right">
          <Tooltip title={isSuspended ? 'Already suspended' : 'Suspend account; existing access tokens expire normally'}>
            <span>
              <IconButton
                size="small"
                color="warning"
                disabled={isBusy || isSuspended}
                onClick={() => {
                  if (window.confirm(`Suspend ${row.firstName} ${row.lastName}? They will be unable to sign in or refresh their session. Existing access tokens may remain valid until they expire. Continue?`))
                    suspend.mutate();
                }}
              >
                <UserX size={16} />
              </IconButton>
            </span>
          </Tooltip>
          <Tooltip title="Permanently delete account">
            <IconButton
              size="small"
              color="error"
              disabled={isBusy}
              onClick={() => {
                if (window.confirm(`Permanently delete ${row.firstName} ${row.lastName}? Sign-in credentials and the account will be removed. If workspace or project records still reference this account, deletion will be blocked and those records will be preserved. Suspend the account instead if you need to retain its history. Continue?`))
                  remove.mutate();
              }}
            >
              <Trash2 size={16} />
            </IconButton>
          </Tooltip>
        </TableCell>
      </TableRow>
      {actionError && (
        <TableRow>
          <TableCell colSpan={6} sx={{ py: 0 }}>
            <Alert severity="error" onClose={() => setActionError('')} sx={{ py: 0 }}>{actionError}</Alert>
          </TableCell>
        </TableRow>
      )}
    </>
  );
}

/* =========================================================
   ORG ROW
========================================================= */

function OrganizationRow({ row, onView }: { row: AdminOrganization; onView: (organization: AdminOrganization) => void }) {
  return (
    <TableRow hover tabIndex={0} aria-label={`Open summary for ${row.name}`} sx={{ cursor: 'pointer' }} onClick={() => onView(row)} onKeyDown={event => { if (event.target === event.currentTarget && (event.key === 'Enter' || event.key === ' ')) { event.preventDefault(); onView(row); } }}>
      <TableCell>
        <span className="admin-management-org"><span className="admin-management-org-mark">{row.name.slice(0, 1).toUpperCase()}</span><span><strong>{row.name}</strong><small>{row.slug}</small></span></span>
      </TableCell>
      <TableCell>{row.owner ? <span className="admin-management-owner"><span>{row.owner.slice(0, 1).toUpperCase()}</span>{row.owner}</span> : <span className="admin-management-no-owner">No owner found</span>}</TableCell>
      <TableCell><span className="admin-management-number">{row.memberCount.toLocaleString()}<small>{row.memberCount === 1 ? 'member' : 'members'}</small></span></TableCell>
      <TableCell><span className="admin-management-number">{row.projectCount.toLocaleString()}<small>{row.projectCount === 1 ? 'project' : 'projects'}</small></span></TableCell>
      <TableCell><Tooltip title={new Date(row.createdAt).toLocaleString()}><span>{relativeDate(row.createdAt)}</span></Tooltip></TableCell>
      <TableCell align="right"><Button size="small" className="admin-management-view-link" endIcon={<ChevronRight size={14} />} onClick={event => { event.stopPropagation(); onView(row); }} aria-label={`View ${row.name} organization summary`}>View</Button></TableCell>
    </TableRow>
  );
}

function relativeDate(value: string): string {
  const elapsedDays = Math.floor((Date.now() - new Date(value).getTime()) / 86_400_000);
  if (!Number.isFinite(elapsedDays) || elapsedDays < 0) return dateLabel(value);
  if (elapsedDays === 0) return 'Today';
  if (elapsedDays === 1) return 'Yesterday';
  if (elapsedDays < 30) return `${elapsedDays} days ago`;
  return dateLabel(value);
}

/* =========================================================
   PROJECT ROW
========================================================= */

function ProjectRow({ row, onView }: { row: AdminProject; onView: (project: AdminProject) => void }) {
  const statusClass = row.archivedAt ? 'archived' : row.status.toLowerCase().replace(/_/g, '-');
  const statusLabel = row.archivedAt ? 'Archived' : row.status.toLowerCase().replace(/_/g, ' ').replace(/\b\w/g, letter => letter.toUpperCase());
  return (
    <TableRow hover tabIndex={0} aria-label={`Open summary for ${row.name}`} sx={{ cursor: 'pointer' }} onClick={() => onView(row)} onKeyDown={event => { if (event.target === event.currentTarget && (event.key === 'Enter' || event.key === ' ')) { event.preventDefault(); onView(row); } }}>
      <TableCell><span className="admin-management-project"><span className="admin-management-project-mark"><FolderKanban size={15}/></span><strong>{row.name}</strong></span></TableCell>
      <TableCell>{row.organizationName ?? <span className="admin-management-no-owner">No organization</span>}</TableCell>
      <TableCell><Chip size="small" label={statusLabel} className={`admin-management-status ${statusClass}`}/></TableCell>
      <TableCell><span className="admin-management-number">{row.taskCount.toLocaleString()}<small>{row.taskCount === 1 ? 'task' : 'tasks'}</small></span></TableCell>
      <TableCell>{row.dueDate ? dateLabel(row.dueDate) : <span className="admin-management-no-owner">No due date</span>}</TableCell>
      <TableCell align="right"><Button size="small" className="admin-management-view-link" endIcon={<ChevronRight size={14} />} onClick={event => { event.stopPropagation(); onView(row); }} aria-label={`View ${row.name} project summary`}>View</Button></TableCell>
    </TableRow>
  );
}
