# Monitoring der Datenverarbeitung

| | |
|---|---|
| **Status** | Idee / Anforderungen sammeln |
| **Ziel** | Excel-Auswertungen der Statistiken ablösen und den **gesamten Prozess** (Schnittstellen, Jobs, Datenaktualität, Auswertungen) an einer Stelle überwachen |
| **Verantwortlich** | Alexander Jung |
| **Betroffene DBs / Server** | v. a. `Statistik`, Schnittstellen-DBs, `msdb` (Job-Historie), `DDL_Export_Admin` |

## Ausgangslage

* Die SQL-Server (Standard Edition) arbeiten als Schnittstellen- und Auswertungsserver.
* Statistiken werden über angebundene **Excel-Dateien** ausgewertet: manuell, verteilt,
  ohne Gesamtbild und ohne Alarmierung.

## Was überwacht werden soll (Entwurf)

| Bereich | Beispiele | Quelle |
|---|---|---|
| Agent-Jobs | Status, Laufzeit, Fehler, Ausreißer | `msdb.dbo.sysjobhistory` |
| Schnittstellen | letzte Lieferung, Zeilenzahlen, Verzug, Fehlersätze | Schnittstellen-DBs (Log-Tabellen, offen) |
| Datenaktualität | jüngster Zeitstempel je Kerntabelle | Fach-DBs |
| Statistiken | heutige Excel-Kennzahlen | `Statistik` |
| DDL-Export | Läufe, Warnungen, Drift | `DDL_Export_Admin.ddl.ExportRun/ExportLog` |
| Server | DB-Größen, Backups, freier Platz | `sys.*`, `msdb.dbo.backupset` |

## Lösungsoptionen

| Option | Beschreibung | Aufwand | Bewertung |
|---|---|---|---|
| A: statische HTML-Seiten | Agent-Job erzeugt HTML (T-SQL/PowerShell) auf einer Freigabe oder im IIS | gering | schneller Ersatz für Excel, aber keine Interaktion und kein Alarm |
| **B: Docker + Grafana** | Grafana-Container mit eingebauter SQL-Server-Datenquelle, Dashboards per SQL, Alarmierung (Mail/Teams) | mittel | **Empfehlung:** wenig Code, Dashboards versionierbar (JSON im Repo), nur lesender DB-Zugriff |
| C: eigene Web-App in Docker | z. B. Python/Node, eigene Oberfläche | hoch | maximal flexibel, aber Entwicklungs- und Pflegeaufwand |

Empfohlener Weg: **B**. Für jede Kennzahl gibt es eine Monitoring-View bzw. Prozedur
(Schema z. B. `mon` in einer Monitoring-DB). Grafana liest diese nur. Option A lässt sich als
Übergang aus denselben Views erzeugen.

## Offene Fragen

1. Zielhost für Docker: vorhandener Linux-Server, Windows mit Docker Desktop/WSL, oder VM?
2. Authentifizierung zu SQL Server: SQL-Login (einfach) oder Windows/Kerberos (aufwändiger
   aus Linux-Containern)?
3. Wer nutzt das Monitoring (Fachbereich, IT), und wer muss alarmiert werden?
4. Welche Excel-Auswertungen gibt es heute? Liste mit Kennzahlen und Quellabfragen.
5. Gibt es Log- bzw. Protokolltabellen in den Schnittstellen-DBs, oder müssen sie entstehen?
6. Aufbewahrung und Historie: Reicht der aktuelle Stand, oder werden Zeitreihen gebraucht?

## Nächster Schritt

Offene Fragen klären, dann `docs/PLAN.md` erstellen und freigeben lassen.
