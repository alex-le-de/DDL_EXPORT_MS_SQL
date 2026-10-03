/*
    10_Settings.sql
    Standardwerte fuer ddl.ExportSetting. Vorhandene Werte werden NICHT ueberschrieben.
    SQLCMD-Variablen: $(ExportRoot), $(Environment)
*/
USE [$(AdminDb)];
GO

MERGE ddl.ExportSetting AS t
USING (VALUES
    ('ExportRoot',        N'$(ExportRoot)',
     N'Lokaler Pfad auf dem SQL-Server-Host: Ordner export im Git-Arbeitsverzeichnis. Ablage: <ExportRoot>\<DB>\<Umgebung>\...'),
    ('Environment',       N'$(Environment)',
     N'Umgebung dieses Servers (z. B. PROD, TEST). Zweite Ordnerebene: <ExportRoot>\<DB>\<Umgebung>. Je DB ueberschreibbar (ExportDatabase.Environment).'),
    ('ServerLabel',       N'',
     N'Servername im Ordner _Server\<Umgebung>\<Server>. Leer = SERVERPROPERTY(''ServerName'').'),
    ('ExportMode',        N'Export',
     N'Export = Dateien schreiben (DB -> Git); DriftCheck = nur vergleichen und Abweichungen melden (Git ist fuehrend); Off = nichts tun.'),
    ('ConfigDataMaxRows', N'10000',
     N'Maximale Zeilenzahl je Konfigurationstabelle. Groessere Tabellen werden nicht als Daten exportiert (Warnung).')
) AS s (SettingKey, SettingValue, Description)
ON t.SettingKey = s.SettingKey
WHEN NOT MATCHED THEN
    INSERT (SettingKey, SettingValue, Description) VALUES (s.SettingKey, s.SettingValue, s.Description)
WHEN MATCHED THEN
    UPDATE SET Description = s.Description;
GO
