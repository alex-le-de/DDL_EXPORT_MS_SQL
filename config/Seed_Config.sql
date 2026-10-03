/*
    Seed_Config.sql - Konfiguration des DDL-Exports (beliebig oft ausfuehrbar)

    Nur hier eingetragene und aktive Datenbanken werden exportiert.
    Konfig-Tabellen: Inhalte werden zusaetzlich zur DDL als INSERT-Skripte exportiert.
    Jobs: nur Agent-Jobs, deren Name auf ein Muster passt (LIKE), werden exportiert.

    Ausfuehrung: sqlcmd -S EVHNT56 -E -b -I -i Seed_Config.sql -v AdminDb="DDL_Export_Admin"
*/
-- SSMS (SQLCMD-Modus): folgende Zeile einkommentieren
-- :setvar AdminDb "DDL_Export_Admin"
USE [$(AdminDb)];
GO

/* ---------------------------------------------------------------------
   1) Datenbanken
   --------------------------------------------------------------------- */
MERGE ddl.ExportDatabase AS t
USING (VALUES
    (N'BAG',           1, N''),
    (N'Belvis_sd_sst', 1, N''),
    (N'Memi',          1, N''),
    (N'Messwert',      1, N''),
    (N'PDB2BELVIS',    1, N''),
    (N'Statistik',     1, N''),
    (N'Test',          1, N'')
) AS s (DatabaseName, IsActive, Description)
ON t.DatabaseName = s.DatabaseName
WHEN NOT MATCHED THEN
    INSERT (DatabaseName, IsActive, Description) VALUES (s.DatabaseName, s.IsActive, NULLIF(s.Description, N''))
WHEN MATCHED AND t.IsActive <> s.IsActive THEN
    UPDATE SET IsActive = s.IsActive, ModifiedAt = SYSDATETIME(), ModifiedBy = SUSER_SNAME();
GO

/* ---------------------------------------------------------------------
   2) Konfigurationstabellen (Daten-Export)
      OrderByColumns / ExcludeColumns / MaskColumns: kommagetrennt, optional
   --------------------------------------------------------------------- */
MERGE ddl.ExportConfigTable AS t
USING (VALUES
    -- (DatabaseName,  SchemaName, TableName,        OrderByColumns, ExcludeColumns, MaskColumns, Description)
    -- (N'Statistik',  N'dbo',     N'Konfiguration', NULL,           NULL,           NULL,        N'Beispiel'),
    -- (N'BAG',        N'dbo',     N'Settings',      NULL,           N'GeaendertAm', N'Passwort', N'Beispiel'),
    (NULL, NULL, NULL, NULL, NULL, NULL, NULL)
) AS s (DatabaseName, SchemaName, TableName, OrderByColumns, ExcludeColumns, MaskColumns, Description)
ON t.DatabaseName = s.DatabaseName AND t.SchemaName = s.SchemaName AND t.TableName = s.TableName
WHEN NOT MATCHED AND s.DatabaseName IS NOT NULL THEN
    INSERT (DatabaseName, SchemaName, TableName, OrderByColumns, ExcludeColumns, MaskColumns, Description)
    VALUES (s.DatabaseName, s.SchemaName, s.TableName, s.OrderByColumns, s.ExcludeColumns, s.MaskColumns, s.Description)
WHEN MATCHED THEN
    UPDATE SET OrderByColumns = s.OrderByColumns, ExcludeColumns = s.ExcludeColumns, MaskColumns = s.MaskColumns,
               Description = s.Description, ModifiedAt = SYSDATETIME(), ModifiedBy = SUSER_SNAME();
GO

/* ---------------------------------------------------------------------
   3) SQL-Agent-Jobs (LIKE-Muster). Ohne Eintrag werden keine Jobs exportiert.
   --------------------------------------------------------------------- */
MERGE ddl.ExportJob AS t
USING (VALUES
    (N'DDL_Export%', N'Export-Job selbst')
    -- , (N'%', N'alle Jobs')
) AS s (JobNamePattern, Description)
ON t.JobNamePattern = s.JobNamePattern
WHEN NOT MATCHED THEN
    INSERT (JobNamePattern, Description) VALUES (s.JobNamePattern, s.Description);
GO

SELECT 'ExportDatabase' AS Tabelle, COUNT(*) AS Anzahl FROM ddl.ExportDatabase WHERE IsActive = 1
UNION ALL SELECT 'ExportConfigTable', COUNT(*) FROM ddl.ExportConfigTable WHERE IsActive = 1
UNION ALL SELECT 'ExportJob', COUNT(*) FROM ddl.ExportJob WHERE IsActive = 1;
GO
