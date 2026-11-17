# S4 — manual checks (app-smoke)

Automated tests cover the labels, arrow-key movement and Return-to-select logic (`[S4-AC20]`); these checks need
a person with VoiceOver and the keyboard. Tick each item when it has been verified in the running app.

- [ ] S4-AC20 VoiceOver reads the Canvas button ("Canvas size: Auto, 1128 by 728 pixels"), the search field, the
      W and H fields, each preset tile ("16:9 Widescreen, 1920 by 1080"), and the Format and Size pickers.
- [ ] S4-AC20 Keyboard only: open the size popover, type in search, press ↓ to reach the grid, move with the
      arrow keys (dashed ring shows the cursor), press Return to pick a size, press Esc to close the popover.
- [ ] S4-AC20 Export options popover: Tab reaches Format, Size, Copy and Export…; Esc closes it.
- [ ] Visual: the Canvas section, size popover and export options popover use the translucent glass look of
      the rest of the inspector, in Light and Dark.
