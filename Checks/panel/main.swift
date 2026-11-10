// The quick chat panel's checks, without a mouse or any event posting: a MOVE never changes the size, and QuickChat.fit
// stays out while the user moves or sizes the panel. The real panel is opened (read-only: nothing is written under the
// user's folders) and moved far from the screen's middle, and the way a move and a live resize reach the panel is called
// directly: setFrameOrigin as a move does, `isMoving` as QCDragView sets it around performDrag, and the window delegate's
// "will start" / "did end" of a live resize.
//   Checks/panel.sh

import AppKit

Files.readOnly = true
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let chat = QuickChat.shared
chat.start()

var failed = 0, passed = 0
func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    if ok { passed += 1 } else { failed += 1; print("FAIL \(name) \(detail())") }
}
func spin(_ s: TimeInterval = 0.4) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }
func panel() -> QuickChatPanel? { NSApp.windows.compactMap { $0 as? QuickChatPanel }.first }
func note(_ name: String) -> Notification { Notification(name: Notification.Name(name)) }
func oneTurn() -> QuickChatTurn { var t = QuickChatTurn(question: "q", answer: "a", model: "Haiku 5.5"); t.phase = .done; return t }

chat.open()
spin(0.8)
guard let p = panel() else { print("FAIL no panel"); exit(1) }

// ── the bar ───────────────────────────────────────────────────────────────────────────────────────
let bar = p.frame.size
check("the bar opens at the card's width and its content's height", bar.width == QuickChatRoot.width + 2 * QuickChatRoot.margin, "\(bar)")
check("idle: not moving, not resizing", p.isIdle)
check("the panel is its own window delegate (macOS calls will-start / did-end of a live resize on it)", p.delegate === p)
check("the panel is a resizable window and borderless", p.styleMask.contains(.resizable) && !p.styleMask.contains(.titled))

// a move as the window server does it: the origin changes, many times, the size never
p.isMoving = true
for i in 0..<500 {
    p.setFrameOrigin(NSPoint(x: -30000 + Double(i) * 7, y: 400 + Double(i % 37) * 3))
    if i % 100 == 0 { spin(0.02) }
}
check("a move keeps the bar's size", p.frame.size == bar, "\(p.frame.size) vs \(bar)")
// the content changing in the middle of a move (the field grows by two lines): macOS holds the window to the content's own
// least height, which is not fit(); fit() itself, called by hand now, must leave the frame as it is
let topBeforeGrowth = p.frame.maxY
chat.model.field = "a\nb\nc"
spin(0.5)
check("a growing field keeps the bar's top edge", abs(p.frame.maxY - topBeforeGrowth) < 0.5, "\(p.frame.maxY) vs \(topBeforeGrowth)")
let midMove = p.frame
chat.fit()
check("fit() stays out during a move", p.frame == midMove, "\(p.frame) vs \(midMove)")
p.isMoving = false
check("the move ended", p.isIdle)
chat.fit()
spin(0.3)
check("after the move the bar takes its content's height (grows, width alone)", p.frame.height > bar.height && p.frame.width == bar.width, "\(p.frame.size)")
chat.model.field = ""
spin(0.5)
check("the bar returns to its height when the lines go", abs(p.frame.height - bar.height) < 0.5, "\(p.frame.height) vs \(bar.height)")

// a live resize: while it is under way fit() stays out; when it ends the user's size is kept
p.windowWillStartLiveResize(note("start"))
check("a live resize is not idle", !p.isIdle)
chat.model.field = "a\nb\nc\nd"
spin(0.5)
let before = p.frame
chat.model.field = ""        // the lines go: only fit() would shrink the bar back, and it must not now
spin(0.5)
chat.fit()
check("fit() stays out during a live resize", p.frame == before, "\(p.frame) vs \(before)")
// the user drags the bottom edge down by 50: macOS sets the frame, then says "did end"
var f = p.frame
f.size.height += 50; f.origin.y -= 50
p.setFrame(f, display: true)
p.windowDidEndLiveResize(note("end"))
check("a live resize ended: idle again", p.isIdle)
let sized = p.frame
spin(0.4)
check("the user's bar size stays after the resize", p.frame.size == sized.size, "\(p.frame.size) vs \(sized.size)")
chat.model.field = ""
spin(0.5)
check("the extra height the user gave the bar is kept when the lines go (content's height + 50 + the 3 lines' share)", p.frame.height >= bar.height + 50 - 0.5, "\(p.frame.height)")

// ── the chat ─────────────────────────────────────────────────────────────────────────────────────
p.setFrameOrigin(NSPoint(x: -30000, y: 900 - p.frame.height))     // room below for the taller chat: fit() keeps a panel on screen
let barTop = p.frame.maxY
chat.model.turns = [oneTurn()]
spin(0.8)
check("bar to chat keeps the top edge", abs(p.frame.maxY - barTop) < 0.5, "\(p.frame.maxY) vs \(barTop)")
let chatSize = p.frame.size
check("the chat opens at the card's width with the first height", chatSize.width == bar.width && abs(chatSize.height - (QuickChatRoot.windowHeight + 2 * QuickChatRoot.margin)) < 0.5, "\(chatSize)")

p.isMoving = true
for i in 0..<500 { p.setFrameOrigin(NSPoint(x: -30000 + Double(i) * 5, y: 300 + Double(i % 53) * 2)) }
spin(0.3)
check("a move keeps the chat's size", p.frame.size == chatSize, "\(p.frame.size)")
chat.model.turns.append(oneTurn())
spin(0.5)
chat.fit()
check("fit() leaves a chat alone during a move", p.frame.size == chatSize, "\(p.frame.size)")
p.isMoving = false

// the user makes the chat shorter and narrower; it stays that way
p.windowWillStartLiveResize(note("start"))
var g = p.frame
g.size.height = 360; g.size.width = 420; g.origin.y += chatSize.height - 360
p.setFrame(g, display: true)
p.windowDidEndLiveResize(note("end"))
let userChat = p.frame.size
chat.fit(); spin(0.4)
check("the user's chat size is kept by fit()", p.frame.size == userChat, "\(p.frame.size) vs \(userChat)")
chat.hide(); chat.open(); spin(0.5)
check("hide and open keep the size", p.frame.size == userChat, "\(p.frame.size)")

// a new chat (the bar), then a first message: the width is kept, the chat's height is the user's
chat.model.newChat()
spin(0.6)
check("the bar after a new chat keeps the width", p.frame.width == userChat.width, "\(p.frame.width)")
chat.model.turns = [oneTurn()]
spin(0.8)
check("the chat comes back at the height the user gave it", abs(p.frame.height - userChat.height) < 0.5 && p.frame.width == userChat.width, "\(p.frame.size) vs \(userChat)")

// ── the least sizes are the system's, from the content's own frames ───────────────────────────────
check("the least width is 320 of card plus the margin", abs(p.contentMinSize.width - (QuickChatRoot.minWidth + 2 * QuickChatRoot.margin)) < 0.5, "\(p.contentMinSize)")
check("the chat's least height holds a line of chat and the field", p.contentMinSize.height >= QuickChatRoot.minWindowHeight + 2 * QuickChatRoot.margin - 0.5, "\(p.contentMinSize)")

print(failed == 0 ? "panel checks: \(passed)/\(passed) passed" : "panel checks: \(failed) failed, \(passed) passed")
exit(failed == 0 ? 0 : 1)
