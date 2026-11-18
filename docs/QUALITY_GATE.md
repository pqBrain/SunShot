# Quality gate

`make gate` (= `scripts/gate.sh`) is the single definition of "shippable". The pre-push hook runs exactly this;
CI runs a subset (see below).
Logs per stage: `.build/gate/<stage>.log`; summary: `.build/gate/report.md` / `report.json`.

| # | Stage | Checks | Fails when |
|---|---|---|---|
| 1 | toolchain | swift 6, swift-format, jq, python3, codesign, sips | a tool is missing |
| 2 | format | `swift format lint --strict` with `.swift-format` | any formatting/lint rule (incl. force unwrap/try, IUO) |
| 3 | hygiene | `scripts/check-hygiene.sh` | `try!`, `as!`, `print`, `NSLog`, `fatalError`, `main.sync`, slice-less TODO, unjustified `@unchecked Sendable`, file > 400 lines, banned brand terms, binary images under `Sources/**/Resources` (S3: wallpapers are generated recipes) |
| 4 | architecture | `scripts/check-architecture.sh` | a module imports outside its allow-list; tests import the app target |
| 5 | build | debug build + tests, warnings as errors, Swift 6 strict concurrency | any warning or error |
| 6 | test | Swift Testing unit + snapshot tests | any failing test or snapshot pixel diff (> 0.1% of pixels beyond ±2/255) |
| 7 | coverage | `scripts/check-coverage.py` per module | Core < 90% or Render < 85% line coverage |
| 8 | traceability | `scripts/check-traceability.py` | a `Done` slice has an AC with no citing test / unticked manual AC; a test cites an unknown AC; malformed AC file |
| 9 | bundle | release `.app`, Info.plist lint, ad-hoc sign with sandbox entitlements, `codesign --verify` | build/sign fails or app > 10 MB |
| 10 | smoke | sandboxed app renders a sample headlessly (`--smoke-test`), image size verified; with `CI` or `SUNSHOT_GATE_LAUNCH=1` also launches the GUI and checks it stays up | crash, timeout, wrong output |
| 11 | perf | release-mode perf tests (`SUNSHOT_PERF=1`, run serially so memory peaks are not mixed) | 4K export median > 500 ms, 6K PNG export median > 1 s, memory over budget |

`make gate-fast` (pre-commit) runs stages 1–6.

## CI runs a subset
`make gate-ci` (= `scripts/gate.sh --ci`) is what GitHub Actions runs, on macOS 26 with Xcode 26.6: Sunshot's
oldest supported macOS and the newest toolchain GitHub offers. Stages: toolchain, format, hygiene, architecture,
build, **coretest** (the Foundation-only `SunshotCoreTests`), traceability and **release** (an optimised build of
the app, which can fail where the debug build compiles).

Rendering, snapshot, video, WebKit, coverage, bundle, smoke and perf stay local: GitHub's macOS runners are 3-core
VMs with no GPU or hardware video encoder. Every one of those tests passes there when run alone, but the parallel
run never finishes, and snapshots drift with the OS's antialiasing. CI catches what only works on your machine
(uncommitted files, a newer compiler, the macOS 26 SDK); the pre-push hook catches the rest. Never push with
`--no-verify`: nothing else runs the full gate.

## The gate is tested too
`make gate-selftest` copies the repo to a scratch dir, plants 18 known defects one at a time (bad format, `try!`,
`print`, slice-less TODO, competitor brand, AppKit in Core, compiler warning, failing test, visual regression,
coverage drop, untested `Done` AC, second drawing path, view-held document copy, unknown AC id, oversized app,
shipped image in Resources, malformed canvas preset JSON, unknown token in the default file-name template) and asserts each is caught **for the right
reason**. Run it locally after changing the gate. Add a case whenever you add a rule.

## Changing thresholds
All budgets live in `scripts/quality.json`. Lowering coverage or raising size/perf budgets needs a reason in the
commit message and the delivery lead's review.
