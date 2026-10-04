# Projekte

Jedes Vorhaben bekommt einen eigenen Ordner. Damit hat jedes Dokument einen festen Platz.

```
projects/<jahr>-<kurzname>/
  README.md     Steckbrief: Ziel, Status, Verantwortliche, betroffene DBs, Links (Pflicht)
  docs/         Plan, Konzepte, Analysen, Protokolle
  sql/          projektbezogene Skripte (Analysen, Migrationen, Einmal-Skripte)
```

Neues Projekt: `projects/_vorlage` kopieren und umbenennen, dann `README.md` ausfüllen.

## Regeln

* Ein Projekt bekommt **einen** Steckbrief. Weitere Dokumente nur, wenn sie gebraucht werden.
  Vorhandene Dokumente lieber aktualisieren als neue anlegen.
* Dateinamen: `docs/<YYYY-MM-DD>_<thema>.md` für datierte Dokumente (Protokolle, Analysen),
  sonst sprechend (`PLAN.md`, `KONZEPT.md`).
* Dauerhaft betriebener Code wandert nach `src/<modul>/`. Hier bleiben nur Projekt-Artefakte.
* Ist ein Projekt abgeschlossen, wird der Status im Steckbrief gesetzt. Der Ordner bleibt
  als Historie erhalten.
* Wichtige Entscheidungen zusätzlich in `memory-bank/decisions.md` eintragen.

## Übersicht

| Projekt | Status | Ziel |
|---|---|---|
| [2026-ddl-export](2026-ddl-export/README.md) | umgesetzt, Einführung offen | DDL-Struktur aller DBs (Prod/Test) versioniert in Git |
| [2026-monitoring](2026-monitoring/README.md) | Idee / Anforderungen | Excel-Auswertungen ablösen, Gesamtprozess überwachen (HTML bzw. Docker + Website) |
