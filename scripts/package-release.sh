#!/usr/bin/env bash
# S18: packages the release named in VERSION for a GitHub release: builds dist/Sunshot.app (scripts/bundle-app.sh),
# zips it as dist/Sunshot-<version>.zip (ditto keeps the signature and extended attributes) and prints its SHA-256.
# Publishing (tag, GitHub release, upload) is a separate, deliberate step; see docs/RELEASING.md.
source "$(dirname "$0")/lib/common.sh"
cd "$ROOT"

VERSION="$(tr -d '[:space:]' < VERSION)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { fail "VERSION '$VERSION' is not a release version (x.y.z)"; exit 1; }

scripts/bundle-app.sh
APP="$ROOT/dist/Sunshot.app"
shipped="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[[ "$shipped" == "$VERSION" ]] || { fail "bundle says $shipped, VERSION says $VERSION"; exit 1; }

ZIP="$ROOT/dist/Sunshot-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
sha="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo "$sha  $(basename "$ZIP")" > "$ZIP.sha256"
echo "release: $ZIP ($(du -k "$ZIP" | cut -f1) KB)"
echo "sha256:  $sha"
