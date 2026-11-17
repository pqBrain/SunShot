# S10 — manual checks (app-smoke)

Automated tests cover the crop maths, crop rendering and undo, saving, URL validation, website capture from local
HTML, timeouts, cancellation and the screen-capture flows with a fake capturer. These checks need a person with the
packaged, sandboxed app (`make run`), a network connection and the macOS Screen Recording prompt. Tick each item when
it has been verified.

- [ ] S10-AC18 File ▸ Capture Area… (⌥⇧⌘4) the first time: macOS asks for Screen Recording permission. Deny it:
      Sunshot explains how to allow it and "Open System Settings" opens the Screen & System Audio Recording pane;
      nothing crashes and the document is unchanged.
- [ ] S10-AC18 Allow the permission, relaunch, Capture Area…: the screen under the pointer dims, a dashed rectangle
      with a size label follows the drag, Esc cancels, releasing captures exactly that area (no Sunshot windows in it).
- [ ] S10-AC18 Capture Window… lists other apps' windows (not Sunshot's); double-click or Capture takes the window
      without its system shadow; ⌘Z restores the previous content.
- [ ] S10-AC18 Capture Website… with `apple.com`, Desktop, Full page on, delay 2 s: progress shows, the long page
      arrives with images loaded; Cancel during loading stops it; `file:///etc/hosts` is refused with a message.
- [ ] S10-AC18 Crop… (⌥⌘C) on a full-page website capture: the image fills the width and scrolls; handles and ratio
      presets work; Reset, Cancel and Apply behave; re-opening shows the full image with the current crop.
- [ ] S10-AC18 Annotate a cropped image: shapes land under the pointer; change the crop: the shapes stay on the same
      image pixels.
- [ ] S10-AC18 Settings ▸ "Capture Area from anywhere (⌥⇧⌘4)" is off by default; turn it on, switch to another app and
      press ⌥⇧⌘4: the area overlay appears; turn it off: the shortcut no longer works outside Sunshot.
- [ ] S10-AC18 VoiceOver reads the Crop button, the crop area with its size, the ratio picker, and the website form
      fields; the crop dialog, website sheet and window picker look right in Light and Dark.
