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

## S5 implementation notes (2026-11-17)
- **Model:** `Project.frame` (`Frame`: kind, title, uiScale %) and `Project.tokens` (`DesignTokens`: four colour
  tokens, Text / Code fonts by PostScript name, chrome appearance light / dark / auto). Defaults live in
  `SunshotDefaults` (frame none, 100 %, auto chrome, #1D1D1F / #FFFFFF / #6E6E73 / #0A84FF, system fonts).
- **Tolerant decoding:** `Project` now has an explicit `init(from:)` (`Project+Coding.swift`) in which every key is
  optional and falls back to its default, and the new nested types do the same; unknown frame kinds / appearances
  decode as `none` / `auto`. Old documents (no `frame` / `tokens` keys) open unchanged. S7 can reuse this rather
  than add a second decoder.
- **Layout:** frame chrome is laid out as part of the content. `CanvasLayout.compute` pads the *frame box*
  (content + `FrameGeometry.insets`) instead of the bare content, so chrome grows an Auto canvas (1000×600 + mac
  bar → 1128×756) and is scaled with the content on exact canvases. `CanvasLayout.frameRect` is new; `contentRect`
  keeps its meaning. With frame none the insets are zero and every value is computed exactly as before, so all
  S1–S4 snapshots pass unchanged (S5-AC2 compares against `s2-border-default` with zero tolerance).
- **One drawing path:** `Renderer.drawContent` now calls `FrameRenderer.draw(image, project:, in: box, context:)`
  inside the existing shadow layer; it draws the whole window silhouette (back cards, chrome, content) into a box
  rect, so the shadow follows the silhouette and a later transform (S6 position / tilt) can wrap the call. Frame
  none takes the old clip-and-draw path. The frame picker's thumbnails go through `Renderer.render` too
  (`Renderer.renderFrameThumbnail`), cached per kind / tokens / corners / UI scale in the Platform layer.
- **All chrome is vector:** traffic lights, chevrons, padlock, caption glyphs and the address field are Core
  Graphics paths; titles are Core Text lines truncated with "…" (`CTLineCreateTruncatedLine`), so RTL text and
  emoji shape correctly. At 4K the bar edge is a 1-pixel transition (S5-AC19).
- **Fonts are not bundled** (see the decisions in `docs/acceptance/S5.md`): system font by default, recommended
  installed families first in the pickers, a missing font falls back to the system font and shows "Font
  unavailable". The repository test for `LICENSES/` guards against adding font files without a licence.
- **Auto chrome contrast rule:** tokens are used as given unless below 2:1 against the bar; see S5.md decisions.
- **Undo names:** "Change Frame", "Edit Frame Title", "Change UI Scale", "Reset Frame", "Change Chrome
  Appearance", "Change Foreground / Background / Secondary / Primary Color", "Reset Colors", "Change Text Font",
  "Change Code Font", "Reset Fonts". Inline title editing is a gesture: live updates, Return = one entry, Esc
  restores with no entry. The section header Reset of Colors & Fonts resets the colours; fonts have their own
  Reset Fonts button.
- **Inline title editing** works in the inspector's Title field and directly on the canvas (double-click the
  title bar; the bar's position comes from `EditorModel.titleBarUnitRect`, computed from the same layout).
- **Inspector:** Frame and Colors & Fonts sections are appended after Shadow (Colors & Fonts starts collapsed).

## S7 implementation notes (2026-11-17)
- **`.sunshot` package:** `document.json` (pretty, key-sorted) + `media/<id>.<ext>` holding each image's original
  bytes (content and user backdrop images; generated content without a source file is stored as PNG). No
  `thumbnail.png` yet (optional in the ACs). UTI `app.sunshot.document` (conforms to `com.apple.package`) is
  exported in `Support/Info.plist`; `.sunshot` files open from Finder.
- **Tolerant, generic decoding:** the whole `Project` (and the manifest) is decoded by laying the stored JSON over
  the JSON of a default value (`JSONValue.decodeTolerantly`): missing keys at any depth take their defaults,
  unknown keys are ignored, a stored enum case replaces the default case. New `Project` fields from other slices
  are therefore saved and loaded with no codec change. **Limitation:** an `Optional` field whose *default* is
  non-nil can't round-trip `nil` (synthesised encoding omits nil keys, so the default comes back) — use a
  non-optional value or an enum for such fields.
- **Schema:** `schemaVersion` 1. A higher version opens **read-only** with "This document was made with a newer
  version of Sunshot": autosave is off and ⌘S becomes Save As, so the newer file is never overwritten with fewer
  fields. `DocumentManifestCodec.migrate` is the hook for v2+ (each step needs `fixtures/v<n>/document.json`
  and a test). Golden fixture: `Tests/SunshotCoreTests/fixtures/v1/document.json`.
- **Hostile documents:** media paths must be `media/<plain-name>` (no `..`, `/`, `\`, `:`, hidden or control
  characters) and, after resolving symlinks, must still be inside `media/`, so neither `../../x` nor a symlink
  can make Sunshot read outside the package. Missing, empty or undecodable media → "Can't open this document" with
  the file names and an "Open with Placeholders" choice (grey content of the recorded size; a missing backdrop
  image falls back to the default colour as in S3).
- **Atomic writes:** the package is built in an `itemReplacementDirectory` and swapped in with
  `FileManager.replaceItemAt` (the sanctioned way under the sandbox); an interrupted save leaves the previous
  version untouched (tested by throwing just before the swap). Writes run on a `DocumentWriter` actor, never on
  the main thread, one at a time.
- **Autosave:** 5 s after the last change (debounced via Observation on the document store), on resign-active and
  on quit. Saved documents save in place; untitled ones go to `Application Support/Sunshot/Drafts/<uuid>.sunshot`.
  An untitled document without content keeps no draft. Autosaving a 20 MB-media document did not block the main
  actor beyond the 250 ms test budget.
- **Recovery:** on launch the newest draft is restored as "Untitled" (older drafts stay in the folder). Drafts are
  not listed in Open Recent (they have no user-visible name), so "drafts surface via Open Recent" is narrowed to
  recovery for now. Closing an untitled document with content asks "Save changes to Untitled?" (Save / Don't Save
  / Cancel); Don't Save deletes the draft. Saved documents close and quit silently after a final save.
- **Single window stays:** File ▸ New and Open replace the current document after the same close prompt (Sunshot
  remains one window, as since S1). The window's red close button doesn't lose work: the document stays in memory
  and is autosaved; ⌘W runs the prompt.
- **Open… opens both** `.sunshot` documents (replacing the document) and images (becoming the content, as in S1).
  ⌘S = Save, ⇧⌘S = Save As, ⇧⌘E = Export Image (per the decision table).
- **Open Recent** is Sunshot's own list (10 items, most recent first, `UserDefaults`) with security-scoped
  bookmarks (`com.apple.security.files.bookmarks.app-scope` entitlement added) so items reopen after relaunch in
  the sandbox. A deleted file shows "File not found" and is removed from the list.
- **Themes:** `Theme.fields` in `Sources/SunshotCore/Document/Theme.swift` is the one list of `Project` properties a
  theme carries (today `backdropSettings`, `border`, `shadow`; padding, canvas, export options and content are
  never included). Frame, colour tokens, fonts and backdrop effects are added there with one line each. Style is
  stored as JSON per field, so themes saved before a field existed apply that field's default. User-image
  backdrops are not carried (themes never hold media): the theme gets Sunshot's default wallpaper instead.
  Files: `Application Support/Sunshot/Themes/<sanitised lower-case name>.json` (`/ \ : * ? " < > |`, control
  characters and leading dots stripped from the file name only; `-2` on clashes). Corrupt files are skipped and
  logged. Themes are not shareable (decision table).
- **Theme header rule ("(modified)"):** the document remembers the applied theme (id + style), undoable with the
  style. Header = "No Theme" when none is applied or it was deleted; the theme's current name when the document's
  style equals the theme's; "<name> (modified)" otherwise (editing back to the theme's values reads unmodified
  again). Save Theme marks the new theme as applied as an undo step "Save Theme" (every document change is
  undoable; undo doesn't delete the theme file). Apply is "Apply Theme <name>".
- **Settings** (`UserDefaults`, prefix `app.sunshot.`): appearance via `NSApp.appearance` (exports never depend on
  it); filename template (plugs into the S4 `FilenameTemplate` via `EditorModel.filenameTemplate`; blank = default
  with "Using the default format"); default export folder (bookmark; written directly with ` 2`, ` 3`… on name
  clashes; a missing or unwritable folder opens the save panel at Pictures with a one-line notice); confirm reset;
  default template (Screenshot only, picker disabled until S12).
- **Menus as data:** `MenuCatalog` (SunshotPlatform) defines every menu item, title and key equivalent; the SwiftUI
  `Commands` are built from it, and a unit test checks required items, S1–S4 shortcuts and that no two items share
  a key equivalent (system items such as ⌘Q, ⌘M, ⌃⌘F are listed so the clash check covers them). Enablement and
  dynamic titles (Undo/Redo names, Show/Hide Inspector) come from `DocumentController`. Cut / Copy / Paste / Select
  All go to a focused text field when there is one; otherwise ⌘C copies the PNG and ⌘V pastes an image as before.
  New: ⌘N New, ⌘W Close, ⌘S Save, ⇧⌘S Save As, File ▸ Start Over (no shortcut), ⌘X, ⌘A.
- **Content keeps its original bytes** (`ContentImage.data`) so a saved document stores the imported file unchanged
  (SHA-256 checked). `NSSupportsSuddenTermination` and automatic termination are off so quit always gets a final
  save. The smoke test also saves and reopens a document inside the sandboxed app.
- **Measured (release, M-series, machine shared with other builds):** reloaded document 4K render median 158 ms
  (budget 500); 8000² content + 8000² backdrop save 2 ms (original bytes are copied, nothing re-encoded) and load
  0.63 s (budget 3 s), peak growth 0.72 GB (budget 1.5). The perf fixtures are solid-colour PNGs, so the save time
  reflects small files; real photos are dominated by disk speed.

## S8 implementation notes (2026-11-17)
- **Effects live in `BackdropSettings.effects`** (`BackdropEffects`: adjustments, pattern, vignette, overlay) plus
  `BackdropSettings.autoShuffle`; no new `Project` field. `BackdropSettings` and every effect struct decode
  tolerantly (`decodeIfPresent`, unknown enum values fall back to none, values clamped), so pre-S8 documents and
  S7 save/load need nothing extra. All values are clamped by `didSet`, like `Border.radius`.
- **Defaults are all off**, and with `isIdentityBelowContent` the renderer takes the unchanged S3 path, so every
  existing snapshot is byte-identical (none were re-recorded).
- **Render order:** backdrop → blur → saturation → pattern → vignette → grain → opacity → underlay texture, then
  content, then the overlay texture when position = above (`EffectsRenderer.drawAboveContent`, one call after
  `drawContent` in `Renderer.render`). Adjustments never touch content.
- **Resolution independence:** every length is canvas pixels at 1× (pattern period 32, blur radius, grain cell =
  1 canvas px); overlay textures and vignettes are laid out relative to the canvas, so they never tile. Edges are
  anti-aliased over one output pixel, so 4K is sharper but the same picture (4K→1× SSIM 0.993 with all effects).
- **Determinism:** blur is a four-pass vImage box blur (≈ Gaussian, edge-extended) on the CPU rather than Core
  Image (GPU results aren't guaranteed byte-stable); grain and value noise use integer hashes; per-pixel passes reuse
  S3's dither. Preview and export are byte-identical.
- **Preview checkerboard with effects:** effects are applied to the backdrop alone, then the grid is composited
  underneath (destination-over) when the backdrop or opacity is translucent, so opacity shows the checkerboard in
  the preview only.
- **Overlay textures are Sunshot's own procedural set** (Blinds, Window, Leaves, Lattice, Ripples, Dapple): soft
  shadow fields drawn as black at `opacity × 0.9`. No bitmaps.
- **Own defaults/ranges:** blur 0–50 px, noise 0–100 %, saturation 0–200 %, opacity 0–100 %; pattern intensity 20 %,
  thickness 100 % (25–300 %), colour #23232B (visible on the light default backdrop); vignette spread/intensity
  50 %; overlay opacity 30 %, above content.
- **Auto backgrounds are generated `Wallpaper` recipes** (base gradient + soft colour fields in five tones: as found,
  radial, pastel, deep, mid) chosen in the Image type, so no new `Backdrop` case and they save like any wallpaper.
  Palette: 64-px sample, 5-bit histogram, greedy pick by prominence with shrinking minimum distance, then tints /
  shades to reach six. Shuffle derives the next seed with SplitMix64 and applies the first new suggestion
  ("Shuffle Auto Backgrounds"); the palette is cached per content image in `AutoBackgroundStore`.
- **Reset Backdrop now also resets the effects**; each effect popover has its own Reset.
- **Measured (release, M-series, machine loaded by parallel agent builds):** 4K image backdrop + every effect
  (blur 24) 229 ms median (budget 500); the S3 4K gradient read 186 ms in the same run (72 ms when idle), so the
  effects cost roughly 40–150 ms.

## S14 implementation notes (2026-11-17)
- **A batch is a list of file references sharing the one `Project`.** `BulkBatch` (Core) holds `BulkItem`s
  (URL + security-scope URL) and the selection; nothing is decoded until needed. Every style control keeps working
  on the document exactly as before, so a style edit applies to every item and stays one ordinary undo step.
  Fields other slices add to `Project` pass through untouched (export builds each item's document from the
  current project and media).
- **Switching items is navigation, not an edit.** `EditorSession.showBulkContent` swaps the content in every
  undo/redo state (`UndoStack.rewriteAll`, new), so undo/redo only ever change the style and never which image is
  on the canvas. Consequence: once a batch is open, undo can't bring back an image that was on the canvas before.
- **Drops:** two or more supported images, or any folder, go to the batch (`EditorModel.bulkDropHandler`, set by
  `BulkSession`); a single image keeps the S1 flow. Without a handler (tests, other windows) S1 behaviour is
  unchanged. File ▸ Import Multiple… (⇧⌘O) takes files and folders. Folders are read top-level only, hidden files
  and subfolders ignored, Finder (numeric-aware) name order. Duplicates (same standardized path) are ignored; the
  batch holds at most 500 items. Skips/duplicates/limit are reported in the notice banner, never an alert.
- **Thumbnails use the one renderer.** `Renderer.render` gained an optional `layoutSize`: the strip renders a
  downsampled proxy (ImageIO thumbnail straight from the file, long edge ≤ 256 px, EXIF orientation applied) laid
  out as if it were the full-size image, so a thumbnail is the export scaled down (SSIM ≥ 0.9 vs a downscaled
  full render in the test) with no second drawing path. Proxies are cached per item (worst case 500 × 256² × 4 ≈
  130 MB), thumbnails (200 px long edge) re-render from them on every style change, one at a time, a newer
  refresh superseding an older one.
- **Export All** writes to a chosen folder (no zip: Finder's Compress does that) with the S4 options per item
  (each item gets its own export size; store/exact sizes are their own size). Items are processed strictly one
  after another off the main actor (decode → render → encode → atomic write). A failing item (corrupt, missing,
  too large) is recorded with its reason and the batch goes on; Cancel stops before the next item, so written
  files stay and no partial file is left (writes are atomic).
- **File names:** the S4 template plus `_{INDEX}` when the template has no `{INDEX}` (1-based, zero-padded to the
  batch size's digit count, list order — so reordering the strip is reordering the files); `{NAME}` is the source
  file name. `{DATE}` is fixed for the whole run. Names that already exist in the folder, or would repeat, get
  `-2`, `-3`… before the extension (case-insensitive like APFS); nothing is ever overwritten.
- **Selection decodes the item at full size** (`ImageLoader`, S1 rules) for the canvas; an unreadable item gets an
  error badge in the strip and a notice, and the canvas is emptied rather than showing a different image.
  Removing the last item closes the batch and empties the canvas; Close Batch keeps the current image.
- **Memory (measured, release, M-series, this machine busy with parallel agents):** exporting 40 images of
  3000×2000 at 2× grows the footprint to ~1.09 GB after ~16 items and then stays flat (+0 MB over the last 20).
  The climb is not the batch: rendering an image that came through ImageIO leaves a CoreGraphics-internal,
  count-limited (~16 entries) cache of render-sized buffers (56 MB each at this size; rendering the same pixels
  from a bitmap-context image doesn't). It is bounded, and S1/S4 single exports hit the same cache. The perf
  budget therefore checks the plateau (last 20 items add ≤ 64 MB) and an absolute 1.5 GB cap. Follow-up: find
  which CG cache this is; for much larger images the plateau scales with image size.
- **Shared files touched (small):** `Renderer.swift` (optional `layoutSize`), `UndoStack.swift` (`rewriteAll`),
  `EditorModel.swift` (`bulkDropHandler` property + one line in `importDroppedFiles`), `EditorView.swift` (drop
  guard accepts folders via `canAcceptDrop`), `SunshotApplication.swift` (creates the `BulkSession`, adds the strip
  as a bottom inset and `BulkCommands`).

## S11 implementation notes (2026-11-17)
- **Content is an image or a snippet, never both.** `EditorDocument.snippet: CodeSnippet?` sits next to `content`;
  New Code Snippet clears the image and importing/pasting an image clears the snippet ("Replace Image"); Clear
  Content clears both. The style (backdrop, border, shadow, canvas, export) is kept across the switch.
  `EditorDocument.contentPixelSize` is the one place that answers "how big is the content" for both kinds.
- **One render path, one hook.** `Renderer.render(document:)` sends snippet documents to
  `Renderer.render(project:snippet:)`, which lays the snippet out at 1× (that size drives the canvas layout) and
  draws it at `scale × styleScale`, then calls the normal `render(project:content:contentSize:)`. The only change
  to the image path is the optional `contentSize` (defaults to the image's pixel size), so existing output is
  byte-identical. The code is therefore always drawn at output density: 2×, 4K and an exact canvas that scales
  the content up all get sharp text.
- **Model is Codable with tolerant decoding** (for S7): every key optional, unknown language = auto-detect,
  unknown theme id renders with the default theme, unknown keys ignored; font size 8…48 and padding 0…120 are
  clamped on every write. `fontName` is a PostScript name (nil = Menlo) so S5's code-font token can drive it.
- **Font: Menlo**, not the system monospaced font: it is always installed, has stable metrics (snapshots), and
  `CTFontCreateWithName` silently substitutes Helvetica for missing names — so a missing `fontName` is detected by
  comparing PostScript names and falls back to Menlo. The title row uses the system UI font.
- **Highlighter:** a single-pass scanner over UTF-16 code units driven by per-language grammar data
  (`CodeGrammar`), plus a small HTML/XML scanner. Tokens are UTF-16 ranges (what CoreText/AppKit index by) and only
  ever split at ASCII characters, so surrogate pairs are never cut (fuzz-tested). Unterminated strings stop at the
  end of the line; unterminated block comments and multi-line strings run to the end. No regexes, no dependencies.
  Known simplifications: no nested string interpolation colouring, no embedded CSS/JS inside HTML, no heredocs.
- **Auto-detect** is a weighted substring-signal table (first 4,000 characters) plus a real `JSONSerialization`
  parse for JSON and a prefix check for markup; ties or scores under 3 give Plain text. TypeScript borrows
  JavaScript's signals once it has its own, so typed JS is TypeScript and plain JS stays JavaScript.
- **Themes are data**, four Sunshot-own themes: Daybreak (default, light, warm), Porcelain (light, cool),
  Midnight (dark navy), Ember (dark warm). Tests enforce WCAG contrast: text ≥ 4.5:1 (also on the highlight band),
  every token colour ≥ 3:1, line numbers ≥ 2.5:1.
- **Layout:** line height = round(1.5 × font size), title row = round(2.4 × font size), gutter = digits (≥ 2) ×
  column advance + one line height, minimum text width 24 columns, tabs = 4 spaces, CRLF/CR = LF.
- **Undo:** each inspector change is one named step; typing and the title field go through
  `performContinuous` so a run of keystrokes is one "Typing" step, closed after 1 s idle or by any other edit,
  undo or redo. The editor's `NSTextView` has its own undo off so ⌘Z always reaches the document's stack.
- **Editor panel** is an `NSTextView` (not `TextEditor`) so smart quotes/dashes, text replacement, spelling and
  link detection can all be switched off — code must stay exactly as typed. It shows plain monospaced text;
  colours are in the preview.
- **New Code Snippet is ⌥⌘N** (⌘N is reserved for S7's File ▸ New). Export file names use `{TEMPLATE}` = `code`.
- **Not in S11** (recorded in the acceptance open questions): ⌥-click a preview line to highlight it, diff
  highlighting, Format Code. Lines are highlighted from the inspector field ("2, 4-6").
- **Measured (release, M-series, machine load ~27 from parallel agents):** 500-line snippet highlight + 1× render
  104 ms (budget 150); 300-line snippet at 2× 279 ms (budget 400). A 500-line snippet at 2× is ~23,000 px tall,
  over the 16384 px export limit, so the 2× budget uses 300 lines. Earlier runs under heavier load reached 172 /
  471 ms; budgets were not loosened.
