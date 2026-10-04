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
#   6. Zweiter "Server" (eigene Admin-DB, Environment=TEST) exportiert ins selbe Repo:
#      Round-Trip-DB unter <DB>/TEST identisch zu <DB>/PROD, PROD-Lauf laesst TEST unberuehrt
#   7. Jobs: Job mit T-SQL-Steps in einer exportierten DB liegt unter <DB>/<Umgebung>/Jobs
#   8. Deaktivierte DB -> nur deren Ordner dieses Servers wird entfernt
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
ADMIN=DDL_Export_Admin   # "Server" PROD; DDL_Export_Admin_T simuliert den Testserver
run()  { sq -d "$ADMIN" -Q "SET NOCOUNT ON; EXEC ddl.usp_Export_Run;" > /dev/null; }
writer() {
    "$PWSH" -NoProfile -File "$REPO/src/writer/Write-DdlExport.ps1" -ExportRoot "$EXP" \
        -ConnectionString "Server=localhost;Database=$ADMIN;User Id=sa;Password=$SA_PW;TrustServerCertificate=True" "$@"
}
install() {   # $1 = Admin-DB, $2 = Umgebung
    docker exec -w /tmp/ddlx/src/install "$CONTAINER" /opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa -P "$SA_PW" -b \
        -i Install.sql -v AdminDb="$1" ExportRoot="$EXP" Environment="$2" > /dev/null
}
P=DDLX_Test/PROD
T=DDLX_Test/TEST
gitq() { git -C "$EXP" -c user.email=test@local -c user.name=test "$@"; }
ok()   { echo "  OK   $*"; }
fail() { echo "  FAIL $*"; FAILED=1; }

echo "== SQL Server starten"
if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    docker run -d --name "$CONTAINER" -e ACCEPT_EULA=Y -e MSSQL_SA_PASSWORD="$SA_PW" \
        mcr.microsoft.com/mssql/server:2022-latest > /dev/null
    for _ in $(seq 1 60); do sq -Q "SELECT 1" > /dev/null 2>&1 && break; sleep 2; done
fi
docker exec -u 0 "$CONTAINER" rm -rf /tmp/ddlx && docker cp "$REPO" "$CONTAINER:/tmp/ddlx"

echo "== 1. Installation (2x)"
for db in DDL_Export_Admin DDL_Export_Admin_T; do
    sq -Q "IF DB_ID('$db') IS NOT NULL BEGIN ALTER DATABASE [$db] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$db]; END" > /dev/null
done
sq -Q "IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'DDLX_Wartung') EXEC msdb.dbo.sp_delete_job @job_name = N'DDLX_Wartung';" > /dev/null
for i in 1 2; do
    install DDL_Export_Admin PROD && ok "Install.sql Durchlauf $i" || fail "Install.sql Durchlauf $i"
done
sq -i /tmp/ddlx/tests/01_Create_TestDatabase.sql > /dev/null
sq -d DDL_Export_Admin -Q "SET NOCOUNT ON;
    INSERT ddl.ExportDatabase (DatabaseName) VALUES (N'DDLX_Test'), (N'DDLX_GibtEsNicht');
    INSERT ddl.ExportConfigTable (DatabaseName, SchemaName, TableName, MaskColumns)
    VALUES (N'DDLX_Test', N'cfg', N'Parameter', N'Geheim'), (N'DDLX_Test', N'cfg', N'Mapping', NULL);" > /dev/null

echo "== 2. Export"
run && writer > /dev/null && ok "Export + Writer" || fail "Export + Writer"
n=$(find "$EXP/$P" -type f | wc -l)
[ "$n" -ge 18 ] && ok "$n Dateien erzeugt" || fail "nur $n Dateien"
gitq init -q && gitq add -A && gitq commit -qm base

echo "== 3. Determinismus"
run && writer > /dev/null
[ -z "$(gitq status --porcelain)" ] && ok "kein Diff ohne DB-Aenderung" || { fail "Diff ohne Aenderung"; gitq status --porcelain; }

echo "== 4. Aenderungen"
sq -d DDLX_Test -Q "DROP PROCEDURE dbo.usp_KundeAnlegen; ALTER TABLE dbo.Kunde ADD Telefon varchar(30) NULL; UPDATE cfg.Mapping SET Ziel = N'Z' WHERE Quelle = N'X';" > /dev/null
run && writer > /dev/null
changed=$(gitq status --porcelain | sort | tr '\n' ' ')
expected=" D $P/StoredProcedures/dbo.usp_KundeAnlegen.sql  M $P/ConfigData/cfg.Mapping.sql  M $P/Tables/dbo.Kunde.sql  M $P/catalog.jsonl "
[ "$(echo $changed | tr ' ' '\n' | sort | tr '\n' ' ')" = "$(echo $expected | tr ' ' '\n' | sort | tr '\n' ' ')" ] \
    && ok "genau die geaenderten Dateien im Diff" || fail "unerwarteter Diff: $changed"
gitq add -A && gitq commit -qm s2

echo "== 5. DriftCheck"
sq -d DDL_Export_Admin -Q "UPDATE ddl.ExportSetting SET SettingValue = 'DriftCheck' WHERE SettingKey = 'ExportMode';" > /dev/null
run
set +e; writer > /dev/null; rc=$?; set -e
[ $rc -eq 0 ] && ok "DriftCheck ohne Abweichung: Exit 0" || fail "DriftCheck ohne Abweichung: Exit $rc"
echo "-- manuell" >> "$EXP/$P/Tables/dbo.Kunde.sql"
set +e; writer > /dev/null; rc=$?; set -e
[ $rc -eq 2 ] && ok "DriftCheck mit Abweichung: Exit 2" || fail "DriftCheck mit Abweichung: Exit $rc"
[ -n "$(gitq status --porcelain)" ] && ok "DriftCheck schreibt nichts zurueck" || fail "DriftCheck hat Datei ueberschrieben"
gitq checkout -q -- .
sq -d DDL_Export_Admin -Q "UPDATE ddl.ExportSetting SET SettingValue = 'Export' WHERE SettingKey = 'ExportMode';" > /dev/null

echo "== 6. Zweiter Server (TEST) im selben Repo / Round-Trip"
sq -Q "IF DB_ID('DDLX_Round') IS NOT NULL DROP DATABASE DDLX_Round; CREATE DATABASE DDLX_Round;" > /dev/null
docker exec -u 0 "$CONTAINER" rm -rf /tmp/ddlx-exp && docker cp "$EXP" "$CONTAINER:/tmp/ddlx-exp"
src=/tmp/ddlx-exp/$P
# Reihenfolge nach Abhaengigkeiten (Historientabelle vor Temporal-Tabelle, PK-Tabelle vor FK)
files="Schemas/cfg.sql Types/dbo.Kurztext.sql Types/dbo.IdListe.sql Sequences/dbo.SeqBeleg.sql
       Tables/cfg.ParameterHistorie.sql Tables/cfg.Parameter.sql Tables/cfg.Mapping.sql Tables/dbo.Kunde.sql Tables/dbo.Auftrag.sql
       Views/dbo.vAuftragKunde.sql Functions/dbo.fn_Brutto.sql Functions/dbo.fn_AuftraegeVon.sql
       Triggers/dbo.Kunde.trg_Kunde_Upd.sql Triggers/DB_trg_DDL_Log.sql Synonyms/dbo.synKunde.sql
       ConfigData/cfg.Parameter.sql ConfigData/cfg.Mapping.sql"
rt=0
for f in $files; do sq -d DDLX_Round -i "$src/$f" > /dev/null 2>&1 || { fail "Einspielen $f"; rt=1; }; done
[ $rt -eq 0 ] && ok "alle Skripte fehlerfrei in leere DB eingespielt"
# Testserver: eigene Admin-DB, Umgebung TEST, DDLX_Round wird als Ordner DDLX_Test exportiert
install DDL_Export_Admin_T TEST && ok "Install Testserver (TEST)" || fail "Install Testserver"
ADMIN=DDL_Export_Admin_T
sq -d "$ADMIN" -Q "SET NOCOUNT ON;
    UPDATE ddl.ExportSetting SET SettingValue = N'TESTSRV' WHERE SettingKey = 'ServerLabel';
    INSERT ddl.ExportDatabase (DatabaseName, FolderName) VALUES (N'DDLX_Round', N'DDLX_Test');
    INSERT ddl.ExportConfigTable (DatabaseName, SchemaName, TableName, MaskColumns)
    VALUES (N'DDLX_Round', N'cfg', N'Parameter', N'Geheim'), (N'DDLX_Round', N'cfg', N'Mapping', NULL);" > /dev/null
run && writer > /dev/null
[ -f "$EXP/$T/catalog.jsonl" ] && [ -f "$EXP/_Server/TEST/TESTSRV/manifest.txt" ] && ok "Ablage unter $T und _Server/TEST/TESTSRV" || fail "TEST-Ablage fehlt"
diff -r -x database.json "$EXP/$P" "$EXP/$T" > /dev/null \
    && ok "PROD und TEST identisch (Round-Trip)" || { fail "PROD/TEST unterschiedlich"; diff -r -x database.json "$EXP/$P" "$EXP/$T" | head -20; }
grep -q '"environment":"TEST"' "$EXP/$T/database.json" && ok "database.json mit Umgebung TEST" || fail "database.json TEST"
ADMIN=DDL_Export_Admin
before=$(find "$EXP/$T" -type f | wc -l)
run && writer > /dev/null
[ "$(find "$EXP/$T" -type f | wc -l)" -eq "$before" ] && ok "PROD-Lauf laesst TEST-Ordner unberuehrt" || fail "PROD-Lauf hat TEST-Ordner veraendert"

echo "== 7. Jobs"
sq -Q "EXEC msdb.dbo.sp_add_job @job_name = N'DDLX_Wartung';
       EXEC msdb.dbo.sp_add_jobstep @job_name = N'DDLX_Wartung', @step_name = N'S1', @subsystem = N'TSQL', @database_name = N'DDLX_Test', @command = N'SELECT 1';
       EXEC msdb.dbo.sp_add_jobserver @job_name = N'DDLX_Wartung';" > /dev/null
sq -d "$ADMIN" -Q "INSERT ddl.ExportJob (JobNamePattern) VALUES (N'DDLX%');" > /dev/null
run && writer > /dev/null
[ -f "$EXP/$P/Jobs/DDLX_Wartung.sql" ] && ok "Job mit DB-Bezug unter $P/Jobs" || fail "Job DDLX_Wartung nicht unter $P/Jobs"

echo "== 8. Deaktivierte DB"
sq -d "$ADMIN" -Q "UPDATE ddl.ExportDatabase SET IsActive = 0 WHERE DatabaseName = N'DDLX_Test';" > /dev/null
run && writer > /dev/null
[ ! -d "$EXP/$P" ] && ok "Ordner $P entfernt" || fail "Ordner $P existiert noch"
[ -f "$EXP/$T/catalog.jsonl" ] && ok "Ordner $T (anderer Server) bleibt erhalten" || fail "Ordner $T wurde entfernt"

rm -rf "$WORK"
echo
[ $FAILED -eq 0 ] && echo "ALLE TESTS BESTANDEN" || { echo "TESTS FEHLGESCHLAGEN"; exit 1; }
