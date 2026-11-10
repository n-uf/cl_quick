#!/usr/bin/env bash
# The panel's checks (a move never changes the size; fit() stays out during a move or a live resize): the whole app but its
# main.swift, and Checks/panel/main.swift in its place. No mouse, no event posting, nothing outside build/ written.
#   Checks/panel.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
out="$repo/build/checks"
mkdir -p "$out"
sources=()
for f in "$repo"/Sources/*.swift; do [ "$(basename "$f")" = main.swift ] || sources+=("$f"); done
swiftc -swift-version 5 -target arm64-apple-macos13.0 -o "$out/panel" "${sources[@]}" "$here/quiet.swift" "$here/panel/main.swift" \
  -framework AppKit -framework SwiftUI -framework Carbon -framework ServiceManagement
"$out/panel"
