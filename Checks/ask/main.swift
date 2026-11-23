// The real-claude check of cl_kit's short ask (Runs' ClaudeAsk.ask), as cl_quick's usage refresher and sign-in word run
// it: once in a fresh throwaway folder (not signed in), then once in the profile's own folder (QC_ASK_PROFILE). Each run
// asks `initialize` and `get_usage` and nothing else: no model message is ever sent. It says only pass or fail, how the
// ask ended, whether an account came (masked: "<address>", never the address itself), whether limits came (no numbers),
// and which stop step ended `claude` (its input closed and SIGTERM, sent together, or SIGKILL after the grace), seen by
// its own exit status (kqueue on the child's pid). Nothing else of its output is printed or kept. Never the Keychain.

import Darwin
import Foundation
import Runs

let env = ProcessInfo.processInfo.environment
let work = env["QC_ASK_WORK"] ?? NSTemporaryDirectory()
let profile = env["QC_ASK_PROFILE"] ?? ""
let grace: TimeInterval = 1.5
var failures = 0

func say(_ s: String) { print(s); fflush(stdout) }

/// The pids of this process's children now.
func children() -> [pid_t] {
    var pids = [pid_t](repeating: 0, count: 256)
    let n = proc_listchildpids(getpid(), &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
    return n > 0 ? Array(pids.prefix(Int(n))) : []
}

/// Watches a child's exit (its wait status and when), off the main thread.
final class ExitWatch {
    private let lock = NSLock()
    private(set) var status: Int32?
    private(set) var at: Date?
    let registered: Bool

    init(_ pid: pid_t) {
        let kq = kqueue()
        var ev = kevent(ident: UInt(pid), filter: Int16(EVFILT_PROC), flags: UInt16(EV_ADD | EV_ONESHOT),
                        fflags: UInt32(NOTE_EXIT) | UInt32(NOTE_EXITSTATUS), data: 0, udata: nil)
        registered = kq >= 0 && kevent(kq, &ev, 1, nil, 0, nil) == 0
        guard registered else { if kq >= 0 { close(kq) }; return }
        DispatchQueue.global().async { [self] in
            var out = kevent()
            var ts = timespec(tv_sec: 60, tv_nsec: 0)
            if kevent(kq, nil, 0, &out, 1, &ts) == 1 {
                lock.lock(); status = Int32(truncatingIfNeeded: out.data); at = Date(); lock.unlock()
            }
            close(kq)
        }
    }

    var ended: (status: Int32, at: Date)? { lock.lock(); defer { lock.unlock() }; return status.flatMap { s in at.map { (s, $0) } } }
}

/// The stop step that ended it, from its wait status and when it ended after the ask returned (the ask closes the input
/// and sends SIGTERM as it returns; SIGKILL follows after the grace).
func stopStep(_ status: Int32, after: TimeInterval) -> (words: String, clean: Bool) {
    let sig = status & 0x7f, code = (status >> 8) & 0xff
    let ms = Int((after * 1000).rounded())
    if sig == SIGKILL { return ("SIGKILL after the grace (\(ms) ms after the ask returned)", after >= grace - 0.1) }
    if sig == SIGTERM { return ("SIGTERM (\(ms) ms after the ask returned, before the grace)", after < grace) }
    if sig != 0 { return ("another signal \(sig) (\(ms) ms)", false) }
    if after < 0 { return ("it ended by itself before the stop, exit \(code)", true) }
    return ("input closed and SIGTERM: it exited \(code) (\(ms) ms after the ask returned, before the grace)", after < grace)
}

/// One ask on `config` (nil: the default folder) in a work folder of its own; `wantAccount`: an account must come.
func run(_ name: String, config: String?, wantAccount: Bool) {
    guard let claude = ClaudeFinder.find()?.path else { say("FAIL \(name): no claude found"); failures += 1; return }
    let folder = (work as NSString).appendingPathComponent("ask-\(name)-\(UUID().uuidString.prefix(8))")
    try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let e = ClaudeEnvironment.make(env, claude: claude, configDir: config, traceless: true)
    let before = Set(children())
    var answer: ClaudeAsk.Answer?
    var returned: Date?
    DispatchQueue.global().async {
        let a = ClaudeAsk.ask(claude: claude, environment: e, folder: folder, usage: true)
        returned = Date()
        DispatchQueue.main.async { answer = a }
    }
    // the ask's `claude`: the child that appears while it runs
    var watch: ExitWatch?
    let start = Date()
    while answer == nil, Date().timeIntervalSince(start) < 40 {
        if watch == nil, let pid = children().first(where: { !before.contains($0) }) { watch = ExitWatch(pid) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
    guard let a = answer, let back = returned else { say("FAIL \(name): the ask didn't return"); failures += 1; return }
    let until = Date().addingTimeInterval(grace + 3)
    while watch?.ended == nil, Date() < until { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
    let named = a.account?["email"] != nil
    let account = a.account == nil ? "no initialize answer" : named ? "<address>" + (a.account?["organization"] != nil ? " with an organisation" : "") : "names nobody"
    let limits = a.limits.map { l in !l.available ? "not available" : [l.fiveHour != nil ? "5-hour" : nil, l.week != nil ? "week" : nil].compactMap { $0 }.joined(separator: " and ") + " given" }
        ?? (a.usageError != nil ? "refused" : "none")
    var ok = true
    var step = "not seen"
    if let w = watch, w.registered, let x = w.ended {
        let s = stopStep(x.status, after: x.at.timeIntervalSince(back))
        step = s.words; ok = ok && s.clean
    } else if watch == nil {
        step = "no child seen"; ok = false
    } else {
        step = "still running \(Int(grace + 3)) s after the ask"; ok = false
    }
    ok = ok && (wantAccount ? named : !named) && (a.end == .answered || (!wantAccount && a.end == .exited))
    if !ok { failures += 1 }
    say("\(ok ? "PASS" : "FAIL") \(name): ended \(a.end), account: \(account), limits: \(limits); stop: \(step)")
}

// the account is taken from `initialize` with or without a model list (the parse alone, on sample lines: example.com)
do {
    let withModels = #"{"type":"control_response","response":{"subtype":"success","request_id":"ask-1","response":{"models":[{"value":"haiku"}],"account":{"email":"sample@example.com"}}}}"#
    let without = #"{"type":"control_response","response":{"subtype":"success","request_id":"ask-1","response":{"account":{"email":"sample@example.com"}}}}"#
    let neither = #"{"type":"control_response","response":{"subtype":"success","request_id":"ask-1","response":{"commands":[]}}}"#
    let ok = ClaudeAsk.event(Data(withModels.utf8)) == .account(["email": "sample@example.com"])
        && ClaudeAsk.event(Data(without.utf8)) == .account(["email": "sample@example.com"])
        && ClaudeAsk.event(Data(neither.utf8)) == .ignored
    if !ok { failures += 1 }
    say("\(ok ? "PASS" : "FAIL") parse: the account from initialize with or without a model list (sample lines)")
}

let throwaway = (work as NSString).appendingPathComponent("ask-config-\(UUID().uuidString.prefix(8))")
try? FileManager.default.createDirectory(atPath: throwaway, withIntermediateDirectories: true)
run("throwaway", config: throwaway, wantAccount: false)
try? FileManager.default.removeItem(atPath: throwaway)
if profile.isEmpty {
    say("note: no signed-in profile folder given (QC_ASK_PROFILE): its run skipped")
} else {
    let home = NSHomeDirectory()
    let isDefault = (profile as NSString).standardizingPath == (home as NSString).appendingPathComponent(".claude")
    run("profile", config: isDefault ? nil : profile, wantAccount: true)
}
say(failures == 0 ? "ask: all passed" : "ask: \(failures) failed")
exit(failures == 0 ? 0 : 1)
