# S6 — manual checks (app-smoke)

Automated tests cover the position/tilt maths, snapping, axis lock, undo names, preset catalogue, thumbnails,
the preset animation timing and the accessibility label strings (`[S6-AC3]`…`[S6-AC20]`); these checks need a
person with the running app, the keyboard and VoiceOver. Tick each item when it has been verified.

- [ ] S6-AC2 With an image loaded, the Position button in the bottom bar opens a popover with "Position" and
      "Tilt" tabs, a mini canvas with a draggable handle, Zoom and Rotation sliders (with typed fields) and a
      Reset (↺) button. With no image the Position button is not shown / is disabled.
- [ ] S6-AC2 Dragging the handle moves the content in the main preview live; a near-horizontal or near-vertical
      drag locks to that axis (dashed guide), ⌥ frees it, ⌘ turns off centre/edge snapping.
- [ ] S6-AC2 Tilt tab: dragging the handle toward an edge leans the image in 3D in the main preview; Tilt X / Y
      sliders reach ±60°.
- [ ] S6-AC18 Keyboard only: Tab to the mini canvas (accent ring), arrow keys move the content by 0.01, ⇧-arrows by
      0.05; the Zoom and Rotation sliders respond to arrows; in the Layouts sidebar ↑/↓ move the cursor and Return
      applies the layout.
- [ ] S6-AC18 VoiceOver reads "Content position, x 0.00 y 0.00", "Zoom, 100 percent", "Rotation, 0 degrees" and,
      in the Layouts sidebar, "Layout: Centered, selected" for the applied layout.
- [ ] S6-AC16 Applying a layout animates smoothly (~0.3 s); with System Settings › Accessibility › Display ›
      Reduce motion on, it jumps straight to the layout.
- [ ] S6-AC14 Changing the backdrop, border or shadow updates the layout thumbnails shortly after, without the UI
      stalling; with no image the sidebar shows grey placeholders and is disabled.
- [ ] S6-AC13 Review: layout names and transforms in `Sources/SunshotCore/Resources/layout-presets.json` are
      Sunshot's own (no names or pixel layouts copied from other products).
- [ ] Visual: the Layouts sidebar, bottom bar and Position popover use the translucent glass look of the rest of
      the window, in Light and Dark.
