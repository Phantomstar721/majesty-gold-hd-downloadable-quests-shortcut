# Majesty Gold HD - Move Custom Quest Button

This tiny Windows helper experiments with moving the Custom/Downloadable Quest button
on Majesty Gold HD's quest selection map down beside the permanent bottom controls.

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
relocates that record near the bottom-control block, and moves it beside the Freestyle
quest button.

Current limitation: in-game testing showed that this still behaves like a map-layer
button when the quest map pans. A later opcode/style rewrite experiment crashed the
quest map, so that unsafe change is not included.

## Experiments

`Experiment - Freestyle Opens Custom Quests.bat` temporarily changes the fixed
Freestyle button's action/text token from `77` to `17`. This is a diagnostic test:
if the fixed Freestyle button opens Custom Quests, then the next proper patch can be
built by duplicating a known fixed overlay button instead of mutating the map marker.

`Experiment - Freestyle Label Opens Custom Quests.bat` targets the wider bottom
`FREESTYLE QUESTS` label/button record instead, changing visible text token `82` to
`17` and the likely action/hotkey token `70` to `76`.

`Experiment - Freestyle Icon Becomes Custom Quests.bat` targets the fixed circular
Freestyle icon and changes its text/image/object IDs to the downloadable quest button.
Executable inspection shows the click dispatcher branches on object ID `4034`, so this
is the strongest fixed-overlay diagnostic so far.

`Experiment - Freestyle Label Object Becomes Custom Quests.bat` targets the wider
bottom `FREESTYLE QUESTS` label/button record and changes its object/image ID from
`5900` to `4034`. This tests whether the lower text strip is the click surface that
dispatches Freestyle.

`Experiment - Freestyle Callback Opens Custom Quests.bat` patches `MajestyHD.exe` so
the fixed Freestyle icon and label object IDs call the Custom Quests callback instead
of the Freestyle callback. This is a stronger diagnostic than the UIData-only tests and
backs up the original EXE before changing anything.

`Experiment - Freestyle Fully Becomes Custom Quests.bat` patches both the Freestyle
hover callback and the click dispatcher. This temporarily replaces Freestyle with
Custom Quests, and is only meant to prove the executable-side path.

`Experiment - Clone Fixed Custom Quest Button.bat` duplicates the fixed Freestyle icon
record, converts the duplicate to object `4034`, and places it beside Freestyle. This
tests the intended final shape: Freestyle stays intact and Downloadable Quests gets its
own fixed-layer button.

`Experiment - Replace Map Button With Fixed Clone.bat` does the same fixed clone, but
also removes the original panning-map `4034` record first. This avoids duplicate object
ID collision and is the more likely final implementation path.

`Experiment - Fixed Unique Custom Quest Button.bat` removes the original panning-map
button, inserts a fixed clone with object ID `5901`, and patches the EXE click
dispatcher/setup references so `5901` is registered and opens Custom Quests. It also
retargets an apparently unused fixed-position table slot from `110` to `5901`, so the
button should be counter-moved with the fixed overlay during map panning.

`Experiment - Reuse Fixed Furniture Slot.bat` temporarily reuses existing fixed-table
object ID `8506` for the custom button. It removes the old `8506` decorative record,
then inserts the fixed custom clone as `8506` and redirects Custom Quest EXE references
to that ID.

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
