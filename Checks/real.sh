#!/usr/bin/env bash
# Real questions through the quick chat's engine and the installed `claude`.
#   Checks/real.sh              a throwaway, signed-out folder: Claude Code says it isn't signed in
#   QC_CONFIG=~/.claude-x Checks/real.sh   that folder's account answers (uses a little of its usage): one kept-alive
#                               `claude`, five turns: it remembers, Stop (interrupt) keeps the conversation, the model
#                               changes in the running chat; then it checks that quick chats are incognito: no session
#                               file for this run's work folder under the folder's projects/, and it lists every file in
#                               the folder that changed during the run (other Claude Code sessions on a folder in use
#                               write there too)
# QC_MODEL (haiku), QC_EFFORT (empty: thinking off), QC_QUESTION (single question only). The work folder and the
# throwaway folder are under build/.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
out="$repo/build/checks"
mkdir -p "$out"
claude="${QC_CLAUDE:-$(command -v claude)}"
work="$out/real-work"
config="${QC_CONFIG:-$out/throwaway-config}"
mkdir -p "$config" "$work"
swiftc -swift-version 5 -target arm64-apple-macos13.0 -o "$out/real" \
  "$repo/Sources/Engine.swift" "$here/real/main.swift"
marker="$out/real-marker"
touch "$marker"; sleep 1
status=0
multi=0; [ -n "${QC_CONFIG:-}" ] && multi=1
log="$out/real-output.txt"
set +e
QC_MULTI="$multi" QC_CLAUDE="$claude" QC_CONFIG="$config" QC_WORK="$work" "$out/real" 2>&1 | tee "$log"
rc=${PIPESTATUS[0]}
set -e
[ "$rc" = 0 ] || status=1
sid="$(sed -n 's/.*SESSION \([0-9a-f-]\{36\}\).*/\1/p' "$log" | head -1)"
# incognito: Claude Code must not have kept a session for this work folder
key="$(printf '%s' "$work" | sed 's/[^A-Za-z0-9]/-/g')"
sleep 1
if [ -n "${QC_CONFIG:-}" ]; then
  echo "--- changed in $config during the run:"
  find "$config" "$config.json" -newer "$marker" -type f 2>/dev/null | sed "s|^$HOME|~|" | sort | head -60 || true
  if [ -n "$key" ] && [ -e "$config/projects/$key" ]; then
    echo "FAIL a session was kept: $config/projects/$key"; ls -la "$config/projects/$key"; status=1
    rm -rf "$config/projects/$key"
  else
    echo "PASS no session kept for this run (no projects/$key)"
  fi
  # nothing in the folder names this chat: not its session id, not its work folder (other sessions' files don't)
  if [ -n "$sid" ]; then
    # the whole folder but projects/ (other sessions' transcripts live there; this run's own key is checked above),
    # cache/, skills/ and plugin marketplaces (downloaded content)
    hits="$(grep -rl --exclude-dir=projects --exclude-dir=cache --exclude-dir=skills --exclude-dir=marketplaces \
              -e "$sid" -e "$work" "$config" "$config.json" 2>/dev/null || true)"
    if [ -n "$hits" ]; then echo "FAIL this chat's session id or work folder is written in: $hits"; status=1
    else echo "PASS no file in the folder (but projects/, cache/, skills/) or its .claude.json names this chat's session id or work folder"; fi
  fi
fi
if [ -z "${QC_CONFIG:-}" ]; then rm -rf "$config"; fi
exit "$status"
