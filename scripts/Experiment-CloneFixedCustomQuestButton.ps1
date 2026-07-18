param(
    [string]$GamePath = "",
    [ValidateSet("RightOfFreestyle", "LeftOfFreestyle")]
    [string]$Placement = "RightOfFreestyle",
    [Nullable[int]]$X = $null,
    [Nullable[int]]$Y = $null,
    [int]$Width = 66,
    [int]$Height = 66,
    [switch]$HideMapButton,
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

function Get-CamEntries {
    param([byte[]]$Bytes)

    if (-not (Test-Magic $Bytes)) {
        throw "Not a Majesty CAM/UIData archive."
    }

    $sectionCount = [int](Read-U32 $Bytes 12)
    $entries = @()

    for ($sectionIndex = 0; $sectionIndex -lt $sectionCount; $sectionIndex++) {
        $dir = 20 + ($sectionIndex * 8)
        $extension = [Text.Encoding]::ASCII.GetString($Bytes, $dir, 4).TrimEnd()
        $sectionHeaderOffset = [int](Read-U32 $Bytes ($dir + 4))
        $entryCount = [int](Read-U32 $Bytes $sectionHeaderOffset)

        for ($entryIndex = 0; $entryIndex -lt $entryCount; $entryIndex++) {
            $entryHeader = $sectionHeaderOffset + 8 + ($entryIndex * 28)
            $name = [Text.Encoding]::ASCII.GetString($Bytes, $entryHeader, 20).TrimEnd([char]0)
            $entries += [pscustomobject]@{
                Extension = $extension
                Name = $name
                DataOffset = [int](Read-U32 $Bytes ($entryHeader + 20))
                DataSize = [int](Read-U32 $Bytes ($entryHeader + 24))
                DataOffsetField = $entryHeader + 20
                DataSizeField = $entryHeader + 24
            }
        }
    }

    return $entries
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

function Test-ElementHasTokenPair {
    param(
        [byte[]]$Bytes,
        [int]$Start,
        [int]$End,
        [uint32]$Token,
        [uint32]$Value
    )

    for ($offset = $Start; $offset -le ($End - 8); $offset += 4) {
        if ((Read-U32 $Bytes $offset) -eq $Token -and (Read-U32 $Bytes ($offset + 4)) -eq $Value) {
            return $true
        }
    }
    return $false
}

function Find-Element {
    param(
        [byte[]]$Bytes,
        [object]$Entry,
        [uint32]$TextId,
        [uint32]$ImageId,
        [switch]$RequireFixed
    )

    $entryOffset = $Entry.DataOffset
    $entryEnd = $Entry.DataOffset + $Entry.DataSize

    for ($relative = 0; $relative -le ($Entry.DataSize - 28); $relative += 4) {
        $absolute = $entryOffset + $relative
        if (
            (Read-U32 $Bytes $absolute) -ne $ElementSentinel -or
            (Read-U32 $Bytes ($absolute + 4)) -ne 0 -or
            (Read-U32 $Bytes ($absolute + 8)) -ne 2
        ) {
            continue
        }

        $next = Get-NextElementOffset $Bytes $entryOffset $entryEnd $relative
        $hasText = Test-ElementHasTokenPair $Bytes ($absolute + 28) $next 33 $TextId
        if (-not $hasText) {
            $hasText = Test-ElementHasTokenPair $Bytes ($absolute + 28) $next 7 $TextId
        }
        $hasImage = Test-ElementHasTokenPair $Bytes ($absolute + 28) $next 6 $ImageId
        $hasFixed = Test-ElementHasTokenPair $Bytes ($absolute + 28) $next 43 1

        if ($hasText -and $hasImage -and ((-not $RequireFixed) -or $hasFixed)) {
            return [pscustomobject]@{
                Offset = $absolute
                EndOffset = $next
                X = [int](Read-U32 $Bytes ($absolute + 12))
                Y = [int](Read-U32 $Bytes ($absolute + 16))
                Width = [int](Read-U32 $Bytes ($absolute + 20))
                Height = [int](Read-U32 $Bytes ($absolute + 24))
            }
        }
    }

    return $null
}

function Insert-Bytes {
    param([byte[]]$Bytes, [int]$Offset, [byte[]]$Chunk)

    [byte[]]$result = New-Object byte[] ($Bytes.Length + $Chunk.Length)
    [Array]::Copy($Bytes, 0, $result, 0, $Offset)
    [Array]::Copy($Chunk, 0, $result, $Offset, $Chunk.Length)
    [Array]::Copy($Bytes, $Offset, $result, $Offset + $Chunk.Length, $Bytes.Length - $Offset)
    return $result
}

function Copy-Range {
    param([byte[]]$Bytes, [int]$Start, [int]$Length)

    [byte[]]$result = New-Object byte[] $Length
    [Array]::Copy($Bytes, $Start, $result, 0, $Length)
    return $result
}

function Convert-FreestyleIconToCustomClone {
    param(
        [byte[]]$Record,
        [int]$TargetX,
        [int]$TargetY,
        [int]$TargetWidth,
        [int]$TargetHeight
    )

    [byte[]]$clone = Copy-Range $Record 0 $Record.Length
    Write-U32 $clone 12 ([uint32]$TargetX)
    Write-U32 $clone 16 ([uint32]$TargetY)
    Write-U32 $clone 20 ([uint32]$TargetWidth)
    Write-U32 $clone 24 ([uint32]$TargetHeight)

    for ($offset = 28; $offset -le ($clone.Length - 8); $offset += 4) {
        $token = Read-U32 $clone $offset
        $value = Read-U32 $clone ($offset + 4)
        if ($token -eq 33 -and $value -eq 77) {
            Write-U32 $clone ($offset + 4) 17
        }
        if ($token -eq 12 -and $value -eq $INPq) {
            Write-U32 $clone ($offset + 4) $IX34
        }
        if ($token -eq 13 -and $value -eq 1039) {
            Write-U32 $clone ($offset + 4) 1005
        }
        if ($token -eq 6 -and $value -eq 5000) {
            Write-U32 $clone ($offset + 4) 4034
        }
    }

    return $clone
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
    $entries = Get-CamEntries $bytes
    $apdb = @($entries | Where-Object { $_.Extension -eq "SMNU" -and $_.Name -eq "APdb" } | Select-Object -First 1)[0]
    if ($null -eq $apdb) {
        return [pscustomobject]@{ Status = "Skipped"; Reason = "No APdb quest menu in this resolution."; Path = $Path }
    }

    $freestyle = Find-Element $bytes $apdb 77 5000 -RequireFixed
    if ($null -eq $freestyle) {
        return [pscustomobject]@{ Status = "Skipped"; Reason = "Could not find the fixed Freestyle icon record."; Path = $Path }
    }

    $existingClone = Find-Element $bytes $apdb 17 4034 -RequireFixed
    if ($null -ne $existingClone) {
        return [pscustomobject]@{
            Status = "AlreadyPatched"
            Path = $Path
            NewRect = "$($existingClone.X),$($existingClone.Y),$($existingClone.Width),$($existingClone.Height)"
            InsertOffset = ("0x{0:X}" -f ($existingClone.Offset - $apdb.DataOffset))
        }
    }

    $mapButton = Find-Element $bytes $apdb 17 4034

    $targetX = 0
    $targetY = 0
    if ($X.HasValue) {
        $targetX = $X.Value
    } elseif ($Placement -eq "LeftOfFreestyle") {
        $targetX = $freestyle.X - $Width - 13
    } else {
        $targetX = $freestyle.X + $freestyle.Width + 13
    }

    if ($Y.HasValue) {
        $targetY = $Y.Value
    } else {
        $targetY = $freestyle.Y + [int][Math]::Round(($freestyle.Height - $Height) / 2)
    }

    $insertOffset = $freestyle.EndOffset
    $recordLength = $freestyle.EndOffset - $freestyle.Offset
    [byte[]]$freestyleRecord = Copy-Range $bytes $freestyle.Offset $recordLength
    [byte[]]$cloneRecord = Convert-FreestyleIconToCustomClone $freestyleRecord $targetX $targetY $Width $Height

    $result = [pscustomobject]@{
        Status = "Patched"
        Path = $Path
        NewRect = "$targetX,$targetY,$Width,$Height"
        InsertOffset = ("0x{0:X}" -f ($insertOffset - $apdb.DataOffset))
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

    [byte[]]$newBytes = Insert-Bytes $bytes $insertOffset $cloneRecord
    $delta = $cloneRecord.Length
    foreach ($entry in $entries) {
        if ($entry.DataOffset -gt $insertOffset) {
            Write-U32 $newBytes $entry.DataOffsetField ([uint32]($entry.DataOffset + $delta))
        }
    }
    Write-U32 $newBytes $apdb.DataSizeField ([uint32]($apdb.DataSize + $delta))

    if ($HideMapButton -and $null -ne $mapButton) {
        Write-U32 $newBytes ($mapButton.Offset + 20) 1
        Write-U32 $newBytes ($mapButton.Offset + 24) 1
    }

    [IO.File]::WriteAllBytes($Path, $newBytes)
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

Write-Host "Majesty Gold HD experiment: Clone fixed Custom Quest button"
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
    if ($item.Status -eq "Patched" -or $item.Status -eq "WouldPatch" -or $item.Status -eq "AlreadyPatched") {
        Write-Host ("{0}: {1} fixed custom button at {2} rect={3}" -f $name, $item.Status, $item.InsertOffset, $item.NewRect)
    } else {
        Write-Host ("{0}: {1} ({2})" -f $name, $item.Status, $item.Reason)
    }
}

$changed = @($results | Where-Object { $_.Status -eq "Patched" -or $_.Status -eq "WouldPatch" -or $_.Status -eq "AlreadyPatched" }).Count
if ($changed -eq 0) {
    throw "No UIData files were patched."
}

Write-Host ""
if ($DryRun) {
    Write-Host "Dry run complete."
} else {
    Write-Host "Done. Use Restore Original Custom Quest Button.bat to undo this experiment."
}
