/*
    Install.sql - Installation / Update des DDL-Export-Packages (idempotent)

    Ausfuehrung im SQLCMD-Modus aus dem Ordner src\install heraus, z. B.:

        cd <Repo>\src\install
        sqlcmd -S EVHNT56 -E -b -i Install.sql ^
               -v AdminDb="DDL_Export_Admin" ExportRoot="L:\Datenverarbeitung\DDL_EXPORT_MS_SQL\export"

    Alternativ in SSMS: Abfrage > SQLCMD-Modus aktivieren, Arbeitsordner beachten.

    Danach:
      1. config\Seed_Config.sql anpassen und ausfuehren (Datenbanken, Konfig-Tabellen, Jobs)
      2. src\job\Create_Job_DDL_Export.sql ausfuehren (Agent-Job)
*/
:on error exit
-- Variablen werden per sqlcmd -v uebergeben (ein :setvar im Skript wuerde -v ueberschreiben).
-- Fuer SSMS (SQLCMD-Modus) die beiden Zeilen einkommentieren und anpassen:
-- :setvar AdminDb    "DDL_Export_Admin"
-- :setvar ExportRoot "L:\Datenverarbeitung\DDL_EXPORT_MS_SQL\export"

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;   -- sqlcmd startet mit QUOTED_IDENTIFIER OFF
GO

:r 01_Database.sql
:r 02_Tables.sql
:r 03_Functions.sql
:r 04_Catalog_Load.sql
:r 05_Script_Objects.sql
:r 06_Script_ConfigData.sql
:r 07_Script_Catalog.sql
:r 08_Script_Jobs.sql
:r 09_Export_Run.sql
:r 10_Settings.sql

PRINT N'Installation von $(AdminDb) abgeschlossen.';
GO
