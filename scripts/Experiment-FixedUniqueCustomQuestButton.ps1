param(
    [string]$GamePath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$DefaultGamePath = "C:\Program Files (x86)\Steam\steamapps\common\Majesty HD"
$CustomQuestObjectBytes = [byte[]](0xC2, 0x0F, 0x00, 0x00)
$UniqueFixedObjectBytes = [byte[]](0x0D, 0x17, 0x00, 0x00)
$CustomQuestCompareImmediateOffset = 0x7A0FE

function Get-MajestyPath {
    param([string]$RequestedPath)

    if ($RequestedPath) {
        return $RequestedPath
    }
    if (Test-Path -LiteralPath $DefaultGamePath) {
        return $DefaultGamePath
    }
    throw "Could not find Majesty HD. Re-run with -GamePath ""C:\Path\To\Majesty HD""."
}

function Test-BytesEqual {
    param([byte[]]$Bytes, [int]$Offset, [byte[]]$Expected)

    if ($Bytes.Length -lt ($Offset + $Expected.Length)) {
        return $false
    }
    for ($i = 0; $i -lt $Expected.Length; $i++) {
        if ($Bytes[$Offset + $i] -ne $Expected[$i]) {
            return $false
        }
    }
    return $true
}

function Write-Bytes {
    param([byte[]]$Bytes, [int]$Offset, [byte[]]$Patch)

    for ($i = 0; $i -lt $Patch.Length; $i++) {
        $Bytes[$Offset + $i] = $Patch[$i]
    }
}

function Assert-FileWritable {
    param([string]$Path)

    $stream = $null
    try {
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    } catch {
        $name = Split-Path -Leaf $Path
        throw "Cannot patch $name because it is in use or not writable. Close Majesty Gold HD and run this experiment again. If the game is closed, right-click the BAT and choose Run as administrator."
    } finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}

$resolvedGamePath = Get-MajestyPath $GamePath
$exePath = Join-Path $resolvedGamePath "MajestyHD.exe"
$dataPath = Join-Path $resolvedGamePath "Data"
$backupDir = Join-Path $dataPath "_custom_quest_button_originals"
$backupPath = Join-Path $backupDir "MajestyHD.exe.original"

if (-not (Test-Path -LiteralPath $exePath)) {
    throw "Could not find MajestyHD.exe at $exePath."
}

[byte[]]$bytes = [IO.File]::ReadAllBytes($exePath)
$isStock = Test-BytesEqual $bytes $CustomQuestCompareImmediateOffset $CustomQuestObjectBytes
$isPatched = Test-BytesEqual $bytes $CustomQuestCompareImmediateOffset $UniqueFixedObjectBytes
if (-not $isStock -and -not $isPatched) {
    $found = [BitConverter]::ToString($bytes, $CustomQuestCompareImmediateOffset, 4)
    throw ("MajestyHD.exe does not match the expected Steam build at file offset 0x{0:X}. Found {1}." -f $CustomQuestCompareImmediateOffset, $found)
}

Write-Host "Majesty Gold HD experiment: Fixed unique Custom Quest button"
Write-Host "Game path: $resolvedGamePath"
if ($DryRun) {
    Write-Host "Dry run: no files will be changed."
}
Write-Host ""

$status = if ($isPatched) { "AlreadyPatched" } else { "WouldPatch" }
if (-not $DryRun -and $status -eq "WouldPatch") {
    $status = "Patched"
}
Write-Host ("MajestyHD.exe: {0} Custom Quest click dispatcher 4034 -> 5901 at file offset 0x{1:X}" -f $status, $CustomQuestCompareImmediateOffset)

$cloneArgs = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", (Join-Path $PSScriptRoot "Experiment-CloneFixedCustomQuestButton.ps1"),
    "-RemoveMapButton",
    "-ObjectId", "5901"
)
if ($DryRun) {
    $cloneArgs += "-DryRun"
}

Write-Host ""
& powershell.exe @cloneArgs
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

if ($DryRun) {
    Write-Host ""
    Write-Host "Dry run complete."
    exit
}

Assert-FileWritable $exePath

if (-not (Test-Path -LiteralPath $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir | Out-Null
}
if (-not (Test-Path -LiteralPath $backupPath)) {
    Copy-Item -LiteralPath $exePath -Destination $backupPath
}

Write-Bytes $bytes $CustomQuestCompareImmediateOffset $UniqueFixedObjectBytes
[IO.File]::WriteAllBytes($exePath, $bytes)

Write-Host ""
Write-Host "Done. Use Restore Original Custom Quest Button.bat to undo this experiment."
