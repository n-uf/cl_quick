// A fenced `html` block in an answer can be looked at: its Preview control opens the block's text as a web page in one
// reusable window. The answer itself never draws HTML (it stays Markdown and text); the page is a separate, isolated
// document, as Claude Code treats HTML. Isolation, all of it set before the first load:
//   - a non-persistent website data store (nothing is stored on the Mac), JavaScript off;
//   - a content rule list that blocks every load (url-filter ".*"), compiled before the page is loaded; when it can't
//     be compiled nothing is loaded and the window says so;
//   - `loadHTMLString(_, baseURL: nil)`; a navigation delegate that allows that one load and cancels every other
//     navigation (a clicked link opens nothing), no new windows, no downloads.
// The web view exists only from a press on Preview to the window's closing; closing releases the window and the view.

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
    /// The folders the rule list was compiled in (under the temporary folder); removed when the window closes.
    private(set) var storeFolders: [URL] = []

    /// "html" or "htm", in any case: the code blocks that get the control.
    static func isHTML(_ language: String) -> Bool {
        ["html", "htm"].contains(language.trimmingCharacters(in: .whitespaces).lowercased())
    }

    /// Blocks every load: images, styles, scripts, frames, fonts, anything with a URL.
    static let blockAll = #"[{"trigger":{"url-filter":".*"},"action":{"type":"block"}}]"#
    static let ruleListName = "cl_quick.preview.block-all"
    /// What gets compiled: `blockAll`. A check sets another to see a rule list that can't be compiled.
    static var encodedRules = blockAll

    /// Preview pressed: the window (made on the first press) shows `html` as a page, replacing what it showed.
    func show(_ html: String) {
        generation += 1
        let mine = generation
        let w = window ?? makeWindow()
        window = w
        if Self.reveal {
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
        }
        dropWebView()
        trace("compile")
        let folder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cl_quick-preview-\(UUID().uuidString)", isDirectory: true)
        storeFolders.append(folder)
        guard let store = WKContentRuleListStore(url: folder) else { return failed(w, "The preview can't be made safe, so it isn't shown.") }
        store.compileContentRuleList(forIdentifier: Self.ruleListName, encodedContentRuleList: Self.encodedRules) { [weak self] list, error in
            DispatchQueue.main.async {
                guard let self, self.generation == mine, let w = self.window else { return }     // closed or replaced meanwhile
                guard let list, error == nil else { return self.failed(w, "The preview can't be made safe, so it isn't shown.") }
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
    }

    /// A web view with the isolation set and the block-all rules added; nothing is loaded yet.
    static func makeWebView(rules: WKContentRuleList, trace: (String) -> Void = { _ in }) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.userContentController.add(rules)
        trace("add rules")
        let view = WKWebView(frame: .zero, configuration: config)
        // on by default on macOS: a force-click on a link would open a Quick Look popover that loads the real page, outside
        // every rule above
        view.allowsLinkPreview = false
        return view
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
        let folders = storeFolders
        storeFolders = []
        // after the close notification has returned
        DispatchQueue.main.async { for f in folders { try? FileManager.default.removeItem(at: f) } }
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
        decisionHandler(decide(isMainFrame: navigationAction.targetFrame?.isMainFrame ?? false, type: navigationAction.navigationType,
                               download: navigationAction.shouldPerformDownload), preferences)
    }

    /// Never a download, and nothing that isn't a page.
    static func responsePolicy(canShow: Bool) -> WKNavigationResponsePolicy { canShow ? .allow : .cancel }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(Self.responsePolicy(canShow: navigationResponse.canShowMIMEType))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { trace("finished") }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { trace("failed load") }

    /// No new windows, whatever asks (target=_blank, window.open).
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
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
