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

    /// Whether new text moves the view to the end. True at the start.
    private(set) var following = true

    private(set) weak var scrollView: NSScrollView?
    private weak var clip: NSClipView?
    private weak var doc: NSView?
    private var flipped = true
    private var lastOffset: CGFloat = 0
    private var lastHeight: CGFloat = 0
    /// Set while this code moves the view (its own moves are not the user's).
    private var moving = false
    private var refreshPending = false
    private var observers: [NSObjectProtocol] = []

    private struct Weak { weak var view: NSView? }
    private var questions: [UUID: Weak] = [:]
    private var answers: [UUID: Weak] = [:]

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
        lastOffset = offset(); lastHeight = doc.bounds.height
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
    private func clipMoved() {
        guard geometry != nil else { return }
        let o = offset()
        if !moving, abs(o - lastOffset) > 0.01 { following = isAtBottom }
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
    }

    // MARK: Anchors

    enum AnchorKind { case question, answer }

    func register(_ kind: AnchorKind, _ id: UUID, _ view: NSView) {
        switch kind {
        case .question: questions[id] = Weak(view: view)
        case .answer: answers[id] = Weak(view: view)
        }
        scheduleRefresh()
    }

    func unregister(_ kind: AnchorKind, _ id: UUID, _ view: NSView) {
        switch kind {
        case .question: if questions[id]?.view === view { questions[id] = nil }
        case .answer: if answers[id]?.view === view { answers[id] = nil }
        }
        scheduleRefresh()
    }

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
                        answersAbove: Set<UUID> = []) {
        self.atBottom = atBottom; self.newBelow = newBelow
        self.canPrevious = canPrevious; self.canNext = canNext; self.flash = flash
        self.answersAbove = answersAbove
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

// MARK: - The floating control

/// The small control floating at the answers' bottom right, just above the field box: ▲ ▼ (the previous and the next message
/// of the user's, once there are two), then jump to latest while the view is not at the bottom (with a dot when text has
/// arrived below since).
struct QCScrollControl: View {
    @ObservedObject var scroll: QCChatScroll
    /// The chat has two or more messages of the user's.
    let prompts: Bool

    var body: some View {
        if prompts || !scroll.atBottom {
            HStack(spacing: 0) {
                if prompts {
                    QCIconButton(symbol: "chevron.up", help: "Previous message of mine", small: true, label: "Previous message of mine",
                                 enabled: scroll.canPrevious) { scroll.previousPrompt() }
                    QCIconButton(symbol: "chevron.down", help: "Next message of mine", small: true, label: "Next message of mine",
                                 enabled: scroll.canNext) { scroll.nextPrompt() }
                }
                if !scroll.atBottom {
                    QCIconButton(symbol: "arrow.down.to.line", help: "Jump to latest", small: true, label: "Jump to latest") { scroll.jumpToLatest() }
                        .overlay(alignment: .topTrailing) {
                            if scroll.newBelow { Circle().fill(QCColor.accent).frame(width: 7, height: 7).offset(x: -3, y: 3).allowsHitTesting(false) }
                        }
                        .accessibilityValue(Text(scroll.newBelow ? "New text below" : ""))
                }
            }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(QCColor.surface))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(QCColor.line))
                .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
                .qcControl()          // the rim as well: a press there never moves the window
        }
    }
}
