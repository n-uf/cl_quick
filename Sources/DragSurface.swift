// QCDragSurface: what lets the quick chat's panel be dragged by its empty areas. SwiftUI's views inside an NSHostingView
// catch the mouse, so the panel's own "movable by background" only worked in a few spots. A transparent view behind the
// content takes the mouse where nothing in front of it does (the padding, the gaps of the picker row, the space around
// and between answers) and hands the drag to the window. The field, the pickers, the buttons and the selectable text sit
// in front and keep their clicks; scrolling goes up the responder chain to the scroll view, as it does for any view.

import AppKit
import SwiftUI

struct QCDragSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { QCDragView() }
    func updateNSView(_ view: NSView, context: Context) {}
}

final class QCDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

private struct QCDraggable: ViewModifier {
    @Environment(\.qcRendering) private var rendering

    func body(content: Content) -> some View {
        // a picture (`--render-quick-chat`) can't draw an AppKit view, and has no mouse
        if rendering { content } else { content.background(QCDragSurface()) }
    }
}

extension View {
    /// The panel can be dragged from this view's empty areas.
    func qcDraggable() -> some View { modifier(QCDraggable()) }
}
