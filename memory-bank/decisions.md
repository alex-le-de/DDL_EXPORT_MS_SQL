# Entscheidungslog

Format: Datum · Entscheidung · Begründung · Verweis

| Datum | Entscheidung | Begründung | Verweis |
|---|---|---|---|
| 2026-10-03 | DDL-Export in **T-SQL** statt PowerShell/SMO | keine SMO-Abhängigkeit, Logik in der DB, testbar | [Plan](../projects/2026-ddl-export/PLAN.md) |
| 2026-10-03 | Eigene **Admin-DB** `DDL_Export_Admin` für Konfiguration und Protokoll | unabhängig von den Fach-DBs | [Plan](../projects/2026-ddl-export/PLAN.md) |
| 2026-10-03 | Dateien schreibt ein **schlanker Writer** (PowerShell ohne SMO), **kein xp_cmdshell** | Sicherheit, T-SQL kann keine Dateien schreiben | [BETRIEB](../docs/BETRIEB.md) |
| 2026-10-03 | **Ein Repo**, Code (`src/`) und Ergebnis (`export/`) getrennt | ein Ort für Agenten | – |
| 2026-10-03 | Git-Commit/Push bleibt **manuell** | Kontrolle in der Startphase | – |
| 2026-10-03 | Nur **definierte** DBs und Jobs werden exportiert | keine Überraschungen, keine Fremd-DBs | `ddl.ExportDatabase`, `ddl.ExportJob` |
| 2026-10-03 | Später ist **Git die Wahrheit**, Modus `DriftCheck` | Änderungen per Review | [BETRIEB §5](../docs/BETRIEB.md) |
| 2026-10-04 | Ablage `export/<DB>/<Umgebung>/`, mehrere Server in einem Branch, Manifest je Server | Prod/Test direkt vergleichbar, keine Konflikte | [BETRIEB §2a](../docs/BETRIEB.md) |
| 2026-10-04 | Projektordner `projects/<jahr>-<name>/` und Memory Bank | Doku hat einen festen Platz | [systemPatterns](systemPatterns.md) |
| 2026-10-04 | Excel-Auswertungen werden durch **HTML bzw. Monitoring (Docker + Website)** abgelöst | Gesamtprozess überwachen | [Projekt Monitoring](../projects/2026-monitoring/README.md) |
