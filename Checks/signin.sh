#!/usr/bin/env bash
# The sign-in's checks: ClaudeAuth's ClaudeSignIn (Shared/ClaudeAuth+SignIn/) as cl_quick builds it, and cl_quick's switch on
# it, against a stand-in Terminal and a stand-in `claude auth login` (Checks/signin/bin/claude): each outcome, a wrong account
# by id and by address and organisation, stop and a second start ending the login, the lock and the process guard, a folder
# that isn't ready, cl_quick's own word (a short claude's `initialize`). First, the Keychain lint: nothing cl_quick compiles
# can read the Keychain (no Auth/Keychain.swift, no `security`, no Security framework), in the sources and in the app built
# (./build.sh --no-install first, for the app's part). The whole app but its main.swift, and Checks/signin/main.swift in its
# place. No window, no real Terminal or claude, nothing outside build/ written; only its own processes are signalled.
#   Checks/signin.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
out="$repo/build/checks"
mkdir -p "$out"
. "$repo/scripts/modules.sh"

# ── the Keychain lint ──
lint=0; lintn=0
fail() { echo "FAIL keychain lint: $*"; lint=1; }
compiled=("$repo"/Sources/*.swift)
while IFS= read -r f; do compiled+=("$f"); done < <(module_sources Core; module_sources Run; module_sources Auth Keychain.swift)
compiled+=("$modules_signin")
for f in "${compiled[@]}"; do
  lintn=$((lintn + 1))
  [ "$(basename "$f")" = Keychain.swift ] && fail "$f is compiled into cl_quick"
  if grep -n -E 'KeychainSignIn|/usr/bin/security|find-generic-password|SecItem|SecKeychain|kSecClass|import Security' "$f" >/dev/null; then
    fail "$f names the Keychain: $(grep -n -E 'KeychainSignIn|/usr/bin/security|find-generic-password|SecItem|SecKeychain|kSecClass|import Security' "$f" | head -3)"
  fi
done
lintn=$((lintn + 1))
grep -q -- '-framework Security' "$repo/build.sh" && fail "build.sh links the Security framework"
lintn=$((lintn + 1))
grep -q 'build_modules "$out/modules" no-keychain' "$repo/build.sh" || fail "build.sh doesn't build the modules without the Keychain"
lintn=$((lintn + 1))
grep -n -E 'stored: *[A-Za-z]|\.stored *=|systemWithKeychain|KeychainSignInReader' "$repo"/Sources/*.swift >/dev/null && fail "cl_quick passes a stored sign-in reader"
app="$repo/build/cl_quick.app/Contents/MacOS/cl_quick"
if [ -x "$app" ]; then
  lintn=$((lintn + 3))
  otool -L "$app" | grep -q 'Security.framework' && fail "the app links Security.framework"
  nm -u "$app" | grep -q -E '_Sec[A-Z]' && fail "the app calls the Security API: $(nm -u "$app" | grep -E '_Sec[A-Z]' | head -3)"
  strings "$app" | grep -q -E '/usr/bin/security|find-generic-password' && fail "the app holds the security tool's path or command"
else
  echo "note: no built app at $app (./build.sh --no-install): its part of the lint skipped"
fi
[ "$lint" = 0 ] && echo "keychain lint: $lintn/$lintn passed"

# ── the Terminal lint: this suite never touches Terminal's real preferences ──
# every ClaudeSignIn the suite makes is handed a stand-in for them (a sign-in sweeps Terminal's kept profiles at its start
# and its end; the real ones are only for the app)
made="$(grep -c 'ClaudeSignIn(' "$here/signin/main.swift" || true)"
handed="$(grep -c 'terminalProfiles: prefs.tool' "$here/signin/main.swift" || true)"
if [ "$made" != "$handed" ] || [ "$made" = 0 ]; then
  echo "FAIL terminal lint: $made ClaudeSignIn(...) in Checks/signin/main.swift, $handed with a stand-in for Terminal's preferences"
  lint=1
elif grep -n -E 'com\.apple\.Terminal|TerminalProfiles\.system|\.system\b.*terminalProfiles' "$here/signin/main.swift" | grep -v '^[0-9]*: *//' >/dev/null; then
  echo "FAIL terminal lint: Checks/signin/main.swift names Terminal's real preferences"
  lint=1
else
  echo "terminal lint: $made/$made sign-ins in the suite are handed Terminal-preferences stand-ins"
fi

# ── the suite ──
build_modules "$out/modules-signin" no-keychain -Onone
link=(); while IFS= read -r f; do link+=("$f"); done < <(modules_link "$out/modules-signin")
sources=()
for f in "$repo"/Sources/*.swift; do [ "$(basename "$f")" = main.swift ] || sources+=("$f"); done
swiftc -swift-version 5 -target arm64-apple-macos13.0 -o "$out/signin" "${sources[@]}" "$here/signin/main.swift" "${link[@]}" \
  -framework AppKit -framework SwiftUI -framework Carbon -framework ServiceManagement
chmod +x "$here/signin/bin/claude" "$here/stub-claude"
# the ad-hoc stand-in for the environment branch (bash, a platform binary, shows the kernel no environment)
mkdir -p "$out/signin-adhoc"
clang -O0 -o "$out/signin-adhoc/claude" "$here/signin/adhoc.c"
status=0
QC_SIGNIN_CLAUDE="$here/signin/bin/claude" QC_SIGNIN_ADHOC="$out/signin-adhoc/claude" QC_SIGNIN_WORK="$out/signin-work" "$out/signin" || status=$?
[ "$lint" = 0 ] || status=1
exit "$status"
