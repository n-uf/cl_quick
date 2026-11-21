// The menu bar menu's checks (Checks/menu.sh): see that script. Nothing here shows a window or reads the user's profiles'
// numbers: levels live in memory (Files.readOnly), the folders are made under build/, and `claude` is the stand-in.

import AddressPrivacy
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
check("saved full: a refusal that names no window, 3 h old: 'Limit full · back at … · last known' (its end in the note), two '–' rows, 'Last known 3 h ago'",
      refusalBlock.fullNote == "Limit full · " + TimeWords.back(now.addingTimeInterval(2 * 3600), now: now) + " · last known" && refusalBlock.rows.map(\.share) == ["–", "–"]
      && !refusalBlock.noUsage && refusalBlock.updated == "Last known 3 h ago" && refusalBlock.dotP == nil && refusalBlock.shape == rich.shape, "\(refusalBlock.lines)")
var oldRefusal = level(five: 30, week: 40, ago: 3 * 3600)
oldRefusal.refusedUntil = now.addingTimeInterval(2 * 3600); oldRefusal.refusedAt = now.addingTimeInterval(-3 * 3600)
let oldRefusalBlock = make(oldRefusal)
check("saved full: the same refusal 3 h old with 5-hour 30% and week 40%: those old numbers aren't shown, two '–' rows, same note",
      oldRefusalBlock.fullNote == refusalBlock.fullNote && oldRefusalBlock.rows.map(\.share) == ["–", "–"] && oldRefusalBlock.shape == rich.shape, "\(oldRefusalBlock.lines)")
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
for (name, saved) in [("week, 12 min old", staleFull), ("week, 2 h old", savedWeek), ("week, a day old", savedDay), ("refusal naming no window, 3 h old, no numbers", refusalBlock),
                      ("refusal naming no window, 3 h old, with numbers", oldRefusalBlock), ("refusal naming no window, 12 min old", recentRefusalBlock)] {
    let open = QCMenuUsageBlock(saved) {}
    open.reload(make(level(five: 5, week: 12)))
    check("live: a saved full (\(name)) is replaced by a fresh answer in the open menu",
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
check("the menu: no standby account's address in it (the words are 'hidden address', the same for every address)", !menuText.contains("zed") && menuText.contains(AddressText.hidden))
check("the menu: no address in full in it (masked only)", !menuText.contains("ultra-"))
check("the menu: the blocks are all as wide as the widest", Set(blocks.map(\.frame.width)).count == 1)
blocks.last?.press(); spin(0.1)
check("the menu: a click picks that profile", chosen == ["work"])

// ── standby accounts: a row each, in their profile's group, through the switch path that exists ─────────
// (sample addresses only: example.com / example.org)
var switched: [String] = []
// (the sample profiles here are not in the store: the click's own rule, still-standby and not waiting, is checked
// below against stored ones; here it lets every click through)
let realAllow = QCStatusMenu.allowSwitch
QCStatusMenu.allowSwitch = { _, _ in true }
let yan = KnownAccount(uuid: "u8", email: "yan.old@example.org")
let zedAddress = "zed@example.com", zedMasked = maskEmail(zedAddress)
func standbyMenu(_ infos: [QCStatusMenu.Info], switching: @escaping (Profile) -> Bool = { _ in false }, live: ((Profile) -> QCStatusMenu.Info)? = nil) -> [NSMenuItem] {
    QCStatusMenu.items(infos, now: now, live: live, switching: switching, switchTo: { p, a in switched.append("\(p.id):\(a.uuid)") }) { _ in }
}
/// The menu's shape in one string: B a profile's block, R a standby row, A Add an account…, - a separator.
func shape(_ items: [NSMenuItem]) -> String {
    items.map { $0.isSeparatorItem ? "-" : $0.view is QCMenuUsageBlock ? "B" : $0.view is QCStandbyMenuRow ? "R" : $0.view is QCAddAccountMenuRow ? "A" : "?" }.joined()
}
let mainOne = QCStatusMenu.Info(profile: main, level: level(five: 13, week: 88), address: mainAddress, problem: nil, standby: [KnownAccount(uuid: "u9", email: zedAddress)])
let mainTwo = QCStatusMenu.Info(profile: main, level: level(five: 13, week: 88), address: mainAddress, problem: nil, standby: [KnownAccount(uuid: "u9", email: zedAddress), yan])
let workNone = QCStatusMenu.Info(profile: work2, level: nil, address: "ultra-2@example.com", problem: nil, standby: [])
let workOne = QCStatusMenu.Info(profile: work2, level: nil, address: "ultra-2@example.com", problem: nil, standby: [KnownAccount(uuid: "w1", email: "kim.studio@example.org")])
let oneProfile = standbyMenu([mainOne])
check("order: one profile with 1 standby: its block, then the standby row, and nothing else", shape(oneProfile) == "BR", shape(oneProfile))
let withRows = standbyMenu(infos)
check("order: a profile with no standby account has just its block", shape(withRows) == "BR-B", shape(withRows))
let twoProfiles = standbyMenu([mainTwo, workNone])
check("order: two profiles, 2 standby + none: the block and both rows, a line, the other block", shape(twoProfiles) == "BRR-B", shape(twoProfiles))
check("order: standby accounts are in the store's order (most recently seen first as given)",
      (twoProfiles[1].view as? QCStandbyMenuRow)?.address == zedAddress && (twoProfiles[2].view as? QCStandbyMenuRow)?.address == yan.email)
check("grouping: lines go between profiles only, never between a block and its rows or between rows",
      shape(standbyMenu([mainTwo, workOne])) == "BRR-BR" && shape(standbyMenu([workNone, mainOne, workNone])) == "B-BR-B")
check("grouping: the menu's own items have no Switch account item and no submenu",
      (withRows + twoProfiles + oneProfile).allSatisfy { $0.submenu == nil && $0.title != "Switch account" })
check("grouping: without a switch path there are no rows", shape(items) == "B-B" && items.allSatisfy { $0.submenu == nil })
check("grouping: a block still opens the quick chat on its profile, with the rows around it",
      (withRows[0].view as? QCMenuUsageBlock) != nil && withRows[0].representedObject as? String == "main" && (withRows[3].view as? QCMenuUsageBlock) != nil)
let groupBlock = withRows[0].view as! QCMenuUsageBlock, loneBlock = withRows[3].view as! QCMenuUsageBlock
check("grouping: a block with rows after it ends closer to them than one with none",
      groupBlock.frame.height == QCMenuUsageBlock.height(groupBlock.model, joined: true) && loneBlock.frame.height == QCMenuUsageBlock.height(loneBlock.model)
      && QCMenuUsageBlock.height(groupBlock.model, joined: true) < QCMenuUsageBlock.height(groupBlock.model))
check("live: a block follows the store while the menu is open (a provider) only when the menu is given a live source",
      (standbyMenu([mainOne], live: { _ in mainOne })[0].view as? QCMenuUsageBlock)?.provider != nil && (oneProfile[0].view as? QCMenuUsageBlock)?.provider == nil)
check("live: a standby row has nothing to follow: no provider, built once for the menu that opened",
      (oneProfile[1].view as? QCStandbyMenuRow) != nil && (standbyMenu([mainOne], live: { _ in mainOne })[1].view as? QCStandbyMenuRow)?.address == zedAddress)

// each row is a drawn view that holds the whole address for drawing; its words, title and VoiceOver label hold it masked
let rows = twoProfiles.compactMap { $0.view as? QCStandbyMenuRow }
check("words: the row holds the standby account's whole address for drawing", rows.map(\.address) == [zedAddress, yan.email])
let zedItem = oneProfile[1], zedRow = oneProfile[1].view as! QCStandbyMenuRow
check("words: its title and VoiceOver label are the address masked, 'standby' and 'switch', never in full",
      zedItem.title == zedMasked + " · standby" && zedRow.accessibilityLabel() == zedMasked + ", standby, switch"
      && !zedItem.title.contains("zed") && !(zedRow.accessibilityLabel() ?? "").contains("zed"), "\(zedItem.title) / \(String(describing: zedRow.accessibilityLabel()))")
check("words: the row is a menu item for VoiceOver, enabled; the item takes Return and type-ahead (a title, an action)",
      zedRow.accessibilityRole() == .menuItem && zedRow.isAccessibilityEnabled() && zedItem.isEnabled && zedItem.action != nil && !zedItem.title.isEmpty)
check("words: a row shows no usage (no number, no bar) and the menu text names no standby address", !QCStandbyMenuRow.title(zedAddress).contains("%") && !menuText.contains("zed"))

// widths and places: every block and row as wide as the widest, laid out as the block's account line is
let longAddress = "a-very-long-standby-account-address-for-a-wide-row@example.org"
let wide = standbyMenu([mainOne, .init(profile: work2, level: nil, address: "ultra-2@example.com", problem: nil, standby: [KnownAccount(uuid: "L", email: longAddress)])])
let wideViews = wide.compactMap { $0.view }
check("widths: every block and row is as wide as the widest", Set(wideViews.map(\.frame.width)).count == 1 && wideViews.count == 4, "\(wideViews.map(\.frame.width))")
check("widths: a long address widens nothing (the room is the stand-in's alone: a longer address is cut while it is revealed, never in a neighbour's place)",
      QCStandbyMenuRow.width(longAddress) == QCStandbyMenuRow.width(zedAddress) && wideViews[0].frame.width == QCStandbyMenuRow.width(longAddress),
      "\(wideViews.map(\.frame.width)) \(QCStandbyMenuRow.width(longAddress))")
check("widths: the rows are as wide as the blocks in a plain menu too", Set(twoProfiles.compactMap { $0.view?.frame.width }).count == 1)
check("widths: a short, a usual and a very long address are all given the same room (the stand-in's): the room says nothing of an address",
      QCStandbyMenuRow.width(zedAddress) == QCStandbyMenuRow.width("z@e.co") && QCStandbyMenuRow.width(longAddress) == QCStandbyMenuRow.width(zedAddress))
let groupBlockOfTwo = twoProfiles[0].view as! QCMenuUsageBlock
check("places: the lamp column, the address's x and the font are the block's account line's",
      QCStandbyMenuRow.lampX == QCMenuUsageBlock.padX && QCStandbyMenuRow.addressX == groupBlockOfTwo.addressRect.minX
      && QCStandbyMenuRow.addressFont === QCProfileMenuRow.addressFont && QCStandbyMenuRow.tagFont === QCMenuUsageBlock.accountFont)
let blurPicture = AddressInk.blurred(AddressText.standIn, color: .labelColor, font: QCStandbyMenuRow.addressFont)
check("places: the row is as tall as the whole blurred picture of the address, so the blur is not cut",
      blurPicture != nil && blurPicture!.size.height <= QCStandbyMenuRow.height && QCStandbyMenuRow.height >= QCStandbyMenuRow.highlightH, "\(String(describing: blurPicture?.size)) in \(QCStandbyMenuRow.height)")

do {
    let row = zedRow
    row.frame = NSRect(x: 0, y: 0, width: max(row.frame.width, 340), height: QCStandbyMenuRow.height)
    check("light: at rest the row is not lit", !row.lit)
    row.highlighted = true
    check("light: highlighted, the row is lit", row.lit)
    row.highlighted = false
    check("light: highlight gone, it is not lit", !row.lit)
    func picture(lit: Bool) -> NSBitmapImageRep? {
        row.highlighted = lit
        defer { row.highlighted = false }
        guard let rep = row.bitmapImageRepForCachingDisplay(in: row.bounds) else { return nil }
        row.cacheDisplay(in: row.bounds, to: rep)
        return rep
    }
    // what is drawn where the address is: blurred at rest (every neighbouring pixel pair close), sharp lit (a hard step)
    func steepest(lit: Bool) -> (steep: Double, ink: Double) {
        guard let rep = picture(lit: lit) else { return (0, 0) }
        let scale = Double(rep.pixelsWide) / Double(row.bounds.width)
        let x0 = Int(Double(QCStandbyMenuRow.addressX) * scale) + 2
        let x1 = Int(Double(QCStandbyMenuRow.addressX + ceil((zedAddress as NSString).size(withAttributes: [.font: QCStandbyMenuRow.addressFont]).width)) * scale) - 2
        // each pixel's grey as seen over a mid grey (what the menu's own background would be under it)
        func seen(_ x: Int, _ y: Int) -> (grey: Double, alpha: Double) {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return (0.5, 0) }
            let a = Double(c.alphaComponent), g = Double(c.redComponent + c.greenComponent + c.blueComponent) / 3
            return (g * a + 0.5 * (1 - a), a)
        }
        var steep = 0.0, ink = 0.0
        for y in 0..<rep.pixelsHigh { for x in x0..<x1 {
            let a = seen(x, y), b = seen(x + 1, y)
            steep = max(steep, abs(a.grey - b.grey))
            ink += a.alpha
        } }
        return (steep, ink)
    }
    let restLook = steepest(lit: false), litLook = steepest(lit: true)
    check("blur: at rest the address region holds blurred ink only (no hard edge), and some ink", restLook.ink > 0 && restLook.steep < 0.2, "\(restLook)")
    check("blur: lit, the same region holds the address sharp (a hard edge between the letters and the highlight)",
          litLook.steep > 2 * restLook.steep && litLook.steep > 0.3, "rest \(restLook) lit \(litLook)")
    // "Switch…" shows at the right only while the row is lit: the pixels there differ from the highlight's own, and at rest there are none
    func marks(in rep: NSBitmapImageRep?, from x0: CGFloat, to x1: CGFloat) -> Int {
        guard let rep else { return -1 }
        let scale = Double(rep.pixelsWide) / Double(row.bounds.width)
        let xs = Int(Double(x0) * scale), xe = Int(Double(x1) * scale)
        let base = rep.colorAt(x: xs, y: rep.pixelsHigh / 2)
        var n = 0
        for y in 0..<rep.pixelsHigh { for x in xs..<xe where rep.colorAt(x: x, y: y) != base { n += 1 } }
        return n
    }
    let hintW = ceil((QCStandbyMenuRow.hint as NSString).size(withAttributes: [.font: QCStandbyMenuRow.tagFont]).width)
    let hintFrom = row.bounds.maxX - QCMenuUsageBlock.padX - hintW - 2, hintTo = row.bounds.maxX - QCMenuUsageBlock.padX + 2
    check("hint: 'Switch…' shows at the right while the row is lit, and not at rest",
          marks(in: picture(lit: true), from: hintFrom, to: hintTo) > 0 && marks(in: picture(lit: false), from: hintFrom, to: hintTo) == 0,
          "\(marks(in: picture(lit: true), from: hintFrom, to: hintTo)) / \(marks(in: picture(lit: false), from: hintFrom, to: hintTo))")
    check("hint: the words are Switch…", QCStandbyMenuRow.hint == "Switch…")
    let lampTo = QCStandbyMenuRow.lampX + QCMenuUsageBlock.dotSize
    let lampRest = picture(lit: false)
    let lampScale = Double(lampRest?.pixelsWide ?? 0) / Double(row.bounds.width)
    check("lamp: a hollow lamp in the lamp column (ring pixels at its edge, none at its centre)",
          marks(in: lampRest, from: QCStandbyMenuRow.lampX, to: lampTo) > 0
          && lampRest?.colorAt(x: Int(Double(QCStandbyMenuRow.lampX + QCMenuUsageBlock.dotSize / 2) * lampScale), y: Int(Double(row.bounds.midY) * lampScale))?.alphaComponent == 0)

    // a click is a release on the row: one released outside it does nothing
    let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 80), styleMask: [.borderless], backing: .buffered, defer: true)   // never shown
    host.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 80))
    host.contentView?.addSubview(row)
    row.frame.origin = NSPoint(x: 20, y: 20)
    check("click: the row sits in a window of its own for the release checks", row.window === host)
    /// A release at a point of the row's own coordinates, as the window would report it.
    func release(atRow p: NSPoint) -> NSEvent? {
        NSEvent.mouseEvent(with: .leftMouseUp, location: row.convert(p, to: nil), modifierFlags: [], timestamp: 0, windowNumber: host.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)
    }
    switched = []
    if let out = release(atRow: NSPoint(x: row.bounds.maxX + 30, y: row.bounds.midY)), let above = release(atRow: NSPoint(x: 60, y: -6)) {
        row.mouseUp(with: out); row.mouseUp(with: above); spin(0.1)
        check("click: a release outside the row picks nothing", switched.isEmpty, "\(switched)")
    } else { check("click: mouse events for the release checks", false) }
    // anywhere on the row: on the lamp, the address, the tag, the empty middle, the hint's place
    for (name, x) in [("the lamp", 17.0), ("the address", QCStandbyMenuRow.addressX + 30), ("the empty middle", row.bounds.maxX - 90), ("the hint's place", row.bounds.maxX - 20), ("the left edge", 3.0)] {
        switched = []
        if let inside = release(atRow: NSPoint(x: x, y: row.bounds.midY)) {
            row.mouseUp(with: inside); spin(0.1)
            check("click: a release on \(name) picks the account, once, with its profile (after the menu closes)", switched == ["main:u9"], "\(switched) at \(x) in \(row.bounds)")
        } else { check("click: mouse event for \(name)", false) }
    }
    row.removeFromSuperview()
}
switched = []
if let t = zedItem.target, let a = zedItem.action { _ = t.perform(a, with: zedItem) }
check("click: the item's own action (Return) goes to the switch path with that profile and account", switched == ["main:u9"], "\(switched)")
switched = []
_ = zedRow.accessibilityPerformPress(); spin(0.1)
check("click: VoiceOver's press does the same", switched == ["main:u9"], "\(switched)")
switched = []
(twoProfiles[2].view as? QCStandbyMenuRow)?.press(); spin(0.1)
check("click: the second row picks its own account", switched == ["main:u8"], "\(switched)")

// while a sign-in for a profile is waited for, its rows are dimmed further and inert; another profile's are not
do {
    let waitingMenu = standbyMenu([mainOne, workOne], switching: { $0.id == "main" })
    let waitMain = waitingMenu[1], waitWork = waitingMenu[4]
    let wRow = waitMain.view as! QCStandbyMenuRow, oRow = waitWork.view as! QCStandbyMenuRow
    check("waiting: the waiting profile's rows are off (the item too) and the other profile's are on", !waitMain.isEnabled && !wRow.enabled && waitWork.isEnabled && oRow.enabled)
    wRow.highlighted = true; oRow.highlighted = true
    switched = []
    wRow.press(); _ = wRow.accessibilityPerformPress(); spin(0.1)
    check("waiting: a dimmed row is never lit, does nothing on a click or a VoiceOver press, and is disabled for VoiceOver",
          !wRow.lit && oRow.lit && switched.isEmpty && !wRow.isAccessibilityEnabled() && oRow.isAccessibilityEnabled(), "\(switched)")
    wRow.highlighted = false; oRow.highlighted = false
    wRow.frame.size.width = 340
    func ink(_ v: NSView) -> Double {
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return 0 }
        v.cacheDisplay(in: v.bounds, to: rep)
        var total = 0.0
        for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide { total += Double(rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) } }
        return total
    }
    oRow.frame.size.width = 340
    check("waiting: a dimmed row is drawn fainter than a standby row at rest", ink(wRow) < ink(oRow) && ink(wRow) > 0, "\(ink(wRow)) vs \(ink(oRow))")
    check("waiting: the block of the waiting profile still opens the chat", (waitingMenu[0].view as? QCMenuUsageBlock) != nil && waitingMenu[0].isEnabled)
}
// a waiting item stays off on its own, not only because the menu doesn't validate its items: with autoenablesItems on
// (the default of a menu) it is still off, and its action does nothing
do {
    let m = NSMenu()
    m.autoenablesItems = true
    standbyMenu([mainOne, workOne], switching: { $0.id == "main" }).forEach(m.addItem)
    m.update()
    let off = m.items[1], on = m.items[4]
    switched = []
    if let t = off.target, let a = off.action { _ = t.perform(a, with: off) }
    spin(0.1)
    check("waiting: with autoenablesItems on, the waiting item is still off and its action does nothing",
          !off.isEnabled && on.isEnabled && switched.isEmpty, "\(off.isEnabled) \(on.isEnabled) \(switched)")
    if let t = on.target, let a = on.action { _ = t.perform(a, with: on) }
    check("waiting: with autoenablesItems on, another profile's item still works", switched == ["work:w1"], "\(switched)")
}

// ── Add an account…: the last row of each profile's group, after its standby rows ──────────────────────
do {
    var added: [String] = []
    let realAdd = QCStatusMenu.allowAddAccount
    QCStatusMenu.allowAddAccount = { _ in true }
    func addMenu(_ infos: [QCStatusMenu.Info], switching: @escaping (Profile) -> Bool = { _ in false }) -> [NSMenuItem] {
        QCStatusMenu.items(infos, now: now, switching: switching, switchTo: { p, a in switched.append("\(p.id):\(a.uuid)") },
                           addAccount: { added.append($0.id) }) { _ in }
    }
    let two = addMenu([mainTwo, workNone]), oneP = addMenu([mainOne]), noStandby = addMenu([workNone])
    check("add: after the standby rows of each profile: its block, its rows, Add an account…, a line, the next profile's", shape(two) == "BRRA-BA", shape(two))
    check("add: a profile with no standby account has its block and Add an account… only (no standby rows)", shape(noStandby) == "BA" && shape(oneP) == "BRA", "\(shape(noStandby)) \(shape(oneP))")
    check("add: no addAccount path, no row (the menu is as before)", shape(standbyMenu([mainTwo, workNone])) == "BRR-B" && shape(items) == "B-B")
    check("add: the block ends close to the rows after it even with no standby account",
          (noStandby[0].view as? QCMenuUsageBlock)?.frame.height == QCMenuUsageBlock.height((noStandby[0].view as! QCMenuUsageBlock).model, joined: true))
    let addItem = two[3], addRow = two[3].view as! QCAddAccountMenuRow
    check("add: the item and the row say Add an account… (title, VoiceOver label), a menu item, no address in it",
          addItem.title == "Add an account…" && addRow.accessibilityLabel() == "Add an account…" && addRow.accessibilityRole() == .menuItem
          && addRow.isAccessibilityEnabled() && addItem.isEnabled && addItem.action != nil && !addItem.title.contains("@"))
    check("add: every block and row of the menu is as wide as the widest", Set(two.compactMap { $0.view?.frame.width }).count == 1, "\(two.compactMap { $0.view?.frame.width })")
    check("add: the columns are the standby row's (lamp and words where its lamp and address are)", addRow.columns == .bar && QCStandbyMenuRow.Columns.bar.addressX == QCStandbyMenuRow.addressX)
    // a click, Return and VoiceOver's press open it on that profile (once each, after the menu closes)
    added = []; addRow.press(); spin(0.1)
    check("add: a click opens Add an account… for its own profile (the one its group is of)", added == ["main"], "\(added)")
    added = []
    if let t = addItem.target, let a = addItem.action { _ = t.perform(a, with: addItem) }
    check("add: the item's own action (Return) does the same", added == ["main"], "\(added)")
    added = []
    _ = addRow.accessibilityPerformPress(); spin(0.1)
    check("add: VoiceOver's press does the same", added == ["main"], "\(added)")
    added = []; (two[6].view as? QCAddAccountMenuRow)?.press(); spin(0.1)
    check("add: the second profile's own row opens it for that profile", added == ["work"], "\(added)")
    // the click's own rule: nothing while a switch is waited for on the profile (a menu built a while ago)
    check("add: the rule is no switch waited for on the profile",
          QCStatusMenu.mayAddAccount(main, waiting: { _ in false }) && !QCStatusMenu.mayAddAccount(main, waiting: { $0.id == "main" }) && QCStatusMenu.mayAddAccount(main, waiting: { $0.id == "work" }))
    QCStatusMenu.allowAddAccount = { _ in false }
    added = []; addRow.press(); spin(0.1)
    check("add: a click the rule refuses opens nothing", added.isEmpty, "\(added)")
    QCStatusMenu.allowAddAccount = realAdd
    check("add: the real rule is the one rows are built with (no switch is waited for here)", QCStatusMenu.mayAddAccount(main))
    QCStatusMenu.allowAddAccount = { _ in true }
    // waiting for a sign-in on the profile: its row is off (the item too), the other profile's is on
    let waitingAdd = addMenu([mainOne, workOne], switching: { $0.id == "main" })
    let offItem = waitingAdd[2], onItem = waitingAdd[6]       // BRA-BRA
    check("add waiting: the waiting profile's row is off, like its standby rows, the other's on",
          shape(waitingAdd) == "BRA-BRA" && !offItem.isEnabled && !(offItem.view as! QCAddAccountMenuRow).enabled && onItem.isEnabled && (onItem.view as! QCAddAccountMenuRow).enabled)
    let offRow = offItem.view as! QCAddAccountMenuRow
    offRow.highlighted = true
    added = []; offRow.press(); _ = offRow.accessibilityPerformPress()
    if let t = offItem.target, let a = offItem.action { _ = t.perform(a, with: offItem) }
    spin(0.1)
    check("add waiting: a dimmed row is never lit, does nothing on a click, a VoiceOver press or Return, and is off for VoiceOver",
          !offRow.lit && added.isEmpty && !offRow.isAccessibilityEnabled(), "\(added)")
    // the look: lit is not the look at rest, dimmed is fainter than at rest
    func picture(_ v: NSView) -> Data? {
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return nil }
        v.cacheDisplay(in: v.bounds, to: rep)
        return rep.tiffRepresentation
    }
    func ink(_ v: NSView) -> Double {
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return 0 }
        v.cacheDisplay(in: v.bounds, to: rep)
        var total = 0.0
        for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide { total += Double(rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) } }
        return total
    }
    let onRow = onItem.view as! QCAddAccountMenuRow
    onRow.frame.size.width = 340; offRow.frame.size.width = 340
    offRow.highlighted = false
    let restPicture = picture(onRow)
    onRow.highlighted = true
    check("add look: lit by the menu it is drawn differently, and is lit", onRow.lit && picture(onRow) != restPicture)
    onRow.highlighted = false
    check("add look: dimmed while a sign-in is waited for it is fainter than at rest, and has ink", ink(offRow) < ink(onRow) && ink(offRow) > 0, "\(ink(offRow)) \(ink(onRow))")
    // the chat's columns: the words start where the in-use row's name does
    let chatRow = QCAddAccountMenuRow(enabled: true, columns: .chat) {}
    check("add: in the chat's menu its words start at the in-use row's text, and its lamp at the dot's",
          QCStandbyMenuRow.Columns.chat.addressX == QCProfileMenuRow.textX && QCStandbyMenuRow.Columns.chat.lampX == QCProfileMenuRow.dotX
          && chatRow.frame.width == QCAddAccountMenuRow.width(columns: .chat) && QCAddAccountMenuRow.width(columns: .chat) > QCAddAccountMenuRow.width(columns: .bar))
    QCStatusMenu.allowAddAccount = realAdd
}

// a click on the block is a release on it: one released outside it does nothing
do {
    var opened = 0
    let b = QCMenuUsageBlock(rich) { opened += 1 }
    let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 300), styleMask: [.borderless], backing: .buffered, defer: true)   // never shown
    host.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
    host.contentView?.addSubview(b)
    b.frame.origin = NSPoint(x: 20, y: 20)
    func release(_ p: NSPoint) -> NSEvent? {
        NSEvent.mouseEvent(with: .leftMouseUp, location: b.convert(p, to: nil), modifierFlags: [], timestamp: 0, windowNumber: host.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)
    }
    if let out = release(NSPoint(x: b.bounds.maxX + 40, y: b.bounds.midY)), let above = release(NSPoint(x: 50, y: -8)), let inside = release(NSPoint(x: 50, y: b.bounds.midY)) {
        b.mouseUp(with: out); b.mouseUp(with: above); spin(0.1)
        check("block: a release outside the block opens nothing", opened == 0, "\(opened)")
        b.mouseUp(with: inside); spin(0.1)
        check("block: a release on the block opens the chat on its profile (after the menu closes)", opened == 1, "\(opened)")
    } else { check("block: mouse events for the release checks", false) }
}

// the account in use changes while the menu is open: the block's old address picture is dropped
do {
    let first = make(level(five: 13, week: 88), address: "aaa-one@example.com")
    let second = make(level(five: 13, week: 88), address: "bbb-two@example.com")
    let open = QCMenuUsageBlock(first) {}, fresh = QCMenuUsageBlock(second) {}
    for v in [open, fresh] { v.setFrameSize(NSSize(width: 340, height: v.frame.height)) }
    func picture(_ v: NSView) -> Data? {
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return nil }
        v.cacheDisplay(in: v.bounds, to: rep)
        return rep.tiffRepresentation
    }
    let before = picture(open)          // draws the first address blurred
    open.reload(second)
    check("live: another account in use is taken in place", open.model.account == second.account)
    // what is blurred is the stand-in, the same for every address: the two accounts look alike at rest, and the block
    // draws the stand-in for both
    check("live: at rest the new account is drawn as the stand-in, exactly as the old one was (nothing of either address in the picture)",
          before != nil && picture(open) == before && picture(open) == picture(fresh)
          && open.drawnAddress == AddressText.standIn && fresh.drawnAddress == AddressText.standIn)
}

// ── a blurred address is a stand-in: nothing of the real one is drawn at rest ─────────────────────────────
do {
    func parts(of a: String) -> [String] {
        // the pieces a candidate could be matched on: the local part, the domain, its words and any 3 letters of it
        let at = a.firstIndex(of: "@")!
        var out = [String(a[..<at]), String(a[a.index(after: at)...])]
        out += a.split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count >= 3 && $0 != "com" }
        return out
    }
    func leaks(_ drawn: String, _ a: String) -> Bool { parts(of: a).contains { drawn.contains($0) } }
    AddressPrivacy.shared.apply(blur: true)
    let one = "zed.sample@example.com", two = "q@e.co"
    // the usage block's account line
    let b1 = QCMenuUsageBlock(make(level(five: 13, week: 88), address: one)) {}, b2 = QCMenuUsageBlock(make(level(five: 13, week: 88), address: two)) {}
    check("stand-in: the block draws the stand-in at rest, nothing of the address", b1.drawnAddress == AddressText.standIn && !leaks(b1.drawnAddress ?? "", one))
    check("stand-in: the same for a different (and a much shorter) address", b1.drawnAddress == b2.drawnAddress)
    b1.hover(at: NSPoint(x: b1.addressRect.midX, y: b1.addressRect.midY))
    check("stand-in: with the pointer on the address the block draws the address itself", b1.drawnAddress == one)
    b1.hover(at: nil)
    check("stand-in: and the stand-in again when it leaves", b1.drawnAddress == AddressText.standIn)
    check("stand-in: the block is as wide for either address (a usual address moves nothing, and says nothing)",
          QCMenuUsageBlock.width(make(level(five: 13, week: 88), address: one)) == QCMenuUsageBlock.width(make(level(five: 13, week: 88), address: two))
          && b1.addressRect.width == b2.addressRect.width)
    // a very long address in the same containers: what follows the address ("· in use", "· standby") stays where it is
    let bLong = QCMenuUsageBlock(make(level(five: 13, week: 88), address: longAddress)) {}
    check("stand-in: a very long address leaves its neighbours where a short one does (the block, the address's room, what follows it)",
          bLong.frame.width == b1.frame.width && bLong.addressRect == b1.addressRect && QCStandbyMenuRow.room(longAddress) == QCStandbyMenuRow.room(one)
          && QCStandbyMenuRow(address: longAddress, enabled: true) {}.frame.width == QCStandbyMenuRow(address: one, enabled: true) {}.frame.width)
    bLong.hover(at: NSPoint(x: bLong.addressRect.midX, y: bLong.addressRect.midY))
    check("stand-in: …revealed, its frame and room are the same (it is cut to the room, never wider)", bLong.drawnAddress == longAddress && bLong.addressRect == b1.addressRect && bLong.frame.width == b1.frame.width)
    // the standby row
    let r1 = QCStandbyMenuRow(address: one, enabled: true) {}, r2 = QCStandbyMenuRow(address: two, enabled: true) {}
    check("stand-in: the standby row draws the stand-in at rest, nothing of the address, the same for another address",
          r1.drawnAddress == AddressText.standIn && r2.drawnAddress == AddressText.standIn && !leaks(r1.drawnAddress, one))
    r1.highlighted = true
    check("stand-in: lit, the standby row draws the address", r1.drawnAddress == one)
    r1.highlighted = false
    check("stand-in: the standby row is as wide for both addresses, so a reveal moves nothing", r1.frame.width == r2.frame.width)
    // blur off: the address
    var offS = QuickChatSettings(); offS.blurAddresses = false
    AddressPrivacy.shared.apply(offS)
    check("stand-in: with Blur addresses off everything draws the address", b1.drawnAddress == one && r1.drawnAddress == one && r2.drawnAddress == two)
    AddressPrivacy.shared.apply(QuickChatSettings())
}

// ── Settings ▸ Blur addresses: on (the default) blurs at rest; off draws every address in full and sharp, and the words hold
// it in full too; it applies to what is built or drawn next ──────────────────────────────────────────────
do {
    func picture(_ v: NSView) -> Data? {
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return nil }
        v.cacheDisplay(in: v.bounds, to: rep)
        return rep.tiffRepresentation
    }
    func build() -> (block: QCMenuUsageBlock, row: QCStandbyMenuRow?, item: NSMenuItem?) {
        let its = QCStatusMenu.items(infos, now: now, switchTo: { _, _ in }) { _ in }
        let b = its.compactMap { $0.view as? QCMenuUsageBlock }.first!
        let line = its.first { $0.view is QCStandbyMenuRow }
        return (b, line?.view as? QCStandbyMenuRow, line)
    }
    check("blur setting: on by default (the shared state and a settings file with no such key)",
          AddressPrivacy.shared.blur && QuickChatSettings().blurAddresses)
    let on = build()
    let onBlock = picture(on.block), onRow = on.row.flatMap(picture)
    check("blur setting: on, the usage block's address is blurred at rest and masked as words, the standby row too",
          !on.block.sharp && on.block.model.lines[1] == maskEmail(mainAddress) + " · in use" && on.row?.sharp == false
          && on.item?.title == zedMasked + " · standby" && on.row?.accessibilityLabel() == zedMasked + ", standby, switch")

    var offSettings = QuickChatSettings(); offSettings.blurAddresses = false
    AddressPrivacy.shared.apply(offSettings)
    let off = build()
    check("blur setting: off, the usage block draws the full address sharp at rest", off.block.sharp && !off.block.revealed)
    check("blur setting: off, the block's words and VoiceOver label hold the full address, no mask",
          off.block.model.lines[1] == mainAddress + " · in use" && off.block.model.spoken.contains(mainAddress) && !off.block.model.spoken.contains("•")
          && (off.block.accessibilityLabel() ?? "").contains(mainAddress), "\(off.block.model.lines)")
    check("blur setting: off, the standby row draws the full address sharp at rest, unlit, and its title and label hold it in full",
          off.row?.sharp == true && off.row?.lit == false && off.row?.address == "zed@example.com"
          && off.item?.title == "zed@example.com · standby" && off.row?.accessibilityLabel() == "zed@example.com, standby, switch")
    check("blur setting: off, what is drawn differs from the blurred look", picture(off.block) != onBlock && off.row.flatMap(picture) != onRow)
    // a dimmed row shows the address in full too
    var dimmedFired = 0
    let dimmedRow = QCStandbyMenuRow(address: "zed@example.com", enabled: false) { dimmedFired += 1 }
    dimmedRow.press(); _ = dimmedRow.accessibilityPerformPress(); spin(0.1)
    check("blur setting: off, a dimmed row is sharp as well (and still does nothing)", dimmedRow.sharp && dimmedFired == 0)

    AddressPrivacy.shared.apply(QuickChatSettings())
    let back = build()
    check("blur setting: on again, the next menu blurs and masks as before", !back.block.sharp && back.block.model.lines[1] == maskEmail(mainAddress) + " · in use"
          && back.row?.sharp == false && back.item?.title == zedMasked + " · standby" && picture(back.block) == onBlock)
}

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
    // a click on A's standby row (built while A was on standby) asks the question only while A is still on standby and no
    // switch is waited for: the rule itself, then through a row after another sign-in moved the folder to A
    let ugA = KnownAccount(uuid: "ug-a", email: "gamma-a@example.com"), ugB = KnownAccount(uuid: "ug-b", email: "gamma-b@example.com")
    check("click rule: a standby account may start the switch; the account in use, an unknown one, or any while waiting, may not",
          QCStatusMenu.mayStartSwitch(pg, ugA, store: store, waiting: { _ in false }) && !QCStatusMenu.mayStartSwitch(pg, ugB, store: store, waiting: { _ in false })
          && !QCStatusMenu.mayStartSwitch(pg, KnownAccount(uuid: "nobody", email: "nobody@example.com"), store: store, waiting: { _ in false })
          && !QCStatusMenu.mayStartSwitch(pg, ugA, store: store, waiting: { $0.id == "gamma" }) && QCStatusMenu.mayStartSwitch(pg, ugA, store: store, waiting: { $0.id == "other" }))
    check("click rule: the real rule is the one rows are built with (no switch is waited for here)", QCStatusMenu.mayStartSwitch(pg, ugA, store: store))
    QCStatusMenu.allowSwitch = realAllow
    switched = []
    let (staleItem, staleRow) = QCStatusMenu.standbyItem(pg, ugA, waiting: false, switchTo: { p, a in switched.append("\(p.id):\(a.uuid)") })
    staleRow.press(); spin(0.1)
    check("click rule: while A is on standby a click asks the question", switched == ["gamma:ug-a"], "\(switched)")
    signIn("gamma-a@example.com", "ug-a")          // a sign-in finished while the menu was open: A is now in use
    switched = []
    staleRow.press(); _ = staleRow.accessibilityPerformPress()
    if let t = staleItem.target, let a = staleItem.action { _ = t.perform(a, with: staleItem) }
    spin(0.1)
    check("click rule: once A is the account in use the row's click, VoiceOver press and Return do nothing", switched.isEmpty, "\(switched)")
    signIn("gamma-b@example.com", "ug-b")
    QCStatusMenu.allowSwitch = { _, _ in true }
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
