# Aktueller Kontext

Stand: 2026-10-04

## Gerade in Arbeit

* DDL-Export-Package fertig und getestet (Docker, SQL Server 2022). Liegt im PR
  [alex-le-de/DDL_EXPORT_MS_SQL#1](https://github.com/alex-le-de/DDL_EXPORT_MS_SQL/pull/1).
* Repo-Grundstruktur angelegt: Memory Bank, `projects/` (Vorlage, DDL-Export, Monitoring),
  DB-Steckbriefe `export/<DB>/README.md`.

## Nächste Schritte

1. PR #1 prüfen und mergen.
2. Installation auf `EVHNT56` (Umgebung PROD?), erster Export, Commit. Siehe
   [docs/BETRIEB.md](../docs/BETRIEB.md).
3. Konfigurationstabellen je DB in `config/Seed_Config.sql` eintragen.
4. Testserver-Namen klären, dort mit `Environment="TEST"` installieren.
5. Projekt Monitoring: Anforderungen klären (siehe offene Fragen dort) und Plan erstellen.

## Offene Fragen

* Ist `EVHNT56` PROD oder TEST? Welche Server gehören zur jeweils anderen Umgebung?
* Welche Tabellen sind Konfigurationstabellen (je DB)?
* Monitoring: Zielhost, Docker verfügbar, wer nutzt es, was genau soll überwacht werden?
