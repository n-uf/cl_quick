// The quick chat panel's resize handles. The panel is the card plus a rim of QuickChatRoot.margin (8 pt) all round, and the
// eight handles lie in that rim: four edge strips 8 pt thick and four corner squares of 13 pt (the corner squares reach
// 5 pt along the rim past the card's corner, where the rounded card isn't). None of them is over the card, so a press on the
// card is never a resize (and moving, from the card, never changes the size).
//
// Each handle has an invisible but NON-ZERO fill (black at alpha 0.02): a window server passes the mouse through the fully
// transparent pixels of a non-opaque window to whatever is below, so a clear rim would never get a click; the system's own
// edge zones of a borderless window, which are in that rim, would not either. The fill is under 2% dark and can't be seen.
//
// A drag is followed in a tracking loop (events only, no timers), so it always ends with the mouse button: no state is left
// behind if the panel is hidden meanwhile. The frame follows the pointer within the content's own least size (the hosting
// view sets contentMinSize from QuickChatRoot's frames) and the screen's visible frame, the opposite edge staying put.

import AppKit

struct QCEdges: OptionSet {
    let rawValue: Int
    static let left = QCEdges(rawValue: 1), right = QCEdges(rawValue: 2), top = QCEdges(rawValue: 4), bottom = QCEdges(rawValue: 8)
}

final class QCResizeHandle: NSView {
    /// The rim's thickness and the corner squares' size (frame points).
    static let rim: CGFloat = 8
    static let corner: CGFloat = 13
    static let fillAlpha: CGFloat = 0.02
    static let all: [QCEdges] = [.left, .right, .top, .bottom, [.left, .top], [.right, .top], [.left, .bottom], [.right, .bottom]]

    let edges: QCEdges
    private var tracking: NSTrackingArea?

    init(edges: QCEdges) {
        self.edges = edges
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0, alpha: Self.fillAlpha).cgColor
    }
    required init?(coder: NSCoder) { nil }

    /// Puts the eight handles in the rim of a view of this size. `flipped`: the view's origin is top-left (NSHostingView's is).
    static func place(_ handles: [QCResizeHandle], in bounds: NSRect, flipped: Bool) {
        let e = rim, c = corner, w = bounds.width, h = bounds.height
        for handle in handles {
            let ed = handle.edges
            let horizontal = ed.contains(.left) || ed.contains(.right), vertical = ed.contains(.top) || ed.contains(.bottom)
            // the y of a handle on the bottom / top side, for a strip of height `t`
            func y(_ t: CGFloat) -> CGFloat { (ed.contains(.bottom) != flipped) ? 0 : h - t }
            let frame: NSRect
            if horizontal && vertical {
                frame = NSRect(x: ed.contains(.left) ? 0 : w - c, y: y(c), width: c, height: c)
            } else if horizontal {
                frame = NSRect(x: ed.contains(.left) ? 0 : w - e, y: c, width: e, height: max(0, h - 2 * c))
            } else {
                frame = NSRect(x: c, y: y(e), width: max(0, w - 2 * c), height: e)
            }
            if handle.frame != frame { handle.frame = frame }
        }
    }

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // The cursor: a tracking area with cursor updates (active always), so it shows while the panel isn't the key window too.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t); tracking = nil }
        let t = NSTrackingArea(rect: .zero, options: [.cursorUpdate, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }
    override func cursorUpdate(with event: NSEvent) { Self.cursor(for: edges).set() }
    override func mouseEntered(with event: NSEvent) { Self.cursor(for: edges).set() }
    // (no mouseExited: whatever is entered next sets its own cursor, and AppKit resets it outside the window)

    /// Where the pointer is, in screen points, for an event of the drag. It is the pointer's own place, never an event's
    /// `locationInWindow` converted with the window as it is now: a resize moves the window, and events queued before the last
    /// step were measured against its old origin, which would run a bottom or left edge ahead of the pointer. (A check
    /// replaces this to script a drag.)
    static var pointer: (NSEvent) -> NSPoint = { _ in NSEvent.mouseLocation }

    override func mouseDown(with event: NSEvent) {
        guard let w = window as? QuickChatPanel else { return }
        let start = w.frame
        let from = Self.pointer(event)
        w.beginResize()
        Self.cursor(for: edges).push()
        defer {
            NSCursor.pop()
            // still over the handle: its cursor, not whatever was under the push
            let inside = w.isVisible && bounds.contains(convert(w.mouseLocationOutsideOfEventStream, from: nil))
            (inside ? Self.cursor(for: edges) : NSCursor.arrow).set()
            w.endResize()
        }
        while let e = NSApp.nextEvent(matching: [.leftMouseDragged, .leftMouseUp], until: .distantFuture, inMode: .eventTracking, dequeue: true) {
            if e.type == .leftMouseUp || !w.isVisible { break }
            let f = Self.frame(from: start, edges: edges, by: Self.pointer(e) - from, in: w)
            if f != w.frame { w.setFrame(f, display: true); w.invalidateShadow() }
        }
    }

    /// The frame after dragging `edges` of `start` by `d` (screen points): within the least size the content asks for
    /// (contentMinSize) and the screen's visible size, the opposite edges where they were.
    static func frame(from start: NSRect, edges: QCEdges, by d: NSPoint, in w: NSWindow) -> NSRect {
        var width = start.width, height = start.height
        if edges.contains(.right) { width += d.x }
        if edges.contains(.left) { width -= d.x }
        if edges.contains(.top) { height += d.y }
        if edges.contains(.bottom) { height -= d.y }
        let vis = (w.screen ?? NSScreen.main)?.visibleFrame
        let lo = w.contentMinSize
        let hiW = max(lo.width, min(w.contentMaxSize.width, vis?.width ?? .greatestFiniteMagnitude))
        let hiH = max(lo.height, min(w.contentMaxSize.height, vis?.height ?? .greatestFiniteMagnitude))
        width = min(max(width, lo.width), hiW)
        height = min(max(height, lo.height), hiH)
        let x = edges.contains(.left) ? start.maxX - width : start.minX
        let y = edges.contains(.bottom) ? start.maxY - height : start.minY
        return NSRect(x: x, y: y, width: width, height: height)
    }

    /// The resize cursor for these edges: macOS 15's frame-resize cursors, or the two straight ones and, at the corners,
    /// the diagonal ones AppKit has under private names (the crosshair if they're gone).
    static func cursor(for e: QCEdges) -> NSCursor {
        let h = e.contains(.left) || e.contains(.right), v = e.contains(.top) || e.contains(.bottom)
        if #available(macOS 15, *) {
            let pos: NSCursor.FrameResizePosition
            switch (e.contains(.left), e.contains(.right), e.contains(.top), e.contains(.bottom)) {
            case (true, _, true, _): pos = .topLeft
            case (_, true, true, _): pos = .topRight
            case (true, _, _, true): pos = .bottomLeft
            case (_, true, _, true): pos = .bottomRight
            case (true, _, _, _): pos = .left
            case (_, true, _, _): pos = .right
            case (_, _, true, _): pos = .top
            default: pos = .bottom
            }
            return NSCursor.frameResize(position: pos, directions: .all)
        }
        if h && v {
            // top-left and bottom-right drag along one diagonal, top-right and bottom-left along the other
            let nwse = (e.contains(.left) && e.contains(.top)) || (e.contains(.right) && e.contains(.bottom))
            let sel = Selector(nwse ? "_windowResizeNorthWestSouthEastCursor" : "_windowResizeNorthEastSouthWestCursor")
            if NSCursor.responds(to: sel), let c = NSCursor.perform(sel)?.takeUnretainedValue() as? NSCursor { return c }
            return .crosshair
        }
        return h ? .resizeLeftRight : .resizeUpDown
    }
}

private func - (a: NSPoint, b: NSPoint) -> NSPoint { NSPoint(x: a.x - b.x, y: a.y - b.y) }
