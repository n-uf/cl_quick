// The quick chat panel's checks, without a mouse (this Mac can't post pointer events): the panel is a titled, resizable
// window with an invisible title bar, so its resize zones, cursors and live resize are the window server's; what can be
// proved here is everything AppKit decides in the app: the style mask and title bar, that the content fills the frame and
// the title bar's area belongs to it (AppKit's own hit test from the window's frame view), first-click acceptance, the
// least and most sizes, that nothing can start a move, and that QuickChat.fit stays out of a move or a live resize (the
// live resize is reached the way AppKit reaches it: its "will start" / "did end" notifications). The real panel is opened
// (read-only: nothing is written under the user's folders) and moved far from the screen's middle.
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
check("resizeIncrements are the plain default", p.resizeIncrements == NSSize(width: 1, height: 1), "\(p.resizeIncrements)")

// ── the window: titled and resizable (the window server's resize zones), with nothing of a title bar showing ─────────
guard let cv = p.contentView as? QuickChatHostingView else { print("FAIL the content view is not the hosting view"); exit(1) }
func windowShape(_ label: String) {
    let m = p.styleMask
    check("\(label): style mask is titled, resizable, full-size content, non-activating, and nothing else",
          m == QuickChatPanel.style && m.contains(.titled) && m.contains(.resizable) && m.contains(.fullSizeContentView)
          && m.contains(.nonactivatingPanel) && !m.contains(.closable) && !m.contains(.miniaturizable), "\(m.rawValue)")
    check("\(label): the title bar is transparent and its title hidden", p.titlebarAppearsTransparent && p.titleVisibility == .hidden)
    check("\(label): no window buttons show", [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
          .allSatisfy { p.standardWindowButton($0).map { $0.isHidden } ?? true })
    check("\(label): the content fills the whole frame (under the title bar too)", cv.frame.size == p.frame.size && cv.frame.origin == .zero,
          "\(cv.frame) in \(p.frame)")
    check("\(label): the card fills the frame (no transparent rim: the resize zones are on its visible edges)", QuickChatRoot.margin == 0)
    check("\(label): clear, non-opaque, with a shadow", !p.isOpaque && p.backgroundColor.alphaComponent == 0 && p.hasShadow)
    check("\(label): takes the mouse (not ignoresMouseEvents)", !p.ignoresMouseEvents)
    check("\(label): floating, on every Space and over full-screen apps", p.level == .floating
          && p.collectionBehavior.contains(.canJoinAllSpaces) && p.collectionBehavior.contains(.fullScreenAuxiliary))
    check("\(label): becomes key on a click without activating cl_quick", p.canBecomeKey && !p.becomesKeyOnlyIfNeeded && !p.canBecomeMain)
    check("\(label): the first click on a non-key panel goes through (acceptsFirstMouse)", cv.acceptsFirstMouse(for: nil))
    check("\(label): the SwiftUI content's safe area ignores the title bar", { if #available(macOS 13.3, *) { return cv.safeAreaRegions.isEmpty }; return true }())
    // AppKit's own hit test, from the window's frame view (the theme frame, where the title bar lives) as NSWindow.sendEvent
    // does it. The theme frame keeps the points of its resize region inside the window for itself (a thin band along
    // every edge, larger at the corners: a press there is a resize, handled by AppKit, never by the content); everything
    // else, the title bar's top 28 pt included, is the content's, so the header keeps its clicks and no title bar view
    // takes one. (The part of the resize zones outside the frame is the window server's and can't be hit-tested here.)
    guard let frameView = cv.superview else { check("\(label): a frame view", false); return }
    let W = p.frame.width, H = p.frame.height
    func hit(_ x: CGFloat, _ y: CGFloat) -> NSView? { frameView.hitTest(frameView.convert(NSPoint(x: x, y: y), from: nil)) }
    func isResizeZone(_ v: NSView?) -> Bool { v === frameView }
    func isContent(_ v: NSView?) -> Bool { v.map { $0.isDescendant(of: cv) } ?? false }
    check("\(label): the frame view is AppKit's titled frame (NSThemeFrame)", "\(type(of: frameView))".contains("Theme"), "\(type(of: frameView))")
    // the edges, 1 pt inside, at their middles and along them: AppKit's resize region
    var edgeMiss: [String] = []
    for t in stride(from: 0.25, through: 0.75, by: 0.125) as StrideThrough<CGFloat> {
        for (n, x, y) in [("left", 1, H * t), ("right", W - 1, H * t), ("bottom", W * t, 1), ("top", W * t, H - 1)] as [(String, CGFloat, CGFloat)]
        where !isResizeZone(hit(x, y)) { edgeMiss.append("\(n) \(x),\(y) → \(hit(x, y).map { "\(type(of: $0))" } ?? "nil")") }
    }
    check("\(label): every edge, 1 pt inside, is AppKit's resize region", edgeMiss.isEmpty, "\(edgeMiss)")
    let corners: [(String, CGFloat, CGFloat)] = [("bottom-left", 2, 2), ("bottom-right", W - 2, 2), ("top-left", 2, H - 2), ("top-right", W - 2, H - 2),
                                                 ("bottom-left along", 8, 2), ("top-right along", W - 2, H - 8)]
    let cornerMiss = corners.filter { !isResizeZone(hit($0.1, $0.2)) }.map(\.0)
    check("\(label): all four corners are AppKit's resize region", cornerMiss.isEmpty, "\(cornerMiss)")
    // inside the band (from 4 pt in, away from the corners' 20 pt): the content, the title bar's area included
    var stolen: [String] = []
    var x: CGFloat = 20
    while x < W - 20 {
        for d in [4, 6, 8, 14, 20, 27, 34] as [CGFloat] where d < H / 2 {
            for y in [H - d, d] where !isContent(hit(x, y)) { stolen.append("\(x),\(y) → \(hit(x, y).map { "\(type(of: $0))" } ?? "nil")") }
        }
        x += 7
    }
    var y: CGFloat = 20
    while y < H - 20 {
        for x in [4, 8, W - 8, W - 4] as [CGFloat] where !isContent(hit(x, y)) { stolen.append("\(x),\(y) → \(hit(x, y).map { "\(type(of: $0))" } ?? "nil")") }
        y += 7
    }
    check("\(label): from 4 pt in, everything is the content's, the title bar's top 28 pt included (no title bar view takes a click)",
          stolen.isEmpty, "\(stolen.count): \(stolen.prefix(8))")
    // the resize region is a band, not a strip of the card: the middle of every side, 4 pt in, is the content's
    check("\(label): the resize band is under 4 pt deep at the sides' middles",
          isContent(hit(4, H / 2)) && isContent(hit(W - 4, H / 2)) && isContent(hit(W / 2, 4)) && isContent(hit(W / 2, H - 4)))
    // the content's own cursor views work while the panel isn't key: their tracking areas are active always with cursor updates
    var cursorAreas = 0, badAreas = 0
    func walk(_ v: NSView) {
        if v is QCCursorView || v is QCDragView {
            for t in v.trackingAreas { cursorAreas += 1; if !t.options.contains(.activeAlways) { badAreas += 1 } }
        }
        v.subviews.forEach(walk)
    }
    walk(cv)
    check("\(label): the content's tracking areas are active always (\(cursorAreas))", badAreas == 0, "\(badAreas)")
}
windowShape("bar")
check("the panel is not movable by its background (the window server starts no move of its own)", !p.isMovableByWindowBackground)

// ── moving: only from the card's empty areas, never from the resize region or anything interactive ────────────────
// Where a press would start a move is found as NSWindow.sendEvent finds the view for it (QCDragView.hit: from the frame
// view, so its resize region comes first); a move itself is the window server's (performDrag), scripted here through
// QCDragView.drag as setFrameOrigin steps, which is all a move does to the window.
func press(_ d: QCDragView, at inWindow: NSPoint) {
    let e = NSEvent.mouseEvent(with: .leftMouseDown, location: inWindow, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: p.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    d.mouseDown(with: e)
}
/// The controls (QCControlMarkView: buttons, pickers, the profile's name, the address's hover zone) and the field (its
/// text view), with their frames in window points. (SwiftUI builds no accessibility tree without a client, so the
/// controls carry an inert marker of their frames instead.)
func interactive() -> [(String, NSRect)] {
    var out: [(String, NSRect)] = []
    func walk(_ v: NSView) {
        let r = v.convert(v.bounds, to: nil)
        if v is QCControlMarkView, r.width > 0, r.height > 0 { out.append(("control \(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))×\(Int(r.height))", r)) }
        if v is NSTextView, v.visibleRect.width > 0 { out.append(("field", v.convert(v.visibleRect, to: nil))) }
        v.subviews.forEach(walk)
    }
    walk(cv)
    return out
}
func movesFromEmptyOnly(_ label: String) {
    check("\(label): moving is on (QCDragView.movesWindow)", QCDragView.movesWindow)
    check("\(label): the panel is movable (performDrag needs it), never by its background", p.isMovable && !p.isMovableByWindowBackground)
    // the transparent title bar is no drag region of its own: the hosting view covers it and says no, and so does every
    // drag surface (they move the window themselves, from their own mouseDown)
    var movers: [String] = []
    func walk(_ v: NSView) {
        if v is QCDragView && v.mouseDownCanMoveWindow { movers.append("\(type(of: v))") }
        v.subviews.forEach(walk)
    }
    walk(cv)
    check("\(label): the hosting view covers the title bar and says no to a window-server move; no drag surface says yes",
          !cv.mouseDownCanMoveWindow && cv.frame.maxY >= p.frame.height && movers.isEmpty, "\(movers)")
    let W = p.frame.width, H = p.frame.height
    // the resize region first: a press 1 pt inside any edge or on a corner is the frame's (a resize), never a move
    var zoneMoves: [String] = []
    for t in stride(from: 0.1, through: 0.9, by: 0.1) as StrideThrough<CGFloat> {
        for pt in [NSPoint(x: 1, y: H * t), NSPoint(x: W - 1, y: H * t), NSPoint(x: W * t, y: 1), NSPoint(x: W * t, y: H - 1)] {
            if QCDragView.surface(at: pt, in: p) != nil || QCDragView.hit(at: pt, in: p) != nil { zoneMoves.append("\(pt)") }
        }
    }
    for pt in [NSPoint(x: 2, y: 2), NSPoint(x: W - 2, y: 2), NSPoint(x: 2, y: H - 2), NSPoint(x: W - 2, y: H - 2)]
    where QCDragView.surface(at: pt, in: p) != nil || QCDragView.hit(at: pt, in: p) != nil { zoneMoves.append("\(pt)") }
    check("\(label): every edge 1 pt in and every corner resizes (the frame's), none starts a move", zoneMoves.isEmpty, "\(zoneMoves)")
    // the card's empty areas move it: the bar's padding, or the chat's header row and empty chat
    var empty: [(String, NSPoint)] = [("top padding", NSPoint(x: W / 2, y: H - 6)), ("left padding", NSPoint(x: 6, y: H / 2))]
    if chat.model.isWindow {
        // the header's empty space under the hidden title bar: the gap between the address and the meters, at the title
        // bar's heights (4 to 28 pt from the top)
        for d in [4, 10, 16, 22, 28] as [CGFloat] { empty.append(("header gap \(Int(d)) pt from the top", NSPoint(x: W * 0.45, y: H - d))) }
        empty.append(("empty chat", NSPoint(x: W / 2, y: H / 2)))
    }
    let notSurfaces = empty.filter { QCDragView.surface(at: $0.1, in: p) == nil }
        .map { "\($0.0) \($0.1) → \(QCDragView.hit(at: $0.1, in: p).map { "\(type(of: $0))" } ?? "frame")" }
    check("\(label): the card's empty areas start a move (\(empty.count) points)", notSurfaces.isEmpty, "\(notSurfaces)")
    // nothing interactive does: every point of every control (its clear padding and the gaps between its glyphs included)
    // and of the field, on a 2 pt grid 1 pt inside their frames
    let items = interactive()
    var moving: [String] = [], probed = 0
    for (name, r) in items {
        let inner = r.insetBy(dx: 1, dy: 1).intersection(NSRect(x: 4, y: 4, width: W - 8, height: H - 8))
        guard !inner.isNull, inner.width > 0, inner.height > 0 else { continue }
        var bad = 0
        for x in stride(from: inner.minX, through: inner.maxX, by: 2) {
            for y in stride(from: inner.minY, through: inner.maxY, by: 2) {
                probed += 1
                if QCDragView.surface(at: NSPoint(x: x, y: y), in: p) != nil { bad += 1 }
            }
        }
        if bad > 0 { moving.append("\(name): \(bad) points") }
    }
    let controls = items.filter { $0.0 != "field" }.count, fields = items.count - controls
    // the bar: three pickers and Send; the chat adds the profile's name, the address, New chat, Hide and an answer's Copy
    check("\(label): the controls and the field are found (\(controls) controls, \(fields) field)",
          fields >= 1 && controls >= (chat.model.isWindow ? 8 : 4), "\(items.map(\.0))")
    check("\(label): no point of a control or the field starts a move (\(probed) points)", moving.isEmpty, "\(moving)")
    // a scripted move from an empty area: the origin follows, the size never changes, fit() stays out, idle after
    guard let from = empty.first, let d = QCDragView.surface(at: from.1, in: p) else { return }
    let start = p.frame
    var during = true, fitOut = true
    QCDragView.drag = { w, _ in
        during = during && !(w as! QuickChatPanel).isIdle
        for i in 1...40 {
            w.setFrameOrigin(NSPoint(x: start.minX + CGFloat(i) * 3, y: start.minY - CGFloat(i) * 2))
            if i == 20 { let f = w.frame; chat.fit(); fitOut = fitOut && w.frame == f }
        }
    }
    press(d, at: from.1)
    QCDragView.drag = { w, e in w.performDrag(with: e) }
    check("\(label): the panel is moving during a move (fit() stays out)", during && fitOut)
    check("\(label): a move from an empty area moves the window and keeps its size",
          p.frame.size == start.size && abs(p.frame.minX - (start.minX + 120)) < 0.5 && abs(p.frame.minY - (start.minY - 80)) < 0.5, "\(p.frame) from \(start)")
    check("\(label): idle after the move", p.isIdle)
    p.setFrameOrigin(start.origin)
}
movesFromEmptyOnly("bar")
// ── sizes: the least is the content's (320 wide; the bar its content's height, the chat 220), the most is open ────────
check("bar: the least width is 320", abs(p.contentMinSize.width - QuickChatRoot.minWidth) < 0.5, "\(p.contentMinSize)")
check("bar: the least height is the bar's content (it can't be squashed below its field and keys)",
      p.contentMinSize.height > 60 && p.contentMinSize.height <= bar.height + 0.5, "\(p.contentMinSize) bar \(bar)")
check("bar: it can grow both ways (the bar resizes as well as the chat)",
      p.contentMaxSize.width > bar.width + 100 && p.contentMaxSize.height > bar.height + 100, "\(p.contentMaxSize)")

// A live resize, reached the way AppKit reaches it: the window posts "will start", the frame changes, it posts "did end".
func liveResize(to f: NSRect, during: () -> Void = {}) {
    NotificationCenter.default.post(name: NSWindow.willStartLiveResizeNotification, object: p)
    check("a live resize is not idle", !p.isIdle)
    p.setFrame(f, display: true)
    during()
    NotificationCenter.default.post(name: NSWindow.didEndLiveResizeNotification, object: p)
    check("a live resize ended: idle again", p.isIdle)
}
let r0 = p.frame
liveResize(to: NSRect(x: r0.minX, y: r0.minY - 40, width: r0.width + 60, height: r0.height + 40)) {
    chat.fit()
    check("fit() stays out of a live resize of the bar", p.frame.size == NSSize(width: r0.width + 60, height: r0.height + 40), "\(p.frame.size)")
}
spin(0.3)
check("the bar keeps the size the user gave it (wider and taller), the top edge staying",
      abs(p.frame.width - (r0.width + 60)) < 0.5 && abs(p.frame.height - (r0.height + 40)) < 0.5 && abs(p.frame.maxY - r0.maxY) < 0.5, "\(p.frame)")
// back to the bar's own size, noted as the user's: no extra height is kept
liveResize(to: NSRect(x: p.frame.minX, y: p.frame.maxY - bar.height, width: bar.width, height: bar.height))
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
NotificationCenter.default.post(name: NSWindow.willStartLiveResizeNotification, object: p)
check("a resize is not idle", !p.isIdle)
chat.model.field = "a\nb\nc\nd"
spin(0.5)
let before = p.frame
chat.model.field = ""        // the lines go: only fit() would shrink the bar back, and it must not now
spin(0.5)
chat.fit()
check("fit() stays out during a resize", p.frame == before, "\(p.frame) vs \(before)")
// the user drags the bottom edge down by 50: macOS sets the frame, then ends the live resize
var f = p.frame
f.size.height += 50; f.origin.y -= 50
p.setFrame(f, display: true)
NotificationCenter.default.post(name: NSWindow.didEndLiveResizeNotification, object: p)
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
var g = p.frame
g.size.height = 360; g.size.width = 420; g.origin.y += chatSize.height - 360
liveResize(to: g)
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
windowShape("chat")
movesFromEmptyOnly("chat")

// ── the least sizes are the system's, from the content's own frames: about 320 × 220 for the chat ─────────────────
check("chat: the least width is 320", abs(p.contentMinSize.width - QuickChatRoot.minWidth) < 0.5, "\(p.contentMinSize)")
check("chat: the least height is about 220 (holds the header, a line of chat and the field)",
      p.contentMinSize.height >= QuickChatRoot.minWindowHeight - 0.5 && p.contentMinSize.height <= QuickChatRoot.minWindowHeight + 60, "\(p.contentMinSize)")
check("chat: it can grow both ways", p.contentMaxSize.width > p.frame.width + 100 && p.contentMaxSize.height > p.frame.height + 100, "\(p.contentMaxSize)")

// ── the cursor: the open hand only where a press moves the window, never fighting the pointing hand, never left behind ─
do {
    let W = p.frame.width, H = p.frame.height
    let gap = NSPoint(x: W * 0.45, y: H - 16)          // the header's empty gap
    check("cursor: the open hand over an empty area", QCDragView.cursor(at: gap, in: p) === NSCursor.openHand)
    check("cursor: nothing set by the drag surfaces in the resize region (the system's resize cursor)",
          QCDragView.cursor(at: NSPoint(x: 1, y: H / 2), in: p) == nil && QCDragView.cursor(at: NSPoint(x: 2, y: 2), in: p) == nil)
    // a control the hosting view takes (any marker's middle): the arrow, or nothing while a pointing-hand control is hovered
    var mark: NSPoint?
    func find(_ v: NSView) { if mark == nil, v is QCControlMarkView { let r = v.convert(v.bounds, to: nil); mark = NSPoint(x: r.midX, y: r.midY) }; v.subviews.forEach(find) }
    find(cv)
    if let m = mark {
        let plain = QCDragView.cursor(at: m, in: p)
        QCCursorView.hovered = true
        let onHand = QCDragView.cursor(at: m, in: p)
        QCCursorView.hovered = false
        check("cursor: over a control the arrow, never the open hand", plain === NSCursor.arrow,
              "\(String(describing: plain)) at \(m) hit \(QCDragView.hit(at: m, in: p).map { "\(type(of: $0))" } ?? "nil")")
        check("cursor: over the profile's name (pointing hand hovered) the drag surfaces set nothing", onHand == nil)
    } else { check("cursor: a control is found", false) }
    // hidden with the open hand up (Esc, ⌘W, the shortcut): it goes, at once
    NSCursor.openHand.set()
    let wasHand = NSCursor.current === NSCursor.openHand
    chat.hide()
    check("cursor: hiding the panel drops the open hand", wasHand && NSCursor.current !== NSCursor.openHand, "set: \(wasHand)")
    check("cursor: nothing is set over a hidden panel", QCDragView.cursor(at: gap, in: p) == nil)
    chat.open(); spin(0.4)
    // the pointer leaving a drag surface for somewhere no press moves the window (here: the panel is far off screen, so the
    // real pointer is outside it): the hand goes
    p.setFrameOrigin(NSPoint(x: -30000, y: 300))
    var surface: QCDragView?
    func findSurface(_ v: NSView) { if surface == nil, let d = v as? QCDragView { surface = d }; v.subviews.forEach(findSurface) }
    findSurface(cv)
    NSCursor.openHand.set()
    let ev = NSEvent.enterExitEvent(with: .mouseExited, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: p.windowNumber,
                                    context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
    surface?.mouseExited(with: ev)
    check("cursor: leaving a drag surface for outside the panel drops the open hand", surface != nil && NSCursor.current !== NSCursor.openHand)
}

// ── after a move, a content change fit() skipped is retried ───────────────────────────────────────────────────────────
do {
    var retried = 0
    let keep = cv.onIntrinsicChange
    cv.onIntrinsicChange = { retried += 1; keep() }
    var surface: QCDragView?
    let gap = NSPoint(x: p.frame.width * 0.45, y: p.frame.height - 16)
    surface = QCDragView.surface(at: gap, in: p)
    QCDragView.drag = { w, _ in w.setFrameOrigin(NSPoint(x: w.frame.minX + 10, y: w.frame.minY)) }
    if let d = surface { press(d, at: gap) }
    QCDragView.drag = { w, e in w.performDrag(with: e) }
    cv.onIntrinsicChange = keep
    check("a move's end retries fit() (the host's onIntrinsicChange)", surface != nil && retried == 1, "\(retried)")
}

print(failed == 0 ? "panel checks: \(passed)/\(passed) passed" : "panel checks: \(failed) failed, \(passed) passed")
exit(failed == 0 ? 0 : 1)
