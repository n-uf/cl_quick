// InstructionsBox: the Custom instructions box of Settings, and the two jump links above it. The box is ONE text view of a
// fixed height (about seven lines) that scrolls inside itself, so what is typed never changes the size of what holds it:
// the built-in instructions first (dimmed, a small lock before them, selectable but not editable), a hairline, then the
// user's own text, which is the only part that is edited, counted, capped at 1,000 characters (a paste too) and stored.
// It opens scrolled to the user's part. "Built in · Custom" scroll it to either part (about 200 ms, at once with Reduce
// Motion on) and the link of the part in view is lit as it scrolls. Links and search swaps the built-in part live.
//
// One NSTextView with the built-in part as a protected prefix, not a read-only view stacked above an editable one: one scroll
// view, one selection and one set of scroll bars for the whole box (selecting across the hairline and copying just work, the
// scroll follows the caret), and no two heights to keep in step. The rules for the protected part and for the parts are plain
// functions (QuickChatInstructions.edit, .caret, .part and .scrollTarget, Engine.swift, checked in Checks/run.sh); the text
// view only asks them: an edit that reaches into the prefix is refused or cut to the user's part, and a caret never goes in
// (a selection to copy does).

import AppKit
import SwiftUI

/// A request from a link to scroll the box to a part; a new `id` is a new request (the same link twice scrolls twice).
struct SJump: Equatable {
    let part: QuickChatInstructions.Part
    let id: Int
}

/// One of the two jump links: light text in the subtitle's size, the one in view full and underlined in orange (1.5 pt, a
/// little below the baseline), the other muted, brighter under the pointer. The hit area is padded to at least 44 × 22 pt.
struct SJumpLink: View {
    let title: String
    let active: Bool
    let action: () -> Void
    @Environment(\.face) private var face
    @State private var hover = false
    /// The least size of what can be clicked.
    static let hit = CGSize(width: 44, height: 22)

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 11.5)).lineLimit(1)
                .foregroundStyle(active ? face.text : hover ? face.soft : face.muted)
                .padding(.bottom, 3)
                .overlay(alignment: .bottom) { Rectangle().fill(FaceTheme.led).frame(height: 1.5).opacity(active ? 1 : 0) }
                .padding(.horizontal, 6)
                .frame(minWidth: Self.hit.width, minHeight: Self.hit.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }
}

/// "Built in · Custom": the box's two jump links.
struct SJumpLinks: View {
    let active: QuickChatInstructions.Part
    let jump: (QuickChatInstructions.Part) -> Void
    @Environment(\.face) private var face

    var body: some View {
        HStack(spacing: 0) {
            SJumpLink(title: "Built in", active: active == .builtIn) { jump(.builtIn) }
            Text("·").font(.system(size: 11.5)).foregroundStyle(face.muted).padding(.bottom, 3)
            SJumpLink(title: "Custom", active: active == .custom) { jump(.custom) }
        }
        .padding(.leading, -6)          // the first word's text lines up with the box's edge
    }
}

/// The box in its well, like SField's: the user's part in `text`, the built-in part from `builtIn`.
struct SInstructionsBox: View {
    let placeholder: String
    @Binding var text: String
    /// The fixed instructions in force (the web or the no-web one).
    let builtIn: String
    @Binding var active: QuickChatInstructions.Part
    var jump: SJump? = nil
    var limit: Int = QuickChatInstructions.limit
    var label = ""
    /// A picture draws the box scrolled to this part.
    var drawnAt: QuickChatInstructions.Part = .custom
    @Environment(\.face) private var face
    /// About seven lines.
    static let height: CGFloat = 108

    var body: some View {
        Group {
            if SField.drawing { drawn }
            else {
                SInstructionsTextView(text: $text, active: $active, jump: jump, builtIn: builtIn, placeholder: placeholder, limit: limit,
                                      label: label, ink: NSColor(face.text), dim: NSColor(face.muted))
                    .frame(height: Self.height)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(WellShape(well: face.win, radius: 4))
    }

    /// A picture can't draw an NSView: it prints the box as it looks scrolled to a part. Scrolled to Custom, the last line
    /// of the built-in text is above the hairline; scrolled to Built in, the whole of it, then the hairline.
    private var drawn: some View {
        let lock = Text(Image(systemName: "lock.fill")).font(.system(size: 8))
        return VStack(alignment: .leading, spacing: 0) {
            (lock + Text(" " + builtIn)).font(.system(size: 11.5)).foregroundStyle(face.muted).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: drawnAt == .custom ? 15 : nil, alignment: .bottomLeading).clipped()
            Rectangle().fill(face.muted.opacity(0.4)).frame(height: 1).padding(.vertical, 4)
            Text(text.isEmpty ? placeholder : text).font(.system(size: 13)).foregroundStyle(text.isEmpty ? face.muted : face.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 5)
        .frame(height: Self.height, alignment: .topLeading).clipped()
    }
}

/// The box's scroll view, which says when the user scrolls it (the wheel or a trackpad; the scroller's own dragging posts
/// its live-scroll notification, which the coordinator listens to as well).
final class SScrollView: NSScrollView {
    var onUserScroll: () -> Void = {}
    override func scrollWheel(with event: NSEvent) {
        onUserScroll()
        super.scrollWheel(with: event)
    }
}

/// The text view: plain text, no smart quotes or dashes, a protected prefix, a limit on the user's part, a hairline.
final class SProtectedTextView: NSTextView {
    /// How many characters at the start are the built-in part (the hairline's own line included).
    var protectedLength = 0
    /// Where the hairline's line is.
    var dividerLocation = 0
    var placeholder = NSAttributedString()
    var hairline = NSColor.gray

    /// What an edit is about to change, as AppKit asks for it before every typing, paste, drop and transformation
    /// (Make Upper Case and the like replace the selection with the whole of the changed text): each range is cut to start
    /// where the user's part does, and one that is only the built-in part is dropped, so no edit can reach it or carry it
    /// into the user's text. Nothing left: nil, and the edit doesn't happen.
    override var rangesForUserTextChange: [NSValue]? {
        guard let ranges = super.rangesForUserTextChange else { return nil }
        let kept = ranges.compactMap { v -> NSValue? in
            let r = v.rangeValue, end = NSMaxRange(r)
            guard end > protectedLength || (r.length == 0 && r.location >= protectedLength) else { return nil }
            let start = max(r.location, protectedLength)
            return NSValue(range: NSRange(location: start, length: end - start))
        }
        return kept.isEmpty ? nil : kept
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let lm = layoutManager, (string as NSString).length >= protectedLength, protectedLength > 0 else { return }
        let o = textContainerOrigin
        // the hairline, in the middle of its own short line
        let line = lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: dividerLocation), effectiveRange: nil)
        hairline.setFill()
        NSRect(x: o.x + line.minX + 5, y: o.y + line.midY - 0.5, width: line.width - 10, height: 1).fill()
        // the placeholder stands where the user's text will start (the empty line after the hairline's)
        guard (string as NSString).length == protectedLength else { return }
        let r = lm.extraLineFragmentRect
        guard !r.isEmpty else { return }
        placeholder.draw(at: NSPoint(x: o.x + r.minX + (textContainer?.lineFragmentPadding ?? 0), y: o.y + r.minY))
    }

    /// The box as a scroll view (what the settings window holds), with `delegate` for the rules above.
    static func make(delegate: NSTextViewDelegate, label: String) -> (SScrollView, SProtectedTextView) {
        let tv = SProtectedTextView(frame: NSRect(x: 0, y: 0, width: 300, height: SInstructionsBox.height))
        tv.delegate = delegate
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 5
        tv.textContainer?.containerSize = NSSize(width: 300, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.minSize = NSSize(width: 0, height: SInstructionsBox.height)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.autoresizingMask = [.width]
        tv.setAccessibilityLabel(label)
        let scroll = SScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: SInstructionsBox.height))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.postsFrameChangedNotifications = true
        scroll.contentView.postsBoundsChangedNotifications = true
        scroll.documentView = tv
        return (scroll, tv)
    }
}

/// What the box is made of, as attributed text.
enum SInstructionsText {
    /// The built-in part: a lock and the fixed text, then the hairline's own short line, the whole ending in a line break;
    /// `divider` is where the hairline's line starts.
    static func prefix(_ builtIn: String, dim: NSColor) -> (text: NSAttributedString, divider: Int) {
        let para = NSMutableParagraphStyle(); para.paragraphSpacing = 0
        let s = NSMutableAttributedString()
        let lock = NSTextAttachment()
        if let img = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Read-only")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [dim])) {
            lock.image = img
            lock.bounds = CGRect(x: 0, y: -1, width: 8, height: 10)
        }
        s.append(NSAttributedString(attachment: lock))
        s.append(NSAttributedString(string: " " + builtIn + "\n", attributes: [.font: NSFont.systemFont(ofSize: 11.5), .foregroundColor: dim, .paragraphStyle: para]))
        let divider = s.length
        s.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: 7), .foregroundColor: dim, .paragraphStyle: para]))
        return (s, divider)
    }

    static func user(_ ink: NSColor) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: ink, .paragraphStyle: NSParagraphStyle.default]
    }
}

struct SInstructionsTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var active: QuickChatInstructions.Part
    let jump: SJump?
    let builtIn: String
    let placeholder: String
    let limit: Int
    let label: String
    let ink: NSColor
    let dim: NSColor

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let (scroll, tv) = SProtectedTextView.make(delegate: context.coordinator, label: label)
        context.coordinator.attach(scroll, tv)
        context.coordinator.apply()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SInstructionsTextView
        private weak var scroll: NSScrollView?
        private weak var tv: SProtectedTextView?
        private var shown: String?              // the built-in text in the box now; nil before it is filled
        private var edited = false              // the user has typed: the box is no longer put back on Custom
        private var settled = false             // a jump has been asked for: nor is it after that
        private var lastJump = 0
        private var watch: [NSObjectProtocol] = []

        init(_ p: SInstructionsTextView) { parent = p }
        deinit { for w in watch { NotificationCenter.default.removeObserver(w) } }

        func attach(_ s: SScrollView, _ t: SProtectedTextView) {
            scroll = s; tv = t
            let nc = NotificationCenter.default
            // scrolled by the user, by any means (the wheel, a trackpad, the scroller): the box is never put back on Custom
            s.onUserScroll = { [weak self] in self?.settled = true }
            watch.append(nc.addObserver(forName: NSScrollView.willStartLiveScrollNotification, object: s, queue: .main) { [weak self] _ in
                self?.settled = true
            })
            watch.append(nc.addObserver(forName: NSView.frameDidChangeNotification, object: s, queue: .main) { [weak self] _ in
                self?.fitSpace(); self?.placeIfReady()
            })
            // scroll-spy: the link of the part in view follows the scrolling (also while a jump animates)
            watch.append(nc.addObserver(forName: NSView.boundsDidChangeNotification, object: s.contentView, queue: .main) { [weak self] _ in
                self?.spy()
            })
            // undo and redo change the text without a textDidChange: what the box holds is taken again
            for name in [Notification.Name.NSUndoManagerDidUndoChange, Notification.Name.NSUndoManagerDidRedoChange] {
                watch.append(nc.addObserver(forName: name, object: nil, queue: nil) { [weak self] n in
                    guard let self, let tv = self.tv, let um = tv.undoManager, (n.object as AnyObject?) === um else { return }
                    tv.setSelectedRange(QuickChatInstructions.caret(tv.selectedRange(), protected: tv.protectedLength))
                    self.takeFromView(tv)
                })
            }
        }

        /// Makes the box show the built-in text and the user's text as the view's inputs have them now: filled the first
        /// time; later the built-in part is swapped when it changed (Links and search) and the user's part replaced when it
        /// was changed from outside (cleared). What the box itself just wrote is the same string, so nothing happens. A new
        /// jump request scrolls to its part.
        func apply() {
            guard let tv, let st = tv.textStorage else { return }
            let (pre, div) = SInstructionsText.prefix(parent.builtIn, dim: parent.dim)
            let attrs = SInstructionsText.user(parent.ink)
            tv.insertionPointColor = parent.ink
            tv.hairline = parent.dim.withAlphaComponent(0.4)
            tv.placeholder = NSAttributedString(string: parent.placeholder, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: parent.dim])
            if shown == nil {
                let all = NSMutableAttributedString(attributedString: pre)
                all.append(NSAttributedString(string: QuickChatInstructions.clamp(parent.text), attributes: attrs))
                st.setAttributedString(all)
                tv.protectedLength = pre.length; tv.dividerLocation = div
                tv.setSelectedRange(NSRange(location: all.length, length: 0))
                tv.undoManager?.removeAllActions()
                shown = parent.builtIn
                fitSpace(); placeIfReady()
                DispatchQueue.main.async { [weak self] in self?.fitSpace(); self?.placeIfReady() }       // after SwiftUI has sized the box
            } else if shown != parent.builtIn {
                let old = tv.protectedLength, sel = tv.selectedRange()
                st.replaceCharacters(in: NSRange(location: 0, length: old), with: pre)
                tv.protectedLength = pre.length; tv.dividerLocation = div
                let moved = NSRange(location: sel.location >= old ? sel.location + pre.length - old : sel.location, length: sel.length)
                tv.setSelectedRange(QuickChatInstructions.caret(moved, protected: pre.length))
                tv.undoManager?.removeAllActions()       // what it could undo has moved
                shown = parent.builtIn
                fitSpace()
                spy()
            }
            let whole = tv.string as NSString, pl = tv.protectedLength
            if whole.substring(from: pl) != QuickChatInstructions.clamp(parent.text), !tv.hasMarkedText() {
                st.replaceCharacters(in: NSRange(location: pl, length: whole.length - pl),
                                     with: NSAttributedString(string: QuickChatInstructions.clamp(parent.text), attributes: attrs))
                tv.setSelectedRange(QuickChatInstructions.caret(tv.selectedRange(), protected: pl))
                tv.undoManager?.removeAllActions()       // an undo would act on text that is no longer there
            }
            if let j = parent.jump, j.id != lastJump { lastJump = j.id; scrollTo(j.part, animated: true) }
            tv.needsDisplay = true
        }

        // MARK: Scrolling

        /// Where the hairline is in the text view's own coordinates.
        private var dividerY: CGFloat {
            guard let tv, let lm = tv.layoutManager, let tc = tv.textContainer else { return 0 }
            lm.ensureLayout(for: tc)
            let r = lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: tv.dividerLocation), effectiveRange: nil)
            return r.minY + tv.textContainerOrigin.y
        }

        /// The text can always scroll until the hairline is at the top, however little the user has written, so Custom
        /// can be shown whole.
        func fitSpace() {
            guard let scroll, let tv, scroll.frame.width > 20 else { return }
            tv.minSize = NSSize(width: 0, height: max(SInstructionsBox.height, dividerY + scroll.contentView.bounds.height))
            tv.sizeToFit()
        }

        /// Opens scrolled to Custom, once the box has a width to lay out in (asked again when it gets its width, until
        /// something is typed or a link is used).
        private func placeIfReady() {
            guard !edited, !settled, let scroll, scroll.frame.width > 20 else { return }
            move(to: .custom, animated: false)
        }

        /// Scrolls to a part: about 200 ms, at once with Reduce Motion on (or when not animated).
        func scrollTo(_ part: QuickChatInstructions.Part, animated: Bool) {
            settled = true
            move(to: part, animated: animated)
        }

        private func move(to part: QuickChatInstructions.Part, animated: Bool) {
            guard let scroll, let tv else { return }
            let clip = scroll.contentView
            let most = tv.frame.height - clip.bounds.height
            let y = QuickChatInstructions.scrollTarget(part, divider: dividerY, most: most)
            let point = NSPoint(x: 0, y: y)
            if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.2
                    ctx.allowsImplicitAnimation = true
                    clip.animator().setBoundsOrigin(point)
                }
            } else {
                clip.setBoundsOrigin(point)
            }
            scroll.reflectScrolledClipView(clip)
        }

        /// The part in view now.
        var partInView: QuickChatInstructions.Part {
            guard let scroll else { return .custom }
            return QuickChatInstructions.part(offset: scroll.contentView.bounds.origin.y, viewport: scroll.contentView.bounds.height, divider: dividerY)
        }

        private func spy() {
            let p = partInView
            if parent.active != p { DispatchQueue.main.async { [weak self] in self?.parent.active = p } }
        }

        // MARK: The rules

        /// The built-in part can't be edited, and the user's part stops at the limit (a paste that doesn't fit gives what does).
        func textView(_ tv: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            guard let new = replacementString, !tv.hasMarkedText(), let box = tv as? SProtectedTextView else { return true }
            switch QuickChatInstructions.edit(new, replacing: range, in: tv.string, protected: box.protectedLength, limit: parent.limit) {
            case .allow: return true
            case .reject: return false
            case .replace(let r, let text): tv.insertText(text, replacementRange: r); return false
            }
        }

        /// A caret never goes into the built-in part; a selection over it (to copy) is fine.
        func textView(_ tv: NSTextView, willChangeSelectionFromCharacterRange old: NSRange, toCharacterRange new: NSRange) -> NSRange {
            QuickChatInstructions.caret(new, protected: (tv as? SProtectedTextView)?.protectedLength ?? 0)
        }

        func textDidChange(_ note: Notification) {
            guard let tv = note.object as? SProtectedTextView else { return }
            takeFromView(tv)
        }

        /// What the box holds as the user's text goes to the page (and is stored): after typing, a paste, a transformation,
        /// undo and redo alike. Typed text takes the user's look, and one over the limit (composed text) is cut.
        func takeFromView(_ tv: SProtectedTextView) {
            guard let st = tv.textStorage else { return }
            let pl = tv.protectedLength, whole = tv.string as NSString
            guard whole.length >= pl else { return }
            edited = true
            var user = whole.substring(from: pl)
            // composed text (an input method) is only checked once it is set; then anything over is cut
            if !tv.hasMarkedText(), user.count > parent.limit { user = QuickChatInstructions.clamp(user) }
            st.setAttributes(SInstructionsText.user(parent.ink), range: NSRange(location: pl, length: whole.length - pl))
            if user != whole.substring(from: pl) {
                st.replaceCharacters(in: NSRange(location: pl, length: whole.length - pl), with: NSAttributedString(string: user, attributes: SInstructionsText.user(parent.ink)))
                tv.undoManager?.removeAllActions()       // an undo would act on text that is no longer there
            }
            if parent.text != user { parent.text = user }
            tv.needsDisplay = true
        }
    }
}
