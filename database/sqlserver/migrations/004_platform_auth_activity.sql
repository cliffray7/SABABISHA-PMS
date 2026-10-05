IF COL_LENGTH('activity_events', 'organization_id') IS NOT NULL
    ALTER TABLE activity_events ALTER COLUMN organization_id UNIQUEIDENTIFIER NULL;

IF COL_LENGTH('activity_events', 'actor_user_id') IS NOT NULL
    ALTER TABLE activity_events ALTER COLUMN actor_user_id UNIQUEIDENTIFIER NULL;

IF OBJECT_ID('__PmsMigrations', 'U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM __PmsMigrations WHERE migration_id = '004_platform_auth_activity')
    INSERT INTO __PmsMigrations (migration_id) VALUES ('004_platform_auth_activity');