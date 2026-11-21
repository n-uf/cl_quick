#!/usr/bin/env bash
# The Custom instructions' checks that need the app (Settings ▸ General ▸ Chat): what is stored and read back, the cap on
# typing and pasting in the real text view, which chat takes which text (a new chat the current text, an open one its own,
# never restarted), the prompt a chat's `claude` is started with (on the stand-in), and Remove clearing it. The whole app
# but its main.swift, and Checks/instructions/main.swift in its place. No mouse, no event posting, nothing on any screen,
# nothing written outside build/. (The prompt's own words and the process key are in Checks/run.sh.)
#   Checks/instructions.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
out="$repo/build/checks"
mkdir -p "$out"
. "$repo/scripts/modules.sh"          # the shared modules the app imports (ClaudeAuth and below), built first
build_modules "$out/modules-instructions" no-keychain -Onone
link=(); while IFS= read -r f; do link+=("$f"); done < <(modules_link "$out/modules-instructions")
sources=()
for f in "$repo"/Sources/*.swift; do [ "$(basename "$f")" = main.swift ] || sources+=("$f"); done
swiftc -swift-version 5 -target arm64-apple-macos13.0 -o "$out/instructions" "${sources[@]}" "$here/quiet.swift" "$here/instructions/main.swift" "${link[@]}" \
  -framework AppKit -framework SwiftUI -framework Carbon -framework ServiceManagement -framework WebKit
chmod +x "$here/stub-claude"
QC_STUB_PATH="$here/stub-claude" QC_SAMPLE_DIR="$out/sample-claude-instructions" "$out/instructions"
