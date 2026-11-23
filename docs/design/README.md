# Design notes

Sketches and design pages for cl_quick, kept as single self-contained HTML files. Open one in a browser. They use
sample addresses only (alex@example.com and the like); no real accounts appear in them.

A sketch shows what was proposed at the time. The app and the CHANGELOG say what shipped.

## Current

- [settings-strip-width-sketch.html](settings-strip-width-sketch.html): the Settings strip (General, profile tiles,
  APP / CHAT) reaches the window's right edge as cl_audit's does; tiles keep their width, left-aligned; today vs
  proposed, plus wrapping in a narrow window. Proposed 2026-11-22, not approved yet.
- [chat-tools-sketch.html](chat-tools-sketch.html): four chat tools and two helpers, six states at real size: find in
  chat (⌘F, a slim bar with "2 of 5" and ▲ ▼), quick actions (Explain, Shorter, Ask about this) floating above a
  selection, the quoted selection in the field, read aloud in an answer's footer, ↑ to recall the last message, and
  the right-click menu with Copy chat as Markdown; plus a light variant of the find bar. Proposed 2026-11-21, not
  approved yet.
- [chat-navigation-sketch.html](chat-navigation-sketch.html): the chat's new navigation, six states at real size: no
  forced scrolling, the floating ▲ ▼ ↓ control (New mark while text arrives), ⤒ in an answer's footer, the keys list
  with Thinking and Model on ⌥⌘ arrows, and the Shortcut row's new presets with the ⌥Space note. Proposed 2026-11-21,
  not approved yet.
- [chat-settings-instructions-sketch.html](chat-settings-instructions-sketch.html): Settings ▸ General split into
  App and Chat, and the Instructions row (the built-in text and your own, one document with jump links). Option E,
  the track with a raised key under the tiles, approved 2026-11-21.

- [inline-preview-sketch.html](inline-preview-sketch.html): an html code block in an answer shows its rendered
  page in place: Code | Page switch, open-big and copy in the block's header; five states (page by default, code
  chosen by the model, a tall page that scrolls inside its block, a still picture with a muted "still" tag, and
  streaming with no switch yet) plus a light variant. Proposed 2026-11-21, not approved yet.

## App sketches

- [menubar-usage-sketch.html](menubar-usage-sketch.html): the account in use's usage in the menu every time it
  opens (M1–M3: grey last known, read again at once), and in the menu bar icon itself (I1–I5: colour only, the
  bubble filling up, two bars, a number, a ring). Proposed 2026-11-21, not picked yet.

- [menu-accounts-sketch.html](menu-accounts-sketch.html): the menu showing which accounts a profile holds (standby
  rows, Add an account…).
- [model-controls-sketch.html](model-controls-sketch.html): the chat's model and thinking controls, four ideas.
- [compact-controls-sketch.html](compact-controls-sketch.html): small chat controls that open on hover.
- [chat-window-design.html](chat-window-design.html): the chat window, redesigned.
- [settings-rethought-sketch.html](settings-rethought-sketch.html): Settings, re-thought (the tile strip, General
  and profiles).
- [own-app-sketch.html](own-app-sketch.html): the quick chat as its own app, apart from cl_audit.
