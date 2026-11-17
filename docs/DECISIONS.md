# Product decisions log

Decisions made by the delivery lead within scope. Each one names what it settled and where.

| Date | Decision | Settles |
|---|---|---|
| 2026-11-17 | ⌘S = Save document (from S7); ⇧⌘E = Export Image everywhere, from S1. ⌘S is not bound before S7. | S1-AC10, S4, S7 open question |
| 2026-11-17 | Ratio presets grow the canvas around unscaled content; exact-pixel (store) presets keep the exact size and scale content to fit. Matches `CanvasLayout`. | S4-AC4 / S4-AC5 |
| 2026-11-17 | Store preset sizes (App Store, Google Play, Chrome Web Store) are supplied by engineering in S4 from each store's published specs, with the source URL and check date recorded in the JSON. | S4 open question |
| 2026-11-17 | S1 defaults: padding 64 px fixed (replaces the S0 seed's 8% fraction), backdrop #EDEDF2, all in `SunshotDefaults`. Preview never upscales past 1:1. | S1 open questions |
| 2026-11-17 | Max canvas side 16384 px; JPEG quality 0.9; `{TEMPLATE}` = `screenshot` until S12. | S4 open questions |
| 2026-11-17 | Theme files are not shareable/importable in the MVP. Drafts surface only through autosave recovery and Open Recent. | S7 open questions |

## S1 implementation notes (2026-11-17)
- **WebP is import-only.** ImageIO can't write WebP on the supported OS (macOS 26+), so S4 export formats are PNG / JPEG / HEIC.
- **Truncated files:** ImageIO reports half a PNG/JPEG as "complete" and fills the rest with grey. The
  loader also requires the PNG `IEND` / JPEG end-of-image marker near the end of the file.
- **Secondary text colour:** macOS `secondaryLabelColor` is ~4:1 on white (fails WCAG AA), so Sunshot uses
  its own greys (light #66666E, dark #A8A8AD), checked by a unit test in both appearances.
- **Module added:** `SunshotPlatform` (AppKit glue + observable editor state) so pasteboard, alerts,
  undo titles and progress logic are unit-tested instead of living in views.
- **Single render path / single store** are enforced by `check-architecture.sh` (no drawing APIs outside
  SunshotRender; views may not hold `@State` copies of the document).
- **Preview** is fitted to the window and never shown larger than 1 image pixel per screen pixel.

## S2 implementation notes (2026-11-17)
- **Minimum macOS is 26** (was 15): the requested native Liquid Glass UI (`glassEffect`, `.glass` button
  styles, `ToolbarSpacer`) only exists from macOS 26. The window is translucent (`containerBackground`
  material); the inspector is a floating glass panel.
- **S2 defaults supersede the S1 look:** new documents get smooth 24 px corners and a spread / medium
  shadow. S1 tests that check untouched content pixels use `Project.plain()` (sharp, no shadow).
- **Shadow constants** (blur / max offset / opacity at 1×): spread 20/20/0.16, 30/20/0.26, 40/20/0.40;
  hug 6/4/0.22, 7/4/0.34, 8/4/0.50. Spread's worst case (47 px) stays inside the 64 px padding; hug ≤ 12 px.
  The shadow is cast from the clipped content's alpha, so transparent cut-outs cast none.
- **Smooth corners** are one cubic per corner reaching 1.28 × radius into each edge, falling back to a
  circular corner when the content is too small.
- **Contrast reference for glass:** glass adapts its tint to what's behind it, so contrast tests use a typical
  settled panel colour per appearance (`SunshotPalette.inspectorSurface`). Custom control outlines use
  `controlStroke` (≥ 3:1).
- **S2-AC10 similarity** is measured on solid content: resampling detailed content at 2× is an S1 concern and
  on its own scores ~0.978 SSIM; border + shadow structure scores 0.99.
