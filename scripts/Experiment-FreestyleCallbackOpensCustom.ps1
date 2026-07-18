param(
    [string]$GamePath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$DefaultGamePath = "C:\Program Files (x86)\Steam\steamapps\common\Majesty HD"
$FreestyleCallbackBytes = [byte[]](0x00, 0x93, 0x47, 0x00)
$CustomQuestCallbackBytes = [byte[]](0x00, 0x92, 0x47, 0x00)

# These are file offsets inside the current Steam MajestyHD.exe build. They are the
# immediate values in "push 0x479300" for object IDs 5000 and 5900 in APdb setup.
$CallbackImmediateOffsets = @(0x798B6, 0x798CE)

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

foreach ($offset in $CallbackImmediateOffsets) {
    $isStock = Test-BytesEqual $bytes $offset $FreestyleCallbackBytes
    $isPatched = Test-BytesEqual $bytes $offset $CustomQuestCallbackBytes
    if (-not $isStock -and -not $isPatched) {
        $found = [BitConverter]::ToString($bytes, $offset, 4)
        throw ("MajestyHD.exe does not match the expected Steam build at file offset 0x{0:X}. Found {1}." -f $offset, $found)
    }
}

Write-Host "Majesty Gold HD experiment: Freestyle callback opens Custom Quests"
Write-Host "Game path: $resolvedGamePath"
if ($DryRun) {
    Write-Host "Dry run: no files will be changed."
}
Write-Host ""

foreach ($offset in $CallbackImmediateOffsets) {
    $status = if (Test-BytesEqual $bytes $offset $CustomQuestCallbackBytes) { "AlreadyPatched" } else { "WouldPatch" }
    if (-not $DryRun -and $status -eq "WouldPatch") {
        $status = "Patched"
    }
    Write-Host ("MajestyHD.exe: {0} callback immediate at file offset 0x{1:X}" -f $status, $offset)
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

foreach ($offset in $CallbackImmediateOffsets) {
    Write-Bytes $bytes $offset $CustomQuestCallbackBytes
}

[IO.File]::WriteAllBytes($exePath, $bytes)

Write-Host ""
Write-Host "Done. Use Restore Original Custom Quest Button.bat to undo this experiment."
