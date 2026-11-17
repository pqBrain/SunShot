#!/usr/bin/env bash
# Builds a release Sunshot.app into dist/, ad-hoc signs it (sandboxed) and enforces the size budget.
source "$(dirname "$0")/lib/common.sh"
cd "$ROOT"

swift build -c release --product Sunshot -Xswiftc -warnings-as-errors
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$ROOT/dist/Sunshot.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/Sunshot" "$APP/Contents/MacOS/Sunshot"
# SwiftPM resource bundles (Bundle.module) live next to the executable's resources.
find "$BIN_DIR" -maxdepth 1 -name 'Sunshot_*.bundle' -exec cp -R {} "$APP/Contents/Resources/" \;

VERSION="$(cat VERSION)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Support/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

strip -x "$APP/Contents/MacOS/Sunshot" 2>/dev/null || true
codesign --force --sign - --options runtime --entitlements Support/Sunshot.entitlements "$APP" >/dev/null
codesign --verify --strict "$APP"

size_kb="$(du -sk "$APP" | cut -f1)"
budget_kb="$(q .appSizeBudgetKB)"
echo "app: $APP ($size_kb KB, budget $budget_kb KB, version $VERSION ($BUILD))"
echo "{\"appSizeKB\": $size_kb, \"budgetKB\": $budget_kb}" > "$GATE_DIR/app-size.json"
if (( size_kb > budget_kb )); then fail "app size $size_kb KB exceeds budget $budget_kb KB"; exit 1; fi
