#!/bin/bash
# Build cl_quick and install it into /Applications.
#   ./build.sh               build, install, open it
#   ./build.sh --no-install  build into ./build only
# One small program: a menu bar app (no Dock icon), signed ad hoc, as released too
# (scripts/release.sh packages the app this builds; there is no Developer ID or notarization yet).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
out="$here/build"
name="cl_quick"
dest="/Applications"
install=1
[ "${1:-}" = "--no-install" ] && install=0
# YY.M.R from VERSION; the build number counts commits, so it only grows.
version="$(tr -d '[:space:]' < "$here/VERSION")"
build="$(git -C "$here" rev-list --count HEAD 2>/dev/null || echo 1)"

rm -rf "$out"; mkdir -p "$out"
echo "compiling…"
swiftc -O -swift-version 5 -target arm64-apple-macos13.0 -o "$out/$name" "$here"/Sources/*.swift \
  -framework AppKit -framework SwiftUI -framework Carbon -framework ServiceManagement

app="$out/$name.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$out/$name" "$app/Contents/MacOS/$name"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>local.n-uf.cl-quick</string>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundleDisplayName</key><string>$name</string>
  <key>CFBundleExecutable</key><string>$name</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$build</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$app" 2>/dev/null
echo "built $name $version ($build), $(du -sh "$app" | cut -f1)"

if [ "$install" = 1 ]; then
  pkill -f "$dest/$name.app/Contents/MacOS/$name" 2>/dev/null || true
  sleep 0.5
  rm -rf "$dest/$name.app"
  ditto "$app" "$dest/$name.app"
  echo "installed $dest/$name.app"
  open "$dest/$name.app"
fi
