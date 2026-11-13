# Changelog

All notable changes to cl_quick are listed here, newest first. Calendar versions, `YY.M.R` (see README ▸ Versioning).

## Unreleased

This is 26.11.0, the first release: cl_audit's quick chat as an app of its own.

- **A floating Claude chat on a shortcut.** A bar first; the first message turns it into a chat window that stays
  floating on every Space until Esc hides it. Your own Claude Code answers, on the profile's account in use, and it
  counts against that account's limits.
- **Its own profiles.** The signed-in Claude Code folders found become profiles; Settings adds more (a folder found,
  Choose a folder…, or a new account in a new folder, signed in through Claude Code in Terminal), names them, and picks
  the default.
- **Settings with a tile per profile.** General and each profile are tiles along the top, with a lamp for the profile's
  health (signed in, waiting for a sign-in, sign-in broken) and a + tile to add a profile. A profile's page shows the
  account in use in its own box, with its address, plan and two bars, the 5-hour limit and the week, with their
  shares and reset times. Standby accounts are slim rows with **Switch…** and **Forget…** and no usage (one folder
  holds one sign-in, so a standby account's limits aren't known). **Sign in again…** appears only when the sign-in is
  broken. Account addresses are shown in full in Settings; prompts and dialogs may mask them.
- **Profiles with several accounts.** A profile is one Claude Code folder; the account signed in to it is in use and the
  others it has had are standby. **Switch…** signs in again in the same folder as another account, through Claude
  Code's own sign-in in Terminal, and checks the result every 2 s (up to 10 minutes). Before it starts, the question
  says that Claude Code in Terminal and editors on that folder moves to the new account, sessions running now
  included, and that the Claude app keeps its own sign-in. The chat offers it when a 5-hour or week limit is full, and
  continues in a new chat on the same profile. Each account keeps its own limits, and after a switch the new account's
  numbers show, not the old one's. **Forget…** drops a standby account from the list, signing nothing out. No helper
  folders; cl_quick reads only the addresses in each folder's `.claude.json`, never the Keychain or a token.
- **The account in use, and its numbers, as they are now.** The folder's `.claude.json` is read again whenever it
  changed, so a sign-in made outside cl_quick counts at once. Limits are kept only for the account the answering Claude
  Code says it is, while the folder is still on it; numbers over 5 minutes old never show a full limit or an offer
  (the menu shows them grey as last known, and none over an hour old, except a full limit whose reset is still ahead:
  that stays in the menu, grey, as "Week full · last known" until it resets), and a standby account is offered
  with no numbers.
- **A profile picker** in the chat: a key in the controls row, with a menu of the profiles, each with its week as Claude
  Code last reported it and the address of its account in use, blurred until the pointer is on it, with a copy button.
  The menu also has **Settings for <profile>…** and **Add a profile…**. A full limit's notice names the window that is
  full (5-hour limit or week) and offers the profile with the most room: Ask on Work.
- **A rich menu bar menu.** Each profile's block shows its name with a dot in its level's colour, the account in use
  with a green lamp (address blurred until the pointer is on it), the 5-hour and week bars with their share and time
  to reset, and how old the numbers are; only the account in use shows usage. Old numbers are asked for again in the
  background when the menu opens (`get_usage` only, one `claude` at a time), nothing else is sent or read. A profile
  with standby accounts has **Switch account ›** under its block (masked addresses, the usual switch question).
- **A quiet chat header.** Once the bar has become a chat window, its header shows only the usage meters ("5h" and
  "wk", with reset times when there's room) and a darker capsule with **+** (new chat) and **✕** (hide). No profile
  name and no address. The window resizes from its edges and moves from any empty area.
- **Model and thinking as bar controls**, always visible in one outlined group, Haiku and thinking off by default; every
  answer says which model gave it. Click a bar to pick it; click the right or left half of a label to step up or
  down, wrapping round; the scroll wheel and ⌥⌘ arrow keys step too. A keys button lists the shortcuts. A warm tint
  marks Fable and thinking at Extra or Max. The model bars are the newest Haiku, Sonnet, Opus and Fable the account
  has, as Claude Code itself lists them.
- **Live usage in the bar.** The bar's usage indicator is a label ("5h" or "wk", whichever is fuller), two thin
  stacked bars (5 hours over the week) and the share of the fuller window. The numbers come from Claude Code when the
  bar opens: no message is sent to a model, and nothing is read from the Keychain.
- **Ask about the selected text in the app you're in.** Select text anywhere, then right-click ▸ Services ▸ **Ask
  cl_quick** (also the app menu ▸ Services; a keyboard shortcut can be set in System Settings ▸ Keyboard ▸ Keyboard
  Shortcuts ▸ Services). cl_quick's bar opens with the selection in the field as a quote, ready to edit and not sent,
  and your question goes under it. Text already in the field stays above the quote; a selection over 20,000 characters
  is cut there, with a line saying so. No Accessibility permission: macOS hands the selection over. Nothing about it is
  kept.
- **Images in the chat.** Paste a screenshot or picture (⌘V) or drop image files on the bar or the chat window: they
  show as thumbnails over the field (up to 5, each with a ✕) and go with the message, scaled down in memory to 1568 px.
  Nothing is saved, so chats stay incognito. An image alone is a message too.
- **Files in the chat.** Drop PDFs and text files (Markdown, CSV, JSON, code and the like) from Finder on the bar or the
  chat window, or copy them in Finder and press ⌘V: they show as chips next to the thumbnails (a symbol, the name, the
  page count or size, each with a ✕) and go with the message as documents, so Claude reads them. A PDF up to 15 MB and
  100 pages, a text file up to 400 KB, 5 attachments a message with the pictures; and per chat, counting what was sent
  earlier and what waits, 20 MB for everything attached, 100 PDF pages and 400 KB of text files. Word, Excel, zip,
  binaries, text that isn't UTF-8 and password-protected PDFs are refused with a muted line, only regular files are
  read (never a pipe or a device), and Claude Code still has no file tools. Files are kept in memory only, never
  written anywhere, and a file alone is a message too. A chat that finally outgrows the model ends with a line saying
  so (Retry asks again in a new chat).
- **A mic button** next to Send starts macOS Dictation into the field; ⌘D turns it on and off from the keyboard.
- **Links and search.** Paste a link, or ask about something current, and Claude can open the page or search the web.
  It runs with Claude Code's two web tools, WebFetch and WebSearch (`--tools WebFetch,WebSearch`, allowed up front so
  print mode never has to ask), and nothing else: no Bash, no files, no MCP. While a tool runs, a muted line beside the
  dot says so ("Reading example.com…", "Searching the web for “…”…"); the answer is the whole reply, the text before and
  after the call, and ⌘⇧C copies it all. What a page says is data for the answer, never instructions; the pages are
  read for that answer only and nothing is stored. Settings ▸ General ▸ **Links and search**, on by default; off, no
  tools at all, as before. A change applies from the next message (after the answer under way, if one is running): the chat then starts anew, since the tools are fixed when `claude` starts, and says so. Pages count toward the account's usage.
- **Any shortcut**: five Space shortcuts or Other… (any key held with ⌘, ⌃ or ⌥), with no Accessibility permission. It
  warns only about real clashes: macOS's own shortcuts, or a key another app holds (when macOS refuses it).
- **Incognito chats.** Quick chats are incognito: nothing is saved on this Mac. Your messages still go to Anthropic under
  the profile's account. `claude` runs with `--no-session-persistence`, so it writes no transcript, and nothing is ever
  resumed: a chat lives only in its running `claude` and ends with it. It ends after 15 minutes idle (window open or
  hidden), on New chat (⌘N), on another profile or account, if `claude` crashes or needs a sign-in, and when cl_quick
  quits; the window says so ("This chat ended after 15 minutes idle. Nothing was saved.") and the next message starts a
  new chat. Retry after a crash asks the last question in a new chat. **Stop** interrupts the answer and the chat goes
  on (if Claude Code doesn't stop in 5 seconds, the chat ends). The model and thinking pickers change the running
  `claude`, so a chat keeps its conversation. A chat never continues on another account.
- **Light**: one menu bar app with no Dock icon, one `claude` at a time (kept while a chat is open, ended after
  15 minutes idle), no usage reading of its own (the numbers come from Claude Code); the app is about 4.5 MB.
- **Its files in one place**, listed in Settings, and Remove… (General) moves them to the Trash. Quick chats write no
  files; chats saved by earlier versions are listed as old chats and removed with the rest.
- Settings in cl_audit's look; the chat in Claude's colours.
- **An update notice.** About once a day cl_quick asks GitHub Releases (anonymously, User-Agent "cl_quick") for the latest
  release; when it is newer than the app, the menu bar menu shows **Update available: <version>**, which opens the
  release's page. Nothing is downloaded or installed. **Settings ▸ General ▸ Updates** turns it off (no request at
  all); the time of the last check and the newest version seen are kept in `updates.json`.
