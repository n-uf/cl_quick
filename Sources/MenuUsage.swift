// MenuUsage: the menu bar item's menu, with each profile's usage drawn as cl_audit's menu draws it: the profile's name
// and a dot in the colour of its fuller limit, the account in use with a green lamp (its address blurred until the
// pointer is on it, as in the profile menu: MenuRow.swift), two bars ("5-hour", "Week") with their share and the time
// to the reset, and how old the numbers are. Only the account in use shows usage; a standby account shows none.
//
// The numbers are the ones cl_quick already keeps (levels.json, from Claude Code's `get_usage`); the menu shows them at
// once when it opens: fresh ones in their colours (a full limit as a crimson note), ones over a few minutes old grey as
// "Last known …", ones over an hour old not at all. One exception: a saved full limit (Week or 5-hour at 100%, or a
// refusal) whose reset is still ahead stays, grey, until that reset, however old: "Week full · last known" in the
// header, its row at 100% with "back …" and "Last known 3 h ago" under the bars; when over an hour old the other
// window's row is "–" (its number is old and nothing bounds it, while a reset still ahead is what says the full one
// still stands). A refusal that names no window puts its end in the note. No dot colour; the block has the shape of a
// fresh one, so a fresh answer replaces it live while the menu is open. It is
// only the menu's: the chat, "Ask on …" and the switch offers never act on a number that isn't fresh (ProfileStore.shownLevel),
// and a fresh answer replaces it at once. When they are older than a few minutes, QCMenuUsageRefresher asks Claude Code again in the
// background: a short-lived `claude` per profile, one at a time, that is sent `get_usage` and nothing else (no message
// to a model), and ends as soon as it has answered. Nothing is read from the Keychain; no token is ever seen.

import AppKit
import Combine

// MARK: - What a profile's block says

/// "in 1h 5m", "back at 15:28": the words for a reset, as cl_audit says them.
extension TimeWords {
    /// Whole minutes left, rounded up (30 s left is "1m"; the reset itself is 0).
    static func minutesLeft(_ d: Date, now: Date = Date()) -> Int { max(0, Int((d.timeIntervalSince(now) / 60).rounded(.up))) }

    /// "19m", "1h 42m", "19h 14m", "2d 19h", "16 days": its form changes as the reset gets closer.
    static func countdown(_ d: Date, now: Date = Date()) -> String {
        let m = minutesLeft(d, now: now)
        if m < 60 { return "\(m)m" }
        if m < 24 * 60 { return "\(m / 60)h \(m % 60)m" }
        if m < 8 * 24 * 60 { return "\(m / 1440)d \(m % 1440 / 60)h" }
        return "\(m / 1440) days"
    }

    /// When a full limit is back: "back at 15:28" today, else "back Thu 09:00", "back 11 Nov".
    static func back(_ d: Date, now: Date = Date()) -> String {
        Calendar.current.isDate(d, inSameDayAs: now) ? "back at \(when(d, now: now))" : "back \(when(d, now: now))"
    }
}

/// One profile's block in the menu, as words and numbers (the view draws it; the checks read it).
struct QCMenuProfile: Equatable {
    enum Account: Equatable {
        /// The account in use, by its address (drawn blurred until the pointer is on it).
        case inUse(address: String)
        /// No account is signed in to the folder, or its sign-in stopped working: the line says so, no lamp, no usage.
        case problem(words: String)
    }

    struct Row: Equatable {
        /// "5h" or "wk".
        let id: String
        /// "5-hour" or "Week".
        let label: String
        /// The share used, 0…100; nil: not known now.
        let p: Double?
        /// "13%", "100%", "–".
        let share: String
        /// "in 1h 5m", "back at 15:28", or "".
        let resets: String
        /// Last known, not now (older than QuickChatLevel.freshFor): drawn grey.
        var stale = false
        /// The level's colour (cl_audit's: green, amber from 50%, red from 80%, crimson from 95%); grey when stale.
        var colour: NSColor { Painter.color(p, stale: stale) }
        var text: String { [label, share, resets].filter { !$0.isEmpty }.joined(separator: " ") }
    }

    let id: String
    /// "Claude Main".
    let title: String
    /// The share the profile's dot shows (the fuller window); nil: grey, no numbers.
    let dotP: Double?
    /// "5-hour full · in 1h 5m", in crimson at the header's right, while a limit holds the account back; for numbers
    /// no longer fresh "Week full · last known 3 h ago", grey (`fullNoteStale`).
    let fullNote: String?
    let account: Account
    /// The two windows; empty with no numbers.
    let rows: [Row]
    /// The account in use has no numbers yet, or none recent: one muted line instead of the bars.
    let noUsage: Bool
    /// "Updated just now", "Updated 3 min ago"; "Last known 12 min ago" for numbers no longer fresh.
    let updated: String?
    /// The muted line when `noUsage`: "No usage yet", or "No recent numbers" when the last ones are over an hour old.
    var noUsageText = Self.noUsageWords
    /// `fullNote` is a saved full limit, last known and not now: drawn grey, not crimson.
    var fullNoteStale = false

    static let noUsageWords = "No usage yet"
    static let noRecentWords = "No recent numbers"
    /// Numbers older than this aren't shown at all, not even muted: the plan, the account or the week may have changed
    /// since (the refresh asks for new ones as the menu opens). Except a full limit whose reset is still ahead.
    static let lastKnownFor: TimeInterval = 3600

    /// "Claude Main"; a name that starts with Claude as it is.
    static func title(_ name: String) -> String { name.lowercased().hasPrefix("claude") ? name : "Claude " + name }

    /// The address as words everywhere but the drawn, blurred line: masked (never a full address unhovered).
    var accountWords: String {
        switch account {
        case .inUse(let a): return maskEmail(a) + " · in use"
        case .problem(let w): return w
        }
    }

    /// Every line the block shows, top to bottom, with the address masked.
    var lines: [String] {
        var l = [title + (fullNote.map { "  " + $0 } ?? ""), accountWords]
        if noUsage { l.append(noUsageText) }
        l += rows.map(\.text)
        if let updated { l.append(updated) }
        return l
    }

    /// The same words for VoiceOver.
    var spoken: String { lines.joined(separator: ". ") }

    /// What sets the block's height (see QCMenuUsageBlock.height): a live update that changes it waits for the next time
    /// the menu opens. The header note doesn't (but its width does: QCMenuUsageBlock.reload).
    var shape: [Int] { [rows.count, noUsage ? 1 : 0, updated == nil ? 0 : 1] }

    /// The block for a profile: `address` is the account in use (nil: signed out), `problem` what is wrong with its sign-in,
    /// `level` its numbers as last reported (nil: none yet).
    static func make(profile p: Profile, level: QuickChatLevel?, address: String?, problem: SignInProblem?, now: Date = Date()) -> QCMenuProfile {
        guard let address, problem != .signedOut else {
            return QCMenuProfile(id: p.id, title: title(p.name), dotP: nil, fullNote: nil, account: .problem(words: SignInProblem.signedOut.words),
                                 rows: [], noUsage: false, updated: nil)
        }
        if let problem {
            return QCMenuProfile(id: p.id, title: title(p.name), dotP: nil, fullNote: nil, account: .problem(words: problem.words),
                                 rows: [], noUsage: false, updated: nil)
        }
        // how old the numbers are: fresh ones are the account now; ones over a few minutes old are what Claude Code said
        // last, drawn grey (the refresh asks again as the menu opens); over an hour old, not shown, except a saved full
        // limit whose reset is still ahead: that stays, grey and worded "last known", until the reset
        let age = level?.at.map { now.timeIntervalSince($0) } ?? .infinity
        let fresh = level?.isFresh(now) == true
        let old = level != nil && age >= lastKnownFor
        let savedFull: FullLimit? = fresh ? nil : level?.full(now, dated: true)
        let shownLevel = old && savedFull == nil ? nil : level
        let full = fresh ? shownLevel?.full(now) : savedFull
        func row(_ id: String, _ label: String, _ p: Double?, _ resets: Date?) -> Row {
            let isFull = full?.id == id
            let shown = isFull ? 100 : p
            let at = isFull ? full?.resets : resets
            var words = ""
            if let shown, let at { words = shown.rounded() >= 100 ? TimeWords.back(at, now: now) : "in " + TimeWords.countdown(at, now: now) }
            return Row(id: id, label: label, p: shown, share: QuickChatLevel.pct(shown), resets: words, stale: !fresh)
        }
        var rows: [Row] = []
        if let level = shownLevel {
            rows = [row("5h", "5-hour", level.fiveHourNow(now), level.fiveHourResets), row("wk", "Week", level.weekNow(now), level.weekResets)]
            // an old saved full limit keeps both rows (so the block has the shape of a fresh one and a fresh answer
            // replaces it live), but the other window's number, over an hour old, is not shown: "–"
            if old { rows = rows.map { $0.id == full?.id ? $0 : Row(id: $0.id, label: $0.label, p: nil, share: QuickChatLevel.pct(nil), resets: "", stale: true) } }
            // two "–" rows stay for a saved full that names no window, so it keeps a fresh block's shape too
            if savedFull == nil, rows.allSatisfy({ $0.p == nil }) { rows = [] }
        }
        let agoWords = shownLevel?.at.map { AccountBook.ago($0, now: now) }
        let name = full.map { $0.id == "5h" ? "5-hour" : $0.id == "wk" ? "Week" : "Limit" }
        // fresh: "Week full · in 2d 3h", crimson. Saved: "Week full · last known", grey, with the age on the line under
        // the bars as for any last known number; a refusal that names no window has no row to carry its end, so its
        // note does: "Limit full · back at 15:28 · last known"
        let note: String? = full.flatMap { f in
            fresh ? name.map { $0 + " full" + (f.resets.map { " · in " + TimeWords.countdown($0, now: now) } ?? "") }
                  : name.map { $0 + " full" + (f.id == FullLimit.any ? f.resets.map { " · " + TimeWords.back($0, now: now) } ?? "" : "") + " · last known" }
        }
        let updated: String? = rows.isEmpty ? nil : agoWords.map { (fresh ? "Updated " : "Last known ") + $0 }
        let noUsageText = old ? noRecentWords : noUsageWords
        return QCMenuProfile(id: p.id, title: title(p.name), dotP: fresh ? shownLevel?.binding(now)?.p : nil, fullNote: note,
                             account: .inUse(address: address), rows: rows, noUsage: rows.isEmpty, updated: updated,
                             noUsageText: noUsageText, fullNoteStale: !fresh && note != nil)
    }
}

// MARK: - The view

/// A profile's block in the menu: drawn by hand (like the profile menu's row, QCProfileMenuRow), so the address can be
/// blurred until the pointer is on it. A click anywhere opens the quick chat on that profile (what the profile's line in
/// this menu always did). While the menu is open the numbers follow the store (a refresh that finishes), when that
/// doesn't change the block's height.
final class QCMenuUsageBlock: NSView {
    private(set) var model: QCMenuProfile
    /// Reads the block again (the store's numbers now); nil: it never changes.
    var provider: (() -> QCMenuProfile)?
    let pick: () -> Void
    /// The pointer is on the address: it is drawn readable.
    private(set) var revealed = false
    private var watch: AnyCancellable?

    static let padX: CGFloat = 14, top: CGFloat = 7, bottom: CGFloat = 8
    static let headH: CGFloat = 18, accountH: CGFloat = 17, rowH: CGFloat = 16, rowGap: CGFloat = 3, noteH: CGFloat = 15
    static let dotSize: CGFloat = 7, textGap: CGFloat = 13
    static let labelW: CGFloat = 46, barW: CGFloat = 110, barH: CGFloat = 5, shareW: CGFloat = 36, colGap: CGFloat = 8
    static let titleFont = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
    static let noteFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    static let accountFont = NSFont.systemFont(ofSize: 11)
    static let rowFont = NSFont.systemFont(ofSize: 11)
    static let shareFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
    static let resetFont = NSFont.systemFont(ofSize: 10.5)
    static let minWidth: CGFloat = 300

    init(_ model: QCMenuProfile, pick: @escaping () -> Void) {
        self.model = model; self.pick = pick
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width(model), height: Self.height(model)))
        autoresizingMask = [.width]
        toolTip = "Open the quick chat on \(model.title.replacingOccurrences(of: "Claude ", with: ""))"
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel(model.spoken)
    }
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    override var isFlipped: Bool { true }

    // MARK: size

    private static func w(_ s: String, _ f: NSFont) -> CGFloat { ceil((s as NSString).size(withAttributes: [.font: f]).width) }

    /// The least width that shows it all (nothing is cut): the widest of the header, the account line, the rows, the note.
    static func width(_ m: QCMenuProfile) -> CGFloat {
        let head = padX + textGap + w(m.title, titleFont) + (m.fullNote.map { 16 + w($0, noteFont) } ?? 0) + padX
        let account: CGFloat
        switch m.account {
        case .inUse(let a): account = padX + textGap + w(a, QCProfileMenuRow.addressFont) + w(" · in use", accountFont) + padX
        case .problem(let words): account = padX + textGap + w(words, accountFont) + padX
        }
        let reset = m.rows.map { w($0.resets, resetFont) }.max() ?? 0
        let rows = m.rows.isEmpty ? 0 : padX + labelW + colGap + barW + colGap + shareW + colGap + max(reset, 64) + padX
        let note = max(m.updated.map { padX + w($0, resetFont) + padX } ?? 0, m.noUsage ? padX + w(m.noUsageText, accountFont) + padX : 0)
        return max(minWidth, head, account, rows, note)
    }

    static func height(_ m: QCMenuProfile) -> CGFloat {
        var h = top + headH + accountH
        if m.noUsage { h += rowGap + rowH }
        if !m.rows.isEmpty { h += 4 + CGFloat(m.rows.count) * rowH + CGFloat(m.rows.count - 1) * rowGap }
        if m.updated != nil { h += 3 + noteH }
        return h + bottom
    }

    // MARK: where things are

    private var accountY: CGFloat { Self.top + Self.headH }
    private func rowY(_ i: Int) -> CGFloat { accountY + Self.accountH + 4 + CGFloat(i) * (Self.rowH + Self.rowGap) }
    private var addressWidth: CGFloat {
        if case .inUse(let a) = model.account { return Self.w(a, QCProfileMenuRow.addressFont) }
        return 0
    }
    /// Where the address is drawn: after the lamp, on the account line.
    var addressRect: NSRect {
        NSRect(x: Self.padX + Self.textGap, y: accountY, width: addressWidth, height: Self.accountH)
    }

    // MARK: the pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with e: NSEvent) { hover(at: convert(e.locationInWindow, from: nil)) }
    override func mouseMoved(with e: NSEvent) { hover(at: convert(e.locationInWindow, from: nil)) }
    override func mouseExited(with e: NSEvent) { hover(at: nil) }

    /// The pointer at a point of the block (nil: it left): only on the address (with a 3 pt margin) is it readable.
    func hover(at p: NSPoint?) {
        let r = addressWidth > 0 && p.map { addressRect.insetBy(dx: -3, dy: -3).contains($0) } == true
        guard r != revealed else { return }
        revealed = r
        needsDisplay = true
    }

    override func mouseUp(with e: NSEvent) { press() }

    /// A click: the menu closes and the quick chat opens on the profile.
    func press() {
        enclosingMenuItem?.menu?.cancelTracking()
        let pick = self.pick
        DispatchQueue.main.async { pick() }      // once the menu has closed, not inside its tracking loop
    }

    override func accessibilityPerformPress() -> Bool { press(); return true }

    // MARK: live numbers

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, let provider else { watch = nil; return }
        // the store says it will change before it has: read it once it has
        watch = ProfileStore.shared.$levels.sink { [weak self] _ in
            DispatchQueue.main.async { guard let self else { return }; self.reload(provider()) }
        }
    }

    /// New numbers for the block, in place: only when its height stays (a menu doesn't take a row that changes size)
    /// and it still fits the width the menu gave it (a header note that grew would be cut).
    func reload(_ m: QCMenuProfile) {
        guard m != model, m.shape == model.shape, Self.width(m) <= frame.width else { return }
        model = m
        setAccessibilityLabel(m.spoken)
        needsDisplay = true
    }

    // MARK: drawing

    private func text(_ s: String, _ font: NSFont, _ color: NSColor, x: CGFloat, midY: CGFloat) {
        let size = (s as NSString).size(withAttributes: [.font: font])
        (s as NSString).draw(at: NSPoint(x: x, y: midY - size.height / 2), withAttributes: [.font: font, .foregroundColor: color])
    }
    private func textRight(_ s: String, _ font: NSFont, _ color: NSColor, right: CGFloat, midY: CGFloat) {
        text(s, font, color, x: right - Self.w(s, font), midY: midY)
    }

    private func lamp(_ color: NSColor, glow: Bool, midY: CGFloat) {
        let r = NSRect(x: Self.padX, y: midY - Self.dotSize / 2, width: Self.dotSize, height: Self.dotSize)
        NSGraphicsContext.saveGraphicsState()
        if glow {
            let s = NSShadow()
            s.shadowColor = color.withAlphaComponent(0.7); s.shadowBlurRadius = 3; s.shadowOffset = .zero
            s.set()
        }
        color.setFill()
        NSBezierPath(ovalIn: r).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// A limit's bar: a faint track and the share in its level's colour, fading in from 70% at its left end (crimson whole).
    private func bar(_ r: NSRect, p: Double?, stale: Bool) {
        NSColor.labelColor.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2).fill()
        guard let p, p > 0 else { return }
        let c = Painter.color(p, stale: stale)
        let w = max(r.height, r.width * CGFloat(min(100, p)) / 100)
        let fill = NSBezierPath(roundedRect: NSRect(x: r.minX, y: r.minY, width: w, height: r.height), xRadius: r.height / 2, yRadius: r.height / 2)
        NSGradient(starting: c.withAlphaComponent(c == Painter.crimson ? 1 : 0.7), ending: c)?.draw(in: fill, angle: 0)
    }

    override func draw(_ dirty: NSRect) {
        let m = model
        let x0 = Self.padX
        // the header: the profile's dot (the colour of its fuller limit), its name, and a full limit at the right
        let headMid = Self.top + Self.headH / 2
        lamp(Painter.color(m.dotP, stale: false), glow: false, midY: headMid)
        text(m.title, Self.titleFont, .labelColor, x: x0 + Self.textGap, midY: headMid)
        if let note = m.fullNote { textRight(note, Self.noteFont, m.fullNoteStale ? Painter.grey : Painter.crimson, right: bounds.width - Self.padX, midY: headMid) }
        // the account in use: a green lamp, the address (blurred until the pointer is on it), "· in use"
        let accMid = accountY + Self.accountH / 2
        switch m.account {
        case .inUse(let address):
            lamp(.systemGreen, glow: true, midY: accMid)
            let a = addressRect
            if revealed {
                text(address, QCProfileMenuRow.addressFont, .secondaryLabelColor, x: a.minX, midY: accMid)
            } else if let img = blurred(address) {
                img.draw(in: NSRect(x: a.minX - QCProfileMenuRow.blurPad, y: a.midY - img.size.height / 2, width: img.size.width, height: img.size.height))
            }
            text(" · in use", Self.accountFont, .secondaryLabelColor, x: a.maxX, midY: accMid)
        case .problem(let words):
            lamp(.tertiaryLabelColor, glow: false, midY: accMid)
            text(words, Self.accountFont, .secondaryLabelColor, x: x0 + Self.textGap, midY: accMid)
        }
        if m.noUsage {
            text(m.noUsageText, Self.accountFont, .tertiaryLabelColor, x: x0, midY: accountY + Self.accountH + Self.rowGap + Self.rowH / 2)
        }
        // the two bars: name, bar, share (in its level's colour), time to the reset
        for (i, r) in m.rows.enumerated() {
            let y = rowY(i), mid = y + Self.rowH / 2
            text(r.label, Self.rowFont, .labelColor, x: x0, midY: mid)
            let bx = x0 + Self.labelW + Self.colGap
            bar(NSRect(x: bx, y: mid - Self.barH / 2, width: Self.barW, height: Self.barH), p: r.p, stale: r.stale)
            let sx = bx + Self.barW + Self.colGap
            textRight(r.share, Self.shareFont, r.p == nil ? .secondaryLabelColor : r.colour, right: sx + Self.shareW, midY: mid)
            text(r.resets, Self.resetFont, .secondaryLabelColor, x: sx + Self.shareW + Self.colGap, midY: mid)
        }
        if let updated = m.updated {
            let y = rowY(max(0, m.rows.count - 1)) + Self.rowH + 3
            text(updated, Self.resetFont, .tertiaryLabelColor, x: x0, midY: y + Self.noteH / 2)
        }
    }

    /// The blurred address, made once for each appearance (its colour is the system's).
    private var blurCache: NSImage?
    private func blurred(_ address: String) -> NSImage? {
        if let blurCache { return blurCache }
        blurCache = QCProfileMenuRow.blurred(address, color: .secondaryLabelColor)
        return blurCache
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        blurCache = nil
        needsDisplay = true
    }
}

// MARK: - The menu's items

enum QCStatusMenu {
    /// What the menu reads about one profile.
    struct Info {
        let profile: Profile
        let level: QuickChatLevel?
        /// The address of the account in use; nil: nothing is signed in.
        let address: String?
        let problem: SignInProblem?
        /// The accounts signed in before and not in use now, the most recently seen first.
        let standby: [KnownAccount]
    }

    /// Every profile as the store has it now: the account in use and its numbers (a standby account's never).
    static func infos(_ store: ProfileStore = .shared) -> [Info] {
        store.profiles.map { info($0, store) }
    }
    static func info(_ p: Profile, _ store: ProfileStore = .shared) -> Info {
        Info(profile: p, level: store.level(of: p), address: ClaudeFolder.account(p.path)?.email, problem: store.signInProblem(p),
             standby: store.standby(p))
    }

    /// A menu item's action: a closure.
    private final class Handler: NSObject {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
        @objc func fire() { run() }
    }

    /// "Switch account ›" for a profile with standby accounts: each one a line, by its masked address, that asks the
    /// switch question (AccountSwitcher.confirmAndSwitch: what it moves, then Claude Code's sign-in in Terminal). Nothing
    /// new happens here: it is the path the chat's and Settings' Switch… take. Lines are off while a sign-in for the
    /// profile is waited for.
    static func switchItem(_ i: Info, waiting: Bool, switchTo: @escaping (Profile, KnownAccount) -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: "Switch account", action: nil, keyEquivalent: "")
        let sub = NSMenu(title: "Switch account")
        sub.autoenablesItems = false
        for a in i.standby {
            let h = Handler { switchTo(i.profile, a) }
            let line = NSMenuItem(title: "Switch to \(maskEmail(a.email))…", action: #selector(Handler.fire), keyEquivalent: "")
            line.target = h
            line.representedObject = h          // the menu item keeps its handler alive
            line.isEnabled = !waiting
            sub.addItem(line)
        }
        item.submenu = sub
        return item
    }

    /// The menu's items for the profiles: a block each (its numbers follow the store while the menu is open when `live`),
    /// under a profile with standby accounts its Switch account › (when `switchTo` is given), a line between profiles.
    /// `pick` opens the quick chat on a profile.
    static func items(_ infos: [Info], now: Date = Date(), live: ((Profile) -> Info)? = nil,
                      switching: (Profile) -> Bool = { _ in false }, switchTo: ((Profile, KnownAccount) -> Void)? = nil,
                      pick: @escaping (String) -> Void) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        var blocks: [QCMenuUsageBlock] = []
        for (n, i) in infos.enumerated() {
            if n > 0 { items.append(.separator()) }
            let p = i.profile
            let block = QCMenuUsageBlock(QCMenuProfile.make(profile: p, level: i.level, address: i.address, problem: i.problem, now: now)) { pick(p.id) }
            if let live {
                block.provider = {
                    let j = live(p)
                    return QCMenuProfile.make(profile: j.profile, level: j.level, address: j.address, problem: j.problem)
                }
            }
            blocks.append(block)
            let item = NSMenuItem()
            item.view = block
            item.representedObject = p.id
            items.append(item)
            if let switchTo, !i.standby.isEmpty { items.append(switchItem(i, waiting: switching(p), switchTo: switchTo)) }
        }
        // all as wide as the widest (the menu then widens them with itself)
        let w = blocks.map(\.frame.width).max() ?? 0
        for b in blocks { b.setFrameSize(NSSize(width: w, height: b.frame.height)) }
        return items
    }
}

// MARK: - Fresh numbers

/// Keeps the menu's numbers from going stale: when the menu opens and a profile's numbers are older than a few minutes
/// (or it has none), a short-lived `claude` on that folder is asked `get_usage` (Claude Code's own sign-in; nothing goes
/// to a model; no Keychain, no token) and ended as soon as it answers. One at a time, at most one try per profile every
/// few minutes, so opening the menu again and again starts nothing more. A profile with no account signed in, or whose
/// sign-in is broken, is left alone. The answer is kept as a report after a chat answer is (ProfileStore.record).
final class QCMenuUsageRefresher {
    static let shared = QCMenuUsageRefresher()
    /// Numbers older than this are asked for again.
    static let staleAfter: TimeInterval = QuickChatLevel.freshFor
    /// A profile is tried at most this often, answered or not.
    static let retryAfter: TimeInterval = 3 * 60
    /// A `claude` that hasn't answered by then is ended.
    static var giveUp: TimeInterval = 25      // (var: the checks shorten it)

    /// Where `claude` is (looked for off the main thread, kept once found). The checks replace it.
    var findClaude: (@escaping (String?) -> Void) -> Void = { done in
        DispatchQueue.global(qos: .utility).async { let p = ClaudeLocator.find()?.path; DispatchQueue.main.async { done(p) } }
    }
    /// The command for a profile (the checks give it a work folder of their own).
    var command: (Profile, String) -> QuickChatCommand = { p, claude in
        QuickChatCommand(claude: claude, configDir: p.path, isDefaultDir: p.isDefaultFolder, workFolder: p.workFolder, model: "", effort: nil)
    }
    /// Told as a `claude` starts and as it ends (the checks count them).
    var onStart: (String) -> Void = { _ in }
    var onEnd: (String) -> Void = { _ in }

    private var queue: [String] = []
    private var running: String?
    private var current: QuickChatProcess?
    private var claudePath: String?
    private var lastTried: [String: Date] = [:]
    private var timeout: Timer?
    /// The id of the running `claude`'s `get_usage` request.
    private var usageRequest: String?

    /// Whether a profile's numbers are worth asking for now.
    func needs(_ p: Profile, store: ProfileStore = .shared, now: Date = Date()) -> Bool {
        guard ClaudeFolder.account(p.path) != nil, store.signInProblem(p) == nil else { return false }
        guard running != p.id, !queue.contains(p.id) else { return false }
        if let t = lastTried[p.id], now.timeIntervalSince(t) < Self.retryAfter { return false }
        guard let at = store.level(of: p)?.at else { return true }
        return now.timeIntervalSince(at) >= Self.staleAfter
    }

    /// The menu opened: ask for the numbers that are old, in the background, one profile at a time.
    func refresh(store: ProfileStore = .shared, now: Date = Date()) {
        for p in store.profiles where needs(p, store: store, now: now) { queue.append(p.id); lastTried[p.id] = now }
        pump(store)
    }

    private func pump(_ store: ProfileStore) {
        guard running == nil, let id = queue.first else { return }
        queue.removeFirst()
        guard let p = store.profile(id), ClaudeFolder.account(p.path) != nil else { pump(store); return }
        running = id
        let start = { [weak self] (path: String?) in
            guard let self else { return }
            guard let path else { self.finish(id, store); return }
            self.claudePath = path
            self.launch(p, claude: path, store)
        }
        if let path = claudePath, ClaudeLocator.isExecutable(path) { start(path) } else { findClaude(start) }
    }

    private func launch(_ p: Profile, claude: String, _ store: ProfileStore) {
        let process = QuickChatProcess(command(p, claude))
        // the account the folder names as it starts (read now, not when the menu opened); the process's own word
        // (initialize) then says who it is
        let start = ClaudeFolder.account(p.path)
        var trail = AccountTrail()
        trail.processStarted(on: start?.uuid, email: start?.email, organizationUuid: ClaudeFolder.organizationUuid(p.path))
        process.onEvent = { [weak self, weak process] e in
            guard let self, let process, process === self.current else { return }
            switch e {
            case .models(_, let who):
                trail.identified(who)
            case .usage(let u):
                // recorded for the account the process is, only while the folder is still on it (AccountTrail.owner): an
                // answer that comes after the folder moved to another account is dropped
                if let owner = trail.owner(folder: ClaudeFolder.account(p.path), organization: ClaudeFolder.organization(p.path),
                                           organizationUuid: ClaudeFolder.organizationUuid(p.path)) {
                    var l = store.levels[ProfileStore.levelKey(p.id, owner)] ?? QuickChatLevel()
                    if l.apply(usage: u) { store.record(p.id, account: owner, l) }
                }
                self.finish(p.id, store)
            case .control(let id, _, _):
                // Claude Code answered `get_usage` with something that isn't limits (an error, say): nothing to keep, and
                // nothing more to wait for
                if id == self.usageRequest { self.finish(p.id, store) }
            default: break
            }
        }
        process.onExit = { [weak self, weak process] _, _ in
            guard let self, let process, process === self.current else { return }
            self.finish(p.id, store)
        }
        do { try process.start() } catch { finish(p.id, store); return }
        current = process
        onStart(p.id)
        process.initialize()          // as the chat's own `claude` is, at its start (nothing goes to a model)
        usageRequest = process.getUsage()
        // in .common mode: an open menu runs the run loop in the event-tracking mode, where a default-mode timer waits
        let t = Timer(timeInterval: Self.giveUp, repeats: false) { [weak self] _ in self?.finish(p.id, store) }
        RunLoop.main.add(t, forMode: .common)
        timeout = t
    }

    private func finish(_ id: String, _ store: ProfileStore) {
        guard running == id else { return }
        timeout?.invalidate(); timeout = nil
        let p = current
        current = nil
        usageRequest = nil
        running = nil
        p?.stop()
        onEnd(id)
        pump(store)
    }
}

// MARK: - A picture

/// `--render-menu OUT.png STATE [light|dark]`: the menu's profile blocks in a drawn menu, with sample names and example.com
/// addresses. STATE: menu (three profiles: plenty left, fuller, no numbers yet), address (the pointer on the first
/// profile's address), full (a full 5-hour limit), one (a single profile in use), signedout.
enum QCMenuRender {
    static func write(to path: String, state: String, dark: Bool) {
        _ = NSApplication.shared
        let now = Date()
        func level(_ five: Double?, _ week: Double?, ago: TimeInterval = 20) -> QuickChatLevel {
            var l = QuickChatLevel()
            l.fiveHour = five; l.fiveHourResets = five == nil ? nil : now.addingTimeInterval(65 * 60 - 5)
            l.week = week; l.weekResets = week == nil ? nil : now.addingTimeInterval(29 * 3600 - 5)
            l.at = now.addingTimeInterval(-ago)
            return l
        }
        func block(_ id: String, _ name: String, _ level: QuickChatLevel?, _ address: String?, problem: SignInProblem? = nil) -> QCMenuUsageBlock {
            let p = Profile(id: id, name: name, folder: "~/.claude-\(id)")
            return QCMenuUsageBlock(QCMenuProfile.make(profile: p, level: level, address: address, problem: problem, now: now)) {}
        }
        var blocks: [QCMenuUsageBlock]
        switch state {
        case "one": blocks = [block("main", "Main", level(13, 88), "ultra-1@example.com")]
        case "full": blocks = [block("main", "Main", level(100, 64), "ultra-1@example.com"), block("work", "Work", level(31, 52, ago: 7 * 60), "ultra-2@example.com")]
        case "signedout": blocks = [block("main", "Main", level(13, 88), "ultra-1@example.com"), block("spare", "Spare", nil, nil)]
        default:
            blocks = [block("main", "Main", level(13, 88), "ultra-1@example.com"),
                      block("work", "Work", level(57, 52, ago: 7 * 60), "ultra-2@example.com"),
                      block("spare", "Spare", nil, "ultra-3@example.com")]
        }
        let w = max(blocks.map(\.frame.width).max() ?? 0, 300)
        for b in blocks { b.setFrameSize(NSSize(width: w, height: b.frame.height)) }
        if state == "address", let b = blocks.first { b.hover(at: NSPoint(x: b.addressRect.midX, y: b.addressRect.midY)) }

        // a drawn menu around them: Quick chat, the blocks, Settings…, Quit
        let font = NSFont.menuFont(ofSize: 0)
        func line(_ title: String, _ key: String) -> NSView {
            let v = NSView(frame: NSRect(x: 0, y: 0, width: w, height: 22))
            let t = NSTextField(labelWithString: title); t.font = font; t.sizeToFit()
            t.setFrameOrigin(NSPoint(x: 14, y: (22 - t.frame.height) / 2)); v.addSubview(t)
            let k = NSTextField(labelWithString: key); k.font = font; k.textColor = .secondaryLabelColor; k.sizeToFit()
            k.setFrameOrigin(NSPoint(x: w - 14 - k.frame.width, y: (22 - k.frame.height) / 2)); v.addSubview(k)
            return v
        }
        func rule() -> NSView {
            let v = NSView(frame: NSRect(x: 0, y: 0, width: w, height: 9))
            let l = NSBox(frame: NSRect(x: 10, y: 4, width: w - 20, height: 1)); l.boxType = .separator; v.addSubview(l)
            return v
        }
        var parts: [NSView] = [line("Quick chat", "⌥Space"), rule()]
        for (n, b) in blocks.enumerated() { if n > 0 { parts.append(rule()) }; parts.append(b) }
        parts += [rule(), line("Settings…", "⌘,"), line("Quit cl_quick", "⌘Q")]
        let pad: CGFloat = 24, menuPad: CGFloat = 5
        let h = parts.reduce(0) { $0 + $1.frame.height } + 2 * menuPad
        let root = NSView(frame: NSRect(x: 0, y: 0, width: w + 2 * pad, height: h + 2 * pad))
        let menu = NSView(frame: NSRect(x: pad, y: pad, width: w, height: h))
        menu.wantsLayer = true
        menu.layer?.cornerRadius = 10
        menu.layer?.backgroundColor = (dark ? NSColor(white: 0.17, alpha: 1) : NSColor(white: 0.96, alpha: 1)).cgColor
        menu.layer?.borderWidth = 0.5
        menu.layer?.borderColor = (dark ? NSColor(white: 1, alpha: 0.18) : NSColor(white: 0, alpha: 0.18)).cgColor
        root.addSubview(menu)
        var y = h - menuPad
        for v in parts { y -= v.frame.height; v.setFrameOrigin(NSPoint(x: 0, y: y)); menu.addSubview(v) }
        root.wantsLayer = true
        root.layer?.backgroundColor = (dark ? NSColor(white: 0.08, alpha: 1) : NSColor(white: 0.80, alpha: 1)).cgColor
        root.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        root.layoutSubtreeIfNeeded()
        // twice the pixels
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(root.bounds.width) * 2, pixelsHigh: Int(root.bounds.height) * 2,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = root.bounds.size
        root.cacheDisplay(in: root.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
