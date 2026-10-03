# export/

Dieser Ordner wird vom Agent-Job `DDL_Export` gepflegt (Writer `src/writer/Write-DdlExport.ps1`).

```
Databases/<DB>/
  catalog.jsonl              1 JSON-Zeile je Tabelle/View/Prozedur/Funktion (für Agenten)
  Schemas/ Types/ Sequences/ Synonyms/
  Tables/<schema>.<tabelle>.sql        CREATE TABLE + Constraints + Indizes + FKs + Extended Properties
  Views/ StoredProcedures/ Functions/
  Triggers/<schema>.<tabelle>.<trigger>.sql | DB_<trigger>.sql
  ConfigData/<schema>.<tabelle>.sql    Inhalte der Konfigurationstabellen (DELETE + INSERT)
Jobs/<jobname>.sql                     SQL-Server-Agent-Jobs
```

Welche Datenbanken, Konfig-Tabellen und Jobs hier landen, steht in der Admin-DB
`DDL_Export_Admin` (Tabellen `ddl.ExportDatabase`, `ddl.ExportConfigTable` und `ddl.ExportJob`).
Siehe [docs/BETRIEB.md](../docs/BETRIEB.md).
