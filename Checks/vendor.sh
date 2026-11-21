#!/usr/bin/env bash
# cl_kit's own checks of the shared modules, run here on the copy cl_quick builds: the vendored tag's Checks/run.sh (core,
# runs, auth, claudesignin and nokeychain), on Vendor/cl_kit-<tag>/ itself. The auth suite builds ClaudeAuth with
# Auth/Keychain.swift and a fake Keychain tool, as cl_kit checks it (nothing reads the real Keychain); the nokeychain suite
# builds it as cl_quick does, without that file. Each suite runs with HOME at its own Checks/.work/<suite>/home inside the
# vendored copy (git-ignored); nothing else is written.
#   Checks/vendor.sh [suite...]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
. "$repo/scripts/modules.sh"
echo "cl_kit $modules_tag (Vendor/cl_kit-$modules_tag)"
exec "$modules_kit/Checks/run.sh" "$@"
