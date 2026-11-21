// A fenced `html` block in an answer can be looked at: its Preview control opens the block's text as a web page in one
// reusable window. The answer itself never draws HTML (it stays Markdown and text); the page is a separate, isolated
// document, as Claude Code treats HTML. Every setting that isolates it, all in place before the first load (and the
// loopback probe in Checks/panel sees whether the whole still keeps every vector off the network):
//   - a non-persistent website data store (nothing is stored on the Mac);
//   - JavaScript off (`allowsContentJavaScript`, also set again in every navigation's preferences);
//   - Safe Browsing off (`isFraudulentWebsiteWarningEnabled`): it asks a service about a URL before the delegate is asked;
//   - link previews off (`allowsLinkPreview`): a force-click would open a Quick Look popover loading the real page;
//   - a content rule list that blocks every load (url-filter ".*"), compiled once per run in a temporary folder that is
//     removed at once (stale ones are swept at launch) and added before the page is loaded; when it can't be compiled
//     nothing is loaded and the window says so;
//   - `loadHTMLString(_, baseURL: nil)`; a navigation delegate that allows that one load and cancels every other
//     navigation (a clicked link, a redirect, a meta refresh, a frame opens nothing), no new windows, and any download
//     WebKit begins anyway is cancelled at once;
//   - a user script of ours (in its own world, not switched off with the page's JavaScript) that cancels every click,
//     auxclick, submit and Enter, with no test of the target: WebKit connects to a link's host, and sends an <a ping>,
//     before the delegate is asked (HTML, SVG and MathML links and links in shadow roots alike);
//   - the right-click menu keeps only its Copy items, without Services (Download Linked File / Image / Media start a
//     download without asking the delegate or the rules; the Open items navigate); Quick Look is a no-op; nothing can
//     be dropped on the page (no dragged types).
// The window opens beside the chat panel (floating when there is no room, so the floating panel can't hide it; it then
// hides when cl_quick isn't the active app). Rule lists compile under `<tmp>/<bundle id>/preview-rules`. The web
// view exists only from a press on Preview to the window's closing; closing releases the window and the view.

import AppKit
import SwiftUI
import WebKit

final class QCHTMLPreview: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    static let shared = QCHTMLPreview()
    /// Checks turn it off: the window is built and loaded but never ordered in, and cl_quick isn't activated.
    static var reveal = true
    /// Checks: each step of a load, in order ("compile", "add rules", "load"), and when it finished or failed.
    var trace: (String) -> Void = { _ in }

    private(set) var window: NSWindow?
    private(set) var page: WKWebView?
    /// The next main-frame navigation is the initial load of our own HTML; set just before `loadHTMLString`.
    private(set) var allowInitialLoad = false
    private var generation = 0

    /// "html" or "htm", in any case: the code blocks that get the control.
    static func isHTML(_ language: String) -> Bool {
        ["html", "htm"].contains(language.trimmingCharacters(in: .whitespaces).lowercased())
    }

    /// Blocks every load: images, styles, scripts, frames, fonts, anything with a URL.
    static let blockAll = #"[{"trigger":{"url-filter":".*"},"action":{"type":"block"}}]"#
    static let ruleListName = "cl_quick.preview.block-all"
    /// What gets compiled: `blockAll`. A check sets another to see a rule list that can't be compiled.
    static var encodedRules = blockAll
    /// Checks only: false leaves the rules out, to see that the network probe notices (never false in the app).
    static var addRules = true
    /// Checks only: false leaves the click guard out (never false in the app).
    static var addGuard = true
    /// Capturing listeners on the window that cancel EVERY click and auxclick, with no test of the target (an HTML, SVG or
    /// MathML link, or one inside a shadow root, which retargets the event to its host, all have the click as their
    /// default action: the link's ping and WebKit's preconnect start from it), every form submit, and every Enter key (an
    /// input's implicit submit: a submit inside a shadow root never reaches the window, and a closed root hides its input
    /// from the event's path, so the key can't be told by its target). Selecting and copying text are neither. It sets
    /// `window.__qcGuard` in its own world, which a check reads.
    static let guardScript = """
    (function () {
      window.__qcGuard = 1;
      var stop = function (e) { e.preventDefault(); e.stopImmediatePropagation(); };
      window.addEventListener('click', stop, true);
      window.addEventListener('auxclick', stop, true);
      window.addEventListener('submit', stop, true);
      ['keydown', 'keypress'].forEach(function (k) {
        window.addEventListener(k, function (e) { if (e.key === 'Enter') stop(e); }, true);
      });
    })();
    """

    /// Preview pressed: the window (made on the first press) shows `html` as a page, replacing what it showed.
    func show(_ html: String) {
        generation += 1
        let mine = generation
        let w = window ?? makeWindow()
        window = w
        if Self.reveal {
            if !w.isVisible { place(w) }
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
        }
        dropWebView()
        trace("compile")
        Self.withRules { [weak self] list in
            guard let self, self.generation == mine, let w = self.window else { return }     // closed or replaced meanwhile
            guard let list else { return self.failed(w, "The preview can't be made safe, so it isn't shown.") }
            let view = Self.makeWebView(rules: list, trace: self.trace)
            view.navigationDelegate = self
            view.uiDelegate = self
            self.page = view
            view.frame = NSRect(origin: .zero, size: w.contentLayoutRect.size)
            view.autoresizingMask = [.width, .height]
            w.contentView = view
            self.allowInitialLoad = true
            self.trace("load")
            view.loadHTMLString(html, baseURL: nil)
        }
    }

    // MARK: the rule list

    /// The compiled list, kept for the run: compiled once, for the encoded rules it was made from.
    private static var compiled: (rules: String, list: WKContentRuleList)?
    private static var compiling = false
    private static var waiting: [(WKContentRuleList?) -> Void] = []
    /// Checks: how many lists were compiled, and the folders they were compiled in (each removed as soon as it was done).
    private(set) static var compiles = 0
    private(set) static var compileFolders: [URL] = []
    /// Where lists are compiled: a parent of our own under the temporary folder (`<tmp>/<bundle id>/preview-rules`), one
    /// folder per compile. Nothing outside it is ever touched.
    static var rulesParent: URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "local.n-uf.cl-quick", isDirectory: true)
            .appendingPathComponent("preview-rules", isDirectory: true)
    }

    /// The block-all list: the one compiled before, or a new one (main thread; `done` gets nil when it can't be compiled).
    static func withRules(_ done: @escaping (WKContentRuleList?) -> Void) {
        let encoded = encodedRules
        if let c = compiled, c.rules == encoded { return done(c.list) }
        waiting.append(done)
        guard !compiling else { return }
        compiling = true
        compiles += 1
        try? FileManager.default.createDirectory(at: rulesParent, withIntermediateDirectories: true)
        let folder = rulesParent.appendingPathComponent(UUID().uuidString, isDirectory: true)
        compileFolders.append(folder)
        func finish(_ list: WKContentRuleList?) {
            try? FileManager.default.removeItem(at: folder)          // the compiled list is in memory: nothing stays on disk
            if let list { compiled = (encoded, list) }
            compiling = false
            let all = waiting
            waiting = []
            for d in all { d(list) }
        }
        guard let store = WKContentRuleListStore(url: folder) else { return finish(nil) }
        store.compileContentRuleList(forIdentifier: ruleListName, encodedContentRuleList: encoded) { list, error in
            DispatchQueue.main.async { finish(error == nil ? list : nil) }
        }
    }

    /// Checks: the next press compiles again.
    static func forgetCompiledRules() { compiled = nil }

    /// At launch: folders a crash left behind (one is made only while a list compiles) go. Only inside `dir` (our own
    /// parent), and not the ones younger than `age` seconds: a second instance may be compiling in one right now.
    static func sweepStaleFolders(in dir: URL = rulesParent, olderThan age: TimeInterval = 60) {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        for n in names {
            let url = dir.appendingPathComponent(n)
            let made = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date ?? .distantPast
            if Date().timeIntervalSince(made) >= age { try? fm.removeItem(at: url) }
        }
    }

    /// A web view with the isolation set and the block-all rules added; nothing is loaded yet.
    static func makeWebView(rules: WKContentRuleList, trace: (String) -> Void = { _ in }) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        // Safe Browsing asks Google/Apple about a navigation's URL before the delegate is asked: no lookups
        config.preferences.isFraudulentWebsiteWarningEnabled = false
        if addRules {
            config.userContentController.add(rules)
            trace("add rules")
        }
        // a click on a link (or an <area>) is stopped before WebKit acts on it: WebKit opens a connection to the link's host
        // ahead of asking the delegate, and sends an <a ping> beforehand, whatever the rules and the policy then say. This
        // runs in a world of our own, which the JavaScript switch above (the page's scripts) doesn't turn off.
        if addGuard {
            config.userContentController.addUserScript(WKUserScript(source: guardScript, injectionTime: .atDocumentStart,
                                                                      forMainFrameOnly: false, in: .defaultClient))
        }
        let view = QCPreviewWebView(frame: .zero, configuration: config)
        // on by default on macOS: a force-click on a link would open a Quick Look popover that loads the real page, outside
        // every rule above
        view.allowsLinkPreview = false
        return view
    }

    /// Where a window `size` big goes beside the chat panel on the screen's visible frame: to its right, else to its left,
    /// top lines aligned (kept on the screen), `gap` apart. With no room on either side it is centred and `floating`, so the
    /// floating chat panel never hides it; with no panel showing it is just centred.
    static func placement(panel: NSRect?, screen: NSRect, size: NSSize, gap: CGFloat = 12) -> (origin: NSPoint, floating: Bool) {
        let centred = NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
        guard let p = panel else { return (centred, false) }
        let y = min(max(p.maxY - size.height, screen.minY), max(screen.maxY - size.height, screen.minY))
        if p.maxX + gap + size.width <= screen.maxX { return (NSPoint(x: p.maxX + gap, y: y), false) }
        if p.minX - gap - size.width >= screen.minX { return (NSPoint(x: p.minX - gap - size.width, y: y), false) }
        return (centred, true)
    }

    /// The window opens beside the chat panel, not behind it.
    private func place(_ w: NSWindow) {
        let panel = NSApp.windows.compactMap { $0 as? QuickChatPanel }.first { $0.isVisible }
        guard let screen = (panel?.screen ?? NSScreen.main)?.visibleFrame else { return }
        let r = Self.placement(panel: panel?.frame, screen: screen, size: w.frame.size)
        w.setFrameOrigin(r.origin)
        w.level = r.floating ? .floating : .normal
        w.hidesOnDeactivate = r.floating          // floating over every app would stay on top of the one in use
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = "Preview"
        w.isReleasedWhenClosed = false          // we own it: closing must not free it under a call still on the stack
        w.delegate = self
        w.minSize = NSSize(width: 320, height: 240)
        w.center()
        return w
    }

    private func failed(_ w: NSWindow, _ text: String) {
        trace("failed")
        let label = NSTextField(wrappingLabelWithString: text)
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        w.contentView = label
    }

    /// The page and its view let go: no navigation, no delegate, nothing left running.
    private func dropWebView() {
        allowInitialLoad = false
        if let v = page {
            v.stopLoading()
            v.navigationDelegate = nil
            v.uiDelegate = nil
            v.removeFromSuperview()
        }
        page = nil
        window?.contentView = nil
    }

    func windowWillClose(_ notification: Notification) { close() }

    /// The window closed (or a check closes it): the web view, then the window, are released.
    func close() {
        generation += 1                              // a rule list still compiling finds nobody to show it
        dropWebView()
        let w = window
        window = nil
        w?.delegate = nil
        w?.orderOut(nil)
    }

    // MARK: navigation

    /// Allows the initial load of our HTML once, in the main frame; cancels everything else (a click on a link, a
    /// redirect, a frame, a form, a script's navigation).
    /// (Plain values, so a check can ask without WebKit's own action objects.)
    func decide(isMainFrame: Bool, type: WKNavigationType, download: Bool) -> WKNavigationActionPolicy {
        guard allowInitialLoad, isMainFrame, type == .other, !download else { return .cancel }
        allowInitialLoad = false
        return .allow
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences,
                 decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        preferences.allowsContentJavaScript = false
        let policy = decide(isMainFrame: navigationAction.targetFrame?.isMainFrame ?? false, type: navigationAction.navigationType,
                            download: navigationAction.shouldPerformDownload)
        // the step the checks read: "decide <navigation type> <path> allow|cancel"
        trace("decide \(navigationAction.navigationType.rawValue) \(navigationAction.request.url?.path ?? "-") \(policy == .allow ? "allow" : "cancel")")
        decisionHandler(policy, preferences)
    }

    /// Never a download, and nothing that isn't a page.
    static func responsePolicy(canShow: Bool) -> WKNavigationResponsePolicy { canShow ? .allow : .cancel }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(Self.responsePolicy(canShow: navigationResponse.canShowMIMEType))
    }

    /// A download that was begun anyway (never by our policy, which cancels what asks for one): stopped at once.
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = nil
        download.cancel(nil)
        trace("download cancelled")
    }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = nil
        download.cancel(nil)
        trace("download cancelled")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { trace("finished") }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { trace("failed load") }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { trace("failed load") }

    /// No new windows, whatever asks (target=_blank, window.open).
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
}

/// The web view of the preview. Its right-click menu has "Download Linked File", "Download Image" and "Download Media",
/// which start a download inside WebKit without asking the navigation delegate or the content rules, and the "Open …"
/// items, which navigate or open windows: only the Copy items stay.
final class QCPreviewWebView: WKWebView {
    /// The identifiers (WebKit's WKMenuItemIdentifier…) of the items that stay.
    static let keptMenuItems: Set<String> = ["WKMenuItemIdentifierCopy", "WKMenuItemIdentifierCopyImage",
                                             "WKMenuItemIdentifierCopyLink", "WKMenuItemIdentifierCopyMediaLink"]

    override init(frame: NSRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        unregisterDraggedTypes()          // nothing is dropped on the page (a dropped link or file would navigate to it)
    }
    required init?(coder: NSCoder) { fatalError("not from a nib") }
    override func registerForDraggedTypes(_ newTypes: [NSPasteboard.PasteboardType]) {}

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        Self.filter(menu)
    }

    /// Quick Look on a force-click (or the three-finger tap) is a link preview by another route: nothing.
    override func quickLook(with event: NSEvent) {}

    /// Takes every item but the kept ones out, then the separators left first, last or doubled; no Services submenu.
    static func filter(_ menu: NSMenu) {
        menu.allowsContextMenuPlugIns = false
        for item in menu.items where !item.isSeparatorItem {
            if !(item.identifier.map { keptMenuItems.contains($0.rawValue) } ?? false) { menu.removeItem(item) }
        }
        var i = 0
        while i < menu.items.count {
            let sep = menu.items[i].isSeparatorItem
            if sep && (i == 0 || menu.items[i - 1].isSeparatorItem) { menu.removeItem(at: i) } else { i += 1 }
        }
        while let last = menu.items.last, last.isSeparatorItem { menu.removeItem(last) }
    }
}

/// The compact "Preview" control in an html block's top row, beside Copy: the language label's size, Copy's 24 pt height
/// and hover.
struct QCPreviewButton: View {
    let html: String
    @State private var hover = false
    var body: some View {
        Button { QCHTMLPreview.shared.show(html) } label: {
            Text("Preview").font(.system(size: 11.5, weight: .medium))
                .padding(.horizontal, 8)
                .frame(height: QCSpace.small)
                .foregroundColor(hover ? QCColor.text : QCColor.muted)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hover ? QCColor.hover : .clear))
                .qcControl()
        }
        .buttonStyle(.plain).help("Preview this HTML in a window").onHover { hover = $0 }
        .qcMark("preview")
        .accessibilityLabel("Preview HTML")
    }
}
