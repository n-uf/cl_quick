# Proposed upstream patches for cl_audit (from cl_quick, stage 1 of the shared sign-in)

Against n-uf/cl_audit **6bce89f** (vendored in `Vendor/cl_audit-6bce89f/`, never edited there). The patched files are in
`upstream/` at the paths they have in cl_audit; `upstream.diff` is the same as one unified diff (`a/` = 6bce89f,
`b/` = patched), with `ClaudeSignIn.swift` as a new `Auth/` file. cl_quick compiles vendor plus these files today
(`scripts/modules.sh`); once cl_audit has taken them, a new commit is vendored and `upstream/` goes.

## 1. The Keychain read behind a protocol, in its own file

Why: ClaudeAuth didn't build without `Auth/Keychain.swift` (`AuthTools.security` was a `KeychainSignIn.Tool`, and
`Authenticator.readSignIn` called `KeychainSignIn.read`). cl_quick never reads the Keychain, so it must be able to leave
that file out.

- `Auth/StoredSignIn.swift` (new): `public protocol StoredSignInReader { func read(_ folder: AuthFolder, user: String) -> Login }`.
- `Auth/Authenticator.swift`: `AuthTools.security` becomes `AuthTools.stored: StoredSignInReader?` (init parameter
  `stored:`, default nil); `AuthTools.system` carries none; `Authenticator.readSignIn()` returns `Login?` (nil without a
  reader).
- `Auth/Keychain.swift`: adds `KeychainSignInReader` (the Keychain as a `StoredSignInReader`, its `tool` injectable) and
  `AuthTools.systemWithKeychain`. `KeychainSignIn` itself is unchanged; it stays the only file naming the Keychain.
- cl_audit callers: none in `Sources/` use `AuthTools(` or `Authenticator.readSignIn` at 6bce89f (`Sources/Model.swift`
  calls `KeychainSignIn.read` directly, unchanged). `Checks/auth/main.swift` changes (patched copy in
  `upstream/Checks/auth/`): the fakes pass `KeychainSignInReader(tool:)`, two more checks (no reader: nil;
  `systemWithKeychain` has the Keychain reader), and its lint now also says no Auth file but `Keychain.swift` names the
  Keychain.

## 2. SignInScript: the files a sign-in is followed by, and one owner-only writer

- `Auth/Runs.swift`: `SignInScript.Watch` (pid, status and declined-mark files) and `lines(..., watch:)`. With a watch, the
  script traps TERM/HUP into a clean `exit 0`, writes its pid first and the login's status after, sends Claude Code's
  errors on to the window through `tee` while `grep -m 1` looks for `OAuth error: access_denied` (only a mark file is kept,
  never the text; `cat` reads the rest so tee never stops), and after a login that didn't end well waits on `read -r`
  (the window stays to be read) before its clean end. Without a watch the lines are as before.
- `SignInScript.write(_:to:)`: the owner-only (0700, O_EXCL, O_NOFOLLOW) writer that `Authenticator.startSignIn` had
  inline, now shared (ClaudeSignIn writes the `.terminal` settings file with it). `startSignIn` gains `watch:`.

## 3. Runs: the process table, moved from the app

- `Run/ProcessTable.swift` (new): cl_audit's `Sources/Processes.swift` kernel table (`table`, `settledTable`, `Launch`,
  `Entry`, `looksLikeClaude`, `launch(of:)`, `parse`, `executable(of:)`, `startTime(of:)`, `runs`), public, Foundation only,
  plus: `Entry.ppid`; `isClaudeCode(_:)` (the folder-free half of `Processes.isCode`); `Launch.environmentRead`; and `runs`
  no longer counts a zombie as running. cl_audit's `Processes` would then read the table through it and keep its app
  parts.
- **Finding for cl_audit (affects 6bce89f as it is):** on macOS 27.3 (26C5035r) `KERN_PROCARGS2` gives no environment for
  another process, even the same user's (`ps -E` shows none either; checked with stand-ins `CLAUDE_CONFIG_DIR=… sleep`).
  `Processes.parse` then reads `configDir` as nil for every `claude`, so `codeRuns(codeDir:)` takes every Claude Code for
  the default folder: a custom folder looks free while Claude Code runs on it, and `~/.claude` looks busy whenever any
  folder's Claude Code runs. `Launch.environmentRead` lets a caller tell "not set" from "not readable"; ClaudeSignIn uses
  it (below). cl_audit's own callers need the same decision.

## 4. ClaudeSignIn (new, `Auth/ClaudeSignIn.swift`)

`Shared/ClaudeAuth+SignIn/ClaudeSignIn.swift` here; it moves as it is. No cl_quick words, UI or global state (one
process-wide queue and "the app's current sign-in", which is the one-window-per-app rule itself). Passes cl_audit's own
auth lint (imports, no `Process()`, no printing, no Keychain).

## 5. `Auth/README.md`

The file table (StoredSignIn, Keychain's new role, Runs' additions, ClaudeSignIn) and the cl_quick fit paragraph.

## Open points for the cl_audit hub

- **Matching an account wanted without an organisation.** `SignedInAccount.match` treats no organisation id as the empty
  one when both sides have account ids, so an account wanted by its id alone never matched a seat in an organisation.
  cl_quick keeps accounts by id (and address) only, so `ClaudeSignIn` compares without the organisation when the account
  wanted names none (`ClaudeSignIn.same`). cl_audit, which keeps seats, should pass the organisation id it knows.
- **The process guard on macOS 27.** With no environment readable, a `claude auth login` is tied to a folder only through
  its parent script's name (`sign-in-<lock key>.command`, any app using ClaudeSignIn); a bare one (a terminal's) can't be
  told and counts as running on every folder (refused rather than guessed).
- **The `.terminal` route** (`Window.settingsFile`) is verified by content only; opening one may also add a profile to
  Terminal's list (to be seen in the live try). `.scripted` (AppleScript) is there as the fallback, untried.
