# cl_quick's code signing, shared by build.sh and scripts/release.sh (sourced, bash). See docs/signing.md. It is cl_audit's
# scripts/signing.sh adapted: the same two settings, so they are set once for both apps.
#
#   CL_SIGN_ID          a Developer ID Application identity ("Developer ID Application: Name (TEAMID)", or its SHA-1 as
#                       `security find-identity -v -p codesigning` lists it). Unset: ad hoc, exactly as before.
#   CL_NOTARY_PROFILE   a notarytool keychain profile (xcrun notarytool store-credentials). Unset: no notarization.
#                       Needs CL_SIGN_ID: Apple notarizes Developer ID signatures only.
#
# Nothing here reads, prints or stores a password, a token or a private key: codesign and notarytool take them from the
# Keychain themselves (the first codesign with a new identity may ask once to use its key: Always Allow).

sign_id="${CL_SIGN_ID:-}"
notary_profile="${CL_NOTARY_PROFILE:-}"

# sign PATH [codesign options...]: ad hoc without CL_SIGN_ID, the very command build.sh always ran (its errors hidden, as
# before); with it, the Developer ID, the hardened runtime and a secure timestamp, errors shown. Never --deep: build.sh
# signs inside out, each nested piece before the bundle that seals it (today there is only the app: see sign_plan).
# No entitlements are passed: under the hardened runtime cl_quick needs none (docs/signing.md ▸ Entitlements).
sign() {
  local path="$1"; shift
  if [ -z "$sign_id" ]; then
    codesign --force --sign - "$@" "$path" 2>/dev/null
  else
    codesign --force --sign "$sign_id" --options runtime --timestamp "$@" "$path"
  fi
}

# What gets signed, in order (inside out), relative to build/: what --check-signing lists. build.sh follows this order.
# cl_quick.app holds one program and no helper app, plug-in, framework or dylib (the shared modules are static libraries
# linked into it), so the app is the one thing to sign. A nested piece added later goes into this list and into build.sh,
# before the app.
sign_plan=(
  "cl_quick.app|the app (local.n-uf.cl-quick), no entitlements"
)

# The identity's line in this Mac's Keychain, or nothing (no secret read: find-identity lists names and hashes only).
# Only a Developer ID Application identity counts, named exactly: its 40-character SHA-1 (any case) or its whole quoted
# name. A fragment ("Developer") or an Apple Development identity doesn't. awk reads every line (no early exit to break
# the pipe under pipefail).
sign_id_line() {
  [ -n "$sign_id" ] || return 0
  security find-identity -v -p codesigning 2>/dev/null | awk -v id="$sign_id" \
    'index($0, "\"Developer ID Application:") && (toupper($2) == toupper(id) || index($0, "\"" id "\"")) { print }'
}
sign_id_found() { [ -n "$(sign_id_line)" ]; }
# The identity's team ID (the ten characters in "… (TEAMID)" at the end of its name), for the release's requirement check.
sign_team() { sign_id_line | sed -n 's/.*(\([A-Z0-9]\{10\}\))"$/\1/p' | head -1; }

# staple FILE: the notarization ticket into it, again up to twice 20 s later (a fresh ticket can take a moment to be
# found: "Record not found").
staple() {
  local i
  for i in 1 2 3; do
    xcrun stapler staple -q "$1" && return 0
    [ "$i" = 3 ] || { echo "stapling $(basename "$1") didn't work yet; trying again in 20 s…" >&2; sleep 20; }
  done
  return 1
}

# The notary profile answers (one call to Apple's notary service, nothing printed; its credentials stay in the Keychain).
notary_profile_found() {
  [ -n "$notary_profile" ] && xcrun notarytool history --keychain-profile "$notary_profile" --output-format json >/dev/null 2>&1
}

# signing_preflight: the set-up found out before anything is built, committed or pushed. Returns 1 with the reason on
# stderr; with both settings unset it does nothing (an ad hoc release).
signing_preflight() {
  if [ -n "$notary_profile" ] && [ -z "$sign_id" ]; then
    echo "CL_NOTARY_PROFILE needs CL_SIGN_ID: Apple notarizes Developer ID signatures only" >&2; return 1
  fi
  if [ -n "$sign_id" ] && ! sign_id_found; then
    echo "CL_SIGN_ID isn't among this Mac's code signing identities (security find-identity -v -p codesigning)" >&2; return 1
  fi
  if [ -n "$notary_profile" ] && ! notary_profile_found; then
    echo "the notary profile \"$notary_profile\" doesn't answer (xcrun notarytool store-credentials; see docs/signing.md)" >&2; return 1
  fi
  return 0
}

# notarize FILE: sends it to Apple's notary service and waits for the verdict; anything but Accepted fails, with the
# command that shows Apple's log. Only the verdict and the submission id are read from the answer.
notarize() {
  local f="$1" out status id err
  echo "notarizing $(basename "$f") (Apple's notary service; usually a few minutes, at most 45)…"
  # notarytool's own messages kept aside, shown when there's no verdict (a profile, network or upload problem); they
  # hold no secret (the profile's password stays in the Keychain)
  err="$(mktemp)"
  out="$(xcrun notarytool submit "$f" --keychain-profile "$notary_profile" --wait --timeout 45m --output-format json 2>"$err")" || true
  status="$(printf '%s' "$out" | plutil -extract status raw -o - - 2>/dev/null || true)"
  id="$(printf '%s' "$out" | plutil -extract id raw -o - - 2>/dev/null || true)"
  if [ "$status" != Accepted ]; then
    echo "the notarization of $(basename "$f") ended ${status:-without an answer}${id:+ (submission $id)}" >&2
    [ -n "$status" ] || cat "$err" >&2
    [ -z "$id" ] || echo "Apple's log of it: xcrun notarytool log $id --keychain-profile \"$notary_profile\"" >&2
    rm -f "$err"
    return 1
  fi
  rm -f "$err"
  echo "notarized $(basename "$f") (submission $id)"
}

# check_signing: the plan, signing nothing: the identity and profile found or not, then each thing it would sign, in order,
# and the release's notarization steps.
check_signing() {
  echo "Code signing plan (nothing is signed or sent):"
  if [ -z "$sign_id" ]; then
    echo "  CL_SIGN_ID unset: ad hoc signing (codesign --sign -), as today"
  elif sign_id_found; then
    echo "  CL_SIGN_ID: found in this Mac's Keychain; Developer ID, --options runtime --timestamp"
  else
    echo "  CL_SIGN_ID: NOT found among this Mac's code signing identities (security find-identity -v -p codesigning)"
  fi
  if [ -z "$notary_profile" ]; then
    echo "  CL_NOTARY_PROFILE unset: no notarization"
  elif [ -z "$sign_id" ]; then
    echo "  CL_NOTARY_PROFILE set without CL_SIGN_ID: a release would stop (Apple notarizes Developer ID signatures only)"
  elif notary_profile_found; then
    echo "  CL_NOTARY_PROFILE: the profile answers (notarytool history)"
  else
    echo "  CL_NOTARY_PROFILE: NOT usable (no such keychain profile, or Apple's notary service not reachable)"
  fi
  echo "Signed, in this order:"
  local i=1 p
  for p in "${sign_plan[@]}"; do echo "  $i. ${p%%|*}: ${p#*|}"; i=$((i + 1)); done
  if [ -n "$sign_id" ] && [ -n "$notary_profile" ]; then
    echo "Then, in scripts/release.sh --push (and --local), before anything is pushed:"
    echo "  zip the app; notarytool submit --wait (Accepted or the release stops); staple the app; zip it again"
    echo "  the disk image from the stapled app; sign it; notarize it; staple it"
    echo "  check: spctl -t exec on the app, spctl -t open (primary signature) on the image, stapler validate on both"
  elif [ -n "$sign_id" ]; then
    echo "Then the release signs the disk image too; without CL_NOTARY_PROFILE nothing is notarized."
  fi
}
