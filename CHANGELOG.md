# Changelog

All notable changes to cl_quick are listed here, newest first. Calendar versions, `YY.M.R` (see README ▸ Versioning).

## Unreleased

- **Read an answer aloud.** A speaker button after ↻ in each finished answer's footer ("Read aloud") reads the answer
  with the Mac's own voice, on the device (Claude's voice isn't available to an app that runs `claude -p`). Press it
  again, or hide the panel, start a new chat or ask again, to stop; the button is a stop glyph while it reads, and only
  one answer reads at a time. The Markdown marks are left out and a code block is said as "code block". An answer in
  your Mac's own language is read in the voice chosen in System Settings ▸ Accessibility ▸ Spoken Content; one in
  another language, in the system's default voice for it (yours when none is installed). Nothing is sent or kept.
- **Copy the chat as Markdown.** ⌥⇧⌘C copies the whole open chat: your messages under a bold **You:** and the
  answers under **Claude:**, exactly as written (headings, lists and code blocks with their fences and languages; a
  block left open by a stopped or unfinished answer is closed), so it pastes well into a note or a GitHub issue.
  Pictures are `[image]` and files `[file: name]`. The answer's footer says "Copied" for a moment, as it does for a
  single answer. Nothing is written anywhere but the pasteboard. The keys list's Write page has it.
- **↑ recalls your last message.** In the field, while it is empty, ↑ puts your last message of the chat in it (the
  caret at the end) to edit and send again; ↑ again goes further back, ↓ goes forward, and ↓ past the newest empties
  the field. Edit the recalled text and ↑ ↓ are normal caret keys again, as they are with text typed or an input
  method composing. Only the open chat's messages, from memory, and only their text (attachments are not recalled); a
  new chat starts empty. The keys list's Write page has it.
- **Quick actions on selected text.** Select text in an answer and a small bar appears just above the selection (below
  it when there is no room above; never under the pointer or over the selection) with three actions. **Explain** and
  **Shorter** send a follow-up at once: your selection as a Markdown blockquote, then "Explain this." or "Say this more
  briefly." (the draft in the field and its attachments are left alone). **Ask about this** puts the quoted selection into
  the field, after what is there and with the caret after it, for you to finish. The bar goes when the selection is
  cleared, on a scroll, a click, a resize, Esc (the first Esc closes it, the next hides the panel) or when the panel loses
  the keyboard. The same three follow the text's own items (Copy, Look Up…) in the right-click menu of an answer, and below them in a group of their own
  comes **Copy chat as Markdown** (⌥⇧⌘C). The actions are never offered while an answer is
  streaming, after the chat ended, with a full limit or without a profile, and not for selections in your own messages,
  the thinking text or the field. Nothing is stored: the quoted text lives in memory until it is sent.- **Find in chat (⌘F).** ⌘F opens a small find bar over the top of the answers, under the header (the window keeps its
  size): a search field, "n of m", ▲ ▼ and ✕. It works wherever the keyboard is in the panel (the field, an answer, a
  page in an answer). Typing searches every message of yours and every answer of the open chat, live and ignoring case
  and accents; each match is highlighted in place with a soft background and the current one stronger, and the view
  scrolls to the current one at once (only when it is not in view already; the view stops following the end, like any
  scroll up). Return or ⌘G is the next match, ⇧Return or ⇧⌘G the previous, wrapping round; Esc closes the bar first
  (and clears the highlights), a second Esc hides the panel. Matches inside code blocks and table cells count. Not
  searched: the thinking text a click opens, the notices and footers, and the code of an html block while its page shows;
  a code block or table that scrolls sideways is brought into view up and down only. The bar's text lives in memory only
  and goes with the bar (also on a new chat and when the panel hides). The keys list's Move page names ⌘F and ⌘G ⇧⌘G.- **An html block shows its page in place.** A finished ```` ```html ```` block in an answer now shows the page it
  draws right inside the block, by default. Its header has a small **Code | Page** switch, **⤢** (opens the page in the
  separate window, as Preview did) and Copy, which copies the code on either side. A block the model fences as
  ```` ```html code ```` (a snippet meant for pasting) starts as code. A block draws only once it is complete, never
  while it is still being written. The page shows at its own height, up to about half the panel; a taller page scrolls
  inside its block, and a swipe stays with the view it started on (the page, or the chat). Only the page in view is
  live; the others are still pictures held in memory, which come back to life when you scroll to them or rest the
  pointer on them. While a page has the keyboard, typing goes to the field; ⌘C copies a selection in the page. Every
  page is isolated exactly like the window's (no scripts, nothing fetched, links do nothing, nothing stored on the
  Mac), with no click needed, which the local-listener check now also confirms for pages shown in place.
- **A way back to your message from the bottom of a long answer.** With a single message of yours in the chat, the right
  handle had no ▲ ▼ (they needed two messages), so at the bottom of a long answer there was no handle at all. Now the
  handle shows ▲ ▼ with a single message too, whenever it starts above or below the view (or the view is not at the
  bottom), one of them dimmed when it has nowhere to go, so the stack keeps its size. With two or more messages both
  always show. A short exchange fully in view still has no right handle. (⌘[ and ⌘] already went to a single message.)
- **Model and thinking keys are now the fn arrows, easier to press.** fn↑ fn↓ step thinking up and down, and fn→ fn←
  step the model up and down, wherever the keyboard is in the panel (the field, an answer, a page). On a Mac keyboard
  they are the Page Up, Page Down, End and Home keys, and the dedicated keys do the same. ⇧fn↑ and ⇧fn↓ scroll the
  answers a page up and down (and stop following unless that reaches the bottom), as plain fn↑ and fn↓ did. The ⌥⌘
  arrows are gone (macOS's and the field's again), and so are plain Page Up and Page Down scrolling and End's jump to
  the bottom: ⌘J jumps to the latest and follows. The controls' VoiceOver hints and the keys list say the new keys.
- **Moving in a chat.**
  - **Edge handles.** Two thin pills stand in the answers' side gutters, above the field. The pointer resting on one for
    about 0.15 s opens a stack beside it (inward, in a solid box); it closes about 0.5 s after the pointer leaves. Nothing
    slides or fades. Right: ▲ ▼ (previous and next message of yours, lighter bubble for a second where you land) and ↓ jump
    to latest; its pill is accent coloured while text has arrived below, until you reach the bottom. Left: ⤒ (start of the
    answer, while its first line is above the view) and copy, for the answer at the view's bottom edge while its footer is
    out of sight; both work while it streams. The handles keep clear of the resize band, the drag surfaces and the scroller;
    the answers' text column is narrower by the gutters (19 pt left, about 31 pt right: the scroller's track and the strip).
  - **Each answer's footer** is now ⤒ copy ↻ (⤒ only while the answer's first line is above the view).
  - **Keys:** ⌘J jump to latest; ⇧⌘J start of the answer in view; ⌘[ ⌘] previous and next message of yours; ⇧⌘C copies the
    answer in view once you have scrolled up (else the last answer); ⇧fn↑ and ⇧fn↓ (⇧Page Up and ⇧Page Down on a Mac
    keyboard) scroll the answers (and stop following), even while the field has the keyboard.
    Buttons' tooltips end with their key.
  - **Behaviour:** a resize at the bottom keeps the bottom and following; a resize mid-chat keeps what you are reading;
    hiding and reopening restores the place and whether it follows; Ask again jumps to the bottom and follows.
  - **No animation anywhere in this:** every jump is instant, and the handles and the keys list's pages switch at once.
- **The keys list has three pages**, as tabs in the look of the cl_audit site's (Model & window · Move · Write: equal
  segments across the list's width, the chosen one a lit plate that snaps to it), always the height of the tallest, so it
  never resizes; a click on a tab turns the page, and the last page is remembered. The pointer over the list is a hand
  over the tabs and an arrow elsewhere, and the text cursor is back once it leaves the list.
- **Step controls** lose the dot under the step in use (the lit bars already show it); the bars are centred in their column.
- **No forced scrolling while an answer streams.** The chat followed the end of the text even when you had scrolled up to
  read. Now it follows only while you are at the bottom (within a few points) when new text arrives. Scroll up by any
  means (wheel, trackpad, scroller, ⇧fn↑, selecting text) and new text never moves the view; scroll back down by hand,
  press the new **jump to latest** button (labelled "Jump to latest", shown only while you are not at the bottom, with a
  mark while text has arrived below), or send a message, and it follows again. The jump is instant.
- **Shortcuts that don't clash with macOS.**
  - **Model and thinking keys are no longer ⌘ arrows** (they are the fn arrows, below). Plain ⌘ arrows were taken by the
    chat, but in a Mac text field they are the caret's jumps to the line's and the text's start and end; they now reach
    the field and a selected answer's view again. ⇧⌘ arrows still select; ⌃⌘ arrows aren't cl_quick's. ⌘1–⌘5 (size) and
    ⌃1–⌃6 (place) are unchanged.
  - **The opener's presets are ⌃⇧Space, ⇧⌘Space and ⌥Space** (then Other… and Off), and a new install opens with
    ⌃⇧Space. The old presets clashed: ⌘Space is Spotlight, ⌃Space and ⌃⌥Space are macOS's input-source switching, and
    ⌥⇧Space types a non-breaking space. ⌥Space stays for people used to it; while it's selected, Settings says "⌥Space
    normally types a non-breaking space; with this shortcut it opens cl_quick instead." A shortcut you already saved is
    kept as it is: an old ⌃Space shows as Other… with its input-source note.
- **AddressPrivacy comes from cl_kit.** The module that hides an account address moved to
  [cl_kit](https://github.com/n-uf/cl_kit) (v26.11.3, `Privacy/`); cl_quick now builds it from the vendored copy, like the
  other shared modules, and no longer keeps its own in `Shared/`. Nothing changes in the app: the code is the same.
- **The chat's prompt tells Claude about Preview.** Both prompts (with and without web links and search) now say that a
  fenced `html` block shows as a page in the chat (its code one click away, ⤢ for a window; a snippet for pasting is
  fenced ```` ```html code ````), that it should be self-contained (inline CSS and SVG only, no scripts, no
  external images, fonts or links, as none of that loads), and that it is for when a visual layout helps or the user
  asks; otherwise the answer stays Markdown. Answers should pick HTML more often when a visual helps, and the pages
  should render whole.
- **Shared modules from cl_kit.** ProfileCore, Runs and ClaudeAuth (with the shared sign-in, ClaudeSignIn) now come from a
  tagged release of [cl_kit](https://github.com/n-uf/cl_kit), copied into `Vendor/cl_kit-<tag>/` by `scripts/vendor.sh`,
  instead of cl_audit's code at a pinned commit plus cl_quick's own patches. The sign-in and the runner are the same code;
  ProfileCore also takes cl_audit's later changes (account and organisation ids, the reader's state machine), which
  cl_quick doesn't use yet. Still built without the Keychain read. CI runs cl_kit's suites on the copy and checks it is
  exactly its tag.
- **Custom instructions.** Settings ▸ General has two sub-pages, chosen on a recessed track under the tiles, in the same
  tray (small capitals, the chosen one a raised key, as cl_quick shares with cl_audit's Card style selector): **APP**
  (first; Shortcut, Dictation, Blur addresses, Open at login and Updates) and **CHAT**, "What new chats start with.
  Changes apply to new chats; open chats keep theirs.": **Model**, **Thinking** and **Links and search** (moved from
  General) and a new **Instructions** row. The track shows only on the General tile (on a profile its room stays empty,
  so the tray keeps its height); General no longer has a page title; the last sub-page is remembered while cl_quick runs;
  the data strip stays under both. The Instructions box is one text view of about
  seven lines that scrolls inside itself, so the window never changes height with what is typed. Its first lines are the
  built-in instructions in force (the web or the no-web text, swapped live by Links and search), dimmed, with a small lock
  and read-only (selectable, not editable); then a hairline; then your own text, which is all that is edited, counted
  ("n / 1,000" under the box, amber from 900, red at the limit), capped at 1,000 characters (a paste too) and stored.
  The box opens scrolled to your text; the caret can't enter the built-in part. Two light links on the row's label line,
  "Built in · Custom", scroll the box to either part (at once; nothing animates), and the link of the
  part in view is underlined in orange as it scrolls. Your text is saved as you type and added after the fixed instructions, under "The user's own instructions:", and never replaces them; an empty
  box adds nothing. The text is part of what a chat's `claude` is started with, so it applies to new chats: an
  open chat keeps the text it started with and is never restarted for a change, while an empty bar takes it at once.
  Remove… clears it with the rest of cl_quick's data. New settings.json key: `instructions`.
- **The chat's profile menu matches the menu bar's.** Under each profile's row, its standby accounts are rows
  ("<address> · standby", **Switch…** at the right, the address blurred until the pointer is on the row) and, after them,
  **Add an account…**. A standby row starts the same switch as the menu bar's row (same guards, same "Switch Main to this
  account?" question). Add an account… opens Settings on that profile with its form open; the menu bar's menu has the same
  row after each profile's standby rows. Both are dimmed while a sign-in for the profile is waited for.
- **The switch question's address unblurs under the pointer.** The alert runs modally and gets no mouse enter or exit
  for its address, so it was blurred whatever the pointer did; the label now reads the pointer's place itself.
- **A blurred address is no longer the address.** A blur over the real text keeps its length and letter shapes, which a
  screenshot gives back by trying candidates. Everywhere an address is blurred (the chat's notes and keys, the profile
  menu, the menu bar's blocks and standby rows, the switch question) what is drawn is now one fixed stand-in, blurred, the
  same for every address; the real address is drawn only while the pointer is on it. An address is given the stand-in's room
  and no more (a longer one is cut while revealed), so its length is in no neighbour's place; a reveal ends when the pointer
  leaves, the app loses focus, a window closes or a menu opens, and nothing fades between the two. In words (VoiceOver, an
  item's title) it is now "hidden address", not its first letter and domain. Old screenshots of the blur or of the words
  show the length and letter shapes, or the first letter and the domain. The blur is the new `AddressPrivacy` module (`Shared/AddressPrivacy/`,
  shared with cl_audit, with its own checks in `Checks/addressprivacy.sh` and CI).
- **The chat's waiting note can be hidden.** It has a × at its top right (it only hides the note; the sign-in keeps
  waiting). While hidden, the lamp by the profile picker is the waiting one and the picker's menu has "Waiting for the
  sign-in…  Show". The note returns by itself when the switch ends.
- **No stale status line while a switch waits.** "Main is on … now." from the last switch goes as soon as a new switch
  (or a sign-in again) begins.
- **Preview for HTML blocks.** A code block marked `html` (or `htm`) in an answer can show as a web page in one
  separate "Preview" window, which opens beside the chat panel (a second press replaces the page and brings the window
  forward); its control is now **⤢** in the block's header, and the page also shows in place (the entry above). The
  page is isolated:
  JavaScript is off, nothing is fetched (images, styles, fonts, frames, prefetch and preconnect hints, link pings and
  refreshes all stay off the network, which a check with a local listener confirms), a click on a link does nothing,
  link previews, Safe Browsing lookups, downloads and new windows are off, the right-click menu only copies, and
  nothing is stored on the Mac. The web view exists only while the window is open.
- **Tables in answers.** A Markdown table in an answer is drawn as a grid, not as raw text with pipes: a semibold
  header, thin row separators, columns aligned as the alignment row says, and bold, italics, `code` and links inside the
  cells. Columns fit their content and wrap in a narrow panel; a table with too many columns to fit scrolls sideways
  inside its own frame. While an answer streams, the table shows as soon as its alignment row is in and rows appear as
  they arrive. Copy and ⌘⇧C still copy the Markdown source.
- **One sign-in window, closed after it.** Every sign-in (Switch…, Sign in again…, a folder found, a new account in a
  new folder) goes through the sign-in shared with cl_audit (ClaudeAuth's ClaudeSignIn). Its Terminal window closes by
  itself on a sign-in, a wrong account, Stop and the 10-minute timeout; one that was declined or failed stays open to be
  read until Return, the next sign-in or Stop. Stop and the timeout now end Claude Code's `claude auth login` in that
  window too, and a new sign-in ends the one before it.
- **Clearer switching.** The switch question says the browser must be signed in to claude.ai as that account first. While
  the sign-in waits, a short checklist says what to check in the browser ("Logged in as" before Authorize, Switch account if
  it's wrong), with the address blurred. After a wrong account the note says the browser was signed in as B, not A, that
  Main is on B now, and whether B is also in use on another profile, with **Try again as A** and **Keep B** (when B is also
  in use on another profile there is no Keep B, only Try again as A and a plain dismiss). A sign-in
  declined in the browser, one Claude Code didn't confirm, and each way a sign-in can fail have their own words, and a
  window Terminal never ran is the "couldn't start" alert.
- **No Terminal profiles left behind.** Terminal keeps a profile for every settings file it opens, with its dead command;
  cl_quick now names its settings file "cl_quick sign-in" and removes the kept profiles that ran its own sign-ins, at every
  sign-in's start and once its window is gone (never a profile Terminal uses as default or at startup).
- **Two guards.** A sign-in doesn't start while a `claude auth login` already runs on the folder, or while another app
  (cl_audit) holds the folder's sign-in lock.
- **The account is confirmed by Claude Code itself.** After a sign-in a short `claude` on the folder says which account
  it is (its `initialize` answer); the folder's `.claude.json` is only a guess until then. Still no Keychain: cl_quick
  doesn't even build the Keychain reader.
- A new account in a new folder now runs `claude auth login` instead of a whole `claude` session.

## 26.11.0 — 2026-11-15

This is 26.11.0, the first release: cl_audit's quick chat as an app of its own.

- **Digit keys in the chat.** ⌘1 to ⌘5 size the panel (Small, Standard, Large, Tall, Wide), ⌃1 to ⌃6 place it at a
  bottom or top corner or centre of its screen; both on any keyboard layout, and in the keys list. macOS can take
  ⌃1–⌃6 for Desktop switching.
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
  broken. Account addresses are shown in full in Settings; everywhere else they are blurred until the pointer is on them.
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
  with standby accounts shows them as rows in its group, under the account in use and its bars (see the next item).
- **Standby accounts as rows of their profile.** In the menu bar menu a profile's standby accounts are rows right under
  its block, so the menu shows that a profile holds several accounts: dimmed, a hollow lamp, the address and "· standby",
  no usage. Pointing at one highlights it, sharpens the address and shows a quiet **Switch…**; a click anywhere on the
  row asks the usual switch question. While a sign-in for the profile is waited for, its rows are dimmed further and
  inert (VoiceOver reads them as disabled). VoiceOver reads the masked address, "standby" and "switch". Lines separate
  profiles only.
- **Addresses blur instead of being masked.** Wherever cl_quick draws an account address (the menu's rows and standby
  rows, the chat's notes and Switch to… button, the switch question) it is blurred and sharp while the pointer is
  on it; only the words VoiceOver reads keep the masked form. **Settings ▸ General ▸ Blur addresses** (on by default)
  turns it off: addresses then show in full, sharp, everywhere, at once in the chat and the next time a menu opens.
- **A quiet chat header.** Once the bar has become a chat window, its header shows only the usage meters ("5h" and
  "wk", with reset times when there's room) and a darker capsule with **+** (new chat) and **✕** (hide). No profile
  name and no address. The window resizes from its edges and moves from any empty area.
- **Model and thinking as bar controls**, always visible in one outlined group, Haiku and thinking off by default; every
  answer says which model gave it. Click a bar to pick it; click the right or left half of a label to step up or
  down, wrapping round; the scroll wheel and ⌘ arrow keys step too (⌘↑ ⌘↓ thinking, ⌘→ ⌘← model; ⇧⌘ arrows still select in the field,
  ⌃A and ⌃E move to a line's start and end). A keys button lists the shortcuts. A warm tint
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
