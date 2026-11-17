# S8 — manual checks (app-smoke)

Automated tests cover the effect model, rendering, undo and the accessibility strings (`[S8-AC18]`); these
checks need a person with the running app, VoiceOver and the keyboard. Tick each item when it has been verified.

- [ ] S8-AC18 The Backdrop section shows an "Effects" row with four glass buttons (Overlay, Adjust, Pattern,
      Vignette); each opens a popover, and a button is highlighted while its effect is on.
- [ ] S8-AC18 Each popover's Reset restores only that group; a slider drag is one undo step in Edit ▸ Undo.
- [ ] S8-AC18 The Auto block shows a six-colour palette strip from the content, five suggestion tiles and a
      Shuffle button; Shuffle gives new tiles and applies the first; ⌘Z brings the previous backdrop back.
- [ ] S8-AC18 VoiceOver reads "Blur, 12 pixels", "Pattern, Dots", "Overlay position, Above content",
      "Auto background 2 of 5" and the palette colours; Tab reaches every control; Esc closes a popover.
- [ ] S8-AC19 Visual: every pattern, vignette and overlay texture on the default, a gradient, a wallpaper and a
      photo backdrop in Light and Dark looks clean (no banding, no tiling seams, overlays read as soft light).
- [ ] S8-AC19 Export at 1× and 4K: the effects look the same, just sharper.
