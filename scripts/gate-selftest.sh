#!/usr/bin/env bash
# Proves the gate has teeth: plants one known defect at a time in a scratch copy of the repo and
# asserts that the responsible stage FAILS. A gate that can't fail is worse than no gate.
source "$(dirname "$0")/lib/common.sh"

WORK="$(mktemp -d /tmp/sunshot-selftest.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
rsync -a --exclude dist --exclude .git "$ROOT/" "$WORK/"
cd "$WORK"
git init -q && git add -A && git -c user.name=selftest -c user.email=selftest@localhost commit -qm base

passed=0; failed=0
expect_fail() { # <name> <stages> <mutation command> <regex the failure output must contain>
  local name="$1" stage="$2" mutation="$3" reason="$4" log
  log="$WORK/.selftest.log"
  git checkout -q -- . && git clean -qfd -e .build
  if ! bash -c "$mutation"; then
    echo "${C_RED}✘ could not plant defect: $name${C_OFF}"; failed=$((failed + 1)); return
  fi
  # shellcheck disable=SC2086  # stage may be a space-separated list
  if bash scripts/gate.sh $stage >"$log" 2>&1; then
    echo "${C_RED}✘ gate MISSED: $name (stage $stage passed)${C_OFF}"; failed=$((failed + 1))
  elif ! grep -qE "$reason" "$log"; then
    echo "${C_RED}✘ failed for the wrong reason: $name (expected /$reason/)${C_OFF}"; tail -15 "$log"
    failed=$((failed + 1))
  else
    echo "${C_GREEN}✔ caught: $name${C_OFF} ${C_DIM}($stage)${C_OFF}"; passed=$((passed + 1))
  fi
}

CORE=Sources/SunshotCore/Model/Project.swift
expect_fail "badly formatted code"            format       "printf 'public  struct   Ugly{let a=1}\n' >> $CORE" "\\[(Spacing|AddLines|LineLength|Indentation|OneVariableDeclarationPerLine)\\]"
expect_fail "force try in production code"    hygiene      "printf 'func boom() { _ = try! String(contentsOfFile: \"x\") }\n' >> $CORE" "force try"
expect_fail "print() in production code"      hygiene      "printf 'func noisy() { print(1) }\n' >> $CORE" "print\\(\\) in production"
expect_fail "TODO without slice reference"    hygiene      "printf '// TODO: later\n' >> $CORE" "must reference a slice"
expect_fail "competitor brand in code"        hygiene      "printf '// Inspired by PostSpark\n' >> $CORE" "banned term"
expect_fail "UI import in Core"               architecture "sed -i '' '1s/^/import AppKit\n/' $CORE" "may not import AppKit"
expect_fail "compiler warning"                build        "printf 'func warn() { var unused = 1 }\n' >> $CORE" "never mutated|never used"
expect_fail "failing unit test"               test         "sed -i '' 's/PixelSize(width: 1200, height: 700)/PixelSize(width: 1, height: 1)/' Tests/SunshotCoreTests/CanvasLayoutTests.swift" "auto canvas adds padding"
expect_fail "visual regression (snapshot)"    test         "sed -i '' 's|red: 237 / 255, green: 237 / 255, blue: 242 / 255|red: 0.2, green: 0.4, blue: 0.9|' Sources/SunshotCore/Model/SunshotDefaults.swift" "Snapshot [a-z0-9-]+ mismatch"
expect_fail "untested code (coverage drop)"   "build test coverage" "python3 -I -c \"
lines = ['public enum Untested {'] + [f'    public static func f{i}(_ x: Int) -> Int {{ x * {i} + {i} }}' for i in range(80)] + ['}']
open('Sources/SunshotCore/Model/Untested.swift', 'w').write(chr(10).join(lines) + chr(10))\"" "SunshotCore .*FAIL"
expect_fail "Done slice with untested AC"     traceability "printf '\n## S1-AC99 — x\nGiven a\nWhen b\nThen c\nTest level: unit\n' >> docs/acceptance/S1.md && sed -i '' -E 's/^(\\| S1 \\|[^|]*\\|) [A-Za-z ]+ \\|/\\1 Done |/' docs/SLICES.md" "S1-AC99 has no test"
expect_fail "second drawing path in the app"  architecture "printf 'import CoreGraphics\nfunc sneaky(_ c: CGContext) { c.fill(.zero) }\n' >> Sources/SunshotApp/Entry.swift" "Drawing APIs are only allowed"
expect_fail "view keeps its own content copy" architecture "printf 'import SwiftUI\nimport CoreGraphics\nstruct Sneaky: View { @State var shot: CGImage? = nil; var body: some View { EmptyView() } }\n' >> Sources/SunshotApp/EditorView.swift" "read document state from EditorModel"
expect_fail "test cites unknown AC id"        traceability "printf '// covers S9-AC99\n' >> Tests/SunshotCoreTests/CanvasLayoutTests.swift" "unknown acceptance criterion S9-AC99"
expect_fail "app over size budget"            bundle       "jq '.appSizeBudgetKB = 1' scripts/quality.json > q.tmp && mv q.tmp scripts/quality.json" "exceeds budget"

echo
if (( failed > 0 )); then fail "gate self-test: $failed defect(s) slipped through, $passed caught"; exit 1; fi
echo "${C_GREEN}${C_BOLD}gate self-test: all $passed planted defects caught${C_OFF}"
