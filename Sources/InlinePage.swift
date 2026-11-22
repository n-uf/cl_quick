// InlinePage: an html block's page shown in place, inside its code block (QCCodeBlock in ChatViews.swift), once the block
// is complete (its fence closed: never while it streams, never reloaded per token). ```html shows the page first,
// ```html code the code first; the block's Code | Page switch decides after that, and Copy copies the code either way.
//
// The page is the Preview window's isolated document (HTMLPreview.swift: `makeWebView`, the same block-all rule list
// compiled once per run, the same navigation rule), in a host of its own:
//   - HEIGHT: the page shows at its content's height, capped at about half the panel's; a taller one scrolls inside the
//     block. It is measured after the load in our own content world (`.defaultClient`, the click guard's: the page's
//     JavaScript stays off), with the web view laid out at the cap, so a page that fills its viewport shows at the cap.
//     A height that changes while the block's top is above the view moves the chat by as much (QCChatScroll
//     `heightWillChange`), so a page never pulls the reader; while following, the end stays in view as always.
//   - ONE LIVE VIEWER: only one page in the whole run has a web view. The page that goes live is the one in view, chosen
//     when the chat has been still for a moment (QCInlinePageLayout.settle): a page never shown before first, then the
//     live one if it is still in view, else the one most in view; the pointer resting on a still picture wakes that one
//     at once. The page that stops being live is photographed (`takeSnapshot`, with its scroll position) and its web
//     view released; the picture stands in its place (memory only, dropped with the chat) until it is live again, so
//     nothing animates off screen. A rule list that can't be compiled leaves the block as code, and it says so.
//   - THE WHEEL: a gesture latches where it starts. Over a page it scrolls the page; one that starts with the page at its
//     end in that direction (or with nothing to scroll), and one begun over the chat, goes to the chat. Our script reports
//     which ends the page is at; a still picture never takes the wheel.
//   - THE KEYBOARD: a click in a page may give it the keyboard (to select and ⌘C); typing goes on to the chat's field, and
//     a click that selects nothing gives the keyboard back to the field.
//   - CLIPPED: the page is a subview of its host and drawn inside it (rounded at the block's bottom corners); the block's
//     top row stays above it.
// Nothing about a page is written anywhere: the memos (height, still picture, scroll position) are in memory only.

import AppKit
import SwiftUI
import WebKit

enum QCInlinePageLayout {
    /// The most a page shows before it scrolls inside its block: about half the chat panel's height (and 160 at least).
    static func cap(panelHeight h: CGFloat) -> CGFloat { max(160, (h / 2).rounded()) }
    /// A page not measured yet (its first load is under way).
    static let placeholder: CGFloat = 120
    /// The least height of a page: an empty one still shows as a page.
    static let least: CGFloat = 24
    /// The chat still for this long after a scroll (or a change) before the page in view goes live.
    static var settle: TimeInterval = 0.2
    /// A load, a measure or a snapshot that hasn't answered in this long is given up (the web process is gone).
    static let giveUp: TimeInterval = 8

    /// Our measure of the page's content, in our own world (the page's JavaScript is off): the bottom of everything in the
    /// body (text and elements alike, by a range over it) plus the body's own bottom padding, border and margin and the
    /// last element's margin; and the document's scroll height when it overflows the viewport (which is the cap while
    /// measuring). A page that fills its viewport (height: 100vh) measures at the cap.
    static let measureScript = """
    (function () {
      var d = document.documentElement, b = document.body, y = window.scrollY || 0, h = 0;
      if (b) {
        var r = document.createRange(); r.selectNodeContents(b);
        var bs = getComputedStyle(b), last = b.lastElementChild;
        h = r.getBoundingClientRect().bottom + y + (parseFloat(bs.paddingBottom) || 0) + (parseFloat(bs.borderBottomWidth) || 0)
          + (parseFloat(bs.marginBottom) || 0) + (last ? (parseFloat(getComputedStyle(last).marginBottom) || 0) : 0);
      }
      if (d.scrollHeight > window.innerHeight + 1) h = Math.max(h, d.scrollHeight);
      return Math.ceil(h);
    })()
    """
    /// A number one of our scripts answered: finite and not negative, else nil (a NaN or an infinity never becomes a height
    /// or a scroll position).
    static func number(_ r: Result<Any, Error>) -> CGFloat? {
        guard let d = (try? r.get()) as? Double, d.isFinite, d >= 0 else { return nil }
        return CGFloat(d)
    }

    /// Ours too: tells the host which ends of the page the document's scroll is at ("t", "b", "tb" or ""), whenever that
    /// changes, and turns the root's overscroll off (no rubber band inside the block to swallow a wheel meant for the chat).
    static let edgeScript = """
    (function () {
      var last = null;
      function edge() {
        var s = document.scrollingElement || document.documentElement;
        var v = (s.scrollTop <= 0 ? 't' : '') + (s.scrollTop + window.innerHeight >= s.scrollHeight - 1 ? 'b' : '');
        if (v !== last) { last = v; window.webkit.messageHandlers.qcPage.postMessage(v); }
      }
      window.addEventListener('scroll', edge, { capture: true, passive: true });
      window.addEventListener('resize', edge);
      document.addEventListener('DOMContentLoaded', function () { document.documentElement.style.overscrollBehavior = 'none'; edge(); });
    })();
    """
}

/// Every page host of the run, and the one live web view.
final class QCInlinePages {
    static let shared = QCInlinePages()

    /// What is kept of a page between its live turns (memory only): its content's height (at `width`), the height it showed
    /// at, its last still picture and where it was scrolled to.
    struct Memo {
        var content: CGFloat
        var shown: CGFloat
        var width: CGFloat
        var still: NSImage?
        var scrollY: CGFloat = 0
    }
    /// By the page's text (two identical blocks share a memo: they look the same).
    private(set) var memos: [String: Memo] = [:]
    private struct Weak { weak var host: QCInlinePageView? }
    private var registered: [Weak] = []
    /// The host whose web view is live (or loading to be): one at most.
    private(set) weak var live: QCInlinePageView?
    /// Checks: every step ("live", "still", "dropped", "failed"), with the page's first characters.
    var trace: (String) -> Void = { _ in }
    /// Checks: web views of pages alive now, the most alive at once, and the loads started, in this run.
    private(set) var alive = 0, mostAlive = 0, loads = 0
    private var pending: DispatchWorkItem?
    private var switching = false, again = false
    private weak var wanted: QCInlinePageView?

    var hosts: [QCInlinePageView] { registered.compactMap(\.host) }

    func register(_ h: QCInlinePageView) {
        registered.removeAll { $0.host == nil || $0.host === h }
        registered.append(Weak(host: h))
        scheduleUpdate()
    }
    func unregister(_ h: QCInlinePageView) {
        registered.removeAll { $0.host == nil || $0.host === h }
        if live === h { live = nil }
        scheduleUpdate()
    }

    /// A host let its web view go outside a switch (a crash, its text replaced, a load given up): it is no longer the live
    /// one, so the next update can make a page live again.
    func lost(_ h: QCInlinePageView) { if live === h { live = nil } }

    func memo(_ html: String) -> Memo? { memos[html] }
    func setMemo(_ html: String, _ m: Memo) { memos[html] = m }
    func edit(_ html: String, _ change: (inout Memo) -> Void) {
        guard var m = memos[html] else { return }
        change(&m)
        memos[html] = m
    }

    /// The chat has no turns any more (a new chat, an ended chat left, a send after it ended): every height, still picture
    /// and scroll position goes at once, with the chat.
    func forgetAll() { memos = [:] }

    func madeWebView() { alive += 1; loads += 1; mostAlive = max(mostAlive, alive) }
    func releasedWebView() { alive -= 1 }
    /// Checks: the most-alive count starts again from what is alive now.
    func resetMost() { mostAlive = alive }

    /// Something moved or changed: the page in view is decided once the chat has been still for a moment, or once it has
    /// waited three such moments (an answer streaming on below a page that has just closed moves the view at every token:
    /// the page must not wait for the stream to pause).
    func scheduleUpdate() {
        if pending != nil, let since = pendingSince, Date().timeIntervalSince(since) > 3 * QCInlinePageLayout.settle { return }
        if pending == nil { pendingSince = Date() }
        pending?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.update() }
        pending = w
        DispatchQueue.main.asyncAfter(deadline: .now() + QCInlinePageLayout.settle, execute: w)
    }
    private var pendingSince: Date?

    /// The pointer came to a still picture: that page goes live now.
    func wake(_ h: QCInlinePageView) {
        guard h !== live, h.inView else { return }
        wanted = h
        update()
    }

    /// The page that should be live: one never shown before, first; else the live one while it is in view; else the one
    /// most in view (or the one the pointer woke). None in view: none.
    func pick() -> QCInlinePageView? {
        let shown = hosts.filter { $0.inView && !$0.failed && $0.crashes < 2 }
        if let w = wanted, shown.contains(where: { $0 === w }) { return w }
        if let fresh = shown.first(where: { memos[$0.html] == nil && $0.tries == 0 }) { return fresh }
        if let l = live, shown.contains(where: { $0 === l }) { return l }
        return shown.max { $0.visibleRect.height * $0.visibleRect.width < $1.visibleRect.height * $1.visibleRect.width }
    }

    /// Makes the picked page live: the live one is photographed and let go first, so there is never a second web view.
    func update() {
        pending?.cancel(); pending = nil; pendingSince = nil
        guard !switching else { again = true; return }
        let next = pick()
        wanted = nil
        guard next !== live else { return }
        switching = true
        let start = { [weak self] in
            guard let self else { return }
            guard let n = next, n.window != nil else { return self.finish() }
            self.live = n
            n.goLive { [weak self] in self?.finish() }
        }
        if let l = live {
            live = nil
            l.retire(then: start)
        } else { start() }
    }

    private func finish() {
        switching = false
        if live?.hasWebView == false { live = nil }       // its load failed or it went away meanwhile
        if again || wanted != nil { again = false; update() }
    }

    /// Checks: whether a switch is under way.
    var busy: Bool { switching || pending != nil }

    // MARK: renders (a picture can't draw a web view: it draws the still pictures these make)

    /// The width each page's block had in a picture's layout pass (so its still picture is made at that width).
    var renderWidths: [String: CGFloat] = [:]

    /// Renders only: loads `html` at `width` in a window off every screen, measured against `cap`, scrolled to `scrollY`,
    /// then photographed as it would be on leaving view: its memo is what a picture draws. Spins the run loop until done.
    func prime(_ html: String, width: CGFloat, cap: CGFloat, scrollY: CGFloat = 0) {
        _ = NSApplication.shared
        let w = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: width, height: cap), styleMask: [.borderless], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        let host = QCInlinePageView(html: html)
        host.managed = false
        host.capOverride = cap
        host.frame = NSRect(x: 0, y: 0, width: width, height: cap)
        w.contentView = host
        w.orderFrontRegardless()
        func spin(_ until: () -> Bool) {
            let end = Date().addingTimeInterval(QCInlinePageLayout.giveUp)
            while !until(), Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        }
        var ready = false
        host.goLive { ready = true }
        spin { ready }
        if scrollY > 0 {
            host.scrollPage(to: scrollY)
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        var done = false
        host.retire { done = true }
        spin { done }
        w.orderOut(nil)
        w.contentView = nil
        w.close()
    }
}

/// The page's host in the chat: its web view while it is live, its still picture otherwise (or the block's own fill before
/// the first one), clipped to its bounds with the block's bottom corners rounded. A control: no press here moves the panel.
final class QCInlinePageView: NSView, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    private(set) var html: String
    /// Told the height the block should be (content, capped); main thread, never inside a SwiftUI update.
    var report: (CGFloat) -> Void = { _ in }
    /// Told when the rule list can't be compiled: the block shows its code.
    var onFail: () -> Void = {}
    weak var scroll: QCChatScroll?
    /// Renders: the cap to measure against (else half the window's height).
    var capOverride: CGFloat?
    /// False for a render's page: it is driven by hand, never picked.
    var managed = true
    /// Loads begun (a page whose load failed isn't put first again as "never shown").
    private(set) var tries = 0
    /// Its web content process ended under it this many times: made again after the first, never after the second.
    private(set) var crashes = 0

    enum State { case idle, starting, live, retiring }
    private(set) var state = State.idle
    private(set) var failed = false
    private(set) var page: QCPreviewWebView?
    private let still = NSImageView()
    private var allowInitialLoad = false
    private var ready: (() -> Void)?
    private var generation = 0
    /// Which ends of its document the page is scrolled to (our script says, whenever it changes).
    private(set) var atTop = true, atBottom = true
    /// Who takes the rest of the wheel gesture under way: the chat (true) or the page (false); nil between gestures.
    private var wheelToChat: Bool?
    private var observers: [NSObjectProtocol] = []
    private var tracking: NSTrackingArea?
    private var remeasure: DispatchWorkItem?

    var hasWebView: Bool { page != nil }

    init(html: String) {
        self.html = html
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = 7
        // the block's bottom corners (a plain, unflipped view: min Y is the bottom); the top edge meets the header's line
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        still.imageScaling = .scaleNone
        still.imageAlignment = .alignTopLeft
        still.isEditable = false
        still.setAccessibilityLabel("The page, as it last looked")
        still.autoresizingMask = [.width, .height]
        still.frame = bounds
        addSubview(still)
        showStill()
    }
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: where it is

    /// Shown in a window that is on show and not covered, with some of it inside the chat's visible area.
    var inView: Bool {
        guard let w = window, w.isVisible, Self.uncovered(w) else { return false }
        let r = visibleRect
        return r.height >= 1 && r.width >= 1
    }

    /// Whether any of the window can be seen (a check stands in for the window server: its panel is off every screen).
    static var uncovered: (NSWindow) -> Bool = { $0.occlusionState.contains(.visible) }

    var cap: CGFloat { capOverride ?? QCInlinePageLayout.cap(panelHeight: window?.frame.height ?? QuickChatRoot.windowHeight) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        let pages = QCInlinePages.shared
        guard let w = window else {
            drop()
            pages.unregister(self)
            return
        }
        guard managed else { return }
        let nc = NotificationCenter.default
        let changed: (Notification) -> Void = { _ in pages.scheduleUpdate() }
        observers.append(nc.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: w, queue: .main, using: changed))
        observers.append(nc.addObserver(forName: NSWindow.didResizeNotification, object: w, queue: .main) { [weak self] _ in self?.capChanged() })
        if let clip = enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            observers.append(nc.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main, using: changed))
        }
        pages.register(self)
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    override func setFrameSize(_ newSize: NSSize) {
        let wider = abs(newSize.width - frame.width) > 0.5
        super.setFrameSize(newSize)
        still.frame = bounds
        placePage()
        if wider, state == .live { scheduleRemeasure() }
        if managed { QCInlinePages.shared.scheduleUpdate() }
    }

    /// Being measured (the first load, or again after the width changed).
    private var measuring = false

    /// The web view: as wide as the host, its top at the host's top; as tall as the host once measured, the cap while it is
    /// being measured (the part below the host clipped off).
    private func placePage() {
        guard let p = page else { return }
        let h = measuring ? max(cap, bounds.height) : bounds.height
        p.frame = NSRect(x: 0, y: bounds.height - h, width: bounds.width, height: h)
    }

    // MARK: the pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }
    /// A still picture under the pointer wakes its page.
    override func mouseEntered(with event: NSEvent) { if managed, state == .idle, !failed { QCInlinePages.shared.wake(self) } }

    // MARK: live and still

    /// The block now shows another text (a reused view): back to its picture, and decided again.
    func replace(_ text: String) {
        guard text != html else { return }
        drop()
        html = text
        failed = false
        tries = 0; crashes = 0           // another page: never shown yet
        showStill()
        QCInlinePages.shared.scheduleUpdate()
    }

    /// Makes the web view and loads the page under its still picture (or the block's fill); `done` once it is measured and
    /// on show, or given up.
    func goLive(_ done: @escaping () -> Void) {
        guard state == .idle, !failed else { return done() }
        state = .starting
        tries += 1
        generation += 1
        let mine = generation
        ready = done
        DispatchQueue.main.asyncAfter(deadline: .now() + QCInlinePageLayout.giveUp) { [weak self] in
            guard let self, self.generation == mine, self.state == .starting else { return }
            self.drop()
        }
        QCHTMLPreview.withRules { [weak self] list in
            guard let self, self.generation == mine, self.state == .starting, self.window != nil else { return }
            guard let list else { return self.fail() }
            let view = QCHTMLPreview.makeWebView(rules: list)
            let content = view.configuration.userContentController
            content.addUserScript(WKUserScript(source: QCInlinePageLayout.edgeScript, injectionTime: .atDocumentStart,
                                               forMainFrameOnly: true, in: .defaultClient))
            content.add(QCWeakScriptHandler(self), contentWorld: .defaultClient, name: "qcPage")
            view.navigationDelegate = self
            view.uiDelegate = self
            view.wheel = { [weak self] e in self?.wheel(e) ?? false }
            view.key = { [weak self] e in self?.typed(e) ?? false }
            view.clicked = { [weak self] in self?.clickEnded() }
            view.alphaValue = 0                      // under the picture, not on show, until it is measured
            self.page = view
            QCInlinePages.shared.madeWebView()
            self.addSubview(view, positioned: .below, relativeTo: self.still)
            self.measuring = true
            self.placePage()
            self.atTop = true; self.atBottom = true; self.wheelToChat = nil
            self.allowInitialLoad = true
            QCInlinePages.shared.trace("load \(self.traceName)")
            view.loadHTMLString(self.html, baseURL: nil)
        }
    }

    /// Measured: the block takes its height, the page its scroll position, and the page shows in place of the picture.
    private func measured(_ content: CGFloat) {
        guard let p = page, state == .starting else { return }
        let pages = QCInlinePages.shared
        let before = pages.memo(html)
        let shown = min(max(content, QCInlinePageLayout.least), cap)
        pages.setMemo(html, .init(content: content, shown: shown, width: bounds.width, still: before?.still, scrollY: before?.scrollY ?? 0))
        setShown(shown)
        state = .live
        DispatchQueue.main.async { [weak self] in          // after the block has its height: the page, then no picture
            guard let self, self.page === p else { return }
            self.measuring = false
            self.placePage()
            if let y = before?.scrollY, y > 0 { self.scrollPage(to: y) }
            p.alphaValue = 1
            self.still.isHidden = true
        }
        pages.trace("live \(traceName)")
        let r = ready; ready = nil
        r?()
    }

    /// The block's height changes to `h`: the chat is told first, so a change above the view doesn't pull the reader.
    private func setShown(_ h: CGFloat) {
        let current = frame.height
        if abs(h - current) > 0.5, current > 0 { scroll?.heightWillChange(of: self, by: h - current) }
        report(h)
    }

    /// No longer the page in view: photographed (with its scroll position), then the web view goes; the picture stays.
    func retire(then done: @escaping () -> Void) {
        guard let p = page, state == .live else { drop(); return done() }
        state = .retiring
        let key = html                     // the page photographed, whatever the block shows by the time the picture comes
        var once = false
        let finish: (NSImage?, CGFloat?) -> Void = { [weak self] image, y in
            guard !once else { return }
            once = true
            QCInlinePages.shared.edit(key) { m in
                if let image { m.still = image }
                if let y { m.scrollY = y }
            }
            if let self, self.page === p {
                self.drop()
                QCInlinePages.shared.trace("still \(self.traceName)")
            }
            done()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + QCInlinePageLayout.giveUp) { finish(nil, nil) }
        p.evaluateJavaScript("(document.scrollingElement || document.documentElement).scrollTop", in: nil, in: .defaultClient) { r in
            let y = QCInlinePageLayout.number(r)
            let cfg = WKSnapshotConfiguration()
            cfg.rect = p.bounds
            p.takeSnapshot(with: cfg) { image, _ in finish(image, y) }
        }
    }

    /// The web view goes, at once: no navigation, no delegate, no handler; the picture (or the block's fill) shows.
    func drop() {
        generation += 1
        allowInitialLoad = false
        remeasure?.cancel(); remeasure = nil
        if let p = page {
            p.stopLoading()
            p.navigationDelegate = nil
            p.uiDelegate = nil
            p.wheel = nil; p.key = nil; p.clicked = nil
            if let w = window as? QuickChatPanel, w.firstResponder === p { w.focusField() }      // the keyboard isn't lost with it
            p.configuration.userContentController.removeAllScriptMessageHandlers()
            p.removeFromSuperview()
            page = nil
            QCInlinePages.shared.releasedWebView()
            QCInlinePages.shared.trace("dropped \(traceName)")
        }
        state = .idle
        showStill()
        QCInlinePages.shared.lost(self)       // never left as the live one with no web view
        let r = ready; ready = nil
        r?()
    }

    private func fail() {
        failed = true
        state = .idle
        QCInlinePages.shared.trace("failed \(traceName)")
        let r = ready; ready = nil
        r?()
        onFail()
    }

    private func showStill() {
        still.image = QCInlinePages.shared.memo(html)?.still
        still.isHidden = false
    }

    /// Checks and renders: the page's document scrolled to `y` (our world; the page's JavaScript stays off).
    func scrollPage(to y: CGFloat) {
        page?.evaluateJavaScript("window.scrollTo(0, \(Double(y))); 1", in: nil, in: .defaultClient) { _ in }
    }

    /// The panel's height changed (the cap with it) or the column's width: measured again while live; else the memo's height
    /// is capped again.
    private func capChanged() {
        if state == .live { return scheduleRemeasure() }
        guard let m = QCInlinePages.shared.memo(html) else { return }
        let shown = min(max(m.content, QCInlinePageLayout.least), cap)
        if abs(shown - frame.height) > 0.5 { setShown(shown) }
    }

    private func scheduleRemeasure() {
        remeasure?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.measureAgain() }
        remeasure = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: w)
    }

    private func measureAgain() {
        guard let p = page, state == .live else { return }
        measuring = true
        placePage()
        p.evaluateJavaScript(QCInlinePageLayout.measureScript, in: nil, in: .defaultClient) { [weak self] r in
            guard let self, self.page === p else { return }
            let content = QCInlinePageLayout.number(r) ?? self.frame.height
            let shown = min(max(content, QCInlinePageLayout.least), self.cap)
            QCInlinePages.shared.edit(self.html) { m in m.content = content; m.shown = shown; m.width = self.bounds.width }
            self.setShown(shown)
            DispatchQueue.main.async { [weak self] in
                self?.measuring = false
                self?.placePage()
            }
        }
    }

    /// The page's first characters, for a check's trace.
    var traceName: String { String(html.prefix(24)).replacingOccurrences(of: "\n", with: " ") }

    // MARK: the wheel

    /// Whether the page has more than it shows (its content taller than the block).
    var scrollable: Bool { (QCInlinePages.shared.memo(html)?.content ?? 0) > frame.height + 1 }

    /// When the trackpad gesture this view saw ended (its momentum may follow, at once).
    private var gestureEnded: Date?

    /// One wheel event over the live page: true when it went on to the chat. A gesture LATCHES, as AppKit's nested scroll
    /// views and Safari do: its first event over the page decides who takes all of it, its momentum included. The page takes
    /// it unless it has nothing to scroll or is already at its end in that direction; then the chat does. So a page scrolled
    /// to its end stops there, and the next swipe goes on to the chat: no gesture is split, so the chat never gets the middle
    /// of one without its start, and the page never loses one without its end. A gesture begun elsewhere (the chat's flick or
    /// its momentum passing over the page) stays the chat's. A wheel with no phases (a mouse) decides each event.
    func wheel(_ e: NSEvent) -> Bool {
        let dy = e.scrollingDeltaY, dx = e.scrollingDeltaX
        func chatTakes() -> Bool {
            guard scrollable else { return true }
            if abs(dx) > abs(dy) { return false }            // sideways is the page's
            if dy > 0 { return atTop }
            if dy < 0 { return atBottom }
            return false
        }
        let plain = e.phase.isEmpty && e.momentumPhase.isEmpty
        if plain || e.phase.contains(.began) || e.phase.contains(.mayBegin) {
            wheelToChat = chatTakes(); gestureEnded = nil
        } else if let end = gestureEnded {
            // the gesture seen here has ended: only its own momentum, starting at once, goes on with the same owner
            if !(e.momentumPhase.contains(.began) && Date().timeIntervalSince(end) < 0.25) { wheelToChat = nil }
            gestureEnded = nil
        }
        if wheelToChat == nil { wheelToChat = true }             // its start was never seen here: begun over the chat
        let toChat = wheelToChat ?? true
        if plain || e.phase.contains(.cancelled) || e.momentumPhase.contains(.ended) || e.momentumPhase.contains(.cancelled) {
            wheelToChat = nil; gestureEnded = nil
        } else if e.phase.contains(.ended) { gestureEnded = Date() }
        guard toChat, let chat = enclosingScrollView else { return false }
        Self.handOn(chat, e)
        return true
    }

    /// How a wheel event goes on to the chat: its scroll view's own handling (a check records it instead: an event made in a
    /// check has no window, and AppKit's scroll view doesn't act on it).
    static var handOn: (NSScrollView, NSEvent) -> Void = { $0.scrollWheel(with: $1) }

    // MARK: WKScriptMessageHandler (our world only: the page's own scripts are off and can't reach it)

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let s = message.body as? String, message.webView === page else { return }
        atTop = s.contains("t"); atBottom = s.contains("b")
    }

    // MARK: navigation: the Preview window's rule (HTMLPreview.swift)

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences,
                 decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        preferences.allowsContentJavaScript = false
        let policy = QCHTMLPreview.policy(allowInitial: &allowInitialLoad, isMainFrame: navigationAction.targetFrame?.isMainFrame ?? false,
                                          type: navigationAction.navigationType, download: navigationAction.shouldPerformDownload)
        QCInlinePages.shared.trace("decide \(navigationAction.navigationType.rawValue) \(navigationAction.request.url?.path ?? "-") \(policy == .allow ? "allow" : "cancel")")
        decisionHandler(policy, preferences)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(QCHTMLPreview.responsePolicy(canShow: navigationResponse.canShowMIMEType))
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = nil
        download.cancel(nil)
    }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = nil
        download.cancel(nil)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === page, state == .starting else { return }
        QCInlinePages.shared.trace("finished \(traceName)")
        webView.evaluateJavaScript(QCInlinePageLayout.measureScript, in: nil, in: .defaultClient) { [weak self] r in
            guard let self, self.page === webView else { return }
            self.measured(QCInlinePageLayout.number(r) ?? QCInlinePageLayout.placeholder)
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { loadFailed(webView) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { loadFailed(webView) }

    /// The initial load itself failed (a later, cancelled navigation is no failure of the page on show).
    private func loadFailed(_ webView: WKWebView) {
        guard webView === page, state == .starting else { return }
        QCInlinePages.shared.trace("failed load \(traceName)")
        drop()
    }

    /// The web content process went away: the page is let go and made again while it is in view, once; a page whose
    /// process ends a second time stays its still picture (no crash loop).
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === page else { return }
        crashes += 1
        QCInlinePages.shared.trace("crashed \(traceName)")
        drop()
        QCInlinePages.shared.scheduleUpdate()
    }

    // MARK: the keyboard: typing belongs to the chat's field

    /// A key while the page has the keyboard (a click put it there): ⌘ keys stay the page's (⌘C copies its selection, ⌘A
    /// selects it all); anything else is typing meant for the chat, so the field takes the keyboard and gets the key.
    func typed(_ e: NSEvent) -> Bool {
        guard !e.modifierFlags.contains(.command), let w = window as? QuickChatPanel else { return false }
        w.focusField()
        guard let f = w.firstResponder, f !== page else { return false }
        w.sendEvent(e)
        return true
    }

    /// A click in the page ended: with nothing selected the keyboard goes back to the field; a selection keeps it (to copy).
    func clickEnded() {
        guard let p = page else { return }
        p.evaluateJavaScript("String(window.getSelection() || '')", in: nil, in: .defaultClient) { [weak self] r in
            guard let self, self.page === p, let w = self.window as? QuickChatPanel, w.firstResponder === p else { return }
            if ((try? r.get()) as? String ?? "").isEmpty { w.focusField() }
        }
    }
}

/// Holds the host weakly: the content controller keeps its handlers.
final class QCWeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ t: WKScriptMessageHandler) { target = t }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(c, didReceive: message)
    }
}

/// The host in SwiftUI.
struct QCInlinePage: NSViewRepresentable {
    let html: String
    @Binding var shown: CGFloat?
    @Binding var failed: Bool
    let scroll: QCChatScroll?

    func makeNSView(context: Context) -> QCInlinePageView {
        let v = QCInlinePageView(html: html)
        wire(v)
        return v
    }
    func updateNSView(_ v: QCInlinePageView, context: Context) {
        wire(v)
        v.replace(html)
    }
    static func dismantleNSView(_ v: QCInlinePageView, coordinator: ()) { v.drop() }

    private func wire(_ v: QCInlinePageView) {
        let shown = $shown, failed = $failed
        v.report = { h in if shown.wrappedValue != h { shown.wrappedValue = h } }
        v.onFail = { failed.wrappedValue = true }
        v.scroll = scroll
    }
}

/// The page part of an html block: the host at the page's height (its memo's, until measured), inside the block's outline.
struct QCInlinePageBlock: View {
    let html: String
    @Binding var failed: Bool
    @State private var shown: CGFloat?
    @Environment(\.qcRendering) private var rendering
    @Environment(\.qcChatScroll) private var scroll

    var body: some View {
        let memo = QCInlinePages.shared.memo(html)
        let h = shown ?? memo?.shown ?? QCInlinePageLayout.placeholder
        Group {
            if rendering {
                // a picture can't draw a web view: the page's still picture (QCInlinePages.prime), its width noted for it
                GeometryReader { g in
                    let _ = QCInlinePages.shared.renderWidths[html] = g.size.width
                    if let img = memo?.still {
                        Image(nsImage: img).frame(width: g.size.width, height: g.size.height, alignment: .topLeading).clipped()
                    }
                }
                .clipShape(QCBottomRounded(radius: 7))
            } else {
                QCInlinePage(html: html, shown: $shown, failed: $failed, scroll: scroll)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: h)
        .padding([.horizontal, .bottom], 1)          // inside the block's outline
        .qcControl()
        .qcMark("inline-page")
    }
}

/// A rectangle with its bottom corners rounded (macOS 13 has no uneven rounded rectangle): a picture's page, as the host
/// clips it.
struct QCBottomRounded: Shape {
    let radius: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        let k = min(radius, r.width / 2, r.height / 2)
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - k))
        p.addArc(center: CGPoint(x: r.maxX - k, y: r.maxY - k), radius: k, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: r.minX + k, y: r.maxY))
        p.addArc(center: CGPoint(x: r.minX + k, y: r.maxY - k), radius: k, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// Code | Page in an html block's top row: the side on show is marked (a raised fill), the other muted; a click on either
/// picks it for that block.
struct QCCodePageSwitch: View {
    @Binding var page: Bool
    /// What the block's Copy copies (the code): for the checks' hook below.
    var copyText = ""

    var body: some View {
        HStack(spacing: 0) {
            side("Code", on: !page) { page = false }
            side("Page", on: page) { page = true }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(QCColor.hover))
        .qcMark("page-switch")
        .onAppear {
            // checks only (no pointer can press a SwiftUI button there): this block's Code, Page and Copy
            if QCQuiet.on {
                QCBlockActions.last = ["code": { page = false }, "page": { page = true }, "copy": { [copyText] in QCCopy.put(copyText) }]
                QCBlockActions.pageMarked = page
            }
        }
        .onChange(of: page) { if QCQuiet.on { QCBlockActions.pageMarked = $0 } }
    }

    private func side(_ title: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        QCSwitchSide(title: title, on: on, action: action)
    }
}

private struct QCSwitchSide: View {
    let title: String
    let on: Bool
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: on ? .semibold : .medium))
                .padding(.horizontal, 7)
                .frame(height: QCSpace.small - 4)
                .foregroundColor(on || hover ? QCColor.text : QCColor.muted)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(on ? QCColor.line : .clear))
                .qcControl()
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(title == "Code" ? "Show the code" : "Show the page")
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Checks (QCQuiet) only: the top-row actions of the html block drawn last, by name ("code", "page", "copy").
enum QCBlockActions {
    static var last: [String: () -> Void] = [:]
    /// Whether that block's switch marks Page (else Code).
    static var pageMarked: Bool?
}

/// The chat's scroll controller, for a page that changes height (it tells it first).
private struct QCChatScrollKey: EnvironmentKey { static let defaultValue: QCChatScroll? = nil }
extension EnvironmentValues {
    var qcChatScroll: QCChatScroll? {
        get { self[QCChatScrollKey.self] }
        set { self[QCChatScrollKey.self] = newValue }
    }
}

/// The pictures' sample pages (`--render-quick-chat page…`): sample content only.
enum QCInlinePageSamples {
    static let card = """
    <!doctype html>
    <html><head><style>
      body { margin: 0; padding: 18px; font: 14px -apple-system, sans-serif; background: #f4f1ea; color: #2b2a27; }
      .card { max-width: 300px; margin: 0 auto; background: #fff; border-radius: 14px; padding: 18px 20px; box-shadow: 0 1px 3px rgba(0,0,0,.12); }
      .tag { display: inline-block; font-size: 11px; letter-spacing: .06em; text-transform: uppercase; color: #a3522f; background: #f6e3d9; border-radius: 6px; padding: 2px 7px; }
      h2 { margin: 10px 0 2px; font-size: 20px; } .price { font-size: 30px; font-weight: 700; margin: 6px 0 10px; }
      .price span { font-size: 13px; font-weight: 400; color: #77736a; } ul { padding-left: 18px; margin: 0 0 14px; line-height: 1.7; }
      .btn { display: block; text-align: center; background: #c6613f; color: #fff; border-radius: 9px; padding: 9px; font-weight: 600; }
    </style></head><body>
      <div class="card"><span class="tag">Most picked</span><h2>Team plan</h2><div class="price">$12 <span>per seat / month</span></div>
      <ul><li>Shared sample projects</li><li>Weekly usage report</li><li>Email support</li></ul><a class="btn" href="#">Choose Team</a></div>
    </body></html>
    """
    static var tall: String {
        let rows = (1...28).map { i in "<tr><td>\(i)</td><td>Sample task \(i)</td><td>\(["Open", "Done", "Waiting"][i % 3])</td></tr>" }.joined()
        return """
        <!doctype html>
        <html><head><style>
          body { margin: 0; padding: 14px 16px; font: 13px -apple-system, sans-serif; background: #fff; color: #222; }
          h3 { margin: 0 0 8px; } table { width: 100%; border-collapse: collapse; }
          td { padding: 6px 4px; border-bottom: 1px solid #e6e3dc; } tr:nth-child(even) td { background: #faf8f4; }
        </style></head><body><h3>Sample task list</h3><table>\(rows)</table></body></html>
        """
    }
    static let snippet = """
    <link rel="icon" href="/favicon.svg" type="image/svg+xml">
    <meta name="theme-color" content="#c6613f">
    """

    static func turns(_ state: String) -> [QuickChatTurn] {
        func turn(_ q: String, _ a: String, _ s: Double) -> QuickChatTurn {
            var t = QuickChatTurn(question: q, answer: a, model: "Sonnet 5.5"); t.phase = .done; t.seconds = s
            return t
        }
        let first = turn("Sketch a pricing card for a team plan?", "Here is one:\n```html\n\(card)\n```\nThe button does nothing here: links are off in the page.", 6.1)
        switch state {
        case "page-tall":
            return [turn("A sample task list as a table, please.", "Here it is:\n```html\n\(tall)\n```\nIt scrolls inside its block.", 4.2)]
        case "page-code":
            return [turn("What goes in the head for an SVG favicon?", "Paste this into your page's `<head>`:\n```html code\n\(snippet)\n```\nThe colour tints the browser's bar on phones.", 2.3)]
        case "page-still":
            return [turn("A sample task list as a table, please.", "Here it is:\n```html\n\(tall)\n```", 4.2),
                    turn("Thanks. Which ones are waiting?", "Tasks 2, 5, 8, 11, 14, 17, 20, 23 and 26.", 1.4)]
        default:
            return [first]
        }
    }

    /// Each page the picture laid out, loaded at its width and photographed (page-tall and page-still scrolled inside).
    static func prime(_ state: String, cap: CGFloat) {
        let pages = QCInlinePages.shared
        for (html, width) in pages.renderWidths where width > 0 {
            pages.prime(html, width: width, cap: cap, scrollY: html == tall ? 180 : 0)
        }
    }
}
