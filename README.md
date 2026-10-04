# DDL_EXPORT_MS_SQL

Versionierung der DDL-Struktur von MS-SQL-Server-Datenbanken in Git. Gedacht als
Wissensbasis für Menschen und KI-Agenten.

* **Export in T-SQL:** Systemkataloge und `sys.sql_modules` liefern die Struktur.
  SMO, dbatools und `xp_cmdshell` werden nicht gebraucht.
* **Gesteuert über eine Admin-DB:** `DDL_Export_Admin` legt fest, welche Datenbanken,
  Konfigurationstabellen (mit Daten) und Agent-Jobs exportiert werden und wohin.
* **Je DB und Umgebung ein Ordner:** `export/<DB>/<Umgebung>/`, z. B. `export/BAG/PROD` und
  `export/BAG/TEST`. Mehrere Server (Prod und Test) exportieren in dasselbe Repo, und jeder
  Server pflegt nur seine eigenen Ordner.
* **Deterministisch:** Die Dateien enthalten keinen Zeitstempel und sind fest sortiert.
  Ohne DB-Änderung entsteht also kein Git-Diff. Gelöschte Objekte verschwinden auch als Datei.
* **Für Agenten:** Pro Datenbank gibt es eine `catalog.jsonl`. Sie enthält Tabellen,
  Spalten, PK/FK, Parameter und Beschreibungen.
* **Git bleibt manuell:** Commit und Push macht ihr selbst. Später ist Git führend,
  dann meldet der Modus `DriftCheck` nur noch Abweichungen.

```
SQL Server (je Server)                                Git-Arbeitsverzeichnis (lokal auf dem Server)
┌───────────────────────────────┐   Agent-Job        ┌───────────────────────────────────┐
│ DDL_Export_Admin              │   "DDL_Export"     │ export/<DB>/PROD/Tables/...       │
│  ddl.ExportDatabase  (welche) │ ─ Step 1 T-SQL ──▶ │ export/<DB>/PROD/ConfigData/...   │
│  ddl.ExportConfigTable (Daten)│   Snapshot         │ export/<DB>/PROD/Jobs/...         │
│  ddl.ExportJob       (Jobs)   │ ─ Step 2 Writer ─▶ │ export/_Server/PROD/<Server>/...  │
│  ddl.ExportSetting   (Pfad,   │   (PowerShell,     └───────────────────────────────────┘
│   Umgebung, Modus)            │    ohne SMO)                 │ git pull / commit / push (manuell)
└───────────────────────────────┘                              ▼
        ▲ liest per [DB].sys.sp_executesql                  GitHub  ◀── Testserver: export/<DB>/TEST/...
  BAG, Belvis_sd_sst, Memi, Messwert, PDB2BELVIS, Statistik, Test
```

## Schnellstart

Alle Schritte laufen auf dem SQL-Server-Host (z. B. `EVHNT56`). Dort liegt ein Klon dieses
Repos, z. B. unter `L:\Datenverarbeitung\DDL_EXPORT_MS_SQL`.

```bat
cd /d L:\Datenverarbeitung\DDL_EXPORT_MS_SQL\src\install
sqlcmd -S EVHNT56 -E -b -i Install.sql -v AdminDb="DDL_Export_Admin" ExportRoot="L:\Datenverarbeitung\DDL_EXPORT_MS_SQL\export" Environment="PROD"

cd ..\..\config
REM vorher Seed_Config.sql anpassen (Konfig-Tabellen eintragen)
sqlcmd -S EVHNT56 -E -b -I -i Seed_Config.sql -v AdminDb="DDL_Export_Admin"

cd ..\src\job
sqlcmd -S EVHNT56 -E -b -I -i Create_Job_DDL_Export.sql -v AdminDb="DDL_Export_Admin" WriterScript="L:\Datenverarbeitung\DDL_EXPORT_MS_SQL\src\writer\Write-DdlExport.ps1" JobOwner="sa"
```

Auf einem Testserver genauso vorgehen, nur mit `Environment="TEST"`.

Danach den Job `DDL_Export` einmal manuell starten, das Ergebnis unter `export\` prüfen und
committen. Anschließend den Zeitplan aktivieren. Die Details stehen in
[docs/BETRIEB.md](docs/BETRIEB.md).

## Konfiguration (Kurzfassung)

```sql
-- weitere Datenbank exportieren
INSERT ddl.ExportDatabase (DatabaseName) VALUES (N'NeueDB');

-- Inhalte einer Konfigurationstabelle mit exportieren (eine Zeile genügt, kein Code)
INSERT ddl.ExportConfigTable (DatabaseName, SchemaName, TableName, MaskColumns)
VALUES (N'Statistik', N'dbo', N'Konfiguration', N'Passwort');

-- Agent-Jobs exportieren (LIKE-Muster)
INSERT ddl.ExportJob (JobNamePattern) VALUES (N'Statistik%');

-- Exportpfad / Modus
UPDATE ddl.ExportSetting SET SettingValue = N'D:\Repos\DDL_EXPORT_MS_SQL\export' WHERE SettingKey = 'ExportRoot';
UPDATE ddl.ExportSetting SET SettingValue = N'DriftCheck'                        WHERE SettingKey = 'ExportMode';
```

## Prod gegen Test vergleichen

```bash
git diff --no-index export/BAG/PROD export/BAG/TEST     # oder Ordnervergleich in VS Code / WinMerge
```

Die Pfade unterhalb der Umgebung sind identisch. `database.json` enthält Server, Umgebung,
Kompatibilitätslevel und Collation.

## Repo-Struktur

| Pfad | Inhalt |
|---|---|
| `src/install/` | `Install.sql` plus idempotente Teilskripte für Admin-DB, Tabellen, Funktionen und Prozeduren |
| `src/writer/Write-DdlExport.ps1` | Datei-Writer und DriftCheck (Step 2 des Jobs) |
| `src/job/Create_Job_DDL_Export.sql` | Agent-Job `DDL_Export` |
| `config/Seed_Config.sql` | Datenbanken, Konfig-Tabellen, Job-Muster |
| `export/` | Ergebnis des Exports, wird vom Writer gepflegt |
| `tests/` | Testdatenbank und Akzeptanztests (Docker und SQL Server 2022) |
| `docs/` | Betriebsdoku des Export-Packages (Installation, Berechtigungen, Migration) |
| `projects/` | ein Ordner je Vorhaben mit Steckbrief, `docs/` und `sql/` (z. B. DDL-Export, Monitoring) |
| `memory-bank/` | dauerhafter Kontext für Agenten: Auftrag, Grund-Setting, Architektur, Entscheidungen, Stand |
| `export/<DB>/README.md` | fachlicher Steckbrief je Datenbank (manuell gepflegt) |
| `CLAUDE.md` | Hinweise für KI-Agenten |

## Voraussetzungen

* SQL Server 2017 oder neuer (`STRING_AGG`, `TRIM`, `CREATE OR ALTER`), getestet mit SQL Server 2022
* SQL Server Agent
* Windows PowerShell 5.1 oder PowerShell 7 auf dem SQL-Server-Host
