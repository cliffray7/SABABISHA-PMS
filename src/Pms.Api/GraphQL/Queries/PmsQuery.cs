using HotChocolate.Authorization;

namespace Pms.Api.GraphQL.Queries;

public sealed class PmsQuery
{
    [Authorize]
    public string ServiceName => "pms-api";

    [Authorize]
    public string Version => "v1";
}
