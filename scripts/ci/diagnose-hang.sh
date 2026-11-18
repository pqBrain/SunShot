#!/usr/bin/env bash
# Temporary CI diagnostic: runs each test matching $1 on its own with a time limit, and samples the stacks of any
# test that does not finish. Remove once the CI test hang is understood.
set -uo pipefail
pattern="${1:?suite regex}"
limit="${2:-180}"
out=".build/diag"
mkdir -p "$out"
swift build --build-tests -Xswiftc -warnings-as-errors >/dev/null || exit 1
swift test list --skip-build 2>/dev/null | grep -E "$pattern" > "$out/tests.txt"
echo "$(wc -l < "$out/tests.txt") tests match /$pattern/"
while IFS= read -r test; do
  filter="$(printf '%s' "$test" | sed -e 's/[][()\.*+?^$|{}]/\\&/g')"
  start=$(date +%s)
  swift test --skip-build --no-parallel --filter "^${filter}\$" > "$out/run.log" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null && (( $(date +%s) - start < limit )); do sleep 2; done
  elapsed=$(( $(date +%s) - start ))
  if kill -0 "$pid" 2>/dev/null; then
    echo "TIMEOUT ${elapsed}s  $test"
    for p in $(pgrep -f 'PackageTests|swiftpm-testing-helper'); do
      sample "$p" 3 -file "$out/sample-$p.txt" >/dev/null 2>&1
      echo "----- stacks of $p ($(ps -o comm= -p "$p")) -----"
      grep -E '^ *[+!:|]' "$out/sample-$p.txt" | grep -E 'Sunshot|AVAsset|AVFoundation|VideoToolbox|VT[A-Z]|WebKit|WK|semaphore|dispatch_sync|_dispatch_|swift_task|Task|CI[A-Z]|Metal|MTL' | sort | uniq -c | sort -rn | head -40
    done
    pkill -9 -f 'PackageTests|swiftpm-testing-helper'; kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  else
    wait "$pid"; status=$?
    result=$([ $status -eq 0 ] && echo PASS || echo "FAIL($status)")
    echo "$result ${elapsed}s  $test"
    [ $status -ne 0 ] && grep -E '✘|↳|error' "$out/run.log" | head -8
  fi
done < "$out/tests.txt"
