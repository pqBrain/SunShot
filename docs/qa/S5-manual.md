# S5 — manual checks (app-smoke)

Automated tests cover the title-edit model (live update, one "Edit Frame Title" entry on Return, Esc restores,
120-character limit, newlines → spaces: `[S5-AC9]`, `[S5-AC10]`) and the VoiceOver strings (`[S5-AC20]`); these
checks need a person with the running app, VoiceOver and the keyboard. Tick each item when verified.

- [ ] S5-AC9 With a Mac / Browser / Windows frame, double-click the title bar on the canvas: a field appears over
      the bar; typing "Release notes" updates the preview live; Return commits (Edit menu: "Undo Edit Frame
      Title"); Esc restores the previous title. Emoji and right-to-left text (e.g. "שלום 👋") show correctly and
      stay inside the bar. The Title field in the Frame section behaves the same.
- [ ] S5-AC20 VoiceOver reads each frame tile ("Frame: Mac window, selected"), the Title field, the UI scale
      slider ("UI scale, 100 percent"), each colour well with its token name and hex value, the Chrome picker and
      the Text / Code font menus; the canvas preview reads the frame title as its value.
- [ ] S5-AC20 Keyboard only: Tab reaches every frame tile, the Title field, the slider, the colour wells, HEX
      fields, Chrome picker, font menus and Reset Fonts; Space / Return activates them.
- [ ] Visual: the Frame and Colors & Fonts sections use the same glass look as Backdrop and Border, in Light and
      Dark; frame thumbnails follow the current tokens and corner radius.
