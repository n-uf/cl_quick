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
/// in view, ⌘[ ⌘] the previous and next message of the user's; ⇧fn↑ and ⇧fn↓ (⇧Page Up, ⇧Page Down, in the panel's sendEvent)
/// scroll a page.
enum QCNav: Equatable { case latest, answerStart, previousPrompt, nextPrompt, pageUp, pageDown }

final class QCChatScroll: ObservableObject {
    /// "At the bottom" is within this many points of it.
    static let slack: CGFloat = 4
    /// A message scrolled to sits this far under the view's top, so its bubble and the flash show whole.
    static let inset: CGFloat = 8
    /// An answer whose first line is less than this far into the view's bottom edge is only peeking in: it is not the answer in
    /// view, and it has no left handle yet.
    static let peek: CGFloat = 24
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

    /// The answers' scroller: its style (the user's "Show scroll bars" setting, or the view's own) and what it takes out of the
    /// clip view (0 for an overlay scroller; a legacy, always visible one's width). The text's right padding and the right
    /// handle follow them (QCEdgeLayout), so nothing covers the scroller and the text ends where the strip starts.
    @Published private(set) var scrollerStyle = NSScroller.preferredScrollerStyle
    @Published private(set) var scrollerInset: CGFloat = NSScroller.preferredScrollerStyle == .legacy
        ? ceil(NSScroller.scrollerWidth(for: QCEdgeLayout.scrollerSize, scrollerStyle: .legacy)) : 0

    /// The two edge handles' states: left (this answer), right (navigation).
    let left = QCEdgeState()
    let right = QCEdgeState()
    /// The window-global frames the handles report, by name ("left.strip", "right.box", …), for the checks.
    var frames: [String: CGRect] = [:]

    func forget(_ name: String) { frames["\(name).strip"] = nil; frames["\(name).box"] = nil }

    /// Told whenever the view's position changes, whoever moved it (the selection's quick actions go when the text moves).
    var moved: () -> Void = {}

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
        view.verticalScroller?.controlSize = QCEdgeLayout.scrollerSize     // the thin scroller (QCEdgeLayout.scroller counts it)
        view.tile()                                                         // its track and the clip view at the new width
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
        if abs(o - lastOffset) > 0.01 { moved() }
        lastClipHeight = g.clip.bounds.height
        clipSawHeight = g.doc.bounds.height
        if !moving, !resized, !shrank, abs(o - lastOffset) > 0.01 {
            // (only an upward move that ENDS ABOVE the bottom stops following: a trackpad's flick to the end overshoots and springs
            // back, and each spring-back step is upward but ends at the bottom)
            if o < lastOffset, o < maxOffset() - 0.5 { following = false } else if isAtBottom { following = true }
        }
        lastOffset = o
        scheduleRefresh()
    }

    /// The window was resized under it: when following, the end stays in view; a view that a growing window leaves at the bottom
    /// (the window grew by as much as the text below it) follows again, as any view at the bottom does.
    private func viewportResized() {
        if following { stick() } else if isAtBottom { following = true }
        lastOffset = offset()
        scheduleRefresh()
    }

    /// The text grew or shrank. Following: the end stays in view. Else the view stays where it is. (Whether text ARRIVED below
    /// is not read from the height: a rewrap or text that grew above the view changes it too. See `contentChanged`.)
    private func documentResized() {
        guard let g = geometry else { return }
        if following { stick() } else if let h = held { held = nil; place(h) }
        lastHeight = g.doc.bounds.height
        scheduleRefresh()
    }

    /// Where the view goes when the text next changes height: a part above the view changed by as much (see below).
    private var held: CGFloat?
    private var heldGeneration = 0

    /// A view in the chat is about to change height by `delta` (a page in an answer measured: InlinePage.swift). When its
    /// top is above the view's top and the view isn't following, the view moves by as much once the text has changed, so
    /// what is in view stays where it was: a page that appears or grows above the view never pulls the reader. Following,
    /// the end stays in view as always; a page in view or below it pushes only what is below it.
    func heightWillChange(of v: NSView, by delta: CGFloat) {
        guard !following, abs(delta) > 0.5, let a = attached(v), top(of: a) < offset() - 0.5 else { return }
        held = (held ?? offset()) + delta
        heldGeneration += 1
        let mine = heldGeneration
        // a change that never came (the height was taken back before the layout) must not move a later one
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if self?.heldGeneration == mine { self?.held = nil }
        }
    }

    /// The chat's text changed (QuickChatModel.scrollTick: text arrived at the end of the chat): keeps the end in view when
    /// following, once the layout has run; when not following, notes text that arrived below the visible end (the "new"
    /// mark): the text grew since before the change, and the view is not at the bottom. A rewrap or growth above the view, with
    /// no change at the end, never ticks, so it never sets the mark.
    func contentChanged() {
        let before = lastHeight
        DispatchQueue.main.async { [weak self] in
            guard let self, let g = self.geometry else { return }
            if self.following { self.stick() }
            else if g.doc.bounds.height > before, !self.isAtBottom { self.newBelow = true }
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
        guard let g = geometry, let sv = scrollView else { return }
        // a style change ("Show scroll bars") may bring a new scroller: keep it thin
        if let v = sv.verticalScroller, v.controlSize != QCEdgeLayout.scrollerSize { v.controlSize = QCEdgeLayout.scrollerSize; sv.tile() }
        let style = sv.scrollerStyle
        // what the scroller has already taken out of the width the text is laid out in: SwiftUI lays the text out at the
        // scroll view's width less a legacy scroller of its own idea of the size (a regular one), which may be wider than the
        // thin one the clip view gives up, so the text's own width (the document's) is what counts, not the clip view's
        let inset = style == .legacy ? max(0, (sv.frame.width - min(g.clip.frame.width, g.doc.frame.width)).rounded()) : 0
        if scrollerStyle != style || scrollerInset != inset {
            scrollerStyle = style; scrollerInset = inset
        }
        let at = isAtBottom
        if atBottom != at {
            atBottom = at
            // the ↓ button hides at the bottom: a focus that was on it goes with it (the stack must not stay held open by it)
            if at { right.focus(false, QCEdgeLayout.latestButton) }
        }
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
            // (its first line is really in view, not just peeking in at the edge)
            if t < bottom - Self.peek, end > bottom + 0.5 { return id }
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
    /// The text column as drawn: the horizontal extent, in window coordinates, of an answer's anchor (it spans the column). A
    /// check measures the handle strips against it.
    func textColumn() -> ClosedRange<CGFloat>? {
        answers.values.compactMap { attached($0.view) }.first.map { v in
            let r = v.convert(v.bounds, to: nil)
            return r.minX...r.maxX
        }
    }

    /// The top of an answer's first line, the same way.
    func top(ofAnswer id: UUID) -> CGFloat? { attached(answers[id]?.view).map(top(of:)) }

    /// Whether a frame (window coordinates) lies in an answer: its centre is in the answer's column. A message of the user's, the
    /// thinking text and the notes are outside every answer.
    func answerContains(_ r: CGRect) -> Bool {
        // (the part of the text that the answers' area shows: a text scrolled away, under the header or the field, is no answer here)
        guard let vis = visibleRectInWindow() else { return false }
        let shown = r.intersection(vis)
        guard !shown.isNull else { return false }
        let c = CGPoint(x: shown.midX, y: shown.midY)
        return answers.values.contains { w in
            guard let v = attached(w.view) else { return false }
            return v.convert(v.bounds, to: nil).contains(c)
        }
    }

    /// The part of the window the answers are seen through (window coordinates), while the chat's scroll view is in one.
    func visibleRectInWindow() -> CGRect? {
        guard let sv = scrollView, sv.window != nil else { return nil }
        return sv.convert(sv.bounds, to: nil)
    }

    /// Find: a line of a text (`line` of `lines`, the text drawn in `v`'s frame) is brought into view. When it is in view already
    /// (clear of the find bar's `cover` at the top) nothing moves; else it lands about a third of the way down, at once, and the
    /// view stops following the end, like any scroll up.
    func reveal(_ v: NSView, line: Int, lines: Int, cover: CGFloat) {
        guard let g = geometry, let a = attached(v), lines > 0 else { return }
        let lh = a.bounds.height / CGFloat(lines)
        let y0 = top(of: a) + CGFloat(line) * lh, y1 = y0 + lh
        let o = offset(), view = g.clip.bounds.height
        if y0 >= o + cover, y1 <= o + view - Self.inset { return }
        go(to: y0 - view * 0.3, follow: false)
    }

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

    /// The answer ⇧⌘J and ⇧⌘C act on: at the bottom the last answer; otherwise the floating pair's answer when there is one,
    /// else the answer that covers the view's middle (or the nearest one above it). Never the next answer whose first line has
    /// only just peeked into the view's bottom edge.
    func answerAtBottomEdge() -> UUID? {
        guard let g = geometry else { return nil }
        let placed = answers.compactMap { id, w -> (id: UUID, top: CGFloat, end: CGFloat)? in
            guard let v = attached(w.view) else { return nil }
            let t = top(of: v)
            let end = attached(footers[id]?.view).map { top(of: $0) + $0.frame.height } ?? t + v.frame.height
            return (id, t, end)
        }.sorted { $0.top < $1.top }
        if isAtBottom { return placed.last?.id }
        if let p = pairedAnswer() { return p }
        let mid = offset() + g.clip.bounds.height / 2
        return (placed.first { $0.top <= mid && mid <= $0.end } ?? placed.last { $0.top < mid })?.id
    }

    /// A key that moves in the chat. False when there is nothing to move (no scroll view yet): the key is not taken.
    func perform(_ nav: QCNav, turns: Int) -> Bool {
        guard geometry != nil else { return false }
        switch nav {
        case .latest: jumpToLatest()
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

    /// ▲ and ▼ (always both, one of them dimmed when it has nowhere to go) show once there are two messages of the user's. With
    /// one message they show whenever the right handle does (it starts above the view, below it, or the view is not at the
    /// bottom), so the stack keeps its size while scrolling and a click on ▲ does not shrink it under the pointer; a short
    /// exchange fully in view has no handle. A long answer read to the bottom has a way back to the message that asked for it.
    static func showsPrompts(turns: Int, canPrevious: Bool, canNext: Bool, atBottom: Bool) -> Bool {
        turns >= 2 || (turns == 1 && (canPrevious || canNext || !atBottom))
    }

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
///   - the vertical scroller of the answers: an NSScroller `scrollerWidth` wide on the right edge, in both styles (an overlay
///     scroller only draws when it is wanted, but its track is there; a legacy, always visible one also takes its width out
///     of the clip view). The right handle stands inward of it, in either style.
///   - the text: the answers' gutters are as wide as the handle strips, so a handle never touches the text column, and the
///     pill is 10 pt or more clear of it, in either scroller style.
enum QCEdgeLayout {
    /// From the window's edge to the handle's strip on the left: clear of the resize band (under 4 pt deep).
    static let clear: CGFloat = 5
    /// The hit strip along the edge, and the pill drawn in it (on its outer side).
    static let stripWidth: CGFloat = 16, stripHeight: CGFloat = 44     // the 5-pt pill stays 11 pt clear of the text
    static let pillWidth: CGFloat = 5, pillHeight: CGFloat = 30
    /// The answers' scroller is the small (thin) one.
    static let scrollerSize: NSControl.ControlSize = .small
    /// The vertical scroller's track on the right, for a scroller style: its nominal width and two points clear (a check compares
    /// it with the real scroller). An overlay scroller draws over the answers (the clip view is the whole width); a LEGACY
    /// (always visible) one takes its width out of the clip view, so the text, which is laid out inside the clip view, already
    /// ends that much before the scroller: see `rightGutter`.
    static func scroller(_ style: NSScroller.Style) -> CGFloat { ceil(NSScroller.scrollerWidth(for: scrollerSize, scrollerStyle: style)) + 2 }
    /// The answers' text starts this far from the left side: the strip fits in the gutter, the pill is 11 pt clear of the text.
    static var leftGutter: CGFloat { clear + stripWidth }
    /// The text's right padding inside the clip view: the scroller's track and the strip, less what the clip view has already
    /// given up to a legacy scroller (`inset`: what the scroller took from the width the text is laid out in; 0 for an overlay
    /// one), so the text always ends where the right strip starts.
    static func rightGutter(_ style: NSScroller.Style, inset: CGFloat) -> CGFloat { max(0, scroller(style) + stripWidth - inset) }
    /// From the answers area's bottom (the field box is under it) to the tallest box's bottom.
    static let bottomGap: CGFloat = 8
    /// A box is at most this tall (three buttons in a stack and its padding), so a handle stays in line at any content.
    static let boxMaxHeight: CGFloat = 3 * QCSpace.small + 2 * boxPadding
    static let boxPadding: CGFloat = 2
    /// The right stack's ↓ button's focus id (it hides at the bottom, with focus possibly on it).
    static let latestButton = 3

    // MARK: How a stack opens (the operator is finalising this: change it here)
    /// The pointer rests on a handle this long before its stack opens (a pass over it opens nothing).
    static let dwell: TimeInterval = 0.15
    /// The stack closes this long after the pointer has left both the handle and the stack.
    static let collapseAfter: TimeInterval = 0.5
    /// The stack opens BESIDE the handle, inward toward the text, this far clear of the pill, centred on it vertically.
    static let boxGap: CGFloat = 6

    /// The box's distance from the window's edge (the pill is `clear` or `scroller` in, and `pillWidth` wide).
    static var leftBoxInset: CGFloat { clear + pillWidth + boxGap }
    static func rightBoxInset(_ style: NSScroller.Style) -> CGFloat { scroller(style) + pillWidth + boxGap }
}

/// One handle's state: whether its stack is open. The pointer's rest, its leaving, and the keyboard drive it; nothing animates.
final class QCEdgeState: ObservableObject {
    /// The stack is open.
    @Published private(set) var expanded = false
    /// The pointer is on the handle, or its stack is open (the pill is lit).
    var lit: Bool { onStrip || expanded }
    @Published private(set) var onStrip = false
    private var onBox = false
    private var focusedIDs = Set<Int>()
    private var focused: Bool { !focusedIDs.isEmpty }
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

    /// Keyboard focus (Full Keyboard Access) came to the handle or a button in its stack, or left them: it opens the stack at once
    /// and keeps it open while focus is inside; moving between the handle and the buttons (focus off, then on) closes nothing.
    /// Each control that can hold focus has its own id (the handle 0, the stack's buttons 1, 2, ...), so one going away with focus
    /// on it (the ↓ button hides at the bottom) clears only its own, and the stack is not held open by a focus that is gone.
    func focus(_ f: Bool, _ id: Int = 0) {
        if f { focusedIDs.insert(id) } else { focusedIDs.remove(id) }
        if f { open() }
        settle()
    }

    /// Pressing the handle (VoiceOver's press, the keyboard's Space on it): opens the stack at once and PINS it open, with no
    /// timer, so it never closes under a VoiceOver cursor on ▲ or ▼; pressing the handle again, or the panel hiding, closes it.
    func activate() {
        if onStrip { open(); return }          // a click with the pointer on it: the pointer holds it, nothing to pin
        if pinned { pinned = false; reset(); return }
        pinned = true
        open()
        settle()
    }

    /// A picture can't wait for a pointer: the state it shows.
    func showForPicture(lit: Bool, expanded: Bool) {
        onStrip = lit; self.expanded = expanded
    }

    /// Closes it at once (the panel hid, or the handle has nothing to show).
    func reset() {
        cancel(&opening); cancel(&closing)
        onBox = false; focusedIDs = []; pinned = false
        if onStrip { onStrip = false }
        if expanded { expanded = false }
    }

    /// Held open by a press on the handle (`activate`).
    private(set) var pinned = false
    private var engaged: Bool { onStrip || onBox || focused || pinned }

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
    /// The answers' scroller style (the right handle stands inward of its track).
    let scrollerStyle: NSScroller.Style
    /// What VoiceOver calls the handle, and its value ("New text below").
    let label: String
    var value = ""
    /// The pill is in the accent colour (new text below).
    var accent = false
    @ViewBuilder let box: () -> Box
    /// Keyboard focus (Full Keyboard Access) on the handle: it opens the stack and keeps it open (the stack's buttons say so too).
    @FocusState private var stripFocus: Bool

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
            .focused($stripFocus)
            .onChange(of: stripFocus) { state.focus($0) }
            .accessibilityLabel(Text(label))
            .accessibilityValue(Text(value))
            .report(scroll, "\(name).strip")
            .padding(left ? .leading : .trailing, left ? QCEdgeLayout.clear : QCEdgeLayout.scroller(scrollerStyle))
            if state.expanded {
                VStack(spacing: 0) { box() }
                    .padding(QCEdgeLayout.boxPadding)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(QCColor.window))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(QCColor.line))
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
                    .qcControl()          // the rim as well: a press there never moves the window
                    .onHover { state.box($0) }
                    .report(scroll, "\(name).box")
                    .padding(left ? .leading : .trailing, left ? QCEdgeLayout.leftBoxInset : QCEdgeLayout.rightBoxInset(scrollerStyle))
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
/// of sight); the right one's is ▲ ▼ (once there are two messages of the user's, or with one whenever the handle shows) and
/// jump to latest (while not at the bottom).
struct QCEdgeHandles: View {
    @ObservedObject var scroll: QCChatScroll
    @ObservedObject var model: QuickChatModel

    var body: some View {
        ZStack {
            if let id = scroll.pair, let turn = model.turns.first(where: { $0.id == id }) {
                QCEdgeHandle(side: .left, state: scroll.left, name: "left", scroll: scroll, scrollerStyle: scroll.scrollerStyle, label: "This answer") {
                    if scroll.answersAbove.contains(id) {
                        QCIconButton(symbol: "arrow.up.to.line", help: QCNavHelp.start, small: true,
                                     label: "Go to the start of this answer", onFocus: { scroll.left.focus($0, 1) }) { scroll.goToStart(ofAnswer: id) }
                    }
                    QCIconButton(symbol: model.copied == id ? "checkmark" : "doc.on.doc", help: "Copy this answer ⇧⌘C", small: true,
                                 label: "Copy this answer", onFocus: { scroll.left.focus($0, 2) }) { _ = model.copyAnswer(of: turn) }
                }
            }
            let prompts = QCChatScroll.showsPrompts(turns: model.turns.count, canPrevious: scroll.canPrevious, canNext: scroll.canNext,
                                                  atBottom: scroll.atBottom)
            if prompts || !scroll.atBottom {
                QCEdgeHandle(side: .right, state: scroll.right, name: "right", scroll: scroll, scrollerStyle: scroll.scrollerStyle, label: "Message navigation",
                             value: scroll.newBelow ? "New text below" : "", accent: scroll.newBelow) {
                    if prompts {
                        QCIconButton(symbol: "chevron.up", help: QCNavHelp.previous, small: true, label: "Previous message of mine",
                                     enabled: scroll.canPrevious, onFocus: { scroll.right.focus($0, 1) }) { scroll.previousPrompt() }
                        QCIconButton(symbol: "chevron.down", help: QCNavHelp.next, small: true, label: "Next message of mine",
                                     enabled: scroll.canNext, onFocus: { scroll.right.focus($0, 2) }) { scroll.nextPrompt() }
                    }
                    if !scroll.atBottom {
                        QCIconButton(symbol: "arrow.down.to.line", help: QCNavHelp.latest, small: true, label: "Jump to latest",
                                     onFocus: { scroll.right.focus($0, QCEdgeLayout.latestButton) }) { scroll.jumpToLatest() }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}
