// QCDragSurface: what lets the quick chat's panel be dragged by its empty areas. SwiftUI's views inside an NSHostingView
// catch the mouse, so the panel's own "movable by background" only worked in a few spots. A transparent view behind the
// content takes the mouse where nothing in front of it does (the padding, the gaps of the picker row, the space around
// and between answers) and hands the drag to the window. The field, the pickers, the buttons and the selectable text sit
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
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func mouseMoved(with event: NSEvent) { setCursor(at: NSEvent.mouseLocation) }
    override func cursorUpdate(with event: NSEvent) { setCursor(at: NSEvent.mouseLocation) }

    /// The cursor for this point, as `hit` finds it: the open hand where a press would move the window (a drag surface);
    /// over a SwiftUI button or label (the hosting view takes those) the pointing hand or the arrow; in the frame's resize
    /// region, or over an AppKit view of the content's own (the field, a scroll bar), nothing: the system's resize cursor
    /// or that view's own.
    private func setCursor(at screen: NSPoint) {
        guard let w = window else { return }
        let hit = Self.hit(at: w.convertPoint(fromScreen: screen), in: w)
        if hit is QCDragView { (Self.movesWindow ? NSCursor.openHand : NSCursor.arrow).set() }
        else if hit is NSHostingView<QuickChatRoot> { (QCCursorView.hovered ? NSCursor.pointingHand : NSCursor.arrow).set() }
    }

    // A window that is ordered out (Esc, ✕) is sent no mouseExited: when it is hidden or shown again, ask where the pointer is.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        guard let w = window else { return }
        NotificationCenter.default.addObserver(self, selector: #selector(windowShownOrHidden), name: NSWindow.didChangeOcclusionStateNotification, object: w)
    }
    @objc private func windowShownOrHidden() {
        guard onHover != nil, let w = window else { return }
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
