# Changelog

All notable changes to cl_quick are listed here, newest first. Calendar versions, `YY.M.R` (see README ▸ Versioning).

## Unreleased

This is 26.11.0, the first release: cl_audit's quick chat as an app of its own.

- **A floating Claude chat on a shortcut.** A bar first; the first message turns it into a chat window that stays
  floating on every Space until Esc hides it. Your own Claude Code answers, on the profile's account in use, and it
  counts against that account's limits.
- **Its own profiles.** The signed-in Claude Code folders found become profiles; Settings adds more (a folder found,
  Choose a folder…, or Sign in another account… through Claude Code in Terminal), names them, and picks the default.
- **Profiles with several accounts.** A profile is one Claude Code folder; the account signed in to it is in use and the
  others it has had are standby. **Switch to …** signs in again in the same folder as another account, through Claude
  Code's own sign-in in Terminal, after asking, and checks the result every 2 s (up to 10 minutes). The chat offers it
  when a week or 5-hour limit is full, and continues in a new chat on the same profile. Each account keeps its own
  week. No helper folders; cl_quick reads only the addresses in each folder's `.claude.json`, never the Keychain or a
  token. Addresses are masked everywhere.
- **A profile picker** in the chat, with each profile's week as Claude Code last reported it. A full week offers the
  profile with the most room: Ask on Work.
- **Model and thinking pickers**, Haiku and thinking off by default; every answer says which model gave it.
- **Any shortcut**: five Space shortcuts or Record another… (checked against macOS's Space shortcuts), with no
  Accessibility permission.
- **Light**: one menu bar app with no Dock icon, one `claude` at a time (closed after 2 minutes idle), no usage reading
  of its own; the app is about 3 MB.
- **Its files in one place**, listed in Settings, and Remove cl_quick data… moves them to the Trash.
- Settings in cl_audit's look; the chat in Claude's colours.
