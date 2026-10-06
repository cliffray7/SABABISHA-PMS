using Microsoft.AspNetCore.SignalR;

namespace Pms.Api.Realtime;

public sealed class RealtimePublisher(IHubContext<WorkspaceHub> hub)
{
    public Task OrganizationChanged(Guid organizationId, string area, CancellationToken ct = default) =>
        hub.Clients.Group(WorkspaceHub.OrganizationGroup(organizationId)).SendAsync("workspaceChanged", area, ct);

    public Task ProjectChanged(Guid organizationId, Guid projectId, string area, CancellationToken ct = default) =>
        Task.WhenAll(
            OrganizationChanged(organizationId, area, ct),
            hub.Clients.Group(WorkspaceHub.ProjectGroup(projectId)).SendAsync("workspaceChanged", area, ct));
}
