// ChatQuick: quick actions on a selection. Select text in an answer and a small bar appears just above it (below it when there is
// no room above) with Explain, Shorter and Ask about this; the same three are added, after a separator, to the answer
// text's own right-click menu (SwiftUI's selectable Text shows only its own menu, so a .contextMenu never appears there: the menu
// is taken from the text view under the pointer and shown with the group added; `chatItems` is room for a further group).
//   - Explain and Shorter send a follow-up at once: the selection as a Markdown blockquote, a blank line, then "Explain this." or
//     "Say this more briefly." The draft in the field and any attachments are left alone (they are not part of it).
//   - Ask about this puts the blockquote into the field (after what is there), the caret after it, for you to finish.
// The bar is a small window of its own over the panel (QCFloat: it never takes the keyboard, so the selection stays), made when the
// mouse button comes up or a key changes the selection. It goes when the selection is cleared, on a scroll, a click, a key that
// ends the selection, Esc, a resize, the panel losing the keyboard or the chat changing. It is never shown (and the menu items are
// dimmed) while an answer is streaming (the text under the selection is still growing, and a follow-up can't be sent), after the
// chat ended, with a full limit or without a profile; it never appears for the user's own messages, the thinking text or a field:
// only a selection that lies in an answer counts. The selection is read from the text views SwiftUI draws (QCTextLines).
// Nothing is kept: the quoted text lives in memory until it is sent or the selection goes.

import AppKit
import Carbon.HIToolbox
import SwiftUI

enum QCQuickAction { case explain, shorter, ask }

/// What goes into the chat for a selection.
enum QCQuickText {
    static let explain = "Explain this."
    static let shorter = "Say this more briefly."

    /// The selection as a Markdown blockquote (a blank line stays a bare ">").
    static func quote(_ selection: String) -> String {
        selection.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces).isEmpty ? ">" : "> " + $0 }
            .joined(separator: "\n")
    }

    /// The follow-up an action sends at once (nil for Ask about this, which only fills the field).
    static func message(_ action: QCQuickAction, _ selection: String) -> String? {
        switch action {
        case .explain: return quote(selection) + "\n\n" + explain
        case .shorter: return quote(selection) + "\n\n" + shorter
        case .ask: return nil
        }
    }

    /// The field after Ask about this: what was there, a blank line, the quote, a blank line for the caret to stand on.
    static func draft(_ selection: String, after field: String) -> String {
        let q = quote(selection) + "\n\n"
        if field.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return q }
        let gap = field.hasSuffix("\n\n") ? "" : field.hasSuffix("\n") ? "\n" : "\n\n"
        return field + gap + q
    }
}

/// The selection's state and its bar. Main thread only.
final class QCQuick: ObservableObject {
    /// The bar's own window (QCFloat makes it the first time).
    static let float = QCFloat()
    /// There is a selection in an answer that the actions can work on (the right-click items are dimmed without one).
    @Published private(set) var available = false
    /// The bar is on screen.
    private(set) var shown = false
    /// The selected text as last read.
    private(set) var text = ""
    weak var model: QuickChatModel?
    private weak var panel: QuickChatPanel?
    private var monitors: [Any] = []
    /// Where the pointer pressed (window coordinates), and the end of the drag the selection came from (nil: by keys).
    private var down: NSPoint?
    private var hint: NSPoint?
    /// Esc closed the bar for this selection: it stays closed until the selection changes.
    private var dismissed: String?

    /// Looks at the panel's mouse and keys (the local monitors never take an event) and its size.
    func attach(_ p: QuickChatPanel) {
        panel = p
        model?.scroll.moved = { [weak self] in self?.hideBar() }
        guard monitors.isEmpty else { return }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .keyDown, .scrollWheel], handler: { [weak self] e in
            self?.seen(e) == true ? nil : e          // (only a right-click that opened the answers' menu is taken)
        }) { monitors.append(m) }
        monitors.append(NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: p, queue: .main) { [weak self] _ in
            self?.hideBar()
        })
    }

    // MARK: What happens

    /// True when the event was taken (a right-click in an answer, which opened the answers' menu).
    @discardableResult
    func seen(_ e: NSEvent) -> Bool {
        guard let panel, e.window === panel else { return false }
        switch e.type {
        case .rightMouseDown:
            return showMenu(e)
        case .leftMouseDown:
            if e.modifierFlags.contains(.control), showMenu(e) { return true }          // a ⌃-click is a right-click
            down = e.locationInWindow; hint = nil; dismissed = nil
            hideBar()
            if available { available = false }          // the press changes the selection: the mouse-up reads it anew
        case .leftMouseUp:
            hint = Self.start(down: down, up: e.locationInWindow)
            readSoon()
        case .keyDown:
            guard Int(e.keyCode) != kVK_Escape else { return false }       // (Esc: QuickChat.closeTopLayer)
            hint = nil
            readSoon()
        case .scrollWheel:
            hideBar()
        default:
            break
        }
        return false
    }

    // MARK: The right-click menu

    /// More menu items for the answers' menu, as their own group after ours (the other builder's "Copy chat as Markdown ⌥⇧⌘C"):
    /// asked each time the menu opens; none, no group.
    var chatItems: () -> [NSMenuItem] = { [] }

    /// A right-click on an answer's text: the text's own menu (Copy, Look Up, Services: SwiftUI's selectable Text draws it, and a
    /// SwiftUI .contextMenu never shows over it) gets our group added, then it is shown the way AppKit would. Anywhere else, or
    /// when the text has no menu, the click goes on as ever.
    private func showMenu(_ e: NSEvent) -> Bool {
        guard let v = answerText(at: e.locationInWindow), let base = v.menu(for: e) else { return false }
        // a copy, so a menu the text view keeps never collects our group twice
        let menu = (base.copy() as? NSMenu) ?? base
        let sel = selection()
        if let sel { text = sel.text; if !available { available = true } }
        let on = sel != nil
        menu.addItem(.separator())
        menu.addItem(QCMenuAction.item("Explain", enabled: on) { [weak self] in self?.run(.explain) })
        menu.addItem(QCMenuAction.item("Shorter", enabled: on) { [weak self] in self?.run(.shorter) })
        menu.addItem(QCMenuAction.item("Ask about this", enabled: on) { [weak self] in self?.run(.ask) })
        let more = chatItems()
        if !more.isEmpty { menu.addItem(.separator()); more.forEach { menu.addItem($0) } }
        hideBar()
        NSMenu.popUpContextMenu(menu, with: e, for: v)
        return true
    }

    /// The answer's text view that really is under a point of the window (window coordinates): the point is in the answers' visible
    /// area (not in the header, the field, or under the find bar), the content view's own hit test lands on the text view (or in it),
    /// so a field or a bar drawn over scrolled-away text never gets the answers' menu, and the text is in an answer.
    private func answerText(at p: NSPoint) -> NSView? {
        guard let panel, let cv = panel.contentView, let model, model.isWindow, let vis = model.scroll.visibleRectInWindow(),
              vis.contains(p) else { return nil }
        if model.find.isOpen, p.y > vis.maxY - (QCFindBar.height + 12) { return nil }       // (window coordinates: the top is the larger y)
        guard let hit = cv.hitTest(cv.superview?.convert(p, from: nil) ?? p) else { return nil }
        guard let v = QCTextLines.all(under: cv).first(where: { hit === $0 || hit.isDescendant(of: $0) }),
              model.scroll.answerContains(v.convert(v.bounds, to: nil)) else { return nil }
        return v
    }

    /// After the event has been handled (the selection is made by then), and once more a moment later for a double or triple
    /// click, whose selection settles after its last press.
    private func readSoon() {
        DispatchQueue.main.async { [weak self] in self?.refresh() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.refresh() }
    }

    /// Where a drag's selection starts, as far as the pointer says: the upper one of the two ends (the left one on a line).
    static func start(down: NSPoint?, up: NSPoint) -> NSPoint {
        guard let d = down else { return up }
        if abs(d.y - up.y) < 2 { return d.x <= up.x ? d : up }
        return d.y > up.y ? d : up            // window coordinates: higher on the screen is larger
    }

    /// The chat changed (a message went, an answer streams): the selection is no longer what the bar was for.
    func turnsChanged() {
        hideBar()
        if available { available = false }
    }

    func hideBar() {
        guard shown else { return }
        shown = false
        Self.float.hide()
    }

    /// Esc: the bar closes (true) while it is shown; the selection itself stays.
    @discardableResult func dismiss() -> Bool {
        guard shown else { return false }
        dismissed = text
        hideBar()
        return true
    }

    private func clear() {
        if available { available = false }
        hideBar()
    }

    // MARK: Reading the selection

    /// The selection in an answer, if the actions may work on it now.
    private func selection() -> (view: NSView, range: NSRange, text: String)? {
        guard let panel, let model, panel.isVisible, panel.isKeyWindow, model.isWindow, !model.busy, !model.blocked,
              model.ended == nil, model.target != nil else { return nil }
        if panel.firstResponder is NSText { return nil }                  // the keyboard is in a field
        var view = (panel.firstResponder as? NSView).flatMap { QCTextLines.isInteraction($0) ? $0 : nil }
        if view == nil, let content = panel.contentView {
            view = QCTextLines.all(under: content).first { $0.accessibilitySelectedTextRange().length > 0 }
        }
        guard let v = view else { return nil }
        let r = v.accessibilitySelectedTextRange()
        guard r.length > 0, let raw = v.accessibilitySelectedText() else { return nil }
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, model.scroll.answerContains(v.convert(v.bounds, to: nil)) else { return nil }
        return (v, r, s)
    }

    func refresh() {
        guard let sel = selection() else { return clear() }
        if dismissed != nil, dismissed != sel.text { dismissed = nil }
        text = sel.text
        if !available { available = true }
        if dismissed == sel.text { return }
        place(sel.view, sel.range)
    }

    // MARK: The bar

    private func place(_ v: NSView, _ r: NSRange) {
        guard let panel, let cv = panel.contentView, let vis = model?.scroll.visibleRectInWindow() else { return hideBar() }
        let n = v.accessibilityNumberOfCharacters()
        guard n > 0 else { return hideBar() }
        let lines = max(1, v.accessibilityLine(for: n - 1) + 1)
        let first = v.accessibilityLine(for: min(max(0, r.location), n - 1))
        let last = v.accessibilityLine(for: min(max(0, r.location + r.length - 1), n - 1))
        // the hosting view's own space (from its top left), as QCFloat wants frames
        func topLeft(_ w: NSRect) -> NSRect {
            let c = cv.convert(w, from: nil)
            return NSRect(x: c.minX, y: cv.isFlipped ? c.minY : cv.bounds.height - c.maxY, width: c.width, height: c.height)
        }
        let box = topLeft(v.convert(v.bounds, to: nil)), area = topLeft(vis)
        let lh = box.height / CGFloat(lines)
        let top = box.minY + CGFloat(first) * lh, bottom = box.minY + CGFloat(last + 1) * lh
        // the selection's lines must overlap what the answers show: scrolled away (⇧fn, ⌘J), the bar is not drawn over the field
        guard bottom > area.minY, top < area.maxY else { return hideBar() }
        var x = box.midX
        if let h = hint { x = cv.convert(h, from: nil).x }
        x = min(max(x, box.minX + 12), max(box.minX + 12, box.maxX - 12))
        let bar = QCQuickBar.height, gap: CGFloat = 6
        let frame: CGRect
        if top - bar - gap >= area.minY - 10 {
            frame = CGRect(x: x - 0.5, y: top, width: 1, height: lh)                       // above the selection's first line
        } else if max(bottom, area.minY) + gap + bar <= area.maxY {
            frame = CGRect(x: x - 0.5, y: max(bottom, area.minY) + gap + bar, width: 1, height: 1)   // no room above: below its last line
        } else {
            return hideBar()
        }
        if Self.float.show(AnyView(QCQuickBar(quick: self)), above: frame, align: .center, interactive: true) { shown = true }
    }

    // MARK: Acting

    /// An action, on the selection as it is now (the menu's items) or as it was last read (the bar's: a click on it leaves the
    /// selection as it was).
    func run(_ a: QCQuickAction) {
        let s = selection()?.text ?? text
        guard let model, available, !s.isEmpty else { return }
        hideBar()
        available = false
        switch a {
        case .explain, .shorter:
            if let q = QCQuickText.message(a, s) { model.followUp(q) }
        case .ask:
            model.quoteIntoField(s)
        }
    }
}

/// The bar: three words, side by side, in one small outline.
struct QCQuickBar: View {
    @ObservedObject var quick: QCQuick
    static let height: CGFloat = 28

    var body: some View {
        HStack(spacing: 0) {
            QCQuickPart(title: "Explain", help: "Explain this selection") { quick.run(.explain) }
            Rectangle().fill(QCColor.line).frame(width: 1, height: 14)
            QCQuickPart(title: "Shorter", help: "Say this more briefly") { quick.run(.shorter) }
            Rectangle().fill(QCColor.line).frame(width: 1, height: 14)
            QCQuickPart(title: "Ask about this", help: "Quote this in the field and ask") { quick.run(.ask) }
        }
        .frame(height: Self.height)
        .fixedSize()
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(QCColor.hex(0x2B2B29)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(QCColor.line))
        .environment(\.colorScheme, .dark)
    }
}

private struct QCQuickPart: View {
    let title: String
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12.5, weight: .medium)).foregroundColor(hover ? QCColor.text : QCColor.soft).lineLimit(1)
                .padding(.horizontal, 10).frame(height: QCQuickBar.height)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hover ? QCColor.hover : .clear).padding(2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .qcPointingHand()
        .help(help)
        .onHover { hover = $0 }
    }
}

/// A menu item's action, held by the item.
final class QCMenuAction: NSObject, NSMenuItemValidation {
    let run: () -> Void
    let enabled: Bool
    init(_ run: @escaping () -> Void, enabled: Bool = true) { self.run = run; self.enabled = enabled }
    @objc func fire() { run() }
    /// (menus enable their items by validation: `isEnabled` alone is overruled)
    func validateMenuItem(_ item: NSMenuItem) -> Bool { enabled }

    static func item(_ title: String, enabled: Bool = true, _ run: @escaping () -> Void) -> NSMenuItem {
        let a = QCMenuAction(run, enabled: enabled)
        let i = NSMenuItem(title: title, action: #selector(fire), keyEquivalent: "")
        i.target = a
        i.representedObject = a          // the item keeps its action alive
        i.isEnabled = enabled
        return i
    }
}
