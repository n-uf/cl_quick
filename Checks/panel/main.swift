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
check("the panel is borderless, and sized by the rim's handles (not the system's zones)", !p.styleMask.contains(.titled) && !p.styleMask.contains(.resizable))
check("resizeIncrements are the plain default", p.resizeIncrements == NSSize(width: 1, height: 1), "\(p.resizeIncrements)")

// ── the rim: eight handles with a fill the window server will deliver clicks to, in the rim only ────────────────────
guard let cv = p.contentView as? QuickChatHostingView else { print("FAIL the content view is not the hosting view"); exit(1) }
check("eight handles", cv.handles.count == 8, "\(cv.handles.count)")
check("every handle has a non-zero invisible fill (a fully transparent rim passes the mouse through)",
      cv.handles.allSatisfy { h in
          guard let c = h.layer?.backgroundColor.flatMap({ NSColor(cgColor: $0) }) else { return false }
          return c.alphaComponent >= 0.01 && c.alphaComponent <= 0.03
      })
let rim = QuickChatRoot.margin, W = p.frame.width, H = p.frame.height
func handle(at x: CGFloat, _ y: CGFloat) -> QCEdges? { (cv.hitTest(NSPoint(x: x, y: y)) as? QCResizeHandle)?.edges }
check("the rim is 8 pt", rim == 8 && QCResizeHandle.rim == rim)
check("left edge rim hit", handle(at: 4, H / 2) == .left)
check("right edge rim hit", handle(at: W - 4, H / 2) == .right)
check("top edge rim hit", handle(at: W / 2, H - 4) == .top)
check("bottom edge rim hit", handle(at: W / 2, 4) == .bottom)
check("corners hit (all four)", handle(at: 4, 4) == [.left, .bottom] && handle(at: W - 4, 4) == [.right, .bottom]
      && handle(at: 4, H - 4) == [.left, .top] && handle(at: W - 4, H - 4) == [.right, .top])
check("a corner square reaches about 13 pt along the rim", handle(at: 12, 12) == [.left, .bottom] && handle(at: 14.5, 14.5) == nil)
check("the card is never a handle: its middle, its padding, 1 pt inside its edge and its corners' arcs",
      handle(at: W / 2, H / 2) == nil && handle(at: 20, 20) == nil && handle(at: W - 20, H - 20) == nil
      && handle(at: rim + 1, H / 2) == nil && handle(at: W / 2, rim + 1) == nil && handle(at: W / 2, H - rim - 1) == nil
      && handle(at: 24, 24) == nil)
// DRAG must not dominate RESIZE: nothing in the rim moves the window, and no drag surface reaches the rim
func noDragInTheRim(_ label: String) {
    let wf = p.frame, r = QuickChatRoot.margin
    let card = NSRect(x: r, y: r, width: wf.width - 2 * r, height: wf.height - 2 * r).insetBy(dx: -0.5, dy: -0.5)
    var surfaces = 0, outside = 0, movers = 0
    var names: [String] = []
    func walk(_ v: NSView) {
        if v is QCDragView {
            surfaces += 1
            if !card.contains(v.convert(v.bounds, to: nil)) { outside += 1 }
        }
        // (the SwiftUI views inside the card may say yes; the panel isn't movable by its background, so it is never asked.
        // Anything that covers the rim must say no.)
        // (a view wholly outside the window, such as SwiftUI's key-view helper placed below it, is never hit)
        let r = v.convert(v.bounds, to: nil)
        if v.mouseDownCanMoveWindow && r.intersects(NSRect(origin: .zero, size: wf.size)) && !card.contains(r) { movers += 1; names.append("\(type(of: v)) \(r)") }
        v.subviews.forEach(walk)
    }
    walk(cv)
    check("\(label): drag surfaces exist (\(surfaces)) and all lie inside the card", surfaces > 0 && outside == 0, "\(outside) outside")
    check("\(label): no view says the window server may start a move from it", movers == 0, "\(names)")
    // every point of the rim: what is hit is a handle, which cannot move the window
    var bad = 0
    var x = 0.5
    while x < wf.width {
        for y in [0.5, 3.5, 7.5, wf.height - 0.5, wf.height - 3.5, wf.height - 7.5] {
            let v = cv.hitTest(NSPoint(x: x, y: y)); if !(v is QCResizeHandle) || v!.mouseDownCanMoveWindow { bad += 1 }
        }
        x += 6
    }
    var y = 0.5
    while y < wf.height {
        for x in [0.5, 3.5, 7.5, wf.width - 0.5, wf.width - 3.5, wf.width - 7.5] {
            let v = cv.hitTest(NSPoint(x: x, y: y)); if !(v is QCResizeHandle) || v!.mouseDownCanMoveWindow { bad += 1 }
        }
        y += 6
    }
    check("\(label): every rim point resolves to a resize handle that cannot move the window", bad == 0, "\(bad) points")
}
check("the panel is not movable by its background (the window server starts no move of its own)", !p.isMovableByWindowBackground)
noDragInTheRim("bar")
check("the content's least width is the card's 320 plus the rim twice", abs(p.contentMinSize.width - (QuickChatRoot.minWidth + 2 * rim)) < 0.5, "\(p.contentMinSize)")

// a drag of a handle, through the handle's own tracking loop: the events are queued, then the press is handed to the handle
func dragHandle(_ edges: QCEdges, from local: NSPoint, by d: NSPoint) -> (before: NSRect, after: NSRect) {
    let before = p.frame
    func ev(_ t: NSEvent.EventType, _ pt: NSPoint) -> NSEvent {
        let loc = p.convertPoint(fromScreen: NSPoint(x: before.minX + pt.x, y: before.minY + pt.y))
        return NSEvent.mouseEvent(with: t, location: loc, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                  windowNumber: p.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    // the pointer's place, as the handle asks for it: scripted in screen points, one per event (the real one is
    // NSEvent.mouseLocation; a queued event's locationInWindow is not a safe stand-in, it is taken against whatever the
    // window was when the event was made and the window moves under a bottom or left edge drag)
    var script = [NSPoint(x: before.minX + local.x, y: before.minY + local.y)]
    for i in 1...6 { script.append(NSPoint(x: before.minX + local.x + d.x * CGFloat(i) / 6, y: before.minY + local.y + d.y * CGFloat(i) / 6)) }
    QCResizeHandle.pointer = { _ in script.isEmpty ? NSPoint.zero : script.removeFirst() }
    for i in 1...6 { NSApp.postEvent(ev(.leftMouseDragged, NSPoint(x: local.x + d.x * CGFloat(i) / 6, y: local.y + d.y * CGFloat(i) / 6)), atStart: false) }
    NSApp.postEvent(ev(.leftMouseUp, NSPoint(x: local.x + d.x, y: local.y + d.y)), atStart: false)
    cv.handles.first { $0.edges == edges }!.mouseDown(with: ev(.leftMouseDown, local))
    return (before, p.frame)
}
let h0 = dragHandle(.right, from: NSPoint(x: W - 4, y: H / 2), by: NSPoint(x: 60, y: 0))
check("a right-edge drag widens by what the pointer moved, nothing else", abs(h0.after.width - (h0.before.width + 60)) < 0.5 && h0.after.height == h0.before.height && h0.after.minX == h0.before.minX && h0.after.maxY == h0.before.maxY, "\(h0)")
check("the drag ended: idle again", p.isIdle)
// a left-edge drag in steps that are queued before the window moves: it follows the pointer exactly (no overshoot)
let hl = dragHandle(.left, from: NSPoint(x: 4, y: p.frame.height / 2), by: NSPoint(x: 40, y: 0))
check("a left-edge drag by 40 narrows by exactly 40, the right edge staying", abs(hl.after.width - (hl.before.width - 40)) < 0.5 && abs(hl.after.maxX - hl.before.maxX) < 0.5, "\(hl)")
let hb = dragHandle(.bottom, from: NSPoint(x: p.frame.width / 2, y: 4), by: NSPoint(x: 0, y: -25))
check("a bottom-edge drag by 25 grows by exactly 25, the top staying", abs(hb.after.height - (hb.before.height + 25)) < 0.5 && abs(hb.after.maxY - hb.before.maxY) < 0.5, "\(hb)")
let hc = dragHandle([.left, .bottom], from: NSPoint(x: 4, y: 4), by: NSPoint(x: -30, y: 15))
check("a bottom-left corner drag follows both ways exactly", abs(hc.after.width - (hc.before.width + 30)) < 0.5 && abs(hc.after.height - (hc.before.height - 15)) < 0.5 && abs(hc.after.maxX - hc.before.maxX) < 0.5 && abs(hc.after.maxY - hc.before.maxY) < 0.5, "\(hc)")
let h1 = dragHandle(.left, from: NSPoint(x: 4, y: p.frame.height / 2), by: NSPoint(x: 5000, y: 0))
check("a left-edge drag stops at the least width, the right edge staying", abs(h1.after.width - p.contentMinSize.width) < 0.5 && abs(h1.after.maxX - h1.before.maxX) < 0.5, "\(h1)")
let h2 = dragHandle(.bottom, from: NSPoint(x: p.frame.width / 2, y: 4), by: NSPoint(x: 0, y: -40))
check("a bottom-edge drag makes the bar taller, the top staying", abs(h2.after.height - (h2.before.height + 40)) < 0.5 && abs(h2.after.maxY - h2.before.maxY) < 0.5 && h2.after.width == h2.before.width, "\(h2)")
let h3 = dragHandle(.top, from: NSPoint(x: p.frame.width / 2, y: p.frame.height - 4), by: NSPoint(x: 0, y: -5000))
check("a top-edge drag stops at the bar's content height, the bottom staying", abs(h3.after.minY - h3.before.minY) < 0.5 && h3.after.height < h3.before.height && h3.after.height >= bar.height - 0.5, "\(h3)")
let h4 = dragHandle([.right, .bottom], from: NSPoint(x: p.frame.width - 4, y: 4), by: NSPoint(x: 40, y: -30))
check("a corner drag moves two edges", abs(h4.after.width - (h4.before.width + 40)) < 0.5 && abs(h4.after.height - (h4.before.height + 30)) < 0.5 && abs(h4.after.maxY - h4.before.maxY) < 0.5, "\(h4)")
// back to the bar's own size (a drag of a left or top edge can't be queued in pieces: the events' places are taken against
// the window as it is when they are made), noted as the user's: no extra height is kept
p.beginResize()
p.setFrame(NSRect(x: p.frame.minX, y: p.frame.maxY - bar.height, width: bar.width, height: bar.height), display: true)
p.endResize()
spin(0.3)
check("the bar is back at its own size", abs(p.frame.width - bar.width) < 0.5 && abs(p.frame.height - bar.height) < 0.5, "\(p.frame.size) vs \(bar)")

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

// a resize: while it is under way fit() stays out; when it ends the user's size is kept
p.beginResize()
check("a resize is not idle", !p.isIdle)
chat.model.field = "a\nb\nc\nd"
spin(0.5)
let before = p.frame
chat.model.field = ""        // the lines go: only fit() would shrink the bar back, and it must not now
spin(0.5)
chat.fit()
check("fit() stays out during a resize", p.frame == before, "\(p.frame) vs \(before)")
// the user drags the bottom edge down by 50: the handle sets the frame, then ends the resize
var f = p.frame
f.size.height += 50; f.origin.y -= 50
p.setFrame(f, display: true)
p.endResize()
check("a resize ended: idle again", p.isIdle)
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
p.beginResize()
var g = p.frame
g.size.height = 360; g.size.width = 420; g.origin.y += chatSize.height - 360
p.setFrame(g, display: true)
p.endResize()
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
noDragInTheRim("chat")

// ── the least sizes are the system's, from the content's own frames ───────────────────────────────
check("the least width is 320 of card plus the margin", abs(p.contentMinSize.width - (QuickChatRoot.minWidth + 2 * QuickChatRoot.margin)) < 0.5, "\(p.contentMinSize)")
check("the chat's least height holds a line of chat and the field", p.contentMinSize.height >= QuickChatRoot.minWindowHeight + 2 * QuickChatRoot.margin - 0.5, "\(p.contentMinSize)")

print(failed == 0 ? "panel checks: \(passed)/\(passed) passed" : "panel checks: \(failed) failed, \(passed) passed")
exit(failed == 0 ? 0 : 1)
