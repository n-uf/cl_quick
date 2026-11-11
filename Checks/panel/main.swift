// The quick chat panel's checks, without a mouse (this Mac can't post pointer events): the panel is a titled, resizable
// window with an invisible title bar, so its resize zones, cursors and live resize are the window server's; what can be
// proved here is everything AppKit decides in the app: the style mask and title bar, that the content fills the frame and
// the title bar's area belongs to it (AppKit's own hit test from the window's frame view), first-click acceptance, the
// least and most sizes, that nothing can start a move, and that QuickChat.fit stays out of a move or a live resize (the
// live resize is reached the way AppKit reaches it: its "will start" / "did end" notifications). The real panel is opened
// (read-only: nothing is written under the user's folders) and moved far from the screen's middle.
//   Checks/panel.sh

import AppKit
import Carbon.HIToolbox

Files.readOnly = true
let app = NSApplication.shared
CheckQuiet.start()          // nothing on any screen, never the keyboard, never active (Checks/quiet.swift)
let chat = QuickChat.shared
chat.start()
// no real `claude`: opening the panel would start one on the user's own profile (QuickChatModel.warm) and ask its usage
chat.model.resolveClaude = { $0(nil) }

var failed = 0, passed = 0
func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    if ok { passed += 1 } else { failed += 1; print("FAIL \(name) \(detail())") }
}
func spin(_ s: TimeInterval = 0.4) { RunLoop.current.run(until: Date().addingTimeInterval(s)); CheckQuiet.verify("after a spin") }
func panel() -> QuickChatPanel? { NSApp.windows.compactMap { $0 as? QuickChatPanel }.first }
func note(_ name: String) -> Notification { Notification(name: Notification.Name(name)) }
/// The middle of the header's empty gap, between the meters and the buttons as drawn; without meters (no numbers yet),
/// between the window's 10 pt line and the buttons. Nil (and a failed check) when the header isn't drawn or has no gap.
func headerGapX(_ W: CGFloat) -> CGFloat? {
    let mk = QCStepTargets.shared.marks
    guard let b = mk["header-buttons"] else { check("header: its buttons are drawn, to find its gap", false); return nil }
    let left = chat.model.level != nil ? mk["header-meters"]?.maxX : QCSpace.gap
    guard let l = left, b.minX - l > 16 else { check("header: an empty gap between its meters and buttons", false, "\(String(describing: left)) \(b)"); return nil }
    return (l + b.minX) / 2
}
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
    // the window is clear around the card's rounded corners, so the card itself must be opaque: nothing of the windows
    // behind may show through it (a 97% fill let a page's text through, around the usage indicator)
    check("\(label): the card's fills are opaque", NSColor(QCBar.fill).alphaComponent == 1 && NSColor(QCWindow.fill).alphaComponent == 1)
    if let rep = cv.bitmapImageRepForCachingDisplay(in: cv.bounds) {
        cv.cacheDisplay(in: cv.bounds, to: rep)
        let at: [(Double, Double)] = [(0.5, 0.5), (0.06, 0.5), (0.94, 0.5), (0.5, 0.2), (0.5, 0.8), (0.8, 0.75)]
        let alphas = at.map { rep.colorAt(x: Int(Double(rep.pixelsWide) * $0.0), y: Int(Double(rep.pixelsHigh) * $0.1))?.alphaComponent ?? 0 }
        check("\(label): drawn, the card is opaque inside (alpha 1)", alphas.allSatisfy { $0 >= 0.999 }, "\(alphas)")
    } else { check("\(label): the card can be drawn to check it", false) }
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
// (Off every screen, where the checks keep the panel, AppKit gives no top or bottom resize region to a window at its least
// height, as it can't tell how far it could grow; on a screen it does. So the bar's shape and edges are checked 20 pt above
// its least height, and the bar is put back before its sizes are.)
let barLeast = p.frame
func userSizes(_ f: NSRect) {         // as the user's live resize (so fit() keeps it)
    NotificationCenter.default.post(name: NSWindow.willStartLiveResizeNotification, object: p)
    p.setFrame(f, display: true)
    NotificationCenter.default.post(name: NSWindow.didEndLiveResizeNotification, object: p)
}
userSizes(NSRect(x: barLeast.minX, y: barLeast.minY - 20, width: barLeast.width, height: barLeast.height + 20))
spin(0.3)
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
        // the header's empty space under the hidden title bar: the gap between the meters and the buttons, at the title
        // bar's heights (4 to 28 pt from the top)
        let gx = headerGapX(W) ?? 0          // (none found: a failed check already, and x 0 is no surface)
        for d in [4, 10, 16, 22, 28] as [CGFloat] { empty.append(("header gap \(Int(d)) pt from the top", NSPoint(x: gx, y: H - d))) }
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
userSizes(NSRect(x: p.frame.minX, y: p.frame.maxY - bar.height, width: bar.width, height: bar.height))
spin(0.3)
check("the bar is back at its least height after the edge checks", p.frame.size == bar, "\(p.frame.size) vs \(bar)")
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

// ── the field box: all of it is the field, at any height ─────────────────────────────────────────────────────────────
// The box above the picker row is the field's scroll view plus its press area (QCFieldArea: the gap to the row, and in
// the chat the box's padding). Every point of it, on a grid, is the text view or the area that presses into it, is never a
// drag surface, and has the I-beam (or nothing set by the drag surfaces); the text's first line is inside what the field
// shows, so the caret and the placeholder can be seen; a press in the area focuses the field.
func fieldBox(_ label: String) {
    var tv: QCTextView?, areas: [QCFieldAreaView] = []
    func walk(_ v: NSView) { if let t = v as? QCTextView { tv = t }; if let a = v as? QCFieldAreaView { areas.append(a) }; v.subviews.forEach(walk) }
    walk(cv)
    guard let tv, let scroll = tv.enclosingScrollView, let area = areas.first else { check("\(label): the field and its area are found", false); return }
    let fieldRect = scroll.convert(scroll.bounds, to: nil)
    let box = fieldRect.union(area.convert(area.bounds, to: nil))
    check("\(label): the scroll view has no automatic insets (the title bar's would push the text out of the field)",
          !scroll.automaticallyAdjustsContentInsets && scroll.contentInsets.top == 0 && scroll.contentInsets.bottom == 0)
    check("\(label): the text view fills the field (at least as tall as what it shows)",
          tv.frame.height >= scroll.contentSize.height - 0.5 && abs(tv.frame.width - scroll.contentSize.width) < 0.5, "\(tv.frame) in \(scroll.contentSize)")
    let line = (tv.font ?? .systemFont(ofSize: 15)).boundingRectForFont.height
    let first = NSRect(x: tv.textContainerOrigin.x, y: tv.textContainerOrigin.y, width: 10, height: line - 1)
    check("\(label): the first line (caret, placeholder) is inside what the field shows", tv.visibleRect.contains(first), "\(tv.visibleRect) vs \(first)")
    var wrong: [String] = [], moves = 0, hands = 0, n = 0
    for x in stride(from: box.minX + 0.5, to: box.maxX, by: 3) {
        for y in stride(from: box.minY + 0.5, to: box.maxY, by: 3) {
            let pt = NSPoint(x: x, y: y)
            n += 1
            let hit = QCDragView.hit(at: pt, in: p)
            let ok = hit === tv || ((hit as? QCFieldAreaView)?.field === tv)
            if !ok, wrong.count < 6 { wrong.append("\(pt) → \(hit.map { "\(type(of: $0))" } ?? "frame")") }
            if QCDragView.surface(at: pt, in: p) != nil { moves += 1 }
            if let c = QCDragView.cursor(at: pt, in: p), c !== NSCursor.iBeam { hands += 1 }
        }
    }
    check("\(label): every point of the field box (\(n), \(Int(box.width))×\(Int(box.height))) is the text view or presses into it",
          wrong.isEmpty, "\(wrong)")
    check("\(label): no point of the field box starts a move", moves == 0, "\(moves)")
    check("\(label): the cursor in the field box is the I-beam (or nothing set), never a hand", hands == 0, "\(hands)")
    // a press in the area around the field (its bottom gap) focuses the field
    p.makeFirstResponder(nil)
    let a = area.convert(area.bounds, to: nil)
    let at = NSPoint(x: a.midX, y: a.minY + 2)
    if QCDragView.hit(at: at, in: p) === area {
        func ev(_ t: NSEvent.EventType) -> NSEvent {
            NSEvent.mouseEvent(with: t, location: at, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: p.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        NSApp.postEvent(ev(.leftMouseUp), atStart: false)
        area.mouseDown(with: ev(.leftMouseDown))
        check("\(label): a press beside the text focuses the field", p.firstResponder === tv, "\(String(describing: p.firstResponder))")
    } else { check("\(label): the field's area is hit below the text", false, "\(String(describing: QCDragView.hit(at: at, in: p)))") }
}
fieldBox("bar")
let barFrame = p.frame
liveResize(to: NSRect(x: barFrame.minX, y: barFrame.maxY - barFrame.height * 3, width: barFrame.width, height: barFrame.height * 3))
spin(0.4)
check("tall bar: three times the bar's height", abs(p.frame.height - barFrame.height * 3) < 0.5, "\(p.frame)")
fieldBox("tall bar")
liveResize(to: barFrame)
spin(0.4)
check("the bar is back at its own size after the tall bar", abs(p.frame.height - bar.height) < 0.5, "\(p.frame.size)")

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
// Dictation's provisional text is marked text (setMarkedText, replaced again and again, then committed): the field grows
// and shrinks with it as it does with typed text, though the text view may not post a change for it
do {
    var dtv: QCTextView?
    func findDictTV(_ v: NSView) { if let t = v as? QCTextView { dtv = t }; v.subviews.forEach(findDictTV) }
    if let c = p.contentView { findDictTV(c) }
    if let tv = dtv {
        let none = NSRange(location: NSNotFound, length: 0)
        tv.setMarkedText("one\ntwo\nthree\nfour", selectedRange: NSRange(location: 17, length: 0), replacementRange: none)
        spin(0.5)
        check("dictation: marked text of four lines grows the bar", p.frame.height > bar.height + 20, "\(p.frame.height) vs \(bar.height)")
        let four = p.frame.height
        tv.setMarkedText("one\ntwo", selectedRange: NSRange(location: 7, length: 0), replacementRange: none)
        spin(0.5)
        check("dictation: shorter marked text shrinks it (two lines between)", p.frame.height < four - 5 && p.frame.height > bar.height + 5, "\(p.frame.height) vs \(four)")
        tv.setMarkedText("one\ntwo\nthree\nfour", selectedRange: NSRange(location: 17, length: 0), replacementRange: none)
        spin(0.3)
        tv.unmarkText()
        spin(0.5)
        check("dictation: committing it keeps the height, and the model has the text", abs(p.frame.height - four) < 0.5 && chat.model.field == "one\ntwo\nthree\nfour", "\(p.frame.height) \(chat.model.field.debugDescription)")
        chat.model.field = ""
        spin(0.5)
        check("dictation: the bar returns to its height when the text goes", abs(p.frame.height - bar.height) < 0.5, "\(p.frame.height) vs \(bar.height)")
    } else { check("dictation: the field is found", false) }
}

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
fieldBox("chat")

// ── the least sizes are the system's, from the content's own frames: about 320 × 220 for the chat ─────────────────
check("chat: the least width is 320", abs(p.contentMinSize.width - QuickChatRoot.minWidth) < 0.5, "\(p.contentMinSize)")
check("chat: the least height is about 220 (holds the header, a line of chat and the field)",
      p.contentMinSize.height >= QuickChatRoot.minWindowHeight - 0.5 && p.contentMinSize.height <= QuickChatRoot.minWindowHeight + 60, "\(p.contentMinSize)")
check("chat: the least height has room for the header's \(Int(QCSpace.header)) pt", QuickChatRoot.minWindowHeight - QCSpace.header >= 180)
check("chat: it can grow both ways", p.contentMaxSize.width > p.frame.width + 100 && p.contentMaxSize.height > p.frame.height + 100, "\(p.contentMaxSize)")

// ── the cursor: the open hand only where a press moves the window, never fighting the pointing hand, never left behind ─
do {
    let W = p.frame.width, H = p.frame.height
    let gap = NSPoint(x: headerGapX(W) ?? 0, y: H - 16)     // the header's empty gap
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

// ── the address: only in the profile menu, blurred until the pointer is on it; a copy glyph copies it (to a pasteboard
// of the check's own: the user's clipboard is never touched) ──────────────────────────────────────────────────────────
do {
    let pb = NSPasteboard(name: NSPasteboard.Name("local.n-uf.cl-quick.checks"))
    pb.clearContents(); pb.setString("before", forType: .string)
    let wrote = QCProfileMenuRow.copy("ultra-1@example.com", to: pb)
    check("address: a copy puts the whole address on the pasteboard, as plain text, and nothing else",
          wrote && pb.string(forType: .string) == "ultra-1@example.com" && (pb.types ?? []).allSatisfy { $0 == .string || $0.rawValue == "NSStringPboardType" },
          "\(String(describing: pb.string(forType: .string))) \(String(describing: pb.types))")
    pb.clearContents(); pb.setString("before", forType: .string)
    check("address: no address known, nothing copied and the pasteboard left alone",
          !QCProfileMenuRow.copy("", to: pb) && !QCProfileMenuRow.copy("  ", to: pb) && pb.string(forType: .string) == "before")

    // the header has no address any more: no hover zone of its own, and VoiceOver's words for it have none either
    var t = chat.model.target ?? QuickChatTarget(Profile(id: "main", name: "Main", folder: "~/.claude-sample"))
    t.email = "ultra-1@example.com"; chat.model.target = t
    chat.model.turns = [oneTurn()]
    p.setFrame(NSRect(x: p.frame.minX, y: p.frame.minY, width: 720, height: p.frame.height), display: true); spin(0.6)
    var hands = 0
    let headerBand = NSRect(x: 0, y: p.frame.height - QCSpace.header, width: p.frame.width, height: QCSpace.header)
    func walk(_ v: NSView) { if v is QCCursorView, headerBand.intersects(v.convert(v.bounds, to: nil)) { hands += 1 }; v.subviews.forEach(walk) }
    walk(cv)
    // (the header is drawn: its buttons' capsule is in that band)
    let capsule = QCStepTargets.shared.marks["header-buttons"]
    check("header: drawn, its buttons in the top band", capsule.map { $0.minY >= 0 && $0.maxY <= QCSpace.header } == true, "\(String(describing: capsule))")
    check("header: no profile name or address zone in it (\(hands) pointing-hand zones)", hands == 0)
    // corner A: New chat and Hide in one capsule, 9 pt in from the top and the right, a row high, two 28 pt buttons 2 pt apart
    if let c = capsule {
        check("header: the buttons' capsule is 9 pt in from the top and the right", abs(c.minY - QCSpace.cornerInset) < 0.5
              && abs(p.frame.width - c.maxX - QCSpace.cornerInset) < 0.5, "\(c) in \(p.frame.width)")
        check("header: the capsule holds two 28 pt buttons 2 pt apart", abs(c.height - QCSpace.row) < 0.5 && abs(c.width - (2 * QCSpace.row + 2)) < 0.5, "\(c)")
        check("header: the capsule's corners are concentric with the window's", QCCornerButton.radius == QCSpace.corner - QCSpace.cornerInset)
        if let m = QCStepTargets.shared.marks["header-meters"] {
            check("header: the meters are level with the capsule", abs(m.midY - c.midY) < 1, "\(m) vs \(c)")
        }
        // a press anywhere on the capsule, the gap between the buttons included, is never a move
        let H = p.frame.height
        let pts = stride(from: c.minX + 1, through: c.maxX - 1, by: 2).flatMap { x in [NSPoint(x: x, y: H - c.midY), NSPoint(x: x, y: H - c.minY - 1)] }
        let moving = pts.filter { QCDragView.surface(at: $0, in: p) != nil }
        check("header: no press on the capsule moves the window (\(pts.count) points)", moving.isEmpty, "\(moving.prefix(4))")
    }
    var wk = QuickChatLevel(); wk.week = 40
    let words = QCHeaderLine.spoken(level: wk)
    check("header: its words are the meters' alone, no profile name or address",
          !words.isEmpty && !words.contains("@") && !words.contains(maskEmail("ultra-1@example.com")) && !words.contains(t.name), words)

    // the profile menu: each profile a row of its own with its account in use's address (none when none is known), then
    // Settings for the chat's profile and Add a profile…
    var picked: [String] = [], settingsOpened = 0
    let menu = QCMenu.profiles([(Profile(id: "main", name: "Main", folder: "~/.claude-sample"), nil),
                                (Profile(id: "work", name: "Work", folder: "~/.claude-work"), nil)], on: "main",
                               address: { $0.id == "main" ? "ultra-1@example.com" : nil }, settings: (name: "Main", open: { settingsOpened += 1 }),
                               pick: { picked.append($0) }, add: {})
    let titles = menu.items.map(\.title)
    check("menu: Settings for Main… after the line, just above Add a profile…",
          titles.firstIndex(of: "Settings for Main…").map { titles.indices.contains($0 + 1) && titles[$0 + 1] == "Add a profile…"
              && menu.items[$0 - 1].isSeparatorItem } == true, "\(titles)")
    if let s = menu.items.first(where: { $0.title == "Settings for Main…" }), let a = s.action {
        NSApp.sendAction(a, to: s.target, from: s)
        check("menu: Settings for Main… opens Settings", settingsOpened == 1)
    } else { check("menu: Settings for Main… has an action", false) }
    // the chat's own item: Settings on the chat's profile, and the chat steps aside (hidden; Settings itself not opened
    // here, the check's openSettings stands in)
    var openedFor: [String?] = []
    let wasOpen = chat.model.openSettings, wasHide = chat.model.hide
    var hid = 0
    chat.model.openSettings = { openedFor.append($0) }
    chat.model.hide = { hid += 1 }
    let item = QCControls.settingsItem(chat.model)
    item?.open()
    chat.model.openSettings = wasOpen; chat.model.hide = wasHide
    check("menu: the chat's item is Settings for its profile, opens Settings on it and hides the chat",
          item?.name == t.name && openedFor == [t.profileID] && hid == 1, "\(String(describing: item?.name)) \(openedFor) \(hid)")
    let rows = menu.items.compactMap { $0.view as? QCProfileMenuRow }
    check("menu: a row view for each profile, the in-use address on Main's, none on Work's",
          rows.count == 2 && rows[0].address == "ultra-1@example.com" && rows[1].address == nil && rows[0].on && !rows[1].on)
    check("menu: the rows are as wide, and the items keep their title and state", rows.count == 2 && rows[0].frame.width == rows[1].frame.width
          && menu.items.contains { $0.view === rows.first && $0.title == "Main" && $0.state == .on && $0.action != nil })
    if let r = rows.first {
        r.pasteboard = pb
        check("menu: at rest the address is blurred", !r.revealed)
        r.hover(at: NSPoint(x: 50, y: 12))
        check("menu: the pointer on the name leaves it blurred, and shows the copy glyph", !r.revealed && r.rowHover)
        r.hover(at: NSPoint(x: r.addressRect.midX, y: r.addressRect.midY))
        check("menu: the pointer on the address makes it readable", r.revealed)
        r.hover(at: nil)
        check("menu: the pointer gone, blurred again", !r.revealed && !r.rowHover)
        pb.clearContents(); pb.setString("before", forType: .string)
        r.press(at: NSPoint(x: r.copyRect.midX, y: r.copyRect.midY))
        check("menu: a click on the copy glyph copies the address, says Copied and picks nothing",
              pb.string(forType: .string) == "ultra-1@example.com" && r.copiedUntil != nil && picked.isEmpty)
        r.press(at: NSPoint(x: 50, y: 12)); spin(0.1)
        check("menu: a click elsewhere on the row picks the profile (after the menu closes)", picked == ["main"], "\(picked)")
    }
    // Return on a highlighted row: the menu sends the item's own action
    if let item = menu.items.first(where: { $0.view === rows.first }), let a = item.action {
        NSApp.sendAction(a, to: item.target, from: item)
        check("menu: the row's item action (Return) picks the profile", picked == ["main", "main"], "\(picked)")
    } else { check("menu: the row's item has an action", false) }
    pb.releaseGlobally()
}

// ── the mic button: macOS Dictation into OUR field, cl_quick never activated (stand-ins for Dictation: no real one
// starts here) ─────────────────────────────────────────────────────────────────────────────────────────────────────────
do {
    if !p.isVisible { chat.open(); spin() }
    let keep = (send: QCDictation.send, handles: QCDictation.handles, isOff: QCDictation.isOff)
    var sent: [(Selector, AnyObject?)] = []
    var off = false
    // the real routing first, without performing anything: the field doesn't take startDictation:, the app does (so a
    // send to the field goes up the key window's chain to NSApplication); the field's text input context takes every
    // stop step (sent to it alone)
    p.focusField()
    if let f = p.firstResponder as? QCTextView {
        check("mic: the field passes startDictation: up the chain, the app takes it",
              !f.responds(to: QCDictation.start) && NSApp.responds(to: QCDictation.start) && keep.handles(QCDictation.start, f))
        let ctx = f.inputContext
        let missing = QCDictation.stopSteps.filter { ctx?.responds(to: $0) != true }.map { "\($0)" }
        check("mic: the field's text input context takes every stop step (\(QCDictation.stopSteps.count))", ctx != nil && missing.isEmpty, "\(missing)")
    } else { check("mic: the field has the keyboard", false) }
    QCDictation.send = { sel, target in sent.append((sel, target)); return true }
    QCDictation.handles = { _, _ in true }
    QCDictation.isOff = { off }
    /// The sends since `from`, as selectors; whether they are exactly the stop steps, each to the field's input context.
    func stopped(since from: Int, field: QCTextView?) -> Bool {
        let tail = sent.dropFirst(from)
        return tail.map(\.0) == QCDictation.stopSteps && tail.allSatisfy { $0.1 != nil && $0.1 === field?.inputContext }
    }
    func steps(since from: Int) -> String { "\(sent.dropFirst(from).map { "\($0.0)" })" }
    let neverToggled = { sent.allSatisfy { $0.0 != QCDictation.stop } && sent.filter { $0.0 == QCDictation.start }.allSatisfy { $0.1 is QCTextView } }
    defer { QCDictation.send = keep.send; QCDictation.handles = keep.handles; QCDictation.isOff = keep.isOff }
    let m = chat.model

    // a control: no press on it moves the window
    if let mic = QCStepTargets.shared.marks["mic"] {
        let H = p.frame.height
        let pts = stride(from: mic.minX + 1, through: mic.maxX - 1, by: 3).flatMap { x in [NSPoint(x: x, y: H - mic.midY), NSPoint(x: x, y: H - mic.minY - 1)] }
        check("mic: no press on it moves the window (\(pts.count) points)", pts.allSatisfy { QCDragView.surface(at: $0, in: p) == nil })
        if let s = QCStepTargets.shared.marks["send"] { check("mic: just left of Send, as tall", mic.maxX <= s.minX && s.minX - mic.maxX <= 8 && abs(mic.height - s.height) < 0.5, "\(mic) \(s)") }
    } else { check("mic: drawn", false) }

    // a click: the panel takes the keyboard without activating cl_quick, the field is first responder, Dictation is
    // started for that field
    p.makeFirstResponder(nil)
    m.dictate(true)
    check("mic: Dictation starts on the next turn, once the panel has the keyboard (nothing at once)", sent.isEmpty)
    spin(0.1)
    let field = p.firstResponder as? QCTextView
    check("mic: a click makes the panel key and the field its first responder", p.isKeyWindow && field != nil)
    check("mic: and starts Dictation for that field", sent.count == 1 && sent[0].0 == QCDictation.start && sent[0].1 === field && m.dictating,
          "\(sent.map { "\($0.0)" })")
    // a click again: Dictation's marked text is committed (the words stay), then the field's input context ends it
    // (discard, its own stop, deactivate, activate); never the app's stopDictation: (a toggle) or the start action
    if let tv = field {
        tv.setMarkedText("said so far", selectedRange: NSRange(location: 11, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    }
    var n = sent.count
    m.dictate(false)
    check("mic: a second click commits Dictation's marked text, the words stay in the field",
          field?.hasMarkedText() == false && m.field.hasSuffix("said so far"), "\(m.field.debugDescription)")
    check("mic: and ends Dictation in the field's input context, step by step", stopped(since: n, field: field) && !m.dictating, steps(since: n))
    check("mic: the field still has the keyboard after, the panel still key", p.isKeyWindow && p.firstResponder === field && field != nil)
    // a state gone stale (Dictation ended by Esc or the Dictation key): the same steps, each harmless when it has ended;
    // nothing that could start it again
    n = sent.count
    m.dictating = true; m.dictate(false)
    check("mic: a stale state ends with the same steps, never a start or the app's toggle", stopped(since: n, field: field) && neverToggled() && !m.dictating,
          steps(since: n))
    // the panel not key (the keyboard elsewhere): the context ends the session but doesn't take the keyboard back
    n = sent.count
    p.quietKey = false
    m.dictating = true; m.dictate(false)
    check("mic: not key, the context doesn't take the keyboard back (no activate)",
          sent.dropFirst(n).map(\.0) == QCDictation.stopSteps.filter { $0 != QCDictation.activate }, steps(since: n))
    p.makeKey(); spin(0.1)
    // Dictation started with macOS's own shortcut (the button's state off): marked text in the field ends it the same way
    if let tv = p.firstResponder as? QCTextView {
        tv.setMarkedText("shortcut words", selectedRange: NSRange(location: 14, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        n = sent.count
        m.dictate(false)
        check("mic: marked text alone (an input method's composition) is left alone: nothing ended", sent.count == n && tv.hasMarkedText(), steps(since: n))
        chat.dictationWatch.entered(Notification(name: QCDictationWatch.enterName))
        m.dictate(false)
        check("mic: marked text with the button off and an enter notice (macOS's shortcut): committed and ended",
              !tv.hasMarkedText() && m.field.hasSuffix("shortcut words") && stopped(since: n, field: tv), steps(since: n))
    } else { check("mic: the field has the keyboard (shortcut)", false) }
    // the button off and no marked text: nothing to end, nothing sent
    n = sent.count
    m.dictate(false)
    check("mic: off with nothing running sends nothing", sent.count == n)
    m.field = ""
    // the panel giving up the keyboard: Dictation has ended with it
    m.dictate(true); spin(0.1)
    p.onKeyLost()
    check("mic: the panel losing the keyboard ends the dictating state", !m.dictating)
    // Dictation ended by macOS (its floating mic clicked, Esc, the Dictation key, a timeout): DictationIM's exit notice
    // turns the button off, and only that (nothing sent: a wrong notice must not stop a Dictation still running)
    do {
        let exit = Notification(name: QCDictationWatch.exitName)
        let wasGrace = QuickChat.exitGrace
        check("mic: the watch listens for DictationIM's exit notice (not in the checks: they post it themselves)",
              QCDictationWatch.exitName.rawValue == "DictationIMNotificationDidExitDictationMode")
        m.dictate(true); spin(0.1)
        n = sent.count
        chat.dictationWatch.exited(exit)
        check("mic: an exit notice right after the button started it is an earlier Dictation's: the state stays on",
              m.dictating && sent.count == n)
        QuickChat.exitGrace = 0
        chat.dictationWatch.exited(exit)
        check("mic: Dictation ended by macOS turns the button off, sends nothing", !m.dictating && sent.count == n, steps(since: n))
        chat.dictationWatch.exited(exit)
        check("mic: an exit notice with the button off changes nothing", !m.dictating && sent.count == n)
        var hops = 0
        m.dictating = true
        DispatchQueue.global().async { chat.dictationWatch.exited(exit) }
        while m.dictating && hops < 50 { spin(0.02); hops += 1 }
        check("mic: an exit notice off the main thread reaches the button on it", !m.dictating, "\(hops)")
        QuickChat.exitGrace = wasGrace
    }
    // a new chat or hiding stops it too
    m.dictate(true); spin(0.1); n = sent.count
    let chatField = p.firstResponder as? QCTextView
    m.newChat(keepField: true)
    check("mic: a new chat stops Dictation", stopped(since: n, field: chatField) && !m.dictating, steps(since: n))
    m.dictate(true); spin(0.1); n = sent.count
    let hidField = p.firstResponder as? QCTextView
    chat.hide(); spin(0.1)
    check("mic: hiding stops Dictation (before the panel goes)", stopped(since: n, field: hidField) && !m.dictating && !p.isVisible, steps(since: n))
    chat.open(); spin()
    // a start nothing takes: the button doesn't stay silent
    let wasSend = QCDictation.send
    QCDictation.send = { _, _ in false }
    m.dictate(true); spin(0.1)
    check("mic: a start nothing takes says so", !m.dictating && m.dictationNote == QCDictation.failedWords)
    QCDictation.send = wasSend; m.dictationNote = nil
    // Dictation off in macOS: one line saying where to turn it on, once a run; nothing is started
    let before = sent.count
    off = true
    m.dictate(true)
    check("mic: Dictation off says where to turn it on, starts nothing", m.dictationNote == QCDictation.offWords && !m.dictating && sent.count == before)
    m.dictationNote = nil
    m.dictate(true)
    check("mic: and says it once a run", m.dictationNote == nil && sent.count == before)

    // Return while Dictation runs: by default the first Return ends it and shows the transcript (nothing sent), the next
    // sends; "sends at once" is the old behaviour; typing always sends at once
    do {
        check("return: shows the transcript first by default, also when the key is missing from settings.json",
              QuickChatSettings().dictationReturn == .showFirst
              && (try? JSONDecoder().decode(QuickChatSettings.self, from: Data("{}".utf8)))?.dictationReturn == .showFirst
              && (try? JSONDecoder().decode(QuickChatSettings.self, from: Data(#"{"dictationReturn":"sendAtOnce"}"#.utf8)))?.dictationReturn == .sendAtOnce)
        let wasDefaults = m.defaults
        var s = QuickChatSettings()
        m.defaults = { s }
        func fresh() { m.newChat(); m.turns = [oneTurn()]; spin(0.2) }
        func tvNow() -> QCTextView? { p.firstResponder as? QCTextView }

        fresh(); m.field = "typed"; m.submit(marked: false)
        check("return: typing sends at once", m.turns.count == 2 && m.field.isEmpty, "\(m.turns.count) \(m.field.debugDescription)")

        fresh(); m.field = "dictated words"; m.dictating = true
        let n0 = sent.count
        m.submit(marked: false)
        check("return: Dictation running, the first Return ends it and keeps the transcript in the field, nothing sent",
              m.turns.count == 1 && m.field == "dictated words" && !m.dictating && stopped(since: n0, field: tvNow()),
              "\(m.turns.count) \(m.field.debugDescription) \(m.dictating) \(steps(since: n0))")
        m.submit(marked: false)
        check("return: the next Return sends it", m.turns.count == 2 && m.field.isEmpty, "\(m.turns.count) \(m.field.debugDescription)")

        // the operator's case: Dictation running with its last words still marked; the first Return commits them, ends
        // Dictation in the field's input context, keeps the panel key and the field focused, and sends nothing
        fresh(); p.focusField(); spin(0.1)
        if let tv = tvNow() {
            tv.setMarkedText("still provisional", selectedRange: NSRange(location: 17, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            m.dictating = true
            let n2 = sent.count
            m.submit(marked: tv.hasMarkedText())
            check("return: the first Return commits the marked words, ends Dictation step by step, sends nothing",
                  m.turns.count == 1 && !tv.hasMarkedText() && m.field == "still provisional" && !m.dictating && stopped(since: n2, field: tv),
                  "\(m.turns.count) \(m.field.debugDescription) \(steps(since: n2))")
            check("return: and the field keeps the keyboard, the panel key, the caret after the words",
                  p.isKeyWindow && p.firstResponder === tv && tv.selectedRange() == NSRange(location: 17, length: 0), "\(tv.selectedRange())")
            m.submit(marked: tv.hasMarkedText())
            check("return: the next Return sends the dictated words", m.turns.count == 2 && m.field.isEmpty, "\(m.turns.count) \(m.field.debugDescription)")
        } else { check("return: the field has the keyboard (marked)", false) }

        // Dictation started with macOS's own shortcut: the mic button doesn't know; DictationIM's enter notice does
        fresh(); p.focusField(); spin(0.1)
        if let tv = tvNow() {
            tv.setMarkedText("provisional words", selectedRange: NSRange(location: 17, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            let enter = Notification(name: QCDictationWatch.enterName), exit = Notification(name: QCDictationWatch.exitName)
            check("return: the watch listens for DictationIM's enter notice too",
                  QCDictationWatch.enterName.rawValue == "DictationIMNotificationDidEnterDictationMode")
            check("return: marked text alone is not Dictation", !m.isDictationActive && !m.dictating && !m.dictationNoticed)
            chat.dictationWatch.entered(enter)
            check("return: an enter notice makes Dictation active, the button's state stays off", m.isDictationActive && m.dictationNoticed && !m.dictating)
            chat.dictationWatch.exited(exit)
            check("return: an exit notice ends it again", !m.isDictationActive && !m.dictationNoticed)
            chat.dictationWatch.entered(enter)
            p.onKeyLost()
            check("return: the panel losing the keyboard forgets the notice", !m.dictationNoticed)
            chat.dictationWatch.entered(enter)
            let n1 = sent.count
            m.submit(marked: tv.hasMarkedText())
            check("return: marked text with an enter notice (macOS's shortcut) ends Dictation and sends nothing",
                  m.turns.count == 1 && stopped(since: n1, field: tv) && m.field == "provisional words" && !tv.hasMarkedText() && !m.dictationNoticed,
                  "\(m.turns.count) \(steps(since: n1)) \(m.field.debugDescription)")
            m.submit(marked: false)
            check("return: and the next Return sends", m.turns.count == 2 && m.field.isEmpty, "\(m.turns.count) \(m.field.debugDescription)")
        } else { check("return: the field has the keyboard", false) }

        // Dictation known by the field's input source alone (no button, no notice)
        fresh(); p.focusField(); spin(0.1)
        if let tv = tvNow() {
            let wasSource = QCDictation.inputSource
            QCDictation.inputSource = { _ in QCDictation.sourceID }
            tv.setMarkedText("by source", selectedRange: NSRange(location: 9, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            let n1 = sent.count
            check("return: Dictation's input source (com.apple.inputmethod.ironwood) makes Dictation active", QCDictation.sourceID == "com.apple.inputmethod.ironwood" && m.isDictationActive && !m.dictating && !m.dictationNoticed)
            m.submit(marked: tv.hasMarkedText())
            check("return: marked text with Dictation's input source ends Dictation and sends nothing",
                  m.turns.count == 1 && stopped(since: n1, field: tv) && m.field == "by source" && !tv.hasMarkedText(), "\(m.turns.count) \(steps(since: n1))")
            QCDictation.inputSource = wasSource
        } else { check("return: the field has the keyboard (source)", false) }

        // an input method composing (Korean, Japanese…): marked text, its own input source, no Dictation. Return only
        // commits the composition: nothing sent, no stop step, no held Return, the Dictation state untouched
        for source in ["com.apple.inputmethod.Korean.2SetKorean", "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese", "com.apple.keylayout.US"] {
            fresh(); p.focusField(); spin(0.1)
            if let tv = tvNow() {
                let wasSource = QCDictation.inputSource
                QCDictation.inputSource = { _ in source }
                tv.setMarkedText("한", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
                let n1 = sent.count
                m.submit(marked: tv.hasMarkedText())
                check("return: marked text of \(source) is not Dictation's: committed, nothing sent, no stop step, no held Return",
                      m.turns.count == 1 && sent.count == n1 && !m.returnHeld && !tv.hasMarkedText() && m.field == "한" && !m.dictating && !m.dictationNoticed,
                      "\(m.turns.count) \(steps(since: n1)) \(m.returnHeld) \(m.field.debugDescription)")
                m.submit(marked: false)
                check("return: and the next Return sends (\(source))", m.turns.count == 2 && m.field.isEmpty && sent.count == n1, "\(m.turns.count) \(m.field.debugDescription)")
                QCDictation.inputSource = wasSource
            } else { check("return: the field has the keyboard (IME)", false) }
        }
        // "sends at once" leaves an input method's Return alone too
        do {
            var once = QuickChatSettings(); once.dictationReturn = .sendAtOnce
            let was = m.defaults
            m.defaults = { once }
            fresh(); p.focusField(); spin(0.1)
            if let tv = tvNow() {
                tv.setMarkedText("あ", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
                let n1 = sent.count
                m.submit(marked: tv.hasMarkedText())
                check("return: \"sends at once\": an input method's marked text is still only committed", m.turns.count == 1 && sent.count == n1 && !tv.hasMarkedText() && m.field == "あ")
            } else { check("return: the field has the keyboard (IME, at once)", false) }
            m.defaults = was
        }

        s.dictationReturn = .sendAtOnce
        fresh(); m.field = "dictated words"; m.dictating = true
        m.submit(marked: false)
        check("return: \"sends at once\": Return ends Dictation and sends the transcript in one go",
              m.turns.count == 2 && m.field.isEmpty && !m.dictating && sent.last?.0 == QCDictation.activate && neverToggled(),
              "\(m.turns.count) \(m.field.debugDescription)")
        fresh(); m.field = "typed"; m.submit(marked: false)
        check("return: \"sends at once\": typing sends at once too", m.turns.count == 2 && m.field.isEmpty)

        m.defaults = wasDefaults
        m.newChat()
    }

    m.turns = [oneTurn()]; spin(0.6)          // the chat again (the new chat above made it the bar), for what follows
}

// ── after a move, a content change fit() skipped is retried ───────────────────────────────────────────────────────────
do {
    var retried = 0
    let keep = cv.onIntrinsicChange
    cv.onIntrinsicChange = { retried += 1; keep() }
    var surface: QCDragView?
    let gap = NSPoint(x: headerGapX(p.frame.width) ?? 0, y: p.frame.height - 16)
    surface = QCDragView.surface(at: gap, in: p)
    QCDragView.drag = { w, _ in w.setFrameOrigin(NSPoint(x: w.frame.minX + 10, y: w.frame.minY)) }
    if let d = surface { press(d, at: gap) }
    QCDragView.drag = { w, e in w.performDrag(with: e) }
    cv.onIntrinsicChange = keep
    check("a move's end retries fit() (the host's onIntrinsicChange)", surface != nil && retried == 1, "\(retried)")
}

// ── the shortcut: the field has the keyboard at once, whatever had it before ──────────────────────────────────────────
do {
    func field() -> QCTextView? {
        var t: QCTextView?
        func walk(_ v: NSView) { if let x = v as? QCTextView { t = x }; v.subviews.forEach(walk) }
        walk(cv); return t
    }
    func keyed(_ label: String) {
        check("focus \(label): the panel is the key window", p.isKeyWindow)
        check("focus \(label): the field is the first responder", field() != nil && p.firstResponder === field(),
              "\(String(describing: p.firstResponder))")
    }
    // (No window here ever takes the real keyboard (Checks/quiet.swift): the panel's makeKey only notes it and does what
    // becoming key does to its first responder, and "another window has the keyboard" is the panel not being key with
    // nothing focused in it. The decisions checked are open()'s and becomeKey's: the panel key, the field first.)
    func elsewhere() { p.quietKey = false; p.makeFirstResponder(nil) }
    // another window had the keyboard (as Settings would): hidden, then the shortcut
    chat.hide()
    elsewhere(); spin(0.2)
    chat.toggle()
    keyed("right after open(), before any layout pass")          // the first keystroke may come at once
    spin(0.4)
    keyed("after the layout pass")
    // the keyboard was elsewhere in the panel when it hid (a menu or a control had it)
    p.makeFirstResponder(nil)
    chat.hide(); chat.open(); spin(0.3)
    keyed("after hiding with the keyboard elsewhere")
    // the bar (a new chat makes the field anew), right after the shortcut
    chat.hide(); chat.model.newChat(); spin(0.3)
    elsewhere(); spin(0.1)
    chat.open()
    keyed("the bar right after open()")
    spin(0.4)
    // after a resize and a move
    let f0 = p.frame
    liveResize(to: NSRect(x: f0.minX, y: f0.minY - 30, width: f0.width + 40, height: f0.height + 30))
    keyed("after a resize")
    p.isMoving = true; p.setFrameOrigin(NSPoint(x: f0.minX + 20, y: f0.minY)); p.isMoving = false
    keyed("after a move")
    // the panel losing and getting back the key (a menu, Settings): the field again
    elsewhere(); spin(0.1)
    p.makeKey(); spin(0.1)
    keyed("when it becomes key again")
}

// the sign-in script (SignIn): it holds the address, so its first command removes it; a leftover is removed too. Run here
// under build/ with a stand-in for claude (/usr/bin/true): nothing outside build/ is written
do {
    let dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("signin-check")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let text = SignIn.script(folder: dir.appendingPathComponent("folder").path, email: "kim@example.org", marker: nil, claude: "/usr/bin/true")
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    check("sign-in script: its first command removes it", lines.count > 2 && lines[0] == "#!/bin/zsh" && lines[1] == #"rm -f -- "$0""#, text)
    check("sign-in script: then the sign-in, as that address", text.contains("exec '/usr/bin/true' auth login --email 'kim@example.org'"), text)
    let script = dir.appendingPathComponent("sign-in.command")
    try? text.write(to: script, atomically: true, encoding: .utf8)
    let run = Process()
    run.executableURL = URL(fileURLWithPath: "/bin/zsh"); run.arguments = [script.path]
    run.environment = ["PATH": "/usr/bin:/bin", "HOME": dir.path]
    try? run.run(); run.waitUntilExit()
    check("sign-in script: gone once it ran", run.terminationStatus == 0 && !FileManager.default.fileExists(atPath: script.path), "status \(run.terminationStatus)")
    try? "leftover".write(to: script, atomically: true, encoding: .utf8)
    SignIn.removeScript(at: script)
    check("sign-in script: a leftover is removed", !FileManager.default.fileExists(atPath: script.path))
    check("sign-in script: never the real one while checking", Files.readOnly)        // removeScript() leaves it alone then
    try? FileManager.default.removeItem(at: dir)
}

// ── an ended chat leaves nothing behind; a limit notice lasts only while the limit is full ──────────────────────────────
do {
    let m = chat.model
    func deadChat() {
        var t = QuickChatTurn(question: "hi"); t.phase = .failed; t.problem = .limitFull
        m.turns = [t]; m.ended = .idle
    }
    // ended while hidden (15 minutes idle): the shortcut opens a fresh bar
    chat.hide(); deadChat(); m.field = ""
    chat.open(); spin(0.5)
    check("ended: the next open shows the bar, not the dead chat", !m.isWindow && m.turns.isEmpty && m.ended == nil,
          "\(m.turns.count) turns, ended \(String(describing: m.ended))")
    check("ended: the bar is ready to type (key, the field first)", p.isKeyWindow && p.firstResponder is QCTextView)
    check("ended: the panel is the bar's height again", p.frame.height < QuickChatRoot.minWindowHeight, "\(p.frame.size)")
    // ended while open: the ended line shows; the first keystroke takes the dead chat away and keeps what's typed
    deadChat(); spin(0.3)
    check("ended: while open the dead chat and its line stay to read", m.isWindow && m.ended == .idle)
    m.field = "n"
    check("ended: the first keystroke leaves the dead chat (bar, the letter kept)", !m.isWindow && m.ended == nil && m.field == "n")
    m.field = ""
    // two real keystrokes, quickly, right after a chat ended with the window open: through the window as AppKit delivers
    // them (sendEvent → first responder), one run-loop turn apart. The first leaves the dead chat (the chat's field is
    // replaced by the bar's); both letters land, in order, and the caret ends after them.
    deadChat(); spin(0.4)
    p.makeKey(); p.focusField(); spin(0.1)
    func key(_ c: String, _ code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                         windowNumber: p.windowNumber, context: nil, characters: c, charactersIgnoringModifiers: c,
                         isARepeat: false, keyCode: code)!
    }
    p.sendEvent(key("a", 0))
    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    p.sendEvent(key("b", 11))
    spin(0.4)
    var tvNow: QCTextView?
    func findTV(_ v: NSView) { if let t = v as? QCTextView { tvNow = t }; v.subviews.forEach(findTV) }
    findTV(cv)
    check("typing after an end: both letters land in order", m.field == "ab" && tvNow?.string == "ab",
          "field '\(m.field)', text view '\(tvNow?.string ?? "nil")'")
    check("typing after an end: the dead chat is gone (the bar)", !m.isWindow && m.ended == nil)
    check("typing after an end: the field keeps the keyboard, the caret after the letters",
          p.firstResponder === tvNow && tvNow?.selectedRange() == NSRange(location: 2, length: 0),
          "\(String(describing: p.firstResponder)) \(String(describing: tvNow?.selectedRange()))")
    m.field = ""; spin(0.2)
    // a live chat is never cleared by typing or opening
    var live = QuickChatTurn(question: "q", answer: "a", model: "Haiku 5.5"); live.phase = .done
    m.turns = [live]; m.ended = nil
    m.field = "x"; chat.hide(); chat.open(); spin(0.3)
    check("ended: a chat that hasn't ended stays through typing and an open", m.turns.count == 1 && m.field == "x")
    m.field = ""; m.newChat(); spin(0.3)
    // a limit notice is live: it shows while the limit is full and goes when the level shows room
    let now = Date()
    var full = QuickChatLevel(); full.fiveHour = 100; full.fiveHourResets = now.addingTimeInterval(3600); full.week = 53
    var refused = QuickChatTurn(question: "hi"); refused.phase = .failed; refused.problem = .limitFull
    m.level = full; m.turns = [refused]
    check("limit notice: shown while the 5-hour window is full", m.shownProblem(m.turns[0]) == .limitFull)
    var room = full; room.fiveHour = 30
    m.update(target: m.target, level: room, offer: nil)
    check("limit notice: gone as soon as the level shows room", m.shownProblem(m.turns[0]) == nil && !m.blocked)
    var other = QuickChatTurn(question: "q"); other.phase = .failed; other.problem = .stopped(detail: "x")
    check("limit notice: other problems stay", m.shownProblem(other) == .stopped(detail: "x"))
    check("limit notice: with room again the refused turn offers Retry", m.retryAfterLimit(m.turns[0]))
    // an older refused turn: when the limit fills again only the latest turn shows the notice (one Ask on …)
    var later = QuickChatTurn(question: "next", answer: "ok", model: "Haiku 5.5"); later.phase = .done
    m.turns = [refused, later]
    m.update(target: m.target, level: full, offer: nil)
    check("limit notice: an older refused turn doesn't show it again when the limit fills",
          m.blocked && m.shownProblem(m.turns[0]) == nil && !m.retryAfterLimit(m.turns[0]))
    // a switch waiting to resend the stopped question when the chat ends: the question moves to the field
    m.turns = [refused]; m.field = ""; m.ended = .idle
    m.switchNotice = .waiting(wanted: "ultra-2@example.com")
    m.leaveEnded()
    check("ended with a switch waiting: the stopped question stays to be sent (in the field)",
          m.turns.isEmpty && m.field == "hi" && m.pendingQuestion() == "hi", "field '\(m.field)'")
    m.switchNotice = nil; m.field = ""
    m.newChat(); spin(0.3)
}

// ── a full limit is named by the window that is full (the operator's "Main's week is full." with the week at 53%) ─────
do {
    let now = Date()
    var five = QuickChatLevel()          // the 5-hour window full, the week with room
    five.fiveHour = 100; five.fiveHourResets = now.addingTimeInterval(2 * 3600)
    five.week = 53; five.weekResets = now.addingTimeInterval(3 * 86400)
    check("limit: a full 5-hour window is the full one", five.full(now)?.id == "5h", "\(String(describing: five.full(now)))")
    let s5 = QuickChatLevel.fullSentence(five, who: "Main", now: now)
    check("limit: the notice names the 5-hour limit and its reset", s5.hasPrefix("Main's 5-hour limit is full, resets ") && !s5.contains("week"), s5)
    var wk = QuickChatLevel()            // the week full, the 5-hour window with room
    wk.fiveHour = 12; wk.fiveHourResets = now.addingTimeInterval(2 * 3600)
    wk.week = 100; wk.weekResets = now.addingTimeInterval(3 * 86400)
    let sw = QuickChatLevel.fullSentence(wk, who: "Main", now: now)
    check("limit: the notice names the week when the week is full", wk.full(now)?.id == "wk" && sw.hasPrefix("Main's week is full, resets "), sw)
    // Claude Code refused before any 5-hour number came, the week known at 53%: the 5-hour window, not the week
    var refused = QuickChatLevel()
    refused.week = 53; refused.weekResets = now.addingTimeInterval(3 * 86400)
    refused.refusedUntil = now.addingTimeInterval(3600)
    check("limit: a refusal with the week at 53% names the 5-hour window", refused.full(now)?.id == "5h", "\(String(describing: refused.full(now)))")
    var refusedWk = QuickChatLevel()     // the 5-hour window known to have room: the week
    refusedWk.fiveHour = 20; refusedWk.fiveHourResets = now.addingTimeInterval(3600); refusedWk.refusedUntil = now.addingTimeInterval(3600)
    check("limit: a refusal with the 5-hour window at 20% names the week", refusedWk.full(now)?.id == "wk")
    check("limit: with no numbers the notice names no window", QuickChatLevel.fullSentence(nil, who: "Main", now: now) == "Main's limit is full.")
    // refused while get_usage reports both windows with room (5h 20%, week 53%): neither is named, neither drawn full
    var both = QuickChatLevel()
    both.fiveHour = 20; both.fiveHourResets = now.addingTimeInterval(3600)
    both.week = 53; both.weekResets = now.addingTimeInterval(3 * 86400)
    both.refusedUntil = now.addingTimeInterval(1800)
    let sb = QuickChatLevel.fullSentence(both, who: "Main", now: now)
    check("limit: refused with 5h at 20% and the week at 53% names neither window", both.full(now)?.id == FullLimit.any
          && sb.hasPrefix("Main's limit is full, resets ") && !sb.contains("week") && !sb.contains("5-hour"), sb)
    check("limit: …and the dot marks neither full (the fuller share as it is)", both.binding(now)?.id == "wk" && both.binding(now)?.p == 53,
          "\(String(describing: both.binding(now)))")
    check("limit: …while the account is still held back", both.full(now) != nil)
    var none = QuickChatLevel(); none.refusedUntil = now.addingTimeInterval(1800)
    check("limit: refused with no numbers names no window", none.full(now)?.id == FullLimit.any && none.binding(now) == nil)
    // the header and the notice agree, and the dot (binding) points at the same window
    check("limit: the dot's window is the full one", five.binding(now)?.id == "5h" && wk.binding(now)?.id == "wk")
    // the offer shows the other profile's fuller window, not its week alone
    var other = QuickChatLevel(); other.fiveHour = 95; other.fiveHourResets = now.addingTimeInterval(3600); other.week = 18
    check("limit: an offer's share is its fuller window (95, not the week's 18)", other.binding(now)?.p == 95)
}

// live usage: a get_usage answer that comes while the bar is open changes what the bar shows (model.level, which the
// usage indicator, the header and the profile dot draw), over an older level kept from before. A chat model of its own
// on a stand-in `claude` (Checks/stub-claude: 5 hours 44%, week 12%), in a folder under build/: nothing else is touched
do {
    let stub = ProcessInfo.processInfo.environment["QC_STUB_PATH"] ?? ""
    let dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("usage-check")
    try? FileManager.default.createDirectory(at: dir.appendingPathComponent("work"), withIntermediateDirectories: true)
    let m = QuickChatModel()
    var t = QuickChatTarget(Profile(id: "usage-check", name: "Main", folder: dir.appendingPathComponent("folder").path))
    t.workFolder = dir.appendingPathComponent("work").path
    t.accountUUID = "u-check"; t.email = "alex@example.com"
    m.target = t
    m.resolveClaude = { $0(stub) }
    var recorded: (String, String, QuickChatLevel)?
    m.levelReported = { id, account, l in recorded = (id, account, l) }
    // what the bar showed before: the account's level from its last time in use, the week alone
    var old = QuickChatLevel(); old.week = 53; old.weekResets = Date().addingTimeInterval(3 * 86400); old.at = Date().addingTimeInterval(-86400)
    m.level = old
    var drawn = 0
    let watch = m.$level.dropFirst().sink { _ in drawn += 1 }       // the level itself published anew, nothing else
    m.warm()            // as the bar opens: the stand-in starts and is asked get_usage
    let end = Date().addingTimeInterval(8)
    while m.level?.fiveHour == nil, Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    check("live usage: the stand-in was found", FileManager.default.isExecutableFile(atPath: stub), stub)
    check("live usage: the answer replaced the older level", m.level?.weekNow() == 12 && m.level?.fiveHourNow() == 44, "\(String(describing: m.level))")
    check("live usage: the 5-hour number shows with its reset", m.level?.fiveHourResets != nil && m.level?.binding() != nil)
    check("live usage: the view was told", drawn > 0)
    check("live usage: kept for that profile and account", recorded?.0 == "usage-check" && recorded?.1 == "u-check" && recorded?.2.week == 12)
    watch.cancel()
    m.shutdown()
    try? FileManager.default.removeItem(at: dir)
}

// a window get_usage gives is taken whole: an old reset already past never hides the number it just gave
do {
    var l = QuickChatLevel(); l.fiveHour = 80; l.fiveHourResets = Date().addingTimeInterval(-3600); l.week = 50
    l.apply(usage: QuickChatUsage(available: true, fiveHour: .init(used: 0, resets: nil), week: .init(used: 62, resets: Date().addingTimeInterval(86400))))
    check("usage: a window with no reset yet still shows its number", l.fiveHourNow() == 0 && l.weekNow() == 62, "\(l)")
    var kept = l; kept.apply(usage: QuickChatUsage(available: false))
    check("usage: not available keeps the last numbers", kept.fiveHour == 0 && kept.week == 62)
}

// ── ⌘V in the bar ──────────────────────────────────────────────────────────────────────────────────
do {
    chat.hide(); chat.model.newChat(); chat.open(); spin(0.5)
    let pb = NSPasteboard.general
    let saved = pb.pasteboardItems?.map { it -> [(NSPasteboard.PasteboardType, Data)] in it.types.compactMap { t in it.data(forType: t).map { (t, $0) } } }
    func put(_ f: (NSPasteboard) -> Void) { pb.clearContents(); f(pb) }
    /// A ⌘ key press as a layout makes it: the character the layout gives the key, and the key's physical code.
    func cmdKey(_ ch: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags = .command) -> Bool {
        guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: p.windowNumber,
                                       context: nil, characters: ch, charactersIgnoringModifiers: ch, isARepeat: false, keyCode: code) else { return false }
        return p.performKeyEquivalent(with: e)
    }
    func cmdV() -> Bool { cmdKey("v", 9) }
    for (label, fill) in [("plain text", { (b: NSPasteboard) in b.setString("pasted plain", forType: .string) }),
                          ("rich text", { (b: NSPasteboard) in
                              let a = NSAttributedString(string: "pasted rich", attributes: [.font: NSFont.boldSystemFont(ofSize: 20)])
                              if let d = try? a.data(from: NSRange(location: 0, length: a.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) { b.setData(d, forType: .rtf) } }),
                          ("html", { (b: NSPasteboard) in b.setData(Data("<b>pasted html</b>".utf8), forType: .html) })] as [(String, (NSPasteboard) -> Void)] {
        chat.model.field = ""; spin(0.3)
        put(fill)
        check("bar paste (\(label)): the bar is up and the field has the keyboard", p.isVisible && !chat.model.isWindow && p.firstResponder is QCTextView, "\(String(describing: p.firstResponder))")
        let taken = cmdV(); spin(0.3)
        let tv = p.firstResponder as? QCTextView
        print("  bar paste (\(label)): taken=\(taken) field=\(tv?.string.debugDescription ?? "nil") model=\(chat.model.field.debugDescription)")
        check("bar paste (\(label)): ⌘V is taken", taken)
        check("bar paste (\(label)): the field has the text", tv?.string.hasPrefix("pasted") == true, "\(tv?.string ?? "nil")")
        check("bar paste (\(label)): the model has the text", chat.model.field.hasPrefix("pasted"), "\(chat.model.field)")
    }
    // the same key in other layouts. Cyrillic (the V key gives "м", C "с", X "ч", A "ф", Z "я"): the shortcut follows the key's
    // place, as macOS's menus do; Dvorak and the like (Latin letters on other keys): it follows the letter; a Latin layout
    // whose V key gives another letter: that letter's shortcut, not V's.
    let layouts: [(String, String, UInt16, Bool)] = [
        ("Cyrillic ⌘V (м on the V key)", "м", 9, true),
        ("Cyrillic capital ⌘V (М on the V key)", "М", 9, true),
        ("Dvorak ⌘V (v on the key QWERTY calls .)", "v", 47, true),
        ("a Latin layout's k on the V key", "k", 9, false),
        ("a Latin layout's Latin letter on the V key, not an edit key", "b", 9, false),
    ]
    for (label, ch, code, pastes) in layouts {
        chat.model.field = ""; spin(0.3)
        put { $0.setString("pasted layout", forType: .string) }
        _ = cmdKey(ch, code); spin(0.3)
        check("bar paste, \(label): \(pastes ? "pastes" : "does not paste")", (chat.model.field == "pasted layout") == pastes, "\(chat.model.field.debugDescription)")
    }
    // Cyrillic ⌘A selects all, ⌘Z undoes, ⌘X cuts, ⌘C copies; Cyrillic keys that are no edit key do nothing
    chat.model.field = ""; spin(0.3)
    put { $0.setString("pasted layout", forType: .string) }
    _ = cmdKey("м", 9); spin(0.3)
    check("Cyrillic ⌘V pastes first", chat.model.field == "pasted layout", "\(chat.model.field.debugDescription)")
    put { $0.setString("other", forType: .string) }
    _ = cmdKey("ф", 0); _ = cmdKey("с", 8); spin(0.3)
    check("Cyrillic ⌘A then ⌘C copies the field (ф, с)", pb.string(forType: .string) == "pasted layout", "\(pb.string(forType: .string) ?? "nil")")
    put { $0.setString("other", forType: .string) }
    _ = cmdKey("ч", 7); spin(0.3)
    check("Cyrillic ⌘X cuts the selection (ч)", chat.model.field.isEmpty && pb.string(forType: .string) == "pasted layout", "\(chat.model.field.debugDescription)")
    _ = cmdKey("я", 6); spin(0.3)
    check("Cyrillic ⌘Z undoes the cut (я)", chat.model.field == "pasted layout", "\(chat.model.field.debugDescription)")
    // Caps Lock on (the key gives a capital, no Shift) and ⇧ (⌘⇧Z redoes) on the same key
    chat.model.field = ""; spin(0.3)
    put { $0.setString("pasted layout", forType: .string) }
    _ = cmdKey("V", 9, [.command, .capsLock]); spin(0.3)
    check("⌘V with Caps Lock on pastes", chat.model.field == "pasted layout", "\(chat.model.field.debugDescription)")
    _ = cmdKey("М", 9, [.command, .capsLock]); spin(0.3)
    check("Cyrillic ⌘V with Caps Lock on pastes again", chat.model.field == "pasted layoutpasted layout", "\(chat.model.field.debugDescription)")
    _ = cmdKey("z", 6); spin(0.3)
    let undone = chat.model.field
    _ = cmdKey("Z", 6, [.command, .shift]); spin(0.3)
    check("⌘Z undoes and ⌘⇧Z redoes", undone != "pasted layoutpasted layout" && chat.model.field == "pasted layoutpasted layout", "\(undone.debugDescription) -> \(chat.model.field.debugDescription)")
    // the QWERTZ layout (Z and Y swapped): the key where Z sits on a US keyboard gives "y", and ⌘Z is on the key that gives "z"
    chat.model.field = ""; spin(0.3)
    put { $0.setString("pasted layout", forType: .string) }
    _ = cmdKey("v", 9); spin(0.3)
    _ = cmdKey("y", 6); spin(0.3)
    check("QWERTZ: the key that gives y (US Z's place) is no undo", chat.model.field == "pasted layout", "\(chat.model.field.debugDescription)")
    _ = cmdKey("z", 16); spin(0.3)
    check("QWERTZ: the key that gives z (US Y's place) undoes", chat.model.field.isEmpty, "\(chat.model.field.debugDescription)")
    // AZERTY: ⌘A is on the key that gives "a" (US Q's place, code 12), and the key at A's place gives "q"
    chat.model.field = ""; spin(0.3)
    put { $0.setString("pasted layout", forType: .string) }
    _ = cmdKey("v", 9); spin(0.3)
    let sel = { (p.firstResponder as? NSTextView)?.selectedRange().length ?? -1 }
    _ = cmdKey("q", 0); spin(0.2)
    check("AZERTY: the key at A's place gives q, no select-all", sel() == 0, "\(sel())")
    _ = cmdKey("a", 12); spin(0.2)
    check("AZERTY: the key that gives a selects all", sel() == ("pasted layout" as NSString).length, "\(sel())")
    // the letter a shortcut names: Russian and Ukrainian keys (N "т", W "ц" in both; Ukrainian has "і", "ї", "є", "ґ" on keys that
    // are no edit key), a digit or a symbol stays as it is
    func letter(_ ch: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags = .command) -> String? {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: p.windowNumber, context: nil,
                         characters: ch, charactersIgnoringModifiers: ch, isARepeat: false, keyCode: code).flatMap(QuickChatPanel.shortcutLetter)
    }
    check("Cyrillic ⌘N and ⌘W (т, ц) name n and w", letter("т", 45) == "n" && letter("ц", 13) == "w", "\(String(describing: letter("т", 45))) \(String(describing: letter("ц", 13)))")
    check("Cyrillic ⌘⇧Z (Я) names z", letter("Я", 6, [.command, .shift]) == "z")
    check("Ukrainian keys that are no edit key stay as they are", letter("і", 1) == "і" && letter("ї", 30) == "ї" && letter("ґ", 42) == "ґ")
    check("a digit, a symbol and an ASCII capital keep their letter", letter("1", 18) == "1" && letter(",", 43) == "," && letter("V", 9) == "v")
    // ⌥⌘ arrows are function keys, the same on every layout (here with a Cyrillic layout's modifiers-ignored characters)
    var steps: [(Bool, Int)] = []
    let oldStep = p.onStep
    p.onStep = { steps.append(($0, $1)) }
    let L = String(UnicodeScalar(UInt16(NSLeftArrowFunctionKey))!), U = String(UnicodeScalar(UInt16(NSUpArrowFunctionKey))!)
    _ = cmdKey(L, 123, [.command, .option]); _ = cmdKey(U, 126, [.command, .option])
    p.onStep = oldStep
    check("⌥⌘← and ⌥⌘↑ still step the model and thinking", steps.count == 2 && steps[0] == (true, -1) && steps[1] == (false, 1), "\(steps)")
    pb.clearContents()
    if let saved { for it in saved { let n = NSPasteboardItem(); for (t, d) in it { n.setData(d, forType: t) }; pb.writeObjects([n]) } }
}

// A recorded shortcut is named by its key as printed, never by the Shift character (⌃⇧1 is "⌃⇧1", not "⌃⇧!")
do {
    if let us = QuickChatShortcut.layoutData(id: "com.apple.keylayout.US") {
        func n(_ code: Int) -> String? { QuickChatShortcut.keyName(keyCode: UInt32(code), layout: us) }
        check("US layout: the 1 key is named 1", n(18) == "1", "\(String(describing: n(18)))")
        check("US layout: a letter key is the capital (A, Z, K)", n(0) == "A" && n(6) == "Z" && n(40) == "K", "\(String(describing: n(0))) \(String(describing: n(6))) \(String(describing: n(40)))")
        check("US layout: symbol keys are named without Shift (/ , ; =)", n(44) == "/" && n(43) == "," && n(41) == ";" && n(24) == "=", "\(String(describing: n(44))) \(String(describing: n(43))) \(String(describing: n(41)))")
        check("special keys keep their names on any layout", n(kVK_Space) == "Space" && n(kVK_Return) == "Return" && n(kVK_LeftArrow) == "←" && n(kVK_F5) == "F5")
        let hold = UInt32(controlKey | shiftKey)
        let old = QuickChatShortcut(keyCode: 18, key: "!", carbonModifiers: hold)       // as an older version kept it
        check("a stored shifted label shows as the key (⌃⇧! → ⌃⇧1)", old.shownKey == (QuickChatShortcut.keyName(keyCode: 18) ?? "!") && old.title.hasPrefix("⌃⇧"), old.title)
        check("a letter with Shift keeps its capital, modifiers in macOS's order (⌥⇧A)", QuickChatShortcut(keyCode: 0, key: "A", carbonModifiers: UInt32(optionKey | shiftKey)).title == "⌥⇧" + (QuickChatShortcut.keyName(keyCode: 0) ?? "A"))
    } else { print("skip: US layout checks (no com.apple.keylayout.US on this Mac)") }
    // with no layout at all the stored name stands
    check("no layout data: the key's code has no name, the stored one stays", QuickChatShortcut.keyName(keyCode: 18, layout: nil) == nil
          && QuickChatShortcut.keyName(keyCode: UInt32(kVK_Space), layout: nil) == "Space")
}

// ── ⌘⇧C: the latest complete answer to the pasteboard (an injectable one, never the operator's) ──────────────────
do {
    let stub = ProcessInfo.processInfo.environment["QC_STUB_PATH"] ?? ""
    let dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("copy-check")
    try? FileManager.default.createDirectory(at: dir.appendingPathComponent("work"), withIntermediateDirectories: true)
    let m = chat.model
    chat.hide(); m.newChat(); spin(0.3)
    let pb = NSPasteboard(name: NSPasteboard.Name("cl-quick-copy-check-\(ProcessInfo.processInfo.processIdentifier)"))
    pb.clearContents()
    let realPasteboard = m.pasteboard
    m.pasteboard = pb
    defer { pb.releaseGlobally(); m.pasteboard = realPasteboard }
    func key(_ ch: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags = [.command, .shift]) -> Bool {
        guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: p.windowNumber,
                                       context: nil, characters: ch, charactersIgnoringModifiers: ch, isARepeat: false, keyCode: code) else { return false }
        return p.performKeyEquivalent(with: e)
    }
    // nothing yet: the key is taken and copies nothing
    pb.setString("before", forType: .string)
    check("⌘⇧C with no answer: taken, the pasteboard untouched", key("C", 8) && pb.string(forType: .string) == "before", "\(pb.string(forType: .string) ?? "nil")")
    // a real answer from the stand-in `claude`
    var t = QuickChatTarget(Profile(id: "copy-check", name: "Main", folder: dir.appendingPathComponent("folder").path))
    t.workFolder = dir.appendingPathComponent("work").path
    t.accountUUID = "u-copy"; t.email = "alex@example.com"
    // (a chat model of its own talks to the stand-in; its finished turn is then put on the panel's model, which the keys reach)
    let s = QuickChatModel()
    s.target = t
    s.resolveClaude = { $0(stub) }
    s.freshTarget = { _, done in done(t) }
    s.field = "hello"; s.send()
    let end = Date().addingTimeInterval(8)
    while s.turns.last?.phase != .done, Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    let answer = s.turns.last?.answer ?? ""
    s.shutdown()
    m.turns = s.turns; m.level = nil; spin(0.2)
    check("copy: the stand-in answered", s.turns.last?.phase == .done && !answer.isEmpty, "\(String(describing: s.turns.last))")
    check("copy: not copied before the key", m.copied == nil && pb.string(forType: .string) == "before")
    check("copy: ⌘⇧C is taken and puts the answer on the pasteboard", key("C", 8) && pb.string(forType: .string) == answer, "\(pb.string(forType: .string) ?? "nil") vs \(answer)")
    check("copy: it is plain text only, nothing else on the pasteboard", Set(pb.types ?? []).isSubset(of: [.string, NSPasteboard.PasteboardType("NSStringPboardType")]) && pb.pasteboardItems?.count == 1, "\(String(describing: pb.types))")
    check("copy: the answer's footer says Copied", m.copied == m.turns.last?.id)
    // Cyrillic (the C key gives "с"/"С"), and Caps Lock; other letters do nothing
    pb.clearContents(); m.copied = nil
    check("copy: Cyrillic ⌘⇧C (С on the C key) copies", key("С", 8) && pb.string(forType: .string) == answer)
    pb.clearContents()
    check("copy: Cyrillic ⌘⇧C with Caps Lock on copies", key("с", 8, [.command, .shift, .capsLock]) && pb.string(forType: .string) == answer)
    pb.clearContents(); pb.setString("other", forType: .string)
    _ = key("M", 46)                                       // ⌘⇧M: not ours
    check("copy: another letter does not copy", pb.string(forType: .string) == "other")
    // ⌘C (no shift) is still the selection's: with nothing selected it copies nothing of the answer
    pb.clearContents(); pb.setString("other", forType: .string)
    _ = key("c", 8, [.command]); spin(0.2)
    check("copy: ⌘C without Shift does not copy the answer", pb.string(forType: .string) != answer || answer == "other")
    // the footer's Copy button copies the same (and flashes the same tick)
    pb.clearContents(); m.copied = nil
    if let first = m.turns.last { m.copyAnswer(of: first) }
    check("copy: a click on Copy puts the answer there too", pb.string(forType: .string) == answer && m.copied != nil)
    // while a later answer streams: the previous complete one is copied
    var live = QuickChatTurn(question: "next"); live.answer = "half an ans"; live.phase = .streaming
    m.turns.append(live)
    pb.clearContents(); m.copied = nil
    check("streaming: ⌘⇧C copies the previous complete answer", key("C", 8) && pb.string(forType: .string) == answer && m.copied == m.turns[0].id, "\(pb.string(forType: .string) ?? "nil")")
    // a lone streaming answer: nothing, the pasteboard as it was
    m.turns = [live]
    pb.clearContents(); pb.setString("kept", forType: .string); m.copied = nil
    check("streaming, no earlier answer: ⌘⇧C copies nothing (taken, pasteboard untouched)", key("C", 8) && pb.string(forType: .string) == "kept" && m.copied == nil)
    // a stopped answer counts, a failed or empty one never
    var stopped = QuickChatTurn(question: "s", answer: "partial text"); stopped.phase = .stopped
    var failedT = QuickChatTurn(question: "f", answer: "broken"); failedT.phase = .failed
    m.turns = [stopped, failedT]
    check("a stopped answer is copied, a later failed one skipped", key("C", 8) && pb.string(forType: .string) == "partial text")
    m.newChat()
    try? FileManager.default.removeItem(at: dir)
}

// ── images: ⌘V with a picture, thumbnails over the field, the message line, nothing on disk ────────────────────────
// A pasteboard of the checks' own (the operator's clipboard is never touched), the bar's field reading it, and a chat model
// of its own on the stand-in `claude` for what is sent. Fixtures (two image files and a text file, for the file cases) are
// made under build/ only.
do {
    let passedBefore = passed, failedBefore = failed
    func png(_ w: Int, _ h: Int, noise: Bool = false, alpha: Bool = true, _ c: (UInt8, UInt8, UInt8) = (220, 40, 40)) -> Data {
        let spp = alpha ? 4 : 3
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: spp,
                                         hasAlpha: alpha, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let base = rep.bitmapData else { return Data() }
        for y in 0..<h {
            let row = base + y * rep.bytesPerRow
            if noise { arc4random_buf(row, w * spp) }
            for x in 0..<w where !noise {
                row[x * spp] = c.0; row[x * spp + 1] = c.1; row[x * spp + 2] = UInt8((x * 255 / max(1, w - 1)) & 0xFF)
                if alpha { row[x * spp + 3] = 255 }
            }
            if noise && alpha { for x in 0..<w { row[x * spp + 3] = 255 } }
        }
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }
    func pixels(_ i: QCImage) -> Int { Int(max(i.pixels.width, i.pixels.height)) }
    func b64(_ i: QCImage) -> Int { (i.payload.data.count + 2) / 3 * 4 }
    func prepared(_ d: Data) -> QCImage? { if case .success(let i) = QCImages.prepare(d) { return i }; return nil }
    func ls(_ url: URL) -> [String] {
        (FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])?.allObjects as? [URL] ?? [])
            .map { u in let v = try? u.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]); return "\(u.path) \(v?.fileSize ?? -1) \(v?.contentModificationDate?.timeIntervalSince1970 ?? 0)" }
            .sorted()
    }

    // the scaling and encoding, on their own
    let small = prepared(png(2, 2))
    check("images: a 2×2 picture stays 2×2 (never enlarged) and goes as PNG", small.map { pixels($0) == 2 && $0.payload.mediaType == "image/png" } == true, "\(String(describing: small?.pixels))")
    let big = prepared(png(4000, 2500))
    check("images: a 4000×2500 picture is scaled to 1568 on its long side, keeping its shape",
          big.map { pixels($0) == 1568 && abs($0.pixels.height - 980) <= 1 } == true, "\(String(describing: big?.pixels))")
    let tall = prepared(png(1000, 3000))
    check("images: a tall one is capped on its height", tall.map { Int($0.pixels.height) == 1568 && Int($0.pixels.width) == 523 } == true, "\(String(describing: tall?.pixels))")
    let noisyPhoto = prepared(png(2400, 1800, noise: true, alpha: false))
    check("images: a large photo (no transparency) goes as a JPEG under 3.75 MB of base64, at most 1568 px",
          noisyPhoto.map { $0.payload.mediaType == "image/jpeg" && b64($0) <= QCImages.maxBase64 && pixels($0) <= 1568 } == true,
          "\(String(describing: noisyPhoto?.payload.mediaType)) \(noisyPhoto.map(b64) ?? -1) \(String(describing: noisyPhoto?.pixels))")
    let noisyAlpha = prepared(png(2400, 1800, noise: true, alpha: true))
    check("images: a large picture with an alpha channel stays PNG and is scaled down under 3.75 MB of base64",
          noisyAlpha.map { $0.payload.mediaType == "image/png" && b64($0) <= QCImages.maxBase64 && pixels($0) <= 1568 } == true,
          "\(String(describing: noisyAlpha?.payload.mediaType)) \(noisyAlpha.map(b64) ?? -1) \(String(describing: noisyAlpha?.pixels))")
    if case .failure(let why) = QCImages.prepare(Data("not an image".utf8)) { check("images: text is no image", why == .notAnImage) } else { check("images: text is no image", false) }
    check("images: the bytes sent are PNG or JPEG", [small, big, noisyPhoto, noisyAlpha].compactMap { $0 }.allSatisfy {
        $0.payload.mediaType == "image/png" ? $0.payload.data.starts(with: [0x89, 0x50, 0x4E, 0x47]) : $0.payload.data.starts(with: [0xFF, 0xD8, 0xFF]) })
    // a TIFF and a JPEG (what Preview and a camera give) come out as pictures too
    let rep = NSBitmapImageRep(data: png(30, 20))
    check("images: TIFF data is taken", rep?.tiffRepresentation.flatMap(prepared) != nil)
    check("images: JPEG data is taken", rep?.representation(using: .jpeg, properties: [.compressionFactor: 0.9]).flatMap(prepared) != nil)

    // what a pasteboard holds
    let ipb = NSPasteboard(name: NSPasteboard.Name("n-uf.cl-quick.image-checks"))
    func putI(_ f: (NSPasteboard) -> Void) { ipb.clearContents(); f(ipb) }
    let fixtures = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("image-fixtures")
    try? FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
    let fileA = fixtures.appendingPathComponent("shot-a.png"), fileB = fixtures.appendingPathComponent("shot-b.png"), fileT = fixtures.appendingPathComponent("notes.txt")
    try? png(40, 30).write(to: fileA); try? png(30, 40, (20, 200, 40)).write(to: fileB); try? Data("notes".utf8).write(to: fileT)
    putI { $0.setData(png(10, 10), forType: .png) }
    check("images: a picture alone is for the chat (paste and drop)", QCImages.found(in: ipb, forPaste: true) != nil && QCImages.found(in: ipb, forPaste: false) != nil)
    putI { $0.setString("cells", forType: .string); $0.setData(png(10, 10), forType: .png) }
    check("images: text with a picture of it (a spreadsheet's cells) is a text paste", QCImages.found(in: ipb, forPaste: true) == nil)
    check("images: …but a drop of it is a picture", QCImages.found(in: ipb, forPaste: false) != nil)
    putI { $0.setString("shot-a.png", forType: .string); $0.writeObjects([fileA as NSURL]) }
    check("images: a copied image file (Finder gives its name as text too) is an image paste", QCImages.found(in: ipb, forPaste: true)?.sources.count == 1)
    putI { _ = $0.writeObjects([fileT as NSURL]) }
    check("images: a copied text file is left to the field (it pastes the name)", QCImages.found(in: ipb, forPaste: true) == nil)
    check("images: …and a drop of it says it isn't an image", QCImages.found(in: ipb, forPaste: false)?.notImages == ["notes.txt"])
    putI { $0.setString("plain words", forType: .string) }
    check("images: plain text is no image", QCImages.found(in: ipb, forPaste: true) == nil && QCImages.found(in: ipb, forPaste: false) == nil)
    check("images: a drag of text alone is not an image drag", !QCImages.isImageDrag(ipb))
    putI { $0.setData(png(10, 10), forType: .png) }
    check("images: a drag with picture data is an image drag", QCImages.isImageDrag(ipb))

    // the bar: ⌘V with a picture adds a thumbnail and inserts no text
    chat.hide(); chat.model.newChat(); chat.open(); spin(0.5)
    guard let tv = p.firstResponder as? QCTextView else { print("FAIL images: the bar's field has the keyboard"); exit(1) }
    tv.pasteboard = ipb
    func cmdV() -> Bool {
        guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: p.windowNumber,
                                       context: nil, characters: "v", charactersIgnoringModifiers: "v", isARepeat: false, keyCode: 9) else { return false }
        return p.performKeyEquivalent(with: e)
    }
    func waitImages(_ n: Int, _ secs: TimeInterval = 6) {
        let end = Date().addingTimeInterval(secs)
        while (chat.model.images.count != n || chat.model.preparing != 0), Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    }
    let m0 = chat.model
    let tall0 = p.frame.height
    putI { $0.setData(png(300, 200), forType: .png) }
    check("images: ⌘V with a picture is taken", cmdV())
    waitImages(1); spin(0.4)
    check("images: ⌘V with PNG data adds one thumbnail", m0.images.count == 1 && m0.preparing == 0, "\(m0.images.count)")
    check("images: …and inserts no text", tv.string.isEmpty && m0.field.isEmpty, "\(tv.string.debugDescription)")
    check("images: the thumbnail is a real picture", m0.images.first.map { $0.thumbnail.size.width > 0 && $0.thumbnail.size.height > 0 } == true)
    let tall1 = p.frame.height
    check("images: the bar grew to hold the thumbnail row, by a tile and its gap", tall1 > tall0 + 40 && tall1 < tall0 + 60, "\(tall0) → \(tall1)")
    putI { $0.setData(NSBitmapImageRep(data: png(100, 100))?.tiffRepresentation ?? Data(), forType: .tiff) }
    _ = cmdV(); waitImages(2); spin(0.4)
    check("images: ⌘V with TIFF data adds a second", m0.images.count == 2, "\(m0.images.count)")
    check("images: the bar did not change height for the second one (no wobble)", abs(p.frame.height - tall1) < 0.5, "\(tall1) → \(p.frame.height)")
    putI { _ = $0.writeObjects([fileA as NSURL, fileB as NSURL]) }
    _ = cmdV(); waitImages(4); spin(0.4)
    check("images: ⌘V with two image files adds both", m0.images.count == 4, "\(m0.images.count)")
    check("images: the bar still the same height with four", abs(p.frame.height - tall1) < 0.5, "\(tall1) → \(p.frame.height)")
    putI { $0.setData(png(20, 20), forType: .png) }
    _ = cmdV(); waitImages(5); spin(0.3)
    check("images: a fifth is taken", m0.images.count == 5)
    check("images: no note while all fit", m0.imageNote == nil, "\(String(describing: m0.imageNote))")
    putI { $0.setData(png(20, 20), forType: .png) }
    _ = cmdV(); waitImages(5); spin(0.3)
    check("images: a sixth is left out", m0.images.count == 5, "\(m0.images.count)")
    check("images: and the note says so, in one line", m0.imageNote == "Up to 5 images go with a message; one was left out.", "\(String(describing: m0.imageNote))")
    check("images: the bar did not grow for the note beyond one note line", p.frame.height < tall1 + 30, "\(tall1) → \(p.frame.height)")
    // removal: ✕ (removeImage) and Delete in an empty field
    let first = m0.images[0].id
    m0.removeImage(first); spin(0.2)
    check("images: ✕ removes that picture", m0.images.count == 4 && !m0.images.contains { $0.id == first } && m0.imageNote == nil)
    let handled = tv.delegate?.textView?(tv, doCommandBy: #selector(NSResponder.deleteBackward(_:))) ?? false
    check("images: Delete in an empty field removes the last picture", handled && m0.images.count == 3, "\(handled) \(m0.images.count)")
    tv.string = "x"
    let kept = tv.delegate?.textView?(tv, doCommandBy: #selector(NSResponder.deleteBackward(_:))) ?? false
    check("images: Delete in a field with text is the text view's own", !kept && m0.images.count == 3)
    tv.string = ""
    while m0.removeLastImage() {}
    spin(0.4)
    check("images: all removed, the bar is its old height again", m0.images.isEmpty && abs(p.frame.height - tall0) < 0.5, "\(tall0) → \(p.frame.height)")
    // text paste is the text view's own: a picture is not taken when the paste is text (here on the general pasteboard, saved and put back)
    let gen = NSPasteboard.general
    let savedGen = gen.pasteboardItems?.map { it -> [(NSPasteboard.PasteboardType, Data)] in it.types.compactMap { t in it.data(forType: t).map { (t, $0) } } }
    tv.pasteboard = gen
    gen.clearContents(); gen.setString("pasted words", forType: .string); gen.setData(png(10, 10), forType: .png)
    _ = cmdV(); spin(0.3)
    check("images: ⌘V with text and a picture on it pastes the text and attaches nothing", tv.string == "pasted words" && m0.images.isEmpty, "\(tv.string.debugDescription) \(m0.images.count)")
    tv.string = ""; m0.field = ""
    gen.clearContents()
    if let savedGen { for it in savedGen { let n = NSPasteboardItem(); for (t, d) in it { n.setData(d, forType: t) }; gen.writeObjects([n]) } }
    tv.pasteboard = ipb
    // a drop of files: images attach, others are said; a drop of nothing the chat takes is left alone
    putI { _ = $0.writeObjects([fileA as NSURL, fileT as NSURL]) }
    check("images: a drop of an image and a text file is taken", m0.attachFromDrop(ipb))
    waitImages(1); spin(0.3)
    check("images: the image attached, the other named", m0.images.count == 1 && m0.imageNote == "Only images can be attached; notes.txt isn't one.", "\(m0.images.count) \(String(describing: m0.imageNote))")
    putI { _ = $0.writeObjects([fileT as NSURL]) }
    check("images: a drop of only a text file attaches nothing and says why", m0.attachFromDrop(ipb) && m0.images.count == 1 && m0.imageNote == "Only images can be attached; notes.txt isn't one.")
    putI { $0.setString("words", forType: .string) }
    check("images: a drop of text is not taken (the field's own)", !m0.attachFromDrop(ipb))
    // the drag lands on the panel: its hosting view takes it as a drop, not a press; no drag surface is registered for drags
    check("images: the panel's view is a drag destination for files and pictures", cv.registeredDraggedTypes.contains(.fileURL) && cv.registeredDraggedTypes.contains(.png))
    var surfaces = 0, registered = 0
    func walkDrag(_ v: NSView) { if v is QCDragView { surfaces += 1; if !v.registeredDraggedTypes.isEmpty { registered += 1 } }; v.subviews.forEach(walkDrag) }
    walkDrag(cv)
    check("images: drag surfaces exist and none takes a drag itself (a drop reaches the panel's view, never a window move)", surfaces > 0 && registered == 0, "\(surfaces) \(registered)")
    final class FakeDrag: NSObject, NSDraggingInfo {
        let pb: NSPasteboard
        init(_ pb: NSPasteboard) { self.pb = pb }
        var draggingDestinationWindow: NSWindow? { nil }
        var draggingSourceOperationMask: NSDragOperation { .every }
        var draggingLocation: NSPoint { .zero }
        var draggedImageLocation: NSPoint { .zero }
        var draggedImage: NSImage? { nil }
        var draggingPasteboard: NSPasteboard { pb }
        var draggingSource: Any? { nil }
        var draggingSequenceNumber: Int { 1 }
        var draggingFormation: NSDraggingFormation = .default
        var animatesToDestination = false
        var numberOfValidItemsForDrop = 1
        var springLoadingHighlight: NSSpringLoadingHighlight { .none }
        func slideDraggedImage(to screenPoint: NSPoint) {}
        func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?, classes classArray: [AnyClass],
                                    searchOptions: [NSPasteboard.ReadingOptionKey: Any], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
        func resetSpringLoading() {}
    }
    putI { _ = $0.writeObjects([fileB as NSURL]) }
    let fake = FakeDrag(ipb)
    check("images: a drag of an image file over the panel is a copy", cv.draggingEntered(fake) == .copy && m0.dropTarget)
    check("images: dropping it attaches the image and ends the outline", cv.performDragOperation(fake) && !m0.dropTarget)
    waitImages(2); spin(0.3)
    check("images: the dropped image is a thumbnail", m0.images.count == 2, "\(m0.images.count)")
    cv.draggingExited(fake)
    putI { $0.setString("words", forType: .string) }
    check("images: a text drag is not taken by the panel's view as images", cv.draggingEntered(FakeDrag(ipb)) != .copy || !m0.dropTarget)
    while m0.removeLastImage() {}; m0.imageNote = nil
    tv.pasteboard = .general
    m0.newChat()
    spin(0.3)

    // sent: a chat model of its own on the stand-in `claude`; the message line the stand-in reads, and nothing written
    let stub = ProcessInfo.processInfo.environment["QC_STUB_PATH"] ?? ""
    let dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("images-check")
    try? FileManager.default.removeItem(at: dir)
    try? FileManager.default.createDirectory(at: dir.appendingPathComponent("work"), withIntermediateDirectories: true)
    let argsFile = dir.appendingPathComponent("args.txt").path
    try? "mode=ok\nargs=\(argsFile)\n".write(to: dir.appendingPathComponent("stub.conf"), atomically: true, encoding: .utf8)
    let m = QuickChatModel()
    var tg = QuickChatTarget(Profile(id: "images-check", name: "Main", folder: dir.appendingPathComponent("folder").path))
    tg.workFolder = dir.appendingPathComponent("work").path
    tg.accountUUID = "u-images"; tg.email = "alex@example.com"
    m.target = tg
    m.resolveClaude = { $0(stub) }
    m.freshTarget = { _, done in done(tg) }
    let support = ls(Files.folder), work = ls(dir.appendingPathComponent("work"))
    let tmp = Set((try? FileManager.default.contentsOfDirectory(atPath: NSTemporaryDirectory())) ?? [])
    func attach(_ srcs: [QCImages.Source], _ n: Int) {
        var landed = false
        m.attach(QCImages.Found(sources: srcs)) { landed = true }
        let end = Date().addingTimeInterval(6)
        while (!landed || m.images.count != n), Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    }
    func answered(_ n: Int) {
        let end = Date().addingTimeInterval(8)
        while !(m.turns.count == n && m.turns.last?.phase == .done), Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    }
    // an image alone
    attach([.data(png(64, 48))], 1)
    let sentImage = m.images.first
    m.send()
    check("images: an image alone is a message (a turn with no text and the image)", m.turns.count == 1 && m.turns[0].question.isEmpty && m.turns[0].images.count == 1, "\(m.turns.count)")
    check("images: sending empties the attachments", m.images.isEmpty && m.preparing == 0)
    answered(1)
    check("images: the image-only message was answered", m.turns.last?.phase == .done, "\(String(describing: m.turns.last?.phase))")
    // text and two images
    attach([.data(png(120, 80, (10, 10, 200))), .file(fileB)], 2)
    let two = m.images
    m.field = "What changed?"
    m.send()
    answered(2)
    check("images: text and two images was answered", m.turns.last?.phase == .done && m.turns.last?.images.count == 2, "\(String(describing: m.turns.last?.phase))")
    // a plain message
    m.field = "thanks"; m.send(); answered(3)
    // a retry sends the same images again
    m.again(); answered(3)
    let lines = ((try? String(contentsOfFile: argsFile + ".in", encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    check("images: the stand-in got four message lines (image alone, text with two images, plain, the retry)", lines.count == 4, "\(lines.count)")
    func blocks(_ i: Int) -> [[String: Any]]? {
        guard i < lines.count, let o = (try? JSONSerialization.jsonObject(with: Data(lines[i].utf8))) as? [String: Any] else { return nil }
        return (o["message"] as? [String: Any])?["content"] as? [[String: Any]]
    }
    func plain(_ i: Int) -> String? {
        guard i < lines.count, let o = (try? JSONSerialization.jsonObject(with: Data(lines[i].utf8))) as? [String: Any] else { return nil }
        return (o["message"] as? [String: Any])?["content"] as? String
    }
    check("images: line 1 is one image block and no text block", blocks(0)?.map { $0["type"] as? String } == ["image"], "\(String(describing: blocks(0)?.map { $0["type"] as Any }))")
    let src0 = blocks(0)?.first?["source"] as? [String: Any]
    check("images: line 1's image is the base64 of what was attached",
          src0?["type"] as? String == "base64" && src0?["media_type"] as? String == "image/png"
          && Data(base64Encoded: src0?["data"] as? String ?? "") == sentImage?.payload.data)
    check("images: line 2 is image, image, then the text", blocks(1)?.map { $0["type"] as? String } == ["image", "image", "text"], "\(String(describing: blocks(1)?.map { $0["type"] as Any }))")
    check("images: line 2's text is the question", blocks(1)?.last?["text"] as? String == "What changed?")
    check("images: line 2's images are the two attached, in order",
          (blocks(1) ?? []).prefix(2).enumerated().allSatisfy { i, b in
              Data(base64Encoded: ((b["source"] as? [String: Any])?["data"] as? String) ?? "") == two[i].payload.data })
    check("images: line 3 is a plain string message", plain(2) == "thanks", "\(String(describing: plain(2)))")
    check("images: the retry of the plain message is plain too", plain(3) == "thanks", "\(String(describing: plain(3)))")
    m.turns.removeAll()
    m.images = []
    // retry of an image message keeps its images
    attach([.data(png(32, 32))], 1)
    m.field = "again please"; m.send(); answered(1); m.again(); answered(1)
    let lines2 = ((try? String(contentsOfFile: argsFile + ".in", encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    check("images: Ask again sends the same images again", lines2.count == 6 && lines2[4].contains("\"image\"") && lines2[5].contains("\"image\""), "\(lines2.count)")
    m.shutdown()
    // nothing written: the app's folder, the work folder and the temp folder (no picture files) are as they were
    check("images: nothing was written to the app's support folder", ls(Files.folder) == support, "\(ls(Files.folder).count) vs \(support.count)")
    check("images: nothing was written to the work folder", ls(dir.appendingPathComponent("work")) == work, "\(ls(dir.appendingPathComponent("work")))")
    let newTmp = Set((try? FileManager.default.contentsOfDirectory(atPath: NSTemporaryDirectory())) ?? []).subtracting(tmp)
        .filter { ["png", "jpg", "jpeg", "tiff", "tif", "heic"].contains(($0 as NSString).pathExtension.lowercased()) }
    check("images: no picture file was made in the temp folder", newTmp.isEmpty, "\(newTmp)")
    ipb.clearContents()
    try? FileManager.default.removeItem(at: fixtures)
    print("  images: \(passed - passedBefore) of \(passed + failed - passedBefore - failedBefore) checks passed")
}

CheckQuiet.verify("at the end")
print(failed == 0 ? "panel checks: \(passed)/\(passed) passed" : "panel checks: \(failed) failed, \(passed) passed")
exit(failed == 0 ? 0 : 1)
