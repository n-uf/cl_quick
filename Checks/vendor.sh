#!/usr/bin/env bash
# cl_audit's own checks of the shared modules, run here on what cl_quick compiles: its core, runs and auth suites
# (Vendor/cl_audit-6bce89f/Checks/, the auth suite as the proposed upstream patch changes it) against the vendored modules
# with the patch and ClaudeSignIn, in the shape cl_audit builds them (Auth/Keychain.swift in, with the suites' fake Keychain
# tool: nothing reads the real one). Their lints read a copy of the sources laid out as cl_audit's tree would have them after
# the patch (ClaudeSignIn in Auth/), under build/. Each suite runs with HOME at its own Checks/.work/<suite>/home in that
# copy, as cl_audit's Checks/run.sh does. Nothing outside build/ is written.
#   Checks/vendor.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
out="$repo/build/checks"
mkdir -p "$out"
. "$repo/scripts/modules.sh"

# the tree as cl_audit's would be after the patch: Core/, Run/, Auth/ (+ ClaudeSignIn) and the three suites
tree="$out/vendor-tree"
rm -rf "$tree"; mkdir -p "$tree/Core" "$tree/Run" "$tree/Auth" "$tree/Checks"
while IFS= read -r f; do cp "$f" "$tree/Core/"; done < <(module_sources Core)
while IFS= read -r f; do cp "$f" "$tree/Run/"; done < <(module_sources Run)
while IFS= read -r f; do cp "$f" "$tree/Auth/"; done < <(module_sources Auth)
cp "$modules_signin" "$tree/Auth/"
for s in core runs auth; do
  mkdir -p "$tree/Checks/$s"
  if [ -f "$modules_patch/Checks/$s/main.swift" ]; then cp "$modules_patch/Checks/$s/main.swift" "$tree/Checks/$s/"
  else cp "$modules_vendor/Checks/$s/main.swift" "$tree/Checks/$s/"; fi
done

mods="$out/modules-vendor"
build_modules "$mods" keychain -Onone -enable-testing
status=0
run() {   # run SUITE LIBS...
  local s="$1"; shift
  local home="$tree/Checks/.work/$s/home"
  rm -rf "$home"; mkdir -p "$home"
  swiftc -Onone -swift-version 5 -target arm64-apple-macos13.0 -o "$out/vendor-$s" "$tree/Checks/$s/main.swift" -I "$mods" -L "$mods" "$@"
  HOME="$home" CFFIXED_USER_HOME="$home" "$out/vendor-$s" || status=1
}
run core -lProfileCore
run runs -lRuns
run auth -lClaudeAuth -lRuns -lProfileCore
exit "$status"
