# Deploying Sababisha PMS

Deploy `apps/web` to Vercel and the .NET API to Railway or Render. Use a production SQL Server instance such as Azure SQL Database; this application does not use Postgres.

## API deployment

Both `railway.toml` and `render.yaml` build `infrastructure/docker/api.Dockerfile` and use `/api/v1/live` as the health check. The API respects the platform `PORT` variable.

Set these variables at the API host:

| Variable | Value |
| --- | --- |
| `ConnectionStrings__PmsDatabase` | Production SQL Server connection string |
| `Jwt__SigningKey` | Long, random secret (at least 32 bytes) |
| `Cors__AllowedOrigins__0` | `https://your-project.vercel.app` or custom frontend domain |
| `FrontendUrl` | Same frontend origin, without a trailing slash |
| `Uploads__Path` | Persistent mounted upload directory |
| `Smtp__Host`, `Smtp__From`, etc. | Production mail provider settings, if used |

Render's Blueprint mounts an upload disk at `/app/data`, using `/app/data/uploads`. A persistent disk limits an API to one instance; use object storage before scaling horizontally. On Railway, configure a volume and set `Uploads__Path` within its mount.

Before go-live, apply the SQL scripts in this order: schema, indexes, types, stored procedures, then seed data as required. They are all under `database/sqlserver`.

## Vercel deployment

Import this repository with these settings:

| Setting | Value |
| --- | --- |
| Root Directory | `apps/web` |
| Framework | Vite |
| Build Command | `npm run build` |
| Output Directory | `dist` |

Set these Vercel Production and Preview variables:

| Variable | Value |
| --- | --- |
| `VITE_API_URL` | `https://your-api-domain/api/v1` |
| `VITE_GRAPHQL_URL` | `https://your-api-domain/graphql` |

`VITE_` variables are public build-time configuration, so never put secrets in them. Redeploy Vercel after changing them. Use `apps/web/.env.example` for local configuration.

## Verification

Open `/api/v1/live`, then `/api/v1/ready` to confirm the API and SQL Server connection. Open the Vercel site, register an account, create a project, and upload a file. Confirm email links return to the Vercel domain.
