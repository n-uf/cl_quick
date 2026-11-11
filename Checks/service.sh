#!/usr/bin/env bash
# The "Ask cl_quick" Services entry's checks: the built Info.plist declares it (build it first: ./build.sh --no-install),
# and the provider's handler, called directly with a private pasteboard, puts the selection into the field of the quiet
# panel (off every screen, never the keyboard) without sending anything. The whole app but its main.swift, and
# Checks/service/main.swift in its place. No mouse, no event posting, nothing outside build/ written.
#   Checks/service.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
out="$repo/build/checks"
mkdir -p "$out"

plist="$repo/build/cl_quick.app/Contents/Info.plist"
[ -f "$plist" ] || { echo "FAIL no $plist: run ./build.sh --no-install first"; exit 1; }
want() { # key path, expected value
  got="$(plutil -extract "$1" raw -o - "$plist" 2>/dev/null || echo "<missing>")"
  [ "$got" = "$2" ] || { echo "FAIL Info.plist $1 is '$got', not '$2'"; exit 1; }
}
want NSServices.0.NSMenuItem.default "Ask cl_quick"
want NSServices.0.NSMessage askAboutSelection
want NSServices.0.NSPortName cl_quick
want NSServices.0.NSSendTypes.0 NSStringPboardType
want NSServices.0.NSSendTypes.1 public.utf8-plain-text
[ "$(plutil -extract NSServices raw -o - "$plist")" = 1 ] || { echo "FAIL Info.plist NSServices is not one entry"; exit 1; }
if plutil -extract NSServices.0.NSReturnTypes raw -o - "$plist" >/dev/null 2>&1; then echo "FAIL Info.plist: the service must take no return types"; exit 1; fi
want LSUIElement true
echo "service plist checks: passed"

sources=()
for f in "$repo"/Sources/*.swift; do [ "$(basename "$f")" = main.swift ] || sources+=("$f"); done
swiftc -swift-version 5 -target arm64-apple-macos13.0 -o "$out/service" "${sources[@]}" "$here/quiet.swift" "$here/service/main.swift" \
  -framework AppKit -framework SwiftUI -framework Carbon -framework ServiceManagement
chmod +x "$here/stub-claude"
QC_STUB_PATH="$here/stub-claude" "$out/service"
