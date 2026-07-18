param(
    [string]$GamePath = ""
)

$ErrorActionPreference = "Stop"
$DefaultGamePath = "C:\Program Files (x86)\Steam\steamapps\common\Majesty HD"

function Get-MajestyPath {
    param([string]$RequestedPath)

    if ($RequestedPath) {
        return $RequestedPath
    }

    if (Test-Path -LiteralPath $DefaultGamePath) {
        return $DefaultGamePath
    }

    foreach ($key in @(
        "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
        "HKLM:\SOFTWARE\Valve\Steam",
        "HKCU:\SOFTWARE\Valve\Steam"
    )) {
        try {
            $installPath = (Get-ItemProperty -LiteralPath $key -ErrorAction Stop).InstallPath
            if ($installPath) {
                $candidate = Join-Path $installPath "steamapps\common\Majesty HD"
                if (Test-Path -LiteralPath $candidate) {
                    return $candidate
                }
            }
        } catch {
        }
    }

    throw "Could not find Majesty HD. Re-run with -GamePath ""C:\Path\To\Majesty HD""."
}

$resolvedGamePath = Get-MajestyPath $GamePath
$dataPath = Join-Path $resolvedGamePath "Data"
$backupDir = Join-Path $dataPath "_custom_quest_button_originals"
$exePath = Join-Path $resolvedGamePath "MajestyHD.exe"
$exeBackup = Join-Path $backupDir "MajestyHD.exe.original"

Write-Host "Majesty Gold HD Custom Quest Button restore"
Write-Host "Game path: $resolvedGamePath"
Write-Host ""

if (-not (Test-Path -LiteralPath $backupDir)) {
    throw "No backup folder found at $backupDir."
}

$backups = Get-ChildItem -LiteralPath $backupDir -Filter "UIData_*.dat.original" | Sort-Object Name
$hasExeBackup = Test-Path -LiteralPath $exeBackup
if ($backups.Count -eq 0 -and -not $hasExeBackup) {
    throw "No UIData or MajestyHD.exe backups found in $backupDir."
}

$targets = foreach ($backup in $backups) {
    $fileName = $backup.Name -replace "\.original$", ""
    Join-Path $dataPath $fileName
}

foreach ($target in $targets) {
    if (-not (Test-Path -LiteralPath $target)) {
        continue
    }

    $stream = $null
    try {
        $stream = [IO.File]::Open($target, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    } catch {
        $name = Split-Path -Leaf $target
        throw "Cannot restore $name because it is in use or not writable. Close Majesty Gold HD and run this restore again. If the game is closed, right-click the BAT and choose Run as administrator."
    } finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}

if ($hasExeBackup -and (Test-Path -LiteralPath $exePath)) {
    $stream = $null
    try {
        $stream = [IO.File]::Open($exePath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    } catch {
        throw "Cannot restore MajestyHD.exe because it is in use or not writable. Close Majesty Gold HD and run this restore again. If the game is closed, right-click the BAT and choose Run as administrator."
    } finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}

foreach ($backup in $backups) {
    $fileName = $backup.Name -replace "\.original$", ""
    $target = Join-Path $dataPath $fileName
    Copy-Item -LiteralPath $backup.FullName -Destination $target -Force
    Write-Host "${fileName}: restored"
}

if ($hasExeBackup -and (Test-Path -LiteralPath $exePath)) {
    Copy-Item -LiteralPath $exeBackup -Destination $exePath -Force
    Write-Host "MajestyHD.exe: restored"
}

Write-Host ""
Write-Host "Done."
