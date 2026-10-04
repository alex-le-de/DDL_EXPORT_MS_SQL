# Technischer Kontext (Grund-Setting)

## SQL-Server-Landschaft

| Eigenschaft | Wert |
|---|---|
| Produkt | Microsoft SQL Server, **Standard Edition** |
| Version | offen (Annahme: 2017 oder neuer; das Package setzt 2017+ voraus) |
| Rollen | überwiegend **Schnittstellenserver** oder **Auswertungsserver** |
| Umgebungen | **PROD** und **TEST**, mehrere Server. Gleiche DB-Namen auf Prod und Test. |
| Bekannte Instanz | `EVHNT56` (Umgebung offen, bisheriger Export lief dort) |
| Authentifizierung | Windows (Integrated Security) |
| Automatisierung | SQL Server Agent (T-SQL- und CmdExec-Steps) |
| Dateiablage | lokal auf dem Server, z. B. `L:\Datenverarbeitung\...` |

### Bekannte Datenbanken auf EVHNT56

| DB | Rolle | Doku |
|---|---|---|
| BAG | offen | [export/BAG](../export/BAG/README.md) |
| Belvis_sd_sst | Schnittstelle BelVis (Annahme) | [export/Belvis_sd_sst](../export/Belvis_sd_sst/README.md) |
| Memi | offen | [export/Memi](../export/Memi/README.md) |
| Messwert | Messwerte (Annahme) | [export/Messwert](../export/Messwert/README.md) |
| PDB2BELVIS | Schnittstelle PDB → BelVis (Annahme) | [export/PDB2BELVIS](../export/PDB2BELVIS/README.md) |
| Statistik | Auswertungen/Statistiken | [export/Statistik](../export/Statistik/README.md) |
| Test | Test-DB (Name, nicht Umgebung) | [export/Test](../export/Test/README.md) |

### Installation DDL-Export auf EVHNT56 (Stand 2026-10-04)

| Einstellung | Wert |
|---|---|
| Admin-DB | `DDL_Export` (nicht der Standardname `DDL_Export_Admin`) |
| ExportRoot | `L:\Datenverarbeitung\DDL_EXPORT` (Freigabe `\\evhnt56\Datenverarbeitung`) |
| Repo-Klon | `L:\Datenverarbeitung\DDL_EXPORT_MS_SQL` |
| Zugriff | nur remote (SSMS, Freigabe), keine Anmeldung am Server |

## Einschränkungen der Standard Edition (relevant für Entwürfe)

* Ressourcen: max. 24 Kerne, Buffer Pool max. 128 GB je Instanz.
* Nicht verfügbar: Online-Index-Operationen, volle Always-On-Verfügbarkeitsgruppen (nur Basic
  AG mit einer DB), Resource Governor, Datenbank-Snapshots für Reporting.
* Verfügbar (seit 2016 SP1): Partitionierung, Columnstore, In-Memory-OLTP, Komprimierung,
  Row-Level Security und Dynamic Data Masking, jeweils mit Ressourcenlimits.
* SQL Server Agent und Database Mail stehen zur Verfügung.
* Entwürfe dürfen keine Enterprise-only-Features voraussetzen.

## Werkzeuge und Konventionen

* Export-Package: T-SQL (Admin-DB `DDL_Export_Admin`) + `Write-DdlExport.ps1`
  (Windows PowerShell 5.1, ohne SMO). Details: [docs/BETRIEB.md](../docs/BETRIEB.md).
* sqlcmd: startet mit `QUOTED_IDENTIFIER OFF`, deshalb immer `-I` oder `SET QUOTED_IDENTIFIER ON`.
  `:setvar` im Skript überschreibt `-v`.
* Agent-Token wie `$(ESCAPE_NONE(SRVR))` kollidieren mit sqlcmd-Variablen, deshalb `-x` nutzen
  oder das Token zusammensetzen.
* Skripte im Repo: ASCII in PowerShell- und SQL-Dateien (Umlaute vermeiden), CRLF (`.gitattributes`).
* Tests: Docker mit `mcr.microsoft.com/mssql/server:2022-latest`, `tests/run_tests.sh`.

## Offen

* SQL-Server-Versionen und Namen der Testserver
* Ziel-Host für das Monitoring (Docker verfügbar? Linux/Windows?)
* Verantwortliche je Datenbank
