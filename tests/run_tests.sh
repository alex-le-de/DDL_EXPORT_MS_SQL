#!/usr/bin/env bash
# =============================================================================
# Akzeptanztests des DDL-Export-Packages gegen einen SQL Server 2022 in Docker.
#
# Voraussetzungen: docker, pwsh (PowerShell 7), git
#   PWSH=/pfad/zu/pwsh tests/run_tests.sh
#
# Getestet wird:
#   1. Installation (zweimal -> idempotent)
#   2. Export + Writer
#   3. Zweiter Lauf ohne DB-Aenderung -> kein Git-Diff
#   4. Objekt geaendert/geloescht + Konfig-Daten geaendert -> genau diese Dateien im Diff
#   5. DriftCheck: Abweichungen -> Exit-Code 2, ohne Abweichung -> 0
#   6. Round-Trip: exportierte Skripte in leere DB einspielen, erneut exportieren -> identisch
#   7. Deaktivierte DB -> Dateien werden entfernt
# =============================================================================
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PWSH="${PWSH:-pwsh}"
CONTAINER="${CONTAINER:-ddlx-mssql}"
SA_PW='Test#Passw0rd!'
WORK="$(mktemp -d)"
EXP="$WORK/export"
FAILED=0

sq()   { docker exec -i "$CONTAINER" /opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa -P "$SA_PW" -I -b "$@"; }
run()  { sq -d DDL_Export_Admin -Q "SET NOCOUNT ON; EXEC ddl.usp_Export_Run;" > /dev/null; }
writer() {
    "$PWSH" -NoProfile -File "$REPO/src/writer/Write-DdlExport.ps1" -ExportRoot "$EXP" \
        -ConnectionString "Server=localhost;Database=DDL_Export_Admin;User Id=sa;Password=$SA_PW;TrustServerCertificate=True" "$@"
}
gitq() { git -C "$EXP" -c user.email=test@local -c user.name=test "$@"; }
ok()   { echo "  OK   $*"; }
fail() { echo "  FAIL $*"; FAILED=1; }

echo "== SQL Server starten"
if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    docker run -d --name "$CONTAINER" -e ACCEPT_EULA=Y -e MSSQL_SA_PASSWORD="$SA_PW" \
        mcr.microsoft.com/mssql/server:2022-latest > /dev/null
    for _ in $(seq 1 60); do sq -Q "SELECT 1" > /dev/null 2>&1 && break; sleep 2; done
fi
docker exec "$CONTAINER" rm -rf /tmp/ddlx && docker cp "$REPO" "$CONTAINER:/tmp/ddlx"

echo "== 1. Installation (2x)"
sq -Q "IF DB_ID('DDL_Export_Admin') IS NOT NULL BEGIN ALTER DATABASE DDL_Export_Admin SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE DDL_Export_Admin; END" > /dev/null
for i in 1 2; do
    docker exec -w /tmp/ddlx/src/install "$CONTAINER" /opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa -P "$SA_PW" -b \
        -i Install.sql -v AdminDb=DDL_Export_Admin ExportRoot="$EXP" > /dev/null && ok "Install.sql Durchlauf $i" || fail "Install.sql Durchlauf $i"
done
sq -i /tmp/ddlx/tests/01_Create_TestDatabase.sql > /dev/null
sq -d DDL_Export_Admin -Q "SET NOCOUNT ON;
    INSERT ddl.ExportDatabase (DatabaseName) VALUES (N'DDLX_Test'), (N'DDLX_GibtEsNicht');
    INSERT ddl.ExportConfigTable (DatabaseName, SchemaName, TableName, MaskColumns)
    VALUES (N'DDLX_Test', N'cfg', N'Parameter', N'Geheim'), (N'DDLX_Test', N'cfg', N'Mapping', NULL);" > /dev/null

echo "== 2. Export"
run && writer > /dev/null && ok "Export + Writer" || fail "Export + Writer"
n=$(find "$EXP/Databases/DDLX_Test" -type f | wc -l)
[ "$n" -ge 18 ] && ok "$n Dateien erzeugt" || fail "nur $n Dateien"
gitq init -q && gitq add -A && gitq commit -qm base

echo "== 3. Determinismus"
run && writer > /dev/null
[ -z "$(gitq status --porcelain)" ] && ok "kein Diff ohne DB-Aenderung" || { fail "Diff ohne Aenderung"; gitq status --porcelain; }

echo "== 4. Aenderungen"
sq -d DDLX_Test -Q "DROP PROCEDURE dbo.usp_KundeAnlegen; ALTER TABLE dbo.Kunde ADD Telefon varchar(30) NULL; UPDATE cfg.Mapping SET Ziel = N'Z' WHERE Quelle = N'X';" > /dev/null
run && writer > /dev/null
changed=$(gitq status --porcelain | sort | tr '\n' ' ')
expected=" D Databases/DDLX_Test/StoredProcedures/dbo.usp_KundeAnlegen.sql  M Databases/DDLX_Test/ConfigData/cfg.Mapping.sql  M Databases/DDLX_Test/Tables/dbo.Kunde.sql  M Databases/DDLX_Test/catalog.jsonl "
[ "$(echo $changed | tr ' ' '\n' | sort | tr '\n' ' ')" = "$(echo $expected | tr ' ' '\n' | sort | tr '\n' ' ')" ] \
    && ok "genau die geaenderten Dateien im Diff" || fail "unerwarteter Diff: $changed"
gitq add -A && gitq commit -qm s2

echo "== 5. DriftCheck"
sq -d DDL_Export_Admin -Q "UPDATE ddl.ExportSetting SET SettingValue = 'DriftCheck' WHERE SettingKey = 'ExportMode';" > /dev/null
run
set +e; writer > /dev/null; rc=$?; set -e
[ $rc -eq 0 ] && ok "DriftCheck ohne Abweichung: Exit 0" || fail "DriftCheck ohne Abweichung: Exit $rc"
echo "-- manuell" >> "$EXP/Databases/DDLX_Test/Tables/dbo.Kunde.sql"
set +e; writer > /dev/null; rc=$?; set -e
[ $rc -eq 2 ] && ok "DriftCheck mit Abweichung: Exit 2" || fail "DriftCheck mit Abweichung: Exit $rc"
[ -n "$(gitq status --porcelain)" ] && ok "DriftCheck schreibt nichts zurueck" || fail "DriftCheck hat Datei ueberschrieben"
gitq checkout -q -- .
sq -d DDL_Export_Admin -Q "UPDATE ddl.ExportSetting SET SettingValue = 'Export' WHERE SettingKey = 'ExportMode';" > /dev/null

echo "== 6. Round-Trip"
sq -Q "IF DB_ID('DDLX_Round') IS NOT NULL DROP DATABASE DDLX_Round; CREATE DATABASE DDLX_Round;" > /dev/null
docker exec "$CONTAINER" rm -rf /tmp/ddlx-exp && docker cp "$EXP" "$CONTAINER:/tmp/ddlx-exp"
src=/tmp/ddlx-exp/Databases/DDLX_Test
# Reihenfolge nach Abhaengigkeiten (Historientabelle vor Temporal-Tabelle, PK-Tabelle vor FK)
files="Schemas/cfg.sql Types/dbo.Kurztext.sql Types/dbo.IdListe.sql Sequences/dbo.SeqBeleg.sql
       Tables/cfg.ParameterHistorie.sql Tables/cfg.Parameter.sql Tables/cfg.Mapping.sql Tables/dbo.Kunde.sql Tables/dbo.Auftrag.sql
       Views/dbo.vAuftragKunde.sql Functions/dbo.fn_Brutto.sql Functions/dbo.fn_AuftraegeVon.sql
       Triggers/dbo.Kunde.trg_Kunde_Upd.sql Triggers/DB_trg_DDL_Log.sql Synonyms/dbo.synKunde.sql
       ConfigData/cfg.Parameter.sql ConfigData/cfg.Mapping.sql"
rt=0
for f in $files; do sq -d DDLX_Round -i "$src/$f" > /dev/null 2>&1 || { fail "Einspielen $f"; rt=1; }; done
[ $rt -eq 0 ] && ok "alle Skripte fehlerfrei eingespielt"
sq -d DDL_Export_Admin -Q "SET NOCOUNT ON;
    INSERT ddl.ExportDatabase (DatabaseName) VALUES (N'DDLX_Round');
    INSERT ddl.ExportConfigTable (DatabaseName, SchemaName, TableName, MaskColumns)
    VALUES (N'DDLX_Round', N'cfg', N'Parameter', N'Geheim'), (N'DDLX_Round', N'cfg', N'Mapping', NULL);" > /dev/null
run && writer > /dev/null
diff -r "$EXP/Databases/DDLX_Test" "$EXP/Databases/DDLX_Round" > /dev/null \
    && ok "Export der neu aufgebauten DB ist identisch" || { fail "Round-Trip unterschiedlich"; diff -r "$EXP/Databases/DDLX_Test" "$EXP/Databases/DDLX_Round" | head -20; }

echo "== 7. Deaktivierte DB"
sq -d DDL_Export_Admin -Q "UPDATE ddl.ExportDatabase SET IsActive = 0 WHERE DatabaseName = N'DDLX_Round';" > /dev/null
run && writer > /dev/null
[ ! -d "$EXP/Databases/DDLX_Round" ] && ok "Dateien der deaktivierten DB entfernt" || fail "Ordner DDLX_Round existiert noch"

rm -rf "$WORK"
echo
[ $FAILED -eq 0 ] && echo "ALLE TESTS BESTANDEN" || { echo "TESTS FEHLGESCHLAGEN"; exit 1; }
