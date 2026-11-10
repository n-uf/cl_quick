// Real questions through the quick chat's engine and the installed `claude` (Checks/real.sh). Its own main.swift:
// top-level code is only allowed there.
// QC_CLAUDE: the claude to run; QC_CONFIG: the folder (a throwaway one by default: Claude Code then says it isn't
// signed in, which is what this checks without an account); QC_MODEL, QC_EFFORT; QC_WORK: the work folder.
// QC_MULTI=1 (real.sh sets it for a real folder): one kept-alive `claude`, several turns, as the incognito chat runs it:
// it remembers earlier turns, Stop (interrupt) keeps the conversation, the model changes in the running process.

import Foundation

let env = ProcessInfo.processInfo.environment
guard let claude = env["QC_CLAUDE"], let config = env["QC_CONFIG"], let work = env["QC_WORK"] else {
    print("needs QC_CLAUDE, QC_CONFIG and QC_WORK"); exit(64)
}
let isDefault = config == NSHomeDirectory() + "/.claude"
let cmd = QuickChatCommand(claude: claude, configDir: config, isDefaultDir: isDefault, workFolder: work,
                           model: env["QC_MODEL"] ?? "haiku", effort: env["QC_EFFORT"].flatMap { $0.isEmpty ? nil : $0 })
let p = QuickChatProcess(cmd)
var events: [QuickChatEvent] = []
var exitInfo: (Int32, String)?
p.onEvent = { events.append($0) }
p.onExit = { exitInfo = ($0, $1) }
func doneCount() -> Int { events.filter { if case .done = $0 { return true }; return false }.count }
func texts(from start: Int) -> String {
    events[start...].compactMap { if case .text(let t) = $0 { return t }; return nil }.joined()
}
func spin(_ seconds: Double, until cond: () -> Bool) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end, exitInfo == nil, !cond() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
}
var failures = 0
func check(_ name: String, _ ok: Bool, _ got: @autoclosure () -> String = "") {
    print("\(ok ? "PASS" : "FAIL") \(name)\(ok ? "" : "  got: \(got())")")
    if !ok { failures += 1 }
}

let t0 = Date()
do { try p.start() } catch { print("couldn't start: \(error)"); exit(1) }

if env["QC_MULTI"] != "1" {
    p.send(env["QC_QUESTION"] ?? "Reply with the single word: pong")
    spin(90) { doneCount() >= 1 }
} else {
    // 1–2: a later turn remembers an earlier one, in the same process
    let pid = p.pid
    p.send("Remember this secret word: kumquat. Reply with just: ok")
    spin(90) { doneCount() >= 1 }
    var mark = events.count
    p.send("What was the secret word? Reply with just the word.")
    spin(90) { doneCount() >= 2 }
    check("a second turn remembers the first", texts(from: mark).lowercased().contains("kumquat"), texts(from: mark))
    // 3–4: Stop = interrupt, once the answer has begun; the process lives and its next answer still remembers
    mark = events.count
    p.send("Write a 2000-word story about a lighthouse keeper.")
    spin(60) { texts(from: mark).count > 30 }
    check("an interrupt is accepted", p.interrupt())
    spin(30) { doneCount() >= 3 }
    let aborted = events[mark...].contains { if case .done(true, _, _, _) = $0 { return true }; return false }
    check("the interrupted answer ends with an error result", aborted)
    check("the interrupted answer was cut short", texts(from: mark).count < 6000, "\(texts(from: mark).count) characters")
    check("the process lives on after the interrupt", p.isRunning && p.pid == pid)
    mark = events.count
    p.send("What was the secret word? Reply with just the word.")
    spin(90) { doneCount() >= 4 }
    check("after the interrupt it still remembers", texts(from: mark).lowercased().contains("kumquat"), texts(from: mark))
    // 5: the model changes in the running process, the conversation stays
    mark = events.count
    check("set_model accepted", p.setModel("sonnet"))
    p.send("What was the secret word? Reply with just the word.")
    spin(90) { doneCount() >= 5 }
    let models = events[mark...].compactMap { e -> String? in if case .started(_, let m) = e { return m }; return nil }
    check("the next answer comes from the new model", models.contains { $0.contains("sonnet") }, models.joined(separator: ","))
    check("and still remembers", texts(from: mark).lowercased().contains("kumquat"), texts(from: mark))
    check("one process for all of it", p.isRunning && p.pid == pid)
    print("rss of the idle claude: \(rssKB(p.pid)) KB")
}

func rssKB(_ pid: Int32) -> String {
    let t = Process(); t.executableURL = URL(fileURLWithPath: "/bin/ps"); t.arguments = ["-o", "rss=", "-p", "\(pid)"]
    let out = Pipe(); t.standardOutput = out
    try? t.run(); t.waitUntilExit()
    return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

let secs = String(format: "%.1f", Date().timeIntervalSince(t0))
p.stop()
let stopEnd = Date().addingTimeInterval(5)
while exitInfo == nil, Date() < stopEnd { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
for e in events {
    switch e {
    case .started(_, let m): print("started: model \(m) (\(QuickChatParse.modelName(m)))")
    case .text(let t): if env["QC_MULTI"] != "1" { print("text: \(t.debugDescription)") }
    case .thinking(let t): print("thinking: \(t.count) characters")
    case .message(let t, let m, let err): print("message: \(t.prefix(80).debugDescription) model \(m) error \(err ?? "none")")
    case .limit(let type, let used, let status, _): print("limit: \(type ?? "?") used \(used.map { String($0) } ?? "?") \(status ?? "?")")
    case .done(let isError, let t, let ms, _): print("done: error \(isError), \(ms) ms, \(t.prefix(80).debugDescription)")
    case .ignored: break
    }
}
print("after \(secs) s; exit \(exitInfo.map { "\($0.0)" } ?? "none")\(exitInfo.map { $0.1.isEmpty ? "" : ", stderr: \($0.1)" } ?? "")")
exit(failures == 0 ? 0 : 1)
