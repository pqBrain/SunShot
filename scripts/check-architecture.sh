#!/usr/bin/env bash
# Enforces module layering: each target may only import its allow-listed modules.
source "$(dirname "$0")/lib/common.sh"
cd "$ROOT"

violations=0
for module in $(jq -r '.allowedImports | keys[]' "$QUALITY"); do
  allowed="$(jq -r --arg m "$module" '.allowedImports[$m][]' "$QUALITY")"
  while IFS=: read -r file line text; do
    [[ -z "$file" ]] && continue
    imported="$(echo "$text" | sed -E 's/^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*((public|internal|package|private|fileprivate)[[:space:]]+)?import[[:space:]]+(struct |class |enum |func |protocol |typealias |var |let )?([A-Za-z_][A-Za-z0-9_]*).*/\5/')"
    if ! grep -qx "$imported" <<<"$allowed"; then
      echo "$file:$line: $module may not import $imported (allowed: $(tr '\n' ' ' <<<"$allowed"))"
      violations=$((violations + 1))
    fi
  done < <(grep -rnE --include='*.swift' '^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*((public|internal|package|private|fileprivate)[[:space:]]+)?import[[:space:]]' "Sources/$module" || true)
done

# Tests must not reach into the app target (keep logic in Core/Render where it is testable).
if grep -rnE --include='*.swift' 'import[[:space:]]+SunshotApp' Tests; then
  echo "Tests must not import SunshotApp — move logic into SunshotCore/SunshotRender"
  violations=$((violations + 1))
fi

if (( violations > 0 )); then fail "architecture: $violations violation(s)"; exit 1; fi
echo "architecture: layering respected"
