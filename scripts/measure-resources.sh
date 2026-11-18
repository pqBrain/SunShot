#!/usr/bin/env bash
# Measures a running Sunshot's CPU and memory: idle CPU (CPU time used over a window), physical footprint (what
# Activity Monitor's Memory column shows), its peak, and thread count.
#
#   measure-resources.sh [--pid PID] [--seconds N] [--enforce]   one sample; --enforce checks quality.json budgets
#   measure-resources.sh [--pid PID] --watch [--seconds N]       print a sample every N seconds until Ctrl-C
#
# Without --pid it measures the newest running Sunshot. Writes .build/gate/resources.json for the last sample.
source "$(dirname "$0")/lib/common.sh"

pid="" seconds="" enforce=0 watch=0
while (($#)); do
  case "$1" in
    --pid) pid="$2"; shift ;;
    --seconds) seconds="$2"; shift ;;
    --enforce) enforce=1 ;;
    --watch) watch=1 ;;
    *) fail "unknown argument: $1"; exit 2 ;;
  esac
  shift
done
seconds="${seconds:-$(q .idleSampleSeconds)}"
pid="${pid:-$(pgrep -n -x Sunshot || true)}"
[[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null || { fail "no running Sunshot (pass --pid)"; exit 1; }

# CPU time used so far, in seconds ("[[dd-]hh:]mm:ss.cc" from ps).
cpu_seconds() {
  ps -o time= -p "$1" | awk '{
    n = split($1, part, /[-:]/); s = 0
    for (i = 1; i <= n; i++) s = s * 60 + part[i]
    print s
  }'
}

# "<footprint> <peak>" in MB, from vmmap's summary ("Physical footprint: 242.6M", "... (peak): 1.3G").
footprint_mb() {
  vmmap --summary "$1" 2>/dev/null | awk '
    function mb(v,   u, n) { u = substr(v, length(v)); n = v + 0
      return u == "K" ? n / 1024 : (u == "G" ? n * 1024 : (u == "M" ? n : n / 1048576)) }
    /^Physical footprint:/ { now = mb($3) }
    /^Physical footprint \(peak\):/ { peak = mb($4) }
    END { printf "%.0f %.0f\n", now, peak }'
}

sample() {
  local t0 t1 cpu mem peak threads
  t0="$(cpu_seconds "$pid")"
  sleep "$seconds"
  kill -0 "$pid" 2>/dev/null || { fail "Sunshot ($pid) exited while being measured"; exit 1; }
  t1="$(cpu_seconds "$pid")"
  cpu="$(awk -v a="$t0" -v b="$t1" -v s="$seconds" 'BEGIN { printf "%.2f", (b - a) / s * 100 }')"
  read -r mem peak < <(footprint_mb "$pid")
  threads="$(ps -M -p "$pid" | tail -n +2 | wc -l | tr -d ' ')"
  printf '{"pid": %s, "idleCpuPercent": %s, "footprintMB": %s, "peakFootprintMB": %s, "threads": %s}\n' \
    "$pid" "$cpu" "${mem:-0}" "${peak:-0}" "$threads" | tee "$GATE_DIR/resources.json"
}

if ((watch)); then
  info "watching Sunshot ($pid) every ${seconds}s — Ctrl-C to stop"
  while kill -0 "$pid" 2>/dev/null; do sample; done
  exit 0
fi

sample >/dev/null
read -r cpu mem < <(jq -r '"\(.idleCpuPercent) \(.footprintMB)"' "$GATE_DIR/resources.json")
cpu_budget="$(q .idleCpuBudgetPercent)"
mem_budget="$(q .idleFootprintBudgetMB)"
echo "resources: idle CPU ${cpu}% (budget ${cpu_budget}%), footprint ${mem} MB (budget ${mem_budget} MB)"
if ((enforce)); then
  status=0
  awk -v v="$cpu" -v b="$cpu_budget" 'BEGIN { exit !(v > b) }' && { fail "idle CPU ${cpu}% exceeds ${cpu_budget}%"; status=1; }
  ((mem > mem_budget)) && { fail "idle footprint ${mem} MB exceeds ${mem_budget} MB"; status=1; }
  exit "$status"
fi
