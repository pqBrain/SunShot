# S7 — manual checks (app-smoke)

Automated tests cover the document format, autosave, recovery, Open Recent, themes, settings persistence, the
menu definition and menu enablement logic. These checks need a person in the running app (`make run`), with
VoiceOver and the keyboard where noted. Tick each item when it has been verified.

- [ ] S7-AC7 With content and "Confirm before resetting" on, File ▸ Start Over (and the toolbar brush button) shows
      "Start over?" with "Start Over" (destructive) and "Cancel"; Cancel changes nothing; Start Over resets content
      and style; Edit ▸ Undo Start Over brings everything back exactly.
- [ ] S7-AC12 Sunshot ▸ Settings… (⌘,) opens a window titled "Settings" with Appearance (System / Light / Dark),
      Filename format (live preview, warning when empty, Reset), Default export folder (path, Choose…, Clear),
      "Confirm before resetting", and a disabled Default template picker showing "Screenshot". Values survive a
      relaunch.
- [ ] S7-AC18 Empty window: Export Image…, Copy, Clear Content, Start Over and Save are disabled; Save As… and Open
      Recent work. With content they are enabled. Edit ▸ Undo reads e.g. "Undo Change Corner Style".
- [ ] S7-AC19 Untitled document with content: ⌘W and ⌘Q ask "Save changes to Untitled?" (Save / Don't Save /
      Cancel); Cancel keeps the window and state. A saved document closes and quits without a prompt and the
      last change is on disk. An untitled document without content closes without a prompt.
- [ ] S7-AC22 VoiceOver reads every Settings control by name, the theme header as "Theme: Ocean" (or
      "Theme: No Theme"), and the Save theme button. Tab reaches every Settings control. Dialogs (Start over?,
      Save changes?, Save Theme name prompt, Replace) focus their default button and answer Return / Esc.
- [ ] S7-AC22 Settings window, theme header and dialogs are legible in Light and Dark (text contrast ≥ 4.5:1).
- [ ] Visual: the theme header sits at the top of the glass inspector; Open Recent lists documents by name with
      "Clear Menu" at the bottom; Finder shows `.sunshot` documents as single files that open in Sunshot.
- [ ] Force-quit (Activity Monitor) with an untitled image open for > 5 s, relaunch: the work is back as "Untitled".
