// Checks for the quick chat's engine and Markdown (Checks/run.sh). Sample data only.

import Foundation

var passed = 0, failed = 0
func check(_ name: String, _ ok: Bool, _ got: @autoclosure () -> Any = "") {
    if ok { passed += 1 } else { failed += 1; print("FAIL \(name)  got: \(got())") }
}
func line(_ s: String) -> Data { Data(s.utf8) }
/// Runs the main run loop until `done` or the time is up.
func wait(_ seconds: Double, until done: () -> Bool) {
    let end = Date().addingTimeInterval(seconds)
    while !done(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
}

// MARK: parsing what Claude Code prints

check("init", QuickChatParse.event(line(#"{"type":"system","subtype":"init","session_id":"s-1","model":"claude-haiku-5-5","tools":[]}"#))
      == .started(session: "s-1", model: "claude-haiku-5-5"))
check("status is ignored", QuickChatParse.event(line(#"{"type":"system","subtype":"status","status":"requesting"}"#)) == .ignored)
check("text delta", QuickChatParse.event(line(#"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hel"}}}"#)) == .text("Hel"))
check("thinking delta", QuickChatParse.event(line(#"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Hmm"}}}"#)) == .thinking("Hmm"))
check("block start is ignored", QuickChatParse.event(line(#"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}}"#)) == .ignored)
check("assistant", QuickChatParse.event(line(#"{"type":"assistant","message":{"model":"claude-haiku-5-5","content":[{"type":"thinking","thinking":"x"},{"type":"text","text":"Hi"},{"type":"text","text":" there"}]}}"#))
      == .message(text: "Hi there", model: "claude-haiku-5-5", error: nil))
check("assistant, not signed in", QuickChatParse.event(line(#"{"type":"assistant","message":{"model":"<synthetic>","content":[{"type":"text","text":"Not logged in · Please run /login"}]},"error":"authentication_failed"}"#))
      == .message(text: "Not logged in · Please run /login", model: "<synthetic>", error: "authentication_failed"))
let lim = QuickChatParse.event(line(#"{"type":"rate_limit_event","rate_limit_info":{"status":"allowed","resetsAt":1794776400,"rateLimitType":"seven_day","unifiedWindows":{"seven_day":{"utilization":0.05,"resetsAt":1794776400,"status":"allowed"}}}}"#))
check("rate limit", lim == .limit(type: "seven_day", used: 0.05, status: "allowed", resets: Date(timeIntervalSince1970: 1794776400)), lim)
// the 5-hour session window comes the same way, with its own type and window (the header's "session" meter)
let five = QuickChatParse.event(line(#"{"type":"rate_limit_event","rate_limit_info":{"status":"allowed","resetsAt":1794700000,"rateLimitType":"five_hour","unifiedWindows":{"five_hour":{"utilization":0.41,"resetsAt":1794700000,"status":"allowed"}}}}"#))
check("rate limit, 5-hour", five == .limit(type: "five_hour", used: 0.41, status: "allowed", resets: Date(timeIntervalSince1970: 1794700000)), five)
check("result", QuickChatParse.event(line(#"{"type":"result","subtype":"success","is_error":false,"result":"Hi","duration_ms":1742,"session_id":"s-1"}"#))
      == .done(isError: false, text: "Hi", ms: 1742, session: "s-1"))
check("result, an error", QuickChatParse.event(line(#"{"type":"result","is_error":true,"result":"Not logged in","duration_ms":5,"session_id":"s-1"}"#))
      == .done(isError: true, text: "Not logged in", ms: 5, session: "s-1"))
check("garbage is ignored", QuickChatParse.event(line("not json")) == .ignored)
check("an unknown type is ignored", QuickChatParse.event(line(#"{"type":"post_turn_summary"}"#)) == .ignored)

// Claude Code's answers to control requests
check("control response, ok with the model", QuickChatParse.event(line(#"{"type":"control_response","response":{"subtype":"success","request_id":"qc-2","response":{"model":"claude-sonnet-5-5"}}}"#))
      == .control(id: "qc-2", error: nil, model: "claude-sonnet-5-5"))
check("control response, interrupt", QuickChatParse.event(line(#"{"type":"control_response","response":{"subtype":"success","request_id":"qc-1","response":{"still_queued":[]}}}"#))
      == .control(id: "qc-1", error: nil, model: nil))
check("control response, an error", QuickChatParse.event(line(#"{"type":"control_response","response":{"subtype":"error","request_id":"qc-3","error":"nope"}}"#))
      == .control(id: "qc-3", error: "nope", model: nil))
check("control response without an id is ignored", QuickChatParse.event(line(#"{"type":"control_response","response":{"subtype":"success"}}"#)) == .ignored)

// the message Claude Code reads: one JSON line, whatever the text holds
let tricky = "Quote \" backslash \\ newline\nand emoji 🙂 and <tags>"
let ul = QuickChatParse.userLine(tricky)
check("user line ends in a newline", ul.last == 0x0A)
let back = (try? JSONSerialization.jsonObject(with: ul.dropLast())) as? [String: Any]
check("user line reads back", (back?["message"] as? [String: Any])?["content"] as? String == tricky, back as Any)
check("user line is one line", !ul.dropLast().contains(0x0A))

// model names
for (id, want) in [("claude-haiku-5-5", "Haiku 5.5"), ("claude-sonnet-5-5-20261001", "Sonnet 5.5"), ("claude-opus-5-5", "Opus 5.5"),
                   ("claude-fable-5-1", "Fable 5.1"), ("claude-haiku-4-5-20251001", "Haiku 4.5"), ("", ""), ("<synthetic>", "<synthetic>")] {
    check("model name \(id)", QuickChatParse.modelName(id) == want, QuickChatParse.modelName(id))
}

// MARK: the command

let cmd = QuickChatCommand(claude: "/opt/sample/bin/claude", configDir: "/Users/sample/.claude-work", isDefaultDir: false,
                           workFolder: "/tmp/sample-work", model: "haiku")
let a = cmd.arguments
func after(_ flag: String, _ args: [String]) -> String? { args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
check("print mode", a.first == "-p")
check("stream-json in", after("--input-format", a) == "stream-json")
check("stream-json out", after("--output-format", a) == "stream-json")
check("no tools", after("--tools", a) == "")
check("no settings files", after("--setting-sources", a) == "")
check("no MCP servers", a.contains("--strict-mcp-config"))
check("no slash commands", a.contains("--disable-slash-commands"))
check("its own system prompt", after("--system-prompt", a) == QuickChatCommand.systemPrompt)
check("the model", after("--model", a) == "haiku")
check("thinking off", after("--settings", a) == #"{"alwaysThinkingEnabled":false}"# && !a.contains("--effort"), a)
check("incognito: no session kept", a.contains("--no-session-persistence"))
check("incognito: nothing to resume, nothing continued", !a.contains("--resume") && !a.contains("-r") && !a.contains("--continue") && !a.contains("-c"), a)
check("never bare (it would skip the Keychain sign-in)", !a.contains("--bare"))
var c2 = cmd; c2.model = ""; c2.effort = "high"
let a2 = c2.arguments
check("the profile's own model", !a2.contains("--model"))
check("thinking high", after("--effort", a2) == "high" && after("--settings", a2) == #"{"alwaysThinkingEnabled":true}"#, a2)
check("incognito with thinking too", a2.contains("--no-session-persistence") && !a2.contains("--resume"))

// control requests: one JSON line each, with the id and the subtype Claude Code reads
func controlObject(_ d: Data) -> [String: Any]? { (try? JSONSerialization.jsonObject(with: d.dropLast())) as? [String: Any] }
let intr = QuickChatParse.controlLine(id: "qc-1", subtype: "interrupt")
check("interrupt line", intr.last == 0x0A && controlObject(intr)?["type"] as? String == "control_request"
      && controlObject(intr)?["request_id"] as? String == "qc-1" && (controlObject(intr)?["request"] as? [String: Any])?["subtype"] as? String == "interrupt", String(decoding: intr, as: UTF8.self))
let sm = QuickChatParse.controlLine(id: "qc-2", subtype: "set_model", ["model": "sonnet"])
check("set_model line", ((controlObject(sm)?["request"] as? [String: Any])?["model"] as? String) == "sonnet")
let th = QuickChatParse.controlLine(id: "qc-3", subtype: "apply_flag_settings", ["settings": QuickChatParse.thinkingSettings("high")])
let ths = ((controlObject(th)?["request"] as? [String: Any])?["settings"] as? [String: Any])
check("thinking on at an effort", ths?["alwaysThinkingEnabled"] as? Bool == true && ths?["effortLevel"] as? String == "high", ths as Any)
check("thinking off", (QuickChatParse.thinkingSettings(nil)["alwaysThinkingEnabled"] as? Bool) == false && QuickChatParse.thinkingSettings(nil)["effortLevel"] == nil)

// answers Stop gave up on: what comes before their `done` is dropped, the `done` ends the wait, a limit report stays
do {
    var s = StaleAnswers()
    let dn = QuickChatEvent.done(isError: true, text: "", ms: 30, session: "s")
    check("stale: nothing abandoned, everything passes", s.fate(of: .text("x")) == .pass && s.fate(of: dn) == .pass && !s.waiting)
    s.abandon()
    check("stale: waiting", s.waiting)
    check("stale: its text, thinking, message and start are dropped",
          s.fate(of: .text("late")) == .drop && s.fate(of: .thinking("t")) == .drop && s.fate(of: .started(session: "s", model: "m")) == .drop
          && s.fate(of: .message(text: "a", model: "m", error: nil)) == .drop)
    check("stale: a limit report is about the account and passes", s.fate(of: .limit(type: "seven_day", used: 0.5, status: "allowed", resets: nil)) == .pass)
    check("stale: a control response passes", s.fate(of: .control(id: "qc-1", error: nil, model: nil)) == .pass)
    check("stale: its done ends the wait", s.fate(of: dn) == .endsOne && !s.waiting)
    check("stale: then the next answer passes", s.fate(of: .text("Answer")) == .pass && s.fate(of: dn) == .pass)
    s.abandon(); s.abandon()
    check("stale: two abandoned, two dones", s.fate(of: dn) == .endsOne && s.waiting && s.fate(of: dn) == .endsOne && !s.waiting)
    s.abandon(); s.reset()
    check("stale: a new process starts clean", !s.waiting)
}

let base = ["PATH": "/usr/bin:/bin", "HOME": "/Users/sample", "LANG": "en_GB.UTF-8", "LC_CTYPE": "UTF-8", "HTTPS_PROXY": "http://proxy.example:8080",
            "ANTHROPIC_API_KEY": "sk-sample", "CLAUDE_CODE_OAUTH_TOKEN": "sample", "CLAUDE_CODE_OAUTH_REFRESH_TOKEN": "sample",
            "ANTHROPIC_AUTH_TOKEN": "sample", "CLAUDE_CONFIG_DIR": "/Users/sample/.claude-other", "ANTHROPIC_BASE_URL": "https://example.com",
            "CLAUDE_CODE_USE_BEDROCK": "1", "AWS_BEARER_TOKEN_BEDROCK": "sample", "CLAUDE_CODE_USE_VERTEX": "1", "ANTHROPIC_VERTEX_PROJECT_ID": "sample",
            "CLAUDE_CODE_ENABLE_TELEMETRY": "1", "OTEL_EXPORTER_OTLP_ENDPOINT": "https://collector.example", "ANTHROPIC_CUSTOM_HEADERS": "X: y",
            "ANTHROPIC_MODEL": "opus", "NODE_OPTIONS": "--require /tmp/x.js"]
let env = cmd.environment(base)
check("its environment carries none of the API key or token variables", env["ANTHROPIC_API_KEY"] == nil && env["ANTHROPIC_AUTH_TOKEN"] == nil && env["CLAUDE_CODE_OAUTH_TOKEN"] == nil
      && env["CLAUDE_CODE_OAUTH_REFRESH_TOKEN"] == nil)
check("no other endpoint", env["ANTHROPIC_BASE_URL"] == nil)
check("no other provider", env["CLAUDE_CODE_USE_BEDROCK"] == nil && env["AWS_BEARER_TOKEN_BEDROCK"] == nil && env["CLAUDE_CODE_USE_VERTEX"] == nil
      && env["ANTHROPIC_VERTEX_PROJECT_ID"] == nil)
check("no telemetry export", env["CLAUDE_CODE_ENABLE_TELEMETRY"] == nil && env["OTEL_EXPORTER_OTLP_ENDPOINT"] == nil)
check("no headers, model or node options from outside", env["ANTHROPIC_CUSTOM_HEADERS"] == nil && env["ANTHROPIC_MODEL"] == nil && env["NODE_OPTIONS"] == nil)
check("language and proxy kept", env["LANG"] == "en_GB.UTF-8" && env["LC_CTYPE"] == "UTF-8" && env["HTTPS_PROXY"] == "http://proxy.example:8080")
check("nothing but the allowed, the folder, the PATH and the off switches",
      Set(env.keys).subtracting(QuickChatCommand.passed).subtracting(["CLAUDE_CONFIG_DIR", "PATH", "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC",
                                                                      "DISABLE_TELEMETRY", "DISABLE_ERROR_REPORTING",
                                                                      "CLAUDE_CODE_AGENTS_MD_ROWS_EVERY_PROCESS", "CLAUDE_CODE_DISABLE_AUTO_MEMORY"]).allSatisfy { $0.hasPrefix("LC_") },
      env.keys.sorted())
check("the profile's folder", env["CLAUDE_CONFIG_DIR"] == "/Users/sample/.claude-work")
check("claude's folder first on the PATH", env["PATH"]?.hasPrefix("/opt/sample/bin:") == true, env["PATH"] ?? "")
check("non-essential traffic off", env["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] == "1" && env["DISABLE_TELEMETRY"] == "1")
check("HOME kept", env["HOME"] == "/Users/sample")
var dflt = cmd; dflt.isDefaultDir = true; dflt.configDir = "/Users/sample/.claude"
check("the default folder runs without CLAUDE_CONFIG_DIR", dflt.environment(base)["CLAUDE_CONFIG_DIR"] == nil)

// the folder Claude Code keeps a work folder's sessions under (seen with Claude Code 2.1.318)
check("project key", QuickChatCommand.projectKey("/Users/sample/Library/Application Support/usage-n-uf/quick-chat/main")
      == "-Users-sample-Library-Application-Support-usage-n-uf-quick-chat-main")
check("project key, dots and dashes", QuickChatCommand.projectKey("/private/tmp/a-1/.b_c") == "-private-tmp-a-1--b-c")
// Claude Code counts UTF-16 units: an emoji is two, so two dashes; an accented letter one
check("project key, beyond ASCII", QuickChatCommand.projectKey("/Users/Dé/😀b") == "-Users-D----b", QuickChatCommand.projectKey("/Users/Dé/😀b"))

// MARK: Markdown

typealias B = QuickChatBlock
check("paragraphs", QuickChatMarkdown.blocks("One\ntwo\n\nThree") == [B.paragraph("One\ntwo"), .paragraph("Three")])
check("code, closed", QuickChatMarkdown.blocks("Use:\n```zsh\nls -la\necho hi\n```\nDone.")
      == [.paragraph("Use:"), .code(language: "zsh", text: "ls -la\necho hi"), .paragraph("Done.")])
check("code, still streaming", QuickChatMarkdown.blocks("Use:\n```swift\nlet a = 1") == [.paragraph("Use:"), .code(language: "swift", text: "let a = 1")])
check("code with no language", QuickChatMarkdown.blocks("```\nx\n```") == [.code(language: "", text: "x")])
check("code keeps blank lines and indents", QuickChatMarkdown.blocks("```\na\n\n    b\n```") == [.code(language: "", text: "a\n\n    b")])
check("tilde fence", QuickChatMarkdown.blocks("~~~py\nprint(1)\n~~~") == [.code(language: "py", text: "print(1)")])
check("bullets", QuickChatMarkdown.blocks("Opts:\n- one\n- two\n  more\n* three") == [.paragraph("Opts:"), .bullets(["one", "two more", "three"])])
check("numbered", QuickChatMarkdown.blocks("3. c\n4. d") == [.numbered(start: 3, items: ["c", "d"])])
check("heading", QuickChatMarkdown.blocks("## Steps\nText") == [.heading(level: 2, text: "Steps"), .paragraph("Text")])
check("not a heading", QuickChatMarkdown.blocks("#hashtag") == [.paragraph("#hashtag")])
check("quote", QuickChatMarkdown.blocks("> a\n> b\nc") == [.quote("a\nb"), .paragraph("c")])
check("rule", QuickChatMarkdown.blocks("a\n\n---\n\nb") == [.paragraph("a"), .rule, .paragraph("b")])
check("empty", QuickChatMarkdown.blocks("") == [])
check("a year is not a list", QuickChatMarkdown.blocks("2026. A year.") == [.paragraph("2026. A year.")])
check("inline code", QuickChatMarkdown.inline("use `ls`").runs.contains { $0.inlinePresentationIntent?.contains(.code) == true })
let links = QuickChatMarkdown.inline("[web](https://example.com) [mail](mailto:a@example.com) [file](file:///etc/hosts) [app](sample-app://x)")
let kept = links.runs.compactMap { $0.link?.scheme }
check("only web and mail links stay links", kept == ["https", "mailto"], kept)
check("a dropped link keeps its words", String(links.characters).contains("file") && String(links.characters).contains("app"))

// MARK: the process, against the stand-in

let stub = ProcessInfo.processInfo.environment["QC_STUB_PATH"] ?? ""
let work = ProcessInfo.processInfo.environment["QC_WORK"] ?? NSTemporaryDirectory() + "qc-work"
let argsFile = work + "-args.txt"
check("the stand-in is there", FileManager.default.isExecutableFile(atPath: stub), stub)

func run(_ mode: String, _ body: (QuickChatProcess, () -> [QuickChatEvent], () -> (Int32, String)?) -> Void) {
    // the stand-in's settings: beside the work folder, since `claude` gets only an allowlisted environment
    try? FileManager.default.createDirectory(atPath: work, withIntermediateDirectories: true)
    try? "mode=\(mode)\nargs=\(argsFile)\n".write(toFile: (work as NSString).deletingLastPathComponent + "/stub.conf", atomically: true, encoding: .utf8)
    try? FileManager.default.removeItem(atPath: argsFile)
    try? FileManager.default.removeItem(atPath: argsFile + ".ctl")
    let p = QuickChatProcess(QuickChatCommand(claude: stub, configDir: "/Users/sample/.claude-work", isDefaultDir: false,
                                              workFolder: work, model: "haiku"))
    var events: [QuickChatEvent] = []
    var exit: (Int32, String)?
    p.onEvent = { events.append($0) }
    p.onExit = { exit = ($0, $1) }
    do { try p.start() } catch { check("\(mode): starts", false, error); return }
    body(p, { events }, { exit })
    p.stop()
    wait(3) { exit != nil }
}

func done(_ es: [QuickChatEvent]) -> Int { es.filter { if case .done = $0 { return true }; return false }.count }

run("ok") { p, events, exit in
    wait(3) { events().contains { if case .started = $0 { return true }; return false } }
    check("ok: started", events().first == .started(session: "00000000-0000-4000-8000-000000000001", model: "claude-haiku-5-5"), events())
    check("ok: sent", p.send("first question"))
    wait(5) { done(events()) == 1 }
    let texts = events().compactMap { if case .text(let t) = $0 { return t }; return nil }.joined()
    check("ok: streamed", texts == "Answer 1", texts)
    check("ok: the limit seen", events().contains(.limit(type: "seven_day", used: 0.62, status: "allowed", resets: Date(timeIntervalSince1970: 1794776400))))
    check("ok: done", events().contains(.done(isError: false, text: "Answer 1", ms: 1200, session: "00000000-0000-4000-8000-000000000001")))
    let pid = p.pid
    check("ok: a follow-up", p.send("second question"))
    wait(5) { done(events()) == 2 }
    check("ok: the same process answered", p.isRunning && p.pid == pid && events().contains(.done(isError: false, text: "Answer 2", ms: 1200, session: "00000000-0000-4000-8000-000000000001")))
    let recorded = (try? String(contentsOfFile: argsFile, encoding: .utf8)) ?? ""
    check("ok: ran in the work folder", recorded.contains("PWD \(work)") || recorded.contains("PWD /private\(work)"), recorded)
    check("ok: on the profile's folder", recorded.contains("ENV CLAUDE_CONFIG_DIR=/Users/sample/.claude-work"))
    check("ok: traffic off", recorded.contains("ENV TRAFFIC=1"))
    check("ok: tools off", recorded.contains("ARG [--tools]\nARG []\n"))
    check("ok: no key passed on", recorded.contains("ENV KEY=<unset>") && recorded.contains("ENV TOKEN=<unset>"))
    check("ok: started once", recorded.components(separatedBy: "PID ").count == 2)
    check("ok: no exit yet", exit() == nil)
    check("ok: incognito, one process for both questions", recorded.contains("ARG [--no-session-persistence]") && !recorded.contains("ARG [--resume]"), recorded)
    // the model and thinking change in the running process, between messages, without a new one
    let modelRequest = p.setModel("sonnet")
    check("ok: set_model sent", modelRequest != nil)
    check("ok: thinking sent", p.setThinking("high"))
    check("ok: no model (Claude Code's own default) sent", p.setModel("") != nil)
    check("ok: its answer names the request and the model in effect",
          { wait(3) { events().contains(.control(id: modelRequest ?? "", error: nil, model: "claude-sonnet-5-5")) }
            return events().contains(.control(id: modelRequest ?? "", error: nil, model: "claude-sonnet-5-5")) }(), events())
    let refused = p.setModel("refuse")
    wait(3) { events().contains { if case .control(refused ?? "", let e?, _) = $0 { return e == "no such model" }; return false } }
    check("ok: a refused set_model comes back as an error",
          events().contains { if case .control(let id, let e?, _) = $0 { return id == refused && e == "no such model" }; return false }, events())
    check("ok: a third question", p.send("third question"))
    wait(5) { done(events()) == 3 }
    check("ok: the same process answered the third", p.pid == pid && events().contains(.done(isError: false, text: "Answer 3", ms: 1200, session: "00000000-0000-4000-8000-000000000001")))
    let ctlLog = (try? String(contentsOfFile: argsFile + ".ctl", encoding: .utf8)) ?? ""
    check("ok: the stand-in saw them in order, before the message",
          ctlLog.contains("CTRL set_model model=sonnet") && ctlLog.contains("CTRL apply_flag_settings") && ctlLog.contains("\"effortLevel\":\"high\"")
          && ctlLog.range(of: "CTRL set_model model=sonnet")!.lowerBound < ctlLog.range(of: "USER 3")!.lowerBound
          && ctlLog.range(of: "CTRL apply_flag_settings")!.lowerBound < ctlLog.range(of: "USER 3")!.lowerBound, ctlLog)
    check("ok: no model means the default", ctlLog.components(separatedBy: "CTRL set_model").count == 4 && ctlLog.contains("CTRL set_model  "), ctlLog)
    // the account's models: asked with `initialize`, answered as a list (nothing goes to a model)
    check("ok: initialize sent", p.initialize())
    wait(3) { events().contains { if case .models = $0 { return true }; return false } }
    let listed: [QuickChatModelEntry] = events().compactMap { e -> [QuickChatModelEntry]? in
        if case .models(let l) = e { return l }; return nil
    }.first ?? []
    check("ok: the models listed", listed.count == 7 && listed.map(\.value).contains("claude-fable-5-2"), listed)
    check("ok: newest Fable picked from the list", QuickChatModels.resolve(.fable, in: listed).value == "claude-fable-5-2")
    check("ok: the process still answers after it", p.send("fourth question") && { wait(5) { done(events()) == 4 }; return done(events()) == 4 }())
}

// the account's limits before any message: `get_usage` on a `claude` that was only started (the bar opened)
run("ok") { p, events, _ in
    check("usage: asked before any message", p.getUsage())
    wait(3) { events().contains { if case .usage = $0 { return true }; return false } }
    let u = events().compactMap { e -> QuickChatUsage? in if case .usage(let u) = e { return u }; return nil }.first
    check("usage: both windows", u?.available == true && u?.fiveHour?.used == 44 && u?.week?.used == 12 && u?.fiveHour?.locked == false, u as Any)
    check("usage: reset times, fractional seconds and offset", u?.fiveHour?.resets == Date(timeIntervalSince1970: 1_794_333_600)
          && u?.week?.resets == QuickChatParse.isoDate("2026-11-14T09:00:00Z"), u as Any)
    let ctl = (try? String(contentsOfFile: argsFile + ".ctl", encoding: .utf8)) ?? ""
    check("usage: no message was sent for it", ctl.contains("CTRL get_usage") && !ctl.contains("USER"), ctl)
    check("usage: the process still takes a message after it", p.send("a question") && { wait(5) { done(events()) == 1 }; return done(events()) == 1 }())
}

// MARK: the account's limits (Claude Code's `get_usage`)

func usageEvent(_ body: String) -> QuickChatEvent {
    QuickChatParse.event(line(#"{"type":"control_response","response":{"subtype":"success","request_id":"qc-5","response":"# + body + "}}"))
}
let locked = usageEvent(#"{"rate_limits_available":true,"rate_limits":{"five_hour":{"utilization":100,"resets_at":"2026-11-10T18:00:00Z","locked_reason":"five_hour_limit"},"seven_day":{"utilization":130.5,"resets_at":"2026-11-14T09:00:00Z"}}}"#)
check("usage: a lock is read, a share is kept within 0…100", locked == .usage(QuickChatUsage(available: true,
      fiveHour: .init(used: 100, resets: QuickChatParse.isoDate("2026-11-10T18:00:00Z"), locked: true),
      week: .init(used: 100, resets: QuickChatParse.isoDate("2026-11-14T09:00:00Z"), locked: false))), locked)
check("usage: not available says so", usageEvent(#"{"rate_limits_available":false,"rate_limits":{}}"#)
      == .usage(QuickChatUsage(available: false, fiveHour: nil, week: nil)))
check("usage: a window missing is nil, an empty lock reason isn't a lock", usageEvent(#"{"rate_limits":{"seven_day":{"utilization":5,"locked_reason":""}}}"#)
      == .usage(QuickChatUsage(available: true, fiveHour: nil, week: .init(used: 5, resets: nil, locked: false))))
check("usage: an error is just a control answer", QuickChatParse.event(line(#"{"type":"control_response","response":{"subtype":"error","request_id":"qc-6","error":"Unknown subtype"}}"#))
      == .control(id: "qc-6", error: "Unknown subtype", model: nil))
check("usage: other control answers are untouched", QuickChatParse.event(line(#"{"type":"control_response","response":{"subtype":"success","request_id":"qc-7","response":{"still_queued":[]}}}"#))
      == .control(id: "qc-7", error: nil, model: nil))
check("iso dates: Z, offset, any fraction; garbage is nil", QuickChatParse.isoDate("2026-11-14T09:00:00Z") == Date(timeIntervalSince1970: 1_794_646_800)
      && QuickChatParse.isoDate("2026-11-14T11:00:00.5+02:00") == Date(timeIntervalSince1970: 1_794_646_800)
      && QuickChatParse.isoDate("2026-11-14T09:00:00.123456789Z") == Date(timeIntervalSince1970: 1_794_646_800)
      && QuickChatParse.isoDate("soon") == nil)
check("usage: a stale answer's filter lets it through", { var s = StaleAnswers(); s.abandon(); return s.fate(of: .usage(QuickChatUsage(available: true))) == .pass }())

// MARK: the account's models (Claude Code's `initialize`)

let initLine = #"{"type":"control_response","response":{"subtype":"success","request_id":"qc-9","response":{"models":[{"value":"default","displayName":"Opus 5.5","supportedEffortLevels":["low","high"]},{"value":"opus","displayName":"Opus 5.5","description":"For the hardest work","supportedEffortLevels":["low","medium","high","xhigh","max"]},{"value":"claude-fable-5-2","displayName":"Fable 5.2","supportedEffortLevels":["low","medium","high","xhigh","max"]},{"value":"fable","displayName":"Fable 5.1"},{"value":"claude-sonnet-5-5","displayName":"Sonnet 5.5","supportedEffortLevels":["low","medium","high","xhigh"]},{"value":"sonnet-old","displayName":"Sonnet 5","supportedEffortLevels":["low"]},{"value":"haiku","displayName":"Haiku 5.5","supportsEffort":false},{"value":"other","displayName":"Something else"},{"displayName":"No value"}]}}}"#
let ml: [QuickChatModelEntry] = { if case .models(let l) = QuickChatParse.event(line(initLine)) { return l }; return [] }()
check("models: parsed, entries without a value left out", ml.count == 8, ml)
check("models: efforts read", ml.first { $0.value == "opus" }?.efforts == ["low", "medium", "high", "xhigh", "max"] && ml.first { $0.value == "opus" }?.description == "For the hardest work")
check("models: no effort said is nil, supportsEffort false is none", ml.first { $0.value == "fable" }?.efforts == nil && ml.first { $0.value == "haiku" }?.efforts == [])
check("models: another control answer is still a control", QuickChatParse.event(line(#"{"type":"control_response","response":{"subtype":"success","request_id":"qc-2","response":{"model":"claude-sonnet-5-5"}}}"#))
      == .control(id: "qc-2", error: nil, model: "claude-sonnet-5-5"))
let nw = QuickChatModels.newest(ml)
check("models: the newest of each family, not the alias", nw[.fable]?.value == "claude-fable-5-2" && nw[.sonnet]?.value == "claude-sonnet-5-5"
      && nw[.opus]?.value == "opus" && nw[.haiku]?.value == "haiku", nw)
check("models: default and unknown names left out", !nw.values.contains { $0.value == "default" || $0.value == "other" })
check("models: versions compare by number", QuickChatModels.newer([5, 10], than: [5, 2]) && QuickChatModels.newer([5, 1, 1], than: [5, 1]) && !QuickChatModels.newer([5], than: [5, 0]))
let noFable = ml.filter { !$0.displayName.hasPrefix("Fable") }
check("models: a family missing goes to the nearest, lighter first", QuickChatModels.resolve(.fable, in: noFable).family == .opus
      && QuickChatModels.resolve(.sonnet, in: ml.filter { !$0.displayName.hasPrefix("Sonnet") }).family == .haiku)
let before = QuickChatModels.resolve(.fable, in: nil)
check("models: before any list, the alias", before.family == .fable && before.value == "fable" && before.entry == nil)
check("thinking: the model's steps, Off first", QuickChatModels.steps(nw[.sonnet], listKnown: true) == ["off", "low", "medium", "high", "xhigh"])
check("thinking: no list, Low to High", QuickChatModels.steps(nil, listKnown: false) == ["off", "low", "medium", "high"])
check("thinking: a model with no efforts, Off only", QuickChatModels.steps(nw[.haiku], listKnown: true) == ["off"])
check("thinking: a model that doesn't say, Low to High", QuickChatModels.steps(QuickChatModelEntry(value: "x", displayName: "Opus 9"), listKnown: true) == ["off", "low", "medium", "high"])
let tie = QuickChatModels.newest([.init(value: "opus[1m]", displayName: "Opus 5.5 (1M context)"), .init(value: "opus", displayName: "Opus 5.5")])
check("models: a tie goes to the plain one, not a variant", tie[.opus]?.value == "opus", tie)
check("thinking: clamped to the nearest, lighter first", QuickChatModels.clamp("max", to: ["off", "low", "medium", "high"]) == "high"
      && QuickChatModels.clamp("medium", to: ["off", "low", "high"]) == "low" && QuickChatModels.clamp("high", to: ["off"]) == "off"
      && QuickChatModels.clamp("xhigh", to: ["off", "low", "medium", "high", "xhigh"]) == "xhigh")
// a list as Claude Code gives it on some accounts: each family by name alone, the version in its description
let bare: [QuickChatModelEntry] = [
    .init(value: "default", displayName: "Default (recommended)", description: "Opus 5.5 · Best for everyday, complex tasks"),
    .init(value: "opus", displayName: "Opus", description: "Opus 5.5 · Best for everyday, complex tasks"),
    .init(value: "claude-fable-5-1[1m]", displayName: "Fable", description: "Fable 5.1 · Most capable for your hardest tasks"),
    .init(value: "sonnet", displayName: "Sonnet", description: "Sonnet 5.5 · Efficient for routine tasks"),
    .init(value: "haiku", displayName: "Haiku", description: "Haiku 5.5 · Fastest for quick answers"),
]
let bareNewest = QuickChatModels.newest(bare)
check("models: bare names count, all four families", bareNewest.count == 4 && bareNewest[.fable]?.value == "claude-fable-5-1[1m]", bareNewest)
check("models: the version from the description", QuickChatModels.family(bare[1])! == (.opus, [5, 5])
      && QuickChatModels.title(bare[2]) == "Fable 5.1")
check("models: a bare name with no version anywhere", QuickChatModels.family(.init(value: "x", displayName: "Sonnet"))! == (.sonnet, [])
      && QuickChatModels.title(.init(value: "x", displayName: "Sonnet")) == "Sonnet")
check("models: a numbered one beats a bare one that isn't the alias", QuickChatModels.newest([.init(value: "sonnet-x", displayName: "Sonnet"),
      .init(value: "s55", displayName: "Sonnet 5.5")])[.sonnet]?.value == "s55")
check("models: the bare alias stands for the newest, beating an older numbered one",
      QuickChatModels.newest([.init(value: "claude-opus-4-1", displayName: "Opus 4.1"), .init(value: "opus", displayName: "Opus")])[.opus]?.value == "opus"
      && QuickChatModels.newest([.init(value: "opus", displayName: "Opus"), .init(value: "claude-opus-4-1", displayName: "Opus 4.1")])[.opus]?.value == "opus")
check("models: a description starting with Claude", QuickChatModels.title(.init(value: "opus", displayName: "Opus", description: "Claude Opus 5.5 · …")) == "Opus 5.5"
      && QuickChatModels.title(.init(value: "x", displayName: "Claude Sonnet 5.5")) == "Sonnet 5.5")
// the model and thinking controls: a step up or down a list of 2 to 6 (the scroll wheel, ⌥⌘ arrows), and the cost tint
let fams: [QuickChatModelChoice] = [.haiku, .sonnet, .opus]
check("steps: up and down", QuickChatModels.step(fams, from: .sonnet, by: 1) == .opus && QuickChatModels.step(fams, from: .sonnet, by: -1) == .haiku)
check("steps: nothing past the ends", QuickChatModels.step(fams, from: .opus, by: 1) == nil && QuickChatModels.step(fams, from: .haiku, by: -1) == nil)
check("steps: from a step not in the list, up is the first, down none",
      QuickChatModels.step(fams, from: .fable, by: 1) == .haiku && QuickChatModels.step(fams, from: .fable, by: -1) == nil)
check("steps: an empty list has no step", QuickChatModels.step([QuickChatModelChoice](), from: .opus, by: 1) == nil)
check("steps: thinking, Off to Low and Max as the top",
      QuickChatModels.step(["off", "low", "medium", "high", "xhigh", "max"], from: "off", by: 1) == "low"
      && QuickChatModels.step(["off", "low", "medium", "high", "xhigh", "max"], from: "max", by: 1) == nil)
check("cost: Fable, Extra and Max", QuickChatModels.costly(.fable) && !QuickChatModels.costly(.opus)
      && QuickChatModels.costly(effort: "xhigh") && QuickChatModels.costly(effort: "max") && !QuickChatModels.costly(effort: "high")
      && !QuickChatModels.costly(effort: nil))
check("cost: the tint is stronger when both are costly", QuickChatModels.tint(own: true, other: false) == 1
      && QuickChatModels.tint(own: true, other: true) == 2 && QuickChatModels.tint(own: false, other: true) == 0)
// settings.json's model: an old "profile" doesn't decode (the settings read it as Haiku, the default), "fable" does
struct SavedModel: Decodable { var model: QuickChatModelChoice }
check("settings: an old saved \"profile\" isn't a model", (try? JSONDecoder().decode(SavedModel.self, from: Data(#"{"model":"profile"}"#.utf8))) == nil)
check("settings: fable is", (try? JSONDecoder().decode(SavedModel.self, from: Data(#"{"model":"fable"}"#.utf8)))?.model == .fable)

setenv("ANTHROPIC_API_KEY", "sk-sample-should-not-pass", 1)
setenv("CLAUDE_CODE_OAUTH_TOKEN", "sample-should-not-pass", 1)
run("auth") { p, events, exit in
    p.send("hi")
    wait(5) { done(events()) == 1 }
    check("auth: the error", events().contains(.message(text: "Not logged in · Please run /login", model: "<synthetic>", error: "authentication_failed")), events())
    check("auth: an error result", events().contains { if case .done(true, _, _, _) = $0 { return true }; return false })
    let recorded = (try? String(contentsOfFile: argsFile, encoding: .utf8)) ?? ""
    check("auth: the Mac's API key and token not passed on", recorded.contains("ENV KEY=<unset>") && recorded.contains("ENV TOKEN=<unset>"), recorded)
}
unsetenv("ANTHROPIC_API_KEY")
unsetenv("CLAUDE_CODE_OAUTH_TOKEN")

run("crash") { p, events, exit in
    p.send("hi")
    wait(5) { exit() != nil }
    check("crash: the half answer arrived", events().contains(.text("Half an ans")))
    check("crash: its exit", exit()?.0 == 3, exit() as Any)
    check("crash: what it said", exit()?.1.contains("sample failure for the checks") == true, exit() as Any)
    check("crash: sending again fails quietly", p.send("again") == false)
}

run("slow") { p, events, exit in
    p.send("hi")
    wait(5) { events().contains(.text("Half an ans")) }
    let t0 = Date()
    p.stop()
    wait(5) { exit() != nil }
    check("slow: Stop ends it", exit() != nil && Date().timeIntervalSince(t0) < 3, Date().timeIntervalSince(t0))
    check("slow: Stop twice is harmless", { p.stop(); return true }())
}

// Stop with the conversation kept: an interrupt control request, the aborted answer ends with its own `done`, and the same
// process answers the next message (it counts messages, so a new process would say "Answer 1")
run("abort") { p, events, exit in
    p.send("long question")
    wait(5) { events().contains(.text("Half an ans")) }
    let pid = p.pid
    check("abort: interrupt sent", p.interrupt())
    wait(5) { done(events()) == 1 }
    let first = events().first { if case .done = $0 { return true }; return false }
    check("abort: the aborted answer ends with an error result", { if case .done(true, _, _, _)? = first { return true }; return false }(), first as Any)
    check("abort: the process lives", p.isRunning && exit() == nil)
    check("abort: the next message goes to the same process", p.send("short question"))
    wait(5) { done(events()) == 2 }
    check("abort: and is answered, the conversation going on", p.pid == pid && events().contains(.done(isError: false, text: "Answer 2", ms: 1200, session: "00000000-0000-4000-8000-000000000001")), events())
    let ctlLog = (try? String(contentsOfFile: argsFile + ".ctl", encoding: .utf8)) ?? ""
    check("abort: the stand-in got the interrupt between the two messages",
          ctlLog.contains("CTRL interrupt") && ctlLog.range(of: "USER 1")!.lowerBound < ctlLog.range(of: "CTRL interrupt")!.lowerBound
          && ctlLog.range(of: "CTRL interrupt")!.lowerBound < ctlLog.range(of: "USER 2")!.lowerBound, ctlLog)
}

// a `claude` that isn't there: start throws, nothing crashes
let missing = QuickChatProcess(QuickChatCommand(claude: "/nonexistent/claude", configDir: "/x", isDefaultDir: false, workFolder: work, model: ""))
check("a missing claude throws", (try? missing.start()) == nil)
check("a missing claude can't be sent to", missing.send("hi") == false)
check("a missing claude can't be interrupted or told a model", missing.interrupt() == false && missing.setModel("haiku") == nil && missing.setThinking(nil) == false)

// MARK: a profile's accounts (Accounts.swift), sample addresses only

do {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var list: [KnownAccount] = []
    AccountBook.note(&list, uuid: "u1", email: "ultra-1@example.com", now: t0)
    check("accounts: the first is added", list.count == 1 && list[0].uuid == "u1")
    check("accounts: the same one within the hour changes nothing",
          AccountBook.note(&list, uuid: "u1", email: "ultra-1@example.com", now: t0.addingTimeInterval(600)).changed == false)
    check("accounts: after the hour its time moves",
          AccountBook.note(&list, uuid: "u1", email: "ultra-1@example.com", now: t0.addingTimeInterval(7200)).changed && list.count == 1)
    AccountBook.note(&list, uuid: "u2", email: "ultra-2@example.com", now: t0)
    check("accounts: another uuid is another account", list.count == 2)
    // the same address under another uuid (a second organization) is not the first account
    AccountBook.note(&list, uuid: "u3", email: "ultra-1@example.com", now: t0)
    check("accounts: one address under two uuids stays two accounts", list.count == 3 && list.filter { $0.email == "ultra-1@example.com" }.count == 2, list)
    // a file that had no accountUuid and now has one: the placeholder becomes the real uuid
    var old = [KnownAccount(uuid: "email:ultra-4@example.com", email: "Ultra-4@example.com", lastSeen: t0)]
    let r = AccountBook.note(&old, uuid: "u4", email: "ultra-4@example.com", now: t0)
    check("accounts: a placeholder uuid is replaced by the real one", old.count == 1 && old[0].uuid == "u4" && r.replaced == "email:ultra-4@example.com", old)
    check("accounts: a real uuid is never found by its address", { var l = [KnownAccount(uuid: "u5", email: "ultra-5@example.com")]
        AccountBook.note(&l, uuid: "email:ultra-5@example.com", email: "ultra-5@example.com"); return l.count == 2 }())
    check("accounts: week key", AccountBook.levelKey("main", "u1") == "main|u1")

    // the folder's file: a reload asked for while another read of it is under way still sees the file as it is now
    let dir = NSTemporaryDirectory() + "cl_quick-checks-\(getpid())"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let file = dir + "/.claude.json"
    func writeAccount(_ uuid: String, _ email: String, mtime: Date) {
        let j = #"{"oauthAccount":{"accountUuid":"\#(uuid)","emailAddress":"\#(email)","planDisplayName":"max"}}"#
        try? j.write(toFile: file, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: file)
    }
    writeAccount("u1", "ultra-1@example.com", mtime: t0)
    check("folder: the first look reads the file", FolderFiles.kept(file).uuid == "u1" && FolderFiles.kept(file).plan == "Max")
    writeAccount("u2", "ultra-2@example.com", mtime: t0.addingTimeInterval(5))      // the sign-in landed
    check("folder: the kept value doesn't move by itself", FolderFiles.kept(file).uuid == "u1")
    var first: Bool?, second: Bool?, seen: String?
    FolderFiles.reload([file]) { first = $0 }                    // a read under way ...
    FolderFiles.reload([file]) { second = $0; seen = FolderFiles.kept(file).uuid }       // ... then what ask() does
    wait(5) { second != nil }
    check("folder: a reload behind another read sees the new account", seen == "u2", seen as Any)
    check("folder: the first read said an account changed, the next had nothing new", first == true && second == false, (first as Any, second as Any))
    // an older read finishing after a newer one never takes its place
    let file2 = dir + "/second.json"
    _ = FolderFiles.keep(FolderRead(mtime: t0.addingTimeInterval(20), email: "ultra-2@example.com", uuid: "u2", plan: nil), for: file2)
    let late = FolderFiles.keep(FolderRead(mtime: t0.addingTimeInterval(10), email: "ultra-1@example.com", uuid: "u1", plan: nil), for: file2)
    check("folder: an older read doesn't overwrite a newer one", FolderFiles.kept(file2).uuid == "u2" && late.uuid == "u2", late)
    _ = FolderFiles.keep(FolderRead(mtime: t0.addingTimeInterval(30), email: "ultra-3@example.com", uuid: "u3", plan: nil), for: file2)
    check("folder: a newer read replaces an older one", FolderFiles.kept(file2).uuid == "u3")
    _ = FolderFiles.keep(FolderRead(mtime: t0.addingTimeInterval(30), email: "ultra-4@example.com", uuid: "u4", plan: nil), for: file2)
    check("folder: the same time takes the later read", FolderFiles.kept(file2).uuid == "u4")
    _ = FolderFiles.keep(FolderRead(mtime: nil, email: nil, uuid: nil, plan: nil), for: file2)
    check("folder: a file that went away takes its place", FolderFiles.kept(file2).uuid == nil)
    try? FileManager.default.removeItem(atPath: dir)

    // what a `claude` reports belongs to the account it started on, whatever the chat's target says later
    var trail = AccountTrail()
    check("trail: nothing running, nothing to report on", trail.reportAccount == nil)
    trail.processStarted(on: "u1")
    let targetNow = "u2"        // the folder moved to another account while the answer was on its way
    check("trail: a report goes to the account the process started on", trail.reportAccount == "u1" && trail.reportAccount != targetNow)
    // incognito: the conversation lives only in the running process, so it goes on only on the account that process started on
    check("trail: a chat goes on on the account its process started on", trail.canContinue(on: "u1"))
    check("trail: it isn't gone on with on another account, or none", !trail.canContinue(on: "u2") && !trail.canContinue(on: nil))
    trail.processEnded()
    check("trail: the conversation ends with its process, a new chat can begin on any account",
          trail.canContinue(on: "u2") && trail.canContinue(on: "u1") && trail.canContinue(on: nil))
    check("trail: a process that ended reports nowhere", trail.reportAccount == nil)
    var noAccount = AccountTrail()
    noAccount.processStarted(on: nil)       // a folder whose file names no account
    check("trail: a chat begun with no account doesn't go on on one that appears", noAccount.canContinue(on: nil) && !noAccount.canContinue(on: "u1"))

    // an older levels.json, keyed by profile id (the values stand for weeks)
    let legacy: [String: Int] = ["main": 50, "work": 20, "gone": 7, "main|u9": 33]
    let moved = AccountBook.migrated(legacy) { id in id == "main" ? "u1" : id == "work" ? nil : nil }
    check("migration: a week goes to the account signed in now", moved["main|u1"] == 50 && moved["main"] == nil, moved)
    check("migration: a week that can't be placed stays under its key", moved["work"] == 20 && moved["gone"] == 7, moved)
    check("migration: a per-account week stays", moved["main|u9"] == 33 && moved.count == 4, moved)
    check("migration: a per-account week wins over the legacy one", AccountBook.migrated(["main": 1, "main|u1": 2]) { _ in "u1" } == ["main|u1": 2])
    check("migration: a second run changes nothing", AccountBook.migrated(moved) { id in id == "main" ? "u1" : nil } == moved)
    // removing a profile takes its weeks, per account and the bare one
    let left = AccountBook.removing(profile: "main", from: moved)
    check("remove: every week of the profile goes, others stay", left == ["work": 20, "gone": 7], left)
    check("remove: a profile whose id starts the same stays", AccountBook.removing(profile: "main", from: ["main-2|u1": 1, "main": 2]) == ["main-2|u1": 1])

    // forgetting a standby account takes it from the list and its week from the levels, nothing else
    let known = [KnownAccount(uuid: "u1", email: "ultra-1@example.com"), KnownAccount(uuid: "u2", email: "ultra-2@example.com")]
    let weeks: [String: Int] = ["main|u1": 50, "main|u2": 20, "work|u2": 9]
    let gone = AccountBook.forgetting("u2", of: "main", accounts: known, levels: weeks, inUse: "u1")
    check("forget: the account leaves the list", gone?.accounts.map(\.uuid) == ["u1"], gone as Any)
    check("forget: its week goes, other weeks stay (another profile's too)", gone?.levels == ["main|u1": 50, "work|u2": 9], gone as Any)
    check("forget: the account in use can't be forgotten", AccountBook.forgetting("u1", of: "main", accounts: known, levels: weeks, inUse: "u1") == nil)
    check("forget: an account that isn't there changes nothing", AccountBook.forgetting("u9", of: "main", accounts: known, levels: weeks, inUse: "u1") == nil)
    check("forget: with nothing signed in, any account can go", AccountBook.forgetting("u1", of: "main", accounts: known, levels: weeks, inUse: nil)?.accounts.count == 1)
    // one account, one profile: by uuid or by address, the same rule the first run uses
    func acct(_ u: String, _ e: String) -> (uuid: String, email: String) { (u, e) }
    let used = [(name: "Main", inUse: Optional(acct("u1", "ultra-1@example.com"))), (name: "Work", inUse: Optional(acct("u2", "ultra-2@example.com"))),
                (name: "Out", inUse: nil as (uuid: String, email: String)?)]
    check("one profile: an account in use on a profile is named", AccountBook.profileUsing(acct("u1", "ultra-1@example.com"), among: used) == "Main")
    check("one profile: found by uuid, whatever the address", AccountBook.profileUsing(acct("u2", "other@example.com"), among: used) == "Work")
    check("one profile: found by address in any case, whatever the uuid", AccountBook.profileUsing(acct("u9", "Ultra-1@Example.com"), among: used) == "Main")
    check("one profile: a free account is free", AccountBook.profileUsing(acct("u3", "ultra-3@example.com"), among: used) == nil)
    check("one profile: a folder signed out uses nothing", AccountBook.profileUsing(acct("u3", "ultra-3@example.com"), among: [used[2]]) == nil)
    check("one profile: a placeholder uuid is found by its address", AccountBook.profileUsing(acct("email:ultra-1@example.com", "ultra-1@example.com"), among: used) == "Main")
    // a placeholder uuid given a real one by the sign-in is still the same account
    check("same sign-in: the same uuid", AccountBook.unchanged(from: ("u1", "ultra-1@example.com"), now: ("u1", "ultra-1@example.com")))
    check("same sign-in: a placeholder upgraded to a real uuid", AccountBook.unchanged(from: ("email:ultra-1@example.com", "Ultra-1@example.com"), now: ("u1", "ultra-1@example.com")))
    check("same sign-in: another uuid is another account", !AccountBook.unchanged(from: ("u1", "ultra-1@example.com"), now: ("u2", "ultra-1@example.com")))
    check("same sign-in: a placeholder and another address", !AccountBook.unchanged(from: ("email:ultra-1@example.com", "ultra-1@example.com"), now: ("u2", "ultra-2@example.com")))
    let ph = [KnownAccount(uuid: "email:ultra-1@example.com", email: "ultra-1@example.com"), KnownAccount(uuid: "u2", email: "ultra-2@example.com")]
    check("forget: a placeholder for the address in use isn't forgotten", AccountBook.forgetting("email:ultra-1@example.com", of: "main", accounts: ph, levels: weeks, inUse: "u1", inUseEmail: "Ultra-1@example.com") == nil)
    check("forget: a placeholder for another address can go", AccountBook.forgetting("email:ultra-1@example.com", of: "main", accounts: ph, levels: weeks, inUse: "u2", inUseEmail: "ultra-2@example.com") != nil)
    // Sign in again… only while the sign-in is broken: signed out, or the last answer failed to authenticate on this account
    let inUse1 = Optional(acct("u1", "ultra-1@example.com"))
    check("broken: a working sign-in isn't", AccountBook.signInProblem(signedIn: inUse1, failedOn: nil) == nil)
    check("broken: no account signed in is signed out", AccountBook.signInProblem(signedIn: nil, failedOn: nil) == .signedOut)
    check("broken: signed out wins over a flag", AccountBook.signInProblem(signedIn: nil, failedOn: "u1") == .signedOut)
    check("broken: an authentication failure on the account in use", AccountBook.signInProblem(signedIn: inUse1, failedOn: "u1") == .stopped)
    check("broken: a failure on another account says nothing about this one", AccountBook.signInProblem(signedIn: inUse1, failedOn: "u2") == nil)
    check("broken: the words", SignInProblem.signedOut.words == "Signed out." && SignInProblem.stopped.words == "The sign-in stopped working.")
    check("forget: an account without a week", AccountBook.forgetting("u2", of: "main", accounts: known, levels: ["main|u1": 50], inUse: "u1")?.levels == ["main|u1": 50])
    // a switch's confirmation says what it affects: Claude Code on the folder, not the Claude app
    let sw0 = AccountBook.switchWords(folder: "~/.claude", email: "a•••@example.com", isDefault: true)
    check("switch words: ~/.claude", sw0.hasPrefix("Claude Code in Terminal and editors on ~/.claude moves to a•••@example.com, sessions running now included")
          && sw0.contains("the Claude app keeps its own sign-in"))
    check("switch words: another folder", AccountBook.switchWords(folder: "~/.claude-work", email: "s•••@work.example", isDefault: false)
          .hasPrefix("Claude Code pointed at ~/.claude-work with CLAUDE_CONFIG_DIR moves to s•••@work.example"))
    // a standby account's "last in use"
    let n0 = Date(timeIntervalSince1970: 1_800_000_000)
    check("ago: the steps", AccountBook.ago(n0.addingTimeInterval(-30), now: n0) == "just now" && AccountBook.ago(n0.addingTimeInterval(-720), now: n0) == "12 min ago"
          && AccountBook.ago(n0.addingTimeInterval(-3 * 3600), now: n0) == "3 h ago" && AccountBook.ago(n0.addingTimeInterval(-30 * 3600), now: n0) == "yesterday"
          && AccountBook.ago(n0.addingTimeInterval(-21 * 86400), now: n0) == "3 weeks ago" && AccountBook.ago(n0.addingTimeInterval(60), now: n0) == "just now")
}

try? FileManager.default.removeItem(atPath: argsFile)
print("quick chat checks: \(passed)/\(passed + failed) passed")
exit(failed == 0 ? 0 : 1)
