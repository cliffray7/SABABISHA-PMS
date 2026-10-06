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

GO
CREATE OR ALTER PROCEDURE usp_GetDashboardMetrics
    @UserId UNIQUEIDENTIFIER,
    @ProjectId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        COALESCE(SUM(CASE WHEN t.status <> 'DONE' THEN 1 ELSE 0 END), 0) AS MyTasks,
        COALESCE(SUM(CASE WHEN t.status <> 'DONE' AND t.due_date < SYSUTCDATETIME() THEN 1 ELSE 0 END), 0) AS OverdueTasks,
        COALESCE(SUM(CASE WHEN t.status = 'DONE' THEN 1 ELSE 0 END), 0) AS CompletedTasks,
        COALESCE(SUM(CASE WHEN t.status = 'IN PROGRESS' THEN 1 ELSE 0 END), 0) AS InProgressTasks,
        COUNT(*) AS TotalTasks
    FROM tasks t
    INNER JOIN projects p ON p.id = t.project_id AND p.deleted_at IS NULL
    INNER JOIN task_assignees ta ON ta.task_id = t.id AND ta.user_id = @UserId AND ta.status = 'active'
    WHERE t.deleted_at IS NULL AND (@ProjectId IS NULL OR t.project_id = @ProjectId);
END;
GO

IF OBJECT_ID('__PmsMigrations', 'U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM __PmsMigrations WHERE migration_id = '005_media_and_trash')
    INSERT INTO __PmsMigrations (migration_id) VALUES ('005_media_and_trash');
