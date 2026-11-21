#!/usr/bin/env bash
# The AddressPrivacy module's own checks, now cl_kit's: the vendored copy's addressprivacy suite (its lint, then the module built
# alone and Vendor/cl_kit-<tag>/Checks/addressprivacy/main.swift against it). No app code, no window, no mouse, no keyboard, no
# real account: sample addresses only; it writes only under the copy's Checks/.work (git-ignored). Checks/vendor.sh runs it too,
# with cl_kit's other suites; this file keeps CI's own step.
#   Checks/addressprivacy.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
exec "$here/vendor.sh" addressprivacy
