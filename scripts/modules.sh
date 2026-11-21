# Sourced by build.sh and Checks/*.sh (needs $repo): the shared modules cl_quick compiles from source, built as static
# libraries in their layers, ProfileCore <- Runs <- ClaudeAuth, the way cl_audit's own build.sh builds them:
#   ProfileCore  Vendor/cl_audit-6bce89f/Core/*.swift                 (Foundation only)
#   Runs         Vendor/cl_audit-6bce89f/Run/*.swift                  + the proposed upstream patch's new files
#   ClaudeAuth   Vendor/cl_audit-6bce89f/Auth/*.swift, each replaced by its patched copy where the proposed upstream patch
#                has one (Shared/ClaudeAuth+SignIn/upstream/), + the patch's new files + Shared/ClaudeAuth+SignIn/ClaudeSignIn.swift.
#                cl_quick leaves Auth/Keychain.swift out: it never reads the Keychain.
# The vendored copy is never edited here (Vendor/README.md); the patch is what cl_audit is asked to take.
#
# and AddressPrivacy, a fourth, standalone one (Shared/AddressPrivacy/*.swift: Foundation, AppKit and SwiftUI, no other module
# of ours; cl_audit adopts it too): the blurred stand-in of an address, its views and the plain text API.
#
#   build_modules OUT keychain|no-keychain [swiftc flags...]   builds the four into OUT
#   build_address_privacy OUT [swiftc flags...]                builds AddressPrivacy alone into OUT (its own suite)
#   modules_link OUT                                           prints the flags that link them

modules_vendor="$repo/Vendor/cl_audit-6bce89f"
modules_patch="$repo/Shared/ClaudeAuth+SignIn/upstream"
modules_signin="$repo/Shared/ClaudeAuth+SignIn/ClaudeSignIn.swift"

# module_sources DIR [left-out file names...]: DIR's vendored sources, the patched copy in place of each one the patch has,
# then the patch's new files; one path per line
module_sources() {
  local dir="$1"; shift
  local f b s out
  for f in "$modules_vendor/$dir"/*.swift "$modules_patch/$dir"/*.swift; do
    [ -e "$f" ] || continue
    b="$(basename "$f")"
    out=0; for s in "$@"; do [ "$s" = "$b" ] && out=1; done
    [ "$out" = 1 ] && continue
    case "$f" in
      "$modules_vendor"/*) [ -f "$modules_patch/$dir/$b" ] && f="$modules_patch/$dir/$b" ;;
      *) [ -f "$modules_vendor/$dir/$b" ] && continue ;;      # a patched copy: already listed in its place
    esac
    printf '%s\n' "$f"
  done
}

modules_addresses="$repo/Shared/AddressPrivacy"

# build_address_privacy OUT [swiftc flags...]: AddressPrivacy as a static library (Swift 5 mode, macOS 13, imports nothing of ours)
build_address_privacy() {
  local out="$1"; shift
  mkdir -p "$out"
  rm -f "$out"/libAddressPrivacy.a
  swiftc -swift-version 5 -parse-as-library -target arm64-apple-macos13.0 "$@" -module-name AddressPrivacy \
    -emit-module -emit-module-path "$out/AddressPrivacy.swiftmodule" -emit-library -static -o "$out/libAddressPrivacy.a" \
    "$modules_addresses"/*.swift
}

build_modules() {
  local out="$1" keychain="$2"; shift 2
  local common=(-swift-version 5 -parse-as-library -target arm64-apple-macos13.0 "$@")
  local core=() runs=() auth=() f
  while IFS= read -r f; do core+=("$f"); done < <(module_sources Core)
  while IFS= read -r f; do runs+=("$f"); done < <(module_sources Run)
  if [ "$keychain" = keychain ]; then
    while IFS= read -r f; do auth+=("$f"); done < <(module_sources Auth)
  else
    while IFS= read -r f; do auth+=("$f"); done < <(module_sources Auth Keychain.swift)
  fi
  auth+=("$modules_signin")
  mkdir -p "$out"
  rm -f "$out"/libProfileCore.a "$out"/libRuns.a "$out"/libClaudeAuth.a
  swiftc "${common[@]}" -module-name ProfileCore \
    -emit-module -emit-module-path "$out/ProfileCore.swiftmodule" -emit-library -static -o "$out/libProfileCore.a" "${core[@]}"
  swiftc "${common[@]}" -module-name Runs \
    -emit-module -emit-module-path "$out/Runs.swiftmodule" -emit-library -static -o "$out/libRuns.a" "${runs[@]}"
  swiftc "${common[@]}" -module-name ClaudeAuth -I "$out" \
    -emit-module -emit-module-path "$out/ClaudeAuth.swiftmodule" -emit-library -static -o "$out/libClaudeAuth.a" "${auth[@]}"
  build_address_privacy "$out" "$@"
}

modules_link() { printf '%s\n' -I "$1" -L "$1" -lClaudeAuth -lRuns -lProfileCore -lAddressPrivacy; }
