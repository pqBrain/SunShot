# S13 — manual checks (app-smoke)

Automated tests cover the timeline maths, easing, undo, export files (codec, frames, alpha, audio), cancel, saving
and the playback model (`[S13-AC1]`–`[S13-AC18]`). These checks need a person in the running app. Tick each item
when it has been verified.

- [ ] S13-AC19 Animate (⇧⌘M or the toolbar button) swaps the bottom toolbar for the timeline strip: Exit, Mute,
      Add Animation, Play/Pause, `00:01.50 / 00:03.00`, clip chips sized by duration (jump cuts marked), Delete.
- [ ] S13-AC19 Selecting a clip and opening its Transition popover shows six easings with curve previews,
      Duration and Hold sliders and the target's X / Y, Zoom, Rotation and Tilt; every change can be undone.
- [ ] S13-AC19 Import Video… (⌥⌘I) loads a short movie; its first frame shows on the canvas; a movie longer than
      2 minutes is refused with a clear message.
- [ ] S13-AC19 Export Video… (⌃⌘E) opens the sheet: Resolution, Frame rate, Codec, read-only Resolution, Duration
      and Format (`.mov` when the backdrop is None); Export shows progress and Cancel Render stops it and leaves no
      file behind. The exported file plays in QuickTime Player, with sound unless muted.
- [ ] S13-AC20 A 1080p canvas with a tilt animation plays smoothly; Space toggles play/pause while the timeline
      has focus; Home / End jump to the start / end.
- [ ] Visual: the timeline strip and export sheet use the glass look of the rest of the window in Light and Dark.
