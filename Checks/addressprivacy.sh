#!/usr/bin/env bash
# The AddressPrivacy module's own checks (Shared/AddressPrivacy/): the module alone, built as the static library the apps link
# (Swift 5, macOS 13, no other module of ours), and Checks/addressprivacy/main.swift against it. No app code, no window, no
# mouse, no keyboard, no real account: sample example.com addresses; nothing is written but build/.
#   Checks/addressprivacy.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
out="$repo/build/checks"
mkdir -p "$out"
. "$repo/scripts/modules.sh"
build_address_privacy "$out/modules-addressprivacy" -Onone
swiftc -swift-version 5 -target arm64-apple-macos13.0 -o "$out/addressprivacy" "$here/addressprivacy/main.swift" \
  -I "$out/modules-addressprivacy" -L "$out/modules-addressprivacy" -lAddressPrivacy \
  -framework AppKit -framework SwiftUI -framework CoreImage
"$out/addressprivacy"
