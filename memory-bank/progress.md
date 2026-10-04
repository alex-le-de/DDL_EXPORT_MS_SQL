# Fortschritt

## Fertig

* [x] Repo initialisiert (`main`)
* [x] DDL-Export-Package (T-SQL + Writer + Agent-Job), Akzeptanztests grün
  (20 Prüfungen, `tests/run_tests.sh`)
* [x] Ablage je DB und Umgebung, Manifest für mehrere Server
* [x] Memory Bank, Projektordner, DB-Steckbriefe (Gerüst)

## Offen

* [ ] Installation auf den echten Servern (PROD, TEST)
* [ ] Konfigurationstabellen je DB festlegen
* [ ] DB-Steckbriefe fachlich füllen (Rolle, Schnittstellen, Verantwortliche)
* [ ] Monitoring: Anforderungen → Plan → Umsetzung
* [ ] Umstieg auf `DriftCheck`, wenn Git führend wird

## Behobene Probleme

* 2026-10-04: `ExportLog` nach Initial-Export leer. Ursache (wahrscheinlich): Der Lauf lief in
  einer offenen Transaktion (SSMS), die später zurückgerollt wurde. Jetzt weist
  `usp_Export_Run` Läufe bei `@@TRANCOUNT > 0` ab. Ein ungültiger `ExportMode` wird protokolliert.

## Bekannte Probleme und Grenzen

* Exportierte Skripte sind je Objekt ausführbar, aber nicht nach Abhängigkeiten sortiert
  (FKs beim Neuaufbau ggf. nachziehen).
* Nicht exportiert: Berechtigungen, Logins, Partitionierung, Volltext, CLR.
* Getestet nur mit SQL Server 2022 (Linux-Container), noch nicht auf Windows/Standard Edition
  produktiv.
