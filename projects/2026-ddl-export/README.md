# DDL-Export MS SQL

| | |
|---|---|
| **Status** | umgesetzt (PR [#1](https://github.com/alex-le-de/DDL_EXPORT_MS_SQL/pull/1)), Einführung auf den Servern offen |
| **Ziel** | DDL, Konfigurationstabellen und Agent-Jobs aller definierten DBs (Prod und Test) deterministisch in Git. Später ist Git führend (DriftCheck). |
| **Verantwortlich** | Alexander Jung |
| **Betroffene DBs / Server** | BAG, Belvis_sd_sst, Memi, Messwert, PDB2BELVIS, Statistik, Test auf `EVHNT56` sowie Testserver (offen) |
| **Beginn** | 2026-10-03 |

## Dokumente

* [PLAN.md](PLAN.md): Plan und Architektur (freigegeben, Rev. 3)
* [docs/BETRIEB.md](../../docs/BETRIEB.md): Installation, Konfiguration, Betrieb, Migration
* Code: `src/`, `config/`, Tests: `tests/`

## Nächste Schritte

Siehe [memory-bank/activeContext.md](../../memory-bank/activeContext.md).
