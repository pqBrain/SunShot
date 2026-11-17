# S1 — manual checks

Tick a box (`- [x]`) once verified in the real app (`make run`). S1 can only be marked `Done` when
every manual AC below is ticked (enforced by the gate).

- [ ] S1-AC4 — Drag a PNG from Finder onto the window: it imports. Drag a PDF: refused. Drag 3 images:
      only the first imports and "Only one image is supported for now" appears.

## Exploratory (not gated, but please look)
- [ ] Empty state looks right in Light and Dark (System Settings ▸ Appearance).
- [ ] ⌘O, ⌘V (after copying a screenshot with ⌃⇧⌘4), ⇧⌘E, ⌘C, ⌘Z / ⇧⌘Z, ⌘⌫ all work from the keyboard.
- [ ] Edit menu shows "Undo Import Image" / "Undo Replace Image" / "Undo Clear Content".
- [ ] Tab reaches Choose Image… on the empty state; VoiceOver (⌘F5) reads the preview size.
