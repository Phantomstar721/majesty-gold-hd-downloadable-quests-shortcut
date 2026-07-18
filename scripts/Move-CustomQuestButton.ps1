param(
    [string]$GamePath = "",
    [ValidateSet("RightOfFreestyle", "LeftOfFreestyle")]
    [string]$Placement = "RightOfFreestyle",
    [Nullable[int]]$X = $null,
    [Nullable[int]]$Y = $null,
    [int]$Width = 66,
    [int]$Height = 66,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$Magic = [byte[]](0x43, 0x59, 0x4C, 0x42, 0x50, 0x43, 0x20, 0x20, 0x01, 0x00, 0x01, 0x00)
$DefaultGamePath = "C:\Program Files (x86)\Steam\steamapps\common\Majesty HD"
$ElementSentinel = [uint32]::MaxValue

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

    $steamRoots = @()
    foreach ($key in @(
        "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
        "HKLM:\SOFTWARE\Valve\Steam",
        "HKCU:\SOFTWARE\Valve\Steam"
    )) {
        try {
            $installPath = (Get-ItemProperty -LiteralPath $key -ErrorAction Stop).InstallPath
            if ($installPath) {
                $steamRoots += $installPath
            }
        } catch {
        }
    }

    foreach ($root in $steamRoots | Select-Object -Unique) {
        $candidate = Join-Path $root "steamapps\common\Majesty HD"
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
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
    $directoryOffset = 20

    for ($sectionIndex = 0; $sectionIndex -lt $sectionCount; $sectionIndex++) {
        $dir = $directoryOffset + ($sectionIndex * 8)
        $extension = [Text.Encoding]::ASCII.GetString($Bytes, $dir, 4).TrimEnd()
        $sectionHeaderOffset = [int](Read-U32 $Bytes ($dir + 4))

        if ($extension -ne "SMNU") {
            continue
        }

        $entryCount = [int](Read-U32 $Bytes $sectionHeaderOffset)
        $entryHeaderOffset = $sectionHeaderOffset + 8

        for ($entryIndex = 0; $entryIndex -lt $entryCount; $entryIndex++) {
            $entry = $entryHeaderOffset + ($entryIndex * 28)
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

function Find-Element {
    param(
        [byte[]]$Bytes,
        [object]$Entry,
        [uint32]$TextId,
        [uint32]$ImageId
    )

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
        $hasText = Test-ElementHasTokenPair $Bytes ($absolute + 28) $next 33 $TextId
        if (-not $hasText) {
            $hasText = Test-ElementHasTokenPair $Bytes ($absolute + 28) $next 7 $TextId
        }
        $hasImage = Test-ElementHasTokenPair $Bytes ($absolute + 28) $next 6 $ImageId

        if ($hasText -and $hasImage) {
            return [pscustomobject]@{
                Offset = $absolute
                X = [int](Read-U32 $Bytes ($absolute + 12))
                Y = [int](Read-U32 $Bytes ($absolute + 16))
                Width = [int](Read-U32 $Bytes ($absolute + 20))
                Height = [int](Read-U32 $Bytes ($absolute + 24))
            }
        }
    }

    return $null
}

function Patch-UiDataFile {
    param(
        [string]$Path,
        [string]$BackupDir
    )

    [byte[]]$bytes = [IO.File]::ReadAllBytes($Path)
    $apdb = Find-ApdbSmnu $bytes
    if ($null -eq $apdb) {
        return [pscustomobject]@{ Status = "Skipped"; Reason = "No APdb quest menu in this resolution."; Path = $Path }
    }

    $custom = Find-Element $bytes $apdb 17 4034
    if ($null -eq $custom) {
        return [pscustomobject]@{ Status = "Skipped"; Reason = "Could not find the downloadable quest button record."; Path = $Path }
    }

    $freestyle = Find-Element $bytes $apdb 77 5000
    if ($null -eq $freestyle -and (-not $X.HasValue -or -not $Y.HasValue)) {
        return [pscustomobject]@{ Status = "Skipped"; Reason = "Could not find Freestyle button for automatic placement."; Path = $Path }
    }

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

    $result = [pscustomobject]@{
        Status = "Patched"
        Path = $Path
        OldRect = "$($custom.X),$($custom.Y),$($custom.Width),$($custom.Height)"
        NewRect = "$targetX,$targetY,$Width,$Height"
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

    Write-U32 $bytes ($custom.Offset + 12) ([uint32]$targetX)
    Write-U32 $bytes ($custom.Offset + 16) ([uint32]$targetY)
    Write-U32 $bytes ($custom.Offset + 20) ([uint32]$Width)
    Write-U32 $bytes ($custom.Offset + 24) ([uint32]$Height)
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

Write-Host "Majesty Gold HD Custom Quest Button mover"
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
        Write-Host ("{0}: {1} {2} -> {3}" -f $name, $item.Status, $item.OldRect, $item.NewRect)
    } else {
        Write-Host ("{0}: {1} ({2})" -f $name, $item.Status, $item.Reason)
    }
}

$changed = @($results | Where-Object { $_.Status -eq "Patched" -or $_.Status -eq "WouldPatch" }).Count
if ($changed -eq 0) {
    throw "No UIData files were patched."
}

Write-Host ""
if ($DryRun) {
    Write-Host "Dry run complete."
} else {
    Write-Host "Done. Original files are backed up in:"
    Write-Host $backupDir
}
