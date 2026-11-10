// QuickChatEngine: the quick chat's talk with Claude Code (issue #11).
//
// One `claude` process per chat, kept open between messages: print mode with stream-json in and out, no tools, no MCP
// servers, no settings files, no slash commands, and Claude Code's non-essential traffic off. It runs on the profile's
// own folder (CLAUDE_CONFIG_DIR), so it answers on the account the profile has in use (and counts against its limits),
// and in quick chat's own work folder. Incognito: it keeps no session (`--no-session-persistence`), so the conversation
// lives only in that process and ends with it. Nothing else is sent anywhere.
//
// Everything here but `QuickChatProcess` is a plain function of its input, for the checks (Checks/quick-chat).

import Foundation

// MARK: - What Claude Code prints

/// One line Claude Code printed (stream-json), as the quick chat needs it.
enum QuickChatEvent: Equatable {
    /// The session started: its id and the model that answers ("claude-haiku-5-5").
    case started(session: String, model: String)
    /// A piece of the answer as it streams.
    case text(String)
    /// A piece of its thinking as it streams.
    case thinking(String)
    /// A whole message from Claude: its text, the model, and an error Claude Code reports with it
    /// ("authentication_failed", "rate_limit", …).
    case message(text: String, model: String, error: String?)
    /// The account's limit as Claude Code saw it: the share used (0…1) of the window it names, and when it resets.
    case limit(type: String?, used: Double?, status: String?, resets: Date?)
    /// The answer is done (or failed): Claude Code's last words, how long it took, the session.
    case done(isError: Bool, text: String, ms: Int, session: String)
    /// Claude Code's answer to a control request we sent (its request id): an error is its own words. The control
    /// response to a `set_model` names the model now in effect ("claude-sonnet-5-5").
    case control(id: String, error: String?, model: String?)
    /// The models this account can use, from Claude Code's answer to `initialize` (sent when `claude` starts; nothing
    /// goes to a model for it).
    case models([QuickChatModelEntry])
    case ignored
}

/// One model Claude Code offers: what `--model` and `set_model` take ("claude-fable-5-2", "opus"), its name ("Fable 5.2")
/// and the thinking efforts it takes ("low" … "max"; nil when Claude Code doesn't say).
struct QuickChatModelEntry: Codable, Equatable {
    var value: String
    var displayName: String
    var description: String? = nil
    var efforts: [String]? = nil
}

/// The model a chat answers with: one of four families, from the lightest on; each is the newest of its family the
/// account has (QuickChatModels). Saved settings keep the family, never a version; an older settings file's
/// "profile" (the profile's own default, gone) reads as Haiku, the default.
enum QuickChatModelChoice: String, CaseIterable, Codable, Identifiable {
    case haiku, sonnet, opus, fable
    var id: String { rawValue }
    var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    /// A few words in a picker, when Claude Code's list gives none.
    var blurb: String {
        switch self {
        case .haiku: return "fast, light on the week"
        case .sonnet: return "for harder questions"
        case .opus: return "for the hardest questions; uses the week fast"
        case .fable: return "Claude's Fable family; uses the week fast"
        }
    }
}

/// Choosing from Claude Code's own list: plain functions, for the checks.
enum QuickChatModels {
    /// Claude Code's thinking efforts, in order; "off" is thinking disabled.
    static let effortOrder = ["off", "low", "medium", "high", "xhigh", "max"]
    /// Before any list is known (a first run): the aliases, and Low to High.
    static let fallbackEfforts = ["low", "medium", "high"]

    /// "Fable 5.2" → (fable, [5, 2]); a name that isn't one of the four families, or has no version, is nil.
    static func family(_ e: QuickChatModelEntry) -> (QuickChatModelChoice, [Int])? {
        let words = e.displayName.split(separator: " ")
        guard words.count >= 2, let f = QuickChatModelChoice(rawValue: words[0].lowercased()) else { return nil }
        let v = words[1].split(separator: ".").compactMap { Int($0) }
        return v.isEmpty ? nil : (f, v)
    }

    /// The newest of each family in the list ("default" and older versions are left out). A family the account
    /// doesn't have is missing.
    static func newest(_ list: [QuickChatModelEntry]) -> [QuickChatModelChoice: QuickChatModelEntry] {
        var best: [QuickChatModelChoice: (QuickChatModelEntry, [Int])] = [:]
        for e in list where e.value != "default" {
            guard let (f, v) = family(e) else { continue }
            if let b = best[f], !newer(v, than: b.1) { continue }
            best[f] = (e, v)
        }
        return best.mapValues(\.0)
    }

    /// [5, 2] is newer than [5, 1] and [5]; [5, 1, 1] newer than [5, 1].
    static func newer(_ a: [Int], than b: [Int]) -> Bool {
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// The family a chat answers with: the one asked for when the account has it, else the nearest it has (the lighter
    /// one first); with no list known, the one asked for, by its alias.
    static func resolve(_ f: QuickChatModelChoice, in list: [QuickChatModelEntry]?) -> (family: QuickChatModelChoice, value: String, entry: QuickChatModelEntry?) {
        guard let list else { return (f, f.rawValue, nil) }
        let have = newest(list)
        if let e = have[f] { return (f, e.value, e) }
        let all = QuickChatModelChoice.allCases, i = all.firstIndex(of: f)!
        for d in 1..<all.count {
            for j in [i - d, i + d] where all.indices.contains(j) {
                if let e = have[all[j]] { return (all[j], e.value, e) }
            }
        }
        return (f, f.rawValue, nil)       // a list with none of the four: the alias, and Claude Code decides
    }

    /// The thinking steps a model takes: Off, then its efforts in order. With no list known, Low to High; a model that
    /// names none takes Off only.
    static func steps(_ entry: QuickChatModelEntry?, listKnown: Bool) -> [String] {
        let efforts = listKnown ? (entry?.efforts ?? []) : fallbackEfforts
        return ["off"] + effortOrder.dropFirst().filter { efforts.contains($0) }
    }

    /// The step asked for when the model takes it, else the nearest it takes (the lighter one first).
    static func clamp(_ effort: String, to steps: [String]) -> String {
        if steps.contains(effort) { return effort }
        guard let i = effortOrder.firstIndex(of: effort) else { return "off" }
        for d in 1..<effortOrder.count {
            for j in [i - d, i + d] where effortOrder.indices.contains(j) && steps.contains(effortOrder[j]) { return effortOrder[j] }
        }
        return "off"
    }
}

enum QuickChatParse {
    /// One line of stream-json output. Lines it doesn't know are ignored, never an error.
    static func event(_ line: Data) -> QuickChatEvent {
        guard let o = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any], let type = o["type"] as? String else {
            return .ignored
        }
        switch type {
        case "system":
            guard o["subtype"] as? String == "init", let s = o["session_id"] as? String else { return .ignored }
            return .started(session: s, model: o["model"] as? String ?? "")
        case "stream_event":
            guard let e = o["event"] as? [String: Any], e["type"] as? String == "content_block_delta",
                  let d = e["delta"] as? [String: Any] else { return .ignored }
            switch d["type"] as? String {
            case "text_delta": return (d["text"] as? String).map { .text($0) } ?? .ignored
            case "thinking_delta": return (d["thinking"] as? String).map { .thinking($0) } ?? .ignored
            default: return .ignored
            }
        case "assistant":
            guard let m = o["message"] as? [String: Any] else { return .ignored }
            let blocks = m["content"] as? [[String: Any]] ?? []
            let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
            return .message(text: text, model: m["model"] as? String ?? "", error: o["error"] as? String)
        case "rate_limit_event":
            guard let info = o["rate_limit_info"] as? [String: Any] else { return .ignored }
            let kind = info["rateLimitType"] as? String
            let window = (info["unifiedWindows"] as? [String: Any])?[kind ?? ""] as? [String: Any]
            let used = (window?["utilization"] as? NSNumber)?.doubleValue ?? (info["utilization"] as? NSNumber)?.doubleValue
            let resets = ((window?["resetsAt"] ?? info["resetsAt"]) as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            return .limit(type: kind, used: used, status: (window?["status"] ?? info["status"]) as? String, resets: resets)
        case "control_response":
            guard let r = o["response"] as? [String: Any], let id = r["request_id"] as? String else { return .ignored }
            let error = r["subtype"] as? String == "error" ? ((r["error"] as? String) ?? "refused") : nil
            // the answer to `initialize`: the account's models
            if error == nil, let list = (r["response"] as? [String: Any])?["models"] as? [[String: Any]] {
                return .models(list.compactMap(modelEntry))
            }
            return .control(id: id, error: error, model: (r["response"] as? [String: Any])?["model"] as? String)
        case "result":
            return .done(isError: o["is_error"] as? Bool ?? false, text: o["result"] as? String ?? "",
                         ms: (o["duration_ms"] as? NSNumber)?.intValue ?? 0, session: o["session_id"] as? String ?? "")
        default:
            return .ignored
        }
    }

    /// One entry of `initialize`'s models: its value and name, and the efforts it takes (none, when Claude Code says it
    /// takes no effort; nil when it doesn't say).
    static func modelEntry(_ m: [String: Any]) -> QuickChatModelEntry? {
        guard let value = m["value"] as? String, let name = m["displayName"] as? String else { return nil }
        let efforts = (m["supportedEffortLevels"] as? [String]) ?? ((m["supportsEffort"] as? Bool) == false ? [] : nil)
        return QuickChatModelEntry(value: value, displayName: name, description: m["description"] as? String, efforts: efforts)
    }

    /// One message for Claude Code's input (stream-json), ending in a newline.
    static func userLine(_ text: String) -> Data {
        let o: [String: Any] = ["type": "user", "message": ["role": "user", "content": text]]
        var d = (try? JSONSerialization.data(withJSONObject: o)) ?? Data()
        d.append(0x0A)
        return d
    }

    /// A control request for Claude Code's input (stream-json), ending in a newline: "interrupt" stops the answer under
    /// way and keeps the conversation; "set_model" (no model: the profile's default) and "apply_flag_settings" change
    /// the model and thinking for the next answers. Claude Code answers each with a control_response, which is ignored.
    static func controlLine(id: String, subtype: String, _ fields: [String: Any] = [:]) -> Data {
        var request: [String: Any] = ["subtype": subtype]
        for (k, v) in fields { request[k] = v }
        let o: [String: Any] = ["type": "control_request", "request_id": id, "request": request]
        var d = (try? JSONSerialization.data(withJSONObject: o)) ?? Data()
        d.append(0x0A)
        return d
    }

    /// The settings that put thinking where the chat's picker is: off, or on at Claude Code's effort.
    static func thinkingSettings(_ effort: String?) -> [String: Any] {
        if let effort { return ["alwaysThinkingEnabled": true, "effortLevel": effort] }
        return ["alwaysThinkingEnabled": false]
    }

    /// Claude Code refused because a limit of the account is full: its error says so ("rate_limit"), or its words do
    /// ("Claude AI usage limit reached|1794776400", "You've hit your limit · resets 5pm", "5-hour limit reached").
    static func isLimit(error: String?, text: String) -> Bool {
        if let e = error?.lowercased(), e.contains("rate_limit") || e.contains("usage_limit") { return true }
        let t = text.lowercased()
        return t.contains("usage limit reached") || t.contains("hit your limit") || t.contains("limit reached")
            || t.contains("out of extra usage")
    }

    /// "claude-haiku-5-5" → "Haiku 5.5"; "claude-sonnet-5-5-20261001" → "Sonnet 5.5"; anything else as it is.
    static func modelName(_ id: String) -> String {
        var parts = id.split(separator: "-").map(String.init)
        if parts.first == "claude" { parts.removeFirst() }
        if let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) { parts.removeLast() }
        guard let family = parts.first, family.first?.isLetter == true else { return id }
        let version = parts.dropFirst().filter { $0.allSatisfy(\.isNumber) }
        let name = family.prefix(1).uppercased() + family.dropFirst()
        return version.isEmpty ? name : name + " " + version.joined(separator: ".")
    }
}

// MARK: - Answers Stop gave up on

/// Stop interrupts the answer under way and the chat goes on in the same `claude`. Claude Code ends an interrupted
/// answer with a `result` of its own (an error, aborted), so every message sent gets exactly one `done`, in order. Until
/// the `done` of an abandoned answer has come, what Claude Code prints belongs to that answer, not to a later one: it
/// is dropped (a limit report is about the account and stays), and the `done` ends the wait.
struct StaleAnswers {
    private(set) var count = 0
    var waiting: Bool { count > 0 }

    enum Fate: Equatable { case pass, drop, endsOne }

    mutating func abandon() { count += 1 }
    mutating func reset() { count = 0 }

    mutating func fate(of e: QuickChatEvent) -> Fate {
        guard count > 0 else { return .pass }
        switch e {
        case .done: count -= 1; return .endsOne
        case .limit, .control, .models, .ignored: return .pass
        default: return .drop
        }
    }
}

// MARK: - The command

/// How the quick chat runs `claude` for one chat.
struct QuickChatCommand: Equatable {
    var claude: String
    /// The profile's Claude Code folder, expanded; the default ~/.claude runs without CLAUDE_CONFIG_DIR, as Terminal does.
    var configDir: String
    var isDefaultDir: Bool
    /// Quick chat's own folder for this profile: Claude Code runs here, so its sessions are listed apart.
    var workFolder: String
    /// What `--model` takes: the newest of the chosen family from Claude Code's list ("claude-fable-5-2"), or its alias
    /// ("haiku") before any list is known; "" leaves it to Claude Code.
    var model: String
    /// nil: thinking off; otherwise Claude Code's effort ("low", "medium", "high", "xhigh", "max").
    var effort: String? = nil

    static let systemPrompt = """
        You are Claude, answering in a small floating chat window on the user's Mac. Answer directly and briefly unless \
        asked for more. Use Markdown; put code in fenced blocks with the language named. You have no tools here.
        """

    /// Incognito: `--no-session-persistence` keeps Claude Code from writing the chat's transcript, so the conversation
    /// lives only in this running process; there is nothing to `--resume`.
    var arguments: [String] {
        var a = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                 "--include-partial-messages", "--no-session-persistence", "--tools", "", "--strict-mcp-config",
                 "--setting-sources", "", "--disable-slash-commands", "--system-prompt", Self.systemPrompt]
        if !model.isEmpty { a += ["--model", model] }
        if let effort { a += ["--effort", effort, "--settings", #"{"alwaysThinkingEnabled":true}"#] }
        else { a += ["--settings", #"{"alwaysThinkingEnabled":false}"#] }
        return a
    }

    /// What `claude` takes from the Mac's environment: who and where the user is, the language, and the network's
    /// proxies and certificates. Nothing else: no key or token, no other provider (Bedrock, Vertex, Foundry and their
    /// credentials), no model override, no custom headers and no telemetry export, so it answers on the folder's own
    /// sign-in and sends nothing but the chat.
    static let passed: Set<String> = ["HOME", "USER", "LOGNAME", "SHELL", "TMPDIR", "LANG", "TERM", "__CF_USER_TEXT_ENCODING",
                                      "HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy", "NO_PROXY", "no_proxy",
                                      "ALL_PROXY", "all_proxy", "SSL_CERT_FILE", "SSL_CERT_DIR", "NODE_EXTRA_CA_CERTS"]

    /// The environment `claude` gets: the allowed part of the Mac's (`passed`), the profile's folder, `claude`'s own
    /// folder first on the PATH (an npm install needs its `node`), and Claude Code's non-essential traffic (telemetry,
    /// error reports, update checks) off.
    func environment(_ base: [String: String]) -> [String: String] {
        var env = base.filter { Self.passed.contains($0.key) || $0.key.hasPrefix("LC_") }
        if !isDefaultDir { env["CLAUDE_CONFIG_DIR"] = configDir }
        let own = (claude as NSString).deletingLastPathComponent
        env["PATH"] = [own, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", base["PATH"] ?? ""]
            .filter { !$0.isEmpty }.joined(separator: ":")
        env["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"
        env["DISABLE_TELEMETRY"] = "1"
        env["DISABLE_ERROR_REPORTING"] = "1"
        // Incognito, to the file: Claude Code's built-in AGENTS.md plugin otherwise notes the session's id in
        // plugins/store/ (a once-per-session marker); this has it send per process and note nothing (checked against
        // 2.1.318). And no auto-memory folder in the profile's projects/ (an empty one appears without a system prompt).
        env["CLAUDE_CODE_AGENTS_MD_ROWS_EVERY_PROCESS"] = "1"
        env["CLAUDE_CODE_DISABLE_AUTO_MEMORY"] = "1"
        return env
    }

    /// The folder name Claude Code kept this work folder's sessions under, in the profile's folder, before quick chats
    /// were incognito: every UTF-16 unit that isn't an ASCII letter or digit becomes "-", as Claude Code counts them
    /// (~/.claude/projects/<this>/). Only for finding and removing those old chats.
    static func projectKey(_ folder: String) -> String {
        String(folder.utf16.map { u -> Character in
            guard u < 128, let s = Unicode.Scalar(u), s.properties.isAlphabetic || ("0"..."9").contains(s) else { return "-" }
            return Character(s)
        })
    }
}

// MARK: - The process

/// One `claude` for one chat: started once, sent each message, read line by line. Its events and its end come on the
/// main thread. A `claude` that dies never takes the agent with it: writes to a closed pipe fail quietly (SIGPIPE is
/// ignored) and its end is reported with the last of what it wrote to stderr.
final class QuickChatProcess {
    let command: QuickChatCommand
    var onEvent: (QuickChatEvent) -> Void = { _ in }
    /// Its exit status and the end of its stderr.
    var onExit: (Int32, String) -> Void = { _, _ in }

    private let process = Process()
    private let input = Pipe(), output = Pipe(), errors = Pipe()
    private let lock = NSLock()
    private var errTail = Data()
    private var stopping = false

    init(_ command: QuickChatCommand) { self.command = command }

    var isRunning: Bool { process.isRunning }
    var pid: Int32 { process.processIdentifier }

    func start(environment base: [String: String] = ProcessInfo.processInfo.environment) throws {
        signal(SIGPIPE, SIG_IGN)
        try FileManager.default.createDirectory(atPath: command.workFolder, withIntermediateDirectories: true)
        process.executableURL = URL(fileURLWithPath: command.claude)
        process.arguments = command.arguments
        process.environment = command.environment(base)
        process.currentDirectoryURL = URL(fileURLWithPath: command.workFolder)
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let out = output.fileHandleForReading, err = errors.fileHandleForReading
        // stdout: whole lines, parsed off the main thread, delivered on it; at its end, the process's exit. Read with
        // read(2), which reports a failed read as an error rather than raising
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var buffer = Data()
            while let chunk = Self.read(out) {
                buffer.append(chunk)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let line = buffer[buffer.startIndex..<nl]
                    buffer.removeSubrange(buffer.startIndex...nl)
                    let e = QuickChatParse.event(Data(line))
                    if e != .ignored { DispatchQueue.main.async { self?.onEvent(e) } }
                }
            }
            if !buffer.isEmpty {
                let e = QuickChatParse.event(buffer)
                if e != .ignored { DispatchQueue.main.async { self?.onEvent(e) } }
            }
            guard let self else { return }
            self.process.waitUntilExit()
            usleep(50_000)      // the last of stderr
            let status = self.process.terminationStatus
            let tail = self.stderrTail()
            DispatchQueue.main.async { self.onExit(status, tail) }
        }
        // stderr: only its last 4 KB is kept, for "what happened"
        DispatchQueue.global(qos: .utility).async { [weak self] in
            while let chunk = Self.read(err) {
                guard let self else { return }
                self.lock.lock()
                self.errTail.append(chunk)
                if self.errTail.count > 4096 { self.errTail = self.errTail.suffix(4096) }
                self.lock.unlock()
            }
        }
    }

    /// What's there to read, as soon as some is; nil at the end or on an error.
    private static func read(_ h: FileHandle) -> Data? {
        var buf = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = Darwin.read(h.fileDescriptor, &buf, buf.count)
            if n > 0 { return Data(buf[0..<n]) }
            if n < 0, errno == EINTR { continue }
            return nil
        }
    }

    /// Sends one message. False when the process is gone (the pipe is closed).
    @discardableResult
    func send(_ text: String) -> Bool {
        lock.lock(); let closed = stopping; lock.unlock()
        guard !closed, process.isRunning else { return false }
        do { try input.fileHandleForWriting.write(contentsOf: QuickChatParse.userLine(text)); return true }
        catch { return false }
    }

    private var requests = 0

    /// Sends a control request; its id (Claude Code's answer, a `.control` event, carries it), or nil when the pipe is closed.
    private func control(_ subtype: String, _ fields: [String: Any] = [:]) -> String? {
        lock.lock(); let closed = stopping; requests += 1; let id = "qc-\(requests)"; lock.unlock()
        guard !closed, process.isRunning else { return nil }
        do { try input.fileHandleForWriting.write(contentsOf: QuickChatParse.controlLine(id: id, subtype: subtype, fields)); return id }
        catch { return nil }
    }

    /// Stops the answer under way; the conversation stays in the process. Claude Code then ends that turn with a result
    /// of its own (an error, "aborted"), so every message sent gets exactly one `done`. False when it can't be asked.
    @discardableResult
    func interrupt() -> Bool { control("interrupt") != nil }

    /// Asks for the account's models (a `.models` event answers). Nothing goes to a model. False when it can't be asked.
    @discardableResult
    func initialize() -> Bool { control("initialize") != nil }

    /// The model for the next answers; "" is the profile's default. The request's id, or nil when it can't be asked.
    @discardableResult
    func setModel(_ model: String) -> String? { control("set_model", model.isEmpty ? [:] : ["model": model]) }

    /// Thinking for the next answers: off (nil), or on at that effort (checked against Claude Code 2.1.318: the effort
    /// in effect follows this, also for a `claude` started with `--effort`). False when it can't be asked.
    @discardableResult
    func setThinking(_ effort: String?) -> Bool {
        control("apply_flag_settings", ["settings": QuickChatParse.thinkingSettings(effort)]) != nil
    }

    /// Ends it: closes its input, then asks it to stop, then stops it.
    func stop() {
        lock.lock(); let already = stopping; stopping = true; lock.unlock()
        guard !already, process.isRunning else { return }
        try? input.fileHandleForWriting.close()
        process.terminate()
        // the fallback holds the process itself: the chat lets go of this object right after Stop
        let p = process
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
            if p.isRunning { kill(p.processIdentifier, SIGKILL) }
        }
    }

    /// The end of what it wrote to stderr: its last few non-empty lines, at most 400 characters.
    func stderrTail() -> String {
        lock.lock(); let d = errTail; lock.unlock()
        let text = String(decoding: d, as: UTF8.self)
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return String(lines.suffix(3).joined(separator: " · ").suffix(400))
    }
}
