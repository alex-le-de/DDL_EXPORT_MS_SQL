# Hinweise für KI-Agenten

Dieses Repo enthält zwei Dinge:

1. **`export/`**: die exportierte DDL-Struktur der MS-SQL-Datenbanken, je Datenbank und
   Umgebung unter `export/<DB>/<Umgebung>/` (z. B. `export/BAG/PROD`, `export/BAG/TEST`). Das ist die Wissensbasis für Analysen, Code-Generierung und
   Impact-Analysen.
2. **`src/`, `config/`, `tests/`**: das T-SQL-Package, das diesen Export erzeugt.

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

* Dateien unter `export/` werden vom Writer des jeweiligen Servers erzeugt, solange
  `ExportMode = 'Export'` gilt. Manuelle Änderungen überschreibt dann der nächste Lauf.
  Im Modus `DriftCheck` ist das Repo führend und Änderungen erfolgen bewusst manuell.
* Das Dateiformat bleibt erhalten: Kopfzeilen, `GO` nach jeder Anweisung, Reihenfolge
  Tabelle → Indizes → FKs → Extended Properties.
* Package-Code (`src/install/*.sql`) muss mit SQL Server 2017 kompatibel bleiben.
  Trenner in `STRING_AGG` nur als Literal oder Variable. Mehrere `STRING_AGG` mit
  unterschiedlicher Sortierung gehören in getrennte `APPLY`s.
* Änderungen am Package mit `tests/run_tests.sh` prüfen (Docker, SQL Server 2022, pwsh).
* Zugangsdaten und Passwörter gehören nicht ins Repo.
