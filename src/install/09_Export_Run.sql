/*
    09_Export_Run.sql
    ddl.usp_Export_Run  - Orchestrator (Step 1 des Agent-Jobs)

    Ablauf:
      1. ExportMode lesen (Export | DriftCheck | Off). Off -> Lauf 'Skipped'.
      2. Je aktiver DB aus ddl.ExportDatabase: Kataloge laden, Skripte erzeugen,
         Snapshot ddl.ExportScript fuer diese DB in einer Transaktion ersetzen.
         - DB fehlt/offline   -> WARN, bestehender Snapshot dieser DB bleibt erhalten.
         - Fehler beim Export -> ERROR, bestehender Snapshot dieser DB bleibt erhalten.
      3. Snapshot-Zeilen nicht (mehr) aktiver DBs entfernen -> Writer loescht deren Dateien.
      4. Agent-Jobs gemaess ddl.ExportJob.
      5. Status setzen; bei Fehlern RAISERROR, damit der Job-Step fehlschlaegt
         und der Writer (Step 2) nicht laeuft.

    Der Modus DriftCheck erzeugt den Snapshot genauso; nur der Writer verhaelt sich anders.
*/
USE [$(AdminDb)];
GO

CREATE OR ALTER PROCEDURE ddl.usp_Export_Run
    @RunId int = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;

    DECLARE @mode varchar(20) = ISNULL((SELECT CAST(SettingValue AS varchar(20)) FROM ddl.ExportSetting WHERE SettingKey = 'ExportMode'), 'Export');
    IF @mode NOT IN ('Export', 'DriftCheck', 'Off')
    BEGIN
        RAISERROR (N'Ungueltiger ExportMode ''%s'' (erlaubt: Export, DriftCheck, Off).', 16, 1, @mode);
        RETURN;
    END;

    INSERT INTO ddl.ExportRun (ExportMode) VALUES (@mode);
    SET @RunId = SCOPE_IDENTITY();

    DECLARE @msg nvarchar(4000) = N'Lauf ' + CAST(@RunId AS nvarchar(10)) + N' gestartet, Modus ' + CAST(@mode AS nvarchar(20)) + N'.';
    EXEC ddl.usp_Log @RunId, 'INFO', @msg;

    IF @mode = 'Off'
    BEGIN
        UPDATE ddl.ExportRun SET Status = 'Skipped', FinishedAt = SYSDATETIME(), FileCount = 0, WarningCount = 0, ErrorCount = 0
        WHERE RunId = @RunId;
        EXEC ddl.usp_Log @RunId, 'INFO', N'ExportMode = Off - nichts zu tun.';
        RETURN;
    END;

    CREATE TABLE #Script
    (
        RelativePath nvarchar(400) NOT NULL PRIMARY KEY,
        Scope        sysname       NOT NULL,
        ObjectType   varchar(30)   NOT NULL,
        SchemaName   sysname       NULL,
        ObjectName   nvarchar(256) NOT NULL,
        Content      nvarchar(max) NOT NULL
    );

    DECLARE @db sysname, @folder nvarchar(128), @cnt int, @err nvarchar(4000);

    DECLARE dbs CURSOR LOCAL FAST_FORWARD FOR
        SELECT DatabaseName, ISNULL(NULLIF(FolderName, N''), DatabaseName)
        FROM ddl.ExportDatabase
        WHERE IsActive = 1
        ORDER BY DatabaseName;
    OPEN dbs;
    FETCH NEXT FROM dbs INTO @db, @folder;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF DB_ID(@db) IS NULL
        BEGIN
            EXEC ddl.usp_Log @RunId, 'WARN', N'Datenbank existiert nicht auf dieser Instanz - bisheriger Export bleibt unveraendert.', @db;
        END
        ELSE IF CAST(DATABASEPROPERTYEX(@db, 'Status') AS nvarchar(60)) <> N'ONLINE'
        BEGIN
            EXEC ddl.usp_Log @RunId, 'WARN', N'Datenbank ist nicht ONLINE - bisheriger Export bleibt unveraendert.', @db;
        END
        ELSE
        BEGIN
            BEGIN TRY
                DELETE FROM #Script;
                EXEC ddl.usp_Catalog_Load     @RunId, @db;
                EXEC ddl.usp_Script_Objects   @RunId, @db, @folder;
                EXEC ddl.usp_Script_ConfigData @RunId, @db, @folder;
                EXEC ddl.usp_Script_Catalog   @RunId, @db, @folder;

                BEGIN TRANSACTION;
                    DELETE FROM ddl.ExportScript WHERE Scope = @db;
                    INSERT INTO ddl.ExportScript (RelativePath, Scope, ObjectType, SchemaName, ObjectName, Content, RunId)
                    SELECT RelativePath, Scope, ObjectType, SchemaName, ObjectName, Content, @RunId FROM #Script;
                    SET @cnt = @@ROWCOUNT;
                COMMIT TRANSACTION;

                SET @msg = CAST(@cnt AS nvarchar(10)) + N' Dateien erzeugt.';
                EXEC ddl.usp_Log @RunId, 'INFO', @msg, @db;
            END TRY
            BEGIN CATCH
                IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
                SET @err = N'Fehler: ' + ERROR_MESSAGE() + N' (Prozedur ' + ISNULL(ERROR_PROCEDURE(), N'-')
                         + N', Zeile ' + CAST(ERROR_LINE() AS nvarchar(10)) + N') - bisheriger Export bleibt unveraendert.';
                EXEC ddl.usp_Log @RunId, 'ERROR', @err, @db;
            END CATCH;
        END;
        FETCH NEXT FROM dbs INTO @db, @folder;
    END;
    CLOSE dbs;
    DEALLOCATE dbs;

    /* Nicht (mehr) aktive DBs aus dem Snapshot entfernen */
    DELETE s
    FROM ddl.ExportScript s
    WHERE s.Scope <> N'(Server)'
      AND NOT EXISTS (SELECT 1 FROM ddl.ExportDatabase d WHERE d.IsActive = 1 AND d.DatabaseName = s.Scope);
    IF @@ROWCOUNT > 0
        EXEC ddl.usp_Log @RunId, 'INFO', N'Snapshot von nicht mehr konfigurierten Datenbanken entfernt.';

    /* Agent-Jobs */
    BEGIN TRY
        DELETE FROM #Script;
        EXEC ddl.usp_Script_Jobs @RunId;
        BEGIN TRANSACTION;
            DELETE FROM ddl.ExportScript WHERE Scope = N'(Server)';
            INSERT INTO ddl.ExportScript (RelativePath, Scope, ObjectType, SchemaName, ObjectName, Content, RunId)
            SELECT RelativePath, Scope, ObjectType, SchemaName, ObjectName, Content, @RunId FROM #Script;
            SET @cnt = @@ROWCOUNT;
        COMMIT TRANSACTION;
        SET @msg = CAST(@cnt AS nvarchar(10)) + N' Agent-Jobs exportiert.';
        EXEC ddl.usp_Log @RunId, 'INFO', @msg, N'(Server)';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @err = N'Fehler beim Job-Export: ' + ERROR_MESSAGE() + N' - bisheriger Export bleibt unveraendert.';
        EXEC ddl.usp_Log @RunId, 'ERROR', @err, N'(Server)';
    END CATCH;

    /* Abschluss */
    DECLARE @warn int = (SELECT COUNT(*) FROM ddl.ExportLog WHERE RunId = @RunId AND Source = 'T-SQL' AND LogLevel = 'WARN');
    DECLARE @errs int = (SELECT COUNT(*) FROM ddl.ExportLog WHERE RunId = @RunId AND Source = 'T-SQL' AND LogLevel = 'ERROR');
    DECLARE @files int = (SELECT COUNT(*) FROM ddl.ExportScript);

    UPDATE ddl.ExportRun
    SET FinishedAt   = SYSDATETIME(),
        FileCount    = @files,
        WarningCount = @warn,
        ErrorCount   = @errs,
        Status       = CASE WHEN @errs > 0 THEN 'Failed' WHEN @warn > 0 THEN 'Warning' ELSE 'Succeeded' END
    WHERE RunId = @RunId;

    SET @msg = N'Lauf beendet: ' + CAST(@files AS nvarchar(10)) + N' Dateien im Snapshot, '
             + CAST(@warn AS nvarchar(10)) + N' Warnungen, ' + CAST(@errs AS nvarchar(10)) + N' Fehler.';
    EXEC ddl.usp_Log @RunId, 'INFO', @msg;

    IF @errs > 0
        RAISERROR (N'DDL-Export Lauf %d mit %d Fehler(n) beendet - siehe ddl.ExportLog.', 16, 1, @RunId, @errs);
END;
GO
