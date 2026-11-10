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
    var onHover: ((Bool) -> Void)? {
        didSet { if (onHover == nil) != (oldValue == nil) { updateTrackingAreas() } }
    }
    private var tracking: NSTrackingArea?

    override var mouseDownCanMoveWindow: Bool { true }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t); tracking = nil }
        guard onHover != nil else { return }
        let t = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

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
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.cursorUpdate, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func mouseEntered(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }
}
