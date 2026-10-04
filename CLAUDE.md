# Hinweise für KI-Agenten

## Zuerst lesen

1. `memory-bank/activeContext.md`, `memory-bank/progress.md` und `memory-bank/techContext.md`
   (Grund-Setting: MS SQL **Standard Edition**, Schnittstellen- und Auswertungsserver,
   PROD/TEST auf mehreren Servern). Regeln dazu: `memory-bank/README.md`.
2. Bei Arbeit an einem Vorhaben: `projects/<projekt>/README.md`.

## Wohin mit Dokumenten

* Projektdokumente nur nach `projects/<jahr>-<name>/docs/`. Ein neues Projekt entsteht als Kopie
  von `projects/_vorlage`.
* Fachwissen zu einer Datenbank: `export/<DB>/README.md` (Steckbrief, manuell).
* Betriebsdoku des Export-Packages: `docs/`.
* Keine neuen Markdown-Dateien im Repo-Root. Vorhandene Dokumente aktualisieren statt neue
  anlegen. Knapp schreiben.
* Am Ende einer Arbeitssitzung `memory-bank/activeContext.md` und `progress.md` aktualisieren,
  Entscheidungen in `memory-bank/decisions.md` eintragen.
* Entwürfe dürfen keine Enterprise-only-Features voraussetzen (Standard Edition).

## Inhalt des Repos

Dieses Repo enthält:

1. **`export/`**: die exportierte DDL-Struktur der MS-SQL-Datenbanken, je Datenbank und
   Umgebung unter `export/<DB>/<Umgebung>/` (z. B. `export/BAG/PROD`, `export/BAG/TEST`). Das ist die Wissensbasis für Analysen, Code-Generierung und
   Impact-Analysen.
2. **`src/`, `config/`, `tests/`**: das T-SQL-Package, das diesen Export erzeugt.
3. **`projects/`** und **`memory-bank/`**: Vorhaben mit ihrer Doku und der dauerhafte Kontext.

## Struktur durchsuchen

* Einstieg pro Datenbank: `export/<DB>/<Umgebung>/catalog.jsonl`. Server, Kompatibilitätslevel
  und Collation stehen in `database.json`. Für Fragen zum produktiven Stand gilt `PROD`.
  Abweichungen zwischen Prod und Test zeigt `git diff --no-index export/<DB>/PROD export/<DB>/TEST`.
  In `catalog.jsonl` ist jede Zeile ein JSON-Objekt für eine Tabelle, View, Prozedur oder Funktion, mit `columns`, `primaryKey`,
  `foreignKeys`, `parameters` und `description` (aus `MS_Description`).
  `file` verweist relativ auf das DDL-Skript. `configData` ist gesetzt, wenn die Tabelle
  eine Konfigurationstabelle ist, deren Inhalt in `ConfigData/` liegt.
* DDL je Objekt: `export/<DB>/<Umgebung>/<Objektart>/<schema>.<name>.sql`.
  Objektarten sind `Tables`, `Views`, `StoredProcedures`, `Functions`, `Triggers`,
  `Types`, `Sequences`, `Synonyms` und `Schemas`.
* Inhalte von Konfigurationstabellen: `export/<DB>/<Umgebung>/ConfigData/<schema>.<tabelle>.sql`.
  Spalten aus `MaskColumns` enthalten `N'***'` statt echter Werte.
* SQL-Agent-Jobs: `export/<DB>/<Umgebung>/Jobs/` (Jobs dieser DB) bzw.
  `export/_Server/<Umgebung>/<Server>/Jobs/` (übrige Jobs).
* Abhängigkeiten findest du per Volltextsuche (z. B. `grep -rl "dbo.Kunde" export/`) und über
  `foreignKeys` in `catalog.jsonl`.

## Regeln

* Dateien unter `export/<DB>/<Umgebung>/` und `export/_Server/` werden vom Writer des jeweiligen Servers erzeugt, solange
  `ExportMode = 'Export'` gilt. Manuelle Änderungen überschreibt dann der nächste Lauf.
  Im Modus `DriftCheck` ist das Repo führend und Änderungen erfolgen bewusst manuell.
* Das Dateiformat bleibt erhalten: Kopfzeilen, `GO` nach jeder Anweisung, Reihenfolge
  Tabelle → Indizes → FKs → Extended Properties.
* Package-Code (`src/install/*.sql`) muss mit SQL Server 2017 kompatibel bleiben.
  Trenner in `STRING_AGG` nur als Literal oder Variable. Mehrere `STRING_AGG` mit
  unterschiedlicher Sortierung gehören in getrennte `APPLY`s.
* Änderungen am Package mit `tests/run_tests.sh` prüfen (Docker, SQL Server 2022, pwsh).
* Zugangsdaten und Passwörter gehören nicht ins Repo.
