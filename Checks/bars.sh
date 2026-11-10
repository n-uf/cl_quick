#!/usr/bin/env bash
# The model and thinking controls' checks (a bar per family; picking any value moves nothing; a click on a bar's centre
# picks it; the scroll wheel steps): the whole app but its main.swift, and Checks/bars/main.swift in its place. No mouse,
# no event posting, nothing outside build/ written.
#   Checks/bars.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
out="$repo/build/checks"
mkdir -p "$out"
sources=()
for f in "$repo"/Sources/*.swift; do [ "$(basename "$f")" = main.swift ] || sources+=("$f"); done
swiftc -swift-version 5 -target arm64-apple-macos13.0 -o "$out/bars" "${sources[@]}" "$here/quiet.swift" "$here/bars/main.swift" \
  -framework AppKit -framework SwiftUI -framework Carbon -framework ServiceManagement
"$out/bars"
