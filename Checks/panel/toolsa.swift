// The chat tools of branch chat-tools-a, in the real chat panel (ordered in invisible, off every screen): ↑ recalls the
// user's earlier messages in the empty field. (Copy the chat as Markdown and Read aloud add their checks below.) No mouse,
// no posted event; the pasteboard is a check's own, never the operator's.
//   (called from Checks/panel/main.swift)

import AppKit
import Carbon.HIToolbox

// ── ↑ recalls your last message ──────────────────────────────────────────────────────────────────────────────────────────
func recallChecks() {
    guard let p = panel() else { check("recall: the panel is there", false); return }
    let m = chat.model
    func done(_ q: String, images: [QCImage] = []) -> QuickChatTurn {
        var t = QuickChatTurn(question: q, images: images, answer: "answer to " + q, model: "Haiku 5.5")
        t.phase = .done; t.seconds = 1
        return t
    }
    m.newChat(); m.field = ""
    m.turns = [done("first"), done(""), done("second"), done("second"), done("third\nwith two lines")]
    chat.open(); spin(0.3)
    guard let tv = p.firstResponder as? NSTextView, let d = tv.delegate else { check("recall: the field has the keyboard", false, "\(String(describing: p.firstResponder))"); return }
    // the arrow keys as the field's text system hands them to its delegate (⇧ ⌥ ⌘ arrows are other selectors)
    func arrow(_ up: Bool) -> Bool { d.textView?(tv, doCommandBy: up ? #selector(NSResponder.moveUp(_:)) : #selector(NSResponder.moveDown(_:))) ?? false }
    func end(_ s: String) -> Bool { m.field == s && tv.string == s && tv.selectedRange() == NSRange(location: (s as NSString).length, length: 0) }

    check("recall: the questions of a chat, one that is empty or a repeat of the one before left out",
          QCRecall.start(["a", "", "a", "a", "b"])?.messages == ["a", "b"] && QCRecall.start(["a", "", "a", "a", "b"])?.shown == "b"
          && QCRecall.start(["", ""]) == nil && QCRecall.start([]) == nil)
    check("recall: ↓ in an empty field is the caret's (not taken), the field stays empty", !arrow(false) && m.field.isEmpty && m.recall == nil)
    check("recall: ↑ in an empty field puts the last message in it, the caret at the end", arrow(true) && end("third\nwith two lines"), "\(m.field) \(tv.selectedRange())")
    check("recall: ↑ again goes further back", arrow(true) && end("second") && arrow(true) && end("first"))
    check("recall: ↑ at the oldest is taken and stays there", arrow(true) && end("first"))
    check("recall: ↓ goes forward", arrow(false) && end("second") && arrow(false) && end("third\nwith two lines"))
    check("recall: ↓ past the newest is empty again (taken), and then it is the caret's", arrow(false) && end("") && !arrow(false) && m.recall == nil)
    check("recall: ↑ starts over from the newest", arrow(true) && end("third\nwith two lines"))
    // an edit ends it: ↑ and ↓ are the caret's again
    m.field = "third\nwith two lines!"; spin(0.1)
    check("recall: once the recalled text is edited ↑ and ↓ are normal caret keys (not taken, text untouched)",
          !arrow(true) && !arrow(false) && m.field == "third\nwith two lines!" && m.recall?.shown != m.field)
    // text typed from nothing is not a recall either
    m.field = ""; spin(0.1)
    m.field = "x"; spin(0.1)
    check("recall: a field with something typed in it is not recalled over", !arrow(true) && m.field == "x")
    // marked text (an input method's composition, Dictation's provisional words): the arrows are the composition's
    m.field = ""; tv.string = ""; spin(0.1)
    tv.setMarkedText("k", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    check("recall: with marked text in the field ↑ is not taken", tv.hasMarkedText() && !arrow(true) && m.field != "third\nwith two lines")
    tv.unmarkText(); tv.string = ""; m.field = ""; spin(0.1)
    // a send starts over, and a new chat has nothing to recall
    check("recall: ↑ after clearing the field recalls again", arrow(true) && end("third\nwith two lines"))
    m.newChat(); spin(0.2)
    check("recall: a new chat starts empty: ↑ recalls nothing and the field stays empty", m.field.isEmpty && m.recall == nil && !arrow(true) && m.field.isEmpty)
    // attachments alone are not recalled (text only)
    m.turns = [done("", images: [])]
    check("recall: a chat with no message text has nothing to recall", !arrow(true) && m.field.isEmpty)
    // the keys list
    let rows = QCKeysView.pages(opener: "⌃⇧Space").first { $0.page == .write }?.rows.map { $0.0 + " " + $0.1 } ?? []
    check("recall: the keys list's Write page names ↑ (empty field)", rows.contains("↑ (empty field) Your earlier messages"), rows.joined(separator: "\n"))
    m.newChat(); chat.hide(); spin(0.2)
}
