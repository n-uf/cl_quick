// QCDragSurface: what lets the quick chat's panel be dragged by its empty areas. SwiftUI's views inside an NSHostingView
// catch the mouse, so the panel's own "movable by background" only worked in a few spots. A transparent view behind the
// content takes the mouse where nothing in front of it does (the padding, the gaps of the controls row, the space around
// and between answers) and hands the drag to the window. The field, the controls, the buttons and the selectable text sit
// in front and keep their clicks; scrolling goes up the responder chain to the scroll view, as it does for any view.

import AppKit
import SwiftUI

struct QCDragSurface: NSViewRepresentable {
    /// Set: the pointer being over this area is told to it (a tracking area, so SwiftUI's hit-testing, which would
    /// take the mouse from the drag, isn't involved).
    var hover: Binding<Bool>?

    func makeNSView(context: Context) -> NSView {
        let v = QCDragView()
        v.onHover = hover.map { b in { b.wrappedValue = $0 } }
        return v
    }
    func updateNSView(_ view: NSView, context: Context) {
        (view as? QCDragView)?.onHover = hover.map { b in { b.wrappedValue = $0 } }
    }
}

final class QCDragView: NSView {
    /// Whether a press on a drag surface moves the panel (it was off while the resize was judged alone).
    static let movesWindow = true

    /// What a press does to move the window: the window server's own drag, which follows the pointer and returns on
    /// mouse-up. (A check replaces it to script a move: no pointer can be driven there.)
    static var drag: (NSWindow, NSEvent) -> Void = { w, e in w.performDrag(with: e) }

    /// What a press at this point of the window (window coordinates) would hit, as NSWindow.sendEvent finds it: from the
    /// window's frame view, so the frame's resize region (a band inside every edge, larger at the corners) comes first.
    /// nil there and outside the window.
    static func hit(at inWindow: NSPoint, in w: NSWindow) -> NSView? {
        guard let content = w.contentView else { return nil }
        let root = content.superview ?? content
        let v = root.hitTest(root.superview?.convert(inWindow, from: nil) ?? inWindow)
        return v === root ? nil : v
    }

    /// The drag surface a press at this point would start a move from: only an empty area of the card, never the frame's
    /// resize region, the field, a picker, a button, the address's hover zone or the profile's name (SwiftUI's hosting
    /// view, or an AppKit view of its own, takes those).
    static func surface(at inWindow: NSPoint, in w: NSWindow) -> QCDragView? { hit(at: inWindow, in: w) as? QCDragView }

    var onHover: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?

    // false: the ONLY thing that moves the panel is mouseDown below (performDrag), and only from a drag surface, which lies
    // inside the card; the window server never starts a move of its own: the panel isn't movable by its background, and
    // the hosting view (false too) covers the transparent title bar, so no part of it is a title bar drag region
    override var mouseDownCanMoveWindow: Bool { false }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard Self.movesWindow, let w = window else { return }
        // a MOVE: the window server moves the window and nothing here changes its size, so the panel is told it is moving
        // (QuickChat.fit stays out), with the closed hand for as long as the drag lasts (performDrag returns on mouse-up)
        let panel = w as? QuickChatPanel
        panel?.isMoving = true
        NSCursor.closedHand.push()
        Self.drag(w, event)
        NSCursor.pop()
        panel?.isMoving = false
        setCursor(at: NSEvent.mouseLocation)
        // a change of the content's height that fit() skipped during the move (a line more in the field): retried now
        (w.contentView as? QuickChatHostingView)?.onIntrinsicChange()
    }

    // One tracking area (events when the pointer enters, leaves and moves, and AppKit's cursor updates: nothing is polled)
    // for the hover and the cursor. Active always: the hand shows while the panel isn't the key window too.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t); tracking = nil }
        let t = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true); setCursor(at: NSEvent.mouseLocation) }
    override func mouseExited(with event: NSEvent) {
        onHover?(false)
        // left for another drag surface, a control, the resize region or another window: whatever is there now; the hand
        // never stays where no press would move the window
        setCursor(at: NSEvent.mouseLocation)
    }
    override func mouseMoved(with event: NSEvent) { setCursor(at: NSEvent.mouseLocation) }
    override func cursorUpdate(with event: NSEvent) { setCursor(at: NSEvent.mouseLocation) }

    /// The cursor this view sets at a point of the window (window coordinates), as `hit` finds it: the open hand where a
    /// press would move the window (a drag surface); over SwiftUI's own content, a button or a label (the hosting view
    /// or one of its internal containers takes those), the arrow, unless the pointer is on a control with the pointing
    /// hand (QCCursorView sets that one, and this never fights it); nil (nothing set here) in the frame's resize region
    /// (the system's resize cursor) and over an AppKit view with a cursor of its own (the field, selectable text, a scroll
    /// bar, a control). Outside a visible window: nil.
    static func cursor(at inWindow: NSPoint, in w: NSWindow) -> NSCursor? {
        guard w.isVisible, let content = w.contentView, let hit = Self.hit(at: inWindow, in: w) else { return nil }
        if hit is QCDragView { return movesWindow ? .openHand : .arrow }
        if hit is QCFieldAreaView || hit is QCTextView { return .iBeam }     // the field and its box: the I-beam, never a hand
        if hit is NSText || hit is NSScroller || hit is NSControl || !hit.isDescendant(of: content) { return nil }
        return QCCursorView.hovered ? nil : .arrow
    }

    /// The hands are this view's alone: wherever no drag surface is (the window hidden, the pointer gone from it), an open
    /// or closed hand left over goes back to the arrow. Any other cursor is someone else's and stays.
    static func dropHand() {
        let c = NSCursor.current
        if c === NSCursor.openHand || c === NSCursor.closedHand { NSCursor.arrow.set() }
    }

    private func setCursor(at screen: NSPoint) {
        guard let w = window else { return }
        let inWindow = w.convertPoint(fromScreen: screen)
        if let c = Self.cursor(at: inWindow, in: w) { c.set() }
        else if !w.isVisible || !NSRect(origin: .zero, size: w.frame.size).contains(inWindow) { Self.dropHand() }
    }

    // A window that is ordered out (Esc, ⌘W, ✕, the shortcut) is sent no mouseExited: when it is hidden the hand goes and
    // the hover ends; when it is shown again, ask where the pointer is.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        guard let w = window else { return }
        NotificationCenter.default.addObserver(self, selector: #selector(windowShownOrHidden), name: NSWindow.didChangeOcclusionStateNotification, object: w)
    }
    @objc private func windowShownOrHidden() {
        guard let w = window else { return }
        if !w.isVisible { Self.dropHand() }
        onHover?(w.isVisible && bounds.contains(convert(w.mouseLocationOutsideOfEventStream, from: nil)))
    }
}

private struct QCDraggable: ViewModifier {
    var hover: Binding<Bool>?
    @Environment(\.qcRendering) private var rendering

    func body(content: Content) -> some View {
        // a picture (`--render-quick-chat`) can't draw an AppKit view, and has no mouse
        if rendering { content } else { content.background(QCDragSurface(hover: hover)) }
    }
}

extension View {
    /// The panel can be dragged from this view's empty areas. `hover`: also tells whether the pointer is over the view.
    func qcDraggable(hover: Binding<Bool>? = nil) -> some View { modifier(QCDraggable(hover: hover)) }
}

/// A control (a button, a picker, the address's hover zone): its whole frame takes the press, so no part of it, its
/// clear padding, the gaps between its glyphs and its rounded corners included, is left to the drag surface behind it
/// (a plain-style button otherwise takes the press only where it draws). An inert AppKit marker of its frame goes with
/// it (never hit, no tracking), so Checks/panel can prove no point of a control starts a move.
private struct QCControl: ViewModifier {
    @Environment(\.qcRendering) private var rendering
    func body(content: Content) -> some View {
        let shaped = content.contentShape(Rectangle())
        if rendering { shaped } else { shaped.background(QCControlMarkView.Mark()) }
    }
}

final class QCControlMarkView: NSView {
    struct Mark: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView { QCControlMarkView() }
        func updateNSView(_ view: NSView, context: Context) {}
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

extension View {
    /// This view is a control: all of its frame takes the press, never the drag surface behind it.
    func qcControl() -> some View { modifier(QCControl()) }
}

/// The pointing hand over a view that does something when clicked. A tracking area (cursor updates, active always), so
/// it works while the panel isn't the key window, and it takes no clicks itself.
struct QCCursorArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { QCCursorView() }
    func updateNSView(_ view: NSView, context: Context) {}
}

private struct QCPointingHand: ViewModifier {
    @Environment(\.qcRendering) private var rendering
    func body(content: Content) -> some View {
        if rendering { content } else { content.background(QCCursorArea()) }     // a picture has no pointer
    }
}

extension View {
    /// The pointing hand over this view.
    func qcPointingHand() -> some View { modifier(QCPointingHand()) }
}

final class QCCursorView: NSView {
    /// The pointer is on one of these (the drag surfaces' arrow must not undo the hand).
    static var hovered = false
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.cursorUpdate, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func mouseEntered(with event: NSEvent) { Self.hovered = true; NSCursor.pointingHand.set() }
    override func mouseExited(with event: NSEvent) { Self.hovered = false; NSCursor.arrow.set() }

    // A window that is ordered out gets no mouseExited: the hand must not stay over what is under it.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        guard let w = window else { return }
        NotificationCenter.default.addObserver(self, selector: #selector(windowChanged), name: NSWindow.didChangeOcclusionStateNotification, object: w)
    }
    @objc private func windowChanged() {
        if window?.isVisible != true { Self.hovered = false; NSCursor.arrow.set() }
    }
}
