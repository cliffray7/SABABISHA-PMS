-- Migration 001: apply the Week 2 MVP schema.
-- Execute in order:
-- 1. ../schema/001_initial_schema.sql
-- 2. ../stored-procedures/000_types.sql
-- 3. ../stored-procedures/usp_CreateTaskWithAssignees.sql
-- 4. ../stored-procedures/usp_GetDashboardMetrics.sql
-- 5. ../indexes/001_query_indexes.sql

IF OBJECT_ID('__PmsMigrations') IS NULL
BEGIN
    CREATE TABLE __PmsMigrations (
        migration_id NVARCHAR(150) NOT NULL PRIMARY KEY,
        applied_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
    );
END;

IF NOT EXISTS (SELECT 1 FROM __PmsMigrations WHERE migration_id = '001_initial_schema')
    INSERT INTO __PmsMigrations (migration_id) VALUES ('001_initial_schema');
