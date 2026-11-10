# cl_quick

A floating Claude chat for the Mac, on a shortcut. Press it over any app: a bar opens; the first message turns it into a
chat window that stays floating, on every Space, until Esc hides it. It never brings another app forward.

Your own Claude Code answers, on the profile's account in use, and it counts against that account's limits. cl_quick
is one menu bar app with no Dock icon and one `claude` at a time, closed after 2 minutes idle.

## Install

Download the latest release, open the disk image and drag cl_quick to Applications. It needs macOS 13 or later and
[Claude Code](https://code.claude.com/docs/en/setup), signed in.

To build it yourself: `./build.sh` (Xcode's command-line tools; it installs into /Applications and opens it), or
`./build.sh --no-install`.

## Profiles

A profile is a Claude Code folder cl_quick chats on: `~/.claude`, a `~/.claude-*` folder, or any folder set with
`CLAUDE_CONFIG_DIR`. On its first run cl_quick takes every one it finds that is signed in, named after the folder (Main
for `~/.claude`, Work for `~/.claude-work`).

In Settings (the menu bar icon ▸ Settings…) each profile has a tile and a card: its name, the account signed in to its
folder (read from the folder's own `.claude.json`, never the Keychain), its week as Claude Code last reported it,
whether the shortcut chats on it, and whether the chat's profile picker offers it. The **+** tile adds one: a folder
found, Choose a folder… (it must be a signed-in Claude Code folder), or Sign in another account…, which makes a new
folder and opens Claude Code's own sign-in for it in Terminal.

## The chat

- Return sends, Shift-Return adds a line, Esc or ⌘W hides it, ⌘N starts a new chat.
- Answers stream in as Markdown; code blocks have Copy; under each answer Copy and a line like "answered by Haiku 5.5 ·
  2.4 s"; under the last one also Ask again.
- Under the field: the profile (its dot in the week's colour), the model (Haiku by default) and thinking (off by
  default). A pick holds for that chat; a new chat goes back to the defaults.
- The week shows in cl_audit's colours: green, amber from 50%, red from 80%, crimson from 95%. cl_quick reads no usage of
  its own: the numbers are what Claude Code reports after each answer.
- When a profile's week is full, the chat says when it resets and offers the profile with the most room: **Ask on
  Work** sends your question there.
- If Claude Code stops mid-answer, the window keeps what arrived and offers Retry.

## Settings ▸ General

- **Shortcut**: ⌥Space by default (⌃⌥Space on a first run if the Claude app is installed, as its Quick Entry may use
  ⌥Space), four other Space shortcuts, or Record another… for any key with ⌘, ⌃ or ⌥. It's checked against macOS's
  shortcuts that use Space and Quick Entry; other keys aren't checked. It's registered the way macOS's own app
  shortcuts are, so there's no Accessibility permission to give.
- **Model** and **Thinking** for a new chat.
- **Open at login**: in the menu bar, ready for the shortcut.
- **Files**: each profile's quick chats, cl_quick's own folder, and **Remove cl_quick data…**.

## What it keeps, and what it sends

- `~/Library/Application Support/cl_quick/`: its profiles, settings, the weeks last reported, and the work folders
  Claude Code runs in. Outside it: the login item, and any folder Sign in another account… made (a Claude Code
  folder, which Remove leaves).
- Each chat is a Claude Code session, which Claude Code keeps in the profile's folder under
  `projects/<cl_quick's work folder>/` and deletes after 30 days by default.
- Remove cl_quick data… moves cl_quick's folder and each profile's quick chats to the Trash, turns the login item off
  and quits. Your Claude Code folders, their sign-ins and their other sessions stay.
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
folder's account and removes its session afterwards.

## Versioning

Calendar versions, `YY.M.R`: the year and month of the release, then a counter within that month.

## License

PolyForm Perimeter 1.0.1, as cl_audit. See LICENSE.
