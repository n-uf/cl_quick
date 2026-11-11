// The "Ask cl_quick" Services entry's checks (Checks/service.sh): the provider's handler is called directly, the way
// macOS calls it, with a private pasteboard that holds the selection. The real panel opens quietly (Checks/quiet.swift:
// off every screen, click-through, never the keyboard, read-only: nothing is written under the user's folders).

import AppKit

Files.readOnly = true
let app = NSApplication.shared
CheckQuiet.start()
let chat = QuickChat.shared
chat.start()
// no real `claude`: opening the panel would start one on the user's own profile (QuickChatModel.warm) and ask its usage
chat.model.resolveClaude = { $0(nil) }

var failed = 0, passed = 0
func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    if ok { passed += 1 } else { failed += 1; print("FAIL \(name) \(detail())") }
}
func spin(_ s: TimeInterval = 0.4) { RunLoop.current.run(until: Date().addingTimeInterval(s)); CheckQuiet.verify("after a spin") }
func panel() -> QuickChatPanel? { NSApp.windows.compactMap { $0 as? QuickChatPanel }.first }
func fieldView() -> QCTextView? {
    var found: QCTextView?
    func walk(_ v: NSView) { if found == nil { if let t = v as? QCTextView { found = t } else { v.subviews.forEach(walk) } } }
    if let c = panel()?.contentView { walk(c) }
    return found
}

let m = chat.model
let provider = QCServiceProvider.shared
/// The handler, as macOS calls it: a pasteboard of its own (not the general one) holding the text; the error string it may set.
func service(_ text: String?) -> String? {
    let pb = NSPasteboard.withUniqueName()
    pb.clearContents()
    if let text { pb.setString(text, forType: .string) }
    var err: NSString = ""
    provider.askAboutSelection(pb, userData: "", error: &err)
    pb.releaseGlobally()
    return err.length > 0 ? err as String : nil
}
func reset() { chat.hide(); m.newChat(); m.dictationNote = nil; m.field = ""; spin(0.2) }
func quiet(_ label: String, turns: Int = 0) {
    guard let p = panel() else { check("\(label): the panel exists", false); return }
    let screens = NSScreen.screens.map(\.frame)
    check("\(label): the panel is shown by the quiet path (ordered in, off every screen, not the key window)",
          p.isVisible && !screens.contains { $0.intersects(p.frame) } && !NSApp.isActive && NSApp.keyWindow == nil,
          "visible \(p.isVisible) frame \(p.frame)")
    check("\(label): nothing was sent (no new turn, nothing busy)", m.turns.count == turns && !m.busy)
}

// ── the format (pure) ─────────────────────────────────────────────────────────────────────────────
typealias S = QCServiceProvider
check("format: a line becomes a quote, a blank line and the caret's place", S.field(existing: "", selection: "hello").text == "> hello\n\n")
check("format: every line is quoted, blank lines as a bare >", S.field(existing: "", selection: "a\n\nb\r\nc").text == "> a\n>\n> b\n> c\n\n",
      S.field(existing: "", selection: "a\n\nb\r\nc").text.debugDescription)
check("format: the selection's outer whitespace goes, its indentation inside stays", S.field(existing: "", selection: "\n\n  x\n    y  \n\n").text == "> x\n>     y\n\n",
      S.field(existing: "", selection: "\n\n  x\n    y  \n\n").text.debugDescription)
check("format: a blank selection changes nothing", S.field(existing: "keep", selection: " \n\t ").text == "keep" && S.field(existing: "", selection: "").text == "")
check("format: text in the field stays, the quote comes after a blank line",
      S.field(existing: "why?\n", selection: "x").text == "why?\n\n> x\n\n", S.field(existing: "why?\n", selection: "x").text.debugDescription)
check("format: a field of only whitespace counts as empty", S.field(existing: "  \n", selection: "x").text == "> x\n\n")
let longText = String(repeating: "ab", count: 15_000)
let capped = S.field(existing: "", selection: longText)
check("format: the cap is \(S.cap) characters of the selection", capped.cut && capped.text == "> " + String(longText.prefix(S.cap)) + "\n\n", "\(capped.text.count)")
check("format: exactly the cap is not cut", !S.field(existing: "", selection: String(repeating: "x", count: S.cap)).cut)

// ── the handler, with the panel ───────────────────────────────────────────────────────────────────
reset()
check("start: the panel is not shown", !chat.isOpen)
let e1 = service("Hello\nworld")
spin(0.8)
check("handler: no error", e1 == nil, "\(e1 ?? "")")
check("handler: the bar opens", chat.isOpen && panel() != nil)
check("handler: the field holds the quoted selection, ready to edit", m.field == "> Hello\n> world\n\n", m.field.debugDescription)
quiet("handler")
if let tv = fieldView() {
    check("handler: the text view shows it, the caret after it", tv.string == m.field && tv.selectedRange() == NSRange(location: (m.field as NSString).length, length: 0),
          "\(tv.string.debugDescription) \(tv.selectedRange())")
} else { check("handler: the field's text view is drawn", false) }
check("handler: no note for a selection that fits", m.dictationNote == nil)

// the field has text: the quote comes after it, a blank line between
m.field = "what does this mean?"
spin(0.2)
_ = service("second one")
spin(0.4)
check("append: the typed text stays, the quote follows after a blank line", m.field == "what does this mean?\n\n> second one\n\n", m.field.debugDescription)
check("append: the chat is the same, nothing sent", m.turns.isEmpty && !m.busy)
quiet("append")

// a hidden bar comes back with the quote; an open chat (turns on screen) stays the same chat
reset()
var t = QuickChatTurn(question: "q", answer: "a", model: "Haiku 5.5"); t.phase = .done
m.turns = [t]
_ = service("from the other app")
spin(0.5)
check("chat: the answer on screen stays (not a new chat), the quote is in its reply field", m.turns.count == 1 && m.field == "> from the other app\n\n", "\(m.turns.count) \(m.field.debugDescription)")
check("chat: nothing was sent (still one turn, nothing busy)", m.turns.count == 1 && !m.busy)
quiet("chat", turns: 1)

// a chat that ended while away: it is gone, the bar is fresh and holds the quote
reset()
m.turns = [t]; m.ended = .idle
chat.hide()
_ = service("after the end")
spin(0.5)
check("ended: the dead chat goes, the quote is in the field", m.turns.isEmpty && m.ended == nil && m.field == "> after the end\n\n", "\(m.turns.count) \(m.field.debugDescription)")

// the cap, with its note
reset()
_ = service(longText)
spin(0.5)
check("cap: the field holds the first \(S.cap) characters, quoted", m.field == "> " + String(longText.prefix(S.cap)) + "\n\n", "\(m.field.count)")
check("cap: a one-line note says so", m.dictationNote == S.capNote, "\(m.dictationNote ?? "nil")")
check("cap: nothing was sent", m.turns.isEmpty && !m.busy)
_ = service("short")
spin(0.3)
check("cap: the next selection that fits takes the note away", m.dictationNote == nil)
quiet("cap")

// a pasteboard with no text: an error for macOS to say, the field untouched
reset()
m.field = "typed"
let e2 = service(nil)
check("no text: the handler sets an error", e2 != nil, "\(e2 ?? "nil")")
check("no text: the field is untouched", m.field == "typed")
// a blank selection opens the bar and changes nothing
_ = service("  \n ")
spin(0.3)
check("blank: the bar is open, the field untouched", chat.isOpen && m.field == "typed", m.field.debugDescription)

// the selection is not kept: the general pasteboard was never touched by the handler
let general = NSPasteboard.general.changeCount
_ = service("private words")
check("nothing kept: the general pasteboard is untouched", NSPasteboard.general.changeCount == general)

reset()
CheckQuiet.verify("at the end")
print(failed == 0 ? "service checks: \(passed)/\(passed) passed" : "service checks: \(failed) failed, \(passed) passed")
exit(failed == 0 ? 0 : 1)
