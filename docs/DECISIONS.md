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
