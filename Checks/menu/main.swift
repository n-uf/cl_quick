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
check("updated: 3 min ago, still fresh, in colour", make(level(five: 13, week: 88, ago: 3 * 60)).updated == "Updated 3 min ago"
      && make(level(five: 13, week: 88, ago: 3 * 60)).rows[1].colour == Painter.red)
// numbers over a few minutes old are what Claude Code said last, not the account now
let lastKnown = make(level(five: 13, week: 88, ago: 12 * 60))
check("stale: 12 min old numbers are 'Last known', grey, with no dot colour",
      lastKnown.updated == "Last known 12 min ago" && lastKnown.rows.allSatisfy { $0.colour == Painter.grey } && lastKnown.dotP == nil,
      "\(lastKnown.lines)")
let staleFull = make(level(five: nil, week: 100, ago: 12 * 60))
check("stale: a full week 12 min old stays visible, grey: 'Week full · last known', both rows grey, no dot, 'Last known 12 min ago' under the bars",
      staleFull.fullNote == "Week full · last known" && staleFull.fullNoteStale && staleFull.dotP == nil && staleFull.updated == "Last known 12 min ago"
      && staleFull.rows.map(\.share) == ["–", "100%"] && staleFull.rows.allSatisfy { $0.colour == Painter.grey } && staleFull.rows[1].resets.hasPrefix("back"), "\(staleFull.lines)")
// a saved full limit whose reset is still ahead stays, grey, however old
let savedWeek = make(level(five: 40, week: 100, ago: 2 * 3600))
check("saved full: a 2 h old full week with its reset ahead: grey 'Week full · last known', no dot colour, 'Last known 2 h ago' under the bars",
      savedWeek.fullNote == "Week full · last known" && savedWeek.fullNoteStale && savedWeek.dotP == nil && !savedWeek.noUsage && savedWeek.updated == "Last known 2 h ago",
      "\(savedWeek.lines)")
check("saved full: the full window's row grey at 100% with when it is back; the other one's 40% (over an hour old) is not shown: '–'",
      savedWeek.rows.map(\.id) == ["5h", "wk"] && savedWeek.rows.map(\.share) == ["–", "100%"] && savedWeek.rows[0].p == nil && savedWeek.rows[1].colour == Painter.grey
      && savedWeek.rows[1].resets == TimeWords.back(now.addingTimeInterval(29 * 3600), now: now) && savedWeek.rows[0].resets == "",
      "\(savedWeek.lines)")
check("saved full: the words never read as now ('last known', no 'Updated')", !savedWeek.lines.joined().contains("Updated") && savedWeek.spoken.contains("last known"))
let savedFive = make(level(five: 100, week: 20, ago: 3 * 3600))
check("saved full: a 3 h old full 5-hour window the same way: '5-hour full · last known', its row 100% back …, the week '–'",
      savedFive.fullNote == "5-hour full · last known" && savedFive.fullNoteStale && savedFive.rows.map(\.share) == ["100%", "–"] && savedFive.rows[0].resets.hasPrefix("back")
      && savedFive.updated == "Last known 3 h ago" && savedFive.dotP == nil, "\(savedFive.lines)")
let savedDay = make(level(five: nil, week: 100, ago: 28 * 3600))
check("saved full: a day-old full week with its reset still ahead: 'Week full · last known', 'Last known yesterday'",
      savedDay.fullNote == "Week full · last known" && savedDay.updated == "Last known yesterday" && savedDay.rows.map(\.share) == ["–", "100%"] && savedDay.dotP == nil, "\(savedDay.lines)")
check("saved full: the block is as tall as a fresh one (so a fresh answer can replace it live)", QCMenuUsageBlock.height(savedDay) == QCMenuUsageBlock.height(rich)
      && savedDay.shape == rich.shape && savedWeek.shape == rich.shape && staleFull.shape == rich.shape)
var savedRefusal = QuickChatLevel()
savedRefusal.refusedUntil = now.addingTimeInterval(2 * 3600); savedRefusal.refusedAt = now.addingTimeInterval(-3 * 3600); savedRefusal.at = now.addingTimeInterval(-3 * 3600)
let refusalBlock = make(savedRefusal)
check("saved full: a refusal that names no window, 3 h old: 'Limit full · back at … · last known' (its end in the note), no bars, 'Last known 3 h ago'",
      refusalBlock.fullNote == "Limit full · " + TimeWords.back(now.addingTimeInterval(2 * 3600), now: now) + " · last known" && refusalBlock.rows.isEmpty
      && refusalBlock.noUsageText == "Last known 3 h ago" && refusalBlock.dotP == nil, "\(refusalBlock.lines)")
var recentRefusal = level(five: 30, week: 40, ago: 12 * 60)
recentRefusal.refusedUntil = now.addingTimeInterval(2 * 3600); recentRefusal.refusedAt = now.addingTimeInterval(-12 * 60)
let recentRefusalBlock = make(recentRefusal)
check("saved full: the same refusal 12 min old (rows shown): its end is in the note too, on both sides of the hour",
      recentRefusalBlock.fullNote == refusalBlock.fullNote && recentRefusalBlock.rows.map(\.share) == ["30%", "40%"] && recentRefusalBlock.updated == "Last known 12 min ago",
      "\(recentRefusalBlock.lines)")
var savedNoReset = level(five: nil, week: 100, ago: 2 * 3600); savedNoReset.weekResets = nil
check("saved full: a 100% with no reset date is not kept (nothing says it still stands)", make(savedNoReset).noUsage && make(savedNoReset).fullNote == nil)
var dateless = level(five: 100, week: 100, ago: 2 * 3600); dateless.weekResets = nil
let datelessBlock = make(dateless)
check("saved full: a week 100% with no date doesn't hide a 5-hour 100% that has one: '5-hour full · last known', its row 100% back …",
      datelessBlock.fullNote == "5-hour full · last known" && datelessBlock.rows.map(\.share) == ["100%", "–"] && datelessBlock.rows[0].resets.hasPrefix("back"), "\(datelessBlock.lines)")
var datelessRefused = level(five: nil, week: 100, ago: 2 * 3600); datelessRefused.weekResets = nil
datelessRefused.refusedUntil = now.addingTimeInterval(3600); datelessRefused.refusedAt = now.addingTimeInterval(-2 * 3600)
check("saved full: nor does it hide a refusal that is still ahead", make(datelessRefused).fullNote?.hasSuffix("last known") == true && make(datelessRefused).fullNote?.contains("full") == true,
      "\(make(datelessRefused).lines)")
let afterReset = make(level(five: nil, week: 100, weekIn: -60, ago: 2 * 3600))
check("saved full: once its reset is past, normal rules: 'No recent numbers', no note",
      afterReset.lines == ["Claude Main", maskEmail(mainAddress) + " · in use", "No recent numbers"] && afterReset.fullNote == nil && !afterReset.fullNoteStale
      && afterReset.rows.isEmpty && afterReset.dotP == nil, "\(afterReset.lines)")
let afterResetFive = make(level(five: 100, fiveIn: -60, week: 30, weekIn: -60, ago: 90 * 60))
check("saved full: both windows reset since, over an hour old: 'No recent numbers'", afterResetFive.noUsage && afterResetFive.noUsageText == "No recent numbers" && afterResetFive.fullNote == nil)
check("saved full: a not-full old number is still hidden: 'No recent numbers'", make(level(five: 40, week: 88, ago: 2 * 3600)).noUsageText == "No recent numbers")
let dayOld = make(level(five: nil, week: 100, weekIn: -3600, ago: 28 * 3600))
check("stale: a day-old week whose reset is past isn't shown at all: 'No recent numbers', no bars, no note, no age",
      dayOld.lines == ["Claude Main", maskEmail(mainAddress) + " · in use", "No recent numbers"] && dayOld.rows.isEmpty && dayOld.fullNote == nil
      && dayOld.dotP == nil && dayOld.updated == nil, "\(dayOld.lines)")
check("stale: 'No recent numbers' sizes the block like 'No usage yet'", QCMenuUsageBlock.height(dayOld) == QCMenuUsageBlock.height(make(nil)))
check("fresh full: a full week 2 min old is still the crimson note ('Week full · in 1d 5h'), the 5-hour row as it is, the dot crimson",
      make(level(five: 40, week: 100, ago: 2 * 60)).fullNote == "Week full · in 1d 5h" && !make(level(five: 40, week: 100, ago: 2 * 60)).fullNoteStale
      && make(level(five: 40, week: 100, ago: 2 * 60)).dotP == 100 && make(level(five: 40, week: 100, ago: 2 * 60)).rows.map(\.share) == ["40%", "100%"])
check("fresh full: a fresh answer replaces the saved one at once (12%, no note)",
      { let b = make(level(five: 5, week: 12, ago: 10)); return b.fullNote == nil && !b.fullNoteStale && b.rows.map(\.share) == ["5%", "12%"] && b.updated == "Updated just now" }())

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
      full.rows[0].share == "100%" && full.rows[0].colour == Painter.crimson && full.fullNote == "5-hour full · in 1h 5m" && !full.fullNoteStale && full.rows[0].resets.hasPrefix("back"),
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
// a saved full limit on the open menu is replaced live by a fresh answer (the refresh finishing), 12 min old or a day old
for (name, saved) in [("12 min old", staleFull), ("2 h old", savedWeek), ("a day old", savedDay)] {
    let open = QCMenuUsageBlock(saved) {}
    open.reload(make(level(five: 5, week: 12)))
    check("live: a saved full week (\(name)) is replaced by a fresh answer in the open menu",
          open.model.fullNote == nil && !open.model.fullNoteStale && open.model.rows.map(\.share) == ["5%", "12%"] && open.model.updated == "Updated just now",
          "\(open.model.lines)")
}
let narrow = QCMenuUsageBlock(make(level(five: 13, week: 88))) {}
let wideNote = QCMenuProfile(id: "main", title: "Claude Main", dotP: nil, fullNote: String(repeating: "Week full · ", count: 8), account: .inUse(address: mainAddress),
                             rows: rich.rows, noUsage: false, updated: rich.updated)
narrow.reload(wideNote)
check("live: a header note wider than the block was given is not taken in place (it would be cut)", narrow.model.fullNote == nil)

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

// ── Switch account ›, for a profile with standby accounts, through the switch path that exists ─────────
var switched: [String] = []
let withSwitch = QCStatusMenu.items(infos, now: now, switchTo: { p, a in switched.append("\(p.id):\(a.uuid)") }) { _ in }
let subs = withSwitch.filter { $0.submenu != nil }
check("switch: one Switch account › item, for the profile with a standby account only, right under its block",
      withSwitch.count == 4 && subs.count == 1 && subs.first?.title == "Switch account" && withSwitch.firstIndex(of: subs[0]) == 1 && withSwitch[2].isSeparatorItem,
      "\(withSwitch.map { $0.title })")
let lines = subs.first?.submenu?.items ?? []
check("switch: its line names the standby account masked, never in full", lines.map(\.title) == ["Switch to \(maskEmail("zed@example.com"))…"] && !lines.map(\.title).joined().contains("zed"), "\(lines.map(\.title))")
if let line = lines.first, let t = line.target, let a = line.action { _ = t.perform(a, with: line) }
check("switch: picking it goes to the switch path with that profile and account", switched == ["main:u9"], "\(switched)")
let waitingItems = QCStatusMenu.items(infos, now: now, switching: { $0.id == "main" }, switchTo: { _, _ in }) { _ in }
check("switch: while a sign-in is waited for, its lines are off", waitingItems.first { $0.submenu != nil }?.submenu?.items.allSatisfy { !$0.isEnabled } == true)
check("switch: without a switch path there is no such item", items.allSatisfy { $0.submenu == nil })

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
store.record("alpha", account: "ua2", level(five: 97, week: 97, ago: 30))         // the standby account's numbers: never kept
check("the store: numbers for an account the folder isn't on are not recorded", store.levels[ProfileStore.levelKey("alpha", "ua2")] == nil)
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
check("refresh: nothing was recorded for the standby account", store.levels[ProfileStore.levelKey("alpha", "ua2")] == nil)
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

// an error answer to get_usage ends the refresh at once, not after the 25 s wait
do {
    try? "mode=ok\nusage=error\nargs=\(argsFile)\n".write(toFile: conf, atomically: true, encoding: .utf8)
    let refused = QCMenuUsageRefresher()
    refused.findClaude = refresher.findClaude
    refused.command = refresher.command
    var refusedEnded: [String] = []
    refused.onEnd = { refusedEnded.append($0) }
    let t0 = Date()
    refused.refresh(store: store)
    spin(until: { !refusedEnded.isEmpty })
    let took = Date().timeIntervalSince(t0)
    check("refresh: an error answer to get_usage ends the refresh at once", refusedEnded == ["alpha"] && took < 5, "\(refusedEnded) after \(took) s")
    try? "mode=ok\nargs=\(argsFile)\n".write(toFile: conf, atomically: true, encoding: .utf8)
}

// the give-up timer runs while a menu is open (the run loop is then in the event-tracking mode, not the default one):
// a `claude` that never answers get_usage is let go after the wait
do {
    try? "mode=ok\nusage=none\nargs=\(argsFile)\n".write(toFile: conf, atomically: true, encoding: .utf8)
    let waiting = QCMenuUsageRefresher()
    waiting.findClaude = refresher.findClaude
    waiting.command = refresher.command
    var waitEnded: [String] = []
    waiting.onEnd = { waitEnded.append($0) }
    let saved = QCMenuUsageRefresher.giveUp
    QCMenuUsageRefresher.giveUp = 1
    let t0 = Date()
    waiting.refresh(store: store)
    // only the event-tracking mode is run, as an open menu does
    while waitEnded.isEmpty, Date().timeIntervalSince(t0) < 6 { RunLoop.current.run(mode: .eventTracking, before: Date().addingTimeInterval(0.05)) }
    QCMenuUsageRefresher.giveUp = saved
    check("refresh: a claude that never answers is let go after the wait, also while a menu is open", waitEnded == ["alpha"], "\(waitEnded) after \(Date().timeIntervalSince(t0)) s")
    try? "mode=ok\nargs=\(argsFile)\n".write(toFile: conf, atomically: true, encoding: .utf8)
}

// ── the account changed outside cl_quick (sample accounts, example.com) ────────────────────────────────
// the folder went from A to B (claude auth login, /login, cl_audit), with A's full week recorded: the menu shows B, with
// no numbers until B's own come, and the refresh asks for B's and keeps them under B
do {
    let dir = folder("gamma", email: "gamma-a@example.com", uuid: "ug-a")
    let pg = Profile(id: "gamma", name: "Gamma", folder: dir,
                     accounts: [KnownAccount(uuid: "ug-a", email: "gamma-a@example.com"), KnownAccount(uuid: "ug-b", email: "gamma-b@example.com")])
    store.save([pg])
    store.record("gamma", account: "ug-a", level(five: nil, week: 100, ago: 30))
    check("switched: A's full week is recorded while A is in use", store.levels[ProfileStore.levelKey("gamma", "ug-a")]?.week == 100)
    var writes = 0.0
    func signIn(_ email: String, _ uuid: String) {
        let json = #"{"oauthAccount":{"emailAddress":"\#(email)","accountUuid":"\#(uuid)"}}"#
        try? json.write(toFile: dir + "/.claude.json", atomically: true, encoding: .utf8)
        writes += 1           // each sign-in a time of its own
        try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(writes)], ofItemAtPath: dir + "/.claude.json")
    }
    signIn("gamma-b@example.com", "ug-b")                    // no reload asked: the menu's next look sees it
    let info = QCStatusMenu.info(pg, store)
    let b = QCMenuProfile.make(profile: pg, level: info.level, address: info.address, problem: info.problem)
    check("switched: the menu shows B in use, with no numbers (A's week is A's), no full note",
          info.address == "gamma-b@example.com" && info.level == nil && b.noUsage && b.fullNote == nil && !b.lines.joined().contains("100"), "\(b.lines)")
    check("switched: A is on standby", info.standby.map(\.uuid) == ["ug-a"])
    // the refresh asks B's numbers and keeps them under B
    try? "mode=ok\nargs=\(argsFile)\n".write(toFile: conf, atomically: true, encoding: .utf8)
    let r = QCMenuUsageRefresher()
    r.findClaude = refresher.findClaude; r.command = refresher.command
    var rEnded: [String] = []
    r.onEnd = { rEnded.append($0) }
    check("switched: B with no numbers needs them", r.needs(pg, store: store))
    r.refresh(store: store)
    spin(until: { !rEnded.isEmpty })
    let got = QCStatusMenu.info(pg, store)
    check("switched: B's own numbers come and are kept under B; A's stay A's",
          got.level?.week == 12 && store.levels[ProfileStore.levelKey("gamma", "ug-b")]?.week == 12
          && store.levels[ProfileStore.levelKey("gamma", "ug-a")]?.week == 100, "\(String(describing: got.level))")

    // B's numbers 10 minutes old: the menu asks again (each ask below starts a `claude`, checked)
    var oldB = store.levels[ProfileStore.levelKey("gamma", "ug-b")]!; oldB.at = Date().addingTimeInterval(-10 * 60)
    store.record("gamma", account: "ug-b", oldB)
    func ask(_ settings: String, during: (() -> Void)? = nil) -> Bool {
        try? (settings + "args=\(argsFile)\n").write(toFile: conf, atomically: true, encoding: .utf8)
        let q = QCMenuUsageRefresher()
        q.findClaude = refresher.findClaude; q.command = refresher.command
        var began = 0, ended: [String] = []
        q.onStart = { _ in began += 1 }
        q.onEnd = { ended.append($0) }
        q.refresh(store: store)
        if let during { spin(0.8); during() }
        spin(until: { !ended.isEmpty })
        return began == 1 && ended == ["gamma"]
    }
    // a get_usage answer that arrives after the folder moved again (back to A) is B's: dropped, not put on A
    let aBefore = store.levels[ProfileStore.levelKey("gamma", "ug-a")]
    let asked = ask("mode=ok\nusagedelay=2\n") { signIn("gamma-a@example.com", "ug-a") }
    check("switched: an answer that comes after the folder moved is dropped (neither A's nor B's numbers change)",
          asked && store.levels[ProfileStore.levelKey("gamma", "ug-a")] == aBefore && store.levels[ProfileStore.levelKey("gamma", "ug-b")] == oldB)
    // a process that says it is another account than the folder's: its numbers are dropped
    signIn("gamma-b@example.com", "ug-b")
    let askedOther = ask("mode=ok\naccount=someone-else@example.com\n")
    check("switched: a process that says it is someone else has its numbers dropped", askedOther && store.levels[ProfileStore.levelKey("gamma", "ug-b")] == oldB)
    // rate_limits null (Claude Code's usage endpoint gave nothing): nothing kept, the numbers stay as old as they were
    let askedNull = ask("mode=ok\nusage=null\n")
    check("switched: rate_limits null keeps nothing and makes nothing fresh", askedNull && store.levels[ProfileStore.levelKey("gamma", "ug-b")] == oldB)
    check("switched: so the menu asks again once the retry time has passed", QCMenuUsageRefresher().needs(pg, store: store))
    try? "mode=ok\nargs=\(argsFile)\n".write(toFile: conf, atomically: true, encoding: .utf8)
}

print(failed == 0 ? "menu checks: \(passed) passed" : "menu checks: \(failed) FAILED, \(passed) passed")
exit(failed == 0 ? 0 : 1)
