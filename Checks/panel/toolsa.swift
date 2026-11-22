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

// ── ⌥⇧⌘C and the answers' menu: the whole chat as Markdown through QCCopy.board ─────────────────────────────────────────────
func chatCopyChecks() {
    guard let p = panel() else { check("chat copy: the panel is there", false); return }
    let m = chat.model
    let board = NSPasteboard(name: NSPasteboard.Name("cl-quick-chatcopy-check-\(ProcessInfo.processInfo.processIdentifier)"))
    let realBoard = QCCopy.board
    QCCopy.board = board
    defer { board.releaseGlobally(); QCCopy.board = realBoard }
    func key(_ flags: NSEvent.ModifierFlags, _ chars: String = "c") -> Bool {
        guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: p.windowNumber, context: nil,
                                       characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: UInt16(kVK_ANSI_C)) else { return false }
        return p.performKeyEquivalent(with: e)
    }
    func done(_ q: String, _ a: String) -> QuickChatTurn {
        var t = QuickChatTurn(question: q, answer: a, model: "Haiku 5.5")
        t.phase = .done; t.seconds = 1
        return t
    }
    m.newChat(); m.field = ""
    m.turns = [done("How do I list files?", "Use:\n\n```zsh\nls -la\n```"), done("And hidden ones?", "Those are in `ls -a`.")]
    chat.open(); spin(0.3)
    let want = "**You:**\n\nHow do I list files?\n\n**Claude:**\n\nUse:\n\n```zsh\nls -la\n```\n\n**You:**\n\nAnd hidden ones?\n\n**Claude:**\n\nThose are in `ls -a`."
    check("chat copy: the model's Markdown is each message and answer, code fences and languages kept", m.chatMarkdown == want, m.chatMarkdown)
    board.clearContents()
    check("chat copy: ⌥⇧⌘C is taken and puts the chat on the pasteboard it was given (QCCopy.board)",
          key([.command, .option, .shift], "Ç") && board.string(forType: .string) == want, "\(board.string(forType: .string) ?? "nil")")
    check("chat copy: it says Copied under the latest answer (no animation: the model's flag, then not)", m.copied == m.turns[1].id)
    spin(QuickChatModel.copiedFor + 0.3)
    check("chat copy: and the Copied goes by itself", m.copied == nil)
    // it is not the answer copy, nor another key
    board.clearContents(); board.setString("kept", forType: .string)
    check("chat copy: ⌥⌘C and ⌃⌥⇧⌘C are not the chat copy", !key([.command, .option]) && !key([.command, .option, .shift, .control]) && board.string(forType: .string) == "kept")
    let pbName = NSPasteboard.Name("cl-quick-chatcopy-answer-\(ProcessInfo.processInfo.processIdentifier)")
    let answers = NSPasteboard(name: pbName)
    let realPasteboard = m.pasteboard
    m.pasteboard = answers
    defer { answers.releaseGlobally(); m.pasteboard = realPasteboard }
    check("chat copy: ⇧⌘C is still the answer copy, not the chat's", key([.command, .shift], "C") && answers.string(forType: .string) == "Those are in `ls -a`."
          && board.string(forType: .string) == "kept")
    // the answers' menu item (the click's own answer says Copied)
    m.copied = nil
    check("chat copy: the menu item copies the chat and says Copied under the answer it was opened on",
          m.copyChat(feedbackOn: m.turns[0].id) && board.string(forType: .string) == want && m.copied == m.turns[0].id)
    // a failed message and a still streaming answer
    var failed = QuickChatTurn(question: "Again?"); failed.phase = .failed
    var live = QuickChatTurn(question: "More"); live.answer = "half an"; live.phase = .streaming
    m.turns = [done("Q1", "A1"), failed, live]
    check("chat copy: a failed message has no Claude part, a streaming answer has its text so far",
          m.chatMarkdown == "**You:**\n\nQ1\n\n**Claude:**\n\nA1\n\n**You:**\n\nAgain?\n\n**You:**\n\nMore\n\n**Claude:**\n\nhalf an")
    // an empty chat: the key is taken, nothing is copied
    m.newChat(); spin(0.2)
    board.clearContents(); board.setString("kept", forType: .string)
    check("chat copy: with no chat the key is taken and the pasteboard untouched", key([.command, .option, .shift], "Ç") && board.string(forType: .string) == "kept" && m.copied == nil)
    // the keys list
    let rows = QCKeysView.pages(opener: "⌃⇧Space").first { $0.page == .write }?.rows.map { $0.0 + " " + $0.1 } ?? []
    check("chat copy: the keys list's Write page names ⌥⇧⌘C", rows.contains("⌥⇧⌘C Copy the chat as Markdown"), rows.joined(separator: "\n"))
    chat.hide(); spin(0.2)
}

// ── read aloud: the speaker button's state (a check makes no sound: QCQuiet.on keeps the state and skips the voice) ──────────────
func readAloudChecks() {
    let m = chat.model
    let speech = QCSpeech.shared
    func done(_ q: String, _ a: String) -> QuickChatTurn {
        var t = QuickChatTurn(question: q, answer: a, model: "Haiku 5.5")
        t.phase = .done; t.seconds = 1
        return t
    }
    speech.stop()
    m.newChat(); m.field = ""
    m.turns = [done("one", "First **answer**."), done("two", "Second answer."), done("three", "")]
    chat.open(); spin(0.3)
    let a = m.turns[0].id, b = m.turns[1].id
    check("read aloud: the speaker is the last footer icon, after ↻, and only where there is text to read",
          QCTurnView.footerActions(above: true, last: true) == [.start, .copy, .again, .speak]
          && QCTurnView.footerActions(above: false, last: true, speak: !m.turns[2].answer.isEmpty) == [.copy, .again])
    check("read aloud: nothing is read at first", speech.reading == nil)
    speech.toggle(a, answer: m.turns[0].answer)
    check("read aloud: the button starts that answer (the stop glyph shows)", speech.reading == a)
    speech.toggle(b, answer: m.turns[1].answer)
    check("read aloud: another answer's button reads that one instead (only one at a time)", speech.reading == b)
    speech.toggle(b, answer: m.turns[1].answer)
    check("read aloud: the same button again stops it", speech.reading == nil)
    speech.toggle(a, answer: "---")
    check("read aloud: an answer with nothing to read does not start", speech.reading == nil)
    speech.toggle(a, answer: "```swift\nlet a = 1\n```")
    check("read aloud: a code block alone is read as \"code block\" (it starts)", speech.reading == a)
    // hiding the panel stops it
    chat.hide(); spin(0.2)
    check("read aloud: hiding the panel stops it", speech.reading == nil)
    chat.open(); spin(0.3)
    // a new chat stops it, and so does the answer starting again or going away
    speech.toggle(a, answer: m.turns[0].answer)
    m.newChat(); spin(0.2)
    check("read aloud: a new chat stops it", speech.reading == nil)
    m.turns = [done("one", "First answer."), done("two", "Second answer.")]
    speech.toggle(m.turns[0].id, answer: m.turns[0].answer)
    m.turns[0].phase = .waiting                  // Ask again begins an answer anew
    check("read aloud: the answer starting again stops it", speech.reading == nil)
    m.turns = [done("one", "First answer.")]
    speech.toggle(m.turns[0].id, answer: m.turns[0].answer)
    m.turns = []
    check("read aloud: the answer going away stops it", speech.reading == nil)
    // the voice follows the answer's language: the best installed for it, else the user's default (nil); never one of another language
    let en = QCSpeech.voice(for: "This is a plain English sentence about reading an answer aloud with the voice of the Mac.")
    let uk = QCSpeech.voice(for: "Це звичайне українське речення про те, як прочитати відповідь уголос голосом комп'ютера.")
    check("read aloud: an English answer gets an English voice (or the default), a Ukrainian one a Ukrainian voice (or the default)",
          (en == nil || en!.language.hasPrefix("en")) && (uk == nil || uk!.language.hasPrefix("uk")), "\(String(describing: en?.language)) \(String(describing: uk?.language))")
    check("read aloud: no text, no voice chosen", QCSpeech.voice(for: "") == nil)
    // the keys list needs no row: no key
    let rows = QCKeysView.rows(opener: "⌃⇧Space").map { $0.0 + " " + $0.1 }.joined(separator: "\n")
    check("read aloud: it has no key, so no row in the keys list", !rows.lowercased().contains("read") && !rows.lowercased().contains("aloud"), rows)
    speech.stop(); m.newChat(); chat.hide(); spin(0.2)
}
