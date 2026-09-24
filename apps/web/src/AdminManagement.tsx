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
  MenuItem,
  Paper,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  TextField,
  Tooltip,
  Typography,
} from '@mui/material';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { UserPlus, UserX, Trash2 } from 'lucide-react';
import { api, dateLabel } from './api';
import type { AdminCreateUserRequest, AdminOrganization, AdminProject, AdminUser } from './types/admin';

/* =========================================================
   PAGE CONFIG
========================================================= */

type Page = 'users' | 'organizations' | 'projects';

const copy: Record<Page, { title: string; description: string; endpoint: string }> = {
  users:         { title: 'Users',         description: 'Manage and monitor registered TaskFlow accounts.',       endpoint: '/admin/users' },
  organizations: { title: 'Organizations', description: 'View organizations across the TaskFlow platform.',        endpoint: '/admin/organizations' },
  projects:      { title: 'Projects',      description: 'Read-only oversight of projects across the platform.',  endpoint: '/admin/projects' },
};

/* =========================================================
   SEARCH HELPERS
========================================================= */

function matchesSearch(fields: (string | number | null | undefined)[], term: string): boolean {
  if (!term) return true;
  const lower = term.toLowerCase();
  return fields.some(f => f != null && String(f).toLowerCase().includes(lower));
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
    <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
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
  const [createOpen, setCreateOpen]   = useState(false);
  const info = copy[page];
  const queryClient = useQueryClient();

  const query = useQuery<AdminUser[] | AdminOrganization[] | AdminProject[]>({
    queryKey: ['admin', page],
    queryFn: () => api.get(info.endpoint).then(r => r.data),
    staleTime: 20_000,
    refetchInterval: 30_000, // auto-refresh every 30 seconds
  });

  const rows = useMemo(() => {
    const data = query.data ?? [];
    return data.filter(row => {
      const term = search.trim();
      if (page === 'users') {
        const u = row as AdminUser;
        return matchesSearch([u.firstName, u.lastName, u.email, u.id, u.status], term);
      }
      if (page === 'organizations') {
        const o = row as AdminOrganization;
        return matchesSearch([o.name, o.slug, o.owner], term);
      }
      const proj = row as AdminProject;
      return (
        matchesSearch([proj.name, proj.organizationName, proj.status], term) &&
        (!statusFilter || proj.status === statusFilter)
      );
    });
  }, [query.data, search, statusFilter, page]);

  const invalidate = () => void queryClient.invalidateQueries({ queryKey: ['admin', page] });

  return (
    <Box sx={{ p: { xs: 2, md: 3 } }}>
      {/* HEADER */}
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', mb: 1 }}>
        <Box>
          <Typography variant="h4" component="h1">{info.title}</Typography>
          <Typography color="text.secondary" sx={{ mt: 0.5, mb: 3 }}>{info.description}</Typography>
        </Box>
        {page === 'users' && (
          <Button
            variant="contained"
            startIcon={<UserPlus size={16} />}
            onClick={() => setCreateOpen(true)}
          >
            Add user
          </Button>
        )}
      </Box>

      {/* FILTERS */}
      <Box sx={{ display: 'flex', gap: 2, flexWrap: 'wrap', mb: 3 }}>
        <TextField
          size="small"
          label={`Search ${info.title.toLowerCase()}`}
          value={search}
          onChange={e => setSearch(e.target.value)}
          sx={{ minWidth: 260 }}
        />
        {page === 'projects' && (
          <TextField
            select size="small" label="Status"
            value={statusFilter} onChange={e => setStatusFilter(e.target.value)}
            sx={{ minWidth: 180 }}
          >
            <MenuItem value="">All statuses</MenuItem>
            {['PLANNING', 'ACTIVE', 'ON_HOLD', 'COMPLETED'].map(v => (
              <MenuItem value={v} key={v}>{v}</MenuItem>
            ))}
          </TextField>
        )}
        {query.isFetching && !query.isLoading && (
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
            <CircularProgress size={14} />
            <Typography variant="caption" color="text.secondary">Refreshing…</Typography>
          </Box>
        )}
      </Box>

      {/* STATES */}
      {query.isLoading && <Box sx={{ py: 6, textAlign: 'center' }}><CircularProgress /></Box>}
      {query.error    && <Alert severity="error">Unable to load {info.title.toLowerCase()}.</Alert>}
      {!query.isLoading && !query.error && rows.length === 0 && (
        <Alert severity="info">No {info.title.toLowerCase()} found{search ? ` matching "${search}"` : ''}.</Alert>
      )}

      {/* TABLE */}
      {rows.length > 0 && (
        <TableContainer component={Paper}>
          <Table size="small" aria-label={`${info.title} table`}>
            <TableHead>
              <TableRow>
                {page === 'users' ? (
                  <>
                    <TableCell>User</TableCell>
                    <TableCell>Email</TableCell>
                    <TableCell>Status</TableCell>
                    <TableCell>Organizations</TableCell>
                    <TableCell>Registered</TableCell>
                    <TableCell align="right">Actions</TableCell>
                  </>
                ) : page === 'organizations' ? (
                  <>
                    <TableCell>Organization</TableCell>
                    <TableCell>Owner</TableCell>
                    <TableCell>Members</TableCell>
                    <TableCell>Projects</TableCell>
                    <TableCell>Created</TableCell>
                  </>
                ) : (
                  <>
                    <TableCell>Project</TableCell>
                    <TableCell>Organization</TableCell>
                    <TableCell>Status</TableCell>
                    <TableCell>Tasks</TableCell>
                    <TableCell>Due date</TableCell>
                  </>
                )}
              </TableRow>
            </TableHead>
            <TableBody>
              {rows.map(row =>
                page === 'users' ? (
                  <UserRow key={row.id} row={row as AdminUser} onAction={invalidate} />
                ) : page === 'organizations' ? (
                  <OrganizationRow key={row.id} row={row as AdminOrganization} />
                ) : (
                  <ProjectRow key={row.id} row={row as AdminProject} />
                )
              )}
            </TableBody>
          </Table>
        </TableContainer>
      )}

      {/* CREATE USER DIALOG */}
      <CreateUserDialog
        open={createOpen}
        onClose={() => setCreateOpen(false)}
        onCreated={invalidate}
      />
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
        <TableCell>{row.firstName} {row.lastName}</TableCell>
        <TableCell>{row.email}</TableCell>
        <TableCell>
          <Chip
            label={row.status}
            size="small"
            color={row.status === 'active' ? 'success' : 'default'}
          />
        </TableCell>
        <TableCell>{row.organizationCount}</TableCell>
        <TableCell>{dateLabel(row.createdAt)}</TableCell>
        <TableCell align="right">
          <Tooltip title={isSuspended ? 'Already suspended' : 'Suspend account'}>
            <span>
              <IconButton
                size="small"
                color="warning"
                disabled={isBusy || isSuspended}
                onClick={() => {
                  if (window.confirm(`Suspend ${row.firstName} ${row.lastName}? They will no longer be able to log in. This can be reversed by contacting your database administrator.`))
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
                if (window.confirm(`Permanently delete ${row.firstName} ${row.lastName}? This cannot be undone. All their data will be removed.`))
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

function OrganizationRow({ row }: { row: AdminOrganization }) {
  return (
    <TableRow>
      <TableCell>
        <strong>{row.name}</strong><br />
        <Typography variant="caption">{row.slug}</Typography>
      </TableCell>
      <TableCell>{row.owner ?? 'No owner found'}</TableCell>
      <TableCell>{row.memberCount}</TableCell>
      <TableCell>{row.projectCount}</TableCell>
      <TableCell>{dateLabel(row.createdAt)}</TableCell>
    </TableRow>
  );
}

/* =========================================================
   PROJECT ROW
========================================================= */

function ProjectRow({ row }: { row: AdminProject }) {
  return (
    <TableRow>
      <TableCell>{row.name}</TableCell>
      <TableCell>{row.organizationName ?? 'Unknown'}</TableCell>
      <TableCell>{row.archivedAt ? 'ARCHIVED' : row.status}</TableCell>
      <TableCell>{row.taskCount}</TableCell>
      <TableCell>{dateLabel(row.dueDate ?? undefined)}</TableCell>
    </TableRow>
  );
}
