/*
    08_Script_Jobs.sql
    ddl.usp_Script_Jobs
        Erzeugt Skripte fuer SQL-Server-Agent-Jobs aus msdb. Exportiert werden nur
        Jobs, deren Name auf ein aktives Muster in ddl.ExportJob passt (LIKE).
        Ohne job_id/schedule_uid -> deterministisch und auf anderen Instanzen ausfuehrbar.
        Ergebnis -> Temp-Tabelle #Script.

    Ablage:
        <Ordner>/<Umgebung>/Jobs/<job>.sql        alle T-SQL-Steps laufen in genau einer
                                                  exportierten Datenbank
        _Server/<Umgebung>/<Server>/Jobs/<job>.sql sonst (CmdExec, mehrere/andere DBs)
*/
USE [$(AdminDb)];
GO

CREATE OR ALTER PROCEDURE ddl.usp_Script_Jobs
    @RunId       int,
    @Environment varchar(20),
    @ServerPath  nvarchar(400)   -- _Server/<Umgebung>/<Server>/
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @nl nchar(2) = NCHAR(13) + NCHAR(10);

    CREATE TABLE #Job (JobId uniqueidentifier NOT NULL PRIMARY KEY, JobName sysname NOT NULL, RelativePath nvarchar(400) NOT NULL);
    INSERT INTO #Job (JobId, JobName, RelativePath)
    SELECT j.job_id, j.name,
           ISNULL(t.BasePath, @ServerPath) + N'Jobs/' + ddl.fn_FileName(j.name) + N'.sql'
    FROM msdb.dbo.sysjobs j
    OUTER APPLY (SELECT DbName = CASE WHEN COUNT(DISTINCT s.database_name) = 1 THEN MIN(s.database_name) END
                 FROM msdb.dbo.sysjobsteps s
                 WHERE s.job_id = j.job_id AND s.subsystem = N'TSQL' AND s.database_name IS NOT NULL) d
    LEFT JOIN ddl.fn_ExportTarget(@Environment) t ON t.DatabaseName = d.DbName
    WHERE EXISTS (SELECT 1 FROM ddl.ExportJob x WHERE x.IsActive = 1 AND j.name LIKE x.JobNamePattern);

    CREATE TABLE #Stmt (JobId uniqueidentifier NOT NULL, Section int NOT NULL, SortKey nvarchar(400) NOT NULL, Stmt nvarchar(max) NOT NULL);

    -- Kategorie + vorhandenen Job entfernen
    INSERT INTO #Stmt (JobId, Section, SortKey, Stmt)
    SELECT j.job_id, 1, N'',
           N'IF NOT EXISTS (SELECT 1 FROM msdb.dbo.syscategories WHERE name = ' + ddl.fn_Literal(c.name) + N' AND category_class = 1)' + @nl
           + N'    EXEC msdb.dbo.sp_add_category @class = N''JOB'', @type = N''LOCAL'', @name = ' + ddl.fn_Literal(c.name) + N';' + @nl
           + N'IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = ' + ddl.fn_Literal(j.name) + N')' + @nl
           + N'    EXEC msdb.dbo.sp_delete_job @job_name = ' + ddl.fn_Literal(j.name) + N', @delete_unused_schedule = 1;'
    FROM #Job x
    JOIN msdb.dbo.sysjobs j       ON j.job_id = x.JobId
    JOIN msdb.dbo.syscategories c ON c.category_id = j.category_id;

    -- Job, Steps, Schedules, Server in einem Batch (@jobId)
    INSERT INTO #Stmt (JobId, Section, SortKey, Stmt)
    SELECT j.job_id, 2, N'',
           N'DECLARE @jobId binary(16);' + @nl
           + N'EXEC msdb.dbo.sp_add_job' + @nl
           + N'    @job_name = ' + ddl.fn_Literal(j.name) + N',' + @nl
           + N'    @enabled = ' + CAST(j.enabled AS nvarchar(1)) + N',' + @nl
           + N'    @description = ' + ddl.fn_LiteralSafe(ISNULL(j.description, N'')) + N',' + @nl
           + N'    @category_name = ' + ddl.fn_Literal(c.name) + N',' + @nl
           + N'    @owner_login_name = ' + ddl.fn_Literal(ISNULL(SUSER_SNAME(j.owner_sid), N'sa')) + N',' + @nl
           + N'    @notify_level_eventlog = ' + CAST(j.notify_level_eventlog AS nvarchar(5)) + N',' + @nl
           + N'    @notify_level_email = '    + CAST(j.notify_level_email AS nvarchar(5)) + N',' + @nl
           + ISNULL(N'    @notify_email_operator_name = ' + ddl.fn_Literal(op.name) + N',' + @nl, N'')
           + N'    @delete_level = ' + CAST(j.delete_level AS nvarchar(5)) + N',' + @nl
           + N'    @job_id = @jobId OUTPUT;' + @nl
           + ISNULL(st.Steps, N'')
           + N'EXEC msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = ' + CAST(j.start_step_id AS nvarchar(10)) + N';' + @nl
           + ISNULL(sc.Schedules, N'')
           + N'EXEC msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N''(local)'';'
    FROM #Job x
    JOIN msdb.dbo.sysjobs j           ON j.job_id = x.JobId
    JOIN msdb.dbo.syscategories c     ON c.category_id = j.category_id
    LEFT JOIN msdb.dbo.sysoperators op ON op.id = j.notify_email_operator_id AND j.notify_email_operator_id <> 0
    OUTER APPLY
    (
        SELECT Steps = STRING_AGG(CAST(
                   N'EXEC msdb.dbo.sp_add_jobstep @job_id = @jobId,' + @nl
                   + N'    @step_id = ' + CAST(s.step_id AS nvarchar(10)) + N',' + @nl
                   + N'    @step_name = ' + ddl.fn_Literal(s.step_name) + N',' + @nl
                   + N'    @subsystem = ' + ddl.fn_Literal(s.subsystem) + N',' + @nl
                   + ISNULL(N'    @database_name = ' + ddl.fn_Literal(s.database_name) + N',' + @nl, N'')
                   + ISNULL(N'    @proxy_name = ' + ddl.fn_Literal(px.name) + N',' + @nl, N'')
                   + N'    @command = ' + ddl.fn_LiteralSafe(ISNULL(s.command, N'')) + N',' + @nl
                   + N'    @on_success_action = ' + CAST(s.on_success_action AS nvarchar(5)) + N', @on_success_step_id = ' + CAST(s.on_success_step_id AS nvarchar(10)) + N',' + @nl
                   + N'    @on_fail_action = '    + CAST(s.on_fail_action AS nvarchar(5))    + N', @on_fail_step_id = '    + CAST(s.on_fail_step_id AS nvarchar(10)) + N',' + @nl
                   + N'    @retry_attempts = ' + CAST(s.retry_attempts AS nvarchar(10)) + N', @retry_interval = ' + CAST(s.retry_interval AS nvarchar(10)) + N',' + @nl
                   + ISNULL(N'    @output_file_name = ' + ddl.fn_Literal(NULLIF(s.output_file_name, N'')) + N',' + @nl, N'')
                   + N'    @flags = ' + CAST(s.flags AS nvarchar(10)) + N';' + @nl
               AS nvarchar(max)), N'') WITHIN GROUP (ORDER BY s.step_id)
        FROM msdb.dbo.sysjobsteps s
        LEFT JOIN msdb.dbo.sysproxies px ON px.proxy_id = s.proxy_id
        WHERE s.job_id = j.job_id
    ) st
    OUTER APPLY
    (
        SELECT Schedules = STRING_AGG(CAST(
                   N'EXEC msdb.dbo.sp_add_jobschedule @job_id = @jobId,' + @nl
                   + N'    @name = ' + ddl.fn_Literal(sch.name) + N',' + @nl
                   + N'    @enabled = ' + CAST(sch.enabled AS nvarchar(1)) + N',' + @nl
                   + N'    @freq_type = ' + CAST(sch.freq_type AS nvarchar(10)) + N', @freq_interval = ' + CAST(sch.freq_interval AS nvarchar(10)) + N',' + @nl
                   + N'    @freq_subday_type = ' + CAST(sch.freq_subday_type AS nvarchar(10)) + N', @freq_subday_interval = ' + CAST(sch.freq_subday_interval AS nvarchar(10)) + N',' + @nl
                   + N'    @freq_relative_interval = ' + CAST(sch.freq_relative_interval AS nvarchar(10)) + N', @freq_recurrence_factor = ' + CAST(sch.freq_recurrence_factor AS nvarchar(10)) + N',' + @nl
                   + N'    @active_start_date = ' + CAST(sch.active_start_date AS nvarchar(10)) + N', @active_end_date = ' + CAST(sch.active_end_date AS nvarchar(10)) + N',' + @nl
                   + N'    @active_start_time = ' + CAST(sch.active_start_time AS nvarchar(10)) + N', @active_end_time = ' + CAST(sch.active_end_time AS nvarchar(10)) + N';' + @nl
               AS nvarchar(max)), N'') WITHIN GROUP (ORDER BY sch.name, sch.schedule_id)
        FROM msdb.dbo.sysjobschedules js
        JOIN msdb.dbo.sysschedules sch ON sch.schedule_id = js.schedule_id
        WHERE js.job_id = j.job_id
    ) sc;

    INSERT INTO #Script (RelativePath, Scope, ObjectType, SchemaName, ObjectName, Content)
    SELECT x.RelativePath, N'(Server)', 'Job', NULL, x.JobName,
           ddl.fn_Header(N'SQL Server Agent Job', QUOTENAME(x.JobName))
           + N'USE [msdb]' + @nl + N'GO' + @nl + @nl
           + s.Body
    FROM #Job x
    CROSS APPLY (SELECT Body = STRING_AGG(CAST(t.Stmt AS nvarchar(max)) + @nl + N'GO' + @nl, @nl)
                               WITHIN GROUP (ORDER BY t.Section, t.SortKey)
                 FROM #Stmt t WHERE t.JobId = x.JobId) s
    WHERE s.Body IS NOT NULL;
END;
GO
