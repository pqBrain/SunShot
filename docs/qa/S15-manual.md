# S15 — manual checks

Automated tests cover the layout catalog, geometry, slot rendering, undo, document round-trip, preview/export
parity and paste/capture growth (`[S15-AC1]`–`[S15-AC10]`); these checks need a person in the running app
(`make run`). Tick each item when it has been verified. S15 can only be marked `Done` when every manual AC below
is ticked (enforced by the gate).

- [ ] S15-AC9 With an image open, the inspector shows a Screenshots section; its layout picker offers None plus
      every screenshot layout (Side by Side, Row of Three, Grid, Overlap, Cascade, Fan…). Choosing one adds
      rows Main, 2, 3… each with a thumbnail; empty rows are dimmed and show the main image.
- [ ] S15-AC9 A non-main row's Choose… opens a panel and the picked image appears in that slot on the canvas;
      dropping an image file onto a non-main row does the same; dropping onto Main is refused.
- [ ] S15-AC9 A non-main row with an image offers Remove; the slot falls back to the main image. ⌘Z / ⇧⌘Z
      undo and redo "Set Screenshot", "Remove Screenshot" and "Change Screenshot Layout".
- [ ] S15-AC9 Choosing a device (S12) disables the layout picker and lists one row per device of the
      arrangement (Pair, Trio); removing the device enables the picker again and slot images are still there.

## Exploratory (not gated, but please look)
- [ ] ⌘V with an image open adds it as the next screenshot and the notice reads e.g. "Added as screenshot 2 ·
      Side by Side"; once Grid is full the notice says all screenshots are filled.
- [ ] Save, close and reopen a `.sunshot` document with slot images: the slots come back.
- [ ] VoiceOver reads each row (name and whether it has its own image); the section looks right in Light and
      Dark.
