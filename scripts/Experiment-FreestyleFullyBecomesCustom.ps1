param(
    [string]$GamePath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$DefaultGamePath = "C:\Program Files (x86)\Steam\steamapps\common\Majesty HD"
$FreestyleCallbackBytes = [byte[]](0x00, 0x93, 0x47, 0x00)
$CustomQuestCallbackBytes = [byte[]](0x00, 0x92, 0x47, 0x00)
$CustomQuestObjectBytes = [byte[]](0xC2, 0x0F, 0x00, 0x00)
$FreestyleObjectBytes = [byte[]](0x88, 0x13, 0x00, 0x00)

# File offsets inside the current Steam MajestyHD.exe build.
$CallbackImmediateOffsets = @(0x798B6, 0x798CE)
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

function Assert-ExpectedBytes {
    param(
        [byte[]]$Bytes,
        [int]$Offset,
        [byte[]]$Original,
        [byte[]]$Patched,
        [string]$Description
    )

    $isOriginal = Test-BytesEqual $Bytes $Offset $Original
    $isPatched = Test-BytesEqual $Bytes $Offset $Patched
    if (-not $isOriginal -and -not $isPatched) {
        $found = [BitConverter]::ToString($Bytes, $Offset, 4)
        throw ("MajestyHD.exe does not match the expected Steam build at file offset 0x{0:X} for {1}. Found {2}." -f $Offset, $Description, $found)
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
    Assert-ExpectedBytes $bytes $offset $FreestyleCallbackBytes $CustomQuestCallbackBytes "Freestyle callback registration"
}
Assert-ExpectedBytes $bytes $CustomQuestCompareImmediateOffset $CustomQuestObjectBytes $FreestyleObjectBytes "Custom Quest click dispatcher compare"

Write-Host "Majesty Gold HD experiment: Freestyle fully becomes Custom Quests"
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
    Write-Host ("MajestyHD.exe: {0} Freestyle hover callback at file offset 0x{1:X}" -f $status, $offset)
}

$clickStatus = if (Test-BytesEqual $bytes $CustomQuestCompareImmediateOffset $FreestyleObjectBytes) { "AlreadyPatched" } else { "WouldPatch" }
if (-not $DryRun -and $clickStatus -eq "WouldPatch") {
    $clickStatus = "Patched"
}
Write-Host ("MajestyHD.exe: {0} Freestyle click dispatcher at file offset 0x{1:X}" -f $clickStatus, $CustomQuestCompareImmediateOffset)

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
Write-Bytes $bytes $CustomQuestCompareImmediateOffset $FreestyleObjectBytes

[IO.File]::WriteAllBytes($exePath, $bytes)

Write-Host ""
Write-Host "Done. This temporarily replaces Freestyle with Custom Quests. Use Restore Original Custom Quest Button.bat to undo it."
