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

Download `cl_quick.dmg` from the [latest release](https://github.com/n-uf/cl_quick/releases/latest), open the disk image
and drag cl_quick to Applications (or use `cl_quick.zip`, the same app), or build it from source (below). It needs an Apple silicon Mac,
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

Account addresses are shown in full in Settings. Everywhere else they are blurred until the pointer is on them; the
words VoiceOver reads and an item's title say "hidden address" (nothing of the address: no first letter, length or domain). What is blurred is not the address: it is one fixed stand-in
(`abcdefghijkl@mnopqrst.com`), the same for every address, so a screenshot of the blur gives nothing back (a blur over the
real text keeps its length and letter shapes); the real address is drawn only while the pointer is on it. This is the
`AddressPrivacy` module, shared with cl_audit in [cl_kit](https://github.com/n-uf/cl_kit) (`Privacy/`, README there).

The **+** tile adds a profile: a folder found on this Mac (Add, or Sign in… for one that isn't signed in), Choose a
folder… (it must be a signed-in Claude Code folder), or "A new account, in a new folder", which takes a name, makes
`~/.claude-<name>` and opens Claude Code's own sign-in for it in Terminal.

### Switching accounts

- cl_quick asks first: "Switch Main to this account?", with the account's address under it (blurred until the pointer
  is on it, while Blur addresses is on). The question says that Claude Code in Terminal and editors on
  that folder (for a folder other than `~/.claude`, Claude Code pointed at it with `CLAUDE_CONFIG_DIR`) moves to the new
  account, sessions running now included, and that the Claude app keeps its own sign-in. It's not just the quick chat.
  Its last line says the browser must be signed in to claude.ai as that account, and to switch it there first if it's on
  another one.
- Then Claude Code's own sign-in (`claude auth login --email …`) opens in Terminal and finishes in your browser. While it
  waits, a short checklist says what to do there: finish it in the browser; before pressing Authorize, check that "Logged
  in as" at the bottom of the page shows the address; if it doesn't, use Switch account there. In the chat the waiting
  note has a **×** at its top right that only hides it: the sign-in keeps waiting, the lamp by the profile picker is the
  amber waiting one meanwhile, and the picker's menu has a row "Waiting for the sign-in…  Show" that brings the note
  back (it also returns by itself when the switch ends). The line left by the last switch ("Main is on … now.") goes as
  soon as a new switch begins, so it never contradicts the waiting note. The
  browser's claude.ai session decides which account actually signs in, so cl_quick checks the result: it looks at the
  folder's `.claude.json` every 2 seconds, for at most 10 minutes, and once the login ends (or the file names another
  account) a short `claude` on the folder says which account it is. It never sees a password or a token and never
  touches the Keychain. The sign-in is the one shared with cl_audit ([cl_kit](https://github.com/n-uf/cl_kit)'s ClaudeSignIn): one window at a time,
  closed after a sign-in, a wrong account, Stop or the timeout (Stop and the timeout end `claude auth login` too); one
  declined or failed stays open to be read until Return, the next sign-in or Stop.
- A switch that ends without the account wanted says what happened, in the chat and on the profile's page in Settings,
  each way in its own words. If another account signed in: "The browser was signed in as <b>, not
  <a>. Main is on <b> now." (and "<b> is also in use on Work." when it is; each address blurred), with two
  compact keys, **Try again as** the account wanted (the same switch again) and **Keep** the one it is on now; when that
  account is also in use on another profile there is no Keep, only Try again as and a plain Dismiss (OK in Settings). Declined in
  the browser: "The sign-in was declined in the browser. The account in use hasn't changed." Signed in but Claude Code
  didn't confirm which account: "Signed in, but Claude Code didn't confirm which account. Check the account line in the
  menu." (the folder may have changed, so it never says "hasn't changed"). After 10 minutes with no change it stops looking
  and says "No sign-in in 10 minutes." A login that failed, ended on nobody or lost its Terminal window has its own line
  too; a sign-in that couldn't start at all (the folder isn't there, one already open, Terminal didn't run it) is the
  "The sign-in couldn't start" alert. The others can be dismissed (Dismiss in the chat, OK in Settings).
- Limits belong to the account: after a switch the chat's new `claude` is asked for the new account's limits at once,
  and the new account's own numbers show, never the old account's. They are kept per account (its id in Claude Code's
  file), not per organization. The account in use is the folder's `.claude.json` as it is at that moment (read again
  whenever it changed), so a sign-in made outside cl_quick (`claude auth login`, /login, another app) counts at once.
  Numbers are kept only for the account the answering `claude` says it is (its `initialize` answer) and only while the
  folder is still on that account: an answer that arrives after the folder moved to another account is dropped.
- Addresses are in full in Settings' account rows, and blurred in its switch notes. Everywhere else they are blurred until the pointer is on them (the switch question's
  alert holds it under its words, in an accessory view); the words VoiceOver reads say "hidden address". In
  the chat's header there is none; the profile menu's rows have the address of the account in use, with a copy button
  beside it, and under each, in the same rows as the menu bar's menu, the profile's standby accounts (blurred at rest, clear
  while the pointer is on the row), and the chat's notes about an account change blur it too. The switch question's address
  is clear under the pointer inside the alert as well. A blurred address is the fixed stand-in blurred, never the address
  (`Checks/addressprivacy.sh` and the menu and panel suites assert it on what each piece draws); an address is given the
  stand-in's room and no more (a longer address is cut while revealed), so its length is never in a neighbour's place. A
  reveal ends when the pointer leaves, the app loses focus, a window closes or a menu opens. **Settings ▸ General ▸ App ▸
  Blur addresses** (on by default) turns the blur off: addresses then show in full, sharp, and the words hold them in full.

## The menu bar menu

Besides Quick chat, Settings… and Quit, the menu bar icon's menu has a block for each profile, drawn as cl_audit's menu
draws it: the profile's name with a dot in the colour of its fuller limit, the account in use with a green lamp
(`<address> · in use`, the address blurred until the pointer is on it), two bars, **5-hour** and **Week**, in green,
amber and red by level, each with its share and the time to its reset ("13% in 1h 5m"), and how old the numbers are
("Updated just now"). Numbers count as the account's state for 5 minutes: older ones are grey, as "Last known 12 min
ago", with no full limit, and ones over an hour old aren't shown ("No recent numbers"); the chat acts only on fresh
ones (no full-limit notice, Ask on … or switch offer on old numbers). A click on a block opens the quick chat on that profile. Only the account in use shows usage;
a profile with no numbers yet says "No usage yet". A profile's standby accounts are rows in its group, under the
account in use and its bars: dimmed, with a hollow lamp, the address (blurred until the row is highlighted) and
"· standby", and no usage. Point at one and it is highlighted, the address turns sharp and a quiet **Switch…** shows at
the right; a click anywhere on the row asks the same question as Switch… in Settings. While a sign-in for the profile is
waited for, its standby rows are dimmed further and do nothing. After the standby rows (or straight after the block when
there are none) comes **Add an account…**: a plus and the words, in the same dimmed look; it opens Settings on that profile
with its Add an account… form open, and is dimmed while a sign-in for the profile is waited for. Lines separate profiles
only, not a profile's block from its rows.

The chat's profile menu (the picker's) is built from the same rows: each profile's row (its week, its account in use with
the address blurred, a copy button) is followed by its standby accounts, each "<address> · standby" with **Switch…** at
the right on the highlight, and **Add an account…**. Choosing a standby account asks the same question and starts the same
switch as the menu bar's row (same guards: not while a sign-in is waited for on that profile, and only while the account
is still on standby); Add an account… hides the chat and opens Settings on that profile with the form open. After the
line come Settings for the chat's profile and Add a profile…, as before. The numbers are the ones Claude Code last gave cl_quick, shown at
once; when they are over 5 minutes old, opening the menu asks again in the background: one short-lived `claude` at a
time is sent `get_usage` and nothing else (no message to a model, no Keychain, no token), at most once every 3
minutes for a profile.

## The chat

- Return sends, Shift-Return adds a line, Esc or ⌘W hides it, ⌘N starts a new chat.
- **Find in chat (⌘F).** ⌘F opens a find bar over the top of the answers, under the header (it never changes the window's
  size): a search field, "n of m", ▲ ▼ and ✕. It works wherever the keyboard is in the panel (the field, an answer, a page
  in an answer), once the chat has a message. Typing searches all of the open chat's messages and answers, live, ignoring
  case and accents; every match is highlighted in place (a soft background, the current one stronger) and the view scrolls
  to the current one at once, when it is not in view already (like any scroll up it stops following the end). Return or
  ⌘G is the next match, ⇧Return or ⇧⌘G the previous (wrapping round); the first Esc closes the bar and clears the
  highlights, the second hides the panel. Code blocks and table cells are searched too. Not searched: the thinking text,
  the notices and footers, and the code of an html block whose page shows by default; a block that scrolls sideways is
  brought into view up and down only. The bar's text is memory only: it goes with the bar (a new chat or hiding the
  panel close it), nothing about it is written to disk.
- **Quick actions on a selection.** Select text in an answer and a small bar appears just above it (below it when there is
  no room above; never under the pointer or over the selection): **Explain** and **Shorter** send a follow-up at once, the
  selection as a Markdown blockquote and then "Explain this." or "Say this more briefly." (the field's draft and any
  attachments stay as they are); **Ask about this** puts the quoted selection into the field, after what is there, the
  caret after it, for you to finish. The bar is a small window of its own, so it never takes the keyboard from the selection.
  It goes when the selection is cleared, on a scroll, a click, a resize, Esc (first Esc: the bar; then the panel) or when the
  panel loses the keyboard. The same three follow the text's own items in an answer's right-click menu, with **Copy chat as Markdown** (⌥⇧⌘C) in a
  group of its own below them. Only selections in an answer count (not your
  own messages, the thinking text or the field), and none is offered while an answer streams, after the chat ended, with a
  full limit or without a profile. Nothing is written to disk.
- **Moving in a chat.** The chat follows the end of an answer as it streams only while you are at the bottom (within a few
  points) when new text arrives. Scroll up by any means (wheel, trackpad, scroller, ⇧fn↑, selecting text) and new text
  never moves the view; get back to the bottom (by hand, ⌘J or the ↓ button) or send a message and it follows again.
  Resizing at the bottom keeps the bottom; resizing mid-chat keeps what you are reading in place; hiding and reopening the
  panel restores the place and whether it follows. Every jump is instant (nothing animates).
  - Two **edge handles** stand in the answers' side gutters, above the field: thin pills at rest. The pointer resting on one
    for about 0.15 s opens its stack beside it, inward over the text, in a solid box; it closes about 0.5 s after the pointer
    leaves both. **Right:** ▲ ▼ (the previous and next message of yours, once there are two, or with one whenever the
    handle shows: it starts above or below the view, so a long answer read to the bottom still has a way back to its
    message; the landed bubble is lighter for about a second) and ↓ jump to latest (while not at the bottom; the pill takes the accent colour while text has arrived
    below, until you reach the bottom). **Left:** ⤒ (the start of the answer, only while its first line is above the view) and
    copy, for the answer at the view's bottom edge while its footer is out of sight (also while it streams: copy takes the text
    so far). Each answer's own footer has ⤒ copy ↻ and a speaker (⤒ only while its first line is above the view).
  - **Keys** (the panel's own, exact modifiers; none is a text edit): ⌘J jump to latest, ⇧⌘J the start of the answer at the
    view's bottom edge (the last one at the bottom), ⌘[ and ⌘] the previous and next message of yours (nothing at the ends),
    ⇧⌘C copies the answer in view once you have scrolled up (else the last answer), and ⇧fn↑ and ⇧fn↓ (⇧Page Up and
    ⇧Page Down on a Mac keyboard: they scroll the answers a page, and stop following unless that reaches the bottom) work
    even while the field has the keyboard; plain arrows keep their text meaning there. ⌘J jumps to the latest and follows.
  - The handles keep clear of the window's resize band (under 4 pt deep), the drag surfaces and the answers' scroller: the left
    one stands 5 pt in, the right one inward of the scroller's track (17 pt), and the text column starts after them.
- Answers stream in as Markdown; tables (header, alignment row, rows) are drawn as a grid whose cells wrap to the
  panel's width and scroll sideways when there are too many columns; code blocks have Copy; under each answer Copy and a line like "answered by Haiku 5.5 ·
  2.4 s"; under the last one also Ask again.
  - **Preview: an `html` block shows its page in place.** Once its fence has closed (while it streams it is code), the
    block shows the page inside itself. Its top row has **Code | Page** (the side shown is marked; your click wins for that
    block), **⤢** (the page in its own window, as before) and Copy, which copies the code whichever side shows. ```` ```html ````
    shows the page first, ```` ```html code ```` the code first: Claude is told to fence a snippet meant for pasting into a
    file that way.
  - The page shows at its own height, up to about half the panel's; a taller one scrolls inside the block. A swipe stays
    with whatever it started over: once the page is at its end, the next swipe (or wheel turn) scrolls the chat, and a
    swipe that started over the chat goes on scrolling the chat as it passes over a page. A page that appears or grows
    above what you are reading doesn't move it.
  - A click in the page lets you select its text and copy it with ⌘C; typing goes on to the reply field, and a click that
    selects nothing gives the keyboard back to the field.
  - Only the page in view is live: the others show a still picture of themselves (kept in memory only, gone with the chat)
    until they come back into view or the pointer rests on them, so nothing runs out of sight.
  - In the chat and in the window alike the page is isolated: no scripts, nothing fetched from the network, links, forms
    and downloads do nothing, and nothing about it is stored on the Mac. When that can't be set up, the block shows its code
    and says so.
- The header (once the bar has become a chat window) shows only the usage meters, "5h" and "wk", each with its bar,
  its share and, when there's room, when it resets, and, at the right, a darker capsule with **+** (new chat) and **✕**
  (hide). No profile name and no address. The empty part of the header moves the window.
- Under the field, in one row: the profile, then the model (Haiku by default) and thinking (off by default) together in
  one outlined group, always visible, then a keys button, and at the end the mic and Send. A pick holds for that chat;
  a new chat goes back to the defaults.
  - Model and thinking are rows of bars. Click a bar to pick it. Click the right half of a control's label for the next
    value up and the left half for the one before, wrapping round past either end. The scroll wheel steps too, and so
    do fn↑ and fn↓ (thinking) and fn→ and fn← (model), wherever the keyboard is in the panel. On a Mac keyboard these are
    the Page Up, Page Down, End and Home keys, and the dedicated keys do the same; with ⌘, ⌥ or ⌃ they are not
    cl_quick's, and nor are ⇧End and ⇧Home (⇧fn↑ and ⇧fn↓ scroll the answers). Plain ⌘ and ⌥⌘ arrows are macOS's own and
    reach the field (the caret jumps to the line's or the text's start and end) and a selected answer's view; ⇧⌘ arrows
    still select, and ⌃⌘ arrows aren't cl_quick's.
  - A warm tint marks the costly steps: Fable, and thinking at Extra or Max.
  - The model bars are the newest Haiku, Sonnet, Opus and Fable the account has, as Claude Code itself lists them.
  - **Digit keys** work while the panel has the keyboard, in the bar and in the chat window:
    - **⌘1 to ⌘5 size the panel,** as if you had sized it by hand: Small 420 × 440, Standard 520 × 580 (the first
      size), Large 720 × 760, Tall (the width it has, the screen's full visible height), Wide 960 × 70% of the
      screen's height. In the bar only the width changes (its height follows its content); in the chat window both
      do, and the chat keeps that size afterwards. The panel stays where it is: the corner or edge centre of its
      nearest place (as ⌃1–⌃6 name them) holds still, and a size larger than the screen is cut to it.
    - **⌃1 to ⌃6 place the panel on its screen,** at the size it has: ⌃1, ⌃2, ⌃3 bottom left, centre, right; ⌃4, ⌃5,
      ⌃6 top left, centre, right. The place is within the screen's visible frame (the menu bar and the Dock stay clear;
      the bottom keeps the 85 pt gap the first opening has, so ⌃2 is that place). The bar keeps growing as it does
      wherever you drag it. macOS can take ⌃1–⌃6 for itself: when "Switch to Desktop N" is turned on in System
      Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸ Mission Control, cl_quick never sees those keys.
  - The keys button opens a list of the shortcuts on three pages, under tabs in the look of the cl_audit site's (Model &
    window · Move · Write; click a tab to turn the page; the last page is remembered while cl_quick runs). The pointer is a
    hand over the tabs and an arrow elsewhere on the list, and the text cursor is back once it leaves the list:
    - **Model & window:** fn↑ fn↓ (thinking), fn→ fn← (model), the label halves, ⌘1–⌘5 (size) and ⌃1–⌃6 (place).
    - **Move:** ⌘J (latest, and follow), ⇧⌘J, ⌘[ ⌘] and ⇧fn↑ ⇧fn↓ (scroll the answers) (see "Moving in a chat" above), ⌘F
      (find in chat) and ⌘G ⇧⌘G (next, previous match).
    - **Write:** Return, ⇧Return, ⌘N, ⌘D (Dictation on/off), ⇧⌘C (copy the answer in view), Esc and ⌘W, the shortcut
      that opens cl_quick, ↑ in an empty field (your earlier messages) and ⌥⇧⌘C (copy the chat as Markdown).

    The list is as tall on every page, so switching never resizes it. A click elsewhere or Esc closes it.
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
  sending, a new chat or hiding stops it. With Dictation off in macOS it says once where to turn it on. Return while
  dictating stops it and shows the text, and Return again sends it (Settings ▸ General ▸ App ▸ **Dictation** can make the
  first Return send at once). The field grows with what you dictate.
- **⇧⌘C** copies the answer in view once you have scrolled up, else the latest complete answer, the same as that
  answer's Copy button.
- **↑ recalls your last message.** In the field, while it is empty (and nothing is being composed), ↑ puts your last
  message of this chat in it, the caret at the end, to edit and send again; ↑ again goes further back, ↓ goes forward, and
  ↓ past the newest leaves the field empty. Once you edit the recalled text, ↑ and ↓ are the caret's again. Only this
  chat's messages are recalled, from memory (a new chat starts empty), and only their text: attachments are not brought
  back. A repeat of the message before is skipped. While a recalled message is unedited, ↑ (and ⌃P) goes to the older
  message even when this one has several lines, and ↓ (⌃N) to the newer; to move the caret inside it, edit it first or
  use ←.
- **Copy the chat as Markdown.** **⌥⇧⌘C** copies the
  whole open chat: each message of yours under a bold **You:** and each answer under **Claude:**, as the answer was
  written (its headings, lists and code blocks with their fences and languages stay), a blank line between all of
  them, so it pastes well into a note or a GitHub issue. A picture is `[image]` and a file `[file: name]` after the
  message's text. A message with no answer (it failed) has no Claude part; an answer still streaming has its text so
  far. The answer's footer says "Copied" for a moment, as for a single answer. Nothing is kept: the copy is made from
  the chat in memory and goes only to the pasteboard. On a layout whose letters aren't Latin (Cyrillic) ⌥⇧⌘C follows
  the C key's place.
- **Read aloud.** The speaker button at the end of a finished answer's footer (after ↻; tooltip "Read aloud") reads the
  answer with the Mac's own voice, on the device: the text never leaves the Mac, and nothing is kept. (Claude's own
  voice is not available to an app that runs `claude -p`, so this is macOS's speech.) The button turns into a stop
  glyph ("Stop reading") while it reads; press it again to stop. Only one answer reads at a time: pressing another
  answer's speaker moves the reading there. Esc or hiding the panel, a new chat, and an answer that starts again also
  stop it. What is read is the answer's plain text: the Markdown marks (bold, links, headings, list marks, table
  pipes) are left out, and a code block is not read out: you hear "code block" in its place. The answer is read in the
  best voice installed for its language (your Mac's own when it can't be told): a Premium voice first, then an
  Enhanced one (the natural Siri voices are among them); between voices of the same quality, the one chosen in Spoken
  Content, then your region's accent. With only the
  compact voices installed, an answer in your own language is read in the voice chosen in System Settings ▸
  Accessibility ▸ Spoken Content and one in another language in the system's default voice for it (yours when none is
  installed). Better voices are a free download there: System voice ▸ Manage Voices…, then a Premium voice such as Ava
  or Zoe. Novelty voices and a Personal Voice are never used. It has no key.
- **Ask about the selected text in any app.** Select text, then right-click ▸ Services ▸ **Ask cl_quick** (also the
  app menu ▸ Services; a keyboard shortcut can be set in System Settings ▸ Keyboard ▸ Keyboard Shortcuts ▸ Services).
  The bar opens with the selection in the field as a quote, ready to edit and not sent, and your question goes under
  it. Text already in the field stays above the quote; a selection over 20,000 characters is cut there, with a line
  saying so. No Accessibility permission: macOS hands the selection over. Nothing about it is kept.
- **Keyboard layouts.** The chat's shortcuts and paste (⌘V, ⌘C, ⌘X, ⌘A, ⌘Z, ⌘N, ⌘W, ⌘D, ⇧⌘C) work on Cyrillic
  layouts such as Russian and Ukrainian too: on a layout whose letters aren't Latin they follow the key's place. The
  digit keys (⌘ with 1 to 5, ⌃ with 1 to 6) follow the key too, on the number row and the keypad, on any layout.
- **Images.** ⌘V with a screenshot or picture on the clipboard (⌃⇧⌘4 copies one), or with image files copied in Finder,
  attaches it; so does dropping image files or a picture from a page on the bar or the chat window. Each shows as a
  small thumbnail over the field with a ✕ (Delete in an empty field removes the last one); up to 5 go with a message,
  and a sixth is left out with a line saying so. Text on the clipboard always pastes as text. An image alone is a
  message too. Each is scaled down in memory to 1568 px on its long side and sent as PNG (JPEG for a large photo) in
  the same connection as the text, so it stays incognito: no file is made for it, and the chat shows it only as a
  thumbnail until it ends. A file you drop is read, never copied; a picture file over 256 MB is refused unread.
- **Files.** The same two ways take a PDF or a text file: drop files from Finder on the bar or the chat window, or copy
  them in Finder and press ⌘V. A PDF (up to 15 MB and 100 pages) and any text or code file (txt, Markdown, CSV, JSON,
  YAML, XML, HTML, logs, Swift, Python, JavaScript/TypeScript, Go, Rust, Java, C, Ruby, shell, SQL, TOML, CSS and the
  like; up to 400 KB, UTF-8) show as chips next to the thumbnails: a symbol, the name and the page count or size, each
  with a ✕. They count toward the 5 attachments of a message with the pictures. The whole conversation goes to the
  model with every message, so a chat also holds at most about 20 MB of attachments, 100 PDF pages and 400 KB of text
  files in all, counting what was sent earlier in it and what waits in the field (✕ gives the room back, a new chat
  starts from nothing); past that a muted line says so. Claude reads what you attached, with that message; it gets no
  access to your files or folders, and only regular files are read (a link to one is followed; pipes and devices are
  refused). A file it can't read (Word, Excel, zip, binaries, text that isn't UTF-8, a password-protected PDF) is
  refused with a muted line over the field ("cl_quick can't read .docx files yet."); one over a limit says by how much
  ("too long: 140 pages, up to 100"). A file alone is a message too, and the chat shows the chips, never the content.
  If a long chat finally outgrows the model ("Prompt is too long"), the chat ends with a line saying so; Retry asks the
  question again in a new one.
- **Links and search.** Paste a link in a message, or ask about something current, and Claude can read the page or
  search the web. While it does, a muted line beside the dot says what it is doing ("Reading example.com…", "Searching
  the web for “…”…") and goes when the text resumes; the answer is the whole reply (the text before and after the call),
  and Copy and ⌘⇧C take all of it. Stop works while a page is being read. Pages count toward the account's usage, like
  any answer. Settings ▸ General ▸ Chat ▸ **Links and search** turns it off. A change applies from the next message (after the
  answer under way, if one is running); the tools are fixed when `claude` starts, so that message starts a new chat and
  the window says "New chat; nothing from the last one was carried over."
- The window resizes from its edges and corners, and moves from any empty area of it (the header, the gaps around
  and between answers); the field, the buttons and the controls never move it.
- The limits show in cl_audit's colours: green, amber from 50%, red from 80%, crimson from 95%. The numbers come from
  the chat's own Claude Code: it starts as the bar opens (the same `claude` the chat then uses; with nothing asked it
  ends after 3 minutes) and is asked for the account's limits then, after each answer, and when the bar opens again (at
  most once a minute) (Claude Code's `get_usage`, which sends no message to a model and uses its own sign-in, and reads
  nothing from the Keychain). After each answer Claude Code also reports them on its own, which stays as the fallback.
- When a profile's 5-hour limit or week is full, the chat's notice names the window that is full ("Main's 5-hour limit
  is full, resets 23:20.") and offers the profile with the most room: **Ask on Work** sends your question there. If the
  profile has a standby account, it also offers the one seen most recently, with no numbers (a standby account shows no
  usage: "<address> is on standby."), as
  **Switch to <address>…** (the address blurred): after the sign-in the chat starts a new chat on the same profile (a chat may not
  carry across accounts) and sends what you had typed, with a line saying "Main is on <address> now."
- If a profile's Claude Code isn't signed in, the notice offers **Sign in…** (Claude Code's own sign-in, in Terminal)
  and Try again, which asks the question in a new chat.
- **Stop** ends the answer where it is and the chat goes on (an interrupt to the same `claude`, which still remembers
  the conversation). If Claude Code doesn't stop in 5 seconds, the chat ends instead.
- If Claude Code stops mid-answer, the window keeps what arrived and says the chat ended; Retry asks the last question
  in a new chat. The model and thinking pickers change the running `claude`, so a chat keeps its conversation.

## Settings ▸ General

Two sub-pages, chosen on a recessed track of small capitals under the tiles (in the same tray; shown only on the General
tile): **APP** (first; the last one shown is remembered) and **CHAT**, then, under both, a strip for cl_quick's own data.

**APP:**

- **Shortcut**: ⌃⇧Space by default, with ⇧⌘Space and ⌥Space, Other… for any key with ⌘, ⌃ or ⌥, or Off. ⌥Space stays for
  those used to it: it normally types a non-breaking space, and a line says so while it's selected. A shortcut saved by
  an earlier version is kept as it is, even if it's no longer one of these (⌃Space shows as Other…, with its note). It warns
  only about real clashes, and with a way out (a button that picks a preset none of macOS's own shortcuts uses):
  - a macOS shortcut that uses the key, as this Mac has them set (Spotlight, Finder's search, the input sources);
  - a key another app holds, when macOS refuses to register it ("taken by another app").

  Other apps' shortcuts can't be read, and macOS lets two apps register the same key, so nothing else is guessed at: if
  the key also opens something else, pick another. It's registered the way macOS's own app shortcuts are, so there's no
  Accessibility permission to give.
- **Dictation**: what Return does after dictating. **Shows text first** (the default: "Return after dictation shows
  the text; Return again sends it.") or **Sends at once** ("Return after dictation sends the text at once.").
- **Blur addresses**, **Open at login** (in the menu bar, ready for the shortcut) and **Updates**: on by default. About
  once a day cl_quick checks GitHub Releases and, when a newer version exists, the
  menu bar menu shows **Update available: 26.11.3**; it opens the release's page in your browser. Nothing is
  downloaded or installed by the app. Off: no request at all (see "What it keeps, and what it sends").

**CHAT**, "What new chats start with. Changes apply to new chats; open chats keep theirs.":

- **Model** and **Thinking** for a new chat. The model is one of four families, Haiku, Sonnet, Opus and Fable, each the
  newest the account has, by Claude Code's own list (asked when a chat's `claude` starts, with `initialize`, which sends
  nothing to a model; kept per profile and account in models.json). A family the account lacks isn't offered. Thinking
  is Off or the efforts the chosen model takes (Low, Medium, High, Extra, Max); a step it doesn't take moves to the
  nearest. Before any list is known: the four aliases, and Low to High. The setting keeps the family, not a version.
- **Links and search**: on by default. "Claude can open links and search the web. Pages count toward your usage." Off:
  Claude runs with no tools, as it did before, and a link in a message is only text. A change applies from the next message, in a new chat.
- **Instructions**: a few lines of your own ("Answer in Ukrainian unless I write in another language."), at most
  1,000 characters (typing and pasting stop there; a counter under the box, "n / 1,000", turns amber from 900 and red at
  the limit). The box is one text view of about seven lines that scrolls inside itself: the window never changes height
  with what is typed. Its first lines are the built-in instructions in force, dimmed and read-only (a small lock; the web
  or the no-web text, by Links and search, swapped live), then a hairline, then your text; it opens scrolled to your text.
  Two light links on the label line, "Built in · Custom", scroll the box to either part (at once; nothing
  animates); the one in view is underlined in orange. Only your part is edited, counted, capped and stored; the
  caret can't enter the built-in part, and selecting and copying it is fine. Saved as you type, for the app (not per profile). Your text is
  added **after** cl_quick's fixed instructions, under "The user's own instructions:", and never replaces them (with
  Links and search on, the fixed text is what says that a page's text is data, not instructions); an empty box adds
  nothing. They apply to new chats: the
  instructions are part of what a chat's `claude` is started with, so an open chat keeps the text it started with and is
  never restarted for a change (an empty bar takes it at once). Remove… clears them with the rest.

**The strip at the bottom**: with the incognito note ("Quick chats are incognito: nothing is saved on this Mac."), the size of
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
- Custom instructions (Settings ▸ General ▸ Chat): your text is kept in settings.json and sent to Claude Code, with the
  fixed instructions, as the chat's system prompt, so it goes to the model with every new chat; nothing else.
- Remove… (it asks "Move cl_quick's data to the Trash?") moves cl_quick's folder and any old quick chats to the Trash, turns the login item off and
  quits. Your Claude Code folders, their sign-ins and their other sessions stay.
- Apart from your messages (through Claude Code, below), the one thing it sends is an update check: about once a day it
  asks GitHub for cl_quick's latest release (`api.github.com/repos/n-uf/cl_quick/releases/latest`, anonymous, with the
  User-Agent "cl_quick"), compares the version and, if a newer one exists, adds "Update available" to the menu, which
  opens the release's page; nothing is downloaded or installed. It keeps the time of the last check and the newest
  version seen in `updates.json`. Settings ▸ General ▸ App ▸ Updates turns it off, and then no request is made.
- Links and search (on by default; Settings ▸ General ▸ Chat): Claude Code gets its two web tools, WebFetch and WebSearch
  (`--tools WebFetch,WebSearch --allowedTools WebFetch,WebSearch`), and nothing else, so it can read a page you link or
  search the web. The pages are fetched by Claude Code for that answer only, and the text goes to the model as part of
  the chat, under your account. cl_quick stores none of it: the chat stays incognito, the page text is never shown raw
  and is told to be data, never instructions. Off, Claude Code runs with no tools.
- Attached files (PDFs, text) go to Claude Code inside the message they are attached to, as document blocks in the same
  connection as the text, and are kept in memory only: nothing is copied to a temporary file, a cache or the app's
  folder, and a file you drop or copy is only read. Claude Code still has no file tools, so it sees nothing but what you
  attached. Like pictures, they stay in the running chat's conversation until it ends, and under the same account.
- Your messages go through Claude Code. Claude Code runs with no tools (only the two web tools above, when Links and
  search is on), no MCP servers, no settings
  files and its non-essential traffic (telemetry, error reports, update checks) off. It gets only an allowlisted part of
  the Mac's environment (who you are, the language, proxies and certificates) and answers on the profile's own sign-in;
  keys, tokens and other providers' settings from your shell are left out.

## With cl_audit

Other apps can open a quick chat with `cl-quick://chat?folder=<percent-encoded Claude Code folder>`: the bar opens on the
profile that uses that folder (as a click on it in the menu bar menu does), or, with no folder or one no profile uses, on
the default profile, the second case with a quiet line saying so. A URL only picks a profile and opens the bar: it never
sends a message, fills the field or changes anything, and the folder is matched by its path as written, never read.

cl_quick runs with or without [cl_audit](https://github.com/n-uf/cl_audit) and shares nothing with it while running
but a folder's sign-in lock (`~/Library/Caches/n-uf/signin-*.lock`), so the two never sign one folder in at once. Both
compile the same shared modules from source: a tagged release of [cl_kit](https://github.com/n-uf/cl_kit), copied into
`Vendor/cl_kit-<tag>/` by `scripts/vendor.sh <tag>` and never edited here (a change is a pull request to cl_kit and a new
tag). cl_quick builds them without cl_kit's `Auth/Keychain.swift`.
On its first run it copies cl_audit's old quick chat settings (the shortcut, model and thinking), if there are any.

## Checks

`Checks/run.sh` checks the engine and the Markdown against a stand-in `claude` (no account, no network); that includes
the arguments with Links and search on and off, and web answers (a tool call between two pieces of text, as a real
stream has it) with Stop in the middle of a tool. `Checks/panel.sh` runs the whole chat on the stand-in for those: the
whole answer, the activity line shown and then gone, Stop mid-tool, ⌘⇧C copying the full answer, the setting.
`Checks/instructions.sh` checks Custom instructions on the stand-in: what is stored and read back (the user's text only),
the box in the real text view (the built-in part above the user's is never changed by an edit or a paste, the caret stays out
of it, Links and search swaps it live, and the 1,000-character cap counts the user's part alone), the prompt a chat starts with (an empty box changes nothing, the text comes
after the fixed text, with and without web), that a new chat takes the current text while an open one keeps its own and
is never restarted, and Remove… clearing it; `Checks/run.sh` has the prompt's words and the chat's key.
`Checks/bars.sh` checks the model and thinking controls in the real panel, with four, three and two families, at 320,
440 and 640: a bar for every family, always shown and ending before Send, picking any value moves nothing, a click on
each bar's centre picks that bar, a click on a label's right or left half goes round forward or back, the scroll wheel
steps, the keys button opens and closes its list (a click elsewhere or Esc closes it), and the bar's usage indicator
shows the limit closest to full with its label before the bars on that window's row.
`Checks/menu.sh` checks the menu bar menu's profile blocks (their words, level colours, the address blurred until the
pointer is on it, no usage for a standby account, "No usage yet", the standby rows and Add an account… in each profile's
group and what choosing them does) and the background refresh of old numbers against
the stand-in `claude`: one at a time, throttled, only `get_usage` asked.
`Checks/signin.sh` checks the sign-in (ClaudeSignIn and the switch on it) against a stand-in Terminal and a stand-in
`claude auth login`: each outcome, a wrong account by id and by address and organisation, Stop and a new sign-in ending
the login, the lock and the process guard, a folder that isn't ready; first its lint that nothing cl_quick compiles can
read the Keychain. `Checks/vendor.sh` runs cl_kit's own checks of the shared modules on the vendored copy cl_quick
compiles, and `scripts/vendor.sh --check` confirms that copy is exactly its tag.
`Checks/real.sh` asks one real question on a throwaway, signed-out folder; with `QC_CONFIG=<folder>` it uses that
folder's account (a little of its usage) and checks the incognito chat end to end: a multi-turn conversation in one
`claude` still remembers, Stop keeps the conversation, the model changes in the running chat, and no transcript
appears under the folder's `projects/`.

## Versioning

cl_quick uses calendar versions, `YY.M.R`, like the other n-uf projects:

- `YY` is the year of the release date (`26` for 2026).
- `M` is the month of the release date, without a leading zero: a release made in November 2026 is `26.11.x`.
- `R` counts releases within that month and starts again at `0` in a new month.

Releases are tagged `vX.Y.Z` (for example `v26.11.0`, the first). The number lives in `VERSION`. Changes go into
[CHANGELOG.md](CHANGELOG.md) under "Unreleased" as they land. Releases are published on
[GitHub Releases](https://github.com/n-uf/cl_quick/releases) as
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
