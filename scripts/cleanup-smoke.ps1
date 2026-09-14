param([Parameter(Mandatory=$true)][ValidatePattern('^smoke-[a-f0-9]{32}$')][string]$TestPrefix)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$config = Get-Content (Join-Path $workspace 'src/Pms.Api/appsettings.json') -Raw | ConvertFrom-Json
$connection = New-Object System.Data.SqlClient.SqlConnection($config.ConnectionStrings.PmsDatabase)
try {
    $connection.Open()
    $command = $connection.CreateCommand()
    $command.CommandText = @'
SET XACT_ABORT ON;
BEGIN TRANSACTION;
DECLARE @users TABLE(id UNIQUEIDENTIFIER);
INSERT INTO @users SELECT id FROM users WHERE email LIKE @prefix + '-%@example.invalid';
DECLARE @orgs TABLE(id UNIQUEIDENTIFIER);
INSERT INTO @orgs SELECT id FROM organizations WHERE slug = @prefix;
DECLARE @projects TABLE(id UNIQUEIDENTIFIER);
INSERT INTO @projects SELECT id FROM projects WHERE organization_id IN (SELECT id FROM @orgs);
DECLARE @tasks TABLE(id UNIQUEIDENTIFIER);
INSERT INTO @tasks SELECT id FROM tasks WHERE project_id IN (SELECT id FROM @projects);
SELECT id FROM attachments WHERE task_id IN (SELECT id FROM @tasks);
DELETE FROM attachments WHERE task_id IN (SELECT id FROM @tasks);
DELETE FROM comment_mentions WHERE comment_id IN (SELECT id FROM comments WHERE task_id IN (SELECT id FROM @tasks));
DELETE FROM comments WHERE task_id IN (SELECT id FROM @tasks);
DELETE FROM task_assignees WHERE task_id IN (SELECT id FROM @tasks);
DELETE FROM tasks WHERE id IN (SELECT id FROM @tasks);
DELETE FROM project_members WHERE project_id IN (SELECT id FROM @projects);
DELETE FROM projects WHERE id IN (SELECT id FROM @projects);
DELETE FROM organization_invitations WHERE organization_id IN (SELECT id FROM @orgs);
DELETE FROM organization_members WHERE organization_id IN (SELECT id FROM @orgs);
DELETE FROM organizations WHERE id IN (SELECT id FROM @orgs);
DELETE FROM notifications WHERE user_id IN (SELECT id FROM @users);
DELETE FROM password_reset_tokens WHERE user_id IN (SELECT id FROM @users);
DELETE FROM refresh_tokens WHERE user_id IN (SELECT id FROM @users);
DELETE FROM login_otp_codes WHERE user_id IN (SELECT id FROM @users);
DELETE FROM users WHERE id IN (SELECT id FROM @users);
COMMIT;
'@
    $command.Parameters.AddWithValue('@prefix',$TestPrefix) | Out-Null
    $reader = $command.ExecuteReader()
    $fileIds = @()
    while ($reader.Read()) { $fileIds += ([guid]$reader.GetGuid(0)).ToString() }
    $reader.Close()
    $uploadRoot = [System.IO.Path]::GetFullPath((Join-Path $workspace 'src/Pms.Api/.data/uploads'))
    foreach ($id in $fileIds) {
        $target = [System.IO.Path]::GetFullPath((Join-Path $uploadRoot $id))
        if (-not $target.StartsWith($uploadRoot + [System.IO.Path]::DirectorySeparatorChar)) { throw 'Invalid test attachment path.' }
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target }
    }
    Write-Output 'Smoke-test records and attachments removed.'
} finally { $connection.Dispose() }
