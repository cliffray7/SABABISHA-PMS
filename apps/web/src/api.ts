import axios, { AxiosError, InternalAxiosRequestConfig } from 'axios';
import { ApolloClient, HttpLink, InMemoryCache } from '@apollo/client';
import { QueryClient } from '@tanstack/react-query';
import { HubConnectionBuilder, LogLevel } from '@microsoft/signalr';

export const api = axios.create({ baseURL: import.meta.env.VITE_API_URL ?? 'http://localhost:5141/api/v1' });
export const queryClient = new QueryClient({ defaultOptions: { queries: { staleTime: 30_000, retry: 1, refetchOnWindowFocus: 'always', refetchOnReconnect: 'always', refetchIntervalInBackground: false } } });
export const graphqlClient = new ApolloClient({
  link: new HttpLink({
    uri: import.meta.env.VITE_GRAPHQL_URL ?? 'http://localhost:5141/graphql',
    fetch: (uri, options) => {
      const headers = new Headers(options?.headers);
      const token = localStorage.getItem('taskflow.accessToken');
      if (token) headers.set('Authorization', `Bearer ${token}`);
      return fetch(uri, { ...options, headers });
    }
  }),
  cache: new InMemoryCache()
});
export type AuthResponse = { userId: string; accessToken: string; refreshToken: string; accessTokenExpiresAt: string };
export const signedIn = () => Boolean(localStorage.getItem('taskflow.accessToken'));
export function createWorkspaceConnection(onChanged: (area: string) => void) {
  const connection = new HubConnectionBuilder()
    .withUrl(`${api.defaults.baseURL?.replace(/\/api\/v1\/?$/, '')}/hubs/workspace`, {
      accessTokenFactory: () => localStorage.getItem('taskflow.accessToken') ?? ''
    })
    .withAutomaticReconnect()
    .configureLogging(LogLevel.Warning)
    .build();
  connection.on('workspaceChanged', (area: string) => onChanged(area));
  return connection;
}
export function saveAuth(auth: AuthResponse) { localStorage.setItem('taskflow.accessToken', auth.accessToken); localStorage.setItem('taskflow.refreshToken', auth.refreshToken); localStorage.setItem('taskflow.userId', auth.userId); }
export function clearAuth() { ['accessToken','refreshToken','userId','organizationId','projectId'].forEach(k => localStorage.removeItem('taskflow.' + k)); }
type RetriableRequestConfig = InternalAxiosRequestConfig & { retried?: boolean; accessTokenAtRequest?: string };
api.interceptors.request.use(config => {
  const token = localStorage.getItem('taskflow.accessToken');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
    (config as RetriableRequestConfig).accessTokenAtRequest = token;
  }
  return config;
});
let renewal: Promise<void> | null = null;
api.interceptors.response.use(r => r, async (error: AxiosError) => {
  const config = error.config as RetriableRequestConfig;
  if (error.response?.status === 401 && config && !config.retried && !config.url?.startsWith('/auth/')) {
    config.retried = true;
    if (!renewal) {
      const renew = async () => {
        // Another tab may already have rotated the single-use refresh token.
        const currentAccessToken = localStorage.getItem('taskflow.accessToken');
        if (config.accessTokenAtRequest && currentAccessToken && currentAccessToken !== config.accessTokenAtRequest) return;
        const refreshToken = localStorage.getItem('taskflow.refreshToken');
        if (!refreshToken) {
          clearAuth();
          window.dispatchEvent(new Event('session-expired'));
          throw new Error('No refresh token is available.');
        }
        try {
          const response = await axios.post<AuthResponse>(`${api.defaults.baseURL}/auth/refresh`, { refreshToken });
          saveAuth(response.data);
        } catch (refreshError) {
          // A network/5xx failure may be temporary; retain the session so the
          // next request can retry. Only a rejected refresh token ends it.
          if (axios.isAxiosError(refreshError) && [400, 401].includes(refreshError.response?.status ?? 0)) {
            clearAuth();
            window.dispatchEvent(new Event('session-expired'));
          }
          throw refreshError;
        }
      };
      const refreshWithLock = (): Promise<void> => typeof navigator !== 'undefined' && navigator.locks
        ? navigator.locks.request<void>('taskflow-refresh-token', async () => { await renew(); })
        : renew();
      renewal = refreshWithLock().finally(() => { renewal = null; });
    }
    await renewal; return api(config);
  }
  return Promise.reject(error);
});
export function errorMessage(error: unknown): string {
  if (axios.isAxiosError(error)) {
    const data = error.response?.data;
    if (typeof data?.message === 'string') return data.message;
    if (data?.error?.message) return data.error.message;
    if (data?.errors) return Object.values(data.errors).flat().join(' ');
    if (error.response?.status === 403) return 'You no longer have access to this workspace, or your role does not allow this action.';
    if (error.response?.status === 401) return 'Your email or password is incorrect. Please log in again.';
    if (error.response?.status === 429) return 'Too many requests. Please wait a minute and try again.';
    if (error.response?.status === 404 && configUrl(error) === '/ai/tasks/suggest') return 'The AI endpoint was not found. Restart the API server, then try again.';
    if (!error.response) return 'Cannot reach the API. Check that the backend is running.';
    return 'The request could not be completed. Please try again.';
  }
  return error instanceof Error ? error.message : 'Something went wrong.';
}
const projectRoleErrorMessages: Record<string, string> = {
  invalid_project_role: 'Choose one of the supported project roles.',
  self_role_change_not_allowed: 'You cannot change your own project role this way.',
  guest_project_role_must_be_viewer: 'Organization guests can only have the Viewer project role.',
  project_must_retain_manager: 'This project must keep at least one active project manager.',
  project_role_update_forbidden: 'You do not have permission to change project member roles.',
  project_manager_grant_forbidden: 'Only organization admins and project managers can grant the Project Manager role.',
  project_role_update_conflict: 'The project is busy. Refresh the member list, then try again.'
};
export function projectRoleErrorMessage(error: unknown): string {
  if (axios.isAxiosError(error)) {
    const data = error.response?.data;
    if (typeof data?.code === 'string' && projectRoleErrorMessages[data.code]) return projectRoleErrorMessages[data.code];
  }
  return errorMessage(error);
}
const memberRemovalErrorMessages: Record<string, string> = {
  MEMBER_REMOVAL_FORBIDDEN: 'You do not have permission to remove this member.',
  MEMBER_RESOLUTION_REQUIRED: 'Resolve every affected task before confirming.',
  MEMBER_RESOLUTION_INVALID: 'One or more task resolutions are no longer valid.',
  MEMBER_REMOVAL_PREVIEW_STALE: 'Project or assignment data changed. Review a fresh preview before confirming.',
  MEMBER_REMOVAL_REPLACEMENT_INELIGIBLE: 'The selected replacement is no longer eligible. Review a fresh preview.',
  PROJECT_OWNER_TRANSFER_REQUIRED: 'Transfer project ownership before removing this member.',
  PROJECT_MUST_RETAIN_MANAGER: 'The project must retain at least one eligible active manager.',
  MEMBER_REMOVAL_CONFLICT: 'The workspace changed during removal. Review a fresh preview and retry.',
  MEMBER_RESOLUTION_LIMIT_EXCEEDED: 'This operation exceeds the supported task-resolution limit and was not applied.',
  ORGANIZATION_OWNER_CANNOT_BE_REMOVED: 'Transfer organization ownership before deactivating this member.',
  PROJECT_NOT_FOUND: 'The project is no longer available. Refresh the member list.',
  MEMBER_NOT_FOUND: 'The member is no longer available. Refresh the member list.'
};
export function memberRemovalErrorMessage(error: unknown): string {
  if (axios.isAxiosError(error)) {
    const data = error.response?.data;
    if (typeof data?.code === 'string' && memberRemovalErrorMessages[data.code]) return memberRemovalErrorMessages[data.code];
  }
  return errorMessage(error);
}
export type RemovalResolutionAction = 'REASSIGN' | 'UNASSIGN' | 'ACCEPT_LIFECYCLE_INACTIVATION';
export type MemberTaskResolution = { taskId: string; action: RemovalResolutionAction; replacementUserId: string | null };
export type RemovalReplacementMember = { userId: string; displayName: string };
export type RemovalTaskPreview = { taskId: string; parentTaskId: string | null; title: string; status: string; currentAssigneeIds: string[]; requiredResolution: string };
export type RemovalHistoricalAttribution = { taskId: string; status: string; taskInTrash: boolean; currentAssigneeIds: string[]; actionOnConfirm: string };
export type RemovalProjectPreview = { projectId: string; lifecycle: string; ownerTransferRequired: boolean; managerInvariantBlocked: boolean; eligibleReplacementMembers: RemovalReplacementMember[]; tasks: RemovalTaskPreview[]; historicalAttributionsToInactivate: RemovalHistoricalAttribution[] };
export type ExpiredTrashTaskPreview = { taskId: string; status: string; currentAssigneeIds: string[]; actionOnConfirm: string };
export type ExpiredTrashProjectPreview = { projectId: string; deletedAt: string; lifecycle: string; ownerManagerChecks: string; tasks: ExpiredTrashTaskPreview[] };
export type MemberRemovalPreview = { projectId: string | null; organizationId: string; memberId: string; snapshotHash: string; affectedTaskCount: number; affectedProjects: RemovalProjectPreview[]; expiredTrashCleanup: ExpiredTrashProjectPreview[] };
export type MemberRemovalRequest = { snapshotHash: string; resolutions: MemberTaskResolution[] };
export async function previewProjectMemberRemoval(projectId: string, userId: string) {
  return (await api.get<MemberRemovalPreview>(`/projects/${projectId}/members/${userId}/removal-preview`)).data;
}
export async function confirmProjectMemberRemoval(projectId: string, userId: string, request: MemberRemovalRequest) {
  await api.post(`/projects/${projectId}/members/${userId}/remove`, request);
}
export async function previewOrganizationMemberDeactivation(organizationId: string, userId: string) {
  return (await api.get<MemberRemovalPreview>(`/organizations/${organizationId}/members/${userId}/deactivation-preview`)).data;
}
export async function confirmOrganizationMemberDeactivation(organizationId: string, userId: string, request: MemberRemovalRequest) {
  await api.post(`/organizations/${organizationId}/members/${userId}/deactivate`, request);
}
function configUrl(error: AxiosError) { return error.config?.url?.split('?')[0]; }
export type Person = { id: string; firstName: string; lastName: string; email: string; timezone: string; avatarUrl?: string | null };
export type Organization = { id: string; name: string; slug: string; role: string };
export type Project = { id: string; organizationId: string; name: string; description?: string; status: string; startDate?: string; dueDate?: string; role: string };
export type Member = { id: string; userId: string; firstName: string; lastName: string; email: string; role: string; avatarUrl?: string | null };
export type Task = { id: string; projectId: string; parentTaskId?: string; title: string; description?: string; status: string; priority: string; startDate?: string; dueDate?: string; createdAt?: string; completedAt?: string; assigneeIds: string[]; subtaskCount?: number; completedSubtaskCount?: number };
export type Subtask = { id: string; title: string; status: string; createdAt: string; completedAt?: string };
export type TaskActivity = { createdAt: string; action: string; detail?: string };
export type DashboardMetrics = { myTasks: number; overdueTasks: number; completedTasks: number; inProgressTasks: number; totalTasks: number };
export type ProjectProgress = { projectId: string; projectStatus: string; hasTasks: boolean; totalEligibleTasks: number; completedTasks: number; progressPercent: number | null; outstandingTaskCount: number; overdueTaskCount: number; timezoneIdUsed: string };
export type AiTaskSuggestion = { title: string; description: string; priority: string; subtasks: string[] };
export type Notice = { id: string; message: string; isRead: boolean; createdAt: string; relatedId?: string; projectId?: string };
export type TrashItem = { kind: 'project' | 'task' | 'subtask' | 'comment' | 'attachment'; id: string; parentId?: string | null; projectId: string; name: string; deletedAt: string };
export type Invitation = { id: string; email: string; role: string; expiresAt: string };
export type Mail = { id: string; to: string; subject: string; link: string; createdAt: string; body?: string };
export const statuses = ['TO DO', 'IN PROGRESS', 'REVIEW', 'DONE'];
export const priorities = ['URGENT','HIGH','MEDIUM','LOW'];
export const projectStatuses = ['PLANNING','ACTIVE','ON_HOLD','COMPLETED'];
const projectStatusLabels: Record<string, string> = { PLANNING:'Planned', ACTIVE:'In Progress', ON_HOLD:'On Hold', COMPLETED:'Completed' };
const taskStatusLabels: Record<string, string> = { 'TO DO':'To Do', 'IN PROGRESS':'In Progress', REVIEW:'In Review', DONE:'Done' };
const readableStatusFallback = (status: string) => status.trim().replace(/_/g,' ').toLowerCase().replace(/\b\w/g, letter => letter.toUpperCase()) || 'Unknown';
export const projectStatusLabel = (status: string) => projectStatusLabels[status] ?? readableStatusFallback(status);
export const taskStatusLabel = (status: string) => taskStatusLabels[status] ?? readableStatusFallback(status);
export const dateInput = (value?: string) => value?.slice(0,10) ?? '';
export const dateLabel = (value?: string) => value ? new Date(value.slice(0,10) + 'T12:00:00').toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' }) : 'No date';
export const overdue = (task: Task) => Boolean(task.dueDate && task.status !== 'DONE' && task.dueDate.slice(0,10) < new Date().toLocaleDateString('en-CA'));
export const initials = (first: string, last: string) => (first[0] ?? '') + (last[0] ?? '');
export const formatDisplayName = (...parts: string[]) => parts.filter(Boolean).join(' ').trim().split(/\s+/).map(part => part.charAt(0).toLocaleUpperCase() + part.slice(1).toLocaleLowerCase()).join(' ');
