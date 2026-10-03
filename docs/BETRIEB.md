# Betrieb: DDL-Export

## 1. Installation

Voraussetzung ist ein Klon des Repos auf dem SQL-Server-Host, z. B. unter
`L:\Datenverarbeitung\DDL_EXPORT_MS_SQL`. Der Export schreibt in dessen Ordner `export\`.

```bat
cd /d L:\Datenverarbeitung\DDL_EXPORT_MS_SQL\src\install
sqlcmd -S EVHNT56 -E -b -i Install.sql ^
       -v AdminDb="DDL_Export_Admin" ExportRoot="L:\Datenverarbeitung\DDL_EXPORT_MS_SQL\export"
```

* `Install.sql` lässt sich beliebig oft ausführen, auch für Updates. Tabellen werden nur
  angelegt, wenn sie fehlen. Prozeduren und Funktionen werden mit `CREATE OR ALTER`
  aktualisiert. Bestehende Einstellungen wie `ExportRoot` werden **nicht** überschrieben.
* sqlcmd muss im Ordner `src\install` gestartet werden, weil die `:r`-Includes relativ sind.
* In SSMS: SQLCMD-Modus aktivieren und die `:setvar`-Zeilen am Anfang von `Install.sql`
  einkommentieren.

## 2. Konfiguration

Alle Einstellungen liegen in der Admin-DB `DDL_Export_Admin`, Schema `ddl`.
`config/Seed_Config.sql` ist die versionierte Vorlage dafür.

| Tabelle | Zweck |
|---|---|
| `ddl.ExportDatabase` | Diese Datenbanken werden exportiert, und **nur** diese (`IsActive = 1`). `FolderName` setzt optional einen anderen Ordnernamen. |
| `ddl.ExportConfigTable` | Diese Tabellen werden **mit Inhalt** exportiert, als `DELETE` + `INSERT`, sortiert nach PK. Optional: `OrderByColumns`, `ExcludeColumns`, `MaskColumns` (jeweils kommagetrennt). |
| `ddl.ExportJob` | LIKE-Muster für Agent-Jobs. Ohne Eintrag werden keine Jobs exportiert. |
| `ddl.ExportSetting` | `ExportRoot` (Zielpfad), `ExportMode` (`Export`, `DriftCheck`, `Off`), `ConfigDataMaxRows` (Standard 10000) |

Beispiele:

```sql
USE DDL_Export_Admin;

INSERT ddl.ExportConfigTable (DatabaseName, SchemaName, TableName, ExcludeColumns, MaskColumns, Description)
VALUES (N'Statistik', N'dbo', N'Konfiguration', N'GeaendertAm', N'Passwort', N'Steuerparameter');

UPDATE ddl.ExportDatabase SET IsActive = 0 WHERE DatabaseName = N'Test';   -- Dateien werden beim nächsten Lauf entfernt
```

**Maskierung:** Bei Textspalten wird der Wert durch `N'***'` ersetzt, bei allen anderen
Typen durch `NULL`. Passwörter, Tokens und personenbezogene Daten gehören maskiert oder
ausgeschlossen, denn das Repo ist keine sichere Ablage für Geheimnisse.

## 3. Agent-Job

```bat
cd /d L:\Datenverarbeitung\DDL_EXPORT_MS_SQL\src\job
sqlcmd -S EVHNT56 -E -b -I -i Create_Job_DDL_Export.sql -v AdminDb="DDL_Export_Admin" ^
       WriterScript="L:\Datenverarbeitung\DDL_EXPORT_MS_SQL\src\writer\Write-DdlExport.ps1" JobOwner="sa"
```

| Step | Typ | Aufgabe |
|---|---|---|
| 1 | T-SQL | `EXEC ddl.usp_Export_Run`: erzeugt den Snapshot in `ddl.ExportScript`. Bei Fehlern schlägt der Step fehl, Step 2 läuft dann nicht. |
| 2 | CmdExec | `Write-DdlExport.ps1`: schreibt die Dateien bzw. führt den DriftCheck aus. Exit 0 = OK, 1 = Fehler, 2 = Drift. |

Der Zeitplan `Taeglich_0200` wird **deaktiviert** angelegt. Nach dem ersten erfolgreichen
manuellen Lauf aktivierst du ihn so:

```sql
EXEC msdb.dbo.sp_update_schedule @name = N'Taeglich_0200', @enabled = 1;
```

## 4. Berechtigungen (Mindestrechte)

Step 1 läuft im Kontext des Job-Owners. Ist das `sa` bzw. sysadmin, ist nichts weiter zu
tun. Bei einem nicht-privilegierten Owner braucht er:

```sql
-- je Fach-DB
USE [Statistik];
CREATE USER [DOMAIN\svc_ddlexport] FOR LOGIN [DOMAIN\svc_ddlexport];
GRANT VIEW DEFINITION TO [DOMAIN\svc_ddlexport];
GRANT SELECT ON dbo.Konfiguration TO [DOMAIN\svc_ddlexport];   -- je Konfig-Tabelle

-- msdb (nur für den Job-Export)
USE msdb;
CREATE USER [DOMAIN\svc_ddlexport] FOR LOGIN [DOMAIN\svc_ddlexport];
ALTER ROLE SQLAgentReaderRole ADD MEMBER [DOMAIN\svc_ddlexport];
-- SQLAgentReaderRole zeigt nur eigene Jobs vollständig; für alle Jobs: SELECT auf dbo.sysjobs, sysjobsteps, sysjobschedules, sysschedules, syscategories

-- Admin-DB
USE DDL_Export_Admin;
CREATE USER [DOMAIN\svc_ddlexport] FOR LOGIN [DOMAIN\svc_ddlexport];
ALTER ROLE db_owner ADD MEMBER [DOMAIN\svc_ddlexport];
```

Step 2 läuft unter dem **SQL-Agent-Dienstkonto** oder einem CmdExec-Proxy. Es braucht:

* in `DDL_Export_Admin` Lesezugriff auf `ddl.ExportSetting`, `ddl.ExportRun` und
  `ddl.ExportScript` sowie `EXECUTE` auf `ddl.usp_Log`
* im Dateisystem Schreib- und Löschrecht auf `<ExportRoot>`

## 5. Modi (`ddl.ExportSetting.ExportMode`)

| Modus | Step 1 | Step 2 | Wofür |
|---|---|---|---|
| `Export` | Snapshot erzeugen | Dateien schreiben und löschen | Startphase: DB → Git |
| `DriftCheck` | Snapshot erzeugen | **nichts schreiben**, Abweichungen melden (Exit 2 → Job schlägt fehl) | Git ist führend |
| `Off` | nichts | nichts | pausiert |

### Umstieg auf „Git ist die Wahrheit“

1. Letzten Export prüfen und committen. Danach ist `git status` sauber.
2. `UPDATE ddl.ExportSetting SET SettingValue = N'DriftCheck' WHERE SettingKey = 'ExportMode';`
3. Ab jetzt werden DDL-Änderungen im Repo gepflegt (Review, Commit) und dann auf die DB
   ausgerollt. Der nächtliche Job meldet jede Abweichung zwischen DB und Repo:

   | Meldung | Bedeutung |
   |---|---|
   | `GEAENDERT` | Inhalt in DB und Repo unterschiedlich |
   | `FEHLT` | Objekt existiert in der DB, aber nicht im Repo (ungeplante Änderung an der DB?) |
   | `NUR REPO` | Datei im Repo, Objekt fehlt in der DB (noch nicht ausgerollt?) |

   Die Meldungen stehen in der Job-Historie und in `ddl.ExportLog` (Source `Writer`).

Bei der manuellen Pflege das Dateiformat beibehalten, also den Kopf, `GO` nach jeder
Anweisung und die Reihenfolge Tabelle → Indizes → FKs → Extended Properties. Sonst meldet
DriftCheck rein formale Abweichungen. Der einfachste Weg ist: Änderung auf einer Test-DB
ausrollen, im Modus `Export` exportieren und das Ergebnis übernehmen.

## 6. Protokoll und Fehlersuche

```sql
SELECT TOP (10) * FROM ddl.ExportRun ORDER BY RunId DESC;
SELECT * FROM ddl.ExportLog WHERE RunId = (SELECT MAX(RunId) FROM ddl.ExportRun) ORDER BY LogId;
SELECT RelativePath, ObjectType, LEN(Content) AS Laenge FROM ddl.ExportScript ORDER BY RelativePath;
```

| Situation | Verhalten |
|---|---|
| DB in `ExportDatabase`, aber nicht vorhanden oder offline | WARN. Die bisherigen Dateien dieser DB bleiben unverändert. |
| Fehler beim Export einer DB | ERROR. Die Dateien dieser DB bleiben unverändert, Step 1 schlägt fehl, der Writer läuft nicht. |
| DB deaktiviert oder gelöscht (`ExportDatabase`) | Ihre Dateien werden beim nächsten Lauf entfernt. |
| Konfig-Tabelle nicht gefunden | WARN, die Tabelle wird übersprungen. |
| Konfig-Tabelle ohne PK | WARN, sortiert wird über alle Spalten. Besser `OrderByColumns` setzen. |
| Konfig-Tabelle größer als `ConfigDataMaxRows` | WARN. Die Datei enthält nur den Hinweis, keine Daten. |
| Snapshot leer | Der Writer löscht nichts (Schutz). |

## 7. Grenzen

* Nicht exportiert werden Logins, User, Rollen, Berechtigungen, Partitionierung, Volltext,
  CLR-Assemblies, XML- und Spatial-Indizes (nur als Hinweis-Kommentar), Statistiken und
  Filegroups/Compression-Optionen.
* Verschlüsselte Module (`WITH ENCRYPTION`) erscheinen nur als Kommentar.
* System-benannte Constraints (z. B. `DF__Kunde__Anlag__3B75D760`) werden ohne Namen
  exportiert. So sind die Dateien zwischen Prod und Test vergleichbar.
* Die Dateien sind **je Objekt** ausführbar, aber nicht nach Abhängigkeiten sortiert. Beim
  Neuaufbau einer DB gilt die Reihenfolge Schemas → Types → Sequences → Historientabellen →
  Tabellen (FKs ggf. nachziehen) → Views → Functions → Procedures → Trigger → Synonyme →
  ConfigData. Ein Beispiel steht in `tests/run_tests.sh`.
* `Jobs/*.sql` enthalten das Agent-Token `$(ESCAPE_NONE(SRVR))`. Mit sqlcmd daher mit `-x`
  ausführen (keine Variablenersetzung) oder in SSMS ohne SQLCMD-Modus.
* Konfig-Daten: `sql_variant` wird als Text exportiert. `hierarchyid`, `geometry` und
  `geography` werden binär (`0x...`) exportiert.

## 8. Migration vom PowerShell/SMO-Altstand

1. Package installieren und konfigurieren (Abschnitte 1 bis 3). Die bisherigen
   `-ConfigTablesJson`-Einträge kommen nach `ddl.ExportConfigTable`.
2. Job `DDL_Export` manuell starten und das Ergebnis unter `export\` prüfen.
3. Alten Job deaktivieren:
   `EXEC msdb.dbo.sp_update_job @job_name = N'DDL_Export_Statistik', @enabled = 0;`
   Danach `Export-DDL-Statistik.ps1` archivieren. Den alten Exportordner
   `L:\Datenverarbeitung\DDL_Export` nicht mehr verwenden.
4. Den ersten Export committen und pushen. Ab jetzt gilt: kein Diff ohne DB-Änderung.
5. Wenn Git führend werden soll, auf `DriftCheck` umstellen (Abschnitt 5).

Unterschiede zum Altstand:

| Thema | Alt (PS1 + SMO) | Neu |
|---|---|---|
| Steuerung | Parameter im Job-Kommando | Tabellen in `DDL_Export_Admin` |
| Zeitstempel im Dateikopf | ja (jeder Lauf ändert jede Datei) | nein |
| Gelöschte Objekte | Datei bleibt liegen | Datei wird gelöscht |
| Konfig-Tabellen | `-ConfigTablesJson` (ungenutzt) | `ddl.ExportConfigTable`, inkl. Maskierung |
| Objektarten | Tabellen, Views, Trigger, Procs, Functions, Jobs | zusätzlich Schemas, Typen, Sequences, Synonyme, DB-Trigger, Agenten-Katalog |
| Jobs | alle | nur per `ddl.ExportJob` freigegebene |
| Abhängigkeit | SMO-Assemblies | keine (T-SQL + PowerShell-Bordmittel) |

## 9. Tests

`tests/run_tests.sh` startet einen SQL Server 2022 in Docker, legt die Testdatenbank
`tests/01_Create_TestDatabase.sql` an und prüft Folgendes:

* Idempotenz der Installation
* kein Diff bei unveränderter DB
* korrekte Diffs nach Änderungen und Löschungen
* DriftCheck
* Round-Trip: Export einspielen, erneut exportieren, Ergebnis identisch
* Entfernen deaktivierter DBs

```bash
PWSH=/pfad/zu/pwsh tests/run_tests.sh
```
