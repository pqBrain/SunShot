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
  (S4 checks this at runtime instead of assuming it; see the S4 notes.)
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

## S3 implementation notes (2026-11-17)
- **Section name is "Backdrop"** (not "Background"), first in the inspector, collapsible with its own Reset.
- **Per-type memory lives in the document** (`BackdropSettings`: last solid colour, gradient and image per type),
  so switching None → Gradient → Solid restores each type's last values, survives undo and will save with S7.
  Reset Backdrop returns to solid #EDEDF2 and leaves the other types' memory alone.
- **Gradient angle:** 0° = bottom → top, clockwise (90° = left → right), CSS-like. Radial is centred and reaches
  the corners. Stops are interpolated in premultiplied sRGB; two stops at the same position make a hard edge.
  Decoded stop positions are clamped to 0…1.
- **Dithering:** every gradient/wallpaper pixel is `floor(value + noise)` with deterministic per-pixel hash noise, so
  preview and export are byte-identical and slow gradients don't band. Values within 1e-4 of an 8-bit level snap
  to it, so a flat gradient is exactly its colour.
- **Wallpapers are generated recipes** (JSON: base gradient + soft colour fields), drawn by the same renderer at
  any size. No photos or third-party images ship; the hygiene gate rejects binary images under `Resources`.
- **Transparency checkerboard** is preview-only: 16 canvas px squares (8 pt at 1:1 on a 2× display), square (0,0)
  is the darker grey; Light #FFFFFF/#DCDCE1, Dark #3A3A3F/#2A2A2E. S3-AC2 (fully transparent export) holds with
  shadow None; a shadow is still drawn on a transparent backdrop by design.
- **Colour-panel edits** stream values with no "ended" event: they merge into one undo step that closes after
  600 ms idle, or as soon as any other edit, undo or redo happens.
- **User backdrop images** keep the original bytes in the document (for S7 save) and the decoded pixels for
  rendering; a missing image falls back to the default colour, never garbage. Unused bytes are dropped when
  another backdrop is chosen; undo restores them.
- **Gradient snapshot references** are stored downscaled (dither noise makes full-size PNGs large); SSIM for
  S3-AC18 is measured on solid content, as in S2.
- **Measured (release, M-series):** 4K image backdrop 69 ms, 4K gradient 72 ms (budget 500 ms); 8000² image
  backdrop + 8000² content peaks at +1.23 GB (budget 2 GB).
- **`os` is allowed in SunshotPlatform** (for `os.Logger`, which the hygiene rules require instead of `print`):
  a catalog that fails to load is logged and shows an empty grid, never a crash. The smoke test fails if any
  catalog is empty, so this can't ship silently.
- **The window is not movable by its background** (was `windowBackgroundDragBehavior(.enabled)` since S2): with
  it on, clicks on SwiftUI-drawn buttons in the glass inspector (swatches, presets, wallpapers, section headers,
  Reset) were taken as window drags and did nothing. The window still moves by its top (toolbar) area.

## S4 implementation notes (2026-11-17)
- **WebP export, checked at runtime:** `CGImageDestinationCopyTypeIdentifiers()` on macOS 27.2.1 lists `public.png`,
  `public.jpeg` and `public.heic` but not `org.webmproject.webp`, so the format picker shows PNG / JPEG / HEIC.
  WebP appears automatically on an OS that can write it (`ImageCodec.writableFormats`).
- **Presets** live in `canvas-presets.json` (34: 10 general, 10 social, 14 app-store sizes) and are validated on
  load (unique ids, declared groups, positive ratios, store presets need a pixel size within 0.5 % of their
  ratio and ≤ 16384 px). `aspect-presets.json` (S0) was replaced. Store sizes were checked on 2026-11-17 against
  Apple's App Store Connect screenshot specs, Google Play's graphic asset guide and the Chrome Web Store image
  guide (URLs in the JSON `sources`).
- **No brand names in preset names:** social presets are named by use ("Portrait post", "Story / vertical
  video", "Link preview"); store presets by device or listing asset ("iPhone 6.7″", "Store feature graphic",
  "Browser extension marquee"). Device platform names (iPhone, iPad, Mac, Apple TV, Android) are kept because
  they are what the sizes are for. Group labels: General / Social / App stores.
- **Ratio presets grow the canvas, never scale content** (S4-AC4). **Exact sizes (store presets and custom W×H)
  scale content + padding uniformly to fit**, centred, so corner radius and shadow scale with it
  (`CanvasLayout.styleScale`); small content is scaled up too, so a store screenshot is always filled the same way.
- **Store / exact presets ignore the scale choice** and always export at their own size: the scale picker is
  disabled with a hint, the button reads "Export 1290×2796 • PNG", and `{SCALE}` is `1x`.
- **Custom W×H is a 1× canvas size**, so the scale applies to it. One side empty follows the Auto canvas ratio
  (S4-AC7: 1200 → 774); both empty = Auto. Invalid input shows "Enter 1–16384" and changes nothing.
- **Export options live in the document** (format, scale) and are undoable ("Change Export Format",
  "Change Export Scale"); canvas changes are "Change Canvas Size". Defaults: PNG at 2×; JPEG / HEIC quality 0.9.
  JPEG is flattened onto white, with a notice in the popover when the backdrop isn't opaque.
- **Too large is refused, not clamped:** any output side over 16384 px disables Export and Copy with "This size is
  too large to export (max 16384 px per side)"; the check runs before anything is rendered.
- **Preview is capped at 6144 px on the long edge** so a 16384² custom canvas can't exhaust memory on screen;
  exports are unaffected.
- **File names:** `{TEMPLATE}_{SCALE}_sunshot_{DATE}` (replaces the S1 interim `sunshot-<date>.png`). The template
  is fixed in S4 (S7 Settings makes it editable); the popover shows the resulting name read-only. `/ : \` become
  `-`, unknown tokens stay literal, the base is cut to 200 characters / bytes.
- **Copy honours the export size but is always PNG** (S4-AC18).
- **Full-scale parity and budgets run in the release perf stage:** the debug build's per-pixel gradient fill takes
  ~13 s at 6K, so the normal test run checks parity at 1× / 2× and the perf stage at 1× / 2× / 4K / 6K. The perf
  stage now runs serially (`--no-parallel`): parallel heavy tests inflated each other's peak-memory readings.
- **Measured (release, M-series, serial):** 4K render 51 ms (budget 500); 6K PNG export of 3712×2032 content incl.
  encoding 354–395 ms (new budget 1000 ms); 8000² export at 1× +0.86 GB (budget 1.5); at 2× (16256², allowed)
  +2.50 GB (budget 4); 4K→1× SSIM 0.998.
- **Memory-heavy test suites run one after another** (`MemoryHeavySuites` in the Platform tests): the S1 8000²
  memory test reads the process-wide footprint, and S4's 16384² preview test running beside it pushed it to
  2.3 GB. The gate now also lists failing test expectations before the log tail, so a broad failure can't hide
  the one that matters (needed by the snapshot self-test case).
- **Known limitation:** a small image exported at 4K/6K with a strong shadow is slow (200×120 content at 6K with
  spread/high: ~4.7 s), because the shadow blur grows with the scale (~750 px). It runs off the main thread;
  rendering the shadow at reduced resolution is the fix if it matters in practice.
