# Vendored: cl_audit's shared modules

`cl_audit-6bce89f/` is n-uf/cl_audit's `Core/`, `Run/` and `Auth/` at commit **6bce89f** (release 26.11.53), exactly as
they are there (`git archive 6bce89f Core Auth Run`), with that commit's own checks of them (`Checks/core`, `Checks/runs`,
`Checks/auth`).

| Folder | Module | Layer |
| --- | --- | --- |
| `Core/` | ProfileCore | Foundation only; imports nothing of ours |
| `Run/` | Runs | Foundation only; the one runner, the cleaned environment |
| `Auth/` | ClaudeAuth | imports ProfileCore and Runs: one folder's Claude Code sign-in |

## The rule

**Never edit these files here.** A change goes upstream, into cl_audit, and comes back as a new vendored commit (a new
`cl_audit-<sha>/` folder, this README and `scripts/modules.sh` pointed at it).

## What cl_quick builds: vendor plus the proposed patch

cl_quick compiles the three modules from this folder **plus the proposed upstream patch** in
`Shared/ClaudeAuth+SignIn/upstream/` (see `Shared/ClaudeAuth+SignIn/UPSTREAM-PATCHES.md`), until cl_audit takes the patch
and a new commit is vendored here:

- a file the patch changes is compiled from the patch, in place of the vendored one;
- a file the patch adds is compiled too (Run/ProcessTable.swift, Auth/StoredSignIn.swift);
- `Shared/ClaudeAuth+SignIn/ClaudeSignIn.swift` is compiled into ClaudeAuth (it moves to cl_audit's `Auth/` upstream);
- **`Auth/Keychain.swift` is left out.** cl_quick never reads the Keychain (a standing rule): with the patch, ClaudeAuth
  reaches a stored sign-in only through `StoredSignInReader`, which cl_quick never passes. `Checks/signin.sh` holds it.

`scripts/modules.sh` does this for `build.sh` and every `Checks/*.sh` (static libraries in their layers, ProfileCore, then
Runs, then ClaudeAuth, the way cl_audit's own build.sh builds them). `Checks/vendor.sh` runs cl_audit's own three suites on
the same sources in cl_audit's shape (Keychain.swift in, with their fake Keychain tool).
