CREATE INDEX ix_refresh_tokens_user_expiry ON refresh_tokens(user_id, expires_at);
CREATE INDEX ix_organization_members_user_status ON organization_members(user_id, status);
CREATE INDEX ix_project_members_user_status ON project_members(user_id, status);
CREATE INDEX ix_tasks_project_status ON tasks(project_id, status) INCLUDE (title, priority, due_date);
CREATE INDEX ix_tasks_project_due_date ON tasks(project_id, due_date) WHERE deleted_at IS NULL;
CREATE INDEX ix_task_assignees_user_status ON task_assignees(user_id, status);
CREATE INDEX ix_comments_task_created ON comments(task_id, created_at);
CREATE INDEX ix_notifications_user_read_created ON notifications(user_id, is_read, created_at DESC);
