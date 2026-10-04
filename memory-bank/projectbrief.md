# Projektauftrag

## Zweck des Repos

Zentrale, versionierte Wissensbasis über die MS-SQL-Server-Landschaft der Datenverarbeitung.
Sie dient Menschen und KI-Agenten bei Analyse, Entwicklung und Betrieb.

## Ziele

1. **Struktur transparent machen:** Die DDL aller relevanten Datenbanken (Prod und Test)
   samt Konfigurationstabellen und Agent-Jobs liegt automatisch und deterministisch in Git
   → [projects/2026-ddl-export](../projects/2026-ddl-export/README.md).
2. **Git wird die Wahrheit:** Nach der Startphase werden DDL-Änderungen im Repo gepflegt.
   Der Export prüft dann nur noch auf Abweichungen (DriftCheck).
3. **Prozesse überwachen:** Die Excel-Auswertungen der Statistiken werden durch HTML-Seiten
   oder eine Monitoring-Instanz (Docker + Website) abgelöst, die den gesamten Prozess
   überwacht → [projects/2026-monitoring](../projects/2026-monitoring/README.md).
4. **Agentische Unterstützung:** Agenten finden über `export/<DB>/<Umgebung>/catalog.jsonl`,
   die Memory Bank und die Projektdokumente alles, was sie für Analysen und Änderungen
   brauchen.

## Nicht-Ziele (vorerst)

* Automatischer Git-Commit/Push vom Server. Das bleibt manuell.
* Automatisches Deployment von DDL aus Git in die Datenbanken.
