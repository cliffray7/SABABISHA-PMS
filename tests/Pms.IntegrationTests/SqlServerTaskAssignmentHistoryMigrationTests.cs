using Microsoft.Data.SqlClient;

namespace Pms.IntegrationTests;

public sealed class SqlServerTaskAssignmentHistoryMigrationTests
{
    [SqlServerManagerRaceTests.SqlServerFact]
    public async Task MigrationCreatesScopedAppendOnlyTableAndIsIdempotent()
    {
        var configuredConnection = Environment.GetEnvironmentVariable("PMS_TEST_SQLSERVER_CONNECTION")!;
        var databaseName = $"PmsAssignmentHistoryMigration_{Guid.NewGuid():N}";
        var masterConnection = new SqlConnectionStringBuilder(configuredConnection) { InitialCatalog = "master" }.ConnectionString;
        var targetConnection = new SqlConnectionStringBuilder(configuredConnection) { InitialCatalog = databaseName }.ConnectionString;
        await using (var connection = new SqlConnection(masterConnection))
        {
            await connection.OpenAsync();
            await using var command = connection.CreateCommand();
            command.CommandText = $"CREATE DATABASE [{databaseName}]";
            await command.ExecuteNonQueryAsync();
        }

        try
        {
            var migrationPath = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory,
                "../../../../../database/sqlserver/migrations/006_task_assignment_events.sql"));
            var migrationSql = await File.ReadAllTextAsync(migrationPath);
            await using var connection = new SqlConnection(targetConnection);
            await connection.OpenAsync();
            await using (var createBase = connection.CreateCommand())
            {
                createBase.CommandText = """
                    CREATE TABLE organizations (id UNIQUEIDENTIFIER NOT NULL PRIMARY KEY);
                    CREATE TABLE users (id UNIQUEIDENTIFIER NOT NULL PRIMARY KEY);
                    CREATE TABLE projects (id UNIQUEIDENTIFIER NOT NULL PRIMARY KEY, organization_id UNIQUEIDENTIFIER NOT NULL);
                    CREATE TABLE tasks (id UNIQUEIDENTIFIER NOT NULL PRIMARY KEY, project_id UNIQUEIDENTIFIER NOT NULL);
                    CREATE TABLE __PmsMigrations (migration_id NVARCHAR(150) NOT NULL PRIMARY KEY);
                    """;
                await createBase.ExecuteNonQueryAsync();
            }
            await using (var apply = connection.CreateCommand())
            {
                apply.CommandText = migrationSql;
                await apply.ExecuteNonQueryAsync();
            }
            await using (var applyAgain = connection.CreateCommand())
            {
                applyAgain.CommandText = migrationSql;
                await applyAgain.ExecuteNonQueryAsync();
            }
            await using var verify = connection.CreateCommand();
            verify.CommandText = "SELECT COUNT(*) FROM sys.foreign_keys WHERE parent_object_id = OBJECT_ID('task_assignment_events') AND delete_referential_action_desc = 'NO_ACTION'; SELECT COUNT(*) FROM sys.indexes WHERE object_id = OBJECT_ID('task_assignment_events') AND name LIKE 'ix_task_assignment_events_%';";
            await using var reader = await verify.ExecuteReaderAsync();
            Assert.True(await reader.ReadAsync());
            Assert.Equal(6, reader.GetInt32(0));
            Assert.True(await reader.NextResultAsync());
            Assert.True(await reader.ReadAsync());
            Assert.Equal(6, reader.GetInt32(0));
        }
        finally
        {
            await using var connection = new SqlConnection(masterConnection);
            await connection.OpenAsync();
            await using var command = connection.CreateCommand();
            command.CommandText = $"ALTER DATABASE [{databaseName}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{databaseName}]";
            await command.ExecuteNonQueryAsync();
        }
    }
}
