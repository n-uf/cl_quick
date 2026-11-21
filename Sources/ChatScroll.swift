// ChatScroll: how the chat window scrolls, in one place.
//
// The chat is a SwiftUI ScrollView, which on the Mac is an NSScrollView; this finds that view (QCScrollProbe) and watches
// it, so the scroll position is known whoever moves it: the wheel, the trackpad, the scroller, the keys, a drag selecting
// text, or this code. The rules:
//   - FOLLOWING: while the view is at the bottom (within a few points) when text arrives, it goes on following the end.
//     The only thing that changes it is the view's own position, as the user moves it: scrolling up (by any means) stops
//     following; coming back to the bottom (by hand, or the jump-to-latest button) resumes it. New text while not
//     following never moves the view (the document just grows below).
//   - No timers and no animation: nothing moves the view by itself, and nothing here fights a scroll. It reacts to the
//     position it is told about, and every move it makes is a jump, final when the call returns.
//   - Sending a message (QuickChatModel.followTick) jumps to the bottom and follows.
//   - The jump-to-latest button jumps to the bottom.
//   - ▲ ▼ scroll to the previous or the next message of the user's own, found from where the view is (never from a stored
//     index, so scrolling by hand and the buttons agree); the message lands near the view's top and its bubble flashes.
//     They stop following, like any scroll up (unless the move ends at the bottom).
//
// Positions are measured as an OFFSET from the document's top (0 = the top, `maxOffset` = the bottom), so the code reads
// the same whichever way the document is flipped. Anchors (QCAnchor) are empty views behind a message, which say where it
// is; they are looked at when the view moves or the document changes, never drawn.

import AppKit
import SwiftUI

/// The keys that move in the chat (the panel's performKeyEquivalent, exact modifiers): ⌘J the latest, ⇧⌘J the start of the answer
/// in view, ⌘[ ⌘] the previous and next message of the user's, Page Up, Page Down and End.
enum QCNav: Equatable { case latest, answerStart, previousPrompt, nextPrompt, pageUp, pageDown, end }

final class QCChatScroll: ObservableObject {
    /// "At the bottom" is within this many points of it.
    static let slack: CGFloat = 4
    /// A message scrolled to sits this far under the view's top, so its bubble and the flash show whole.
    static let inset: CGFloat = 8
    /// A message scrolled to is lit for this long, then plain again (no fade).
    static let flashFor: TimeInterval = 1

    // MARK: What the views read (published only when they change)

    /// The view is at the bottom (the jump-to-latest button hides).
    @Published private(set) var atBottom = true
    /// Text arrived below while the view was not at the bottom (a dot on the jump-to-latest button).
    @Published private(set) var newBelow = false
    /// ▲ and ▼ have a message of the user's to go to from where the view is.
    @Published private(set) var canPrevious = false
    @Published private(set) var canNext = false
    /// The message just scrolled to (its bubble flashes), for about a second.
    @Published private(set) var flash: UUID?
    /// The answers whose top edge (first line) is above the visible area: their "go to the start" shows.
    @Published private(set) var answersAbove: Set<UUID> = []
    /// The answer at the view's bottom edge whose footer is out of sight (taller than the view, its first line above the
    /// view's bottom, its end below it): the left handle's answer, whose ⤒ and copy float. Nil: no left handle.
    @Published private(set) var pair: UUID?

    /// The two edge handles' states: left (this answer), right (navigation).
    let left = QCEdgeState()
    let right = QCEdgeState()
    /// The window-global frames the handles report, by name ("left.strip", "right.box", …), for the checks.
    var frames: [String: CGRect] = [:]

    func forget(_ name: String) { frames["\(name).strip"] = nil; frames["\(name).box"] = nil }

    /// Whether new text moves the view to the end. True at the start.
    private(set) var following = true

    private(set) weak var scrollView: NSScrollView?
    private weak var clip: NSClipView?
    private weak var doc: NSView?
    private var flipped = true
    private var lastOffset: CGFloat = 0
    private var lastHeight: CGFloat = 0
    private var lastClipHeight: CGFloat = 0
    /// The text's height as the last move of the view saw it (a smaller one now: the text shrank under the view).
    private var clipSawHeight: CGFloat = 0
    /// Set while this code moves the view (its own moves are not the user's).
    private var moving = false
    private var refreshPending = false
    private var observers: [NSObjectProtocol] = []

    private struct Weak { weak var view: NSView? }
    private var questions: [UUID: Weak] = [:]
    private var answers: [UUID: Weak] = [:]
    /// Behind each finished answer's footer row (the answer's id): where the footer ends.
    private var footers: [UUID: Weak] = [:]

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    // MARK: Finding the scroll view

    /// Called by the probe once the chat's NSScrollView is in a window.
    func attach(_ view: NSScrollView) {
        guard scrollView !== view, let doc = view.documentView else { return }
        let clip = view.contentView
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        scrollView = view; self.clip = clip; self.doc = doc
        flipped = doc.isFlipped
        clip.postsBoundsChangedNotifications = true
        clip.postsFrameChangedNotifications = true
        doc.postsFrameChangedNotifications = true
        let nc = NotificationCenter.default
        observers = [
            nc.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in self?.clipMoved() },
            nc.addObserver(forName: NSView.frameDidChangeNotification, object: clip, queue: .main) { [weak self] _ in self?.viewportResized() },
            nc.addObserver(forName: NSView.frameDidChangeNotification, object: doc, queue: .main) { [weak self] _ in self?.documentResized() },
        ]
        lastOffset = offset(); lastHeight = doc.bounds.height; lastClipHeight = clip.bounds.height; clipSawHeight = doc.bounds.height
        if following { stick() }
        refresh()
    }

    // MARK: Where the view is

    private var geometry: (clip: NSClipView, doc: NSView)? {
        guard let clip, let doc, scrollView != nil else { return nil }
        return (clip, doc)
    }

    /// How far the view is scrolled from the top.
    func offset() -> CGFloat {
        guard let g = geometry else { return 0 }
        return flipped ? g.clip.bounds.minY - g.doc.bounds.minY : g.doc.bounds.maxY - g.clip.bounds.maxY
    }

    /// The most it can be scrolled.
    func maxOffset() -> CGFloat {
        guard let g = geometry else { return 0 }
        return max(0, g.doc.bounds.height - g.clip.bounds.height)
    }

    /// Points of document below the visible area.
    var distanceBelow: CGFloat { maxOffset() - offset() }
    var isAtBottom: Bool { distanceBelow <= Self.slack }

    private func clamped(_ o: CGFloat) -> CGFloat { min(max(0, o), maxOffset()) }

    /// Moves the view to an offset at once, without telling `following`.
    private func place(_ o: CGFloat) {
        guard let g = geometry else { return }
        let o = clamped(o)
        let y = flipped ? g.doc.bounds.minY + o : g.doc.bounds.maxY - g.clip.bounds.height - o
        moving = true
        g.clip.scroll(to: NSPoint(x: g.clip.bounds.minX, y: y))
        scrollView?.reflectScrolledClipView(g.clip)
        moving = false
        lastOffset = offset()
    }

    private func stick() { place(maxOffset()) }

    // MARK: What happens when something moves

    /// The view's position changed: the wheel, the trackpad, the scroller, a key, a selection's drag, or ours. Whoever it
    /// was, the position says whether to follow; ours leave `following` as they were asked to.
    ///
    /// Any move UP stops following, however small (a trackpad's first 1 to 3 points are still a scroll up: the next text must
    /// not pull the view back); only a move DOWN that ends within the slack of the bottom resumes it. Two things move the
    /// position that are not the user's, and leave `following` alone: the viewport changing height (a resize: the view's
    /// top is held, or the bottom pulled up) and the text shrinking under a view at the bottom (AppKit cuts the position).
    private func clipMoved() {
        guard let g = geometry else { return }
        let o = offset()
        let resized = g.clip.bounds.height != lastClipHeight
        let shrank = g.doc.bounds.height < clipSawHeight && isAtBottom
        lastClipHeight = g.clip.bounds.height
        clipSawHeight = g.doc.bounds.height
        if !moving, !resized, !shrank, abs(o - lastOffset) > 0.01 {
            if o < lastOffset { following = false } else if isAtBottom { following = true }
        }
        lastOffset = o
        scheduleRefresh()
    }

    /// The window was resized under it: when following, the end stays in view.
    private func viewportResized() {
        if following { stick() }
        scheduleRefresh()
    }

    /// The text grew or shrank. Following: the end stays in view. Else the view stays where it is, and text that arrived
    /// below is noted.
    private func documentResized() {
        guard let g = geometry else { return }
        let h = g.doc.bounds.height
        if following { stick() }
        else if h > lastHeight, !isAtBottom { newBelow = true }
        lastHeight = h
        scheduleRefresh()
    }

    /// The chat's text changed (QuickChatModel.scrollTick): keeps the end in view when following, once the layout has run.
    func contentChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.following { self.stick() }
            self.refresh()
        }
    }

    private func scheduleRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.async { [weak self] in
            self?.refreshPending = false
            self?.refresh()
        }
    }

    /// Works out what the views show, and publishes what changed.
    func refresh() {
        guard geometry != nil else { return }
        let at = isAtBottom
        if atBottom != at { atBottom = at }
        if at, newBelow { newBelow = false }
        let p = previousTarget() != nil, n = nextTarget() != nil
        if canPrevious != p { canPrevious = p }
        if canNext != n { canNext = n }
        let o = offset()
        let above = Set(answers.compactMap { id, w -> UUID? in
            guard let v = attached(w.view), top(of: v) < o - 0.5 else { return nil }
            return id
        })
        if answersAbove != above { answersAbove = above }
        let belongs = pairedAnswer()
        if pair != belongs { pair = belongs }
    }

    /// The answer the left handle belongs to: the one that has begun above the view's bottom edge while its footer is out of
    /// view, whatever its height (the handle is there to reach ⤒ and copy when the footer is not). The footer counts: an
    /// answer that is itself in view but whose footer is below the edge has the handle too. A streaming answer has no footer,
    /// so its end counts: while following at the bottom its end is in view, and there is none.
    func pairedAnswer() -> UUID? {
        guard let g = geometry else { return nil }
        let bottom = offset() + g.clip.bounds.height
        for (id, w) in answers {
            guard let v = attached(w.view) else { continue }
            let t = top(of: v)
            let end = attached(footers[id]?.view).map { top(of: $0) + $0.frame.height } ?? t + v.frame.height
            if t < bottom, end > bottom + 0.5 { return id }
        }
        return nil
    }

    // MARK: Anchors

    enum AnchorKind { case question, answer, footer }

    func register(_ kind: AnchorKind, _ id: UUID, _ view: NSView) {
        switch kind {
        case .question: questions[id] = Weak(view: view)
        case .answer: answers[id] = Weak(view: view)
        case .footer: footers[id] = Weak(view: view)
        }
        scheduleRefresh()
    }

    func unregister(_ kind: AnchorKind, _ id: UUID, _ view: NSView) {
        switch kind {
        case .question: if questions[id]?.view === view { questions[id] = nil }
        case .answer: if answers[id]?.view === view { answers[id] = nil }
        case .footer: if footers[id]?.view === view { footers[id] = nil }
        }
        scheduleRefresh()
    }

    /// Where an answer's footer row ends, as an offset from the document's top (a check reads it); nil while it has none.
    func bottom(ofFooter id: UUID) -> CGFloat? { attached(footers[id]?.view).map { top(of: $0) + $0.frame.height } }

    private func attached(_ v: NSView?) -> NSView? {
        guard let v, let doc, v.window != nil, v.isDescendant(of: doc) else { return nil }
        return v
    }

    /// How far a view's top edge is below the document's top.
    private func top(of v: NSView) -> CGFloat {
        guard let doc else { return 0 }
        let r = v.convert(v.bounds, to: doc)
        return flipped ? r.minY - doc.bounds.minY : doc.bounds.maxY - r.maxY
    }

    /// The top of a message of the user's, as an offset from the document's top (a check reads it).
    func top(ofQuestion id: UUID) -> CGFloat? { attached(questions[id]?.view).map(top(of:)) }
    /// The top of an answer's first line, the same way.
    func top(ofAnswer id: UUID) -> CGFloat? { attached(answers[id]?.view).map(top(of:)) }

    // MARK: Messages of the user's

    /// Where each message would put the view (near its top, cut to what can be scrolled to), in the order they stand.
    private func promptOffsets() -> [(id: UUID, top: CGFloat, offset: CGFloat)] {
        questions.compactMap { id, w in
            guard let v = attached(w.view) else { return nil }
            let t = top(of: v)
            return (id, t, clamped(t - Self.inset))
        }.sorted { $0.top < $1.top }
    }

    /// The nearest message above where the view is, by where it would put the view: nil when going to it would not move
    /// the view (at the first message; the first message already at the top).
    func previousTarget() -> (id: UUID, offset: CGFloat)? {
        let o = offset()
        return promptOffsets().last { $0.offset < o - 1 }.map { ($0.id, $0.offset) }
    }

    /// The nearest one below (nil at the last, or when the end of the chat is as far as the view goes).
    func nextTarget() -> (id: UUID, offset: CGFloat)? {
        let o = offset()
        return promptOffsets().first { $0.offset > o + 1 }.map { ($0.id, $0.offset) }
    }

    /// ▲: the message of the user's before where the view is. Stops following (unless it ends at the bottom).
    func previousPrompt() {
        guard let t = previousTarget() else { return }
        go(to: t.offset, follow: false, flashing: t.id)
    }

    /// ▼: the next one.
    func nextPrompt() {
        guard let t = nextTarget() else { return }
        go(to: t.offset, follow: false, flashing: t.id)
    }

    /// An answer's "go to the start": its first line near the view's top. Stops following, like any scroll up.
    func goToStart(ofAnswer id: UUID) {
        guard let v = attached(answers[id]?.view) else { return }
        go(to: top(of: v) - Self.inset, follow: false)
    }

    /// The answer at the view's bottom edge: the last one whose first line is above that edge (so, with the view at the bottom,
    /// the last answer). The left handle's, ⇧⌘J's and ⇧⌘C's.
    func answerAtBottomEdge() -> UUID? {
        guard let g = geometry else { return nil }
        let bottom = offset() + g.clip.bounds.height
        return answers.compactMap { id, w -> (UUID, CGFloat)? in
            guard let v = attached(w.view) else { return nil }
            let t = top(of: v)
            return t < bottom ? (id, t) : nil
        }.max { $0.1 < $1.1 }?.0
    }

    /// A key that moves in the chat. False when there is nothing to move (no scroll view yet): the key is not taken.
    func perform(_ nav: QCNav, turns: Int) -> Bool {
        guard geometry != nil else { return false }
        switch nav {
        case .latest, .end: jumpToLatest()
        case .answerStart: if let id = answerAtBottomEdge() { goToStart(ofAnswer: id) }
        case .previousPrompt: previousPrompt()
        case .nextPrompt: nextPrompt()
        case .pageUp: go(to: offset() - page(), follow: false)
        case .pageDown: go(to: offset() + page(), follow: false)
        }
        return true
    }

    /// A page: the visible height less a few lines, as the system's page keys keep some of what was in view.
    private func page() -> CGFloat { max(40, (clip?.bounds.height ?? 0) - 40) }

    /// ▲ and ▼ show once there are two messages of the user's to go between.
    static func showsPrompts(turns: Int) -> Bool { turns >= 2 }

    private func clearFlash(_ id: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.flashFor) { [weak self] in
            if self?.flash == id { self?.flash = nil }
        }
    }

    // MARK: Jumping to the latest

    /// The jump-to-latest button, and a message sent: the bottom, and following again.
    func jumpToLatest() { go(to: maxOffset(), follow: true) }

    // MARK: Moving

    /// Every move is a jump: the view is at its target, and everything the views show is final, when this returns.
    private func go(to target: CGFloat, follow: Bool, flashing: UUID? = nil) {
        guard geometry != nil else { return }
        if let flashing { flash = flashing; clearFlash(flashing) }
        place(target)
        // following again if it ended at the bottom
        following = follow || isAtBottom
        refresh()
    }

    // MARK: For pictures (a render can't draw a scroll view)

    func showForPicture(atBottom: Bool, newBelow: Bool, canPrevious: Bool = true, canNext: Bool = true, flash: UUID? = nil,
                        answersAbove: Set<UUID> = [], pair: UUID? = nil) {
        self.atBottom = atBottom; self.newBelow = newBelow
        self.canPrevious = canPrevious; self.canNext = canNext; self.flash = flash
        self.answersAbove = answersAbove; self.pair = pair
    }
}

// MARK: - The views that tell where things are

/// Sits in the chat's scroll content and hands its NSScrollView to the controller.
struct QCScrollProbe: NSViewRepresentable {
    let scroll: QCChatScroll

    func makeNSView(context: Context) -> NSView { Probe(scroll) }
    func updateNSView(_ view: NSView, context: Context) {}

    final class Probe: NSView {
        let scroll: QCChatScroll
        init(_ s: QCChatScroll) { scroll = s; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError() }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                if let self, let sv = self.enclosingScrollView { self.scroll.attach(sv) }
            }
        }
    }
}

/// Behind a message of the user's: tells the controller where it is. Draws nothing, takes no press.
struct QCAnchor: NSViewRepresentable {
    let scroll: QCChatScroll
    let kind: QCChatScroll.AnchorKind
    let id: UUID

    func makeNSView(context: Context) -> NSView {
        let v = Anchor()
        v.setUp(scroll, kind, id)
        return v
    }

    func updateNSView(_ view: NSView, context: Context) { (view as? Anchor)?.setUp(scroll, kind, id) }

    static func dismantleNSView(_ view: NSView, coordinator: ()) { (view as? Anchor)?.release() }

    final class Anchor: NSView {
        private var scroll: QCChatScroll?
        private var kind = QCChatScroll.AnchorKind.question
        private var id = UUID()

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func setUp(_ s: QCChatScroll, _ k: QCChatScroll.AnchorKind, _ i: UUID) {
            if scroll === s, kind == k, id == i { return }
            release()
            scroll = s; kind = k; id = i
            s.register(k, i, self)
        }

        func release() {
            scroll?.unregister(kind, id, self)
            scroll = nil
        }
    }
}


/// The navigation buttons' tooltips: the words, then the key.
enum QCNavHelp {
    static let previous = "Previous message of mine ⌘["
    static let next = "Next message of mine ⌘]"
    static let latest = "Jump to latest ⌘J"
    static let start = "Go to the start of this answer ⇧⌘J"
}

// MARK: - Edge handles

/// Where the edge handles stand and how they open: ONE place for the numbers.
///
/// What else lives at the panel's edges, and where the handles keep clear of it (points, from the answers area's side):
///   - macOS's resize band: the window frame's own, under 4 pt deep inside the edge (a press 1 pt in resizes, 4 pt in is the
///     content's), 20 pt around a corner. The handles start 5 pt in, and the corners are far below the answers' bottom.
///   - the drag surfaces: every empty part of the card moves the window; a control (`qcControl`) never does. Handles' strips
///     and boxes are controls.
///   - the vertical scroller of the answers: an NSScroller `scrollerWidth` (15 pt) wide on the right edge, in both styles
///     (an overlay scroller only draws when it is wanted, but its track is there). The right handle stands inward of it.
///   - the text: the answers' gutters are as wide as the handle strips, so a handle never touches the text column, and the
///     pill is 10 pt or more clear of it.
enum QCEdgeLayout {
    /// From the window's edge to the handle's strip on the left: clear of the resize band (under 4 pt deep).
    static let clear: CGFloat = 5
    /// The hit strip along the edge, and the pill drawn in it (on its outer side).
    static let stripWidth: CGFloat = 14, stripHeight: CGFloat = 44
    static let pillWidth: CGFloat = 3, pillHeight: CGFloat = 30
    /// The vertical scroller's track on the right (a check compares it with what the scroll view has).
    /// (measured: 17 pt wide in the panel with either style; two points over the scroller's nominal width are kept clear)
    static var scroller: CGFloat { ceil(NSScroller.scrollerWidth(for: .regular, scrollerStyle: NSScroller.preferredScrollerStyle)) + 2 }
    /// The answers' text starts and ends this far from the sides: the strip fits in the gutter, the pill is 11 pt clear of the text.
    static var leftGutter: CGFloat { clear + stripWidth }
    static var rightGutter: CGFloat { scroller + stripWidth }
    /// From the answers area's bottom (the field box is under it) to the tallest box's bottom.
    static let bottomGap: CGFloat = 8
    /// A box is at most this tall (three buttons in a stack and its padding), so a handle stays in line at any content.
    static let boxMaxHeight: CGFloat = 3 * QCSpace.small + 2 * boxPadding
    static let boxPadding: CGFloat = 2

    // MARK: How a stack opens (the operator is finalising this: change it here)
    /// The pointer rests on a handle this long before its stack opens (a pass over it opens nothing).
    static let dwell: TimeInterval = 0.15
    /// The stack closes this long after the pointer has left both the handle and the stack.
    static let collapseAfter: TimeInterval = 0.5
    /// The stack opens BESIDE the handle, inward toward the text, this far clear of the pill, centred on it vertically.
    static let boxGap: CGFloat = 6
    /// Keyboard or VoiceOver opening: it stays this long when nothing holds it open.
    static let keptAfterActivation: TimeInterval = 4

    /// The box's distance from the window's edge (the pill is `clear` or `scroller` in, and `pillWidth` wide).
    static var leftBoxInset: CGFloat { clear + pillWidth + boxGap }
    static var rightBoxInset: CGFloat { scroller + pillWidth + boxGap }
}

/// One handle's state: whether its stack is open. The pointer's rest, its leaving, and the keyboard drive it; nothing animates.
final class QCEdgeState: ObservableObject {
    /// The stack is open.
    @Published private(set) var expanded = false
    /// The pointer is on the handle, or its stack is open (the pill is lit).
    var lit: Bool { onStrip || expanded }
    @Published private(set) var onStrip = false
    private var onBox = false
    private var focused = false
    private var opening: DispatchWorkItem?
    private var closing: DispatchWorkItem?
    var dwell = QCEdgeLayout.dwell
    var collapseAfter = QCEdgeLayout.collapseAfter

    /// The pointer entered or left the handle's strip.
    func strip(_ inside: Bool) {
        if onStrip != inside { onStrip = inside }
        settle()
    }

    /// The pointer entered or left the open stack.
    func box(_ inside: Bool) {
        onBox = inside
        settle()
    }

    /// Keyboard focus is on the handle.
    func focus(_ f: Bool) {
        focused = f
        if f { open() }
        settle()
    }

    /// Opens it at once (the keyboard, VoiceOver): it stays until the pointer or focus has come and gone, or for a few seconds.
    func activate() {
        open()
        cancel(&closing)
        if !onStrip, !onBox, !focused { close(after: QCEdgeLayout.keptAfterActivation) }
    }

    /// A picture can't wait for a pointer: the state it shows.
    func showForPicture(lit: Bool, expanded: Bool) {
        onStrip = lit; self.expanded = expanded
    }

    /// Closes it at once (the panel hid, or the handle has nothing to show).
    func reset() {
        cancel(&opening); cancel(&closing)
        onBox = false; focused = false
        if onStrip { onStrip = false }
        if expanded { expanded = false }
    }

    private var engaged: Bool { onStrip || onBox || focused }

    private func settle() {
        if engaged {
            cancel(&closing)
            if !expanded, opening == nil {
                let w = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.opening = nil
                    if self.engaged { self.open() }
                }
                opening = w
                DispatchQueue.main.asyncAfter(deadline: .now() + dwell, execute: w)
            }
        } else {
            cancel(&opening)
            if expanded, closing == nil { close(after: collapseAfter) }
        }
    }

    private func open() { cancel(&opening); if !expanded { expanded = true } }

    private func close(after delay: TimeInterval) {
        cancel(&closing)
        let w = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.closing = nil
            if !self.engaged, self.expanded { self.expanded = false }
        }
        closing = w
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
    }

    private func cancel(_ w: inout DispatchWorkItem?) { w?.cancel(); w = nil }
}

/// A handle on one side of the answers area: a thin pill in a strip along the edge; the pointer resting on it opens a stack
/// of buttons beside it, inward. Nothing slides or fades: it is there or it is not.
struct QCEdgeHandle<Box: View>: View {
    enum Side { case left, right }
    let side: Side
    @ObservedObject var state: QCEdgeState
    /// The frames the handle reports (a check reads them), under this name.
    let name: String
    let scroll: QCChatScroll
    /// What VoiceOver calls the handle, and its value ("New text below").
    let label: String
    var value = ""
    /// The pill is in the accent colour (new text below).
    var accent = false
    @ViewBuilder let box: () -> Box

    var body: some View {
        let left = side == .left
        ZStack(alignment: left ? .leading : .trailing) {
            // the hit strip, with the pill on its outer side
            Button { state.activate() } label: {
                ZStack(alignment: left ? .leading : .trailing) {
                    Color.clear
                    Capsule().fill(accent ? QCColor.accent : state.lit ? QCColor.text : QCColor.muted)
                        .frame(width: QCEdgeLayout.pillWidth, height: QCEdgeLayout.pillHeight)
                }
                .frame(width: QCEdgeLayout.stripWidth, height: QCEdgeLayout.stripHeight)
                .contentShape(Rectangle())
                .qcControl()
            }
            .buttonStyle(.plain)
            .onHover { state.strip($0) }
            .accessibilityLabel(Text(label))
            .accessibilityValue(Text(value))
            .report(scroll, "\(name).strip")
            .padding(left ? .leading : .trailing, left ? QCEdgeLayout.clear : QCEdgeLayout.scroller)
            if state.expanded {
                VStack(spacing: 0) { box() }
                    .padding(QCEdgeLayout.boxPadding)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(QCColor.window))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(QCColor.line))
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
                    .qcControl()          // the rim as well: a press there never moves the window
                    .onHover { state.box($0) }
                    .report(scroll, "\(name).box")
                    .padding(left ? .leading : .trailing, left ? QCEdgeLayout.leftBoxInset : QCEdgeLayout.rightBoxInset)
            }
        }
        .frame(height: QCEdgeLayout.boxMaxHeight, alignment: .center)
        .frame(maxWidth: .infinity, alignment: left ? .leading : .trailing)
        .padding(.bottom, QCEdgeLayout.bottomGap)
        .onDisappear { state.reset(); scroll.forget(name) }
    }
}

private extension View {
    /// Tells the scroll controller this view's frame (window-global), for the checks.
    func report(_ scroll: QCChatScroll, _ key: String) -> some View {
        background(GeometryReader { g in
            Color.clear
                .onAppear { scroll.frames[key] = g.frame(in: .global) }
                .onChange(of: g.frame(in: .global)) { scroll.frames[key] = $0 }
                .onDisappear { scroll.frames[key] = nil }
        })
    }
}

/// What floats over the answers, in two handles: the left one's stack is this answer's ⤒ and copy (while its footer is out
/// of sight); the right one's is ▲ ▼ (once there are two messages of the user's) and jump to latest (while not at the bottom).
struct QCEdgeHandles: View {
    @ObservedObject var scroll: QCChatScroll
    @ObservedObject var model: QuickChatModel

    var body: some View {
        ZStack {
            if let id = scroll.pair, let turn = model.turns.first(where: { $0.id == id }) {
                QCEdgeHandle(side: .left, state: scroll.left, name: "left", scroll: scroll, label: "This answer") {
                    if scroll.answersAbove.contains(id) {
                        QCIconButton(symbol: "arrow.up.to.line", help: QCNavHelp.start, small: true,
                                     label: "Go to the start of this answer") { scroll.goToStart(ofAnswer: id) }
                    }
                    QCIconButton(symbol: model.copied == id ? "checkmark" : "doc.on.doc", help: "Copy this answer ⇧⌘C", small: true,
                                 label: "Copy this answer") { _ = model.copyAnswer(of: turn) }
                }
            }
            if QCChatScroll.showsPrompts(turns: model.turns.count) || !scroll.atBottom {
                QCEdgeHandle(side: .right, state: scroll.right, name: "right", scroll: scroll, label: "Message navigation",
                             value: scroll.newBelow ? "New text below" : "", accent: scroll.newBelow) {
                    if QCChatScroll.showsPrompts(turns: model.turns.count) {
                        QCIconButton(symbol: "chevron.up", help: QCNavHelp.previous, small: true, label: "Previous message of mine",
                                     enabled: scroll.canPrevious) { scroll.previousPrompt() }
                        QCIconButton(symbol: "chevron.down", help: QCNavHelp.next, small: true, label: "Next message of mine",
                                     enabled: scroll.canNext) { scroll.nextPrompt() }
                    }
                    if !scroll.atBottom {
                        QCIconButton(symbol: "arrow.down.to.line", help: QCNavHelp.latest, small: true, label: "Jump to latest") { scroll.jumpToLatest() }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}
