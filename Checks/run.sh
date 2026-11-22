#!/usr/bin/env bash
# The quick chat's checks: the stream-json parser, the `claude` command and its environment, the Markdown blocks, the
# kept-alive process against a stand-in `claude` (stub-claude), and a profile's accounts on cl_kit's account rule (the
# seat keys, the stored keys' move and backup, whose numbers a running claude's are). No account, no network, nothing
# outside the repo but a work folder under build/ and the system's temporary folder.
#   Checks/run.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
out="$repo/build/checks"
mkdir -p "$out"
. "$repo/scripts/modules.sh"          # Accounts.swift imports ClaudeAuth and ProfileCore: the shared modules, built first
build_modules "$out/modules-run" no-keychain -Onone
link=(); while IFS= read -r f; do link+=("$f"); done < <(modules_link "$out/modules-run")
chmod +x "$here/stub-claude"
swiftc -swift-version 5 -target arm64-apple-macos13.0 -o "$out/checks" \
  "$repo/Sources/Engine.swift" "$repo/Sources/Markdown.swift" "$repo/Sources/Accounts.swift" "$repo/Sources/Updates.swift" "$here/main.swift" \
  "${link[@]}"
QC_STUB_PATH="$here/stub-claude" QC_WORK="$out/work" "$out/checks"
