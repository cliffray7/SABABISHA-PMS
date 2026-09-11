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
    INNER JOIN task_assignees ta ON ta.task_id = t.id AND ta.user_id = @UserId AND ta.status = 'active'
    WHERE t.deleted_at IS NULL AND (@ProjectId IS NULL OR t.project_id = @ProjectId);
END;
