// Pages in place (Sources/InlinePage.swift), in the real chat panel (ordered in invisible, off every screen): an html block
// shows its page once its fence has closed (```html code shows the code), at its content's height up to about half the
// panel's, with one live web view at most (the others still pictures), the wheel handed on to the chat at the page's end,
// a page growing above the view never pulling the reader, the handles and gutters clear of it, Copy copying the code,
// and not one connection leaving it (the loopback probe, with no click). No mouse, no posted event, no clipboard.
//   (called from Checks/panel/main.swift)

import AppKit
import Network
import WebKit

func inlinePageChecks() {
    guard let p = panel(), let cv = p.contentView else { check("inline: the panel is there", false); return }
    func near(_ a: CGFloat, _ b: CGFloat, _ d: CGFloat = 1) -> Bool { abs(a - b) <= d }
    let m = chat.model
    let sc = m.scroll
    let pages = QCInlinePages.shared
    var steps: [String] = []
    pages.trace = { steps.append($0) }
    defer { pages.trace = { _ in } }
    m.newChat(); m.field = ""
    chat.open(); spin(0.3)

    func hosts() -> [QCInlinePageView] {
        var out: [QCInlinePageView] = []
        func walk(_ v: NSView) { if let h = v as? QCInlinePageView { out.append(h) }; v.subviews.forEach(walk) }
        walk(cv)
        return out.sorted { $0.convert($0.bounds, to: nil).maxY > $1.convert($1.bounds, to: nil).maxY }      // top first
    }
    func liveViews() -> Int { hosts().filter(\.hasWebView).count }
    /// Until the pages have settled: no switch under way or waiting, for a few turns in a row.
    func settle() {
        var quiet = 0
        let end = Date().addingTimeInterval(20)
        while quiet < 8, Date() < end {
            spin(0.05)
            quiet = pages.busy || hosts().contains(where: { $0.state == .starting || $0.state == .retiring }) ? 0 : quiet + 1
        }
    }
    func turn(_ answer: String, _ phase: QuickChatTurn.Phase = .done, question: String = "q") -> QuickChatTurn {
        var t = QuickChatTurn(question: question, answer: answer, model: "Haiku 5.5"); t.phase = phase; t.seconds = 1
        return t
    }
    func show(_ answers: [String]) { m.turns = answers.map { turn($0) }; m.scrollTick += 1; spin(0.3); settle() }
    func mark(_ k: String) -> CGRect? { QCStepTargets.shared.marks[k] }
    let short = "<p style=\"margin:0;padding:8px\">Sample page</p>"

    // ── page by default; ```html code shows the code; other languages have neither ──
    pages.forgetAll()
    show(["Here:\n```html\n\(short)\n```"])
    let first = hosts()
    check("inline: a complete html block shows its page in place, by default", first.count == 1, "\(first.count)")
    check("inline: …live, measured, on show (one web view)", first.first?.state == .live && liveViews() == 1 && first.first?.page?.alphaValue == 1,
          "\(String(describing: first.first?.state)) \(liveViews())")
    check("inline: its top row has Code | Page and ⤢ beside Copy", mark("page-switch") != nil && mark("preview") != nil)
    if let h = first.first, let memo = pages.memo(h.html) {
        check("inline: a short page shows at its content's height (\(memo.content) pt), not the cap", near(h.frame.height, memo.shown) && memo.shown < 80 && memo.content >= 30,
              "frame \(h.frame.height) memo \(memo)")
    } else { check("inline: the page was measured", false) }
    check("inline: every web view is the Preview's isolated one (QCPreviewWebView, JavaScript off, no link previews, non-persistent, guard in)",
          first.first?.page.map { v in
            v.configuration.defaultWebpagePreferences.allowsContentJavaScript == false && !v.allowsLinkPreview && !v.configuration.websiteDataStore.isPersistent
            && v.configuration.preferences.isFraudulentWebsiteWarningEnabled == false
            && v.configuration.userContentController.userScripts.contains { $0.source == QCHTMLPreview.guardScript } } == true)
    show(["Paste:\n```html code\n\(short)\n```"])
    check("inline: ```html code shows the code (no page), and still has the switch", hosts().isEmpty && mark("page-switch") != nil && liveViews() == 0)
    check("inline: the fence's meta is read: code first only for `code`", QCHTMLPreview.codeFirst("code") && QCHTMLPreview.codeFirst("Code x")
          && !QCHTMLPreview.codeFirst("") && !QCHTMLPreview.codeFirst("page") && !QCHTMLPreview.codeFirst("codes"))
    show(["```swift\nlet a = 1\n```"])
    check("inline: another language has no switch, no ⤢ and no page", mark("page-switch") == nil && mark("preview") == nil && hosts().isEmpty)

    // ── the switch: the user's click wins, both ways; Copy copies the code whichever side shows ──
    let board = NSPasteboard(name: NSPasteboard.Name("cl-quick-inline-check-\(ProcessInfo.processInfo.processIdentifier)"))
    let realBoard = QCCopy.board
    QCCopy.board = board
    defer { board.releaseGlobally(); QCCopy.board = realBoard }
    show(["Here:\n```html\n\(short)\n```"])
    func press(_ label: String) -> Bool {
        // the block's own actions, as its buttons run them (QCBlockActions: SwiftUI builds no accessibility tree here, and a
        // click sent to the panel would make this program the active app)
        guard let a = QCBlockActions.last[label.lowercased()] else { return false }
        a()
        return true
    }
    board.clearContents()
    let pagePressCopy = press("Copy")
    check("inline: Copy copies the code while the page shows", pagePressCopy && board.string(forType: .string) == short, "\(pagePressCopy) \(String(describing: board.string(forType: .string)))")
    let pressedCode = press("Code"); spin(0.3); settle()
    check("inline: a click on Code shows the code (the page and its web view go)", pressedCode && hosts().isEmpty && liveViews() == 0, "\(pressedCode) \(hosts().count)")
    board.clearContents()
    _ = press("Copy")
    check("inline: …and Copy copies the same code", board.string(forType: .string) == short)
    m.turns[0].answer += "\nMore text."; m.scrollTick += 1; spin(0.3); settle()
    check("inline: the click holds while the answer changes (code still)", hosts().isEmpty)
    let pressedPage = press("Page"); spin(0.3); settle()
    check("inline: a click on Page shows the page again, live", pressedPage && hosts().count == 1 && liveViews() == 1, "\(pressedPage) \(hosts().count)")
    show(["Paste:\n```html code\n\(short)\n```"])
    _ = press("Page"); spin(0.3); settle()
    check("inline: on a ```html code block a click on Page shows the page", hosts().count == 1 && liveViews() == 1)

    // ── only when complete: an unfinished block is code; it renders once its fence closes, and never reloads per token ──
    pages.forgetAll()
    m.turns = [turn("Here:\n```html\n<p style=\"margin:0\">Sam", .streaming)]; m.scrollTick += 1; spin(0.3); settle()
    check("inline: while the fence is open the block is code: no page, no switch, no ⤢", hosts().isEmpty && mark("page-switch") == nil && mark("preview") == nil)
    let loads0 = pages.loads
    m.turns[0].answer += "ple</p>\n```\n"; m.scrollTick += 1
    // the answer streams on below it, a token every 50 ms for 2 s: the page goes live meanwhile, loaded once, never again
    var liveDuring = false, hostsDuring = Set<ObjectIdentifier>()
    for i in 1...40 {
        m.turns[0].answer += " word\(i)"; m.scrollTick += 1; spin(0.05)
        hosts().forEach { hostsDuring.insert(ObjectIdentifier($0)) }
        if hosts().first?.state == .live { liveDuring = true }
    }
    let closedHost = hosts().first
    check("inline: the fence closed: the page shows, and goes live while the answer still streams on below it", liveDuring && hosts().count == 1)
    m.turns[0].phase = .done; m.scrollTick += 1; spin(0.3); settle()
    check("inline: 40 tokens after it and the answer ending reload nothing (one host all along, one load)",
          pages.loads == loads0 + 1 && hosts().first === closedHost && closedHost?.state == .live && hostsDuring.count == 1, "loads \(pages.loads - loads0) hosts \(hostsDuring.count)")

    // ── the height: capped at about half the panel; a taller page scrolls inside its block ──
    let tallRows = (1...80).map { "<p style=\"margin:0;height:20px\">Row \($0)</p>" }.joined()
    let tall = "<!doctype html><html><body style=\"margin:0\">\(tallRows)</body></html>"
    show(["Tall:\n```html\n\(tall)\n```"])
    let cap = QCInlinePageLayout.cap(panelHeight: p.frame.height)
    if let h = hosts().first, let memo = pages.memo(h.html) {
        check("inline: a page taller than the cap shows at the cap (\(cap) pt, half the panel's \(p.frame.height))",
              near(h.frame.height, cap) && memo.content >= 1600 && h.scrollable, "frame \(h.frame.height) memo \(memo)")
        check("inline: the cap is about half the panel's height", near(cap, (p.frame.height / 2).rounded()) || cap == 160)
        check("inline: the web view is the host's size, inside the block (clipped to it)",
              h.page.map { near($0.frame.height, h.bounds.height) && near($0.frame.width, h.bounds.width) && $0.frame.minY >= -0.5 } == true && h.layer?.masksToBounds == true,
              "\(String(describing: h.page?.frame)) \(h.bounds)")
    } else { check("inline: the tall page was measured", false) }
    let full = "<!doctype html><html><style>html,body{height:100%;margin:0}</style><body><div style=\"height:100%;background:#eee\">Fills its viewport</div></body></html>"
    show(["Full:\n```html\n\(full)\n```"])
    check("inline: a page that fills its viewport (height 100%) shows at the cap, not at whatever it was given", hosts().first.map { near($0.frame.height, cap) } == true,
          "\(String(describing: hosts().first?.frame))")
    let bare = "<div style=\"padding:6px\">no doctype, no body</div>"
    show(["Bare:\n```html\n\(bare)\n```"])
    check("inline: a snippet with no doctype (quirks mode) shows at its content's height, not the cap",
          hosts().first.map { $0.frame.height < 80 } == true, "\(String(describing: hosts().first?.frame))")

    // ── the clip and the column: the page is inside the text column and under its block's top row; the handles keep working ──
    show(["Here:\n```html\n\(short)\n```"])
    func win(_ r: CGRect) -> NSRect {      // a SwiftUI global frame (top-left) as a window rect
        let a = cv.convert(NSPoint(x: r.minX, y: cv.isFlipped ? r.minY : cv.bounds.height - r.minY), to: nil)
        let b = cv.convert(NSPoint(x: r.maxX, y: cv.isFlipped ? r.maxY : cv.bounds.height - r.maxY), to: nil)
        return NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
    if let h = hosts().first, let col = sc.textColumn(), let sw = mark("page-switch"), let ex = mark("preview") {
        let r = h.convert(h.bounds, to: nil)
        check("inline: the page sits inside the text column (clear of both gutters)", r.minX >= col.lowerBound - 0.5 && r.maxX <= col.upperBound + 0.5, "\(r) column \(col)")
        check("inline: the block's top row (Code | Page, ⤢) is above the page, not on it", r.maxY <= win(sw).minY + 0.5 && r.maxY <= win(ex).minY + 0.5,
              "page \(r) switch \(win(sw)) ⤢ \(win(ex))")
        check("inline: no point of the page starts a move (a control)", stride(from: r.minX + 2, to: r.maxX - 2, by: 9).allSatisfy { x in
            stride(from: r.minY + 2, to: r.maxY - 2, by: 9).allSatisfy { y in QCDragView.surface(at: NSPoint(x: x, y: y), in: p) == nil } })
    } else { check("inline: the page, the column and the switch are found", false) }

    // ── one live viewer: the page in view; the others are still pictures (memory only), and come back live ──
    let lines = ChatScrollRig.lines(24, "between")
    let three = (1...3).map { "Page \($0):\n```html\n<p style=\"margin:0;padding:10px\">Sample page \($0)</p>\n```\n\n" + lines }
    pages.forgetAll()
    m.turns = three.enumerated().map { turn($0.element, question: "Sample question \($0.offset + 1)?") }
    m.scrollTick += 1; spin(0.3)
    guard let sv = sc.scrollView else { check("inline: the chat's scroll view", false); return }
    let clip = sv.contentView
    func user(scrollTo o: CGFloat) { clip.scroll(to: NSPoint(x: 0, y: o)); sv.reflectScrolledClipView(clip); spin(0.05); settle() }
    func toPage(_ i: Int) -> QCInlinePageView? {          // the i-th page in the middle of the view
        guard let h = hosts().dropFirst(i).first, let doc = sv.documentView else { return nil }
        let r = h.convert(h.bounds, to: doc)
        let t = doc.isFlipped ? r.minY : doc.bounds.height - r.maxY
        user(scrollTo: max(0, t - clip.bounds.height / 3))
        return h
    }
    pages.resetMost()
    var seen: [String] = []
    for i in [0, 1, 2, 0] {
        guard let h = toPage(i) else { check("inline: page \(i + 1) is found", false); continue }
        let others = hosts().filter { $0 !== h }
        seen.append("\(i + 1): live \(h.state == .live) web \(liveViews()) stills \(others.map { pages.memo($0.html)?.still != nil })")
        check("inline: page \(i + 1) in view is the live one, the only web view", h.state == .live && h.hasWebView && liveViews() == 1, seen.last!)
    }
    check("inline: never more than one web view of a page at once, all along", pages.mostAlive <= 1, "\(pages.mostAlive)")
    // the right handle's stack opens over a live page (its bottom at the view's bottom edge) and keeps its clicks
    if let h = hosts().dropFirst(1).first, let doc = sv.documentView {
        let r0 = h.convert(h.bounds, to: doc)
        let t = doc.isFlipped ? r0.minY : doc.bounds.height - r0.maxY
        user(scrollTo: t + h.frame.height - clip.bounds.height + 2)
        sc.right.activate(); spin(0.3)
        if let box = sc.frames["right.box"] {
            let b = win(box), page = h.convert(h.bounds, to: nil)
            let c = NSPoint(x: b.midX, y: b.midY)
            let hit = QCDragView.hit(at: c, in: p)
            check("inline: the handle's open stack over a live page takes the press there, not the page",
                  h.state == .live && page.contains(c) && hit != nil && !(hit!.isDescendant(of: h)), "page \(page) box \(b) hit \(String(describing: hit.map { type(of: $0) }))")
        } else { check("inline: the right handle's stack opens", false, "\(sc.frames.keys.sorted())") }
        sc.right.reset(); spin(0.1)
    } else { check("inline: the second page is found", false) }
    check("inline: the pages that went out of view left still pictures", hosts().allSatisfy { pages.memo($0.html)?.still != nil }, "\(seen)")
    // nothing in view: nothing live
    user(scrollTo: sc.maxOffset())
    if let lastTop = hosts().last.map({ $0.convert($0.bounds, to: nil) }), lastTop.maxY < sv.convert(sv.bounds, to: nil).minY {
        check("inline: with no page in view no web view is alive", liveViews() == 0 && pages.alive == 0, "\(liveViews())")
    }
    // the pointer resting on a still picture wakes it at once (two pages in view)
    let pair = (1...2).map { "Page \($0):\n```html\n<p style=\"margin:0;padding:10px\">Sample pair \($0)</p>\n```" }
    m.turns = pair.map { turn($0) }; m.scrollTick += 1; spin(0.3); settle()
    let both = hosts()
    if both.count == 2, let still = both.first(where: { !$0.hasWebView }) {
        let enter = NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: p.windowNumber,
                                           context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        still.mouseEntered(with: enter); settle()
        check("inline: the pointer on a still picture wakes its page, and the other one goes still", still.state == .live && liveViews() == 1, "\(still.state) \(liveViews())")
    } else { check("inline: two pages in view, one still", false, "\(both.map(\.state))") }
    // the panel hidden: no web view stays; shown again: the page in view is live again
    chat.hide(); spin(0.1); settle()
    check("inline: the panel hidden, no page's web view is alive", pages.alive == 0, "\(pages.alive)")
    chat.open(); spin(0.3); settle()
    check("inline: shown again, the page in view is live again", liveViews() == 1, "\(liveViews())")

    // ── a still picture comes back where the page was scrolled to ──
    pages.forgetAll()
    m.turns = [turn("Tall:\n```html\n\(tall)\n```\n\n" + lines, question: "Sample tall?"), turn("Page:\n```html\n\(short)\n```\n\n" + lines)]
    m.scrollTick += 1; spin(0.3)
    if let h = toPage(0) {
        h.scrollPage(to: 400); spin(0.4)
        _ = toPage(1); settle()
        let y = pages.memo(h.html)?.scrollY ?? -1
        check("inline: a page leaving view keeps where it was scrolled to (with its still picture)", near(y, 400, 2) && pages.memo(h.html)?.still != nil, "\(y)")
        _ = toPage(0); spin(0.3); settle()
        var back: Double?
        h.page?.evaluateJavaScript("(document.scrollingElement || document.documentElement).scrollTop", in: nil, in: .defaultClient) { r in back = (try? r.get()) as? Double ?? -1 }
        spinUntil(5) { back != nil }
        check("inline: back in view it is live again, scrolled where it was", h.state == .live && near(CGFloat(back ?? -1), 400, 2), "\(String(describing: back))")
    } else { check("inline: the tall page is found", false) }

    // ── the wheel: a page with nothing to scroll hands it to the chat; a tall one keeps it until its end, then hands it on ──
    // (an event made here has no window, and AppKit's scroll view doesn't act on one: what goes on to the chat is recorded
    // where it is handed on, and must be the chat's own scroll view; what the page keeps goes to WebKit, which scrolls it)
    func wheel(_ dy: Int32) -> NSEvent? {
        CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: dy, wheel2: 0, wheel3: 0).flatMap { NSEvent(cgEvent: $0) }
    }
    var handed: [NSScrollView] = []
    let realHandOn = QCInlinePageView.handOn
    QCInlinePageView.handOn = { sv, _ in handed.append(sv) }
    defer { QCInlinePageView.handOn = realHandOn }
    if let h = toPage(1), let v = h.page, let down = wheel(-30) {
        handed = []
        v.scrollWheel(with: down); spin(0.2)
        check("inline: the wheel over a page with nothing to scroll goes on to the chat's scroll view", !h.scrollable && handed.count == 1 && handed.first === sv, "\(handed)")
    } else { check("inline: the short page and a wheel event", false) }
    if let h = toPage(0), let v = h.page, let down = wheel(-30), let up = wheel(30) {
        h.scrollPage(to: 0); spin(0.4)
        handed = []
        var y0: Any??, y1: Any??
        v.evaluateJavaScript("(document.scrollingElement || document.documentElement).scrollTop", in: nil, in: .defaultClient) { y0 = .some(try? $0.get()) }
        spinUntil(5) { y0 != nil }
        v.scrollWheel(with: down); spin(0.4)
        v.evaluateJavaScript("(document.scrollingElement || document.documentElement).scrollTop", in: nil, in: .defaultClient) { y1 = .some(try? $0.get()) }
        spinUntil(5) { y1 != nil }
        let before = ((y0 ?? nil) as? Double) ?? -1, after = ((y1 ?? nil) as? Double) ?? -1
        check("inline: over a tall page at its top, the wheel down stays with the page: not handed to the chat, the page scrolls",
              handed.isEmpty && h.scrollable && before == 0 && after > 0 && !h.atBottom, "handed \(handed.count) bottom \(h.atBottom) scrollTop \(before) → \(after)")
        h.scrollPage(to: 100000); spin(0.5)
        v.scrollWheel(with: down); spin(0.2)
        check("inline: at the page's end the wheel goes on to the chat", h.atBottom && handed.count == 1 && handed.first === sv, "bottom \(h.atBottom) handed \(handed.count)")
        v.scrollWheel(with: up); spin(0.2)
        check("inline: …and back up, the page takes it again (it is not at its top)", handed.count == 1 && !h.atTop, "handed \(handed.count) top \(h.atTop)")
        // a still picture never takes the wheel: nothing between it and the chat's scroll view handles one
        _ = toPage(1); settle()
        if h.state == .idle, let still = h.subviews.first(where: { $0 is NSImageView }) {
            var chain: [String] = [], r: NSResponder? = still.nextResponder, reached = false
            while let x = r { if x === sv { reached = true; break }; chain.append("\(type(of: x))"); r = x.nextResponder }
            check("inline: over a still picture the wheel goes up the responder chain to the chat's scroll view, past no web view",
                  reached && !chain.contains { $0.contains("WKWebView") || $0.contains("QCPreviewWebView") }, "\(chain)")
        } else { check("inline: the tall page went still", false, "\(h.state)") }
    } else { check("inline: the tall page and wheel events", false) }

    // ── a page that grows above the view never pulls the reader ──
    // the answer arrives while the chat follows the end: its page is above the view at once, never in view, so not measured
    // (the chat stays a chat throughout: no turns at all would make it the bar, and another scroll view)
    pages.forgetAll()
    sc.jumpToLatest()
    m.turns = [turn("Tall:\n```html\n\(tall)\n```\n\n" + lines + "\n\n" + lines, question: "Sample above?"), turn(lines, question: "Sample below?")]
    m.followTick += 1; spin(0.02); settle()
    if let h = hosts().first, let doc = sv.documentView {
        let r = h.convert(h.bounds, to: doc)
        let pageTop = doc.isFlipped ? r.minY : doc.bounds.height - r.maxY
        check("inline: a page that never came into view isn't loaded (its placeholder's height, no memo)",
              pages.memo(h.html) == nil && near(h.frame.height, QCInlinePageLayout.placeholder) && !h.hasWebView, "\(h.frame.height) \(h.state)")
        // scrolled up so the page is partly above the view's top: once it goes live it grows (placeholder → cap) above the view
        let below = m.turns[1].id
        clip.scroll(to: NSPoint(x: 0, y: pageTop + 40)); sv.reflectScrolledClipView(clip); spin(0.02)
        let before = (sc.top(ofQuestion: below) ?? 0) - sc.offset(), held = h.frame.height, o = sc.offset()
        settle(); spin(0.3)
        let after = (sc.top(ofQuestion: below) ?? 0) - sc.offset()
        check("inline: a page partly above the view's top that grows (\(held) → \(h.frame.height) pt) leaves what is in view where it was",
              h.state == .live && h.frame.height > held + 20 && near(before, after) && !sc.following,
              "grew \(held) → \(h.frame.height), offset \(o) → \(sc.offset()), next question at \(before) → \(after) in view")
    } else { check("inline: the page above is found", false) }

    // ── not one connection: the loopback probe, every fetch vector pointed at 127.0.0.1, with no click ──
    final class Listener {
        private var l: NWListener?
        private(set) var connections = 0, paths: [String] = []
        private(set) var port: UInt16 = 0
        func start() -> Bool {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
            guard let l = try? NWListener(using: params) else { return false }
            l.newConnectionHandler = { [weak self] c in
                self?.connections += 1
                c.start(queue: .main)
                c.receive(minimumIncompleteLength: 1, maximumLength: 2048) { d, _, _, _ in
                    if let d, let s = String(data: d, encoding: .utf8) {
                        let parts = s.prefix { $0 != "\r" && $0 != "\n" }.split(separator: " ")
                        if parts.count >= 2 { self?.paths.append(String(parts[1].dropFirst())) }
                    }
                    c.cancel()
                }
            }
            var ready = false
            l.stateUpdateHandler = { if case .ready = $0 { ready = true } }
            l.start(queue: .main)
            spinUntil(5) { ready }
            port = l.port?.rawValue ?? 0
            self.l = l
            return ready && port != 0
        }
        func stop() { l?.cancel(); l = nil }
    }
    func probe(_ port: UInt16) -> String {
        let u = { (t: String) in "http://127.0.0.1:\(port)/\(t)" }
        return """
        <!doctype html><html><head><title>probe</title>
        <link rel="stylesheet" href="\(u("css-link"))"><link rel="preload" as="image" href="\(u("preload"))">
        <link rel="preconnect" href="\(u("preconnect"))"><meta http-equiv="refresh" content="1;url=\(u("refresh"))">
        <style>@import url("\(u("css-import"))"); @font-face { font-family: F; src: url("\(u("font"))"); }
        body { font-family: F; background: url("\(u("css-url"))"); }</style><script>document.title = 'js'</script></head>
        <body><p>probe page</p><img src="\(u("img"))"><img srcset="\(u("srcset")) 1x">
        <svg width="20" height="20"><image href="\(u("svg-image"))" width="20" height="20"></image></svg>
        <iframe src="\(u("iframe"))"></iframe><object data="\(u("object"))"></object>
        <video src="\(u("video"))" preload="auto"></video><audio src="\(u("audio"))" preload="auto"></audio>
        <video><source src="\(u("source"))"></video><a href="\(u("href"))" ping="\(u("ping"))">link</a></body></html>
        """
    }
    func run(rules: Bool) -> (connections: Int, paths: [String], title: String?) {
        let lb = Listener()
        guard lb.start() else { check("inline probe: a listener on 127.0.0.1 started", false); return (-1, [], nil) }
        defer { lb.stop() }
        QCHTMLPreview.addRules = rules
        defer { QCHTMLPreview.addRules = true }
        pages.forgetAll()
        let html = probe(lb.port)
        m.turns = [turn("Probe:\n```html\n\(html)\n```")]; m.scrollTick += 1; spin(0.3); settle()
        spin(2.5)                                          // the meta refresh (1 s) and anything late
        var title: String?
        if let v = hosts().first?.page {
            var out: Any??
            v.evaluateJavaScript("document.title", in: nil, in: .page) { r in out = .some(try? r.get()) }
            spinUntil(5) { out != nil }
            title = (out ?? nil) as? String
        }
        let live = hosts().first?.state == .live
        m.turns = []; spin(0.3); settle()
        return (live ? lb.connections : -1, lb.paths, title)
    }
    let open = run(rules: false)
    check("inline probe: with the rules left out the listener does see requests (so the probe would see a lost rule list)",
          open.connections > 0 && ["css-import", "css-link"].allSatisfy(open.paths.contains), "\(open.connections) \(open.paths)")
    let sealed = run(rules: true)
    check("inline probe: an inline page sends not one connection to 127.0.0.1 (css url, @import, @font-face, link, preload, preconnect, img, srcset, svg image, iframe, object, video, audio, source, meta refresh, a ping), with no click",
          sealed.connections == 0, "\(sealed.connections) \(sealed.paths)")
    check("inline probe: the page's own script did not run", sealed.title == "probe", "\(String(describing: sealed.title))")

    // ── a rule list that can't be compiled: the block stays code and says so ──
    let goodRules = QCHTMLPreview.encodedRules
    QCHTMLPreview.encodedRules = "not rules"
    show(["Here:\n```html\n<p>unsafe sample</p>\n```"])
    check("inline: when the rules don't compile, the block shows its code and no web view is made", hosts().isEmpty && pages.alive == 0, "\(hosts().count) \(pages.alive)")
    QCHTMLPreview.encodedRules = goodRules

    // ── a new chat lets go of every page: no web view, no memo of its pages ──
    show(["Here:\n```html\n\(short)\n```"])
    m.newChat(); spin(0.3); settle()
    check("inline: a new chat leaves no web view and no memo of the old pages (memory only, nothing kept)", pages.alive == 0 && pages.memos.isEmpty && hosts().isEmpty,
          "\(pages.alive) \(pages.memos.count)")
    check("inline: never more than one page web view at once, in this whole section", pages.mostAlive <= 1, "\(pages.mostAlive)")
    chat.hide(); spin(0.2)
}
