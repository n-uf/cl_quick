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
    var onHover: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?

    override var mouseDownCanMoveWindow: Bool { true }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        // a MOVE: the window server moves the window and nothing here changes its size, so the panel is told it is moving
        // (QuickChat.fit stays out), with the closed hand for as long as the drag lasts (performDrag returns on mouse-up)
        let panel = window as? QuickChatPanel
        panel?.isMoving = true
        NSCursor.closedHand.push()
        window?.performDrag(with: event)
        NSCursor.pop()
        panel?.isMoving = false
        setCursor(at: NSEvent.mouseLocation)
    }

    // One tracking area (events when the pointer enters, leaves and moves: nothing is polled) for the hover and the cursor.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t); tracking = nil }
        let t = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true); setCursor(at: NSEvent.mouseLocation) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func mouseMoved(with event: NSEvent) { setCursor(at: NSEvent.mouseLocation) }

    /// The open hand where the window would be dragged from: where the hit view is a drag surface. Over a SwiftUI button
    /// or label (the hosting view takes those) the arrow; over anything else (the field, a scroll bar, a resize handle)
    /// whatever that view sets.
    private func setCursor(at screen: NSPoint) {
        guard let w = window, let content = w.contentView else { return }
        let inWindow = w.convertPoint(fromScreen: screen)
        let hit = content.hitTest((content.superview ?? content).convert(inWindow, from: nil))
        if hit is QCDragView { NSCursor.openHand.set() }
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
