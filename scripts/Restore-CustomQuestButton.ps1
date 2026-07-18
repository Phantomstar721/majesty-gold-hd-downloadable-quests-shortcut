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

Write-Host "Majesty Gold HD Custom Quest Button restore"
Write-Host "Game path: $resolvedGamePath"
Write-Host ""

if (-not (Test-Path -LiteralPath $backupDir)) {
    throw "No backup folder found at $backupDir."
}

$backups = Get-ChildItem -LiteralPath $backupDir -Filter "UIData_*.dat.original" | Sort-Object Name
if ($backups.Count -eq 0) {
    throw "No UIData backups found in $backupDir."
}

foreach ($backup in $backups) {
    $fileName = $backup.Name -replace "\.original$", ""
    $target = Join-Path $dataPath $fileName
    Copy-Item -LiteralPath $backup.FullName -Destination $target -Force
    Write-Host "${fileName}: restored"
}

Write-Host ""
Write-Host "Done."
