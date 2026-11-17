#!/usr/bin/env bash
# Sunshot quality gate. One command, every check, a clear verdict.
#
#   scripts/gate.sh             full gate (what CI and pre-push run)
#   scripts/gate.sh --fast      pre-commit subset: toolchain, format, hygiene, architecture, build, test
#   scripts/gate.sh <stage>...  run named stages only
#
# Stages run in order; a stage whose prerequisite failed is skipped. Logs: .build/gate/<stage>.log
# Summary: .build/gate/report.md and report.json. Exit code is non-zero if any stage failed.
source "$(dirname "$0")/lib/common.sh"
cd "$ROOT"

ALL_STAGES=(toolchain format hygiene architecture build test coverage traceability bundle smoke perf)
FAST_STAGES=(toolchain format hygiene architecture build test)
# Prerequisites (bash 3.2 compatible — no associative arrays on stock macOS).
needs() { case "$1" in test) echo build ;; coverage) echo test ;; smoke) echo bundle ;; perf) echo build ;; *) echo "" ;; esac; }
set_result() { echo "$2" >"$GATE_DIR/.result.$1"; echo "$3" >"$GATE_DIR/.seconds.$1"; }
result_of() { cat "$GATE_DIR/.result.$1" 2>/dev/null || echo ""; }
seconds_of() { cat "$GATE_DIR/.seconds.$1" 2>/dev/null || echo 0; }

stage_toolchain() {
  for tool in swift xcrun jq python3 codesign sips perl; do
    command -v "$tool" >/dev/null || { echo "missing tool: $tool"; return 1; }
  done
  swift --version 2>&1 | head -1
  swift format --version >/dev/null 2>&1 || { echo "swift format unavailable (needs Swift 6 toolchain)"; return 1; }
  echo "swift-format $(swift format --version)"
}

stage_format() {
  swift format lint --strict --recursive --parallel Package.swift Sources Tests
}

stage_hygiene() { bash scripts/check-hygiene.sh; }
stage_architecture() { bash scripts/check-architecture.sh; }

stage_build() {
  # Same flags as the test stage so the test stage's build is a no-op.
  swift build --build-tests --enable-code-coverage -Xswiftc -warnings-as-errors
}

stage_test() {
  rm -f "$(swift build --show-bin-path)"/codecov/*.profraw
  swift test --enable-code-coverage --parallel -Xswiftc -warnings-as-errors 2>&1 | tee "$GATE_DIR/test-output.log" | grep -E '✘|↳|Test run with|error:' || true
  # swift test's exit status is lost in the pipe; derive it from the output instead.
  ! grep -qE '✘|error:' "$GATE_DIR/test-output.log" && grep -q 'Test run with' "$GATE_DIR/test-output.log"
}

stage_coverage() {
  local bin profdata args="" bundle
  bin="$(swift build --show-bin-path)"
  profdata="$GATE_DIR/coverage.profdata"
  xcrun llvm-profdata merge -sparse "$bin"/codecov/*.profraw -o "$profdata"
  for bundle in "$bin"/*Tests.xctest; do
    # First binary is positional, the rest are passed with -object.
    [[ -n "$args" ]] && args="$args -object"
    args="$args $bundle/Contents/MacOS/$(basename "$bundle" .xctest)"
  done
  # shellcheck disable=SC2086  # intentional word splitting of the object list
  xcrun llvm-cov export -summary-only -instr-profile "$profdata" $args >"$GATE_DIR/coverage.json"
  python3 -I scripts/check-coverage.py "$GATE_DIR/coverage.json" "$QUALITY" "$GATE_DIR/coverage.md"
}

stage_traceability() { python3 -I scripts/check-traceability.py "$ROOT"; }
stage_bundle() { bash scripts/bundle-app.sh; }

stage_smoke() {
  if [[ -n "${CI:-}" || "${SUNSHOT_GATE_LAUNCH:-}" == "1" ]]; then
    bash scripts/smoke-test.sh --launch
  else
    bash scripts/smoke-test.sh
  fi
}

stage_perf() {
  SUNSHOT_PERF=1 swift test -c release --no-parallel --filter RenderPerformanceTests 2>&1 | tee "$GATE_DIR/perf-output.log" \
    | grep -E 'perf\.|✘|↳|Test run with|error:' || true
  ! grep -qE '✘|error:' "$GATE_DIR/perf-output.log" && grep -q 'passed' "$GATE_DIR/perf-output.log"
}

# ---------------------------------------------------------------------------
stages=()
case "${1:-}" in
  "") stages=("${ALL_STAGES[@]}") ;;
  --fast) stages=("${FAST_STAGES[@]}") ;;
  *) stages=("$@") ;;
esac

overall=0
rm -f "$GATE_DIR"/.result.* "$GATE_DIR"/.seconds.*
echo "${C_BOLD}Sunshot quality gate${C_OFF} — ${stages[*]}"
for stage in "${stages[@]}"; do
  if ! declare -F "stage_$stage" >/dev/null; then fail "unknown stage: $stage (stages: ${ALL_STAGES[*]})"; exit 2; fi
  dep="$(needs "$stage")"
  if [[ -n "$dep" && "$(result_of "$dep")" == "fail" ]]; then
    set_result "$stage" skip 0
    echo "${C_YELLOW}– $stage skipped ($dep failed)${C_OFF}"; continue
  fi
  log="$GATE_DIR/$stage.log"
  start=$(date +%s)
  if ( "stage_$stage" ) >"$log" 2>&1; then result=pass; else result=fail; overall=1; fi
  elapsed=$(( $(date +%s) - start ))
  set_result "$stage" "$result" "$elapsed"
  if [[ "$result" == "pass" ]]; then
    echo "${C_GREEN}✔ $stage${C_OFF} ${C_DIM}(${elapsed}s)${C_OFF}"
  else
    echo "${C_RED}✘ $stage${C_OFF} ${C_DIM}(${elapsed}s) — last lines of $log:${C_OFF}"
    # Failing test expectations first (a broad failure can push them out of the tail), then the tail.
    { grep -E 'recorded an issue' "$log" || true; } | head -12 | sed 's/^/    /'
    grep -vE '^[[:space:]]*$' "$log" | tail -25 | sed 's/^/    /'
  fi
done

{
  echo "# Quality gate report — $(date '+%Y-%m-%d %H:%M:%S') — $(git rev-parse --short HEAD 2>/dev/null || echo 'no commit')"
  echo; echo "| Stage | Result | Seconds |"; echo "|---|---|---|"
  for stage in "${stages[@]}"; do echo "| $stage | $(result_of "$stage") | $(seconds_of "$stage") |"; done
  if [[ -f "$GATE_DIR/coverage.md" && " ${stages[*]} " == *" coverage "* ]]; then
    echo; echo "## Coverage"; echo; cat "$GATE_DIR/coverage.md"
  fi
} >"$GATE_DIR/report.md"
{
  printf '{"passed": %s, "stages": {' "$([[ $overall == 0 ]] && echo true || echo false)"
  sep=""
  for stage in "${stages[@]}"; do
    printf '%s"%s": {"result": "%s", "seconds": %s}' "$sep" "$stage" "$(result_of "$stage")" "$(seconds_of "$stage")"
    sep=", "
  done
  printf '}}\n'
} >"$GATE_DIR/report.json"

if [[ $overall == 0 ]]; then
  echo "${C_GREEN}${C_BOLD}GATE PASSED${C_OFF} ${C_DIM}(report: .build/gate/report.md)${C_OFF}"
else
  echo "${C_RED}${C_BOLD}GATE FAILED${C_OFF} ${C_DIM}(report: .build/gate/report.md)${C_OFF}"
fi
exit $overall
