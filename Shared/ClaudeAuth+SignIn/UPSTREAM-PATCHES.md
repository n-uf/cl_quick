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
- **A caveat for stand-ins (corrected; an earlier draft wrongly said the environment was hidden for every process).**
  `KERN_PROCARGS2` gives no environment for Apple's platform binaries (`/bin/sleep`, `/bin/bash`), which checks often use
  as stand-ins; it does for Claude Code's own program and for ad-hoc built ones. A check whose stand-in `claude` is a bash
  script therefore reads `configDir` as nil, as if the default folder. `Launch.environmentRead` tells "not set" from "not
  readable"; ClaudeSignIn uses it, and its checks use an ad-hoc compiled stand-in for the environment branch.

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
  wanted names none (`ClaudeSignIn.judge`). cl_audit, which keeps seats, should pass the organisation id it knows. An
  account wanted by its id is compared by ids only: a word that names no id (a running claude's) takes the record's id,
  and only when the record agrees with the word; otherwise the sign-in ends `unverified`.
- **The process guard fails closed.** A `claude auth login` is tied to a folder by its CLAUDE_CONFIG_DIR where the
  environment is readable (unset: the default folder; an absolute path: compared as a folder; empty, relative or `~`:
  can't be told) and by the ClaudeSignIn script it runs under (`sign-in-<lock key>.command`, any app's). Either naming
  this folder refuses; neither at all, or an environment that can't be told, refuses too; a hidden process refuses all.
- **`unverified`.** A login that ended but whose account the app's word didn't confirm after `confirmTries` (3) asks ends
  `unverified(account)`, never `signedIn`. While the login still runs, nothing ends on a guess or on the word and the record
  disagreeing; only the two agreeing on another account than the one wanted ends it early (`wrongAccount`).
- **The `.terminal` route** (`Window.settingsFile`) is verified by content only. Whether Terminal adds the opened
  settings file to its profile list can't be told without opening one; each sign-in's profile has a name of its own
  (`<title> <8 hex>`), so a kept one never stands for a later sign-in, but if Terminal does keep them they pile up, one
  per sign-in (the live try settles it; then `.scripted`, AppleScript, is the fallback, untried).
