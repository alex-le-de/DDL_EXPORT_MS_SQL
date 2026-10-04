# Architektur und Muster

## DDL-Export

```
Server (je PROD/TEST)                                         Git-Repo (ein Branch)
DDL_Export_Admin ── Job DDL_Export ─ Step 1 T-SQL ─▶ ddl.ExportScript (Snapshot)
                                    ─ Step 2 Writer ─▶ export/<DB>/<Umgebung>/...
                                                       export/_Server/<Umgebung>/<Server>/...
```

* **Konfiguration in Tabellen statt Parametern:** `ddl.ExportDatabase`,
  `ddl.ExportConfigTable`, `ddl.ExportJob`, `ddl.ExportSetting`. Neues wird per INSERT
  aufgenommen, nicht per Code.
* **Fremde DBs nur lesen:** Zugriff per `EXEC [DB].sys.sp_executesql`. In den Fach-DBs werden
  keine Objekte angelegt.
* **Staging + Generierung:** Systemkataloge kommen nach `cat.*`, daraus erzeugt statisches
  T-SQL die Skripte.
* **Determinismus:** keine Zeitstempel, feste Sortierung, system-benannte Constraints ohne Namen.
* **Fail-safe:** Bei Fehlern oder Offline-DBs bleibt der letzte Snapshot erhalten. Ein leerer
  Snapshot löscht nichts. Der Writer räumt nur in den Ordnern auf, die im Manifest stehen.
* **Modi:** `Export` (DB → Git), `DriftCheck` (Git führend, nur melden), `Off`.

## Repo-Konventionen

| Ort | Inhalt | Wer schreibt |
|---|---|---|
| `export/<DB>/<Umgebung>/` | generierte DDL, Konfig-Daten, Katalog | nur der Writer (Modus Export) |
| `export/<DB>/README.md` | fachlicher Steckbrief der DB | Mensch/Agent, manuell |
| `src/`, `config/`, `tests/` | Code des Export-Packages | Entwicklung |
| `docs/` | Betriebsdoku des Export-Packages | Entwicklung |
| `projects/<jahr>-<name>/` | ein Ordner je Vorhaben mit `README.md`, `docs/`, `sql/` | Projekt |
| `memory-bank/` | dauerhafter Kontext für Agenten | alle, knapp |

## Muster für neue Vorhaben

1. Ordner aus `projects/_vorlage` kopieren und `README.md` (Steckbrief) ausfüllen.
2. Plan in `projects/<projekt>/docs/` ablegen und freigeben lassen.
3. Umsetzen. Code, der dauerhaft betrieben wird, wandert nach `src/<modul>/`, Projekt-SQL bleibt
   unter `projects/<projekt>/sql/`.
4. Entscheidungen in `memory-bank/decisions.md`, Stand in `memory-bank/progress.md`.
