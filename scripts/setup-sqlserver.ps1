$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$databaseRoot = Join-Path $root 'database\sqlserver'
$composeRoot = Join-Path $root 'infrastructure\docker'
$envFile = Join-Path $composeRoot '.env'
$docker = Get-Command docker -ErrorAction SilentlyContinue
if (-not $docker) {
    $userDocker = Join-Path $env:LOCALAPPDATA 'Programs\DockerDesktop\resources\bin\docker.exe'
    if (Test-Path $userDocker) { $docker = Get-Item $userDocker }
}
if (-not $docker) { throw 'Docker CLI was not found. Restart Docker Desktop or add its CLI directory to PATH.' }
if (-not (Test-Path $envFile)) {
    Copy-Item (Join-Path $composeRoot '.env.example') $envFile
    throw "Created $envFile. Set MSSQL_SA_PASSWORD, then run this script again."
}

$dockerPath = if ($docker.Source) { $docker.Source } else { $docker.FullName }
$composeArgs = @('compose', '--env-file', $envFile, '-f', (Join-Path $composeRoot 'docker-compose.yml'))
& $dockerPath @composeArgs up -d sqlserver
if ($LASTEXITCODE -ne 0) { throw 'Unable to start SQL Server. Check Docker Desktop and the image download output above.' }

# Use stdin for SQL and the container environment for the password. This avoids
# nested PowerShell/bash quoting and keeps credentials out of command arguments.
function Invoke-DatabaseSql([string] $Database, [string] $Sql) {
    $command = 'export SQLCMDPASSWORD=$MSSQL_SA_PASSWORD; exec /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -I -b -l 5 -d ' + $Database
    $Sql | & $dockerPath @composeArgs exec -T sqlserver bash -c $command
    if ($LASTEXITCODE -ne 0) { throw "SQL command failed in database $Database." }
}

$ready = $false
for ($attempt = 1; $attempt -le 30; $attempt++) {
    try {
        Invoke-DatabaseSql 'master' 'SET NOCOUNT ON; SELECT 1;' | Out-Null
        $ready = $true
        break
    } catch {
        Write-Host "Waiting for SQL Server ($attempt/30)..."
        Start-Sleep -Seconds 2
    }
}
if (-not $ready) { throw 'SQL Server did not become ready. Check docker logs sababisha-pms-sqlserver.' }
Invoke-DatabaseSql 'master' "IF DB_ID('PmsDb') IS NULL CREATE DATABASE PmsDb;"

# An existing database can still be recovering after master accepts connections.
$databaseReady = $false
for ($attempt = 1; $attempt -le 30; $attempt++) {
    try {
        Invoke-DatabaseSql 'PmsDb' 'SET NOCOUNT ON; SELECT 1;' | Out-Null
        $databaseReady = $true
        break
    } catch {
        Write-Host "Waiting for PmsDb recovery ($attempt/30)..."
        Start-Sleep -Seconds 2
    }
}
if (-not $databaseReady) { throw 'PmsDb did not become ready. Check SQL Server recovery logs.' }

$files = @(
    'schema\001_initial_schema.sql',
    'security\001_login_otp_codes.sql',
    'stored-procedures\000_types.sql',
    'stored-procedures\usp_CreateTaskWithAssignees.sql',
    'stored-procedures\usp_GetDashboardMetrics.sql',
    'indexes\001_query_indexes.sql',
    'seed\001_reference_data.sql'
)
foreach ($file in $files) {
    $sql = Get-Content -Raw (Join-Path $databaseRoot $file)
    # A second setup run must preserve existing tables and indexes.
    if ($file -like 'schema\*') {
        $sql = [regex]::Replace($sql, '(?m)^CREATE TABLE (\w+)', 'IF OBJECT_ID(N''dbo.$1'', N''U'') IS NULL' + "`n" + 'CREATE TABLE $1')
    }
    if ($file -like 'indexes\*') {
        $sql = [regex]::Replace($sql, '(?m)^CREATE INDEX (\w+) ON (\w+)', 'IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N''$1'' AND object_id = OBJECT_ID(N''dbo.$2''))' + "`n" + 'CREATE INDEX $1 ON $2')
    }
    Write-Host "Applying $file"
    Invoke-DatabaseSql 'PmsDb' $sql
}
Write-Host 'SQL Server schema, procedures, indexes, and seed data applied successfully.'
