#!/usr/bin/env bash
# Smoke tests the bundled app: (1) headless render via --smoke-test, (2) optional real GUI launch.
# Usage: smoke-test.sh [--launch]
source "$(dirname "$0")/lib/common.sh"
cd "$ROOT"

APP="$ROOT/dist/Sunshot.app"
EXE="$APP/Contents/MacOS/Sunshot"
[[ -x "$EXE" ]] || { fail "no app bundle — run scripts/bundle-app.sh"; exit 1; }

# The app is sandboxed: it renders into its own container temp dir, which macOS (App Data protection) won't
# let a shell read, so it also streams the PNG over stdout as `smoke-test png <base64>`.
output="$(run_with_timeout "$(q .smokeTimeoutSeconds)" "$EXE" --smoke-test)"
grep -v '^smoke-test png ' <<<"$output"
OUT="$GATE_DIR/smoke.png"
rm -f "$OUT"
sed -nE 's/^smoke-test png (.+)$/\1/p' <<<"$output" | base64 -D -o "$OUT" || true
grep -qE '^smoke-test ok [0-9]+x[0-9]+ ' <<<"$output" && [[ -s "$OUT" ]] || { fail "smoke test produced no image"; exit 1; }
expected="$(sed -nE 's/^smoke-test ok ([0-9]+)x([0-9]+) .*$/\1 \2/p' <<<"$output")"
actual="$(sips -g pixelWidth -g pixelHeight "$OUT" | awk '/pixelWidth/{w=$2}/pixelHeight/{h=$2}END{print w" "h}')"
[[ -n "$expected" && "$expected" == "$actual" ]] || { fail "smoke image size '$actual' != reported '$expected'"; exit 1; }
echo "smoke: headless render ok ($actual)"

if [[ "${1:-}" == "--launch" ]]; then
  secs="$(q .launchCheckSeconds)"
  "$EXE" >"$GATE_DIR/launch.log" 2>&1 &
  pid=$!
  sleep "$secs"
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid"; wait "$pid" 2>/dev/null || true
    echo "smoke: GUI launched and stayed up for ${secs}s"
  else
    wait "$pid"; code=$?
    fail "GUI exited early with code $code"; cat "$GATE_DIR/launch.log"; exit 1
  fi
fi
