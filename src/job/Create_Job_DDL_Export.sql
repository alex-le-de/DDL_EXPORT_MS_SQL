/*
    Create_Job_DDL_Export.sql
    Legt den SQL-Server-Agent-Job "DDL_Export" an bzw. neu an (idempotent).

      Step 1 (T-SQL)  : EXEC ddl.usp_Export_Run   -> Snapshot in der Admin-DB
      Step 2 (CmdExec): Write-DdlExport.ps1       -> Dateien ins Git-Arbeitsverzeichnis
                        (laeuft unter dem Agent-Dienstkonto bzw. Proxy)

    Ausfuehrung: die drei Werte unten anpassen, dann in SSMS normal ausfuehren (F5)
    oder per  sqlcmd -S EVHNT56 -E -b -I -i Create_Job_DDL_Export.sql

    Zeitplan "Taeglich_0200" wird DEAKTIVIERT angelegt - nach dem ersten
    erfolgreichen manuellen Lauf aktivieren:
        EXEC msdb.dbo.sp_update_schedule @name = N'Taeglich_0200', @enabled = 1;
*/
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
USE [msdb];

/* ======================= ANPASSEN ======================= */
DECLARE @AdminDb      sysname        = N'DDL_Export_Admin';
DECLARE @WriterScript nvarchar(500)  = N'L:\Datenverarbeitung\DDL_EXPORT_MS_SQL\src\writer\Write-DdlExport.ps1';
DECLARE @JobOwner     sysname        = N'sa';
/* ======================================================== */

IF DB_ID(@AdminDb) IS NULL
BEGIN
    RAISERROR (N'Admin-DB %s existiert nicht - zuerst src\install\Install.sql ausfuehren.', 16, 1, @AdminDb);
    RETURN;
END;

BEGIN TRANSACTION;

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'DDL_Export')
    EXEC msdb.dbo.sp_delete_job @job_name = N'DDL_Export', @delete_unused_schedule = 1;

DECLARE @jobId binary(16);
-- Agent-Token: wird zur Laufzeit durch den Servernamen ersetzt (zusammengesetzt, damit sqlcmd es nicht als Variable auswertet)
DECLARE @srvToken nvarchar(50) = N'$' + N'(ESCAPE_NONE(SRVR))';
DECLARE @writerCmd nvarchar(4000) =
    N'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + @WriterScript + N'"'
    + N' -SqlInstance "' + @srvToken + N'" -AdminDatabase "' + @AdminDb + N'"';
DECLARE @descr nvarchar(512) =
    N'DDL-Export (T-SQL) der in ' + @AdminDb + N'.ddl.ExportDatabase konfigurierten Datenbanken ins Git-Arbeitsverzeichnis. Repo: DDL_EXPORT_MS_SQL. Git-Commit/Push manuell.';

EXEC msdb.dbo.sp_add_job
    @job_name              = N'DDL_Export',
    @enabled               = 1,
    @description           = @descr,
    @category_name         = N'[Uncategorized (Local)]',
    @owner_login_name      = @JobOwner,
    @notify_level_eventlog = 2,
    @job_id                = @jobId OUTPUT;

EXEC msdb.dbo.sp_add_jobstep @job_id = @jobId,
    @step_id           = 1,
    @step_name         = N'1 - Snapshot erzeugen (T-SQL)',
    @subsystem         = N'TSQL',
    @database_name     = @AdminDb,
    @command           = N'EXEC ddl.usp_Export_Run;',
    @on_success_action = 3,   -- weiter mit naechstem Step
    @on_fail_action    = 2;   -- Job mit Fehler beenden

EXEC msdb.dbo.sp_add_jobstep @job_id = @jobId,
    @step_id           = 2,
    @step_name         = N'2 - Dateien schreiben / DriftCheck (PowerShell)',
    @subsystem         = N'CmdExec',
    @command           = @writerCmd,
    @cmdexec_success_code = 0,
    @on_success_action = 1,   -- Job erfolgreich beenden
    @on_fail_action    = 2;

EXEC msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1;

EXEC msdb.dbo.sp_add_jobschedule @job_id = @jobId,
    @name               = N'Taeglich_0200',
    @enabled            = 0,
    @freq_type          = 4,      -- taeglich
    @freq_interval      = 1,
    @freq_subday_type   = 1,      -- einmal
    @active_start_time  = 20000;  -- 02:00:00

EXEC msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)';

COMMIT TRANSACTION;
PRINT N'Job DDL_Export angelegt (Zeitplan deaktiviert). Start: EXEC msdb.dbo.sp_start_job @job_name = N''DDL_Export'';';
