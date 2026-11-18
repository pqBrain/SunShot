#!/usr/bin/env bash
# Temporary CI diagnostic: runs each test matching $1 on its own with a time limit, and samples the stacks of any
# test that does not finish. Remove once the CI test hang is understood.
set -uo pipefail
# Usage: diagnose-hang.sh <regex> [seconds]            each matching test alone
#        diagnose-hang.sh --together <regex|.> [seconds]  all matching tests in one parallel run, like the gate
together=0
[[ "${1:-}" == "--together" ]] && { together=1; shift; }
pattern="${1:?suite regex}"
limit="${2:-180}"
out=".build/diag"
mkdir -p "$out"
swift build --build-tests -Xswiftc -warnings-as-errors >/dev/null || exit 1

sample_stuck() {
  for p in $(pgrep -f 'PackageTests|swiftpm-testing-helper'); do
    sample "$p" 3 -file "$out/sample-$p.txt" >/dev/null 2>&1
    echo "----- stacks of $p ($(ps -o comm= -p "$p")) -----"
    grep -E '^ *[+!:|]' "$out/sample-$p.txt" | grep -E 'Sunshot|AVAsset|AVFoundation|VideoToolbox|VT[A-Z]|WebKit|WK|semaphore|dispatch_sync|_dispatch_|swift_task|Task|CI[A-Z]|Metal|MTL' | sort | uniq -c | sort -rn | head -40
  done
}

if (( together )); then
  start=$(date +%s)
  swift test --skip-build --parallel --filter "$pattern" > "$out/run.log" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null && (( $(date +%s) - start < limit )); do sleep 5; done
  if kill -0 "$pid" 2>/dev/null; then
    echo "TIMEOUT after ${limit}s running /$pattern/ in parallel; tests started but not finished:"
    python3 - "$out/run.log" <<'PY'
import re, sys
started, done = [], set()
for line in open(sys.argv[1], errors="replace"):
    m = re.match(r'◇ Test (?:case passing .* to )?"(.*?)" started', line)
    if m: started.append(m.group(1))
    m = re.match(r'[✔✘] Test "(.*?)" (passed|failed)', line)
    if m: done.add(m.group(1))
for name in dict.fromkeys(started):
    if name not in done: print("  ", name)
PY
    sample_stuck
    pkill -9 -f 'PackageTests|swiftpm-testing-helper'; kill -9 "$pid" 2>/dev/null
  else
    wait "$pid"; echo "finished in $(( $(date +%s) - start ))s, exit $?"
    grep -E '✘|↳|Test run with' "$out/run.log" | head -20
  fi
  exit 0
fi
swift test list --skip-build 2>/dev/null | grep -E "$pattern" > "$out/tests.txt"
echo "$(wc -l < "$out/tests.txt") tests match /$pattern/"
while IFS= read -r test; do
  filter="${test%()}"  # Swift Testing ids end in "()"; anchors and escaped parens match nothing
  start=$(date +%s)
  swift test --skip-build --no-parallel --filter "$filter" > "$out/run.log" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null && (( $(date +%s) - start < limit )); do sleep 2; done
  elapsed=$(( $(date +%s) - start ))
  if kill -0 "$pid" 2>/dev/null; then
    echo "TIMEOUT ${elapsed}s  $test"
    sample_stuck
    pkill -9 -f 'PackageTests|swiftpm-testing-helper'; kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  else
    wait "$pid"; status=$?
    result=$([ $status -eq 0 ] && echo PASS || echo "FAIL($status)")
    grep -q 'Test run with 1 test' "$out/run.log" || result="$result(ran $(grep -o 'Test run with [0-9]* tests\{0,1\}' "$out/run.log" | grep -o '[0-9]*' || echo 0))"
    echo "$result ${elapsed}s  $test"
    [ $status -ne 0 ] && grep -E '✘|↳|error' "$out/run.log" | head -8
  fi
done < "$out/tests.txt"
