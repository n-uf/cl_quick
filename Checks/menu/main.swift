// The menu bar menu's checks (Checks/menu.sh): see that script. Nothing here shows a window or reads the user's profiles'
// numbers: levels live in memory (Files.readOnly), the folders are made under build/, and `claude` is the stand-in.

import AppKit

Files.readOnly = true
_ = NSApplication.shared

var failed = 0, passed = 0
func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    if ok { passed += 1 } else { failed += 1; print("FAIL \(name) \(detail())") }
}
func spin(_ s: TimeInterval = 0.2) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }
func spin(until done: () -> Bool, max: TimeInterval = 10) {
    let end = Date().addingTimeInterval(max)
    while !done(), Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
}

let env = ProcessInfo.processInfo.environment
let stub = env["QC_STUB_PATH"] ?? ""
let work = env["QC_WORK"] ?? NSTemporaryDirectory() + "qc-menu-work"
let now = Date()
let main = Profile(id: "main", name: "Main", folder: "~/.claude-sample-main")
let mainAddress = "ultra-1@example.com"

func level(five: Double?, fiveIn: TimeInterval = 65 * 60, week: Double?, weekIn: TimeInterval = 29 * 3600, ago: TimeInterval = 20) -> QuickChatLevel {
    var l = QuickChatLevel()
    l.fiveHour = five; l.fiveHourResets = five == nil ? nil : now.addingTimeInterval(fiveIn)
    l.week = week; l.weekResets = week == nil ? nil : now.addingTimeInterval(weekIn)
    l.at = now.addingTimeInterval(-ago)
    return l
}
func make(_ l: QuickChatLevel?, address: String? = mainAddress, problem: SignInProblem? = nil, profile: Profile = main) -> QCMenuProfile {
    QCMenuProfile.make(profile: profile, level: l, address: address, problem: problem, now: now)
}

// ── the words of a block ───────────────────────────────────────────────────────────────────────────
let rich = make(level(five: 13, week: 88))
check("lines: header, account in use (masked), the two bars' words, how old", rich.lines == [
    "Claude Main", maskEmail(mainAddress) + " · in use", "5-hour 13% in 1h 5m", "Week 88% in 1d 5h", "Updated just now"], "\(rich.lines)")
check("rows: 13% and 88% with the time to each reset", rich.rows.map(\.share) == ["13%", "88%"] && rich.rows.map(\.resets) == ["in 1h 5m", "in 1d 5h"])
check("colours: 13% green, 88% red (cl_audit's scale)", rich.rows[0].colour == Painter.green && rich.rows[1].colour == Painter.red)
check("colours: amber from 50%, red from 80%, crimson from 95%",
      Painter.color(49, stale: false) == Painter.green && Painter.color(50, stale: false) == Painter.amber
      && Painter.color(80, stale: false) == Painter.red && Painter.color(95, stale: false) == Painter.crimson)
check("colours: the profile's dot takes the fuller window's colour", rich.dotP == 88)
check("a name that starts with Claude is not given a second one", QCMenuProfile.title("Claude Work") == "Claude Work" && QCMenuProfile.title("Work") == "Claude Work")
check("the words never hold the full address", !rich.lines.joined().contains(mainAddress) && !rich.spoken.contains(mainAddress) && rich.spoken.contains(maskEmail(mainAddress)))
check("countdown: minutes, hours, days", [TimeWords.countdown(now.addingTimeInterval(19 * 60), now: now), TimeWords.countdown(now.addingTimeInterval(102 * 60), now: now),
      TimeWords.countdown(now.addingTimeInterval(67 * 3600), now: now), TimeWords.countdown(now.addingTimeInterval(16 * 86400), now: now)]
      == ["19m", "1h 42m", "2d 19h", "16 days"])

// ── relative time of the numbers' age ──────────────────────────────────────────────────────────────
check("updated: just now", make(level(five: 13, week: 88, ago: 20)).updated == "Updated just now")
check("updated: 12 min ago", make(level(five: 13, week: 88, ago: 12 * 60)).updated == "Updated 12 min ago", "\(String(describing: make(level(five: 13, week: 88, ago: 12 * 60)).updated))")
check("updated: 3 h ago", make(level(five: 13, week: 88, ago: 3 * 3600 + 60)).updated == "Updated 3 h ago")

// ── no numbers, a window not known, a full limit, signed out ───────────────────────────────────────
let none = make(nil)
check("no numbers: the account line and one muted line, no bars, no age", none.lines == ["Claude Main", maskEmail(mainAddress) + " · in use", "No usage yet"] && none.rows.isEmpty && none.noUsage,
      "\(none.lines)")
check("only an old week (reset since): no numbers either", make(level(five: nil, week: 70, weekIn: -60)).noUsage)
let weekOnly = make(level(five: nil, week: 21))
check("a window not known yet: its bar empty, its share a dash; the other as it is", weekOnly.rows.map(\.share) == ["–", "21%"] && weekOnly.rows[0].p == nil && !weekOnly.noUsage,
      "\(weekOnly.rows)")
let full = make(level(five: 100, week: 64))
check("a full 5-hour limit: 100% in crimson, the header says so, the bar's reset is when it is back",
      full.rows[0].share == "100%" && full.rows[0].colour == Painter.crimson && full.fullNote == "5-hour full · in 1h 5m" && full.rows[0].resets.hasPrefix("back"),
      "\(full.rows[0]) \(String(describing: full.fullNote))")
check("signed out: one line, no bars, no usage", make(level(five: 13, week: 88), address: nil).lines == ["Claude Main", "Signed out."])
check("a sign-in that stopped: its words, no bars, no usage", make(level(five: 13, week: 88), problem: .stopped).lines == ["Claude Main", "The sign-in stopped working."])

// ── the view: the address is blurred until the pointer is on it ─────────────────────────────────────
var picked: [String] = []
let block = QCMenuUsageBlock(rich) { picked.append("main") }
check("the block is as wide as it needs (min 300) and as tall as its lines", block.frame.width >= 300 && block.frame.height == QCMenuUsageBlock.height(rich))
check("the address is blurred at rest", !block.revealed)
block.hover(at: NSPoint(x: block.addressRect.midX, y: block.addressRect.midY))
check("the address reads while the pointer is on it", block.revealed)
block.hover(at: NSPoint(x: block.addressRect.midX, y: 4))
check("the pointer leaving the address blurs it again", !block.revealed)
block.hover(at: NSPoint(x: block.addressRect.midX, y: block.addressRect.midY)); block.hover(at: nil)
check("the pointer leaving the block blurs it", !block.revealed)
check("the VoiceOver label has the masked address only", (block.accessibilityLabel() ?? "").contains(maskEmail(mainAddress)) && !(block.accessibilityLabel() ?? "").contains(mainAddress))
block.press(); spin(0.1)
check("a click opens the chat on the profile", picked == ["main"])
let longName = make(level(five: 13, week: 88), profile: Profile(id: "x", name: String(repeating: "Wide name ", count: 5), folder: "~/.claude-x"))
check("a long name widens the block (nothing is cut)", QCMenuUsageBlock.width(longName) > QCMenuUsageBlock.width(rich))
check("with no numbers the block is shorter", QCMenuUsageBlock.height(none) < QCMenuUsageBlock.height(rich))
// live numbers: the same height takes them in place, another height waits for the next open
block.reload(make(level(five: 44, week: 12)))
check("new numbers (same height) are taken in place", block.model.rows.map(\.share) == ["44%", "12%"])
block.reload(none)
check("a block that would change height keeps its own until the menu opens again", block.model.rows.map(\.share) == ["44%", "12%"])

// ── the menu's items ────────────────────────────────────────────────────────────────────────────────
let work2 = Profile(id: "work", name: "Work", folder: "~/.claude-sample-work")
let infos: [QCStatusMenu.Info] = [
    .init(profile: main, level: level(five: 13, week: 88), address: mainAddress, problem: nil, standby: [KnownAccount(uuid: "u9", email: "zed@example.com")]),
    .init(profile: work2, level: nil, address: "ultra-2@example.com", problem: nil, standby: []),
]
var chosen: [String] = []
let items = QCStatusMenu.items(infos, now: now) { chosen.append($0) }
let blocks = items.compactMap { $0.view as? QCMenuUsageBlock }
check("the menu: a block per profile and a line between them", blocks.count == 2 && items.count == 3 && items[1].isSeparatorItem)
check("the menu: the first has its bars, the second 'No usage yet'", blocks.first?.model.lines.contains("Week 88% in 1d 5h") == true && blocks.last?.model.lines.contains("No usage yet") == true)
let menuText = blocks.flatMap { $0.model.lines }.joined(separator: "\n")
check("the menu: no standby account's address in it, even masked", !menuText.contains(maskEmail("zed@example.com")) && !menuText.contains("zed"))
check("the menu: no address in full in it (masked only)", !menuText.contains("ultra-"))
check("the menu: the blocks are all as wide as the widest", Set(blocks.map(\.frame.width)).count == 1)
blocks.last?.press(); spin(0.1)
check("the menu: a click picks that profile", chosen == ["work"])

// ── from the store: a standby account's week never shows, the account in use's does ────────────────
let home = work + "/../menu-home"
func folder(_ name: String, email: String, uuid: String) -> String {
    let dir = home + "/.claude-" + name
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let json = #"{"oauthAccount":{"emailAddress":"\#(email)","accountUuid":"\#(uuid)"}}"#
    try? json.write(toFile: dir + "/.claude.json", atomically: true, encoding: .utf8)
    return dir
}
let pa = Profile(id: "alpha", name: "Alpha", folder: folder("alpha", email: "alpha-1@example.com", uuid: "ua1"),
                 accounts: [KnownAccount(uuid: "ua1", email: "alpha-1@example.com"), KnownAccount(uuid: "ua2", email: "alpha-2@example.com", lastSeen: now.addingTimeInterval(-3600))])
let pb = Profile(id: "beta", name: "Beta", folder: folder("beta", email: "beta-1@example.com", uuid: "ub1"), accounts: [KnownAccount(uuid: "ub1", email: "beta-1@example.com")])
let store = ProfileStore.shared
store.save([pa, pb])
store.noteAccounts()
store.record("alpha", account: "ua2", level(five: 97, week: 97, ago: 30))         // the standby account's numbers: never shown
let fromStore = QCStatusMenu.infos(store)
let alpha = fromStore.first { $0.profile.id == "alpha" }!
check("the store: the account in use's address; the standby account is listed apart, with its own week left out", alpha.address == "alpha-1@example.com" && alpha.standby.map(\.uuid) == ["ua2"] && alpha.level == nil)
let alphaBlock = QCMenuProfile.make(profile: alpha.profile, level: alpha.level, address: alpha.address, problem: alpha.problem)
check("a standby account's 97% is not on the in-use account's block", alphaBlock.noUsage && !alphaBlock.lines.joined().contains("97"), "\(alphaBlock.lines)")

// ── the background refresh ─────────────────────────────────────────────────────────────────────────
let conf = work + "/stub.conf", argsFile = work + "/args.txt"
try? FileManager.default.createDirectory(atPath: work, withIntermediateDirectories: true)
try? FileManager.default.removeItem(atPath: argsFile + ".ctl")
try? "mode=ok\nargs=\(argsFile)\n".write(toFile: conf, atomically: true, encoding: .utf8)
let refresher = QCMenuUsageRefresher()
var started: [String] = [], ended: [String] = [], running = 0, mostAtOnce = 0, lookedFor = 0
refresher.findClaude = { done in lookedFor += 1; done(stub) }
refresher.command = { p, claude in
    QuickChatCommand(claude: claude, configDir: p.path, isDefaultDir: false, workFolder: work + "/" + p.id, model: "", effort: nil)
}
refresher.onStart = { started.append($0); running += 1; mostAtOnce = max(mostAtOnce, running) }
refresher.onEnd = { ended.append($0); running -= 1 }

check("refresh: a profile with no numbers needs them", refresher.needs(pa, store: store) && refresher.needs(pb, store: store))
check("refresh: a profile with no account signed in is left alone", !refresher.needs(Profile(id: "gone", name: "Gone", folder: home + "/.claude-nowhere"), store: store))
refresher.refresh(store: store)
refresher.refresh(store: store)         // the menu opened again at once: nothing more is started
spin(until: { ended.count >= 2 })
check("refresh: each profile asked once, one at a time", started == ["alpha", "beta"] && ended == ["alpha", "beta"] && mostAtOnce == 1, "\(started) \(ended) \(mostAtOnce)")
check("refresh: claude was looked for once", lookedFor == 1, "\(lookedFor)")
let got = store.level(of: pa)
check("refresh: the account in use's numbers are kept (5-hour 44%, week 12%)", got?.fiveHour == 44 && got?.week == 12 && got?.at != nil, "\(String(describing: got))")
check("refresh: the standby account's numbers were not touched", store.levels[ProfileStore.levelKey("alpha", "ua2")]?.week == 97)
let ctl = (try? String(contentsOfFile: argsFile + ".ctl", encoding: .utf8)) ?? ""
check("refresh: Claude Code was asked for the usage, and no message went to a model", ctl.contains("CTRL get_usage") && !ctl.contains("USER "), ctl)
check("refresh: the numbers are fresh, so the profile needs nothing more", !refresher.needs(pa, store: store))
check("refresh: and it's tried at most every few minutes", !refresher.needs(pa, store: store, now: Date().addingTimeInterval(2 * 60)))
// old numbers are asked for again, once the retry time has passed
var old = got!; old.at = Date().addingTimeInterval(-10 * 60)
store.record("alpha", account: "ua1", old)
check("refresh: numbers 10 minutes old need asking again, after the retry time", refresher.needs(pa, store: store, now: Date().addingTimeInterval(QCMenuUsageRefresher.retryAfter + 1)))
check("refresh: but not before it", !refresher.needs(pa, store: store, now: Date().addingTimeInterval(60)))
// a `claude` that can't be found starts nothing and leaves nothing waiting
let lost = QCMenuUsageRefresher()
lost.findClaude = { $0(nil) }
var lostStarted = 0
lost.onStart = { _ in lostStarted += 1 }
lost.refresh(store: store)
spin(0.3)
check("refresh: no claude found, nothing started", lostStarted == 0)

print(failed == 0 ? "menu checks: \(passed) passed" : "menu checks: \(failed) FAILED, \(passed) passed")
exit(failed == 0 ? 0 : 1)
