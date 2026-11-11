# cl_quick

> [!CAUTION]
> ## Not yet stable
>
> **cl_quick is young and still changing. Its settings, the few files it stores and the way it talks to Claude Code are not final.**
>
> Version numbers are dates (YY.M.R), not semantic versions, so any release may change them, and a newer Claude Code can stop parts of cl_quick working until it is updated. cl_quick stores nothing beyond its settings and a few small files in `~/Library/Application Support/cl_quick` (levels.json, models.json, profiles.json, settings.json and updates.json) and the work folders Claude Code runs in, and it has no backups or exports. Read the [CHANGELOG](CHANGELOG.md) before you upgrade.

A floating Claude chat for the Mac, on a shortcut. Press it over any app: a bar opens; the first message turns it into a
chat window that stays floating, on every Space, until Esc hides it. It never brings another app forward.

Your own Claude Code answers, on the profile's account in use, and it counts against that account's limits. cl_quick
is one menu bar app with no Dock icon and one `claude` at a time, kept while a chat is open and ended after 15 minutes
idle.

**Quick chats are incognito: nothing is saved on this Mac. Your messages still go to Anthropic under the profile's
account.** A chat lives only in the running `claude` (it runs with `--no-session-persistence`), so it ends with it: after
15 minutes idle, on New chat (⌘N), on another profile or account, if `claude` crashes, or when cl_quick quits. The
window then says "This chat ended after 15 minutes idle. Nothing was saved." and the next message starts a new chat.

## Install

Once the first release is published, download it from [GitHub Releases](https://github.com/n-uf/cl_quick/releases),
open the disk image and drag cl_quick to Applications. Until then, build it from source (below). It needs an Apple silicon Mac,
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

In Settings (the menu bar icon ▸ Settings…) the profiles are tiles along the top, next to General and a **+** tile.
A tile has a lamp (green signed in, amber waiting for a sign-in, red when the sign-in is broken), the profile's name and
the account in use. A profile's page has:

- Its name and folder, and Show in Finder.
- **Accounts**. The account in use comes first, in a box with its address, its plan, an "In use" tag and two bars, the
  5-hour limit and the week, each with its share and when it resets, as Claude Code last reported them (or "No limits
  yet"). Under it, each standby account is a row with its address and when it was last in use, and two buttons,
  **Switch…** and **Forget…**. A standby account shows no usage: one folder holds one sign-in, so its limits aren't
  known here. **Sign in again…** appears only when the sign-in is broken (or the folder has no account signed in).
  **Add an account…** takes an address and signs in as it; the account in use then goes to standby. Accounts are
  read from the folder's own `.claude.json`, never the Keychain.
- **In the chat**: Make default (the profile the shortcut opens on), and whether the chat's profile picker offers it.
- **Remove from cl_quick…**, which leaves the folder, its sign-in and its sessions as they are.

**Forget…** asks first, then drops a standby account from the profile's list. Nothing is signed out and no session is
touched; the account comes back if it signs in on that folder again.

Account addresses are shown in full in Settings. Prompts, dialogs and the chat's notices may mask them
(p•••@example.com).

The **+** tile adds a profile: a folder found on this Mac (Add, or Sign in… for one that isn't signed in), Choose a
folder… (it must be a signed-in Claude Code folder), or "A new account, in a new folder", which takes a name, makes
`~/.claude-<name>` and opens Claude Code's own sign-in for it in Terminal.

### Switching accounts

- cl_quick asks first: "Switch Main to p•••@example.com?" The question says that Claude Code in Terminal and editors on
  that folder (for a folder other than `~/.claude`, Claude Code pointed at it with `CLAUDE_CONFIG_DIR`) moves to the new
  account, sessions running now included, and that the Claude app keeps its own sign-in. It's not just the quick chat.
- Then Claude Code's own sign-in (`claude auth login --email …`) opens in Terminal and finishes in your browser. The
  browser's claude.ai session decides which account actually signs in, so cl_quick checks the result: it looks at the
  folder's `.claude.json` every 2 seconds, for at most 10 minutes, until the account changes. It never sees a password or
  a token and never touches the Keychain.
- If another account signed in, the chat says so ("Signed in as m•••@example.com, not p•••@example.com") and offers
  to try again. After 10 minutes with no change it stops looking and says "No sign-in in 10 minutes." (in the chat, and
  on the profile's page in Settings), with a way to try again and Dismiss (OK in Settings).
- Limits belong to the account: after a switch the chat's new `claude` is asked for the new account's limits at once,
  and the new account's own numbers show, never the old account's. They are kept per account (its id in Claude Code's
  file), not per organization.
- Addresses are in full in Settings. Prompts and dialogs may mask them (p•••@example.com). In the chat the address is in
  the profile menu only: each profile's row has the address of its account in use (never a standby one's), blurred
  until the pointer is on it; a copy button beside it copies it.

## The chat

- Return sends, Shift-Return adds a line, Esc or ⌘W hides it, ⌘N starts a new chat.
- Answers stream in as Markdown; code blocks have Copy; under each answer Copy and a line like "answered by Haiku 5.5 ·
  2.4 s"; under the last one also Ask again.
- The header (once the bar has become a chat window) shows only the usage meters, "5h" and "wk", each with its bar,
  its share and, when there's room, when it resets, and, at the right, a darker capsule with **+** (new chat) and **✕**
  (hide). No profile name and no address. The empty part of the header moves the window.
- Under the field, in one row: the profile, then the model (Haiku by default) and thinking (off by default) together in
  one outlined group, always visible, then a keys button, and at the end the mic and Send. A pick holds for that chat;
  a new chat goes back to the defaults.
  - Model and thinking are rows of bars. Click a bar to pick it. Click the right half of a control's label for the next
    value up and the left half for the one before, wrapping round past either end. The scroll wheel steps too, and so
    do ⌥⌘↑ and ⌥⌘↓ (thinking) and ⌥⌘→ and ⌥⌘← (model).
  - A warm tint marks the costly steps: Fable, and thinking at Extra or Max.
  - The model bars are the newest Haiku, Sonnet, Opus and Fable the account has, as Claude Code itself lists them.
  - The keys button opens a list of the shortcuts: the ⌥⌘ arrow keys, the label halves, Return, ⇧Return, ⌘N, ⌘D
    (Dictation on/off), Esc and ⌘W, and the shortcut that opens cl_quick. A click elsewhere or Esc closes it.
  - In the bar (before the first message) the row also has the usage indicator: a label ("5h" or "wk", whichever is
    fuller), two thin stacked bars (the 5-hour window over the week) and the share of the fuller window, such as
    "5h ▬ 78%" ("full" when a limit is full). On a narrow bar it drops the share, then the label.
- The profile is a key in that row (a dot in the colour of its fuller limit, and its name). It opens a menu with each
  profile, its week under the name, and its account in use's address, blurred until the pointer is on it, with a copy
  button beside it (the copy shows "Copied" for a moment); below, **Settings for <profile>…** and **Add a profile…**.
  The address is nowhere else in the chat.
- The mic button left of Send starts macOS Dictation into the field (cl_quick stays in the background: the panel takes
  the keyboard as it does for the shortcut, so Dictation types into the field, not the app behind); ⌘D does the same
  as a click, on and off (also for a Dictation macOS's own shortcut started); a click again,
  sending, a new chat or hiding stops it. With Dictation off in macOS it says once where to turn it on.
- **Images.** ⌘V with a screenshot or picture on the clipboard (⌃⇧⌘4 copies one), or with image files copied in Finder,
  attaches it; so does dropping image files or a picture from a page on the bar or the chat window. Each shows as a
  small thumbnail over the field with a ✕ (Delete in an empty field removes the last one); up to 5 go with a message,
  and a sixth is left out with a line saying so. Files that aren't images are refused with a line. Text on the
  clipboard always pastes as text. An image alone is a message too. Each is scaled down in memory to 1568 px on its
  long side and sent as PNG (JPEG for a large photo) in the same connection as the text, so it stays incognito: no
  file is made for it, and the chat shows it only as a thumbnail until it ends. A file you drop is read, never copied.
- The window resizes from its edges and corners, and moves from any empty area of it (the header, the gaps around
  and between answers); the field, the buttons and the controls never move it.
- The limits show in cl_audit's colours: green, amber from 50%, red from 80%, crimson from 95%. The numbers come from
  the chat's own Claude Code: it starts as the bar opens (the same `claude` the chat then uses; with nothing asked it
  ends after 3 minutes) and is asked for the account's limits then, after each answer, and when the bar opens again (at
  most once a minute) (Claude Code's `get_usage`, which sends no message to a model and uses its own sign-in, and reads
  nothing from the Keychain). After each answer Claude Code also reports them on its own, which stays as the fallback.
- When a profile's 5-hour limit or week is full, the chat's notice names the window that is full ("Main's 5-hour limit
  is full, resets 23:20.") and offers the profile with the most room: **Ask on Work** sends your question there. If the profile has a standby account with room, it also offers
  **Switch to p•••@example.com…**: after the sign-in the chat starts a new chat on the same profile (a chat may not
  carry across accounts) and sends what you had typed, with a line saying "Main is on p•••@example.com now."
- If a profile's Claude Code isn't signed in, the notice offers **Sign in…** (Claude Code's own sign-in, in Terminal)
  and Try again, which asks the question in a new chat.
- **Stop** ends the answer where it is and the chat goes on (an interrupt to the same `claude`, which still remembers
  the conversation). If Claude Code doesn't stop in 5 seconds, the chat ends instead.
- If Claude Code stops mid-answer, the window keeps what arrived and says the chat ended; Retry asks the last question
  in a new chat. The model and thinking pickers change the running `claude`, so a chat keeps its conversation.

## Settings ▸ General

- **Shortcut**: ⌥Space by default, four other Space shortcuts, Other… for any key with ⌘, ⌃ or ⌥, or Off. It warns
  only about real clashes, and with a way out (a button that picks a preset none of macOS's own shortcuts uses):
  - a macOS shortcut that uses the key, as this Mac has them set (Spotlight, Finder's search, the input sources);
  - a key another app holds, when macOS refuses to register it ("taken by another app").

  Other apps' shortcuts can't be read, and macOS lets two apps register the same key, so nothing else is guessed at: if
  the key also opens something else, pick another. It's registered the way macOS's own app shortcuts are, so there's no
  Accessibility permission to give.
- **Model** and **Thinking** for a new chat. The model is one of four families, Haiku, Sonnet, Opus and Fable, each the
  newest the account has, by Claude Code's own list (asked when a chat's `claude` starts, with `initialize`, which sends
  nothing to a model; kept per profile and account in models.json). A family the account lacks isn't offered. Thinking
  is Off or the efforts the chosen model takes (Low, Medium, High, Extra, Max); a step it doesn't take moves to the
  nearest. Before any list is known: the four aliases, and Low to High. The setting keeps the family, not a version.
- **Open at login**: in the menu bar, ready for the shortcut.
- **Updates**: on by default. About once a day cl_quick checks GitHub Releases and, when a newer version exists, the
  menu bar menu shows **Update available: 26.11.3**; it opens the release's page in your browser. Nothing is
  downloaded or installed by the app. Off: no request at all (see "What it keeps, and what it sends").
- A strip at the bottom: the incognito note ("Quick chats are incognito: nothing is saved on this Mac."), the size of
  cl_quick's own files, any old chats saved by earlier versions, **Show in Finder**, and **Remove…**, which moves
  cl_quick's data to the Trash.

## What it keeps, and what it sends

- `~/Library/Application Support/cl_quick/`: its profiles (with the addresses and ids of their accounts, never tokens),
  settings, the limits last reported per account, and the work folders Claude Code runs in. Outside it: the login item,
  and any folder "A new account, in a new folder" made (a Claude Code folder, which Remove leaves).
- Chats: nothing. Claude Code runs with `--no-session-persistence`, so it writes no transcript, and a chat is never
  resumed. Checked on a signed-in folder (Claude Code 2.1.318): no file names the chat's session id or work folder, and
  no folder for it appears under `projects/`. Claude Code's built-in AGENTS.md plugin would note the session's id in
  `plugins/store/`; cl_quick sets `CLAUDE_CODE_AGENTS_MD_ROWS_EVERY_PROCESS=1` so it notes nothing (and
  `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`, so no memory folder appears). What any `claude` start still does, chat or not: it
  may refresh its feature-flag cache timestamp in the profile's `.claude.json` and take a backup copy of that file.
  Chats saved by earlier versions are Claude Code sessions in the profile's folder under
  `projects/<cl_quick's work folder>/`, deleted after 30 days by default; cl_quick doesn't touch them except in
  Settings ▸ General ▸ Remove….
- Remove… (it asks "Move cl_quick's data to the Trash?") moves cl_quick's folder and any old quick chats to the Trash, turns the login item off and
  quits. Your Claude Code folders, their sign-ins and their other sessions stay.
- Apart from your messages (through Claude Code, below), the one thing it sends is an update check: about once a day it
  asks GitHub for cl_quick's latest release (`api.github.com/repos/n-uf/cl_quick/releases/latest`, anonymous, with the
  User-Agent "cl_quick"), compares the version and, if a newer one exists, adds "Update available" to the menu, which
  opens the release's page; nothing is downloaded or installed. It keeps the time of the last check and the newest
  version seen in `updates.json`. Settings ▸ General ▸ Updates turns it off, and then no request is made.
- Your messages go through Claude Code. Claude Code runs with no tools, no MCP servers, no settings
  files and its non-essential traffic (telemetry, error reports, update checks) off. It gets only an allowlisted part of
  the Mac's environment (who you are, the language, proxies and certificates) and answers on the profile's own sign-in;
  keys, tokens and other providers' settings from your shell are left out.

## With cl_audit

cl_quick runs with or without [cl_audit](https://github.com/n-uf/cl_audit) and shares nothing with it while running.
On its first run it copies cl_audit's old quick chat settings (the shortcut, model and thinking), if there are any.

## Checks

`Checks/run.sh` checks the engine and the Markdown against a stand-in `claude` (no account, no network).
`Checks/bars.sh` checks the model and thinking controls in the real panel, with four, three and two families, at 320,
440 and 640: a bar for every family, always shown and ending before Send, picking any value moves nothing, a click on
each bar's centre picks that bar, a click on a label's right or left half goes round forward or back, the scroll wheel
steps, the keys button opens and closes its list (a click elsewhere or Esc closes it), and the bar's usage indicator
shows the limit closest to full with its label before the bars on that window's row.
`Checks/real.sh` asks one real question on a throwaway, signed-out folder; with `QC_CONFIG=<folder>` it uses that
folder's account (a little of its usage) and checks the incognito chat end to end: a multi-turn conversation in one
`claude` still remembers, Stop keeps the conversation, the model changes in the running chat, and no transcript
appears under the folder's `projects/`.

## Versioning

cl_quick uses calendar versions, `YY.M.R`, like the other n-uf projects:

- `YY` is the year of the release date (`26` for 2026).
- `M` is the month of the release date, without a leading zero: a release made in November 2026 is `26.11.x`.
- `R` counts releases within that month and starts again at `0` in a new month.

Releases are tagged `vX.Y.Z` (for example `v26.11.0`). The number lives in `VERSION`; no release has been made yet, and
`26.11.0` is the number the first one will carry. Changes go into [CHANGELOG.md](CHANGELOG.md) under "Unreleased" as
they land. Releases will be published on [GitHub Releases](https://github.com/n-uf/cl_quick/releases) as
`cl_quick.dmg` and `cl_quick.zip`, the same app. To release, from a clean `main`:

```bash
scripts/release.sh --dry-run   # the next version
scripts/release.sh             # date the notes, commit "release X", tag vX
scripts/release.sh --push      # the same, then build the zip and disk image, push, publish the GitHub Release
scripts/release.sh --local     # only build dist/cl_quick.zip and dist/cl_quick.dmg, to check them
```

A version can't signal a breaking change, so read the notes before updating.

## License

[PolyForm Perimeter 1.0.1](LICENSE): source-available. You may use, change and share it, but not to build a product
that competes with cl_quick.

---

cl_quick is an independent tool. It is not affiliated with, endorsed by or sponsored by Anthropic.
"Claude" is a trademark of Anthropic.
