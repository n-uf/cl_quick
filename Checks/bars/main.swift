// The model and thinking controls' checks, against the operator's complaints about build 103 ("couldn't manage the model
// at all"; the control "changes its size and escapes from the mouse"), without a mouse or any event posting. The real
// panel is opened (read-only: nothing is written under the user's folders) and laid out by SwiftUI, on a model list in
// the shape Claude Code gives it (each family by name alone, the version in its description), with four, three and two
// families; as the bar and as the chat window, at the first width and at the least (320):
//   - at rest the "Opus · High" pill keeps one width and place through every value ("must not wobble"); a click on it
//     opens the bars over the row and nothing in the row moves; a press inside keeps them open, one outside closes
//     them, as do the pill again and Esc;
//   - the model control has a bar for every family the account has;
//   - picking every model and every thinking level leaves every control and every bar exactly where it was;
//   - a click on each bar's centre (the action of the bar found at that point) picks that bar's value; a level the
//     model doesn't take does nothing;
//   - the scroll wheel over a control steps it (a notch a step, a trackpad's deltas add up, momentum not), and
//     scrolling elsewhere is left alone;
//   - the bar's usage indicator shows the limit closest to full, its label on that window's row, never moving sideways
//     or changing width.
//   Checks/bars.sh

import AppKit

Files.readOnly = true
let app = NSApplication.shared
CheckQuiet.start()          // nothing on any screen, never the keyboard, never active (Checks/quiet.swift)
let chat = QuickChat.shared
chat.start()
// no real `claude`: opening the panel would start one on the user's own profile (QuickChatModel.warm) and its models
// would replace the sample list mid-run (on a real account Haiku may well take Max)
chat.model.resolveClaude = { $0(nil) }

var failed = 0, passed = 0
func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    if ok { passed += 1 } else { failed += 1; print("FAIL \(name) \(detail())") }
}
func spin(_ s: TimeInterval = 0.12) { RunLoop.current.run(until: Date().addingTimeInterval(s)); CheckQuiet.verify("after a spin") }
let m = chat.model
let targets = QCStepTargets.shared

chat.open()
spin(0.8)
guard let p = NSApp.windows.compactMap({ $0 as? QuickChatPanel }).first else { print("FAIL no panel"); exit(1) }
if m.target == nil { m.target = QuickChatTarget(Profile(id: "main", name: "Main", folder: "~/.claude-sample")) }
let t = m.target!
let efforts = ["low", "medium", "high", "xhigh", "max"]
let fullList: [QuickChatModelEntry] = [
    .init(value: "default", displayName: "Default (recommended)", description: "Opus 5.5 · Best for everyday, complex tasks", efforts: efforts),
    .init(value: "haiku", displayName: "Haiku", description: "Haiku 5.5 · Fastest for quick answers", efforts: ["low", "medium", "high"]),
    .init(value: "sonnet", displayName: "Sonnet", description: "Sonnet 5.5 · Efficient for routine tasks", efforts: Array(efforts.prefix(4))),
    .init(value: "opus", displayName: "Opus", description: "Opus 5.5 · Best for everyday, complex tasks", efforts: efforts),
    .init(value: "claude-fable-5-1[1m]", displayName: "Fable", description: "Fable 5.1 · Most capable", efforts: efforts),
]
let levels = QuickChatThinking.allCases

/// Every control's and bar's frame, as SwiftUI laid them out, with the pill and the open bars' panel.
func frames() -> [String: CGRect] {
    var f: [String: CGRect] = [:]
    for (k, v) in targets.controls { f[k] = v.frame }
    for (k, v) in targets.bars { f[k] = v.frame }
    if let pill = targets.pill { f["pill"] = pill.frame }
    if let o = targets.marks["open"], o != .zero { f["open"] = o }
    return f
}
/// The pill's frame alone (the row at rest).
func pillFrame() -> [String: CGRect] { targets.pill.map { ["pill": $0.frame] } ?? [:] }
func same(_ a: [String: CGRect], _ b: [String: CGRect]) -> Bool {
    a.keys.sorted() == b.keys.sorted() && a.allSatisfy { k, r in
        guard let s = b[k] else { return false }
        return abs(r.minX - s.minX) < 0.01 && abs(r.minY - s.minY) < 0.01 && abs(r.width - s.width) < 0.01 && abs(r.height - s.height) < 0.01
    }
}
func moved(_ a: [String: CGRect], _ b: [String: CGRect]) -> String {
    a.keys.sorted().compactMap { k in b[k] == a[k] ? nil : "\(k): \(a[k].map { "\($0)" } ?? "-") → \(b[k].map { "\($0)" } ?? "-")" }.joined(separator: "; ")
}
/// The bar found at the centre of bar `key`'s frame must be exactly that one; its action is then called.
func click(_ key: String) -> Bool {
    guard let f = targets.bars[key]?.frame else { return false }
    let c = CGPoint(x: f.midX, y: f.midY)
    let hit = targets.bars.filter { $0.value.frame.contains(c) }
    guard hit.count == 1, hit.first?.key == key else { return false }
    hit.first!.value.pick()
    spin()
    return true
}
func centre(_ key: String) -> CGPoint { let f = targets.controls[key]?.frame ?? .zero; return CGPoint(x: f.midX, y: f.midY) }
/// A point of the hosting view (SwiftUI's top-left frames) in the window, as an event's locationInWindow would be.
func inWindow(_ q: CGPoint) -> NSPoint {
    guard let cv = p.contentView else { return .zero }
    return cv.convert(NSPoint(x: q.x, y: cv.isFlipped ? q.y : cv.bounds.height - q.y), to: nil)
}

func width(_ w: CGFloat) {
    var f = p.frame
    f.size.width = w + 2 * QuickChatRoot.margin
    p.setFrame(f, display: true)
    spin(0.5)
}

func scenario(_ name: String, families: [QuickChatModelChoice]) {
    let top = families.last!
    m.controlsOpen = false
    m.choose(top); m.choose(QuickChatThinking.high)
    spin(0.4)
    // at rest: the "Opus · High" pill keeps one width and place through every value ("must not wobble"), and the gap
    // after it is still the window's to move
    let rest = pillFrame()
    check("\(name): the pill is laid out", rest["pill"] != nil, "\(rest)")
    check("\(name): at rest the bars are closed", targets.controls.isEmpty && targets.bars.isEmpty, "\(targets.controls.keys.sorted())")
    for f in families {
        for l in levels {
            m.choose(f); m.choose(l); spin(0.06)
            check("\(name): at rest, \(f.rawValue) / \(l.rawValue) moves nothing", same(pillFrame(), rest), moved(rest, pillFrame()))
        }
    }
    if let pf = rest["pill"] {
        check("\(name): a press on the pill is not a move", QCDragView.surface(at: inWindow(CGPoint(x: pf.midX, y: pf.midY)), in: p) == nil)
        check("\(name): the gap after the pill moves the window", QCDragView.surface(at: inWindow(CGPoint(x: pf.maxX + 3, y: pf.midY)), in: p) != nil)
    }
    // a click on the pill opens the bars over the row; nothing in the row moves for it
    m.choose(top); m.choose(QuickChatThinking.high); spin()
    targets.pill?.toggle(); spin(0.3)
    check("\(name): a click on the pill opens the bars", m.controlsOpen && targets.controls["m"] != nil && targets.controls["t"] != nil)
    check("\(name): opening moves nothing in the row", same(pillFrame(), rest), moved(rest, pillFrame()))
    let base = frames()
    // the operator couldn't manage the model at all: one bar per family, each its own target
    check("\(name): a bar for every family", m.modelChoices.map(\.choice) == families, "\(m.modelChoices.map(\.choice))")
    let keys = ["m", "t"] + families.indices.map { "m\($0)" } + levels.indices.map { "t\($0)" }
    check("\(name): every control and bar is laid out, and no other", Set(base.keys).subtracting(["pill", "open"]) == Set(keys), "\(base.keys.sorted())")
    check("\(name): the open bars are drawn over the pill, not beside it", (base["open"] ?? .zero).intersects(rest["pill"] ?? .zero))
    for k in keys.dropFirst(2) {
        let r = base[k] ?? .zero
        check("\(name): \(k) is an 8 × 28 target", abs(r.width - 8) < 0.01 && abs(r.height - 28) < 0.01, "\(r)")
    }
    // compact, and the targets still easy: each control at most 95 pt, its bars' targets touching edge to edge
    for c in ["m", "t"] {
        let w = base[c]?.width ?? 0
        check("\(name): the \(c == "m" ? "model" : "thinking") control is compact (\(Int(w)) pt)", w > 0 && w <= 95, "\(w)")
        let n = c == "m" ? families.count : levels.count
        for j in 1..<n {
            let a = base["\(c)\(j - 1)"] ?? .zero, b = base["\(c)\(j)"] ?? .zero
            check("\(name): \(c)\(j - 1) and \(c)\(j) touch", abs(a.maxX - b.minX) < 0.01, "\(a.maxX) / \(b.minX)")
        }
    }
    // the control changed its size and escaped from the mouse: every value, every family, nothing moves
    for f in families {
        m.choose(f); spin()
        check("\(name): \(f.rawValue) moves nothing", same(frames(), base), moved(base, frames()))
        for l in m.thinkingSteps {
            m.choose(l); spin()
            check("\(name): \(f.rawValue) / \(l.rawValue) moves nothing", same(frames(), base), moved(base, frames()))
        }
    }
    // the window's own hit test, at the real coordinates: a press on any bar or label never starts a move, and the
    // empty gap after the controls does (so the frames are where the window sees them)
    for k in keys {
        let f = base[k] ?? .zero
        let pts = k.count == 1 ? [CGPoint(x: f.minX + 3, y: f.midY), CGPoint(x: f.midX, y: f.midY)] : [CGPoint(x: f.midX, y: f.midY), CGPoint(x: f.midX, y: f.minY + 2)]
        for q in pts {
            check("\(name): a press at \(k) (\(Int(q.x)), \(Int(q.y))) is not a move", QCDragView.surface(at: inWindow(q), in: p) == nil)
        }
    }
    // the limits changing (the bar's usage indicator) moves nothing (a full limit is another matter: its notice opens
    // above the field and the row moves down with the field, as it always has)
    let week = m.level
    m.level = nil; spin()
    check("\(name): no week known moves nothing", same(frames(), base), moved(base, frames()))
    var l = QuickChatLevel(); l.week = 99; m.level = l; spin()
    check("\(name): a week of 99% moves nothing", same(frames(), base), moved(base, frames()))
    l.week = 7; m.level = l; spin()
    check("\(name): a week of 7% moves nothing", same(frames(), base), moved(base, frames()))
    m.level = week; spin()
    // a click on each bar's centre picks it
    for (j, f) in families.enumerated() {
        check("\(name): the bar at m\(j)'s centre is m\(j)", click("m\(j)"))
        check("\(name): clicking m\(j) picks \(f.rawValue)", m.resolvedModel.family == f, "\(m.resolvedModel.family)")
    }
    // every model and every level: a level the model takes is picked by its bar; one it doesn't (faint) does nothing
    let takes: [QuickChatModelChoice: [QuickChatThinking]] = [.haiku: [.off, .low, .medium, .high], .sonnet: [.off, .low, .medium, .high, .xhigh],
                                                              .opus: levels, .fable: levels]
    for f in families {
        m.choose(f); m.choose(QuickChatThinking.off); spin()
        check("\(name): \(f.rawValue) takes the sample list's levels", m.thinkingSteps == takes[f], "\(m.thinkingSteps)")
        for (j, l) in levels.enumerated() {
            let before = m.effectiveThinking
            check("\(name): the bar at t\(j)'s centre is t\(j) on \(f.rawValue)", click("t\(j)"))
            let want = takes[f]!.contains(l) ? l : before
            check("\(name): \(f.rawValue), clicking \(l.rawValue) \(want == l ? "picks it" : "(not taken) does nothing")",
                  m.effectiveThinking == want && m.thinking == (want == l ? l : before), "\(m.effectiveThinking) / saved \(m.thinking)")
        }
    }
    check("\(name): the faint levels keep their place", same(frames(), base), moved(base, frames()))
    // the scroll wheel
    m.choose(families[families.count - 2]); m.choose(QuickChatThinking.low); spin()
    targets.scroll(at: centre("t"), by: 1, precise: false, began: true); spin()
    check("\(name): a notch up over thinking: Medium", m.effectiveThinking == .medium, "\(m.effectiveThinking)")
    targets.scroll(at: centre("t"), by: -2, precise: false, began: true); spin()
    check("\(name): two notches down: Off", m.effectiveThinking == .off, "\(m.effectiveThinking)")
    targets.scroll(at: centre("t"), by: 10, precise: true, began: true)
    targets.scroll(at: centre("t"), by: 10, precise: true, began: false); spin()
    check("\(name): a trackpad's 20 pt is not yet a step", m.effectiveThinking == .off, "\(m.effectiveThinking)")
    targets.scroll(at: centre("t"), by: 6, precise: true, began: false); spin()
    check("\(name): 26 pt is one", m.effectiveThinking == .low, "\(m.effectiveThinking)")
    targets.scroll(at: centre("t"), by: 80, precise: true, began: false, momentum: true); spin()
    check("\(name): momentum steps nothing", m.effectiveThinking == .low, "\(m.effectiveThinking)")
    targets.scroll(at: centre("m"), by: 1, precise: false, began: true); spin()
    check("\(name): a notch up over the model: \(top.rawValue)", m.resolvedModel.family == top, "\(m.resolvedModel.family)")
    check("\(name): scrolling elsewhere is left alone", !targets.scroll(at: CGPoint(x: 1, y: 1), by: 1, precise: false, began: true))
    // a trackpad gesture that began in the chat and drifts onto the row is the chat's, its momentum too
    let was = m.effectiveThinking
    check("\(name): a gesture begun elsewhere is not taken", !targets.scroll(at: CGPoint(x: 1, y: 1), by: 5, precise: true, began: true)
          && !targets.scroll(at: centre("t"), by: 40, precise: true, began: false)
          && !targets.scroll(at: centre("t"), by: 40, precise: true, began: false, momentum: true))
    spin()
    check("\(name): and steps nothing", m.effectiveThinking == was, "\(m.effectiveThinking)")
    check("\(name): after it all, nothing moved", same(frames(), base), moved(base, frames()))
    // a press inside the open bars keeps them open; one outside closes them (and the press still does its own thing)
    if let b0 = base["t0"] { targets.pressed(at: CGPoint(x: b0.midX, y: b0.midY)) }
    check("\(name): a press on a bar keeps them open", m.controlsOpen)
    targets.pressed(at: CGPoint(x: 4, y: 4)); spin()
    check("\(name): a click outside closes them", !m.controlsOpen && targets.controls.isEmpty)
    check("\(name): closing moves nothing in the row", same(pillFrame(), rest), moved(rest, pillFrame()))
    // the pill again, and Esc
    targets.pill?.toggle(); spin(0.3)
    targets.pill?.toggle(); spin(0.3)
    check("\(name): a second click on the pill closes them", !m.controlsOpen)
    targets.pill?.toggle(); spin(0.3)
    m.escape(); spin()
    check("\(name): Esc closes them, and the panel stays", !m.controlsOpen && p.isVisible)
}

let sets: [[QuickChatModelChoice]] = [[.haiku, .sonnet, .opus, .fable], [.haiku, .sonnet, .opus], [.haiku, .sonnet]]
for fams in sets {
    let list = fullList.filter { e in e.value == "default" || QuickChatModels.family(e).map { fams.contains($0.0) } == true }
    ModelCatalog.shared.set(list, profile: t.profileID, account: t.accountUUID)
    m.turns = []
    spin(0.6)
    width(QuickChatRoot.width)
    scenario("\(fams.count) families, bar at the first width", families: fams)
    width(QuickChatRoot.minWidth)
    scenario("\(fams.count) families, bar at 320", families: fams)
    var turn = QuickChatTurn(question: "q", answer: "a", model: "Opus 5.5"); turn.phase = .done
    m.turns = [turn]
    spin(0.6)
    width(QuickChatRoot.width)
    scenario("\(fams.count) families, window at the first width", families: fams)
    width(QuickChatRoot.minWidth)
    scenario("\(fams.count) families, window at 320", families: fams)
}

// the bar's usage indicator: the limit closest to full, its label and share on that window's row, one width whatever
// it says; the profile's dot in the same colour
m.turns = []
spin(0.6)
for w in [QuickChatRoot.width, CGFloat(440)] {
    width(w)
    var first: CGRect?
    for (five, week) in [(78.0, 20.0), (30.0, 85.0), (9.0, 9.5), (100.0, 64.0), (0.0, 100.0), (55.0, 54.9)] {
        var l = QuickChatLevel(); l.fiveHour = five; l.fiveHourResets = Date().addingTimeInterval(7200); l.week = week
        l.weekResets = Date().addingTimeInterval(3 * 86400); m.level = l; spin()
        let higher = l.binding()?.id ?? "-"
        let ui = targets.marks["usage"] ?? .zero, label = targets.marks["usage-label"] ?? .zero, row = targets.marks["usage-\(higher)"] ?? .zero
        let name = "usage at \(Int(w)), 5h \(five) wk \(week)"
        check("\(name): shown", ui != .zero && label != .zero, "\(ui) \(label)")
        check("\(name): \(higher) is the higher one", higher == (five >= week || l.full()?.id == "5h" ? "5h" : "wk") || (l.full()?.id == "wk" && higher == "wk"))
        check("\(name): its label sits on the \(higher) row", abs(label.midY - row.midY) <= 1.5, "\(label.midY) vs \(row.midY)")
        // across the row: a full limit opens its notice above the field and the whole row moves down with the field
        if let f = first { check("\(name): the indicator never moves sideways or changes width", ui.minX == f.minX && ui.width == f.width, "\(ui) vs \(f)") } else { first = ui }
    }
}

CheckQuiet.verify("at the end")
print("model and thinking control checks: \(passed)/\(passed + failed) passed")
exit(failed == 0 ? 0 : 1)
