-- Migration 002: append-only administrative audit events.
-- Apply this script to the existing SQL Server database before deploying the API.

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

IF OBJECT_ID('__PmsMigrations', 'U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM __PmsMigrations WHERE migration_id = '002_admin_audit_events')
    INSERT INTO __PmsMigrations (migration_id) VALUES ('002_admin_audit_events');
