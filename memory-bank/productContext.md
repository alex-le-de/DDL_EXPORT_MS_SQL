# Produktkontext

## Ausgangslage

* Die SQL-Server dienen **überwiegend als Schnittstellenserver** (Datenaustausch zwischen
  Systemen, z. B. BelVis, PDB) **oder als Auswertungsserver** (Statistiken, Messwerte).
* Die Logik steckt in Stored Procedures, Views, Konfigurationstabellen und SQL-Agent-Jobs.
  Ein Teil der Steuerung liegt damit **in Daten**, nicht nur in DDL.
* Statistiken werden bisher über **angebundene Excel-Dateien** ausgewertet.
* Den DDL-Export erledigte bisher ein PowerShell/SMO-Skript (`Export-DDL-Statistik.ps1`,
  Job `DDL_Export_Statistik`). Es wurde durch das T-SQL-Package in diesem Repo abgelöst.

## Probleme, die gelöst werden sollen

| Problem | Lösung |
|---|---|
| Änderungen an DB-Objekten sind nicht nachvollziehbar | DDL-Export nach Git, kein Diff-Rauschen |
| Unterschiede zwischen Prod und Test sind unklar | Ablage `export/<DB>/PROD` und `export/<DB>/TEST`, Vergleich per Diff |
| Konfiguration in Tabellen ist unversioniert | Export der Konfigurationstabellen (`ddl.ExportConfigTable`) |
| Auswertungen per Excel: manuell, verteilt, kein Gesamtbild | Monitoring (HTML bzw. Docker + Website), Projekt `2026-monitoring` |
| Agenten fehlt der Kontext | Memory Bank, `catalog.jsonl`, Projektordner mit Doku |

## Arbeitsweise

* Erst planen und den Prompt bzw. Plan freigeben lassen, dann umsetzen.
* Ergebnisse gehören ins Repo: Code nach `src/`, Projektdoku nach `projects/<projekt>/docs/`.
* Dokumente knapp halten. Lieber eine gepflegte Datei als viele halbe.
* Sprache: Deutsch.
