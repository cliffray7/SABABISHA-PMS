using System.Data;
using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Pms.Infrastructure.Persistence.EfCore;

namespace Pms.Api;

public static class DatabaseMigrationRunner
{
    private static readonly (string MigrationId, string Script)[] EmbeddedMigrations =
    [
        ("002_admin_audit_events", """
IF OBJECT_ID('admin_audit_events', 'U') IS NULL
BEGIN
    CREATE TABLE admin_audit_events (
        id UNIQUEIDENTIFIER NOT NULL CONSTRAINT pk_admin_audit_events PRIMARY KEY,
        actor_id UNIQUEIDENTIFIER NOT NULL,
        actor_display_name NVARCHAR(201) NOT NULL,
        action NVARCHAR(80) NOT NULL,
        target_type NVARCHAR(80) NOT NULL,
        target_id UNIQUEIDENTIFIER NOT NULL,
        target_display_name NVARCHAR(300) NOT NULL,
        outcome NVARCHAR(20) NOT NULL,
        reason NVARCHAR(500) NULL,
        correlation_id NVARCHAR(128) NOT NULL,
        occurred_at DATETIMEOFFSET(7) NOT NULL
    );

    CREATE INDEX ix_admin_audit_events_occurred_at_id
        ON admin_audit_events (occurred_at DESC, id DESC);
    CREATE INDEX ix_admin_audit_events_actor_id_occurred_at
        ON admin_audit_events (actor_id, occurred_at DESC);
    CREATE INDEX ix_admin_audit_events_action_occurred_at
        ON admin_audit_events (action, occurred_at DESC);
    CREATE INDEX ix_admin_audit_events_target_type_target_id_occurred_at
        ON admin_audit_events (target_type, target_id, occurred_at DESC);
END;
"""),
        ("003_activity_events", """
IF OBJECT_ID('activity_events', 'U') IS NULL
BEGIN
    CREATE TABLE activity_events (
        id UNIQUEIDENTIFIER NOT NULL CONSTRAINT pk_activity_events PRIMARY KEY,
        organization_id UNIQUEIDENTIFIER NOT NULL,
        project_id UNIQUEIDENTIFIER NULL,
        actor_user_id UNIQUEIDENTIFIER NOT NULL,
        actor_name NVARCHAR(201) NOT NULL,
        category NVARCHAR(40) NOT NULL,
        action NVARCHAR(80) NOT NULL,
        entity_type NVARCHAR(40) NOT NULL,
        entity_id UNIQUEIDENTIFIER NOT NULL,
        entity_name NVARCHAR(300) NOT NULL,
        description NVARCHAR(500) NOT NULL,
        status NVARCHAR(20) NOT NULL,
        correlation_id NVARCHAR(128) NOT NULL,
        created_at_utc DATETIME2(7) NOT NULL
    );

    CREATE INDEX ix_activity_events_org_created_id
        ON activity_events (organization_id, created_at_utc DESC, id DESC);
    CREATE INDEX ix_activity_events_org_project_created
        ON activity_events (organization_id, project_id, created_at_utc DESC);
    CREATE INDEX ix_activity_events_org_category_created
        ON activity_events (organization_id, category, created_at_utc DESC);
    CREATE INDEX ix_activity_events_org_actor_created
        ON activity_events (organization_id, actor_user_id, created_at_utc DESC);
    CREATE INDEX ix_activity_events_org_entity
        ON activity_events (organization_id, entity_type, entity_id);
END;
"""),
        ("004_platform_auth_activity", """
IF COL_LENGTH('activity_events', 'organization_id') IS NOT NULL
    ALTER TABLE activity_events ALTER COLUMN organization_id UNIQUEIDENTIFIER NULL;

IF COL_LENGTH('activity_events', 'actor_user_id') IS NOT NULL
    ALTER TABLE activity_events ALTER COLUMN actor_user_id UNIQUEIDENTIFIER NULL;
"""),
        ("005_media_and_trash", """
IF COL_LENGTH('users', 'avatar_public_id') IS NULL
    ALTER TABLE users ADD avatar_public_id NVARCHAR(500) NULL;
IF COL_LENGTH('attachments', 'cloudinary_public_id') IS NULL
    ALTER TABLE attachments ADD cloudinary_public_id NVARCHAR(500) NULL;
IF COL_LENGTH('attachments', 'cloudinary_resource_type') IS NULL
    ALTER TABLE attachments ADD cloudinary_resource_type NVARCHAR(20) NULL;
IF COL_LENGTH('projects', 'deleted_at') IS NULL
    ALTER TABLE projects ADD deleted_at DATETIME2 NULL;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_projects_deleted_at' AND object_id = OBJECT_ID('projects'))
    CREATE INDEX ix_projects_deleted_at ON projects(deleted_at) WHERE deleted_at IS NOT NULL;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_tasks_deleted_at' AND object_id = OBJECT_ID('tasks'))
    CREATE INDEX ix_tasks_deleted_at ON tasks(deleted_at) WHERE deleted_at IS NOT NULL;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_comments_deleted_at' AND object_id = OBJECT_ID('comments'))
    CREATE INDEX ix_comments_deleted_at ON comments(deleted_at) WHERE deleted_at IS NOT NULL;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_attachments_deleted_at' AND object_id = OBJECT_ID('attachments'))
    CREATE INDEX ix_attachments_deleted_at ON attachments(deleted_at) WHERE deleted_at IS NOT NULL;
"""),
        ("006_task_assignment_events", """
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'uq_projects_id_organization_id' AND object_id = OBJECT_ID('projects'))
    CREATE UNIQUE INDEX uq_projects_id_organization_id ON projects(id, organization_id);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'uq_tasks_id_project_id' AND object_id = OBJECT_ID('tasks'))
    CREATE UNIQUE INDEX uq_tasks_id_project_id ON tasks(id, project_id);

IF OBJECT_ID('task_assignment_events', 'U') IS NULL
BEGIN
    CREATE TABLE task_assignment_events (
        event_id UNIQUEIDENTIFIER NOT NULL CONSTRAINT pk_task_assignment_events PRIMARY KEY,
        operation_id UNIQUEIDENTIFIER NOT NULL,
        organization_id UNIQUEIDENTIFIER NOT NULL,
        project_id UNIQUEIDENTIFIER NOT NULL,
        task_id UNIQUEIDENTIFIER NOT NULL,
        departing_user_id UNIQUEIDENTIFIER NOT NULL,
        replacement_user_id UNIQUEIDENTIFIER NULL,
        actor_user_id UNIQUEIDENTIFIER NOT NULL,
        occurred_at_utc DATETIME2(7) NOT NULL,
        action NVARCHAR(32) NOT NULL,
        reason_code NVARCHAR(40) NULL,
        CONSTRAINT ck_task_assignment_events_action_replacement_reason CHECK (
            (action = 'REASSIGNED' AND replacement_user_id IS NOT NULL
                AND replacement_user_id <> departing_user_id AND reason_code IS NULL)
            OR (action = 'UNASSIGNED' AND replacement_user_id IS NULL AND reason_code IS NULL)
            OR (action = 'LIFECYCLE_INACTIVATED' AND replacement_user_id IS NULL AND reason_code IS NOT NULL
                AND reason_code IN ('PROJECT_ARCHIVED', 'PROJECT_TRASHED', 'PROJECT_TRASH_EXPIRED'))
        ),
        CONSTRAINT fk_task_assignment_events_organization FOREIGN KEY (organization_id)
            REFERENCES organizations(id) ON DELETE NO ACTION,
        CONSTRAINT fk_task_assignment_events_project_scope FOREIGN KEY (project_id, organization_id)
            REFERENCES projects(id, organization_id) ON DELETE NO ACTION,
        CONSTRAINT fk_task_assignment_events_task_scope FOREIGN KEY (task_id, project_id)
            REFERENCES tasks(id, project_id) ON DELETE NO ACTION,
        CONSTRAINT fk_task_assignment_events_departing_user FOREIGN KEY (departing_user_id)
            REFERENCES users(id) ON DELETE NO ACTION,
        CONSTRAINT fk_task_assignment_events_replacement_user FOREIGN KEY (replacement_user_id)
            REFERENCES users(id) ON DELETE NO ACTION,
        CONSTRAINT fk_task_assignment_events_actor_user FOREIGN KEY (actor_user_id)
            REFERENCES users(id) ON DELETE NO ACTION
    );
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_task_assignment_events_task_time' AND object_id = OBJECT_ID('task_assignment_events'))
    CREATE INDEX ix_task_assignment_events_task_time ON task_assignment_events(task_id, occurred_at_utc, event_id);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_task_assignment_events_project_scope' AND object_id = OBJECT_ID('task_assignment_events'))
    CREATE INDEX ix_task_assignment_events_project_scope ON task_assignment_events(project_id, organization_id, task_id);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_task_assignment_events_operation' AND object_id = OBJECT_ID('task_assignment_events'))
    CREATE INDEX ix_task_assignment_events_operation ON task_assignment_events(operation_id, event_id);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_task_assignment_events_departing_user' AND object_id = OBJECT_ID('task_assignment_events'))
    CREATE INDEX ix_task_assignment_events_departing_user ON task_assignment_events(departing_user_id);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_task_assignment_events_actor_user' AND object_id = OBJECT_ID('task_assignment_events'))
    CREATE INDEX ix_task_assignment_events_actor_user ON task_assignment_events(actor_user_id);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'ix_task_assignment_events_replacement_user' AND object_id = OBJECT_ID('task_assignment_events'))
    CREATE INDEX ix_task_assignment_events_replacement_user ON task_assignment_events(replacement_user_id) WHERE replacement_user_id IS NOT NULL;
""")
    ];

    public static async Task ApplyPendingMigrationsAsync(IServiceProvider services, ILogger logger)
    {
        try
        {
            using var scope = services.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<PmsDbContext>();
            if (!db.Database.IsSqlServer()) return;

            var connectionString = db.Database.GetConnectionString();
            if (string.IsNullOrWhiteSpace(connectionString)) return;

            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync();

            await using (var cmd = connection.CreateCommand())
            {
                cmd.CommandText = """
IF OBJECT_ID('__PmsMigrations', 'U') IS NULL
BEGIN
    CREATE TABLE __PmsMigrations (
        migration_id NVARCHAR(150) NOT NULL PRIMARY KEY,
        applied_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
    );
END;
""";
                await cmd.ExecuteNonQueryAsync();
            }

            var applied = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            await using (var cmd = connection.CreateCommand())
            {
                cmd.CommandText = "SELECT migration_id FROM __PmsMigrations;";
                await using var reader = await cmd.ExecuteReaderAsync();
                while (await reader.ReadAsync())
                {
                    applied.Add(reader.GetString(0));
                }
            }

            foreach (var (migrationId, script) in EmbeddedMigrations)
            {
                if (applied.Contains(migrationId)) continue;

                logger.LogInformation("Applying automatic database migration {MigrationId}...", migrationId);
                var batches = Regex.Split(script, @"^\s*GO\s*$", RegexOptions.Multiline | RegexOptions.IgnoreCase);

                await using var tx = connection.BeginTransaction();
                try
                {
                    foreach (var batch in batches)
                    {
                        var trimmed = batch.Trim();
                        if (string.IsNullOrWhiteSpace(trimmed)) continue;

                        await using var batchCmd = connection.CreateCommand();
                        batchCmd.Transaction = tx;
                        batchCmd.CommandText = trimmed;
                        batchCmd.CommandTimeout = 120;
                        await batchCmd.ExecuteNonQueryAsync();
                    }

                    await using (var recordCmd = connection.CreateCommand())
                    {
                        recordCmd.Transaction = tx;
                        recordCmd.CommandText = "INSERT INTO __PmsMigrations (migration_id) VALUES (@id);";
                        recordCmd.Parameters.Add(new SqlParameter("@id", SqlDbType.NVarChar, 150) { Value = migrationId });
                        await recordCmd.ExecuteNonQueryAsync();
                    }

                    await tx.CommitAsync();
                    logger.LogInformation("Migration {MigrationId} applied successfully.", migrationId);
                }
                catch (Exception ex)
                {
                    await tx.RollbackAsync();
                    logger.LogError(ex, "Failed to apply migration {MigrationId}.", migrationId);
                    throw;
                }
            }
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "An error occurred while running automatic database migrations on startup.");
        }
    }
}

