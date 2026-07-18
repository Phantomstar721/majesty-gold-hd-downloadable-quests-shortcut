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

The bottom Freestyle button is identified by:

- text token `33, 77`, where text ID `77` is `Freestyle Game`
- image token `6, 5000`

This project computes the custom button placement relative to the Freestyle button,
so it can patch all supported UIData resolutions with the same logic.
