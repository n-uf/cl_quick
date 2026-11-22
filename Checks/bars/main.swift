// The model and thinking controls' checks, against the operator's complaints about build 103 ("couldn't manage the model
// at all"; the control "changes its size and escapes from the mouse"), without a mouse or any event posting. The real
// panel is opened (read-only: nothing is written under the user's folders) and laid out by SwiftUI, on a model list in
// the shape Claude Code gives it (each family by name alone, the version in its description), with four, three and two
// families; as the bar and as the chat window, at 320, 440 and 640:
//   - the model control has a bar for every family the account has, always shown, and the bars end before Send;
//   - picking every model and every thinking level leaves every control, every bar and Send exactly where they were;
//   - a click on each bar's centre (the action of the bar found at that point) picks that bar's value; a level the
//     model doesn't take does nothing;
//   - a click on a label's right half goes round forward over what the model takes, on its left half back;
//   - the scroll wheel over a control steps it (a notch a step, a trackpad's deltas add up, momentum not), and
//     scrolling elsewhere is left alone;
//   - the keys button opens its list above the row and closes it again, as do a press elsewhere and Esc;
//   - the bar's usage indicator shows the limit closest to full, its label on that window's row (or, in a row too
//     narrow, the bars alone), never moving sideways or changing width, and ending before Send; ⌘W hides.
//   Checks/bars.sh

import AppKit
import SwiftUI

Files.readOnly = true
let app = NSApplication.shared
CheckQuiet.start()          // nothing on any screen, never the keyboard, never active (Checks/quiet.swift)
/// The user's clipboard: this suite never reads or writes it, and the last check says so.
let clipboardAtStart = NSPasteboard.general.changeCount
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
/// Pumps the run loop until `done()` holds, for `ceiling` s at most: a slow runner (a CI virtual Mac, a Mac under load) gets
/// the time its deferred layout passes need, and a condition that never comes ends at the ceiling, where the check that
/// follows fails with its own detail. Returns whether `done()` held. (As in Checks/panel.)
@discardableResult
func spinUntil(_ ceiling: TimeInterval = 20, _ done: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(ceiling)
    while !done(), Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
    CheckQuiet.verify("after a spin")
    return done()
}
/// Pumps the run loop until `window` has made `turns` turns in a row without a resize or a changed frame (its deferred
/// layout passes and fit() tries are over), for `ceiling` s at most. Counted in turns, not in seconds: a pass waiting in the
/// main queue runs in the first turn that comes, however slow the machine. Returns whether it settled. (As in Checks/panel.)
@discardableResult
func spinQuiet(_ window: NSWindow, turns: Int = 15, ceiling: TimeInterval = 20) -> Bool {
    var resizes = 0
    let watch = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: nil) { _ in resizes += 1 }
    defer { NotificationCenter.default.removeObserver(watch) }
    let end = Date().addingTimeInterval(ceiling)
    var quiet = 0, seen = resizes, frame = window.frame
    while quiet < turns, Date() < end {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        if resizes == seen && window.frame == frame { quiet += 1 } else { quiet = 0; seen = resizes; frame = window.frame }
    }
    CheckQuiet.verify("after a spin")
    return quiet >= turns
}
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
    if let k = targets.marks["keys"] { f["keys"] = k }
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
    check("\(name): every control, bar, label half and the keys button is laid out, and no other",
          Set(base.keys).subtracting(["send"]) == Set(keys + halves + ["keys"]), "\(base.keys.sorted())")
    // each label splits in two halves side by side, the left one from the control's edge, the right one up to the bars
    for c in ["m", "t"] {
        let l = base["\(c)<"] ?? .zero, r = base["\(c)>"] ?? .zero, whole = base[c] ?? .zero, first = base["\(c)0"] ?? .zero
        check("\(name): \(c)'s label halves split it", abs(l.minX - whole.minX) < 0.01 && abs(l.maxX - r.minX) < 0.01 && r.maxX <= first.minX + 0.01
              && abs(l.width - r.width) < 0.6 && l.width > 6 && abs(l.height - whole.height) < 0.01 && abs(r.height - whole.height) < 0.01,
              "\(l) \(r) in \(whole), first bar \(first)")
    }
    // from the bar's first width up the profile key keeps its name ("● Main ⌄"), whatever the families
    if p.frame.width >= 440 {
        // the dot alone is 23 pt (7 pt dot, 8 pt padding each side): a name adds at least 20
        check("\(name): the profile key shows its name", (targets.marks["profile"]?.width ?? 0) >= 43, "\(targets.marks["profile"].map { "\($0)" } ?? "-")")
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
    // fn arrows step the model (fn→ up, fn← down) and thinking (fn↑ up, fn↓ down) one at a time among what the list has and the model
    // takes, do nothing at either end, and move nothing. On a Mac they are the Page Up, Page Down, End and Home key codes with the
    // function and numeric-pad flags; the dedicated keys have neither flag and do the same. Sent through the panel's sendEvent,
    // which reads them before the field does. ⌥⌘ arrows and every other modifier combination do nothing of ours.
    let fnFlags: NSEvent.ModifierFlags = [.function, .numericPad]
    func key(_ f: Int, _ code: UInt16, _ flags: NSEvent.ModifierFlags = []) {
        let ch = String(UnicodeScalar(UInt16(f))!)
        guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: p.windowNumber,
                                       context: nil, characters: ch, charactersIgnoringModifiers: ch, isARepeat: false, keyCode: code) else { return }
        p.sendEvent(e)
    }
    let right = (Int(NSEndFunctionKey), UInt16(119)), left = (Int(NSHomeFunctionKey), UInt16(115))
    let up = (Int(NSPageUpFunctionKey), UInt16(116)), down = (Int(NSPageDownFunctionKey), UInt16(121))
    // the arrows themselves (and the arrow codes with ⌥⌘, which are macOS's now)
    let arrowRight = (Int(NSRightArrowFunctionKey), UInt16(124)), arrowLeft = (Int(NSLeftArrowFunctionKey), UInt16(123))
    let arrowUp = (Int(NSUpArrowFunctionKey), UInt16(126)), arrowDown = (Int(NSDownArrowFunctionKey), UInt16(125))
    for (label, extra) in [("fn", fnFlags), ("dedicated", [])] as [(String, NSEvent.ModifierFlags)] {
        m.choose(families[0]); m.choose(QuickChatThinking.off); spin(0.2)
        var seenModels: [QuickChatModelChoice] = [m.resolvedModel.family]
        for _ in families.dropFirst() {
            key(right.0, right.1, extra)
            seenModels.append(m.resolvedModel.family)
        }
        check("\(name): \(label) → steps the model up through every family, in order", seenModels == families, "\(seenModels) vs \(families)")
        key(right.0, right.1, extra)
        check("\(name): \(label) → at the last family changes nothing", m.resolvedModel.family == families.last!, "\(m.resolvedModel.family)")
        key(left.0, left.1, extra)
        check("\(name): \(label) ← steps the model down", m.resolvedModel.family == (families.count > 1 ? families[families.count - 2] : families[0]), "\(m.resolvedModel.family)")
        for _ in families { key(left.0, left.1, extra) }
        check("\(name): \(label) ← at the first family changes nothing", m.resolvedModel.family == families[0], "\(m.resolvedModel.family)")
        check("\(name): \(label) arrows step the model and move nothing", same(frames(), base), moved(base, frames()))
        m.choose(top); m.choose(QuickChatThinking.off); spin(0.2)
        let steps = m.thinkingSteps
        var seenSteps: [QuickChatThinking] = [m.effectiveThinking]
        for _ in steps.dropFirst() {
            key(up.0, up.1, extra)
            seenSteps.append(m.effectiveThinking)
        }
        check("\(name): \(label) ↑ steps thinking up through every step \(top.rawValue) takes, in order", seenSteps == steps, "\(seenSteps) vs \(steps)")
        key(up.0, up.1, extra)
        check("\(name): \(label) ↑ at the last step changes nothing", m.effectiveThinking == steps.last!, "\(m.effectiveThinking)")
        key(down.0, down.1, extra)
        check("\(name): \(label) ↓ steps thinking down", m.effectiveThinking == (steps.count > 1 ? steps[steps.count - 2] : steps[0]), "\(m.effectiveThinking)")
        for _ in steps { key(down.0, down.1, extra) }
        check("\(name): \(label) ↓ at Off changes nothing", m.effectiveThinking == steps[0], "\(m.effectiveThinking)")
        check("\(name): \(label) arrows step thinking and move nothing", same(frames(), base), moved(base, frames()))
    }
    // not ours: ⌥⌘ arrows (macOS's and the field's now), plain ⌘, ⇧⌘, ⌃⌘, ⌃⌥⌘, ⌃, ⌥ and plain arrows; the page keys with ⌘, ⌥, ⌃, ⇧⌥, ⇧⌃ or ⇧⌘
    // (and ⇧End, ⇧Home) step nothing either
    m.choose(families[0]); m.choose(QuickChatThinking.off); spin(0.2)
    let atStart = (m.resolvedModel.family, m.effectiveThinking)
    for f in [NSEvent.ModifierFlags.command, [.command, .option], [.command, .shift], [.command, .control], [.command, .control, .option], [.command, .option, .shift], [.control], [.option], []] {
        for (k, c) in [arrowRight, arrowLeft, arrowUp, arrowDown] { key(k, c, f.union(.function)); key(k, c, f) }
    }
    check("\(name): ⌥⌘ arrows, plain ⌘, ⇧⌘, ⌃⌘, ⌃⌥⌘, ⇧⌥⌘, ⌃, ⌥ and plain arrows step nothing", (m.resolvedModel.family, m.effectiveThinking) == atStart, "\(m.resolvedModel.family) \(m.effectiveThinking)")
    for f in [NSEvent.ModifierFlags.command, .option, .control, [.shift, .option], [.shift, .control], [.shift, .command], [.command, .option]] {
        for (k, c) in [right, left, up, down] { key(k, c, f.union(fnFlags)); key(k, c, f) }
    }
    key(right.0, right.1, [.shift, .function, .numericPad]); key(left.0, left.1, [.shift, .function, .numericPad])
    check("\(name): the page keys with ⌘, ⌥, ⌃, ⇧⌥, ⇧⌃, ⇧⌘ and ⇧End, ⇧Home step nothing", (m.resolvedModel.family, m.effectiveThinking) == atStart, "\(m.resolvedModel.family) \(m.effectiveThinking)")
    // ⇧fn↑ ⇧fn↓ scroll the answers (the panel check's), and never step
    key(up.0, up.1, [.shift, .function, .numericPad]); key(down.0, down.1, [.shift])
    check("\(name): ⇧fn↑ and ⇧fn↓ step neither model nor thinking", (m.resolvedModel.family, m.effectiveThinking) == atStart, "\(m.resolvedModel.family) \(m.effectiveThinking)")
    m.choose(top); m.choose(QuickChatThinking.high); spin(0.3)
    // the window's own hit test, at the real coordinates: a press on any bar or label never starts a move, and the
    // empty gap after the controls does (so the frames are where the window sees them)
    for k in keys + halves + ["keys"] {
        let f = base[k] ?? .zero
        let pts = k.count == 1 ? [CGPoint(x: f.minX + 3, y: f.midY), CGPoint(x: f.midX, y: f.midY)] : [CGPoint(x: f.midX, y: f.midY), CGPoint(x: f.midX, y: f.minY + 2)]
        for q in pts {
            check("\(name): a press at \(k) (\(Int(q.x)), \(Int(q.y))) is not a move", QCDragView.surface(at: inWindow(q), in: p) == nil)
        }
    }
    if let k = base["keys"] {
        // past the outline (1 pt after the keys button) and the row's 2 pt spacing: the spacer, the window's to move
        check("\(name): the gap after the controls moves the window", QCDragView.surface(at: inWindow(CGPoint(x: k.maxX + 3.5, y: k.midY)), in: p) != nil)
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
    // the keys button, at the end of the controls before Send: a click opens the keys list above the row and another
    // closes it; a press elsewhere or Esc closes it too (the panel stays); nothing in the row moves
    let kb = base["keys"] ?? .zero, keysList = QCKeys.shared
    check("\(name): the keys button comes after thinking, before Send", kb != .zero && kb.minX >= (base["t"]?.maxX ?? .infinity) - 0.01
          && kb.maxX <= (base["send"]?.minX ?? 0), "\(kb)")
    let buttonTop = p.convertPoint(toScreen: inWindow(CGPoint(x: kb.midX, y: kb.minY))).y
    keysList.toggle(); spin()
    let list = QCFloat.keys.shownFrame
    check("\(name): a click on the keys button opens the list", keysList.shown && list != nil)
    check("\(name): the list is above the row", (list?.minY ?? 0) >= buttonTop - 0.5, "\(list.map { "\($0)" } ?? "-") vs top \(buttonTop)")
    check("\(name): the list open moves nothing", same(frames(), base), moved(base, frames()))
    // a press goes through the list's mouse-down monitor as an event at the window's point, then (on the button) to
    // the button's tap, which toggles
    func mouseDown(at q: CGPoint, window: Int) -> NSEvent? {
        NSEvent.mouseEvent(with: .leftMouseDown, location: window == p.windowNumber ? inWindow(q) : .zero, modifierFlags: [],
                           timestamp: 0, windowNumber: window, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
    }
    if let e = mouseDown(at: CGPoint(x: kb.midX, y: kb.midY), window: p.windowNumber) { keysList.mouseDown(e) }; spin()
    check("\(name): a press on the button is the button's, not a close", keysList.shown)
    keysList.toggle(); spin()
    check("\(name): another click closes it", !keysList.shown && QCFloat.keys.shownFrame == nil)
    keysList.open(); spin()
    if let e = mouseDown(at: centre("m"), window: p.windowNumber) { keysList.mouseDown(e) }; spin()
    check("\(name): a press elsewhere in the panel closes it", !keysList.shown && QCFloat.keys.shownFrame == nil)
    keysList.open(); spin()
    if let e = mouseDown(at: .zero, window: 0) { keysList.mouseDown(e) }; spin()
    check("\(name): a press outside the panel closes it", !keysList.shown && QCFloat.keys.shownFrame == nil)
    keysList.open(); spin()
    chat.escape(); spin()
    check("\(name): Esc closes the list and leaves the panel", !keysList.shown && QCFloat.keys.shownFrame == nil && p.isVisible)
    check("\(name): the list closed moves nothing", same(frames(), base), moved(base, frames()))
    // the pages: Model & window first, then Move, then Write, turned by clicking the track (← and → are the field's, open or
    // closed); the last page is remembered; the list is as tall and wide on every page
    check("\(name): the keys list's pages are Model & window, Move, Write, in that order, and the first time it shows the first",
          QCKeysPage.allCases.map(\.title) == ["Model & window", "Move", "Write"] && QCKeys().page == .modelWindow)
    let sizes = QCKeysPage.allCases.map { pg -> CGSize in
        QCKeys.shared.page = pg
        return NSHostingView(rootView: AnyView(QCKeysView(opener: "⌃⇧Space"))).fittingSize
    }
    check("\(name): the keys list is the same size on every page", sizes.dropFirst().allSatisfy { $0 == sizes[0] } && sizes[0].height > 0, "\(sizes)")
    QCKeys.shared.page = .modelWindow
    check("\(name): ← and → are not taken while the list is closed (the field's)", !arrow(Int(NSRightArrowFunctionKey), 124, []) && !arrow(Int(NSLeftArrowFunctionKey), 123, []) && keysList.page == .modelWindow)
    keysList.open(); spin()
    let listSize = QCFloat.keys.shownFrame?.size
    // the pages turn by clicking the track only: ← and → stay the field's even while the list is open
    check("\(name): ← and → are not taken while the list is open either (the field keeps its arrows), and turn no page",
          !arrow(Int(NSRightArrowFunctionKey), 124, []) && !arrow(Int(NSLeftArrowFunctionKey), 123, []) && keysList.page == .modelWindow, "\(keysList.page)")
    keysList.page = .write                  // what a click on the track does (the track's binding)
    check("\(name): a click on the track turns the page (the binding)", keysList.page == .write)
    keysList.page = .move; keysList.close(); spin(); keysList.open(); spin()
    check("\(name): the list opens on the page it was left on", keysList.page == .move && QCFloat.keys.shownFrame?.size == listSize, "\(keysList.page) \(String(describing: QCFloat.keys.shownFrame?.size)) vs \(String(describing: listSize))")
    if let e = mouseDown(at: .zero, window: QCFloat.keys.windowNumber) { keysList.mouseDown(e) }; spin()
    check("\(name): a press on the list itself (its track) does not close it", keysList.shown && QCFloat.keys.windowNumber != 0)
    // the pointer over the list: the pointing hand over each tab, the arrow over everything else, and the panel's own I-beam
    // held off while the pointer is on the list and back after (asked of the list's content view; the real pointer isn't moved)
    if let host = QCFloat.keys.contentHost {
        host.layoutSubtreeIfNeeded()
        func hands(_ v: NSView) -> [CGRect] { v.subviews.flatMap { s in (s is QCCursorView ? [s.convert(s.bounds, to: host)] : []) + hands(s) } }
        let tabs = hands(host).sorted { $0.minX < $1.minX }
        check("\(name): the keys list has a pointing-hand zone on each of its three tabs, side by side", tabs.count == 3 && tabs.allSatisfy { $0.height > 10 && $0.width > 30 }
              && zip(tabs, tabs.dropFirst()).allSatisfy { $0.maxX <= $1.minX + 0.5 } && (tabs.map(\.width).max() ?? 0) - (tabs.map(\.width).min() ?? 0) <= 1, "\(tabs)")
        check("\(name): the pointer over each tab is the pointing hand", tabs.count == 3 && tabs.allSatisfy { host.cursor(at: CGPoint(x: $0.midX, y: $0.midY)) === NSCursor.pointingHand }, "\(tabs)")
        let below = CGPoint(x: host.bounds.midX, y: (tabs.first?.maxY ?? 0) + 30)
        check("\(name): over the rows, the margin and the track's edge it is the arrow",
              host.cursor(at: below) === NSCursor.arrow && host.cursor(at: CGPoint(x: 2, y: host.bounds.midY)) === NSCursor.arrow
              && host.cursor(at: CGPoint(x: tabs.first?.midX ?? 0, y: (tabs.first?.minY ?? 0) - 6)) === NSCursor.arrow, "\(below)")
        // the float's own area (found by its options: the hosting view has one of its own, with the same owner, that SwiftUI's hover uses)
        let want = QCFloatHost.trackingOptions
        let areas = host.trackingAreas.filter { $0.options.isSuperset(of: want) }
        check("\(name): the list tracks the pointer whoever is key (cursor updates and moves, active always, its visible rect), beside the hosting view's own area",
              areas.count == 1 && areas.first === host.pointerArea && host.trackingAreas.count >= 2 && host.window?.acceptsMouseMovedEvents == true,
              "areas \(host.trackingAreas.map(\.options.rawValue)) want \(want.rawValue), moves \(String(describing: host.window?.acceptsMouseMovedEvents))")
        // the handlers, with synthetic events: the cursor each puts on (recorded, never set on the real pointer), and the hold
        var put: [NSCursor] = []
        host.apply = { put.append($0) }
        func at(_ pt: CGPoint) -> CGPoint { host.convert(pt, to: nil) }
        let wn = host.window?.windowNumber ?? 0
        func moveEvent(_ pt: CGPoint) -> NSEvent? { NSEvent.mouseEvent(with: .mouseMoved, location: at(pt), modifierFlags: [], timestamp: 0, windowNumber: wn, context: nil, eventNumber: 0, clickCount: 0, pressure: 0) }
        func crossed(_ t: NSEvent.EventType, _ pt: CGPoint) -> NSEvent? { NSEvent.enterExitEvent(with: t, location: at(pt), modifierFlags: [], timestamp: 0, windowNumber: wn, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil) }
        let tabPoint = CGPoint(x: tabs.first?.midX ?? 0, y: tabs.first?.midY ?? 0)
        if let e = crossed(.mouseEntered, tabPoint) { host.mouseEntered(with: e) }
        check("\(name): the pointer entering on a tab: the hand, and the panel's cursor rectangles are off", put.last === NSCursor.pointingHand && host.holdingPanel && !p.areCursorRectsEnabled)
        if let e = moveEvent(below) { host.mouseMoved(with: e) }
        check("\(name): moving on to the rows: the arrow", put.last === NSCursor.arrow)
        if let e = moveEvent(tabPoint) { host.mouseMoved(with: e) }
        check("\(name): moving back over a tab: the hand", put.last === NSCursor.pointingHand)
        if let e = NSEvent.enterExitEvent(with: .cursorUpdate, location: at(below), modifierFlags: [], timestamp: 0, windowNumber: wn, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil) { host.cursorUpdate(with: e) }
        check("\(name): a cursor update over the rows: the arrow", put.last === NSCursor.arrow, "\(put.count)")
        if let e = crossed(.mouseExited, below) { host.mouseExited(with: e) }
        check("\(name): the pointer leaving the list: the panel's cursor rectangles are back on", !host.holdingPanel && p.areCursorRectsEnabled)
        host.apply = { $0.set() }
        check("\(name): the panel's cursor rectangles are on before the pointer reaches the list", p.areCursorRectsEnabled && !host.holdingPanel)
        host.holdPanel()
        check("\(name): with the pointer on the list the panel's cursor rectangles (its I-beam) are off", !p.areCursorRectsEnabled && host.holdingPanel)
        host.releasePanel()
        check("\(name): when the pointer leaves the list they are back on", p.areCursorRectsEnabled && !host.holdingPanel)
        host.holdPanel(); keysList.close(); spin()
        check("\(name): and when the list closes under the pointer (no mouse-exit comes) they are back on too", p.areCursorRectsEnabled && !host.holdingPanel)
    } else { check("\(name): the keys list has a content view", false) }
    keysList.close(); keysList.page = .modelWindow; spin()
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
    ModelCatalog.shared.set(list, profile: t.profileID, account: t.account?.text)
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
// it says; the profile's dot in the same colour. With all four families, the widest row.
ModelCatalog.shared.set(fullList, profile: t.profileID, account: t.account?.text)
m.turns = []
m.choose(QuickChatModelChoice.fable); m.choose(QuickChatThinking.max)
spin(0.6)
for w in [CGFloat(320), 440, 640] {
    width(w)
    var first: (ui: CGRect, five: CGRect, week: CGRect)?
    var barHeight: CGFloat?         // the panel's height with no notice above the field (the first state's)
    for (five, week) in [(78.0, 20.0), (30.0, 85.0), (9.0, 9.5), (100.0, 64.0), (0.0, 100.0), (55.0, 54.9)] {
        var l = QuickChatLevel(); l.fiveHour = five; l.fiveHourResets = Date().addingTimeInterval(7200); l.week = week
        // a full limit opens its notice above the field and the panel grows with it (the row 71 pt lower); a limit with room
        // takes it away again and the panel shrinks back, in fit() on a later turn of the run loop: what is measured is the
        // layout of the level set, once the window has stopped changing
        l.weekResets = Date().addingTimeInterval(3 * 86400); m.level = l; spin(); spinQuiet(p)
        if first == nil { barHeight = p.frame.height }
        let higher = l.binding()?.id ?? "-"
        let ui = targets.marks["usage"] ?? .zero, label = targets.marks["usage-label"] ?? .zero, share = targets.marks["usage-share"] ?? .zero
        let row = targets.marks["usage-\(higher)"] ?? .zero
        let rows = (five: targets.marks["usage-5h"] ?? .zero, week: targets.marks["usage-wk"] ?? .zero)
        let name = "usage at \(Int(w)), 5h \(five) wk \(week)"
        // short of room the share goes first (the label stays), a narrow row keeps the two bars alone (both on hover)
        let says: QCUsageView.Says? = [.all, .label, .bars].first { abs(ui.width - QCUsageView.width($0)) < 0.5 }
        check("\(name): shown", ui != .zero && says != nil, "\(ui)")
        // from the bar's first width up, the profile keeps its name ("● Main ⌄"); what gives way there is the share
        if w >= 440 {
            let profile = targets.marks["profile"] ?? .zero
            check("\(name): the profile key shows its name", profile.width >= 43, "\(profile)")
            check("\(name): with room, its label is shown", says == .all || says == .label, "\(ui)")
        }
        if w >= 640 { check("\(name): with more room, its share too", says == .all, "\(ui)") }
        check("\(name): \(higher) is the higher one", higher == (five >= week || l.full()?.id == "5h" ? "5h" : "wk") || (l.full()?.id == "wk" && higher == "wk"))
        if says != .bars {
            // the label, then the bars, then the share, the label and share on the higher window's row
            check("\(name): its label sits on the \(higher) row", label != .zero && abs(label.midY - row.midY) <= 1.5, "\(label.midY) vs \(row.midY)")
            check("\(name): the label comes before the bars", label.maxX <= row.minX + 0.01, "label \(label), bar \(row)")
        }
        if says == .all {
            check("\(name): its share sits on the \(higher) row", share != .zero && abs(share.midY - row.midY) <= 1.5, "\(share.midY) vs \(row.midY)")
            check("\(name): the share comes after the bars", share.minX >= row.maxX - 0.01, "bar \(row), share \(share)")
        } else {
            check("\(name): no share drawn", targets.marks["usage-share"] == nil)
        }
        // exactly two tracks, one tight pair (5h on top, 3 pt apart), centred on the row
        check("\(name): two tracks, 5h over wk, 3 pt apart, as wide", abs(rows.week.minY - rows.five.maxY - QCUsageView.trackGap) < 0.5
              && abs(rows.five.width - QCUsageView.bar) < 0.5 && abs(rows.week.width - QCUsageView.bar) < 0.5 && abs(rows.five.minX - rows.week.minX) < 0.5,
              "\(rows)")
        check("\(name): the pair is centred on the indicator", abs((rows.five.minY + rows.week.maxY) / 2 - ui.midY) < 0.5, "\(rows) in \(ui)")
        if let s = targets.marks["send"], let mic = targets.marks["mic"] {
            check("\(name): it ends before the mic, the mic before Send", ui.maxX <= mic.minX && mic.maxX <= s.minX, "\(ui) / \(mic) / \(s)")
        } else { check("\(name): the mic and Send are drawn", false) }
        // across the row: a full limit opens its notice above the field and the whole row moves down with the field
        if let f = first {
            check("\(name): the indicator never moves sideways or changes width", ui.minX == f.ui.minX && ui.width == f.ui.width, "\(ui) vs \(f.ui)")
            check("\(name): its bars never move sideways", rows.five.minX == f.five.minX && rows.week.minX == f.week.minX && rows.five.width == f.five.width,
                  "\(rows) vs \(f)")
        } else { first = (ui, rows.five, rows.week) }
    }
    // no 5-hour number yet: its track is an outline in the very same place (not a bar of its own elsewhere), and the
    // week's label sits on the week's track
    var l = QuickChatLevel(); l.week = 21; l.weekResets = Date().addingTimeInterval(3 * 86400); m.level = l; spin()
    // the state before this one was a full week (a notice above the field, the panel 71 pt taller): wait for the notice to go
    // and the panel to be back at the bar's own height, then for the window to stop changing, before the tracks are read
    spinUntil { abs(p.frame.height - (barHeight ?? p.frame.height)) < 0.5 }
    spinQuiet(p)
    let five = targets.marks["usage-5h"] ?? .zero, wk = targets.marks["usage-wk"] ?? .zero, ui = targets.marks["usage"] ?? .zero
    if let f = first {
        // a week and no 5-hour number: the account has no 5-hour window (hasFiveHour), so the week's track stands alone, centred
        check("usage at \(Int(w)), no 5h window: the week's track alone, centred on the row, the row where it always is", five == .zero && wk != .zero
              && abs(wk.midY - ui.midY) < 0.5 && ui.minX == f.ui.minX,
              "\(five) \(wk) vs \(f) (panel \(p.frame.height) pt, the bar's \(barHeight.map { "\($0)" } ?? "-"))")
    }
    if abs(ui.width - QCUsageView.width(.bars)) > 0.5 {
        let label = targets.marks["usage-label"]
        check("usage at \(Int(w)), no 5h number: the label sits on the week's track", label.map { abs($0.midY - wk.midY) <= 1.5 } == true,
              "\(label.map { "\($0)" } ?? "none") vs \(wk)")
    }
}

// (still four families with Fable and Max from the usage loop: the widest row, the hardest to fit)
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
        check("narrow row at \(Int(w)): the usage indicator is shown",
              ui != .zero && [.all, .label, .bars].contains { abs(ui.width - QCUsageView.width($0)) < 0.5 }, "\(ui)")
        if abs(ui.width - QCUsageView.width(.bars)) < 0.5 {
            barsAt = w
            let t = targets.controls["t"]?.frame ?? .zero, s = targets.marks["send"] ?? .zero, mic = targets.marks["mic"] ?? .zero
            check("narrow row at \(Int(w)): the bars, the usage bars, the mic, then Send, none over another",
                  t.maxX <= ui.minX && ui.maxX <= mic.minX && mic != .zero && mic.maxX <= s.minX, "thinking \(t), usage \(ui), mic \(mic), send \(s)")
            check("narrow row at \(Int(w)): the labels are letters", mw > 0 && mw < (wide ?? 0), "\(mw) vs \(wide ?? 0)")
            break
        }
    }
    check("a narrow enough row keeps the usage bars alone", barsAt != nil)
    check("with the bars alone the card gives both shares, else the one the row lacks",
          QCUsageCard.leftOut(l, rowShowsShare: false) == nil && QCUsageCard.leftOut(l, rowShowsShare: true) == "5h")
    probe.removeFromSuperview(); spin()
    // the probe took the row's names: the panel's own row lays out again and has them back
    width(440); width(320)
    check("after the narrow row, the panel's row is back", targets.controls["m"] != nil && targets.controls["t"] != nil
          && targets.marks["send"] != nil && targets.marks["keys"] != nil && targets.halves["m>"] != nil)
}

// ⌘W hides at once
if let w = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: p.windowNumber,
                            context: nil, characters: "w", charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13) {
    check("⌘W is taken", p.performKeyEquivalent(with: w))
    spin()
    check("⌘W hides the panel", !p.isVisible)
} else { check("a ⌘W event can be made", false) }

CheckQuiet.verify("at the end")
// strict on CI (GitHub Actions sets CI; nobody copies there); on a Mac the user or another session may copy meanwhile, so
// a changed count is only a NOTE
let clipboardCounts = "change count \(clipboardAtStart) → \(NSPasteboard.general.changeCount)"
let clipboardSame = NSPasteboard.general.changeCount == clipboardAtStart, onCI = ProcessInfo.processInfo.environment["CI"] != nil
if !clipboardSame && !onCI { print("NOTE clipboard: the general pasteboard changed during the run (\(clipboardCounts)); this suite never writes it, so someone else did") }
check("clipboard: the whole suite left the general pasteboard as it was", clipboardSame || !onCI, clipboardCounts)
print("model and thinking control checks: \(passed)/\(passed + failed) passed")
exit(failed == 0 ? 0 : 1)
