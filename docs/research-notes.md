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

The bottom Freestyle button is identified by:

- text token `33, 77`, where text ID `77` is `Freestyle Game`
- image token `6, 5000`

This project computes the custom button placement relative to the Freestyle button,
so it can patch all supported UIData resolutions with the same logic.
