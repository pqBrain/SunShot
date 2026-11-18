#!/usr/bin/env bash
# Builds a release Sunshot.app into dist/, signs it (sandboxed) and enforces the size budget.
source "$(dirname "$0")/lib/common.sh"
cd "$ROOT"

swift build -c release --product Sunshot -Xswiftc -warnings-as-errors
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$ROOT/dist/Sunshot.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/Sunshot" "$APP/Contents/MacOS/Sunshot"
# SwiftPM resource bundles (Bundle.module) live next to the executable's resources.
# Test-target bundles (Sunshot_*Tests.bundle) share the bin dir after `swift test -c release`; never ship them.
find "$BIN_DIR" -maxdepth 1 -name 'Sunshot_*.bundle' ! -name '*Tests.bundle' -exec cp -R {} "$APP/Contents/Resources/" \;
# S17: the app icon is drawn by Sunshot's own code at build time (no artwork is checked in).
scripts/make-app-icon.sh "$APP/Contents/Resources/AppIcon.icns"

VERSION="$(cat VERSION)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Support/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# Full strip (not -x): an executable needs no local or global symbol table at runtime; Swift metadata lives in its
# own sections. Saves ~0.6 MB. Crash logs then show addresses only; keep the unstripped .build binary to symbolicate.
strip "$APP/Contents/MacOS/Sunshot"
# Signing identity: an ad-hoc signature's designated requirement is the binary's cdhash, so macOS privacy grants
# (Screen Recording) are lost on every rebuild. A real certificate keeps the requirement stable across builds.
# Order: $SUNSHOT_SIGN_IDENTITY, then an "Apple Development" or "Sunshot Local Signing" certificate, else ad-hoc.
identity="${SUNSHOT_SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity="$(security find-identity -p codesigning 2>/dev/null \
    | grep -E '"(Apple Development: .*|Sunshot Local Signing)"' | head -1 | awk '{print $2}' || true)"
fi
identity="${identity:--}"
codesign --force --sign "$identity" --options runtime --entitlements Support/Sunshot.entitlements "$APP" >/dev/null
codesign --verify --strict "$APP"
[[ "$identity" == "-" ]] && echo "signed: ad-hoc (Screen Recording permission resets on each rebuild)" \
  || echo "signed: $identity"

size_kb="$(du -sk "$APP" | cut -f1)"
budget_kb="$(q .appSizeBudgetKB)"
echo "app: $APP ($size_kb KB, budget $budget_kb KB, version $VERSION ($BUILD))"
echo "{\"appSizeKB\": $size_kb, \"budgetKB\": $budget_kb}" > "$GATE_DIR/app-size.json"
if (( size_kb > budget_kb )); then fail "app size $size_kb KB exceeds budget $budget_kb KB"; exit 1; fi
