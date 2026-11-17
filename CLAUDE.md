# Sunshot — engineering conventions

Lightweight native macOS screenshot beautifier. Swift 6, SwiftUI, macOS 26+ (Liquid Glass), zero third-party dependencies.

## Not a clone
`postspark-macos-spec.md` + `ref/` (local-only, gitignored) describe controls that exist in this product category. Use them for *what*
to build, never *how it looks*: Sunshot has its own name, design, copy, defaults, presets and assets. The gate
bans competitor names in `Sources/`, `Tests/`, `Support/`.

## Layout
| Path | What | Rules |
|---|---|---|
| `Sources/SunshotCore` | Document model, layout maths, presets, formatting, undo-able state | Foundation only. Pure, value types, `Sendable`. ≥ 90% line coverage. |
| `Sources/SunshotRender` | The one render function used by preview **and** export | CoreGraphics/CoreImage/ImageIO/AVFoundation. No AppKit/SwiftUI. ≥ 85% coverage. |
| `Sources/SunshotApp` | Thin SwiftUI/AppKit shell | No business logic — if it needs a test, move it to Core/Render. |
| `Tests/*` | Swift Testing (`import Testing`) | Unit + snapshot (`assertSnapshot`) + perf (`SUNSHOT_PERF=1`). |
| `docs/SLICES.md` | Delivery plan + slice status | Gate parses the table. |
| `docs/acceptance/S<n>.md` | Acceptance criteria `S<n>-AC<k>` | Every AC of a `Done` slice must be cited by a test. |
| `docs/qa/S<n>-manual.md` | Tester's manual sign-off `- [x] S<n>-AC<k>` | Required for `Test level: manual` ACs. |
| `scripts/quality.json` | All gate thresholds/budgets | Raising a budget needs a reason in the commit message. |

## Workflow per slice
1. Slice → `In progress` in `docs/SLICES.md`; ACs exist in `docs/acceptance/S<n>.md`.
2. Build model → renderer → UI, test-first where practical. Name tests with the AC they prove:
   `@Test("[S1-AC3] export PNG matches canvas size × scale")`.
3. `make gate` green (it runs on pre-push and CI anyway; `make setup` installs hooks).
4. Principal Tester verifies, ticks manual ACs in `docs/qa/S<n>-manual.md`.
5. Slice → `Done` (the gate now enforces full AC traceability for it).

## Code rules (gate-enforced)
- Warnings are errors. Swift 6 language mode, strict concurrency, `ExistentialAny`, `InternalImportsByDefault`,
  `MemberImportVisibility`.
- `swift format` (`.swift-format`) — run `make format`. No force unwrap / `try!` / `as!` / IUO.
- No `print`/`NSLog`/`fatalError` in Sources (use `os.Logger`; throw instead of crashing).
- `TODO(S<n>):` must name a slice. `@unchecked Sendable` needs a `// SAFETY:` line above it.
- Files ≤ 400 lines. Module imports restricted per `scripts/quality.json`.
- Every model mutation goes through the document store so it is undoable.
- Preview and export call the same `Renderer.render` — never a second drawing path.

## Snapshots
References live in `Tests/SunshotRenderTests/__Snapshots__`. A missing reference is recorded **and fails** the
test; re-run to pass. `make snapshots-record` re-records all — review the PNG diff before committing. CI never
records. On mismatch, `<name>.failure.png` and `<name>.diff.png` are written next to the reference.

## Commands
`make help` · `make gate` · `make gate-fast` · `make gate-selftest` · `make format` · `make test` · `make run`
