# ADR 0001 — SwiftPM package, three modules, single render path, scripted quality gate

- Status: Accepted (S0)
- Date: 2026-11-17

## Context
Sunshot must stay lightweight, be buildable and verifiable entirely from the command line (for CI and coding
agents), and keep preview and export pixel-identical.

## Decision
1. **SwiftPM, no Xcode project, no third-party dependencies.** The `.app` is assembled by
   `scripts/bundle-app.sh` (Info.plist, resource bundles, ad-hoc signature, App Sandbox). An Xcode project can be
   generated later for App Store distribution without changing module boundaries.
2. **Three modules**: `SunshotCore` (pure model/logic), `SunshotRender` (CoreGraphics/CoreImage),
   `SunshotApp` (thin SwiftUI shell). Layering is enforced by the gate, not by convention.
3. **One render function** (`Renderer.render(project:content:scale:)`) for preview and export. Preview displays
   its output scaled; there is no separate SwiftUI drawing of the composition.
4. **Value-type document** (`Project`): mutations produce new values → undo/redo and snapshot testing are trivial.
5. **Swift Testing** for all tests; image snapshot testing implemented in-repo (pixel diff with tolerance).
6. **Quality gate as a script** (`scripts/gate.sh`) shared by hooks and CI, with its own self-test.
7. **Minimum macOS 26** (raised from 15 in S2 so the UI can use Liquid Glass natively; see DECISIONS.md).

## Consequences
- UI-level automation (XCUITest) is not available with a pure SwiftPM app; mitigated by keeping logic out of
  the app target, headless smoke runs of the real bundle, and manual ACs signed off in `docs/qa/`.
- Snapshot references may need re-recording when Apple changes CoreGraphics antialiasing across OS releases.
