# Sourced by build.sh and Checks/*.sh (needs $repo): the shared modules cl_quick compiles from source, ProfileCore <- Runs
# <- ClaudeAuth (with ClaudeSignIn), from the tagged release of n-uf/cl_kit vendored in Vendor/cl_kit-<tag>/ (Vendor/CL_KIT
# names it; scripts/vendor.sh copies a tag). The build recipe is cl_kit's own (its scripts/modules.sh); this file only
# points it at the vendored copy and always leaves Auth/Keychain.swift out: cl_quick never reads the Keychain.
#
# and AddressPrivacy, a fourth, standalone one (cl_kit's Privacy/, vendored: Apple's UI frameworks, no other module of ours;
# cl_audit uses it too): the blurred stand-in of an address, its views and the plain text API. Built by the copy's own
# kit_build_privacy; the names below stay as cl_quick's scripts know them.
#
#   build_modules OUT no-keychain [swiftc flags...]   builds the four into OUT
#   build_address_privacy OUT [swiftc flags...]       builds AddressPrivacy alone into OUT (its own suite)
#   modules_link OUT                                  prints the flags that link them
#   module_sources Core|Run|Auth [left-out names...]  a module's vendored sources, one path per line
#   modules_kit, modules_tag                          the vendored copy's folder and its tag

[ -f "$repo/Vendor/CL_KIT" ] || { echo "no Vendor/CL_KIT: run scripts/vendor.sh <tag>" >&2; return 1; }
read -r modules_tag _ < "$repo/Vendor/CL_KIT"
modules_kit="$repo/Vendor/cl_kit-$modules_tag"
[ -f "$modules_kit/scripts/modules.sh" ] || { echo "no $modules_kit: run scripts/vendor.sh $modules_tag" >&2; return 1; }
kit_root="$modules_kit"
. "$modules_kit/scripts/modules.sh"

module_sources() { kit_sources "$@"; }

# build_address_privacy OUT [swiftc flags...]: AddressPrivacy as a static library (Swift 5 mode, macOS 13, imports nothing of
# ours), from the vendored copy's Privacy/
build_address_privacy() { kit_build_privacy "$@"; }

build_modules() {
  local out="$1" keychain="$2"; shift 2
  [ "$keychain" = no-keychain ] || { echo "build_modules: cl_quick builds the modules without the Keychain only" >&2; return 64; }
  kit_build "$out" no-keychain "$@" || return 1
  build_address_privacy "$out" "$@"
}

modules_link() { kit_link "$1"; printf '%s\n' -lAddressPrivacy; }
