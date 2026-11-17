# S9 — manual checks (app-smoke)

Automated tests cover the annotation model, hit-testing, gestures, undo and rendering. These checks need a person in
the running app. Tick each item when it has been verified.

- [ ] S9-AC20 Press ⇧⌘A (or the Annotate toolbar button): the glass tool palette appears at the bottom of the canvas,
      in Light and Dark; the selected tool is highlighted; Esc leaves Annotate mode.
- [ ] S9-AC20 VoiceOver reads each tool with its shortcut ("Pen, P"), the colour swatches by name, the size and line
      style controls.
- [ ] S9-AC20 Draw with the pen and highlighter, add an arrow, rectangle, text, three steps, a redaction and a sticker:
      each appears under the pointer as you drag, with no visible lag on a 4K screenshot.
- [ ] S9-AC20 Select an object: the outline and handles follow it, including after rotating it; arrows show endpoint
      handles; ⌘-click selects several; ⌘D, ⌫ and ⌘⌫ work and each is undone by one ⌘Z.
- [ ] S9-AC20 Export at 2×: annotations are sharp, redacted areas are unreadable, nothing outside the content moved.
