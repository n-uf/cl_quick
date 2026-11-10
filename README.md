# cl_quick

A floating Claude chat for the Mac, on a shortcut. Press it over any app: a bar opens; the first message turns it into a
chat window that stays floating, on every Space, until Esc hides it. It never brings another app forward.

Your own Claude Code answers, on the profile's account in use, and it counts against that account's limits. cl_quick
is one menu bar app with no Dock icon and one `claude` at a time, kept while a chat is open and ended after 15 minutes
idle.

**Quick chats are incognito: no message is saved on this Mac. Your messages still go to Anthropic under the profile's
account.** A chat lives only in the running `claude` (it runs with `--no-session-persistence`), so it ends with it: after
15 minutes idle, on New chat (⌘N), on another profile or account, if `claude` crashes, or when cl_quick quits. The
window then says "This chat ended after 15 minutes idle. Nothing was saved." and the next message starts a new chat.

## Install

Download the latest release, open the disk image and drag cl_quick to Applications. It needs an Apple silicon Mac,
macOS 13 or later and [Claude Code](https://code.claude.com/docs/en/setup), signed in. cl_quick isn't signed with an
Apple Developer ID yet, so the first time macOS says it can't verify the app: open System Settings ▸ Privacy &
Security and click **Open Anyway** (once).

To build it yourself: `./build.sh` (Xcode's command-line tools; it installs into /Applications and opens it), or
`./build.sh --no-install`.

## Profiles

A profile is a Claude Code folder cl_quick chats on: `~/.claude`, a `~/.claude-*` folder, or any folder set with
`CLAUDE_CONFIG_DIR`. On its first run cl_quick takes every one it finds that is signed in, named after the folder (Main
for `~/.claude`, Work for `~/.claude-work`); two folders signed in to the same account make one profile, `~/.claude`
first.

A profile has several accounts, one folder. A Claude Code folder holds one signed-in account at a time, so a profile
remembers the accounts that have been signed in to its folder: the one signed in now is **in use**, the others are
**standby**. Switching to a standby account means signing in again in the same folder as that account. There are no
helper folders: one profile, one folder.

In Settings (the menu bar icon ▸ Settings…) each profile has a tile and a card: its name, its accounts (the one in use
with its week as Claude Code last reported it, the others on standby with their last week or "no numbers yet"; read
from the folder's own `.claude.json`, never the Keychain), whether the shortcut chats on it, and whether the chat's
profile picker offers it. On the card, **Switch to this account…** changes the account in use, **Sign in again…**
renews the one in use, and **Add an account…** takes an address and switches to it. The **+** tile adds a profile: a
folder found, Choose a folder… (it must be a signed-in Claude Code folder), or Sign in another account…, which makes a
new folder and opens Claude Code's own sign-in for it in Terminal.

### Switching accounts

- cl_quick asks first: "Switch Main to p•••@example.com?" Every Claude Code session using that folder moves to the
  account when it next renews its sign-in, not just the quick chat.
- Then Claude Code's own sign-in (`claude auth login --email …`) opens in Terminal and finishes in your browser. The
  browser's claude.ai session decides which account actually signs in, so cl_quick checks the result: it looks at the
  folder's `.claude.json` every 2 seconds, for at most 10 minutes, until the account changes. It never sees a password or
  a token and never touches the Keychain.
- If another account signed in, the chat says so ("Signed in as m•••@example.com, not p•••@example.com") and offers
  Sign in again. After 10 minutes with no change it stops looking and says "No sign-in in 10 minutes." (in the chat and on the profile's card), with Sign in again and Dismiss.
- Each account keeps its own week: after a switch the chat shows that account's last-reported week, or "no numbers yet".
  Weeks are kept per account (its id in Claude Code's file), not per organization.
- Addresses are masked everywhere in cl_quick (p•••@example.com).

## The chat

- Return sends, Shift-Return adds a line, Esc or ⌘W hides it, ⌘N starts a new chat.
- Answers stream in as Markdown; code blocks have Copy; under each answer Copy and a line like "answered by Haiku 5.5 ·
  2.4 s"; under the last one also Ask again.
- Under the field: the profile (its dot in the week's colour), the model (Haiku by default) and thinking (off by
  default). A pick holds for that chat; a new chat goes back to the defaults.
- The week shows in cl_audit's colours: green, amber from 50%, red from 80%, crimson from 95%. cl_quick reads no usage of
  its own: the numbers are what Claude Code reports after each answer.
- When a profile's week (or 5-hour limit) is full, the chat says when it resets and offers the profile with the most
  room: **Ask on Work** sends your question there. If the profile has a standby account with room, it also offers
  **Switch to p•••@example.com…**: after the sign-in the chat starts a new chat on the same profile (a chat may not
  carry across accounts) and sends what you had typed, with a line saying "Main is on p•••@example.com now."
- If a profile's Claude Code isn't signed in, the notice offers **Sign in…** (Claude Code's own sign-in, in Terminal)
  and Try again, which asks the question in a new chat.
- **Stop** ends the answer where it is and the chat goes on (an interrupt to the same `claude`, which still remembers
  the conversation). If Claude Code doesn't stop in 5 seconds, the chat ends instead.
- If Claude Code stops mid-answer, the window keeps what arrived and says the chat ended; Retry asks the last question
  in a new chat. The model and thinking pickers change the running `claude`, so a chat keeps its conversation.

## Settings ▸ General

- **Shortcut**: ⌥Space by default, four other Space shortcuts, Other… for any key with ⌘, ⌃ or ⌥, or Off. It's checked
  against macOS's own shortcuts that use Space (Spotlight, Finder's search, the input sources, as this Mac has them).
  Other apps' shortcuts can't be read and macOS lets two apps register the same key, so a clash with another app isn't
  caught and none is guessed at: if the key opens something else too, pick another. If macOS does refuse the key,
  Settings says so and offers a free one. It's registered the way macOS's own app shortcuts are, so there's no
  Accessibility permission to give.
- **Model** and **Thinking** for a new chat.
- **Open at login**: in the menu bar, ready for the shortcut.
- **Files**: the incognito note, cl_quick's own folder, any old chats saved by earlier versions, and
  **Remove cl_quick data…**.

## What it keeps, and what it sends

- `~/Library/Application Support/cl_quick/`: its profiles (with the addresses and ids of their accounts, never tokens),
  settings, the weeks last reported per account, and the work folders Claude Code runs in. Outside it: the login item, and any folder Sign in another account… made (a Claude Code
  folder, which Remove leaves).
- Chats: nothing. Claude Code runs with `--no-session-persistence`, so it writes no transcript, and a chat is never
  resumed. Checked on a signed-in folder (Claude Code 2.1.318): no file names the chat's session id or work folder, and
  no folder for it appears under `projects/`. Claude Code's built-in AGENTS.md plugin would note the session's id in
  `plugins/store/`; cl_quick sets `CLAUDE_CODE_AGENTS_MD_ROWS_EVERY_PROCESS=1` so it notes nothing (and
  `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`, so no memory folder appears). What any `claude` start still does, chat or not: it
  may refresh its feature-flag cache timestamp in the profile's `.claude.json` and take a backup copy of that file.
  Chats saved by earlier versions are Claude Code sessions in the profile's folder under
  `projects/<cl_quick's work folder>/`, deleted after 30 days by default; cl_quick doesn't touch them except in
  Remove cl_quick data….
- Remove cl_quick data… moves cl_quick's folder and any old quick chats to the Trash, turns the login item off and
  quits. Your Claude Code folders, their sign-ins and their other sessions stay.
- It sends nothing but your messages, through Claude Code. Claude Code runs with no tools, no MCP servers, no settings
  files and its non-essential traffic (telemetry, error reports, update checks) off. It gets only an allowlisted part of
  the Mac's environment (who you are, the language, proxies and certificates) and answers on the profile's own sign-in;
  keys, tokens and other providers' settings from your shell are left out.

## With cl_audit

cl_quick runs with or without [cl_audit](https://github.com/n-uf/cl_audit) and shares nothing with it while running.
On its first run it copies cl_audit's old quick chat settings (the shortcut, model and thinking), if there are any.

## Checks

`Checks/run.sh` checks the engine and the Markdown against a stand-in `claude` (no account, no network).
`Checks/real.sh` asks one real question on a throwaway, signed-out folder; with `QC_CONFIG=<folder>` it uses that
folder's account (a little of its usage) and checks the incognito chat end to end: a multi-turn conversation in one
`claude` still remembers, Stop keeps the conversation, the model changes in the running chat, and no transcript
appears under the folder's `projects/`.

## Versioning

Calendar versions, `YY.M.R`: the year and month of the release, then a counter within that month.

## Releases

Downloads come from [GitHub Releases](https://github.com/n-uf/cl_quick/releases): `cl_quick.dmg` and `cl_quick.zip`,
the same app. Notes go in CHANGELOG.md under "Unreleased" as changes land. To release, from a clean `main`:

```bash
scripts/release.sh --dry-run   # the next version
scripts/release.sh             # date the notes, commit "release X", tag vX
scripts/release.sh --push      # the same, then build the zip and disk image, push, publish the GitHub Release
scripts/release.sh --local     # only build dist/cl_quick.zip and dist/cl_quick.dmg, to check them
```

## License

PolyForm Perimeter 1.0.1, as cl_audit. See LICENSE.
