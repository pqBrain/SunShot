# Shared helpers for gate scripts. Source, don't execute.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE_DIR="$ROOT/.build/gate"
QUALITY="$ROOT/scripts/quality.json"
mkdir -p "$GATE_DIR"

if [[ -t 1 ]]; then
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'; C_OFF=$'\033[0m'
else
  C_RED=""; C_GREEN=""; C_YELLOW=""; C_DIM=""; C_BOLD=""; C_OFF=""
fi

q() { jq -r "$1" "$QUALITY"; }

# run_with_timeout <seconds> <cmd...>
run_with_timeout() { local secs="$1"; shift; perl -e 'alarm shift; exec @ARGV or die "exec: $!"' "$secs" "$@"; }

fail() { echo "${C_RED}✘ $*${C_OFF}" >&2; }
info() { echo "${C_DIM}$*${C_OFF}"; }
