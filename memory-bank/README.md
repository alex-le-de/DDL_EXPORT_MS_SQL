# Memory Bank

Das dauerhafte Gedächtnis für Menschen und KI-Agenten. Agenten starten jede Sitzung ohne
Erinnerung. Was hier nicht steht, ist für sie nicht bekannt.

| Datei | Inhalt | Ändert sich |
|---|---|---|
| [projectbrief.md](projectbrief.md) | Auftrag und Ziele des Repos | selten |
| [productContext.md](productContext.md) | Warum: Nutzer, Probleme, gewünschte Arbeitsweise | selten |
| [techContext.md](techContext.md) | **Grund-Setting:** Server, Editionen, Datenbanken, Werkzeuge, Einschränkungen | bei Änderungen der Umgebung |
| [systemPatterns.md](systemPatterns.md) | Architektur und wiederkehrende Muster | bei Architekturentscheidungen |
| [decisions.md](decisions.md) | Entscheidungslog (was, warum, Datum) | bei jeder Entscheidung |
| [activeContext.md](activeContext.md) | Woran gerade gearbeitet wird, nächste Schritte, offene Fragen | ständig |
| [progress.md](progress.md) | Was fertig ist, was offen ist, bekannte Probleme | nach jedem Arbeitsschritt |

## Regeln

1. **Zu Beginn einer Sitzung** lesen: `activeContext.md`, `progress.md` und `techContext.md`.
   Den Rest bei Bedarf.
2. **Am Ende einer Sitzung** (oder nach einem abgeschlossenen Schritt) `activeContext.md` und
   `progress.md` aktualisieren. Neue Entscheidungen kommen in `decisions.md`.
3. Kurz halten. Hier stehen Fakten und Verweise, keine Abhandlungen. Ausführliche Dokumente
   gehören in `projects/<projekt>/docs/` oder `docs/`, hier nur verlinkt.
4. Keine Zugangsdaten, Passwörter oder personenbezogenen Daten.
5. Unbekanntes als **offen** markieren, nicht raten.
