# Sunshot — delivery slices

Sunshot is a lightweight, native macOS screenshot beautifier. The feature
inventory in `postspark-macos-spec.md` is used as a reference for *what kinds of
controls* users expect in this product category; Sunshot has its own name,
visual design, assets, defaults and copy. Do not reuse PostSpark branding,
artwork, texture packs, template names or pixel layouts.

Every slice is **vertical** (model → renderer → UI → tests), ships on its own,
and must pass `make gate` before it is marked `Done`. Acceptance criteria live
in `docs/acceptance/S<n>.md` with IDs like `S1-AC3`; every AC of a `Done` slice
must be referenced by at least one test (enforced by `scripts/check-traceability.py`).

Status values: `Planned` · `In progress` · `Done` · `Deferred`.
(The gate parses the table below — keep the column layout.)

| Slice | Name | Status | Spec refs |
|---|---|---|---|
| S0 | Harness & quality gate | Done | — |
| S1 | Walking skeleton: import → canvas → export | In progress | §2.3, §3.1, §10.1, §10.3, §16 |
| S2 | Border & shadow | Planned | §9.2, §9.3 |
| S3 | Backdrop basics: none / solid / gradient / image | Planned | §9.1 (type selector), §9.1 gradient editor |
| S4 | Canvas size & export options | Planned | §4, §10.1, §15 (filename) |
| S5 | Frames & colour tokens | Planned | §5, §9.4, §9.5 |
| S6 | Position, tilt & layout presets | Planned | §6, §7.1 |
| S7 | Documents, themes, settings & menus | Planned | §2.3 drafts/cleanup, §9 Save theme, §15, §16 |
| S8 | Backdrop effects & auto backgrounds | Planned | §9.1 effects/pattern/vignette/overlay/auto |
| S9 | Annotate | Planned | §7.2 |
| S10 | Crop & capture (screen, website URL) | Planned | §3.2, §3.3 |
| S11 | Code snippet template | Planned | §12 (Code Snippet) |
| S12 | Device mockups & template gallery | Planned | §3.4, §12 (Device), §13 |
| S13 | Animate & video export | Planned | §7.3, §8, §10.2 |
| S14 | Bulk edit & batch export | Planned | §11 |

**MVP = S1–S7** (a complete, saveable, still-image beautifier).

## Slice details

### S0 — Harness & quality gate
Repo, SwiftPM package (`SunshotCore` / `SunshotRender` / `SunshotApp`),
`make gate` with format, hygiene, architecture, warnings-as-errors build, tests,
snapshot tests, coverage thresholds, AC traceability, app bundle + size budget,
headless smoke launch, render performance budget, gate self-test, git hooks, CI
workflow. Seed code exists only to give each stage something real to check.

### S1 — Walking skeleton
Open / drag-drop / paste (⌘V) an image (PNG, JPEG, HEIC, TIFF, WebP read).
Canvas preview = backdrop (default solid) + content with default padding.
Export PNG via save panel (⇧⌘E) and Copy PNG (⌘C). Undo/redo (⌘Z / ⇧⌘Z) through
a single document store. Preview and export use the same render function
(pixel parity test). Empty state with drop zone. Clear content.

### S2 — Border & shadow
Corner style sharp / smooth (continuous) / round + radius (0–200 px).
Shadow none / spread / hug × low / medium / high + light-source offset handle.
Inspector sections with per-section reset. All undoable, snapshot-tested.

### S3 — Backdrop basics
Type: none (transparent, checkerboard in preview only) / solid (Sunshot swatch
set + colour picker) / gradient (Sunshot preset set + editor: linear/radial,
angle, multi-stop add/move/delete) / image (user file; a small set of Sunshot's
own generated wallpapers). Reset backdrop.

### S4 — Canvas size & export options
Aspect presets shipped as bundled JSON (general + social + store groups), search,
`Auto`, custom W×H. Store presets export at exact pixel sizes.
Export format PNG / JPEG / HEIC (+ WebP if ImageIO can write it on the min OS),
scale 1× / 2× / 4K / 6K long-edge. Filename template
`{TEMPLATE}_{SCALE}_sunshot_{DATE}` with `{DATE} {TEMPLATE} {SCALE} {RANDOM}
{WIDTH} {HEIGHT}`. Export button label reflects current preset.

### S5 — Frames & colour tokens
Frames: none, mac window, browser window, card, stack, stack 2, thick border,
Windows-style window — all drawn by Sunshot (vector, own styling). Inline title
edit, UI scale. Colour tokens foreground / background / secondary / primary,
fonts (text, code; bundle open-licence fonts only). Light/dark chrome.

### S6 — Position, tilt & layout presets
Position with axis lock + centre/edge snapping, zoom, 2D rotation, 3D tilt with
perspective (preview + export parity), reset. ≥12 Sunshot layout presets
rendered as live thumbnails; applying is animated and undoable.

### S7 — Documents, themes, settings & menus
`.sunshot` package document (JSON + media), autosave, Open Recent, Start Over
(with optional confirmation). Save / apply named themes. Settings window:
appearance, filename format, default export folder, confirm reset, default
template. Full menu bar mirroring every shortcut.

### S8 — Backdrop effects & auto backgrounds
Backdrop blur / noise / saturation / opacity (resolution-independent), patterns
(circles, waves, dots, rays, grid, stripes, noise) with intensity / thickness /
colour, vignette dark/light with spread/intensity, overlay textures (Sunshot's
own procedurally generated set) above/below content. Auto backgrounds: palette
extraction from content, generated mesh gradients, shuffle.

### S9 — Annotate
Pen, highlighter, eraser, arrow, rectangle, text, step counter, blur/pixelate
redaction, emoji stickers; colour palette + custom; size; solid/dashed/dotted.
Select, move, resize, rotate, ⌘-click multi-select, ⌘D, ⌫, clear (⌘⌫); all
undoable; vector, rendered at export resolution. Tool shortcuts.

### S10 — Crop & capture
Non-destructive crop dialog (free + ratio presets, tall images scroll).
Screen capture (area / window) via ScreenCaptureKit. Website capture from URL
(offscreen WKWebView, viewport width, full-page, delay). Optional global hotkey.

### S11 — Code snippet template
Code editor, dependency-free syntax highlighting for a starter set of
languages, line numbers toggle, highlighted lines, title, theme colours/fonts.

### S12 — Device mockups & template gallery
Sunshot-drawn generic device frames (phone, tablet, laptop, desktop) in a few
finishes; recommended media sizes; device suggestion from media dimensions;
multi-device layouts. Template gallery of Sunshot document presets; default
template at launch.

### S13 — Animate & video export
Video content import, timeline with keyframe clips (target transform, duration,
easing: spring / linear / cubic / out / in-out / out-circ), playback, mute,
jump cut, MP4 (H.264/HEVC) 30/60 fps ≤ 2 min, HEVC-with-alpha `.mov` for
transparent backdrops, progress + cancel.

### S14 — Bulk edit
Import many images, one shared style, preview strip, export all to a folder
with progress.

## Deferred — needs a product decision
- Social post templates (X / Bluesky): need network fetching of third-party content.
- Stock photo search (Unsplash): needs an API key and attribution rules.
- Cloud storage & share links, accounts/sign-in.
- Paid tiers / StoreKit paywall (the spec's [Pro] markers are ignored for now — everything is free).
- Auto-update (Sparkle), signing & notarisation, App Store packaging.
- Share extension / Services menu / VS Code bridge.
