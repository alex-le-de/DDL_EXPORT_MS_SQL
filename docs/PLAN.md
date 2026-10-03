# Plan: T-SQL-basierter DDL-Export (Package `DDL_EXPORT_MS_SQL`)

Status: **Phase 1 – zur Freigabe (Rev. 2)**

## 0. Leitplanken (Rev. 2)

1. **Nur definierte Datenbanken:** Exportiert wird ausschließlich, was in
   `ddl.ExportDatabase` mit `IsActive = 1` eingetragen ist. Kein Wildcard,
   keine automatische Erkennung. Ein eingetragener DB-Name, den es auf der
   Instanz nicht gibt, ergibt eine Warnung im Log. Auch Agent-Jobs werden
   nur exportiert, wenn ihr Name in `ddl.ExportJob` (LIKE-Muster)
   eingetragen ist.
2. **Lokales Dateisystem des SQL Servers, Pfad konfigurierbar:** Der
   Writer läuft als Agent-Job-Step direkt auf dem SQL-Server-Host. Der
   Zielpfad steht in `ddl.ExportSetting` (`ExportRoot`, z. B.
   `L:\Datenverarbeitung\DDL_EXPORT_MS_SQL\export`) und lässt sich per
   Parameter `-ExportRoot` überschreiben.
3. **Später ist Git die Wahrheit:** Der Export ist ein Übergangs- und
   Bootstrap-Werkzeug. `ddl.ExportSetting.ExportMode` steuert das Verhalten:
   * `Export`: Dateien schreiben (Startphase, DB → Git)
   * `DriftCheck`: nichts schreiben; der Writer vergleicht DB-Stand und
     Git-Arbeitskopie und meldet Abweichungen (Log + Exit-Code ≠ 0, damit
     der Job fehlschlägt bzw. benachrichtigt). Ab hier wird DDL manuell in
     Git gepflegt und der Export ist nur noch die Kontrolle.
   * `Off`: Job läuft leer.

## 1. Architektur

```
┌──────────────────────── SQL Server EVHNT56 ─────────────────────────┐
│                                                                      │
│  DDL_Export_Admin (neue Admin-DB)                                    │
│   ├─ ddl.ExportSetting        Schlüssel/Wert (ExportRoot, ...)       │
│   ├─ ddl.ExportDatabase       welche DBs exportiert werden           │
│   ├─ ddl.ExportConfigTable    welche Konfig-Tabellen (Daten) je DB   │
│   ├─ ddl.ExportRun / ExportLog  Lauf-Protokoll                       │
│   ├─ ddl.ExportScript         Snapshot: 1 Zeile = 1 Datei            │
│   └─ ddl.usp_Export_Run       Orchestrator                           │
│        ├─ usp_Script_Schemas / Types / Sequences / Synonyms          │
│        ├─ usp_Script_Tables   (Spalten, PK, FK, UQ, CK, DF, Indizes) │
│        ├─ usp_Script_Modules  (Views, Procs, Functions, Trigger)     │
│        ├─ usp_Script_ConfigData (deterministische INSERTs)           │
│        ├─ usp_Script_Catalog  (catalog.jsonl für Agenten)            │
│        └─ usp_Script_Jobs     (SQL-Agent-Jobs aus msdb)              │
│                                                                      │
│  Fach-DBs: BAG, Belvis_sd_sst, Memi, Messwert, PDB2BELVIS, ...       │
│   ← gelesen per  EXEC [<DB>].sys.sp_executesql  (Kontextwechsel,     │
│     kein Objekt in den Fach-DBs nötig)                               │
└──────────────────────────────────────────────────────────────────────┘
          │  Agent-Job "DDL_Export"
          │   Step 1 (T-SQL):   EXEC DDL_Export_Admin.ddl.usp_Export_Run
          │   Step 2 (CmdExec): Write-DdlExport.ps1  (nur Datei-Writer,
          ▼                     kein SMO, kein xp_cmdshell)
   <Repo>\export\...   →  git add / commit / push  (manuell)
```

* Die gesamte DDL-Erzeugung findet in T-SQL statt (Systemkataloge `sys.*`,
  `sys.sql_modules`, `msdb.dbo.sysjobs*`).
* Der Writer liest `ddl.ExportScript`, schreibt geänderte Dateien
  (UTF-8 ohne BOM, CRLF), lässt unveränderte unangetastet und **löscht
  Dateien entfernter Objekte** in den verwalteten Ordnern.

## 2. Datenmodell Admin-DB (Entwurf)

| Tabelle | Schlüssel | Wichtige Spalten |
|---|---|---|
| `ddl.ExportSetting` | `SettingKey` | `SettingValue` (`ExportRoot`, `ExportMode`) |
| `ddl.ExportDatabase` | `DatabaseName` | `IsActive`, `FolderName`, `Description` |
| `ddl.ExportJob` | `JobNamePattern` | `IsActive`, `Description` (LIKE-Muster) |
| `ddl.ExportConfigTable` | `DatabaseName, SchemaName, TableName` | `IsActive`, `OrderBy` (optional), `ExcludeColumns`, `MaskColumns`, `Description` |
| `ddl.ExportRun` | `RunId` | `StartedAt`, `FinishedAt`, `Status`, `FileCount`, `ErrorCount` |
| `ddl.ExportLog` | `LogId` | `RunId`, `LogLevel`, `DatabaseName`, `Message` |
| `ddl.ExportScript` | `RelativePath` | `RunId`, `DatabaseName`, `ObjectType`, `SchemaName`, `ObjectName`, `Content`, `ContentHash` |

Neue Konfig-Tabelle aufnehmen = **ein INSERT** in `ddl.ExportConfigTable`.

## 3. Exportumfang und Dateistruktur

```
export/
  Databases/<DB>/
    Schemas/<schema>.sql
    Types/<schema>.<typ>.sql
    Sequences/<schema>.<seq>.sql
    Synonyms/<schema>.<syn>.sql
    Tables/<schema>.<tabelle>.sql        CREATE TABLE + Constraints + Indizes + Extended Properties
    Views/<schema>.<view>.sql
    StoredProcedures/<schema>.<proc>.sql
    Functions/<schema>.<func>.sql
    Triggers/<schema>.<tabelle>.<trigger>.sql | DB_<trigger>.sql
    ConfigData/<schema>.<tabelle>.sql    DELETE + INSERT, sortiert nach PK
    catalog.jsonl                        1 Zeile je Tabelle/View/Proc (Agenten)
  Jobs/<jobname>.sql
```

Determinismus: kein Zeitstempel im Inhalt, feste Sortierung (column_id,
Name), Collation wird weggelassen (wie bisher `NoCollation`), keine GUIDs
(job_id, schedule_uid) im Job-Skript.

## 4. Repo-Struktur

```
src/install/   Install.sql (SQLCMD-Modus, :r-Includes), idempotente Teilskripte
src/writer/    Write-DdlExport.ps1
src/job/       Agent-Job "DDL_Export" (2 Steps, täglich 02:00)
config/        Seed_Config.sql (7 DBs + Beispiel-Konfig-Tabellen)
docs/          PLAN.md, Betrieb, Berechtigungen, Migration
export/        Ergebnis (vom Writer erzeugt, manuell committed)
CLAUDE.md      Hinweise für Agenten
```

## 5. Berechtigungen (Mindestrechte)

* Job-Owner (Step 1, T-SQL): in jeder Fach-DB `VIEW DEFINITION` +
  `SELECT` auf die Konfig-Tabellen; in msdb `SQLAgentReaderRole`;
  `db_owner` bzw. `EXECUTE` in `DDL_Export_Admin`.
* Agent-Dienstkonto (Step 2, CmdExec): `SELECT` auf `ddl.ExportScript`,
  `ddl.ExportSetting`; NTFS-Schreibrecht auf das Repo-Verzeichnis.

## 6. Migration vom PowerShell/SMO-Altstand

1. `Install.sql` ausführen (legt Admin-DB, Objekte, Seed-Config an).
2. Konfig-Tabellen in `ddl.ExportConfigTable` eintragen.
3. Job `DDL_Export` anlegen, einmal manuell starten, Ergebnis prüfen.
4. Alten Job `DDL_Export_Statistik` deaktivieren, PS1 archivieren.
5. Ersten Export in Git committen. Ab dann gilt: kein Diff ohne DB-Änderung.
6. Umstieg auf Git als Wahrheit: `ExportMode = 'DriftCheck'` setzen.
   DDL-Änderungen erfolgen dann manuell im Repo, der Job meldet nur noch
   Abweichungen zwischen DB und Repo.

## 7. Bekannte Grenzen

* Ziel: SQL Server 2017+ (`STRING_AGG`, `CREATE OR ALTER`).
* Nicht exportiert: Logins/User/Berechtigungen, Partitionierung,
  Memory-Optimized-Details, Volltext, Temporal-Tabellen werden ohne
  `SYSTEM_VERSIONING`-Klausel geschrieben (Hinweis im Skript).
* Verschlüsselte Module: nur Platzhalter-Kommentar.
