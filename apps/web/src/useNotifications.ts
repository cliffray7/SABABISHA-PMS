import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { api, errorMessage, Notice } from './api';

export function useNotifications(authenticated: boolean, version: number) {
  const queryClient = useQueryClient();
  const query = useQuery({
    queryKey: ['notifications', authenticated, version],
    queryFn: async ({ signal }) => (await api.get<Notice[]>('/notifications', { signal })).data,
    enabled: authenticated,
    refetchInterval: authenticated ? 10_000 : false,
    refetchOnWindowFocus: true
  });
  const markMutation = useMutation({
    mutationFn: async (id?: string) => api.patch(id ? `/notifications/${id}/read` : '/notifications/read-all'),
    onSuccess: () => { void queryClient.invalidateQueries({ queryKey: ['notifications'] }); }
  });

  const markRead = async (id?: string) => {
    await markMutation.mutateAsync(id);
  };
  return { notices: query.data ?? [], error: query.error ? errorMessage(query.error) : markMutation.error ? errorMessage(markMutation.error) : '', reload: query.refetch, markRead };
}
