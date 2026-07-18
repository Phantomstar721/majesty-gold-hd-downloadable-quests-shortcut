# Majesty Gold HD - Move Custom Quest Button

This tiny Windows helper moves the Custom/Downloadable Quest button on Majesty Gold
HD's quest selection map down beside the permanent bottom controls.

The normal game places that button on the map itself, which means you often have to
pan around just to reach downloaded or Workshop quests. This patch changes the
quest-selection UI data files directly and makes a backup before editing anything.

## Use It

1. Close Majesty Gold HD.
2. Download this folder or the release ZIP.
3. Double-click `Install - Move Custom Quest Button.bat`.
4. Start Majesty Gold HD and open the quest selection screen.

To undo the change, double-click `Restore Original Custom Quest Button.bat`.

If Windows blocks the install because Majesty is under `Program Files`, right-click the
install BAT and choose **Run as administrator**.

The installer skips the older `800x600` and `1024x768` UIData files because those files
do not contain the same Custom Quest menu record.

## What It Changes

The installer patches `Data\UIData_*.dat` inside your Majesty Gold HD install. It looks
for the quest-select menu record named `APdb`, finds the downloadable quest button,
and moves it beside the Freestyle quest button.

Original files are backed up here:

```text
Majesty HD\Data\_custom_quest_button_originals
```

## Advanced Placement

From PowerShell, you can preview or choose a different placement:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\Move-CustomQuestButton.ps1 -DryRun
powershell.exe -ExecutionPolicy Bypass -File .\scripts\Move-CustomQuestButton.ps1 -Placement LeftOfFreestyle
powershell.exe -ExecutionPolicy Bypass -File .\scripts\Move-CustomQuestButton.ps1 -X 760 -Y 934 -Width 66 -Height 66
```

## Notes

This is not a Steam Workshop mod. Majesty loads Workshop mods after the game is already
running, but this UIData file is loaded from the base install before that mod selection
flow is useful. For now, a small local patcher is the practical route.

Tested first against the `1680x1050` UI layout. The patcher also scans and patches the
other newer UIData layouts that contain the same quest-selection menu.
