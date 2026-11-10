// Resize handles for the quick chat's panel. The panel is a transparent margin (QuickChatRoot.margin) around the visible
// card, and the handles live in that margin: 8 pt edge strips and 16 pt corner squares (8 of each in the margin, the rest
// over the card's outermost 8 pt, where nothing but padding is). So they can't take a click from the field, the pickers, the
// send key or a scroll bar, and they are big enough to hit. Each shows the matching resize cursor.
//
// The frame is set from the pointer as it moves (events, no timers), within the limits the panel is given: the least and
// the most it may be (QuickChatPanel.limits).

import AppKit

struct QCEdges: OptionSet {
    let rawValue: Int
    static let left = QCEdges(rawValue: 1), right = QCEdges(rawValue: 2), top = QCEdges(rawValue: 4), bottom = QCEdges(rawValue: 8)
}

/// The panel's content view: the hosting view filling it, and the eight handles over it.
final class QuickChatContainer: NSView {
    private let content: NSView
    private var handles: [QCResizeHandle] = []
    static let edge: CGFloat = 8
    static let corner: CGFloat = 16

    init(content: NSView) {
        self.content = content
        super.init(frame: .zero)
        addSubview(content)
        let all: [QCEdges] = [.left, .right, .top, .bottom, [.left, .top], [.right, .top], [.left, .bottom], [.right, .bottom]]
        for e in all {
            let h = QCResizeHandle(edges: e)
            addSubview(h)
            handles.append(h)
        }
    }
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        content.frame = bounds
        let e = Self.edge, c = Self.corner, w = bounds.width, h = bounds.height
        for handle in handles {
            let ed = handle.edges
            let horizontal = ed.contains(.left) || ed.contains(.right), vertical = ed.contains(.top) || ed.contains(.bottom)
            if horizontal && vertical {
                handle.frame = NSRect(x: ed.contains(.left) ? 0 : w - c, y: ed.contains(.bottom) ? 0 : h - c, width: c, height: c)
            } else if horizontal {
                handle.frame = NSRect(x: ed.contains(.left) ? 0 : w - e, y: c, width: e, height: max(0, h - 2 * c))
            } else {
                handle.frame = NSRect(x: c, y: ed.contains(.bottom) ? 0 : h - e, width: max(0, w - 2 * c), height: e)
            }
        }
    }
}

final class QCResizeHandle: NSView {
    let edges: QCEdges
    private var start = NSRect.zero
    private var from = NSPoint.zero
    private var tracking: NSTrackingArea?

    init(edges: QCEdges) {
        self.edges = edges
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { nil }

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
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }

    override func mouseDown(with event: NSEvent) {
        guard let w = window as? QuickChatPanel else { return }
        start = w.frame
        from = w.convertPoint(toScreen: event.locationInWindow)
        w.isResizing = true
        Self.cursor(for: edges).push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let w = window as? QuickChatPanel else { return }
        let p = w.convertPoint(toScreen: event.locationInWindow)
        let dx = p.x - from.x, dy = p.y - from.y
        let (lo, hi) = w.limits()
        var width = start.width, height = start.height
        if edges.contains(.right) { width += dx }
        if edges.contains(.left) { width -= dx }
        if edges.contains(.top) { height += dy }
        if edges.contains(.bottom) { height -= dy }
        width = min(max(width, lo.width), max(lo.width, hi.width))
        height = min(max(height, lo.height), max(lo.height, hi.height))
        // the opposite edge stays where it was
        let x = edges.contains(.left) ? start.maxX - width : start.minX
        let y = edges.contains(.bottom) ? start.maxY - height : start.minY
        let f = NSRect(x: x, y: y, width: width, height: height)
        if f != w.frame { w.setFrame(f, display: true); w.invalidateShadow() }
    }

    override func mouseUp(with event: NSEvent) {
        guard let w = window as? QuickChatPanel else { return }
        NSCursor.pop()
        w.isResizing = false
        w.onResized()
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
            let name = nwse ? "_windowResizeNorthWestSouthEastCursor" : "_windowResizeNorthEastSouthWestCursor"
            let sel = Selector(name)
            if NSCursor.responds(to: sel), let c = NSCursor.perform(sel)?.takeUnretainedValue() as? NSCursor { return c }
            return .crosshair
        }
        return h ? .resizeLeftRight : .resizeUpDown
    }
}
