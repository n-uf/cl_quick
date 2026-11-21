// The Custom instructions' checks that need the app (Checks/instructions.sh). Sample text only; a chat on the stand-in
// `claude` (Checks/stub-claude, under build/ only), nothing on any screen, nothing of this Mac's own written.
//   - stored with the other settings, read back, cut at 1,000 characters, an old file without the key reads as none;
//   - typing and pasting in the real text view stop at 1,000;
//   - the prompt a chat's `claude` is started with: an empty box leaves it as it was, the text comes after the fixed text
//     (web and no web);
//   - which chat takes which text: a new chat the current one, an open chat its own, and an open chat is never restarted
//     for it (same process, no "New chat" line); an empty bar takes it at once and replaces its idle `claude` silently;
//   - Remove cl_quick data… clears it everywhere it is held (the file goes to the Trash with the rest).

import AppKit
import SwiftUI

Files.readOnly = true
let app = NSApplication.shared
CheckQuiet.start()          // nothing on any screen, never the keyboard, never active (Checks/quiet.swift)
/// The user's clipboard: this suite never reads or writes it, and the last check says so.
let clipboardAtStart = NSPasteboard.general.changeCount

var failed = 0, passed = 0
func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    if ok { passed += 1 } else { failed += 1; print("FAIL \(name) \(detail())") }
}

// Nothing of this Mac's own: one sample profile in memory (readOnly keeps the store out of the file) on a sample folder.
let sampleFolder = ProcessInfo.processInfo.environment["QC_SAMPLE_DIR"] ?? NSTemporaryDirectory() + "cl_quick-instructions-checks-sample"
try? FileManager.default.createDirectory(atPath: sampleFolder, withIntermediateDirectories: true)
ProfileStore.shared.save([Profile(id: "main", name: "Main", folder: sampleFolder)])

let own = "Answer in Ukrainian unless I write in another language.\nPrefer tables when comparing things."
let lead = "\n\nThe user's own instructions:\n"

// MARK: what is stored

func decode(_ json: String) -> QuickChatSettings? { try? JSONDecoder().decode(QuickChatSettings.self, from: Data(json.utf8)) }
func json(_ o: [String: Any]) -> String { String(decoding: (try? JSONSerialization.data(withJSONObject: o)) ?? Data(), as: UTF8.self) }
check("stored: the box starts empty, and a file without the key reads as none",
      QuickChatSettings().instructions.isEmpty && decode("{}")?.instructions == "")
check("stored: an old settings file keeps its other settings and reads no instructions",
      decode(#"{"webLinks":false,"blurAddresses":false}"#).map { !$0.webLinks && !$0.blurAddresses && $0.instructions.isEmpty } == true)
check("stored: the text is read as written, lines and all", decode(json(["instructions": own]))?.instructions == own)
check("stored: a wrong type is none", decode(#"{"instructions":5}"#)?.instructions == "" && decode(#"{"instructions":null}"#)?.instructions == "")
check("stored: a file edited by hand past the cap is cut to 1,000",
      decode(json(["instructions": String(repeating: "a", count: 1500)]))?.instructions.count == 1000)
var saved = QuickChatSettings(); saved.instructions = own
let enc = (try? JSONEncoder().encode(saved)) ?? Data()
check("stored: it is written under its own key and read back whole",
      ((try? JSONSerialization.jsonObject(with: enc)) as? [String: Any])?["instructions"] as? String == own
      && (try? JSONDecoder().decode(QuickChatSettings.self, from: enc)) == saved)
check("stored: for the app, not per profile (a profile holds no instructions)",
      !String(decoding: (try? JSONEncoder().encode(Profile(id: "p", name: "P", folder: "~/.claude-sample"))) ?? Data(), as: UTF8.self).contains("instructions"))
check("stored: in settings.json, inside the folder Remove… moves to the Trash",
      Files.settings.lastPathComponent == "settings.json"
      // Paths, not URLs: a URL made for a folder that is not there yet (a fresh machine, the CI runner) has no trailing
      // slash, while the one cut from the file's URL has, and the two URLs then differ for the same folder.
      && Files.settings.deletingLastPathComponent().standardizedFileURL.path == Files.folder.standardizedFileURL.path,
      "\(Files.settings.deletingLastPathComponent().standardizedFileURL.path) vs \(Files.folder.standardizedFileURL.path)")

// MARK: the box, in the real text view: the built-in part above the user's, protected; the cap on the user's part

do {
    var bound = ""                      // what the box hands to Settings, and Settings stores: the user's part only
    var spied = QuickChatInstructions.Part.custom       // the link lit (what scroll-spy hands to the page)
    func parent(web: Bool, jump: SJump? = nil) -> SInstructionsTextView {
        SInstructionsTextView(text: Binding(get: { bound }, set: { bound = $0 }), active: Binding(get: { spied }, set: { spied = $0 }), jump: jump,
                              builtIn: QuickChatCommand.fixedPrompt(web: web),
                              placeholder: "For example: “Answer in Ukrainian.”", limit: 1000, label: "Instructions",
                              ink: .white, dim: .gray)
    }
    let coord = parent(web: false).makeCoordinator()
    let (scroll, tv) = SProtectedTextView.make(delegate: coord, label: "Instructions")
    scroll.frame = NSRect(x: 0, y: 0, width: 420, height: 108)
    coord.attach(scroll, tv)
    coord.apply()
    scroll.layoutSubtreeIfNeeded()
    func whole() -> NSString { tv.string as NSString }
    func built() -> String { whole().substring(to: tv.protectedLength) }
    func user() -> String { whole().substring(from: tv.protectedLength) }
    func put(_ s: String, at range: NSRange) { tv.insertText(s, replacementRange: range) }
    let pl = tv.protectedLength, builtFirst = built()

    check("box: the built-in text (after a lock) is the box's first lines, then the hairline's line, and the user's part is empty",
          builtFirst.contains(QuickChatCommand.systemPrompt) && builtFirst.hasSuffix("\n\n") && tv.dividerLocation == pl - 1 && user().isEmpty && bound.isEmpty,
          builtFirst)
    check("box: it is one scroll view of a fixed height of about seven lines", scroll.frame.height == SInstructionsBox.height && SInstructionsBox.height >= 100 && SInstructionsBox.height <= 120)
    let lm = tv.layoutManager!
    lm.ensureLayout(for: tv.textContainer!)
    func hairlineY() -> CGFloat { lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: tv.dividerLocation), effectiveRange: nil).minY }
    func top() -> CGFloat { scroll.contentView.bounds.origin.y }
    /// Runs the main run loop until `done` holds, or `s` seconds are up.
    func spin(_ s: TimeInterval = 2, until done: () -> Bool) {
        let end = Date().addingTimeInterval(s)
        while !done(), Date() < end { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
    }
    func atCustom() -> Bool { abs(top() - (hairlineY() - 4)) < 2 }
    check("box: it opens scrolled to Custom: the hairline is at the top, with the box able to scroll that far however little is written",
          hairlineY() > 20 && atCustom(), "scrolled to \(top()), the hairline is at \(hairlineY())")
    check("box: …and Custom is the part in view (its link lit)", coord.partInView == .custom && spied == .custom)
    // jump links and scroll-spy
    coord.scrollTo(.builtIn)
    check("box: Built in is at the top the moment the call returns (one step)", top() == 0 && coord.partInView == .builtIn, "\(top())")
    spin { spied == .builtIn }
    check("box: Built in scrolls to the top, and its link is the one lit", top() == 0 && coord.partInView == .builtIn && spied == .builtIn, "\(top()) \(spied)")
    coord.scrollTo(.custom)
    check("box: Custom is at the hairline the moment the call returns (one step)", atCustom(), "\(top())")
    spin { spied == .custom }
    check("box: Custom scrolls back to the hairline, and its link is lit again", atCustom() && spied == .custom, "\(top()) \(spied)")
    // part way: the link follows the middle of the view
    scroll.contentView.setBoundsOrigin(NSPoint(x: 0, y: 10)); scroll.reflectScrolledClipView(scroll.contentView)
    spin { spied == .builtIn }
    check("box: scrolling by hand lights the link of the part in view", spied == .builtIn && coord.partInView == .builtIn, "\(top()) \(spied)")
    // a link's request (a new id each time): instant, the final position right after the click, whatever Reduce Motion says
    coord.parent = parent(web: false, jump: SJump(part: .custom, id: 1)); coord.apply()
    check("box: a link's request is at its part right after the click (no animation)", atCustom(), "\(top())")
    spin { spied == .custom }
    check("box: …and the spy follows", atCustom() && spied == .custom, "\(top()) \(spied)")
    scroll.contentView.setBoundsOrigin(NSPoint(x: 0, y: 0)); scroll.reflectScrolledClipView(scroll.contentView)
    coord.apply()
    spin(0.3) { false }
    check("box: the same request is not run twice", top() == 0, "\(top())")
    coord.parent = parent(web: false, jump: SJump(part: .custom, id: 2)); coord.apply()
    check("box: …a new one is, at once", atCustom(), "\(top())")
    coord.parent = parent(web: false, jump: SJump(part: .builtIn, id: 3)); coord.apply()
    check("box: …and Built in's request goes to the top at once", top() == 0, "\(top())")
    spin { spied == .builtIn }
    check("box: …and its link is lit", spied == .builtIn, "\(spied)")
    coord.scrollTo(.custom)
    // the links' hit areas
    check("box: a jump link's hit area is at least 44 × 22 pt", SJumpLink.hit.width >= 44 && SJumpLink.hit.height >= 22)

    put("Keep it short.", at: NSRange(location: pl, length: 0))
    check("box: typing at the start of the user's part works, and the field's text is the user's part alone",
          user() == "Keep it short." && bound == "Keep it short." && built() == builtFirst, "\(user()) | \(bound)")
    // edits and pastes never change the built-in part
    put("XX", at: NSRange(location: 3, length: 0))
    put(String(repeating: "v", count: 200), at: NSRange(location: 0, length: 0))
    put("", at: NSRange(location: 0, length: 30))
    put("", at: NSRange(location: pl - 1, length: 1))
    put("z", at: NSRange(location: pl - 5, length: 5))
    check("box: edits and pastes in the built-in part, and a backspace at the start of the user's, change nothing",
          built() == builtFirst && user() == "Keep it short." && bound == "Keep it short.", "\(built().prefix(40)) | \(user())")
    put("New.", at: NSRange(location: 0, length: whole().length))
    check("box: select all and type replaces the user's part only", built() == builtFirst && user() == "New." && bound == "New.", user())
    put("", at: NSRange(location: 0, length: whole().length))
    check("box: select all and delete clears the user's part only", built() == builtFirst && user().isEmpty && bound.isEmpty)
    // the caret and selections
    tv.setSelectedRange(NSRange(location: 2, length: 0))
    check("box: the caret can't be put in the built-in part", tv.selectedRange() == NSRange(location: pl, length: 0), "\(tv.selectedRange())")
    tv.setSelectedRange(NSRange(location: 0, length: 20))
    check("box: a selection over the built-in part (to copy it) is allowed", tv.selectedRange() == NSRange(location: 0, length: 20), "\(tv.selectedRange())")
    // the cap counts the user's part alone, a paste included
    put(String(repeating: "x", count: 900), at: NSRange(location: pl, length: 0))
    put(String(repeating: "p", count: 500), at: NSRange(location: pl + 900, length: 0))
    check("box: a paste past 1,000 of the user's part gives what fits (the built-in part isn't counted)",
          user().count == 1000 && user().hasSuffix(String(repeating: "p", count: 100)) && bound == user() && whole().length > 1000 && built() == builtFirst, "\(user().count)")
    put("a", at: NSRange(location: whole().length, length: 0))
    check("box: a key typed in a full box does nothing", user().count == 1000 && !user().hasSuffix("a"))
    put(String(repeating: "q", count: 40), at: NSRange(location: pl, length: 0))
    check("box: a paste into a full box does nothing", user().count == 1000 && !user().contains("q") && built() == builtFirst)
    put(String(repeating: "r", count: 30), at: NSRange(location: pl, length: 10))
    check("box: a paste over a selection takes the room the selection frees", user().count == 1000 && user().hasPrefix(String(repeating: "r", count: 10) + "x"), String(user().prefix(14)))
    put("", at: NSRange(location: pl, length: 50))
    put("b", at: NSRange(location: pl + 950, length: 0))
    check("box: deleting works in a full box, and typing then works again, one character at a time up to the limit", user().count == 951 && bound.hasSuffix("b"))
    put("", at: NSRange(location: 0, length: whole().length))
    put(String(repeating: "z", count: 5000), at: NSRange(location: pl, length: 0))
    check("box: a long paste into an empty box is cut to 1,000", user().count == 1000 && bound.count == 1000 && built() == builtFirst)
    // what is stored holds only the user's text
    let st = SettingsState()
    st.settings.instructions = QuickChatInstructions.clamp(bound)
    let stored = String(decoding: (try? JSONEncoder().encode(st.settings)) ?? Data(), as: UTF8.self)
    check("box: the stored setting holds the user's text only, never the built-in part",
          st.settings.instructions == bound && !stored.contains("Built in") && !stored.contains("Yours") && !stored.contains(QuickChatCommand.systemPrompt)
          && !stored.contains("floating chat window"))
    // Links and search swaps the built-in part live; the user's text and the rules stay
    put("", at: NSRange(location: 0, length: whole().length))
    put("My text.", at: NSRange(location: pl, length: 0))
    coord.parent = parent(web: true)
    coord.apply()
    check("box: Links and search swaps the built-in text live: the web one, the user's text where it was",
          built().contains(QuickChatCommand.webSystemPrompt) && !built().contains("You have no tools here.") && user() == "My text." && bound == "My text.", built())
    let pl2 = tv.protectedLength, builtWeb = built()
    check("box: …and the swap doesn't count as the user's text", pl2 != pl && bound == "My text.")
    put("YY", at: NSRange(location: 4, length: 0))
    put("!", at: NSRange(location: pl2, length: 0))
    check("box: …the new built-in part is protected too, and typing still goes into the user's part", built() == builtWeb && user() == "!My text.", "\(user())")
    coord.parent = parent(web: false)
    coord.apply()
    check("box: …and back to the no-web text", built() == builtFirst && user() == "!My text.")
    // a change from outside (the text cleared) reaches the box
    bound = ""
    coord.apply()
    check("box: a text cleared from outside empties the user's part and leaves the built-in part", user().isEmpty && built() == builtFirst)
    // the same through Settings' own binding: whatever gets to the stored text is within the cap
    st.settings.instructions = QuickChatInstructions.clamp(String(repeating: "m", count: 2000))
    check("cap: the stored text never goes past 1,000", st.settings.instructions.count == 1000)
}

// MARK: the chat on the stand-in `claude`

struct Fix {
    let m: QuickChatModel
    let dir: URL
    let argsFile: String
    /// The stand-in's process id (it writes it when it starts; a restarted chat has another).
    var pid: String {
        ((try? String(contentsOfFile: argsFile, encoding: .utf8)) ?? "").split(separator: "\n").first { $0.hasPrefix("PID ") }.map { String($0.dropFirst(4)) } ?? ""
    }
    /// The system prompt the stand-in was started with (its argument after --system-prompt).
    var prompt: String? {
        let r = (try? String(contentsOfFile: argsFile, encoding: .utf8)) ?? ""
        guard let a = r.range(of: "ARG [--system-prompt]\nARG [") else { return nil }
        guard let b = r.range(of: "]\nARG [--", range: a.upperBound..<r.endIndex) else { return nil }
        return String(r[a.upperBound..<b.lowerBound])
    }
    func answered(_ n: Int) {
        let end = Date().addingTimeInterval(40)
        while !(m.turns.count == n && m.turns.last?.phase == .done), Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        CheckQuiet.verify("after an answer")
    }
    func say(_ text: String, answers n: Int) { m.field = text; m.send(); answered(n) }
    func waitFor(_ s: TimeInterval = 20, _ f: () -> Bool) {
        let end = Date().addingTimeInterval(s)
        while !f(), Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.03)) }
    }
}
func signedInFolder(_ folder: URL, uuid: String, email: String) {
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try? Data(#"{"oauthAccount":{"accountUuid":"\#(uuid)","emailAddress":"\#(email)"}}"#.utf8).write(to: folder.appendingPathComponent(".claude.json"))
}
func fixture(_ name: String) -> Fix {
    let stub = ProcessInfo.processInfo.environment["QC_STUB_PATH"] ?? ""
    let dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("ins-" + name)
    try? FileManager.default.removeItem(at: dir)
    try? FileManager.default.createDirectory(at: dir.appendingPathComponent("work"), withIntermediateDirectories: true)
    let argsFile = dir.appendingPathComponent("args.txt").path
    try? "mode=ok\nargs=\(argsFile)\n".write(to: dir.appendingPathComponent("stub.conf"), atomically: true, encoding: .utf8)
    let m = QuickChatModel()
    var tg = QuickChatTarget(Profile(id: name, name: "Main", folder: dir.appendingPathComponent("folder").path))
    tg.workFolder = dir.appendingPathComponent("work").path
    tg.accountUUID = "u-\(name)"; tg.email = "alex@example.com"
    signedInFolder(dir.appendingPathComponent("folder"), uuid: "u-\(name)", email: "alex@example.com")
    m.target = tg
    m.resolveClaude = { $0(stub) }
    m.freshTarget = { _, done in done(tg) }
    return Fix(m: m, dir: dir, argsFile: argsFile)
}
func settings(_ text: String, web: Bool) -> QuickChatSettings { var s = QuickChatSettings(); s.instructions = text; s.webLinks = web; return s }

// an empty box leaves the prompt as it was, web and no web
do {
    let f = fixture("empty"), m = f.m
    m.defaults = { settings("", web: false) }; m.newChat()
    f.say("hi", answers: 1)
    check("chat: an empty box starts claude with the fixed text alone (no web)", f.prompt == QuickChatCommand.systemPrompt, f.prompt ?? "nil")
    m.defaults = { settings("  \n ", web: true) }; m.newChat()
    f.say("hi", answers: 1)
    check("chat: a box of blanks adds nothing either (web)", f.prompt == QuickChatCommand.webSystemPrompt, f.prompt ?? "nil")
    m.shutdown(); try? FileManager.default.removeItem(at: f.dir)
}

// the text comes after the fixed text, web and no web
do {
    let f = fixture("after"), m = f.m
    m.defaults = { settings(own, web: false) }; m.newChat()
    f.say("hi", answers: 1)
    check("chat: the text follows the fixed text, lead-in between (no web)", f.prompt == QuickChatCommand.systemPrompt + lead + own, f.prompt ?? "nil")
    m.defaults = { settings("\n" + own + "\n", web: true) }; m.newChat()
    f.say("hi", answers: 1)
    check("chat: the text follows the web text, trimmed (web)", f.prompt == QuickChatCommand.webSystemPrompt + lead + own, f.prompt ?? "nil")
    m.shutdown(); try? FileManager.default.removeItem(at: f.dir)
}

// which chat takes which text
do {
    let f = fixture("keeps"), m = f.m
    m.defaults = { settings(own, web: false) }; m.newChat()
    check("chat: a new chat takes the current text", m.instructions == own)
    f.say("first", answers: 1)
    let pid = f.pid
    check("chat: the chat started with that text", !pid.isEmpty && f.prompt == QuickChatCommand.systemPrompt + lead + own)
    // the text changes in Settings while the chat is open
    m.defaults = { settings("Keep it short.", web: false) }; m.instructionsSettingChanged("Keep it short.")
    check("chat: an open chat keeps the text it started with", m.instructions == own, m.instructions)
    f.say("second", answers: 2)
    check("chat: …and is not restarted for it: the same claude answers, with no \"New chat\" line",
          f.pid == pid && m.turns.count == 2 && m.accountNote == nil && f.prompt == QuickChatCommand.systemPrompt + lead + own,
          "\(f.pid) \(pid) \(m.turns.count) \(String(describing: m.accountNote))")
    m.defaults = { settings("", web: false) }; m.instructionsSettingChanged("")
    f.say("third", answers: 3)
    check("chat: …not even when the box is emptied", f.pid == pid && m.turns.count == 3 && m.instructions == own)
    // a new chat takes what is there now
    m.defaults = { settings("Keep it short.", web: false) }
    m.newChat()
    check("chat: a new chat takes the text as it is now", m.instructions == "Keep it short." && m.turns.isEmpty)
    f.say("fourth", answers: 1)
    check("chat: …and its claude is started with it, a new process",
          f.pid != pid && f.prompt == QuickChatCommand.systemPrompt + lead + "Keep it short.", "\(f.pid) \(pid) \(f.prompt ?? "nil")")
    m.shutdown(); try? FileManager.default.removeItem(at: f.dir)
}

// an empty bar (no chat on screen) takes the text at once; the claude it had warm is replaced, silently
do {
    let f = fixture("bar"), m = f.m
    m.defaults = { settings("Old text.", web: false) }; m.newChat()
    m.warm()
    f.waitFor { !f.pid.isEmpty }
    let warm = f.pid
    check("bar: a claude is warm for the empty bar, with the old text", !warm.isEmpty && f.prompt == QuickChatCommand.systemPrompt + lead + "Old text.", f.prompt ?? "nil")
    m.defaults = { settings(own, web: false) }; m.instructionsSettingChanged(own)
    check("bar: an empty bar takes a changed text at once", m.instructions == own)
    f.say("hello", answers: 1)
    check("bar: …its warm claude is replaced by one with the new text, and nothing says so (no chat was lost)",
          f.pid != warm && f.prompt == QuickChatCommand.systemPrompt + lead + own && m.accountNote == nil, "\(f.pid) \(warm) \(f.prompt ?? "nil")")
    m.shutdown(); try? FileManager.default.removeItem(at: f.dir)
}

// MARK: Settings saves as it is typed; Remove… clears it

do {
    let chat = QuickChat.shared
    chat.model.defaults = { chat.settings }
    let st = SettingsState()
    st.settings.instructions = "Keep it short."
    st.save()
    check("save: a change in the box reaches the app's settings as it is made (no Save key)",
          chat.settings.instructions == "Keep it short." && chat.model.instructions == "Keep it short.", chat.settings.instructions)
    st.settings.instructions = "Keep it short and plain."
    st.save()
    check("save: …key after key", chat.settings.instructions == "Keep it short and plain." && chat.model.instructions == "Keep it short and plain.")
    chat.closeForRemoval()
    check("Remove…: the app's settings and the chat hold none afterwards", chat.settings.instructions.isEmpty && chat.model.instructions.isEmpty,
          "\(chat.settings.instructions) | \(chat.model.instructions)")
    st.dataRemoved()
    check("Remove…: the settings window's own copy is cleared too (and nothing is saved on the way)",
          st.settings.instructions.isEmpty && chat.settings.instructions.isEmpty)
    check("Remove…: a new chat afterwards starts with the fixed text alone",
          QuickChatCommand(claude: "/opt/sample/bin/claude", configDir: sampleFolder, isDefaultDir: false, workFolder: sampleFolder, model: "haiku",
                           instructions: chat.model.instructions).prompt == QuickChatCommand.systemPrompt)
}

// MARK: the box's other ways in: transformations, undo and redo, paste, the Edit keys, the user's own scrolling

do {
    var bound = ""
    var spied = QuickChatInstructions.Part.custom
    // each box sits in a window of its own that is never shown (a text view has an undo manager only in a window)
    var windows: [NSWindow] = []
    func fixture() -> (coord: SInstructionsTextView.Coordinator, scroll: SScrollView, tv: SProtectedTextView, win: SettingsNSWindow) {
        let parent = SInstructionsTextView(text: Binding(get: { bound }, set: { bound = $0 }), active: Binding(get: { spied }, set: { spied = $0 }),
                                           jump: nil, builtIn: QuickChatCommand.fixedPrompt(web: false), placeholder: "Example", limit: 1000,
                                           label: "Instructions", ink: .white, dim: .gray)
        let coord = parent.makeCoordinator()
        let (scroll, tv) = SProtectedTextView.make(delegate: coord, label: "Instructions")
        let win = SettingsNSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 108), styleMask: [.titled], backing: .buffered, defer: true)
        win.isReleasedWhenClosed = false
        windows.append(win)
        win.contentView = scroll
        scroll.frame = NSRect(x: 0, y: 0, width: 420, height: 108)
        coord.attach(scroll, tv)
        coord.apply()
        scroll.layoutSubtreeIfNeeded()
        return (coord, scroll, tv, win)
    }
    func spin(_ s: TimeInterval = 2, until done: () -> Bool) {
        let end = Date().addingTimeInterval(s)
        while !done(), Date() < end { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
    }
    let (coord, scroll, tv, _) = fixture()
    func whole() -> NSString { tv.string as NSString }
    func built() -> String { whole().substring(to: tv.protectedLength) }
    func user() -> String { whole().substring(from: tv.protectedLength) }
    func put(_ s: String, at range: NSRange) { tv.insertText(s, replacementRange: range) }
    func selectAll() { tv.setSelectedRange(NSRange(location: 0, length: whole().length)) }
    let pl = tv.protectedLength, builtFirst = built()

    // what an edit may change (rangesForUserTextChange): cut to the user's part
    put("Mine", at: NSRange(location: pl, length: 0))
    selectAll()
    check("clip: select all offers the user's part alone", tv.rangesForUserTextChange == [NSValue(range: NSRange(location: pl, length: 4))], "\(String(describing: tv.rangesForUserTextChange))")
    tv.setSelectedRange(NSRange(location: 3, length: 12))
    check("clip: a selection inside the built-in part offers nothing", tv.rangesForUserTextChange == nil, "\(String(describing: tv.rangesForUserTextChange))")
    tv.setSelectedRange(NSRange(location: pl - 5, length: 8))
    check("clip: a selection reaching into the user's part offers the part of it that is there", tv.rangesForUserTextChange == [NSValue(range: NSRange(location: pl, length: 3))])
    tv.setSelectedRange(NSRange(location: pl + 2, length: 0))
    check("clip: a caret in the user's part is as it is", tv.rangesForUserTextChange == [NSValue(range: NSRange(location: pl + 2, length: 0))])

    // transformations over a select-all (right-click ▸ Transformations): the built-in text is never carried into the user's
    selectAll(); tv.uppercaseWord(nil)
    check("transform: Make Upper Case after select all changes the user's part only", built() == builtFirst && user() == "MINE" && bound == "MINE", "\(user()) | \(bound)")
    selectAll(); tv.lowercaseWord(nil)
    check("transform: Make Lower Case", built() == builtFirst && user() == "mine" && bound == "mine", "\(user()) | \(bound)")
    selectAll(); tv.capitalizeWord(nil)
    check("transform: Capitalize", built() == builtFirst && user() == "Mine" && bound == "Mine", "\(user()) | \(bound)")
    check("transform: what is stored is the user's text, with none of the built-in text in it", !bound.contains("floating chat window") && !bound.contains("You are Claude"))

    // undo and redo reach the page
    guard let um = tv.undoManager else { check("undo: the box has an undo manager", false); exit(1) }
    um.groupsByEvent = false
    um.removeAllActions()
    selectAll()
    um.beginUndoGrouping(); put("", at: NSRange(location: 0, length: whole().length)); um.endUndoGrouping()
    um.beginUndoGrouping(); put("mine", at: NSRange(location: pl, length: 0)); um.endUndoGrouping()
    um.beginUndoGrouping(); put("x", at: NSRange(location: pl + 4, length: 0)); um.endUndoGrouping()
    check("undo: typed text is on the page", user() == "minex" && bound == "minex", "\(user()) | \(bound)")
    um.undo()
    check("undo: undo takes the typed key off the box and off the page (the stored text, the counter)", user() == "mine" && bound == "mine" && built() == builtFirst, "\(user()) | \(bound)")
    um.redo()
    check("undo: redo puts it back, on the page too", user() == "minex" && bound == "minex" && built() == builtFirst, "\(user()) | \(bound)")
    um.undo(); um.undo()
    check("undo: undoing the typing leaves the user's part empty and the built-in part whole", user().isEmpty && bound.isEmpty && built() == builtFirst, "\(user()) | \(bound)")
    check("undo: undo never reaches into the built-in part", !um.canUndo || { um.undo(); return built() == builtFirst }())
    um.groupsByEvent = true      // as in the app: an edit outside a group opens one
    // an outside clear leaves nothing to undo (and an undo then can't act on text that is gone)
    um.beginUndoGrouping(); put("abc", at: NSRange(location: pl, length: 0)); um.endUndoGrouping()
    bound = ""
    coord.apply()
    check("undo: a text cleared from outside empties the box and leaves no undo to reach it", user().isEmpty && !um.canUndo && !um.canRedo)
    um.undo()
    check("undo: …and an undo then does nothing (no exception)", user().isEmpty && built() == builtFirst)

    // paste: the real path (paste: reads the pasteboard and inserts through the same checks); a private pasteboard here
    let pb = NSPasteboard(name: NSPasteboard.Name("cl-quick-instructions-check-\(ProcessInfo.processInfo.processIdentifier)"))
    pb.clearContents(); pb.setString(String(repeating: "p", count: 5000), forType: .string)
    tv.setSelectedRange(NSRange(location: pl, length: 0))
    let pasted = tv.readSelection(from: pb, type: .string)
    check("paste: a long paste at the user's start is cut to 1,000 of the user's part", pasted && user().count == 1000 && bound.count == 1000 && built() == builtFirst, "\(pasted) \(user().count)")
    selectAll(); _ = tv.readSelection(from: pb, type: .string)
    check("paste: a paste over a select-all replaces the user's part only", user().count == 1000 && built() == builtFirst && !bound.contains("Claude"))
    tv.setSelectedRange(NSRange(location: 4, length: 0))
    pb.clearContents(); pb.setString("zz", forType: .string)
    _ = tv.readSelection(from: pb, type: .string)
    check("paste: with the caret put in the built-in part, the paste is refused or lands in the user's part, never in the built-in text",
          built() == builtFirst && (user().count == 1000), "\(user().count)")
    pb.releaseGlobally()

    // the Edit keys in the settings window (the app has no Edit menu): they reach the box
    func key(_ ch: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags, window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber, context: nil,
                         characters: ch, charactersIgnoringModifiers: ch, isARepeat: false, keyCode: code)!
    }
    let (coord2, scroll2, tv2, win) = fixture()
    _ = scroll2
    win.makeFirstResponder(tv2)
    bound = ""; coord2.apply()
    let sels: [(String, UInt16, NSEvent.ModifierFlags, Selector?)] = [("x", 7, [.command], #selector(NSText.cut(_:))), ("c", 8, [.command], #selector(NSText.copy(_:))),
        ("v", 9, [.command], #selector(NSText.paste(_:))), ("a", 0, [.command], #selector(NSText.selectAll(_:))), ("z", 6, [.command], Selector(("undo:"))),
        ("z", 6, [.command, .shift], Selector(("redo:"))), ("v", 9, [.command, .option], nil), ("v", 9, [.command, .control], nil), ("v", 9, [], nil),
        ("c", 8, [.command, .shift], nil), ("q", 12, [.command], nil)]
    check("keys: ⌘X ⌘C ⌘V ⌘A ⌘Z and ⇧⌘Z stand for cut, copy, paste, select all, undo and redo; no other key does",
          sels.allSatisfy { QCEditKeys.action(for: key($0.0, $0.1, $0.2, window: win)) == $0.3 })
    tv2.insertText("hello", replacementRange: NSRange(location: tv2.protectedLength, length: 0))
    check("keys: the box is the window's first responder", win.firstResponder === tv2)
    let didA = win.performKeyEquivalent(with: key("a", 0, [.command], window: win))
    check("keys: ⌘A in the settings window selects all of the box", didA && tv2.selectedRange() == NSRange(location: 0, length: (tv2.string as NSString).length), "\(didA) \(tv2.selectedRange())")
    let um2 = tv2.undoManager!
    um2.groupsByEvent = false; um2.removeAllActions()
    tv2.setSelectedRange(NSRange(location: (tv2.string as NSString).length, length: 0))
    um2.beginUndoGrouping(); tv2.insertText("!", replacementRange: NSRange(location: (tv2.string as NSString).length, length: 0)); um2.endUndoGrouping()
    let didZ = win.performKeyEquivalent(with: key("z", 6, [.command], window: win))
    check("keys: ⌘Z in the settings window undoes the last typing, and the page follows", didZ && bound == "hello", "\(didZ) \(bound)")
    let didR = win.performKeyEquivalent(with: key("z", 6, [.command, .shift], window: win))
    check("keys: ⇧⌘Z redoes it", didR && bound == "hello!", "\(didR) \(bound)")
    check("keys: a key that is no edit key is left alone", !win.performKeyEquivalent(with: key("q", 12, [], window: win)))

    // scrolled by the user (the wheel): the box is not put back on Custom when it is resized afterwards
    bound = ""
    let (coord3, scroll3, tv3, _) = fixture()
    _ = coord3; _ = tv3
    scroll3.contentView.setBoundsOrigin(NSPoint(x: 0, y: 0)); scroll3.reflectScrolledClipView(scroll3.contentView)
    if let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 3, wheel2: 0, wheel3: 0), let ev = NSEvent(cgEvent: cg) {
        scroll3.scrollWheel(with: ev)
    } else { check("wheel: a scroll event can be made", false) }
    scroll3.setFrameSize(NSSize(width: 380, height: 108))
    spin(0.5) { false }
    let (_, scroll4, _, _) = fixture()
    let custom = scroll4.contentView.bounds.origin.y
    check("wheel: after the user scrolled, a resize doesn't snap the box back to Custom", custom > 30 && scroll3.contentView.bounds.origin.y < custom - 10,
          "\(scroll3.contentView.bounds.origin.y) against Custom at \(custom)")
    let y4 = custom
    scroll4.setFrameSize(NSSize(width: 380, height: 108))
    spin(0.3) { false }
    check("wheel: untouched, it stays on Custom through a resize", y4 > 20 && scroll4.contentView.bounds.origin.y > 20, "\(y4) \(scroll4.contentView.bounds.origin.y)")
    _ = scroll; _ = coord; _ = spin
}

// the track keeps the tray's height on a profile's page, and is not there to be reached
do {
    func tray(_ page: SettingsPage) -> NSSize {
        let host = NSHostingView(rootView: SettingsTiles(profiles: [.init(id: "main", name: "Main", sub: "default · alex@example.com", lamp: .ok)], page: page).face(.std))
        return host.fittingSize
    }
    check("tabs: the tray is as tall on a profile's page as on General's (the track's room is kept)", tray(.general).height == tray(.profile("main")).height,
          "\(tray(.general)) \(tray(.profile("main")))")
    check("tabs: the track is 26 pt high", SettingsTiles.trackHeight == 26)
}

// General ▸ APP | CHAT: the state, the pages Settings opens on, the track's metrics
do {
    let st = SettingsState()
    check("tabs: General opens on APP", st.page == .general && st.generalTab == .app)
    // picking a segment is setting the track's binding: the state follows, and is remembered
    let pick = Binding(get: { st.generalTab }, set: { st.generalTab = $0 })
    pick.wrappedValue = .chat
    check("tabs: picking CHAT selects it, and it is remembered across pages", st.generalTab == .chat)
    st.open(profile: "main", addAccount: true)
    check("tabs: Add an account… still lands on the profile's page with its form open", st.page == .profile("main") && st.addingFor == "main" && st.generalTab == .chat)
    st.open(profile: SettingsWindow.addPage)
    check("tabs: Add a profile still lands on its page", st.page == .add)
    st.open(profile: nil)
    check("tabs: no profile lands on General, on the sub-page last shown", st.page == .general && st.generalTab == .chat)
    st.open(profile: nil, firstProfile: "main", firstRun: true)
    check("tabs: the first run lands on the first profile", st.page == .profile("main"))
    st.generalTab = .app; st.recording = .some(nil); st.generalTab = .chat
    check("tabs: leaving APP ends a shortcut recording", st.recording == nil)
    // the track as cl_audit's Card style selector draws it (compact PillPicker), at the sizes the operator set
    let w = PillPicker<GeneralTab>.equalWidth(GeneralTab.allCases.map(\.title), size: SettingsTiles.tabSize, padding: 16)
    let one = PillPicker<GeneralTab>.equalWidth(["CHAT"], size: SettingsTiles.tabSize, padding: 16)
    check("tabs: label 10.5 pt; the segments are all one width: the widest label plus 16 pt each side", SettingsTiles.tabSize >= 10.5 && SettingsTiles.tabSize <= 11
          && w >= one && w - one < 16, "\(w) \(one)")
}

// the window's height: both sub-pages (and a profile's) are no taller than General was at eaed019. Drawn as the app draws
// them (--render-settings): the picture is 2 pixels to the point, the old General 666 pt (its render, 1332 px).
if #available(macOS 14, *) {
    let oldGeneralHeight: CGFloat = 666
    let dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("ins-renders")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var heights: [String: CGFloat] = [:]
    for page in ["general", "profile", "chat-custom", "chat-builtin", "chat-limit", "chat-noweb"] {
        let path = dir.appendingPathComponent(page + ".png").path
        MainActor.assumeIsolated { SettingsRender.write(to: path, page: page) }
        if let rep = NSBitmapImageRep(data: (try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data()) { heights[page] = CGFloat(rep.pixelsHigh) / 2 }
    }
    // (a profile's page too: the track's row, which every page keeps, is paid for by that page's tighter spacing)
    let subPages = ["general", "profile", "chat-custom", "chat-builtin", "chat-limit", "chat-noweb"].compactMap { heights[$0] }
    check("height: APP, CHAT (scrolled to Custom or to Built in, at the limit, Links and search off) and a profile's page are each no taller than General's 666 pt",
          heights.count == 6 && subPages.count == 6 && subPages.allSatisfy { $0 <= oldGeneralHeight }, "\(heights)")
    check("height: what is typed never changes it: CHAT is as tall with no text, with some and at the limit, and with the other built-in text",
          Set(["chat-custom", "chat-builtin", "chat-limit", "chat-noweb"].compactMap { heights[$0] }).count == 1, "\(heights)")
    try? FileManager.default.removeItem(at: dir)
}

CheckQuiet.verify("at the end")
// strict on CI (GitHub Actions sets CI; nobody copies there); on a Mac the user or another session may copy meanwhile, so
// a changed count is only a NOTE
let clipboardCounts = "change count \(clipboardAtStart) → \(NSPasteboard.general.changeCount)"
let clipboardSame = NSPasteboard.general.changeCount == clipboardAtStart, onCI = ProcessInfo.processInfo.environment["CI"] != nil
if !clipboardSame && !onCI { print("NOTE clipboard: the general pasteboard changed during the run (\(clipboardCounts)); this suite never writes it, so someone else did") }
check("clipboard: the whole suite left the general pasteboard as it was", clipboardSame || !onCI, clipboardCounts)
print(failed == 0 ? "instructions checks: \(passed)/\(passed) passed" : "instructions checks: \(failed) failed, \(passed) passed")
exit(failed == 0 ? 0 : 1)
