<#
.SYNOPSIS
    Schreibt den DDL-Snapshot aus der Admin-DB als Dateien ins lokale Git-
    Arbeitsverzeichnis (Step 2 des Agent-Jobs "DDL_Export").

.DESCRIPTION
    Die gesamte DDL-Erzeugung passiert in T-SQL (ddl.usp_Export_Run). Dieses
    Skript ist bewusst schlank: kein SMO, kein dbatools, kein Git.

    Ablauf:
      1. Einstellungen (ExportRoot, ExportMode) und den letzten Lauf aus der
         Admin-DB lesen. Nur Laeufe mit Status Succeeded/Warning werden
         verarbeitet.
      2. Snapshot ddl.ExportScript lesen (1 Zeile = 1 Datei).
      3. Je nach ExportMode:
         Export     - geaenderte/neue Dateien schreiben (UTF-8 ohne BOM, CRLF),
                      unveraenderte Dateien nicht anfassen, Dateien entfernter
                      Objekte loeschen.
         DriftCheck - nichts schreiben; Abweichungen zwischen DB und
                      Arbeitsverzeichnis melden (Exit-Code 2).
         Off        - nichts tun.
         Geloescht bzw. als Drift gemeldet wird nur in den Ordnern, die dieser
         Server verwaltet (Manifest _Server\<Umgebung>\<Server>\manifest.txt,
         alter und neuer Stand) und nur Dateien *.sql, *.jsonl, *.json, *.txt.
         Ordner anderer Server (z. B. <DB>\TEST neben <DB>\PROD) bleiben unberuehrt.
      4. Ergebnis in ddl.ExportLog (Source = 'Writer') und auf der Konsole
         (Job-Historie) protokollieren.

    Exit-Codes: 0 = OK, 1 = Fehler, 2 = Drift erkannt (nur DriftCheck).

.PARAMETER SqlInstance
    SQL-Server-Instanz (Windows-Authentifizierung). Im Agent-Job wird der Instanzname beim
    Anlegen des Jobs fest eingetragen (src/job/Create_Job_DDL_Export.sql).

.PARAMETER AdminDatabase
    Name der Admin-DB (Standard: DDL_Export_Admin).

.PARAMETER ExportRoot
    Ueberschreibt ddl.ExportSetting.ExportRoot.

.PARAMETER Mode
    Ueberschreibt ddl.ExportSetting.ExportMode (Export | DriftCheck | Off).

.PARAMETER ConnectionString
    Optional: vollstaendiger Connection-String (statt SqlInstance/Windows-Auth).

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File Write-DdlExport.ps1 -SqlInstance EVHNT56
#>
[CmdletBinding()]
param(
    [string]$SqlInstance      = '.',
    [string]$AdminDatabase    = 'DDL_Export_Admin',
    [string]$ExportRoot       = '',
    [ValidateSet('', 'Export', 'DriftCheck', 'Off')]
    [string]$Mode             = '',
    [string]$ConnectionString = ''
)

$ErrorActionPreference = 'Stop'
$utf8NoBom   = New-Object System.Text.UTF8Encoding($false)
$managedExt  = @('.sql', '.jsonl', '.json', '.txt')

if (-not $ConnectionString) {
    $ConnectionString = "Server=$SqlInstance;Database=$AdminDatabase;Integrated Security=SSPI;Application Name=DDL_Export_Writer;Connect Timeout=30"
}

$conn  = $null
$runId = $null

function Write-Line {
    param([string]$Level, [string]$Message)
    Write-Output ("{0:yyyy-MM-dd HH:mm:ss}  {1,-5}  {2}" -f (Get-Date), $Level, $Message)
}

function Invoke-Sql {
    param([string]$Sql, [hashtable]$Params = @{})
    $cmd = $conn.CreateCommand()
    $cmd.CommandText    = $Sql
    $cmd.CommandTimeout = 300
    foreach ($k in $Params.Keys) {
        $v = $Params[$k]
        if ($null -eq $v) { $v = [DBNull]::Value }
        [void]$cmd.Parameters.AddWithValue($k, $v)
    }
    $dt = New-Object System.Data.DataTable
    $rd = $cmd.ExecuteReader()
    $dt.Load($rd)
    $rd.Close()
    return ,$dt
}

function Write-Log {
    param([string]$Level, [string]$Message)
    Write-Line $Level $Message
    if ($conn -and $conn.State -eq 'Open') {
        try {
            $msg = $Message
            if ($msg.Length -gt 4000) { $msg = $msg.Substring(0, 4000) }
            [void](Invoke-Sql -Sql 'EXEC ddl.usp_Log @RunId, @Level, @Message, NULL, ''Writer'';' `
                              -Params @{ '@RunId' = $runId; '@Level' = $Level; '@Message' = $msg })
        } catch { Write-Line 'WARN' "Log in DB fehlgeschlagen: $($_.Exception.Message)" }
    }
}

# Zeilenenden vereinheitlichen
function ConvertTo-Lf   { param([string]$Text) return $Text.Replace("`r`n", "`n").Replace("`r", "`n") }
function ConvertTo-Crlf { param([string]$Text) return (ConvertTo-Lf $Text).Replace("`n", "`r`n") }

$exitCode = 0
try {
    $conn = New-Object System.Data.SqlClient.SqlConnection($ConnectionString)
    $conn.Open()

    # --- Einstellungen und letzter Lauf ---------------------------------------
    $settings = @{}
    foreach ($r in (Invoke-Sql 'SELECT SettingKey, SettingValue FROM ddl.ExportSetting;').Rows) {
        $settings[[string]$r.SettingKey] = [string]$r.SettingValue
    }
    if (-not $ExportRoot) { $ExportRoot = $settings['ExportRoot'] }
    if (-not $Mode)       { $Mode       = $settings['ExportMode'] }
    if (-not $Mode)       { $Mode       = 'Export' }

    $run = (Invoke-Sql 'SELECT TOP (1) RunId, Status FROM ddl.ExportRun ORDER BY RunId DESC;').Rows
    if ($run.Count -eq 0) { throw 'Kein Exportlauf vorhanden. Zuerst ddl.usp_Export_Run ausfuehren.' }
    $runId  = [int]$run[0].RunId
    $status = [string]$run[0].Status

    Write-Log 'INFO' "Writer gestartet: Lauf $runId (Status $status), Modus $Mode, ExportRoot '$ExportRoot'."

    if ($Mode -eq 'Off' -or $status -eq 'Skipped') {
        Write-Log 'INFO' 'ExportMode = Off - nichts zu tun.'
        exit 0
    }
    if ($status -notin @('Succeeded', 'Warning')) {
        throw "Letzter Lauf $runId hat Status '$status' - es werden keine Dateien geschrieben."
    }
    if (-not $ExportRoot -or $ExportRoot.Trim().Length -lt 4) {
        throw "ExportRoot '$ExportRoot' ist leer oder zu kurz (Schutz vor Schreiben in ein Laufwerks-Root)."
    }
    if (-not [System.IO.Path]::IsPathRooted($ExportRoot) -or $ExportRoot -match '^[A-Za-z][\\/]') {
        throw "ExportRoot '$ExportRoot' ist kein absoluter Pfad (z. B. 'L:\Datenverarbeitung\DDL_EXPORT_MS_SQL\export' oder '\\server\freigabe\...'). Bitte ddl.ExportSetting.ExportRoot korrigieren."
    }
    $ExportRoot = [System.IO.Path]::GetFullPath($ExportRoot)
    if (-not (Test-Path -LiteralPath $ExportRoot)) {
        if ($Mode -eq 'Export') { [void](New-Item -ItemType Directory -Path $ExportRoot -Force) }
        else { throw "ExportRoot '$ExportRoot' existiert nicht." }
    }

    # --- Snapshot lesen ----------------------------------------------------------
    $rows = (Invoke-Sql 'SELECT RelativePath, ObjectType, Content FROM ddl.ExportScript ORDER BY RelativePath;').Rows
    $expected = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $sep = [System.IO.Path]::DirectorySeparatorChar
    $manifestPath = $null; $manifestNew = ''
    foreach ($r in $rows) {
        $rel  = ([string]$r.RelativePath).Replace('/', $sep)
        $full = Join-Path $ExportRoot $rel
        $expected[$full] = [string]$r.Content
        if ([string]$r.ObjectType -eq 'Manifest') { $manifestPath = $full; $manifestNew = [string]$r.Content }
    }

    # --- Verwaltete Ordner: Manifest neu (Snapshot) + alt (Datei) ----------------------
    function Get-ManifestFolders([string]$Text) {
        $result = @()
        foreach ($line in (ConvertTo-Lf $Text).Split("`n")) {
            $l = $line.Trim()
            if (-not $l -or $l.StartsWith('#')) { continue }
            $parts = @($l.Split('/') | Where-Object { $_ })
            # nur relative Pfade mit mindestens 2 Ebenen (<DB>/<Umgebung>), kein '..'
            if ($parts.Count -lt 2 -or $parts -contains '..' -or $l -match '^[A-Za-z]:|^[\\/]') { continue }
            $result += ($parts -join $sep)
        }
        return $result
    }
    $managed = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    if ($manifestPath) {
        foreach ($m in (Get-ManifestFolders $manifestNew)) { [void]$managed.Add($m) }
        if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
            foreach ($m in (Get-ManifestFolders ([System.IO.File]::ReadAllText($manifestPath, $utf8NoBom)))) { [void]$managed.Add($m) }
        }
    } else {
        Write-Log 'WARN' 'Snapshot enthaelt kein Manifest - es wird nichts geloescht.'
    }

    $written = 0; $unchanged = 0; $deleted = 0
    $drift = New-Object System.Collections.Generic.List[string]

    # --- Dateien schreiben / vergleichen ------------------------------------------
    foreach ($path in ($expected.Keys | Sort-Object)) {
        $content = ConvertTo-Crlf $expected[$path]
        $same = $false
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $current = [System.IO.File]::ReadAllText($path, $utf8NoBom)
            $same = ((ConvertTo-Lf $current) -ceq (ConvertTo-Lf $content))
        }
        if ($same) { $unchanged++; continue }

        $relPath = $path.Substring($ExportRoot.Length).TrimStart($sep)
        if ($Mode -eq 'Export') {
            $dir = Split-Path -Parent $path
            if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
            [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
            $written++
        } else {
            if (Test-Path -LiteralPath $path) { $drift.Add("GEAENDERT  $relPath") }
            else                               { $drift.Add("FEHLT      $relPath  (in DB vorhanden, nicht im Repo)") }
        }
    }

    # --- Dateien entfernter Objekte (nur in verwalteten Ordnern) ------------------------
    foreach ($d in ($managed | Sort-Object)) {
        $root = Join-Path $ExportRoot $d
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $files = Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $managedExt -contains $_.Extension.ToLowerInvariant() }
        foreach ($f in $files) {
            if ($expected.ContainsKey($f.FullName)) { continue }
            $relPath = $f.FullName.Substring($ExportRoot.Length).TrimStart($sep)
            if ($Mode -eq 'Export') {
                if ($expected.Count -eq 0) { continue }   # Schutz: leerer Snapshot loescht nichts
                Remove-Item -LiteralPath $f.FullName -Force
                $deleted++
            } else {
                $drift.Add("NUR REPO   $relPath  (nicht in DB vorhanden)")
            }
        }
        if ($Mode -eq 'Export') {
            # leere Ordner entfernen (tiefste zuerst), danach leere Elternordner bis unterhalb ExportRoot
            Get-ChildItem -LiteralPath $root -Recurse -Directory |
                Sort-Object { $_.FullName.Length } -Descending |
                Where-Object { -not (Get-ChildItem -LiteralPath $_.FullName -Force) } |
                ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }
            $dir = $root
            while ($dir -and $dir.Length -gt $ExportRoot.Length -and (Test-Path -LiteralPath $dir) -and
                   -not (Get-ChildItem -LiteralPath $dir -Force)) {
                Remove-Item -LiteralPath $dir -Force
                $dir = Split-Path -Parent $dir
            }
        }
    }

    if ($Mode -eq 'Export') {
        if ($expected.Count -eq 0) { Write-Log 'WARN' 'Snapshot ist leer - es wurden keine Dateien geloescht.' }
        Write-Log 'INFO' "Export abgeschlossen: $written geschrieben, $unchanged unveraendert, $deleted geloescht."
    } else {
        if ($drift.Count -gt 0) {
            $shown = 0
            foreach ($line in $drift) {
                if ($shown -ge 200) { Write-Log 'WARN' "... weitere $($drift.Count - $shown) Abweichungen."; break }
                Write-Log 'WARN' "Drift: $line"
                $shown++
            }
            Write-Log 'ERROR' "DriftCheck: $($drift.Count) Abweichung(en) zwischen Datenbank und Repo."
            $exitCode = 2
        } else {
            Write-Log 'INFO' "DriftCheck: keine Abweichungen ($unchanged Dateien geprueft)."
        }
    }
}
catch {
    $exitCode = 1
    Write-Log 'ERROR' "Writer fehlgeschlagen: $($_.Exception.Message)"
}
finally {
    if ($conn) { $conn.Dispose() }
}
exit $exitCode
