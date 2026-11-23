# Vendored: cl_kit, the modules shared with cl_audit

`cl_kit-<tag>/` is a tagged release of [n-uf/cl_kit](https://github.com/n-uf/cl_kit), exactly as the tag has it (without
cl_kit's own `.github/`). `CL_KIT` names the tag and its commit; `scripts/modules.sh` builds from the folder it names.

| Folder | Module | Layer |
| --- | --- | --- |
| `Core/` | ProfileCore | Foundation only; imports nothing of ours |
| `Run/` | Runs | Foundation only; the one runner, the cleaned environment, the process table |
| `Auth/` | ClaudeAuth | imports ProfileCore and Runs: one folder's Claude Code sign-in, and ClaudeSignIn |
| `Privacy/` | AddressPrivacy | apart from the layers (Apple's UI frameworks, nothing of ours): an address hidden on screen |
| `MenuRows/` | MenuRows | on top of ProfileCore and AddressPrivacy (Foundation, AppKit): one account row of a menu; cl_quick's standby rows |

## The rule

**Never edit these files here.** A change is a pull request to cl_kit, then a new tag there, then here:

```bash
scripts/vendor.sh v26.11.4   # copies the tag, removes the old folder, rewrites CL_KIT; then commit Vendor/
```

`scripts/vendor.sh --check` (run in CI) confirms the copy is exactly its tag and the tag still names the recorded commit.

## What cl_quick builds

`scripts/modules.sh` sources the copy's own `scripts/modules.sh` (cl_kit's build recipe: static libraries in their layers,
ProfileCore, then Runs, then ClaudeAuth) and always builds **without `Auth/Keychain.swift`**: cl_quick never reads the
Keychain (a standing rule), and ClaudeAuth reaches a stored sign-in only through `StoredSignInReader`, which cl_quick never
passes. The kit's no-keychain build also leaves out `Auth/DiscoveryApp.swift` (the desktop app's session folders and the
chats' account ids, which cl_quick never calls). `Checks/signin.sh` holds both. AddressPrivacy (`Privacy/`) is built beside
them by the copy's `kit_build_privacy`, under cl_quick's old name `build_address_privacy`, then MenuRows (`MenuRows/`) by
`kit_build_menurows` into the same folder; its link flags come before the others'.

`Checks/vendor.sh` runs cl_kit's own suites on the copy (`cl_kit-<tag>/Checks/run.sh`): core, runs, auth (with
`Keychain.swift` and a fake Keychain tool, as cl_kit checks it; nothing reads the real one), claudesignin and nokeychain.
