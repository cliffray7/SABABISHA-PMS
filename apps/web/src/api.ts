import axios, { AxiosError, InternalAxiosRequestConfig } from 'axios';
import { ApolloClient, HttpLink, InMemoryCache } from '@apollo/client';
import { QueryClient } from '@tanstack/react-query';

export const api = axios.create({ baseURL: import.meta.env.VITE_API_URL ?? 'http://localhost:5141/api/v1' });
export const queryClient = new QueryClient({ defaultOptions: { queries: { staleTime: 30_000, retry: 1 } } });
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
export function saveAuth(auth: AuthResponse) { localStorage.setItem('taskflow.accessToken', auth.accessToken); localStorage.setItem('taskflow.refreshToken', auth.refreshToken); localStorage.setItem('taskflow.userId', auth.userId); }
export function clearAuth() { ['accessToken','refreshToken','userId','organizationId','projectId'].forEach(k => localStorage.removeItem('taskflow.' + k)); }
api.interceptors.request.use(config => { const token = localStorage.getItem('taskflow.accessToken'); if (token) config.headers.Authorization = `Bearer ${token}`; return config; });
let renewal: Promise<void> | null = null;
api.interceptors.response.use(r => r, async (error: AxiosError) => {
  const config = error.config as InternalAxiosRequestConfig & { retried?: boolean };
  if (error.response?.status === 401 && config && !config.retried && !config.url?.startsWith('/auth/')) {
    config.retried = true;
    if (!renewal) renewal = axios.post<AuthResponse>(`${api.defaults.baseURL}/auth/refresh`, { refreshToken: localStorage.getItem('taskflow.refreshToken') }).then(r => saveAuth(r.data)).catch(e => { clearAuth(); window.dispatchEvent(new Event('session-expired')); throw e; }).finally(() => { renewal = null; });
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
function configUrl(error: AxiosError) { return error.config?.url?.split('?')[0]; }
export type Person = { id: string; firstName: string; lastName: string; email: string; timezone: string };
export type Organization = { id: string; name: string; slug: string; role: string };
export type Project = { id: string; organizationId: string; name: string; description?: string; status: string; startDate?: string; dueDate?: string; role: string };
export type Member = { id: string; userId: string; firstName: string; lastName: string; email: string; role: string };
export type Task = { id: string; projectId: string; parentTaskId?: string; title: string; description?: string; status: string; priority: string; startDate?: string; dueDate?: string; completedAt?: string; assigneeIds: string[]; subtaskCount?: number; completedSubtaskCount?: number };
export type Subtask = { id: string; title: string; status: string; createdAt: string; completedAt?: string };
export type TaskActivity = { createdAt: string; action: string; detail?: string };
export type DashboardMetrics = { myTasks: number; overdueTasks: number; completedTasks: number; inProgressTasks: number; totalTasks: number };
export type AiTaskSuggestion = { title: string; description: string; priority: string; subtasks: string[] };
export type Notice = { id: string; message: string; isRead: boolean; createdAt: string; relatedId?: string; projectId?: string };
export type Invitation = { id: string; email: string; role: string; expiresAt: string };
export type Mail = { id: string; to: string; subject: string; link: string; createdAt: string; body?: string };
export const statuses = ['TO DO', 'IN PROGRESS', 'REVIEW', 'DONE'];
export const priorities = ['URGENT','HIGH','MEDIUM','LOW'];
export const projectStatuses = ['PLANNING','ACTIVE','ON_HOLD','COMPLETED'];
export const dateInput = (value?: string) => value?.slice(0,10) ?? '';
export const dateLabel = (value?: string) => value ? new Date(value.slice(0,10) + 'T12:00:00').toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' }) : 'No date';
export const overdue = (task: Task) => Boolean(task.dueDate && task.status !== 'DONE' && task.dueDate.slice(0,10) < new Date().toLocaleDateString('en-CA'));
export const initials = (first: string, last: string) => (first[0] ?? '') + (last[0] ?? '');
