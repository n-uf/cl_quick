// ChatScroll: how the chat window scrolls, in one place.
//
// The chat is a SwiftUI ScrollView, which on the Mac is an NSScrollView; this finds that view (QCScrollProbe) and watches
// it, so the scroll position is known whoever moves it: the wheel, the trackpad, the scroller, the keys, a drag selecting
// text, or this code. The rules:
//   - FOLLOWING: while the view is at the bottom (within a few points) when text arrives, it goes on following the end.
//     The only thing that changes it is the view's own position, as the user moves it: scrolling up (by any means) stops
//     following; coming back to the bottom (by hand, or the jump-to-latest button) resumes it. New text while not
//     following never moves the view (the document just grows below).
//   - Nothing moves the view by itself on a timer, and nothing here fights a scroll: it reacts to the position it is told
//     about, and the one animation it runs (the buttons' glide) ends with the position it was asked for.
//   - Sending a message (QuickChatModel.followTick) jumps to the bottom and follows.
//   - The jump-to-latest button scrolls to the bottom, smoothly, or at once with Reduce Motion.
//
// Positions are measured as an OFFSET from the document's top (0 = the top, `maxOffset` = the bottom), so the code reads
// the same whichever way the document is flipped.

import AppKit
import SwiftUI

final class QCChatScroll: ObservableObject {
    /// "At the bottom" is within this many points of it.
    static let slack: CGFloat = 4

    // MARK: What the views read (published only when they change)

    /// The view is at the bottom (the jump-to-latest button hides).
    @Published private(set) var atBottom = true
    /// Text arrived below while the view was not at the bottom (a dot on the jump-to-latest button).
    @Published private(set) var newBelow = false

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
    private var animating = false
    private var refreshPending = false
    private var observers: [NSObjectProtocol] = []

    /// Reduce Motion in System Settings; a check sets it.
    var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

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
        if !moving, !animating, abs(o - lastOffset) > 0.01 { following = isAtBottom }
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
    }

    // MARK: Jumping to the latest

    /// The jump-to-latest button, and a message sent: the bottom, and following again.
    func jumpToLatest(animated: Bool = true) { go(to: maxOffset(), animated: animated, follow: true) }

    // MARK: Moving

    private func go(to target: CGFloat, animated: Bool, follow: Bool) {
        guard let g = geometry else { return }
        following = follow
        let o = clamped(target)
        if !animated || reduceMotion() || abs(o - offset()) < 1 {
            place(o)
            finishMove(follow: follow)
            return
        }
        let y = flipped ? g.doc.bounds.minY + o : g.doc.bounds.maxY - g.clip.bounds.height - o
        animating = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ctx.allowsImplicitAnimation = true
            g.clip.animator().setBoundsOrigin(NSPoint(x: g.clip.bounds.minX, y: y))
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.animating = false
            self.scrollView?.reflectScrolledClipView(g.clip)
            self.lastOffset = self.offset()
            if follow { self.stick() }
            self.finishMove(follow: follow)
        })
    }

    /// After a move: following again if it ended at the bottom.
    private func finishMove(follow: Bool) {
        following = follow || isAtBottom
        lastOffset = offset()
        refresh()
    }

    // MARK: For pictures (a render can't draw a scroll view)

    func showForPicture(atBottom: Bool, newBelow: Bool) {
        self.atBottom = atBottom; self.newBelow = newBelow
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

// MARK: - The floating control

/// The small control floating at the answers' bottom right, just above the field box: jump to latest, while the view is not
/// at the bottom (with a dot when text has arrived below since).
struct QCScrollControl: View {
    @ObservedObject var scroll: QCChatScroll

    var body: some View {
        if !scroll.atBottom {
            QCIconButton(symbol: "arrow.down.to.line", help: "Jump to latest", small: true, label: "Jump to latest") { scroll.jumpToLatest() }
                .overlay(alignment: .topTrailing) {
                    if scroll.newBelow { Circle().fill(QCColor.accent).frame(width: 7, height: 7).offset(x: -3, y: 3).allowsHitTesting(false) }
                }
                .accessibilityValue(Text(scroll.newBelow ? "New text below" : ""))
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(QCColor.surface))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(QCColor.line))
                .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
                .qcControl()          // the rim as well: a press there never moves the window
        }
    }
}
