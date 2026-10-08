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

IF OBJECT_ID('__PmsMigrations', 'U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM __PmsMigrations WHERE migration_id = '006_task_assignment_events')
    INSERT INTO __PmsMigrations (migration_id) VALUES ('006_task_assignment_events');
