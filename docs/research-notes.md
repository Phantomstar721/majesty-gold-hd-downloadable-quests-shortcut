# Research Notes

Majesty Gold HD stores quest-select UI records in the `APdb` entry inside
`UIData_*.dat`.

The relevant archive entry is:

- section: `SMNU`
- entry: `APdb`

`APdb.SMNU` contains 32-bit little-endian record streams. UI element records observed
so far start with:

```text
FF FF FF FF  00 00 00 00  02 00 00 00  x  y  width  height
```

The custom/downloadable quest button is identified by both:

- text token `33, 17`, where text ID `17` is `Load Downloadable Quest (hidden until available)`
- image token `6, 4034`, using the `IX34q download btn` image set from `DataMX\mx_interfacedata.cam`

The stock rectangle is hard-coded at `70,131,10,10` in every newer UIData file checked.
When only this rectangle is changed, the button moves visually and remains clickable,
but it still belongs to the panning map layer.

Moving the whole 112-byte button record so it sits immediately before the Freestyle
button record is file-format safe, but in-game testing showed it still behaves like a
map-layer button.

Do not rewrite the trailing opcode block from the map-marker pattern:

```text
3,2, 3,201326592, 6,4034, 36,3, color, color, color
```

to the attempted fixed-overlay-style pattern:

```text
3,2, 3,128, 43,1, 6,4034, 38,0, 0
```

This keeps text/action ID `17` and image ID `4034` intact.

That experiment crashed the quest map with `Unknown opcode in CYDialog Stream`, so the
classification is not a simple style-tail swap.

Next diagnostic: change only the existing fixed Freestyle button's `33,77` token to
`33,17`, leaving its opcode shape and sprite intact. If the button opens Custom Quests,
then action ID `17` can run from a fixed overlay record and the real solution should
duplicate a fixed overlay control record rather than convert the original map marker.

The circular Freestyle icon record may not be the actual clicked surface. A follow-up
diagnostic changed the wider `FREESTYLE QUESTS` label/button record from token `82` to
`17`; in-game, this changed the visible bottom text to `Load Downloadable`, but the
button still launched Freestyle and the top hover still showed `Freestyle Game`.

Next diagnostic changes the wider label record's `5,70` pair to `5,76` as well. These
values line up with ASCII hotkeys/actions (`F` to `L`) across other menu records.

In-game testing showed the wider label text could be changed to `Load Downloadable`, but
the click still launched Freestyle. The `5,70 -> 76` change also did not affect the
click dispatch, so the label text/action-looking fields are cosmetic or secondary.

Executable inspection found hardcoded APdb handling near `MajestyHD.exe` file offsets
`0x787D0`, `0x79870`, and `0x7A0EE`. The click path compares a selected object/image ID
against values including:

- `0x0FC2` / `4034`: downloadable/custom quest button
- `0x1388` / `5000`: Freestyle icon
- `0x138A` / `5002`: Erase Victories

This suggests the fixed-overlay experiment should change a known fixed control's object
ID to `4034`, while preserving a valid fixed-control opcode shape.

The follow-up fixed-label diagnostic changes the wider bottom Freestyle label's `6,5900`
token to `6,4034`, because `5900` appears in the APdb setup path alongside `5000`.
In-game testing showed this made the bottom label render incorrectly/blank while still
launching Freestyle. That means the `6,5900` token affects the visual object, but not
the click dispatch.

Current conclusion: APdb UIData can move or relabel these controls, but the fixed
bottom Freestyle action is not redirected by changing the obvious text, hotkey, image,
or object tokens. A true fixed-overlay Custom Quests button probably requires an
executable patch, a callback registration change, or finding a different UIData opcode
that safely selects the fixed layer without changing the callback.

Executable callback diagnostic:

- file offset `0x798B6`: callback immediate for object ID `5000`
- file offset `0x798CE`: callback immediate for object ID `5900`
- original bytes: `00 93 47 00`, runtime callback `0x479300` / Freestyle
- diagnostic bytes: `00 92 47 00`, runtime callback `0x479200` / Custom Quests

This leaves UIData stock and tests whether the fixed bottom controls can launch Custom
Quests when the executable callback registration is changed directly.

In-game testing showed the callback diagnostic changed the hover text and top-left
preview image to Downloadable Quests, but clicking the bottom Freestyle button still
opened the Freestyle menu. Therefore the hover callback registration and click
dispatcher are separate.

Click dispatcher diagnostic:

- file offset `0x7A0FE`: immediate in `cmp ebx, 0x0FC2`
- original bytes: `C2 0F 00 00`, checking Custom Quest object `4034`
- diagnostic bytes: `88 13 00 00`, checking Freestyle object `5000`

This reuses the existing Custom Quests click branch for the fixed Freestyle object. It
temporarily steals the Freestyle click path and may stop the original map-layer Custom
Quest marker from clicking during the experiment.

In-game testing showed that the circular Freestyle icon opened Downloadable Quests after
the click dispatcher patch, while the text label still opened Freestyle. This proves the
fixed icon and bottom text label are separate hit targets.

Next final-shape diagnostic: clone the fixed Freestyle icon record, convert only the
clone to `4034`, and insert it immediately after the original fixed icon record. If the
stock executable accepts a fixed-layer `4034` clone, this should preserve Freestyle and
add a separate fixed Downloadable Quests button without EXE patching.

In-game testing showed the clone-only experiment did not produce a visible new button.
The most likely cause is duplicate object ID collision: the stock panning-map
Downloadable Quests record still owns object `4034`, so the fixed duplicate is ignored
or overwritten. The next diagnostic removes the original map-layer `4034` record before
inserting the fixed clone.

The replace-map-button experiment made the button visible and clickable beside
Freestyle, but it still panned with the quest map. This means object ID `4034` appears
to carry map-layer behavior even when the record is cloned from a fixed Freestyle icon
and retains fixed opcode `43,1`.

Next diagnostic: use fixed clone object ID `5901` instead of `4034`, remove the original
map-layer `4034` record, and patch the click dispatcher compare at file offset `0x7A0FE`
from `4034` to `5901`.

In-game testing showed the original map button disappeared, but the new `5901` fixed
clone did not appear. That means APdb records are not enough on their own: object IDs
must also be registered by executable setup code before they render/click.

The registered unique diagnostic patches all known APdb setup references from `4034` to
`5901`:

- `0x798EF`: visibility/enable setup branch
- `0x798FA`: visibility/enable setup branch
- `0x79904`: lookup/configure object
- `0x7994A`: callback registration
- `0x7A0FE`: click dispatcher compare

In-game testing showed this made the `5901` button appear, but it still panned with the
map and clicking did nothing. The missing fixed-layer behavior appears to be the
hardcoded fixed reposition table at VA `0x7B54C8` / file `0x3B42C8`.

The first fixed table entry is object `110`, which does not appear as an APdb UI image
record. The next diagnostic retargets that unused-looking slot from `110` to `5901` so
the new button is included in fixed repositioning without stealing visible UI art.

In-game testing showed the `110 -> 5901` table retarget made the button fixed, but it
appeared at the upper-left and absorbed a huge click area. Slot `110` appears to have
bad/default runtime geometry for this purpose.

Next diagnostic: reuse an existing fixed-table UI furniture ID with sane geometry.
Object `8506` is the bottom-center decorative panel around Freestyle. Temporarily remove
the original `8506` APdb record, insert the custom fixed clone as `8506`, and patch
Custom Quest executable references from `4034` to `8506`.

In-game testing showed the `8506` experiment rendered the button near the bottom, but
the bottom-center decoration was obviously missing. After panning, the button vanished
until leaving/re-entering the screen. It was clickable in the sense of hit testing, but
still did not open Downloadable Quests. This suggests fixed-table membership alone is
not enough; some IDs carry runtime lifecycle/geometry assumptions from their original
role.

Known working route: object `5000`, the fixed circular Freestyle icon, can be routed to
Downloadable Quests when the `4034` click compare is changed to `5000`. In-game testing
showed the separate bottom Freestyle text label still opens Freestyle. A fallback design
can therefore split the original Freestyle affordance: circular icon = Downloadable
Quests, text label = Freestyle.

The first split fallback also tried to change the fixed icon art/text to the
Downloadable Quest art and move it beside Freestyle. In-game testing showed the icon
became transparent/click-through. The safer fallback keeps the Freestyle icon record at
its stock rectangle/art and only patches executable routing. The original panning map
button can still be removed from UIData so there is no dead Downloadable Quest marker on
the map.

The bottom Freestyle button is identified by:

- text token `33, 77`, where text ID `77` is `Freestyle Game`
- image token `6, 5000`

This project computes the custom button placement relative to the Freestyle button,
so it can patch all supported UIData resolutions with the same logic.
