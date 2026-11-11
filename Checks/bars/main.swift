// The model and thinking controls' checks, against the operator's complaints about build 103 ("couldn't manage the model
// at all"; the control "changes its size and escapes from the mouse"), without a mouse or any event posting. The real
// panel is opened (read-only: nothing is written under the user's folders) and laid out by SwiftUI, on a model list in
// the shape Claude Code gives it (each family by name alone, the version in its description), with four, three and two
// families; as the bar and as the chat window, at 320, 440 and 640:
//   - the model control has a bar for every family the account has, always shown, and the bars end before Send;
//   - picking every model and every thinking level leaves every control, every bar and Send exactly where they were;
//   - a click on each bar's centre (the action of the bar found at that point) picks that bar's value; a level the
//     model doesn't take does nothing;
//   - the scroll wheel over a control steps it (a notch a step, a trackpad's deltas add up, momentum not), and
//     scrolling elsewhere is left alone;
//   - the bar's usage indicator shows the limit closest to full, its label on that window's row (or, in a row too
//     narrow, the bars alone), never moving sideways or changing width, and ending before Send; ⌘W hides.
//   Checks/bars.sh

import AppKit
import SwiftUI

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

/// Every control's and bar's frame, as SwiftUI laid them out, and Send's.
func frames() -> [String: CGRect] {
    var f: [String: CGRect] = [:]
    for (k, v) in targets.controls { f[k] = v.frame }
    for (k, v) in targets.bars { f[k] = v.frame }
    for (k, v) in targets.halves { f[k] = v.frame }
    if let s = targets.marks["send"] { f["send"] = s }
    return f
}
/// A click on a label's half ("m>", "t<"): the half found at its centre must be exactly that one, and no bar; its
/// action is then called.
func press(_ key: String) -> Bool {
    guard let h = targets.halves[key] else { return false }
    let c = CGPoint(x: h.frame.midX, y: h.frame.midY)
    let hit = targets.halves.filter { $0.value.frame.contains(c) }
    guard hit.count == 1, hit.first?.key == key, !targets.bars.contains(where: { $0.value.frame.contains(c) }) else { return false }
    h.press()
    spin()
    return true
}
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
    m.choose(top); m.choose(QuickChatThinking.high)
    spin(0.4)
    let base = frames()
    // the operator couldn't manage the model at all: one bar per family, each its own target, always shown
    check("\(name): a bar for every family", m.modelChoices.map(\.choice) == families, "\(m.modelChoices.map(\.choice))")
    let keys = ["m", "t"] + families.indices.map { "m\($0)" } + levels.indices.map { "t\($0)" }
    let halves = ["m<", "m>", "t<", "t>"]
    check("\(name): every control, bar and label half is laid out, and no other", Set(base.keys).subtracting(["send"]) == Set(keys + halves), "\(base.keys.sorted())")
    // each label splits in two halves side by side, the left one from the control's edge, the right one up to the bars
    for c in ["m", "t"] {
        let l = base["\(c)<"] ?? .zero, r = base["\(c)>"] ?? .zero, whole = base[c] ?? .zero, first = base["\(c)0"] ?? .zero
        check("\(name): \(c)'s label halves split it", abs(l.minX - whole.minX) < 0.01 && abs(l.maxX - r.minX) < 0.01 && r.maxX <= first.minX + 0.01
              && abs(l.width - r.width) < 0.6 && l.width > 6 && abs(l.height - whole.height) < 0.01 && abs(r.height - whole.height) < 0.01,
              "\(l) \(r) in \(whole), first bar \(first)")
    }
    // the bars never overlap Send
    if let s = base["send"], let t = base["t"] {
        check("\(name): the bars end before Send", t.maxX <= s.minX, "\(t.maxX) vs \(s.minX)")
    }
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
    for k in keys + halves {
        let f = base[k] ?? .zero
        let pts = k.count == 1 ? [CGPoint(x: f.minX + 3, y: f.midY), CGPoint(x: f.midX, y: f.midY)] : [CGPoint(x: f.midX, y: f.midY), CGPoint(x: f.midX, y: f.minY + 2)]
        for q in pts {
            check("\(name): a press at \(k) (\(Int(q.x)), \(Int(q.y))) is not a move", QCDragView.surface(at: inWindow(q), in: p) == nil)
        }
    }
    if let t = base["t"] {
        // past the outline (4 pt) and the row's 2 pt spacing: the spacer, the window's to move
        check("\(name): the gap after the bars moves the window", QCDragView.surface(at: inWindow(CGPoint(x: t.maxX + 7, y: t.midY)), in: p) != nil)
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
    // a click on the label's right half: the next value, round past the last; on its left half the one before, round
    // past the first; only values the model takes; nothing moves on any of them
    func round(_ k: String, _ n: Int, _ now: () -> String) -> [String] {
        var seen = [now()]
        for i in 0..<n {
            check("\(name): the half at \(k)'s centre is \(k) (click \(i + 1))", press(k))
            seen.append(now())
            check("\(name): \(k) click \(i + 1) (\(now())) moves nothing", same(frames(), base), moved(base, frames()))
        }
        return seen
    }
    let fam = { m.resolvedModel.family.rawValue }, lvl = { m.effectiveThinking.rawValue }
    m.choose(families[0]); spin()
    let names = families.map(\.rawValue)
    var seen = round("m>", families.count, fam)
    check("\(name): the model's right half goes round forward", seen == names + [names[0]], "\(seen)")
    seen = round("m<", families.count, fam)
    check("\(name): the model's left half goes round back", seen == [names[0]] + names.reversed(), "\(seen)")
    for f in families {
        m.choose(f); m.choose(QuickChatThinking.off); spin()
        let steps = takes[f]!.map(\.rawValue)
        seen = round("t>", steps.count, lvl)
        check("\(name): \(f.rawValue), thinking's right half goes round forward over what it takes", seen == steps + ["off"], "\(seen)")
        seen = round("t<", steps.count, lvl)
        check("\(name): \(f.rawValue), thinking's left half goes round back over what it takes", seen == ["off"] + steps.reversed(), "\(seen)")
    }
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
}

let sets: [[QuickChatModelChoice]] = [[.haiku, .sonnet, .opus, .fable], [.haiku, .sonnet, .opus], [.haiku, .sonnet]]
for fams in sets {
    let list = fullList.filter { e in e.value == "default" || QuickChatModels.family(e).map { fams.contains($0.0) } == true }
    ModelCatalog.shared.set(list, profile: t.profileID, account: t.accountUUID)
    m.turns = []
    spin(0.6)
    for w in [CGFloat(320), 440, 640] {
        width(w)
        scenario("\(fams.count) families, bar at \(Int(w))", families: fams)
    }
    var turn = QuickChatTurn(question: "q", answer: "a", model: "Opus 5.5"); turn.phase = .done
    m.turns = [turn]
    spin(0.6)
    for w in [CGFloat(320), 440, 640] {
        width(w)
        scenario("\(fams.count) families, window at \(Int(w))", families: fams)
    }
}

// the bar's usage indicator: the limit closest to full, its label and share on that window's row, one width whatever
// it says; the profile's dot in the same colour
m.turns = []
spin(0.6)
for w in [CGFloat(320), 440, 640] {
    width(w)
    var first: (ui: CGRect, five: CGRect, week: CGRect)?
    for (five, week) in [(78.0, 20.0), (30.0, 85.0), (9.0, 9.5), (100.0, 64.0), (0.0, 100.0), (55.0, 54.9)] {
        var l = QuickChatLevel(); l.fiveHour = five; l.fiveHourResets = Date().addingTimeInterval(7200); l.week = week
        l.weekResets = Date().addingTimeInterval(3 * 86400); m.level = l; spin()
        let higher = l.binding()?.id ?? "-"
        let ui = targets.marks["usage"] ?? .zero, label = targets.marks["usage-label"] ?? .zero, share = targets.marks["usage-share"] ?? .zero
        let row = targets.marks["usage-\(higher)"] ?? .zero
        let rows = (five: targets.marks["usage-5h"] ?? .zero, week: targets.marks["usage-wk"] ?? .zero)
        let name = "usage at \(Int(w)), 5h \(five) wk \(week)"
        // a narrow row keeps the two bars alone (the share on hover)
        let barsOnly = abs(ui.width - QCUsageView.width(numbers: false)) < 0.5
        check("\(name): shown", ui != .zero, "\(ui)")
        check("\(name): \(higher) is the higher one", higher == (five >= week || l.full()?.id == "5h" ? "5h" : "wk") || (l.full()?.id == "wk" && higher == "wk"))
        if !barsOnly {
            // the label, then the bars, then the share, the label and share on the higher window's row
            check("\(name): its label sits on the \(higher) row", label != .zero && abs(label.midY - row.midY) <= 1.5, "\(label.midY) vs \(row.midY)")
            check("\(name): its share sits on the \(higher) row", share != .zero && abs(share.midY - row.midY) <= 1.5, "\(share.midY) vs \(row.midY)")
            check("\(name): the label comes before the bars, the share after", label.maxX <= row.minX + 0.01 && share.minX >= row.maxX - 0.01,
                  "label \(label), bar \(row), share \(share)")
        }
        if let s = targets.marks["send"] { check("\(name): it ends before Send", ui.maxX <= s.minX, "\(ui.maxX) vs \(s.minX)") }
        // across the row: a full limit opens its notice above the field and the whole row moves down with the field
        if let f = first {
            check("\(name): the indicator never moves sideways or changes width", ui.minX == f.ui.minX && ui.width == f.ui.width, "\(ui) vs \(f.ui)")
            check("\(name): its bars never move sideways", rows.five.minX == f.five.minX && rows.week.minX == f.week.minX && rows.five.width == f.five.width,
                  "\(rows) vs \(f)")
        } else { first = (ui, rows.five, rows.week) }
    }
}

// narrower than the panel ever is (a row of its own in the panel, made narrower step by step): the labels shorten and
// the usage indicator keeps its bars alone, but never goes, and nothing reaches Send; its card then gives both shares
do {
    var l = QuickChatLevel(); l.fiveHour = 78; l.fiveHourResets = Date().addingTimeInterval(7200); l.week = 20
    l.weekResets = Date().addingTimeInterval(3 * 86400); m.level = l
    let probe = NSHostingView(rootView: QCControls(model: m, inBar: true))
    p.contentView?.addSubview(probe)
    probe.frame = NSRect(x: 0, y: 0, width: 640, height: QCSpace.row); spin()
    let wide: CGFloat? = targets.controls["m"]?.frame.width
    var barsAt: CGFloat?
    for w in stride(from: CGFloat(320), through: 160, by: -4) {
        probe.frame = NSRect(x: 0, y: 0, width: w, height: QCSpace.row); spin()
        let ui = targets.marks["usage"] ?? .zero, mw = targets.controls["m"]?.frame.width ?? 0
        check("narrow row at \(Int(w)): the usage indicator is shown", ui != .zero && (abs(ui.width - QCUsageView.width(numbers: true)) < 0.5
              || abs(ui.width - QCUsageView.width(numbers: false)) < 0.5), "\(ui)")
        if abs(ui.width - QCUsageView.width(numbers: false)) < 0.5 {
            barsAt = w
            let t = targets.controls["t"]?.frame ?? .zero, s = targets.marks["send"] ?? .zero
            check("narrow row at \(Int(w)): the bars, then the usage bars, then Send, none over another", t.maxX <= ui.minX && ui.maxX <= s.minX,
                  "thinking \(t), usage \(ui), send \(s)")
            check("narrow row at \(Int(w)): the labels are letters", mw > 0 && mw < (wide ?? 0), "\(mw) vs \(wide ?? 0)")
            break
        }
    }
    check("a narrow enough row keeps the usage bars alone", barsAt != nil)
    check("with the bars alone the card gives both shares, else the one the row lacks",
          QCUsageCard.leftOut(l, rowShowsShare: false) == nil && QCUsageCard.leftOut(l, rowShowsShare: true) == "5h")
    probe.removeFromSuperview(); spin()
}

// ⌘W hides at once
if let w = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: p.windowNumber,
                            context: nil, characters: "w", charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13) {
    check("⌘W is taken", p.performKeyEquivalent(with: w))
    spin()
    check("⌘W hides the panel", !p.isVisible)
} else { check("a ⌘W event can be made", false) }

CheckQuiet.verify("at the end")
print("model and thinking control checks: \(passed)/\(passed + failed) passed")
exit(failed == 0 ? 0 : 1)
