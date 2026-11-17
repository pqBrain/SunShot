# S11 — manual checks (app-smoke)

Automated tests cover the snippet model, highlighter, detection, themes, rendering, undo and typing coalescing;
these checks need a person in the running app. Tick each item when it has been verified.

- [ ] S11-AC18 File ▸ New Code Snippet (⌥⌘N) and the empty-state "New Code Snippet" button both open a snippet
      document: the preview shows the starter code and a code editor panel appears below it.
- [ ] S11-AC18 Typing in the editor updates the preview live; the editor shows "Enter some code…" when empty; typing
      `"quotes"` and `--` stays exactly as typed (no smart quotes, no em dash, no autocorrect).
- [ ] S11-AC18 ⌘Z after typing a word undoes the whole word ("Undo Typing" in the Edit menu), not one letter.
- [ ] S11-AC18 The inspector shows a Code section first: Language (Auto-detect shows the detected language, e.g.
      "Auto-detect (Swift)"), Theme, Line numbers, Highlighted lines ("2, 4-6" + Return), Title, Font size and
      Padding; each change shows in the preview and Reset restores the style but keeps the code.
- [ ] S11-AC18 VoiceOver reads the code editor ("Code editor"), the Language and Theme pickers with their values,
      the Line numbers toggle, the Highlighted lines field, the Title field and both sliders with pixel values.
- [ ] S11-AC18 Opening or pasting an image replaces the snippet; the editor panel and Code section disappear.
- [ ] Visual: export at 2× and 4K and zoom in — code text is crisp (no upscaling blur); the editor panel uses the
      glass look of the inspector, in Light and Dark.
