#!/usr/bin/env bash
# The menu bar menu's checks: each profile's block (its words, colours, the address blurred until the pointer is on it,
# no usage for a standby account, "No usage yet"), the items the menu is built from, and the background refresh of old
# numbers against a stand-in `claude` (stub-claude; one at a time, throttled, only `get_usage`). The whole app but its
# main.swift, and Checks/menu/main.swift in its place. No window, no mouse, no real `claude`, no account: sample names
# and example.com addresses; folders under build/ only, nothing written under the user's folders.
#   Checks/menu.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
out="$repo/build/checks"
mkdir -p "$out"
sources=()
for f in "$repo"/Sources/*.swift; do [ "$(basename "$f")" = main.swift ] || sources+=("$f"); done
swiftc -swift-version 5 -target arm64-apple-macos13.0 -o "$out/menu" "${sources[@]}" "$here/menu/main.swift" \
  -framework AppKit -framework SwiftUI -framework Carbon -framework ServiceManagement
chmod +x "$here/stub-claude"
QC_STUB_PATH="$here/stub-claude" QC_WORK="$out/menu-work" "$out/menu"
