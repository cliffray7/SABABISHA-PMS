-- Migration 003: tenant-scoped human-readable activity timeline.
-- Separate from admin_audit_events, which remains the privileged audit trail.

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

IF OBJECT_ID('__PmsMigrations', 'U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM __PmsMigrations WHERE migration_id = '003_activity_events')
    INSERT INTO __PmsMigrations (migration_id) VALUES ('003_activity_events');
