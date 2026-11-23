#!/usr/bin/env bash
# The real-claude check of cl_kit's short ask (ClaudeAsk), the one cl_quick's usage refresher and sign-in word run: the
# installed `claude`, asked `initialize` and `get_usage` only (never a model message), first in a fresh throwaway folder
# under $TMPDIR (not signed in: no account, a clean stop), then once in the profile's own folder: ~/.claude-work when it
# is there and signed in, else ~/.claude (never a standby account's folder, never another). It prints pass or fail, how
# each ask ended and the stop step that ended `claude`; an address shows only as "<address>". Its work folders are under
# $TMPDIR and removed after. Never the Keychain (Claude Code reads its own sign-in as it always does).
#   Checks/ask.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
out="$repo/build/checks"
mkdir -p "$out"
. "$repo/scripts/modules.sh"
build_modules "$out/modules-ask" no-keychain -Onone
link=(); while IFS= read -r f; do link+=("$f"); done < <(modules_link "$out/modules-ask")
swiftc -swift-version 5 -target arm64-apple-macos13.0 -o "$out/ask" "$here/ask/main.swift" "${link[@]}"

# signed in: the folder's record names an account (only that key is looked for; nothing of it is printed)
signed_in() { [ -f "$1" ] && grep -q '"oauthAccount"' "$1"; }
profile=""
if [ -d "$HOME/.claude-work" ] && signed_in "$HOME/.claude-work/.claude.json"; then profile="$HOME/.claude-work"
elif [ -d "$HOME/.claude" ] && signed_in "$HOME/.claude.json"; then profile="$HOME/.claude"; fi
work="$(mktemp -d "${TMPDIR:-/tmp}/cl_quick-ask.XXXXXX")"
trap 'rm -rf "$work"' EXIT
QC_ASK_WORK="$work" QC_ASK_PROFILE="$profile" "$out/ask"
