// The model and thinking controls' checks, against the operator's complaints about build 103 ("couldn't manage the model
// at all"; the control "changes its size and escapes from the mouse"), without a mouse or any event posting. The real
// panel is opened (read-only: nothing is written under the user's folders) and laid out by SwiftUI, on a model list in
// the shape Claude Code gives it (each family by name alone, the version in its description), with four, three and two
// families; as the bar and as the chat window, at the first width and at the least (320):
//   - the model control has a bar for every family the account has;
//   - picking every model and every thinking level leaves every control and every bar exactly where it was;
//   - a click on each bar's centre (the action of the bar found at that point) picks that bar's value; a level the
//     model doesn't take does nothing;
//   - the scroll wheel over a control steps it (a notch a step, a trackpad's deltas add up, momentum not), and
//     scrolling elsewhere is left alone.
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

/// Every control's and bar's frame, as SwiftUI laid them out.
func frames() -> [String: CGRect] {
    var f: [String: CGRect] = [:]
    for (k, v) in targets.controls { f[k] = v.frame }
    for (k, v) in targets.bars { f[k] = v.frame }
    return f
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
    // the operator couldn't manage the model at all: one bar per family, each its own target
    check("\(name): a bar for every family", m.modelChoices.map(\.choice) == families, "\(m.modelChoices.map(\.choice))")
    let keys = ["m", "t"] + families.indices.map { "m\($0)" } + levels.indices.map { "t\($0)" }
    check("\(name): every control and bar is laid out, and no other", Set(base.keys) == Set(keys), "\(base.keys.sorted())")
    for k in keys.dropFirst(2) {
        let r = base[k] ?? .zero
        check("\(name): \(k) is a 10 × 28 target", abs(r.width - 10) < 0.01 && abs(r.height - 28) < 0.01, "\(r)")
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
    if let tf = base["t"] {
        check("\(name): the gap after the controls moves the window", QCDragView.surface(at: inWindow(CGPoint(x: tf.maxX + 2, y: tf.midY)), in: p) != nil)
    }
    // the week arriving or going (the bar's meter) moves nothing (a full week is another matter: its notice opens
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

CheckQuiet.verify("at the end")
print("model and thinking control checks: \(passed)/\(passed + failed) passed")
exit(failed == 0 ? 0 : 1)
