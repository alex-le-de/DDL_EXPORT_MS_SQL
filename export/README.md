# export/

Dieser Ordner wird von den Agent-Jobs `DDL_Export` der einzelnen Server gepflegt
(Writer `src/writer/Write-DdlExport.ps1`). Jeder Server schreibt nur in seine eigenen Ordner.

```
<DB>/<Umgebung>/                       z. B. BAG/PROD, BAG/TEST
  database.json                        Server, Umgebung, Kompatibilitätslevel, Collation
  catalog.jsonl                        1 JSON-Zeile je Tabelle/View/Prozedur/Funktion (für Agenten)
  Schemas/ Types/ Sequences/ Synonyms/
  Tables/<schema>.<tabelle>.sql        CREATE TABLE + Constraints + Indizes + FKs + Extended Properties
  Views/ StoredProcedures/ Functions/
  Triggers/<schema>.<tabelle>.<trigger>.sql | DB_<trigger>.sql
  ConfigData/<schema>.<tabelle>.sql    Inhalte der Konfigurationstabellen (DELETE + INSERT)
  Jobs/<jobname>.sql                   Agent-Jobs, deren T-SQL-Steps in dieser DB laufen
_Server/<Umgebung>/<Server>/
  Jobs/<jobname>.sql                   übrige Agent-Jobs des Servers
  manifest.txt                         vom Server verwaltete Ordner
```

Prod gegen Test vergleichen: `git diff --no-index export/BAG/PROD export/BAG/TEST`

Welche Datenbanken, Konfig-Tabellen und Jobs hier landen, steht in der Admin-DB
`DDL_Export_Admin` des jeweiligen Servers. Siehe [docs/BETRIEB.md](../docs/BETRIEB.md).
