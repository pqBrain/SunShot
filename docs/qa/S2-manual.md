# S2 — manual checks

S2 has no gated manual ACs (all 19 are covered by automated tests). Please look at these in the real app
(`make run`) before S2 is marked `Done`.

## Exploratory (not gated, but please look)
- [ ] The window is translucent: the desktop shows through the Liquid Glass background; the toolbar has no bar.
- [ ] The inspector floats as a glass panel on the right; ⌥⌘E and the toolbar button show/hide it.
- [ ] Corner style sharp / smooth / round changes the preview; the radius slider and the number field stay in sync.
- [ ] Dragging the radius slider, then ⌘Z, undoes the whole drag in one step ("Undo Change Corner Radius").
- [ ] Drag the sun in the light pad: the shadow falls the opposite way. Click the pad, then arrow keys / ⇧+arrows nudge it.
- [ ] Reset on Border leaves the shadow alone, and vice versa.
- [ ] Light and Dark appearance: inspector text and the light pad are readable.
- [ ] VoiceOver (⌘F5) reads "Corner style: smooth", "Corner radius, 24 pixels", "Light direction, x 0, y -0.35".
