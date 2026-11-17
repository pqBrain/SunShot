#!/usr/bin/env bash
# Source hygiene rules that swift-format doesn't cover. Fails with file:line for each violation.
source "$(dirname "$0")/lib/common.sh"
cd "$ROOT"

violations=0
report() { echo "$1: $2"; violations=$((violations + 1)); }

check_pattern() { # <regex> <message> <paths...>
  local regex="$1" message="$2"; shift 2
  while IFS= read -r hit; do
    [[ -n "$hit" ]] && report "${hit%%:[[:space:]]*}" "$message"
  done < <(grep -rnE --include='*.swift' "$regex" "$@" 2>/dev/null | grep -vE 'hygiene:allow' | cut -d: -f1,2 || true)
}

check_pattern '(^|[^A-Za-z_])try!' 'force try (try!) is not allowed' Sources
check_pattern '[^A-Za-z_?]as! ' 'force cast (as!) is not allowed' Sources
check_pattern '(^|[^A-Za-z_])print\(' 'print() in production code — use os.Logger' Sources
check_pattern '(^|[^A-Za-z_])NSLog\(' 'NSLog in production code — use os.Logger' Sources
check_pattern '(^|[^A-Za-z_])fatalError\(' 'fatalError in production code — throw or handle (mark "hygiene:allow" with reason if truly unreachable)' Sources
check_pattern 'DispatchQueue\.main\.sync' 'DispatchQueue.main.sync can deadlock' Sources
# TODO/FIXME must reference a slice: TODO(S3): …
while IFS= read -r hit; do
  [[ -n "$hit" ]] && report "$(cut -d: -f1,2 <<<"$hit")" 'TODO/FIXME must reference a slice, e.g. TODO(S3): …'
done < <(grep -rnE --include='*.swift' '(TODO|FIXME)' Sources Tests 2>/dev/null | grep -vE '(TODO|FIXME)\(S[0-9]+\)' || true)

# @unchecked Sendable needs a SAFETY justification on the line above.
while IFS=: read -r file line _; do
  [[ -z "$file" ]] && continue
  prev=$((line - 1))
  if ! sed -n "${prev}p" "$file" | grep -q 'SAFETY:'; then
    report "$file:$line" '@unchecked Sendable requires a "// SAFETY:" comment on the line above'
  fi
done < <(grep -rnE --include='*.swift' '@unchecked Sendable' Sources || true)

# File length budget.
max_lines="$(q .maxSourceFileLines)"
while IFS= read -r file; do
  lines=$(wc -l < "$file" | tr -d ' ')
  (( lines > max_lines )) && report "$file:$lines" "file exceeds $max_lines lines — split it"
done < <(find Sources Tests -name '*.swift')

# Brand guard: this is not a clone. No competitor names in code, tests, resources or user-facing docs.
while IFS= read -r term; do
  while IFS= read -r hit; do
    [[ -n "$hit" ]] && report "$hit" "banned term \"$term\" (Sunshot has its own brand)"
  done < <(grep -rniIl -- "$term" Sources Tests Support 2>/dev/null || true)
done < <(q '.bannedTerms[]')

# Backdrop provenance: bundled resources are text recipes only. No photos or third-party images ship with
# Sunshot (wallpapers are generated from JSON), so any binary image under a Resources folder is rejected.
while IFS= read -r file; do
  [[ -n "$file" ]] && report "$file" "binary image in bundled resources: wallpapers must be generated recipes (JSON), not shipped images"
done < <(find Sources -path '*/Resources/*' -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \
  -o -iname '*.heic' -o -iname '*.heif' -o -iname '*.gif' -o -iname '*.tif' -o -iname '*.tiff' -o -iname '*.webp' \
  -o -iname '*.bmp' -o -iname '*.avif' -o -iname '*.psd' \) 2>/dev/null)

if (( violations > 0 )); then
  fail "hygiene: $violations violation(s)"; exit 1
fi
echo "hygiene: clean"
