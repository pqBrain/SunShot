# S3 — manual checks

Everything in S3 has an automated test except the parts of S3-AC20 that need a person at the keyboard. Please
look at these in the real app (`make run`) before S3 is marked `Done`.

## S3-AC20 — Accessibility and appearance (manual part)
- [ ] VoiceOver (⌘F5) reads swatches as "Mist, #EDEDF2, selected", presets as "Gradient preset <name>", stops as
      "Gradient stop 2 of 3, #HEX, position 50 percent", and the angle field as "Gradient angle, degrees".
- [ ] Keyboard only: Tab reaches the type picker, swatches, HEX field, presets, angle slider and field, the stop
      bar, + / − buttons, wallpapers and "Choose Image…". On a focused stop, ← / → move it by 1 %, ⇧ by 10 %,
      Delete removes it (not below two stops).
- [ ] Light and Dark: labels, swatch rings and the stop bar outline are readable; the checkerboard behind
      None switches greys with the appearance. If you use a non-blue accent colour, check the selection ring.

## Exploratory (not gated, but please look)
- [ ] The Backdrop section matches the Border / Shadow glass style, collapses, and its Reset leaves them alone.
- [ ] Colour panel: drag the colour wheel around, then ⌘Z once: the whole drag undoes in one step.
- [ ] Drag a gradient stop along the bar, then ⌘Z: one step. Click the bar to add a stop at that colour.
- [ ] Drop a photo onto the image well; Choose Image… picks one too. A non-image file is refused.
- [ ] Wallpapers and preset thumbnails look the same as the canvas when picked.
- [ ] Export or copy with None: the PNG is transparent outside the content (no checkerboard).
