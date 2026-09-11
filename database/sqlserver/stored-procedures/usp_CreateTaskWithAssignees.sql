CREATE OR ALTER PROCEDURE usp_CreateTaskWithAssignees
    @TaskId UNIQUEIDENTIFIER,
    @ProjectId UNIQUEIDENTIFIER,
    @Title NVARCHAR(300),
    @Description NVARCHAR(MAX) = NULL,
    @Status NVARCHAR(40) = 'TO DO',
    @Priority NVARCHAR(20) = 'MEDIUM',
    @DueDate DATETIME2 = NULL,
    @CreatedBy UNIQUEIDENTIFIER,
    @Assignees dbo.GuidList READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;
    INSERT INTO tasks (id, project_id, title, description, status, priority, due_date, created_by)
    VALUES (@TaskId, @ProjectId, @Title, @Description, @Status, @Priority, @DueDate, @CreatedBy);
    INSERT INTO task_assignees (id, task_id, user_id)
    SELECT NEWID(), @TaskId, value FROM @Assignees;
    INSERT INTO notifications (id, user_id, type, message, entity_type, related_id)
    SELECT NEWID(), value, 'TASK_ASSIGNED', CONCAT('You were assigned task: ', @Title), 'TASK', @TaskId FROM @Assignees;
    COMMIT TRANSACTION;
    SELECT * FROM tasks WHERE id = @TaskId;
END;
