param(
    [string]$GamePath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$Magic = [byte[]](0x43, 0x59, 0x4C, 0x42, 0x50, 0x43, 0x20, 0x20, 0x01, 0x00, 0x01, 0x00)
$DefaultGamePath = "C:\Program Files (x86)\Steam\steamapps\common\Majesty HD"
$ElementSentinel = [uint32]::MaxValue
$INPq = [BitConverter]::ToUInt32([Text.Encoding]::ASCII.GetBytes("INPq"), 0)
$IX34 = [BitConverter]::ToUInt32([Text.Encoding]::ASCII.GetBytes("IX34"), 0)

function Read-U32 {
    param([byte[]]$Bytes, [int]$Offset)
    return [BitConverter]::ToUInt32($Bytes, $Offset)
}

function Write-U32 {
    param([byte[]]$Bytes, [int]$Offset, [uint32]$Value)
    [byte[]]$Raw = [BitConverter]::GetBytes($Value)
    [Array]::Copy($Raw, 0, $Bytes, $Offset, 4)
}

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

function Test-Magic {
    param([byte[]]$Bytes)
    if ($Bytes.Length -lt 20) {
        return $false
    }
    for ($i = 0; $i -lt $Magic.Length; $i++) {
        if ($Bytes[$i] -ne $Magic[$i]) {
            return $false
        }
    }
    return $true
}

function Find-ApdbSmnu {
    param([byte[]]$Bytes)

    if (-not (Test-Magic $Bytes)) {
        throw "Not a Majesty CAM/UIData archive."
    }

    $sectionCount = [int](Read-U32 $Bytes 12)
    for ($sectionIndex = 0; $sectionIndex -lt $sectionCount; $sectionIndex++) {
        $dir = 20 + ($sectionIndex * 8)
        $extension = [Text.Encoding]::ASCII.GetString($Bytes, $dir, 4).TrimEnd()
        $sectionHeaderOffset = [int](Read-U32 $Bytes ($dir + 4))
        if ($extension -ne "SMNU") {
            continue
        }

        $entryCount = [int](Read-U32 $Bytes $sectionHeaderOffset)
        for ($entryIndex = 0; $entryIndex -lt $entryCount; $entryIndex++) {
            $entry = $sectionHeaderOffset + 8 + ($entryIndex * 28)
            $name = [Text.Encoding]::ASCII.GetString($Bytes, $entry, 20).TrimEnd([char]0)
            if ($name -eq "APdb") {
                return [pscustomobject]@{
                    Offset = [int](Read-U32 $Bytes ($entry + 20))
                    Size = [int](Read-U32 $Bytes ($entry + 24))
                }
            }
        }
    }

    return $null
}

function Get-NextElementOffset {
    param([byte[]]$Bytes, [int]$EntryOffset, [int]$EntryEnd, [int]$RelativeStart)

    for ($relative = $RelativeStart + 4; $relative -le ($EntryEnd - $EntryOffset - 12); $relative += 4) {
        $absolute = $EntryOffset + $relative
        if (
            (Read-U32 $Bytes $absolute) -eq $ElementSentinel -and
            (Read-U32 $Bytes ($absolute + 4)) -eq 0 -and
            (Read-U32 $Bytes ($absolute + 8)) -eq 2
        ) {
            return $absolute
        }
    }
    return $EntryEnd
}

function Find-FreestyleIconRecord {
    param([byte[]]$Bytes, [object]$Entry)

    $entryOffset = $Entry.Offset
    $entryEnd = $Entry.Offset + $Entry.Size

    for ($relative = 0; $relative -le ($Entry.Size - 28); $relative += 4) {
        $absolute = $entryOffset + $relative
        if (
            (Read-U32 $Bytes $absolute) -ne $ElementSentinel -or
            (Read-U32 $Bytes ($absolute + 4)) -ne 0 -or
            (Read-U32 $Bytes ($absolute + 8)) -ne 2
        ) {
            continue
        }

        $next = Get-NextElementOffset $Bytes $entryOffset $entryEnd $relative
        $textValueOffset = $null
        $imageGroupOffset = $null
        $frameIdOffset = $null
        $objectIdOffset = $null
        $hasFixedOpcode = $false

        for ($offset = $absolute + 28; $offset -le ($next - 8); $offset += 4) {
            $token = Read-U32 $Bytes $offset
            $value = Read-U32 $Bytes ($offset + 4)
            if ($token -eq 33 -and $value -eq 77) {
                $textValueOffset = $offset + 4
            }
            if ($token -eq 12 -and $value -eq $INPq) {
                $imageGroupOffset = $offset + 4
            }
            if ($token -eq 13 -and $value -eq 1039) {
                $frameIdOffset = $offset + 4
            }
            if ($token -eq 43 -and $value -eq 1) {
                $hasFixedOpcode = $true
            }
            if ($token -eq 6 -and $value -eq 5000) {
                $objectIdOffset = $offset + 4
            }
        }

        if (
            $null -ne $textValueOffset -and
            $null -ne $imageGroupOffset -and
            $null -ne $frameIdOffset -and
            $null -ne $objectIdOffset -and
            $hasFixedOpcode
        ) {
            return [pscustomobject]@{
                ElementOffset = $absolute
                TextValueOffset = $textValueOffset
                ImageGroupOffset = $imageGroupOffset
                FrameIdOffset = $frameIdOffset
                ObjectIdOffset = $objectIdOffset
                Rect = "{0},{1},{2},{3}" -f (Read-U32 $Bytes ($absolute + 12)), (Read-U32 $Bytes ($absolute + 16)), (Read-U32 $Bytes ($absolute + 20)), (Read-U32 $Bytes ($absolute + 24))
            }
        }
    }

    return $null
}

function Assert-FilesWritable {
    param([object[]]$Files)

    foreach ($file in $Files) {
        $stream = $null
        try {
            $stream = [IO.File]::Open($file.FullName, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        } catch {
            throw "Cannot patch $($file.Name) because it is in use or not writable. Close Majesty Gold HD and run this experiment again. If the game is closed, right-click the BAT and choose Run as administrator."
        } finally {
            if ($null -ne $stream) {
                $stream.Dispose()
            }
        }
    }
}

function Patch-UiDataFile {
    param([string]$Path, [string]$BackupDir)

    [byte[]]$bytes = [IO.File]::ReadAllBytes($Path)
    $apdb = Find-ApdbSmnu $bytes
    if ($null -eq $apdb) {
        return [pscustomobject]@{ Status = "Skipped"; Reason = "No APdb quest menu in this resolution."; Path = $Path }
    }

    $icon = Find-FreestyleIconRecord $bytes $apdb
    if ($null -eq $icon) {
        return [pscustomobject]@{ Status = "Skipped"; Reason = "Could not find the stock fixed Freestyle icon record."; Path = $Path }
    }

    $result = [pscustomobject]@{
        Status = "Patched"
        Path = $Path
        Rect = $icon.Rect
        Offset = ("0x{0:X}" -f ($icon.ElementOffset - $apdb.Offset))
    }

    if ($DryRun) {
        $result.Status = "WouldPatch"
        return $result
    }

    if (-not (Test-Path -LiteralPath $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir | Out-Null
    }

    $backupPath = Join-Path $BackupDir ((Split-Path -Leaf $Path) + ".original")
    if (-not (Test-Path -LiteralPath $backupPath)) {
        Copy-Item -LiteralPath $Path -Destination $backupPath
    }

    Write-U32 $bytes $icon.TextValueOffset 17
    Write-U32 $bytes $icon.ImageGroupOffset $IX34
    Write-U32 $bytes $icon.FrameIdOffset 1005
    Write-U32 $bytes $icon.ObjectIdOffset 4034
    [IO.File]::WriteAllBytes($Path, $bytes)

    return $result
}

$resolvedGamePath = Get-MajestyPath $GamePath
$dataPath = Join-Path $resolvedGamePath "Data"
if (-not (Test-Path -LiteralPath $dataPath)) {
    throw "Could not find Data folder at $dataPath."
}

$backupDir = Join-Path $dataPath "_custom_quest_button_originals"
$uiFiles = Get-ChildItem -LiteralPath $dataPath -Filter "UIData_*.dat" | Sort-Object Name
if ($uiFiles.Count -eq 0) {
    throw "No UIData_*.dat files found in $dataPath."
}
if (-not $DryRun) {
    Assert-FilesWritable $uiFiles
}

Write-Host "Majesty Gold HD experiment: Freestyle icon becomes Custom Quests"
Write-Host "Game path: $resolvedGamePath"
if ($DryRun) {
    Write-Host "Dry run: no files will be changed."
}
Write-Host ""

$results = foreach ($file in $uiFiles) {
    Patch-UiDataFile $file.FullName $backupDir
}

foreach ($item in $results) {
    $name = Split-Path -Leaf $item.Path
    if ($item.Status -eq "Patched" -or $item.Status -eq "WouldPatch") {
        Write-Host ("{0}: {1} fixed Freestyle icon -> custom object 4034 at {2} rect={3}" -f $name, $item.Status, $item.Offset, $item.Rect)
    } else {
        Write-Host ("{0}: {1} ({2})" -f $name, $item.Status, $item.Reason)
    }
}

Write-Host ""
if ($DryRun) {
    Write-Host "Dry run complete."
} else {
    Write-Host "Done. Use Restore Original Custom Quest Button.bat to undo this experiment."
}
