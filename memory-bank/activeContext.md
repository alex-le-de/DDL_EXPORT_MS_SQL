# Aktueller Kontext

Stand: 2026-10-04 (nachts)

## Gerade in Arbeit

* DDL-Export-Package fertig und getestet (Docker, SQL Server 2022). Liegt im PR
  [alex-le-de/DDL_EXPORT_MS_SQL#1](https://github.com/alex-le-de/DDL_EXPORT_MS_SQL/pull/1).
* Repo-Grundstruktur angelegt: Memory Bank, `projects/` (Vorlage, DDL-Export, Monitoring),
  DB-Steckbriefe `export/<DB>/README.md`.

## Erreicht

* Erster erfolgreicher Export auf `EVHNT56` (Admin-DB `DDL_EXPORT`, ExportRoot
  `L:\Datenverarbeitung\DDL_EXPORT`, Modus `Export`). Step 2 des Jobs wurde per
  `sp_update_jobstep` korrigiert, weil die alte Version noch `$(...)`-Platzhalter enthielt.

## Nächste Schritte

1. PR #1 prüfen und mergen.
2. Export-Ergebnis unter `L:\Datenverarbeitung\DDL_EXPORT` prüfen. Git-Ablage klären: eigenes Repo oder Klon mit `ExportRoot …\export`. Danach committen. Zeitplan aktivieren. Siehe
   [docs/BETRIEB.md](../docs/BETRIEB.md).
3. Konfigurationstabellen je DB in `config/Seed_Config.sql` eintragen (Statistik: erledigt, SDTS_Abgleich_*; restliche DBs offen).
4. Testserver-Namen klären, dort mit `Environment="TEST"` installieren.
5. Projekt Monitoring: Anforderungen klären (siehe offene Fragen dort) und Plan erstellen.

## Offene Fragen

* Ist `EVHNT56` PROD oder TEST? Welche Server gehören zur jeweils anderen Umgebung?
* Welche Tabellen sind Konfigurationstabellen (je DB)?
* Monitoring: Zielhost, Docker verfügbar, wer nutzt es, was genau soll überwacht werden?
