// MenuUsage: the menu bar item's menu, with each profile's usage drawn as cl_audit's menu draws it: the profile's name
// and a dot in the colour of its fuller limit, the account in use with a green lamp (its address blurred until the
// pointer is on it, as in the profile menu: MenuRow.swift), two bars ("5-hour", "Week") with their share and the time
// to the reset, and how old the numbers are. Only the account in use shows usage; a standby account shows none.
//
// The numbers are the ones cl_quick already keeps (levels.json, from Claude Code's `get_usage`); the menu shows them at
// once when it opens: fresh ones in their colours (a full limit as a crimson note), older ones grey however old, as
// "Last known 3 h ago", or "Reading now… · last known 3 h ago" while QCMenuUsageRefresher asks for fresh ones (it starts
// as the menu opens). A window whose reset has passed since shows "–" (its old number says nothing now). A saved full
// limit (Week or 5-hour at 100%, or a refusal) whose reset is still ahead stays until that reset: "Week full · last
// known" in the header, grey, its row at 100% with "back …". A refusal that names no window puts its end in the note.
// No dot colour; the block has the shape of a fresh one, so a fresh answer replaces it live while the menu is open. It
// is only the menu's: the chat, "Ask on …" and the switch offers never act on a number that isn't fresh
// (ProfileStore.shownLevel), and a fresh answer replaces it at once. When they are older than a few minutes, QCMenuUsageRefresher asks Claude Code again in the
// background: cl_kit's short ask (ClaudeAsk) per profile, one at a time, sent `initialize` and `get_usage` and nothing
// else (no message to a model), and stopped as soon as it has answered. Nothing is read from the Keychain; no token is
// ever seen. The rules the block follows (how old, what holds the account back, the colours, the week-only rule, the
// time words) are ProfileCore's (QuickChatLevel.display).

import AddressPrivacy
import AppKit
import ClaudeAuth
import Combine
import MenuRows
import ProfileCore
import Runs

// MARK: - What a profile's block says

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
        /// Last known, not now (no longer fresh by QuickChatLevel.ages): drawn grey.
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
    /// The account in use has no numbers yet (or none that still say anything): one muted line instead of the bars.
    let noUsage: Bool
    /// "Updated just now", "Updated 3 min ago"; "Last known 3 h ago" for numbers no longer fresh, "Reading now… · last
    /// known 3 h ago" while fresh ones are being asked for.
    var updated: String?
    /// The muted line when `noUsage`: "No usage yet", or "Reading now…" while numbers are being asked for.
    var noUsageText = Self.noUsageWords
    /// `fullNote` is a saved full limit, last known and not now: drawn grey, not crimson.
    var fullNoteStale = false

    static let noUsageWords = "No usage yet"
    /// Said while QCMenuUsageRefresher asks Claude Code for this profile's numbers (it starts as the menu opens).
    static let readingWords = "Reading now…"

    /// "Claude Main"; a name that starts with Claude as it is.
    static func title(_ name: String) -> String { name.lowercased().hasPrefix("claude") ? name : "Claude " + name }

    /// The address as words (VoiceOver, the checks): masked. On screen it is blurred everywhere, masked only as words.
    var accountWords: String {
        switch account {
        case .inUse(let a): return AddressPrivacy.words(a) + " · in use"
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
    /// the menu opens (but for the reading words: `notReading`). The header note doesn't (but its width does:
    /// QCMenuUsageBlock.reload).
    var shape: [Int] { [rows.count, noUsage ? 1 : 0, updated == nil ? 0 : 1] }

    private static let readingLead = readingWords + " · last known"

    /// Whether it says fresh numbers are being read.
    var isReading: Bool { noUsageText == Self.readingWords || updated?.hasPrefix(Self.readingLead) == true }

    /// The same block, no longer saying a read is under way: "Reading now…" back to "No usage yet", "Reading now… · last
    /// known 3 h ago" to "Last known 3 h ago". What an open menu shows when the read ended with an answer that changes
    /// the block's height (the numbers then wait for the next time it opens; the words mustn't say it is still reading).
    var notReading: QCMenuProfile {
        var m = self
        if m.noUsageText == Self.readingWords { m.noUsageText = Self.noUsageWords }
        if let u = m.updated, u.hasPrefix(Self.readingLead) { m.updated = "Last known" + u.dropFirst(Self.readingLead.count) }
        return m
    }

    /// The block for a profile: `address` is the account in use (nil: signed out), `problem` what is wrong with its sign-in,
    /// `level` its numbers as last reported (nil: none yet), `reading` whether fresh ones are being asked for now.
    static func make(profile p: Profile, level: QuickChatLevel?, address: String?, problem: SignInProblem?, reading: Bool = false,
                     now: Date = Date()) -> QCMenuProfile {
        guard let address, problem != .signedOut else {
            return QCMenuProfile(id: p.id, title: title(p.name), dotP: nil, fullNote: nil, account: .problem(words: SignInProblem.signedOut.words),
                                 rows: [], noUsage: false, updated: nil)
        }
        if let problem {
            return QCMenuProfile(id: p.id, title: title(p.name), dotP: nil, fullNote: nil, account: .problem(words: problem.words),
                                 rows: [], noUsage: false, updated: nil)
        }
        // how old the numbers are: fresh ones are the account now; older ones are what Claude Code said last, drawn grey
        // however old (the refresh asks again as the menu opens), a window whose reset has passed since as "–"; a saved
        // full limit whose reset is still ahead stays, grey and worded "last known", until the reset (ProfileCore's
        // display value by cl_quick's ages, QuickChatLevel.ages: fresh numbers act; older ones are only drawn)
        let d = level?.display(now)
        let fresh = d?.tier == .fresh
        // what holds the account back: while fresh, any; else a saved full limit (or refusal) whose end is still ahead
        let full = d?.heldBack
        let savedFull = fresh ? nil : full
        func row(_ id: String, _ label: String) -> Row {
            let isFull = full?.window.id == id
            let p = isFull ? 100 : d?.number(id)
            let at = isFull ? full?.resets : id == "5h" ? d?.usage?.fiveHourResets : d?.usage?.weeklyResets
            var words = ""
            if let p, let at { words = p.rounded() >= 100 ? TimeWords.back(at, now: now) : "in " + TimeWords.countdown(at, now: now) }
            return Row(id: id, label: label, p: p, share: QuickChatLevel.pct(p), resets: words, stale: !fresh)
        }
        var rows: [Row] = []
        if let d {
            rows = [row("5h", "5-hour"), row("wk", "Week")]
                .filter { $0.id != "5h" || d.hasFiveHour }       // no 5-hour window on the account: the week alone
            // two "–" rows stay for a saved full that names no window, so it keeps a fresh block's shape too; with no
            // full one, rows that all say nothing (every window reset since) are no numbers
            if savedFull == nil, rows.allSatisfy({ $0.p == nil }) { rows = [] }
        }
        let agoWords = level?.at.map { AccountBook.ago($0, now: now) }
        let name = full.map { $0.window == .fiveHour ? "5-hour" : $0.window == .week ? "Week" : "Limit" }
        // fresh: "Week full · in 2d 3h", crimson. Saved: "Week full · last known", grey, with the age on the line under
        // the bars as for any last known number; a refusal that names no window has no row to carry its end, so its
        // note does: "Limit full · back at 15:28 · last known"
        let note: String? = full.flatMap { f in
            fresh ? name.map { $0 + " full" + (f.resets.map { " · in " + TimeWords.countdown($0, now: now) } ?? "") }
                  : name.map { $0 + " full" + (f.window == .any ? f.resets.map { " · " + TimeWords.back($0, now: now) } ?? "" : "") + " · last known" }
        }
        // last known: "Last known 3 h ago", or "Reading now… · last known 3 h ago" while fresh ones are asked for (the line
        // is there either way, so the answer replaces it live)
        // (numbers kept before their report time was: "Last known" with no age)
        let ago = agoWords.map { " " + $0 } ?? ""
        let updated: String? = rows.isEmpty ? nil : fresh ? agoWords.map { "Updated " + $0 } : (reading ? readingLead : "Last known") + ago
        let noUsageText = reading ? readingWords : noUsageWords
        return QCMenuProfile(id: p.id, title: title(p.name), dotP: fresh ? d?.binding?.p : nil, fullNote: note,
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
    /// The address is drawn readable: the pointer is on it, or addresses are not blurred (AddressPrivacy).
    var sharp: Bool { revealed || !AddressPrivacy.shared.blur }
    private var watch: AnyCancellable?

    static let padX: CGFloat = 14, top: CGFloat = 7, bottom: CGFloat = 8, joinedBottom: CGFloat = 1
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

    init(_ model: QCMenuProfile, joined: Bool = false, pick: @escaping () -> Void) {
        self.model = model; self.pick = pick
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width(model), height: Self.height(model, joined: joined)))
        autoresizingMask = [.width]
        toolTip = "Open the quick chat on \(model.title.replacingOccurrences(of: "Claude ", with: ""))"
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
    }
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    /// What VoiceOver reads, worked out on each call (so a change of the Blur addresses setting reaches it).
    override func accessibilityLabel() -> String? { model.spoken }

    override var isFlipped: Bool { true }

    // MARK: size

    private static func w(_ s: String, _ f: NSFont) -> CGFloat { ceil((s as NSString).size(withAttributes: [.font: f]).width) }
    /// Measures the room an address is given: the stand-in's while the blur is on, whatever the address (nothing moves when it is revealed).
    private static let sizer = AddressInk(font: QCProfileMenuRow.addressFont)
    /// Draws the address (its own text while it is readable, else the stand-in blurred).
    private let ink = AddressInk(font: QCProfileMenuRow.addressFont)

    /// The least width that shows it all (nothing is cut): the widest of the header, the account line, the rows, the note.
    static func width(_ m: QCMenuProfile) -> CGFloat {
        let head = padX + textGap + w(m.title, titleFont) + (m.fullNote.map { 16 + w($0, noteFont) } ?? 0) + padX
        let account: CGFloat
        switch m.account {
        case .inUse(let a): account = padX + textGap + sizer.room(for: a, blur: AddressPrivacy.shared.blur) + w(" · in use", accountFont) + padX
        case .problem(let words): account = padX + textGap + w(words, accountFont) + padX
        }
        let reset = m.rows.map { w($0.resets, resetFont) }.max() ?? 0
        let rows = m.rows.isEmpty ? 0 : padX + labelW + colGap + barW + colGap + shareW + colGap + max(reset, 64) + padX
        let note = max(m.updated.map { padX + w($0, resetFont) + padX } ?? 0, m.noUsage ? padX + w(m.noUsageText, accountFont) + padX : 0)
        return max(minWidth, head, account, rows, note)
    }

    /// `joined`: standby rows follow the block in its group, which then ends a little closer to them.
    static func height(_ m: QCMenuProfile, joined: Bool = false) -> CGFloat {
        var h = top + headH + accountH
        if m.noUsage { h += rowGap + rowH }
        if !m.rows.isEmpty { h += 4 + CGFloat(m.rows.count) * rowH + CGFloat(m.rows.count - 1) * rowGap }
        if m.updated != nil { h += 3 + noteH }
        return h + (joined ? joinedBottom : bottom)
    }

    // MARK: where things are

    private var accountY: CGFloat { Self.top + Self.headH }
    private func rowY(_ i: Int) -> CGFloat { accountY + Self.accountH + 4 + CGFloat(i) * (Self.rowH + Self.rowGap) }
    private var addressWidth: CGFloat {
        if case .inUse(let a) = model.account { return Self.sizer.room(for: a, blur: AddressPrivacy.shared.blur) }
        return 0
    }
    /// The text drawn for the account's address now: its own while it is readable, else the stand-in.
    var drawnAddress: String? {
        if case .inUse(let a) = model.account { return AddressText.drawn(address: a, revealed: sharp, blur: true) }
        return nil
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

    /// A click is a release on the block: one released outside it (the press was on it) does nothing.
    override func mouseUp(with e: NSEvent) { if releasedOn(e) { press() } }

    /// A click: the menu closes and the quick chat opens on the profile.
    func press() { closeMenuThen(pick) }

    override func accessibilityPerformPress() -> Bool { press(); return true }

    // MARK: live numbers

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, let provider else { watch = nil; return }
        // the store says it will change before it has: read it once it has. A read that ends with no answer changes no
        // numbers, only "Reading now…" back to "Last known …": the refresher says so.
        watch = ProfileStore.shared.$levels.map { _ in () }.merge(with: QCMenuUsageRefresher.shared.changed).sink { [weak self] _ in
            DispatchQueue.main.async { guard let self else { return }; self.reload(provider()) }
        }
    }

    /// New numbers for the block, in place: only when its height stays (a menu doesn't take a row that changes size)
    /// and it still fits the width the menu gave it (a header note that grew would be cut).
    /// An answer that changes the height waits for the next time the menu opens, but once the read is over the block
    /// stops saying "Reading now…" (QCMenuProfile.notReading).
    func reload(_ m: QCMenuProfile) {
        let next = m.shape == model.shape ? m : m.isReading ? model : model.notReading
        guard next != model, Self.width(next) <= frame.width else { return }
        model = next
        needsDisplay = true
    }

    // MARK: drawing

    /// A line of text with its middle at `midY` (the standby rows draw theirs the same way).
    static func drawText(_ s: String, _ font: NSFont, _ color: NSColor, x: CGFloat, midY: CGFloat) {
        let size = (s as NSString).size(withAttributes: [.font: font])
        (s as NSString).draw(at: NSPoint(x: x, y: midY - size.height / 2), withAttributes: [.font: font, .foregroundColor: color])
    }
    private func text(_ s: String, _ font: NSFont, _ color: NSColor, x: CGFloat, midY: CGFloat) { Self.drawText(s, font, color, x: x, midY: midY) }
    private func textRight(_ s: String, _ font: NSFont, _ color: NSColor, right: CGFloat, midY: CGFloat) {
        text(s, font, color, x: right - Self.w(s, font), midY: midY)
    }

    /// The account in use's lamp in the lamp column (a standby row's hollow one is MenuRows': `.hollowLamp`).
    static func drawLamp(_ color: NSColor, glow: Bool = false, midY: CGFloat) {
        let r = NSRect(x: padX, y: midY - dotSize / 2, width: dotSize, height: dotSize)
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
    private func lamp(_ color: NSColor, glow: Bool, midY: CGFloat) { Self.drawLamp(color, glow: glow, midY: midY) }

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
            ink.draw(address: address, readable: sharp, color: .secondaryLabelColor, x: a.minX, midY: accMid, blur: AddressPrivacy.shared.blur)
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

    // (the blurred stand-in is made once per colour by `ink`, and made again if the appearance changes: its colour is the system's)
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        ink.reset()
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
        /// The seats signed in before and not in use now, the most recently seen first (one row each: a personal plan
        /// and a Team seat on one address are two).
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

    /// Whether a click on a standby row may start the switch now: the account is still a standby one of the profile (a
    /// sign-in that finished while the menu was open may have made it the one in use) and no switch is waited for.
    static func mayStartSwitch(_ p: Profile, _ a: KnownAccount, store: ProfileStore = .shared,
                               waiting: (Profile) -> Bool = { AccountSwitcher.shared.waiting[$0.id] != nil }) -> Bool {
        !waiting(p) && store.standby(p).contains { $0.key == a.key }
    }
    /// The rule a click is held to (a seam: the checks replace it).
    static var allowSwitch: (Profile, KnownAccount) -> Bool = { mayStartSwitch($0, $1) }

    /// A standby account as cl_kit's MenuRows says it: dimmed, a hollow lamp, "<address> · standby" and a quiet "Switch…" at
    /// the right while it is lit. It shows no usage. Off (`waiting`) while a sign-in for the profile is waited for: never lit,
    /// does nothing. The address is MenuRows': its stand-in blurred until the pointer is on the row (never the real text).
    static func standbyRow(address: String, waiting: Bool) -> MenuAccountRow {
        MenuAccountRow(address: address, inUse: false, tag: " · standby", hint: "Switch…", enabled: !waiting, dimmed: true, marker: .hollowLamp,
                       waiting: waiting)
    }

    /// A standby account's row (MenuRows' MenuAccountRowView), in its profile's group: a click anywhere on it asks the switch
    /// question (AccountSwitcher.confirmAndSwitch: what it moves, then Claude Code's sign-in in Terminal). Nothing new happens
    /// here: it is the path the chat's and Settings' Switch… take. Off while a sign-in for the profile is waited for.
    /// The item's title and action stay for VoiceOver, the menu's type-ahead and Return (the title has the address masked).
    static func standbyItem(_ p: Profile, _ a: KnownAccount, waiting: Bool, columns: MenuRowColumns = .bar,
                            switchTo: @escaping (Profile, KnownAccount) -> Void) -> (NSMenuItem, MenuAccountRowView) {
        // the menu was built some time ago: the question is asked only if the account is still on standby
        let item = MenuAccountRowView.item(standbyRow(address: a.email, waiting: waiting), columns: columns, addressFont: MenuAccountRowView.quickAddressFont) {
            if allowSwitch(p, a) { switchTo(p, a) }
        }
        return (item, item.view as! MenuAccountRowView)
    }

    /// Whether a click on Add an account… may open it now: the profile is still there (it may have been removed since the
    /// menu was built) and no switch is waited for on it (one may have begun since).
    static func mayAddAccount(_ p: Profile, exists: (Profile) -> Bool = { ProfileStore.shared.profile($0.id) != nil },
                              waiting: (Profile) -> Bool = { AccountSwitcher.shared.waiting[$0.id] != nil }) -> Bool {
        exists(p) && !waiting(p)
    }
    /// The rule a click on Add an account… is held to (a seam: the checks replace it).
    static var allowAddAccount: (Profile) -> Bool = { mayAddAccount($0) }

    /// Add an account… as MenuRows' row with no account (`MenuAccountRow.add`: a "+" and the words), dimmed like a standby row.
    static func addAccountRow(waiting: Bool) -> MenuAccountRow {
        var r = MenuAccountRow.add("Add an account…", enabled: !waiting, waiting: waiting)
        r.dimmed = true
        return r
    }

    /// Add an account… (MenuRows' MenuAccountRowView), last in its profile's group: opens Settings on the profile with its Add
    /// an account… form open (`add`). Nothing new is begun here: the form is Settings' own. Off while a sign-in for the profile
    /// is waited for, as Settings' own key is. Both menus build it here.
    static func addAccountItem(_ p: Profile, waiting: Bool, columns: MenuRowColumns = .bar,
                               add: @escaping (Profile) -> Void) -> (NSMenuItem, MenuAccountRowView) {
        let item = MenuAccountRowView.item(addAccountRow(waiting: waiting), columns: columns, addressFont: MenuAccountRowView.quickAddressFont) {
            if allowAddAccount(p) { add(p) }
        }
        return (item, item.view as! MenuAccountRowView)
    }

    /// Every block and row as wide as the widest (the menu then widens them with itself).
    static func fit(blocks: [QCMenuUsageBlock], rows: [NSView]) {
        let w = max(blocks.map(\.frame.width).max() ?? 0, rows.map(\.frame.width).max() ?? 0)
        for b in blocks { b.setFrameSize(NSSize(width: w, height: b.frame.height)) }
        for r in rows { r.setFrameSize(NSSize(width: w, height: r.frame.height)) }
    }

    /// The menu's items for the profiles: a block each (its numbers follow the store while the menu is open when `live`),
    /// under it a row for each standby account (when `switchTo` is given) and Add an account… (when `addAccount` is given),
    /// a line between profiles and none inside a profile's group. `pick` opens the quick chat on a profile. The rows stay
    /// as built when the menu opened (it is built again on every open).
    static func items(_ infos: [Info], now: Date = Date(), live: ((Profile) -> Info)? = nil,
                      reading: @escaping (Profile) -> Bool = { _ in false },
                      switching: (Profile) -> Bool = { _ in false }, switchTo: ((Profile, KnownAccount) -> Void)? = nil,
                      addAccount: ((Profile) -> Void)? = nil,
                      pick: @escaping (String) -> Void) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        var blocks: [QCMenuUsageBlock] = []
        var rows: [NSView] = []
        for (n, i) in infos.enumerated() {
            if n > 0 { items.append(.separator()) }
            let p = i.profile
            let block = QCMenuUsageBlock(QCMenuProfile.make(profile: p, level: i.level, address: i.address, problem: i.problem,
                                                            reading: reading(p), now: now),
                                         joined: (switchTo != nil && !i.standby.isEmpty) || addAccount != nil) { pick(p.id) }
            if let live {
                block.provider = {
                    let j = live(p)
                    return QCMenuProfile.make(profile: j.profile, level: j.level, address: j.address, problem: j.problem, reading: reading(j.profile))
                }
            }
            blocks.append(block)
            let item = NSMenuItem()
            item.view = block
            item.representedObject = p.id
            items.append(item)
            let waiting = switching(p)
            if let switchTo {
                for a in i.standby {
                    let (line, row) = standbyItem(p, a, waiting: waiting, switchTo: switchTo)
                    rows.append(row)
                    items.append(line)
                }
            }
            if let addAccount {
                let (line, row) = addAccountItem(p, waiting: waiting, add: addAccount)
                rows.append(row)
                items.append(line)
            }
        }
        fit(blocks: blocks, rows: rows)
        return items
    }
}

// MARK: - Fresh numbers

/// Keeps the menu's numbers from going stale: when the menu opens and a profile's numbers are no longer fresh (or it has
/// none), cl_kit's short ask (ClaudeAsk: a `claude` on that folder with nothing kept or loaded) is asked `initialize` and
/// `get_usage` (Claude Code's own sign-in; nothing goes to a model; no Keychain, no token) and stopped as soon as it has
/// answered (its input closed, then SIGTERM, then SIGKILL). One at a time, at most one try per profile every few
/// minutes, so opening the menu again and again starts nothing more. A profile with no account signed in, or whose
/// sign-in is broken, is left alone. The answer is kept as a report after a chat answer is (ProfileStore.record).
final class QCMenuUsageRefresher {
    static let shared = QCMenuUsageRefresher()
    /// A profile is tried at most this often, answered or not.
    static let retryAfter: TimeInterval = 3 * 60
    /// A `claude` that hasn't answered by then is ended.
    static var giveUp: TimeInterval = 25      // (var: the checks shorten it)

    /// Where `claude` is (looked for off the main thread, kept once found). The checks replace it.
    var findClaude: (@escaping (String?) -> Void) -> Void = { done in
        DispatchQueue.global(qos: .utility).async { let p = ClaudeFinder.find()?.path; DispatchQueue.main.async { done(p) } }
    }
    /// The folder `claude` runs in for a profile: its quick chat work folder (the checks give it one of their own).
    var workFolder: (Profile) -> String = { $0.workFolder }
    /// Told as a `claude` starts and as it ends (the checks count them).
    var onStart: (String) -> Void = { _ in }
    var onEnd: (String) -> Void = { _ in }

    private var queue: [String] = []
    private var running: String?
    private var claudePath: String?
    private var lastTried: [String: Date] = [:]

    /// Told when a profile starts or stops being read (an open menu's blocks say "Reading now…" meanwhile).
    let changed = PassthroughSubject<Void, Never>()

    /// Whether a profile's numbers are being asked for now, or waiting their turn.
    func reading(_ id: String) -> Bool { running == id || queue.contains(id) }

    /// Whether a profile's numbers are worth asking for now.
    func needs(_ p: Profile, store: ProfileStore = .shared, now: Date = Date()) -> Bool {
        guard ClaudeFolder.account(p.path) != nil, store.signInProblem(p) == nil else { return false }
        guard running != p.id, !queue.contains(p.id) else { return false }
        if let t = lastTried[p.id], now.timeIntervalSince(t) < Self.retryAfter { return false }
        // none yet, or no longer fresh (QuickChatLevel.ages): asked for again
        return store.level(of: p)?.age(now) != .fresh
    }

    /// The menu opened: ask for the numbers that are old, in the background, one profile at a time.
    func refresh(store: ProfileStore = .shared, now: Date = Date()) {
        // (the menu's blocks are built after this and read `reading` then: nothing to tell them yet)
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
        if let path = claudePath, ClaudeFinder.isExecutable(path) { start(path) } else { findClaude(start) }
    }

    private func launch(_ p: Profile, claude: String, _ store: ProfileStore) {
        let folder = workFolder(p)
        guard (try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)) != nil else { finish(p.id, store); return }
        // the account the folder names as it starts (read now, not when the menu opened); the process's own word
        // (initialize) then says who it is
        var trail = ProcessTrail(launchedOn: ClaudeFolder.account(p.path))
        let env = ClaudeEnvironment.make(ProcessInfo.processInfo.environment, claude: claude,
                                         configDir: p.isDefaultFolder ? nil : p.path, traceless: true)
        let giveUp = Self.giveUp
        onStart(p.id)
        // the ask blocks until every answer came, `claude` ended or the time ran out (then it is stopped): off the main
        // thread; the answer is taken on the main queue, which an open menu's run loop serves too
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let answer = ClaudeAsk.ask(claude: claude, environment: env, folder: folder, usage: true, timeout: giveUp)
            DispatchQueue.main.async {
                guard let self, self.running == p.id else { return }
                trail.said(SignedInAccount.process(answer.account.map { $0 as [String: Any] }))
                // kept for the account the numbers belong to (the kit's numbersBelongTo with the process's trail): an
                // answer that comes after the folder moved to another account stays that account's, never the new one's.
                // An error answer, or none, keeps nothing.
                if let u = answer.limits, let owner = AccountBook.numbersOwner(record: ClaudeFolder.account(p.path), trail: trail) {
                    var l = store.base(p.id, for: owner) ?? QuickChatLevel()
                    if l.apply(usage: u) { store.record(p.id, account: owner, l) }
                }
                self.finish(p.id, store)
            }
        }
    }

    private func finish(_ id: String, _ store: ProfileStore) {
        guard running == id else { return }
        running = nil
        onEnd(id)
        pump(store)
        changed.send()
    }
}

// MARK: - A picture

/// `--render-menu OUT.png STATE [light|dark]`: the menu's profile blocks in a drawn menu, with sample names and example.com
/// addresses. STATE: menu (three profiles: plenty left, fuller, no numbers yet), address (the pointer on the first
/// profile's address), full (a full 5-hour limit), one (a single profile in use), signedout, reading (3 h old numbers,
/// grey, "Reading now… · last known 3 h ago"), lastknown (the same after a read with no answer). With standby accounts:
/// standby (one profile and one standby row, at rest), standby-lit (the same, the row highlighted: sharp address and
/// "Switch…"), standby-waiting (a sign-in waited for: the row dimmed further), standby2 (two profiles: Main with two
/// standby rows, the first highlighted, and Work with none and no numbers). With Add an account… after the
/// standby rows: add (one profile, one standby row), add-lit (Add an account… highlighted), add-waiting (a sign-in waited
/// for: both rows dimmed), add2 (Main with two standby rows, Work with none: Add an account… alone).
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
        func block(_ id: String, _ name: String, _ level: QuickChatLevel?, _ address: String?, problem: SignInProblem? = nil, joined: Bool = false,
                   reading: Bool = false) -> QCMenuUsageBlock {
            let p = Profile(id: id, name: name, folder: "~/.claude-\(id)")
            return QCMenuUsageBlock(QCMenuProfile.make(profile: p, level: level, address: address, problem: problem, reading: reading, now: now),
                                    joined: joined) {}
        }
        func standby(_ address: String, waiting: Bool = false, lit: Bool = false) -> MenuAccountRowView {
            let r = MenuAccountRowView(row: QCStatusMenu.standbyRow(address: address, waiting: waiting), columns: .bar,
                                       addressFont: MenuAccountRowView.quickAddressFont) {}
            r.highlighted = lit
            return r
        }
        func addRow(waiting: Bool = false, lit: Bool = false) -> MenuAccountRowView {
            let r = MenuAccountRowView(row: QCStatusMenu.addAccountRow(waiting: waiting), columns: .bar,
                                       addressFont: MenuAccountRowView.quickAddressFont) {}
            r.highlighted = lit
            return r
        }
        var blocks: [QCMenuUsageBlock]
        var standbyRows: [[NSView]] = []
        switch state {
        case "add", "add-lit", "add-waiting":
            // Add an account… after the standby row (-lit: highlighted; -waiting: a sign-in waited for, both dimmed further)
            blocks = [block("main", "Main", level(42, 68), "alex@example.com", joined: true)]
            standbyRows = [[standby("alex.studio@example.com", waiting: state == "add-waiting"), addRow(waiting: state == "add-waiting", lit: state == "add-lit")]]
        case "add2":
            // two profiles: Main with two standby rows, Work with none (Add an account… alone)
            blocks = [block("main", "Main", level(42, 68), "alex@example.com", joined: true), block("work", "Work", level(nil, nil, ago: 2 * 3600), "kim.work@example.org", joined: true)]
            standbyRows = [[standby("alex.studio@example.com"), standby("alex.old@example.org"), addRow()], [addRow()]]
        case "standby", "standby-lit", "standby-waiting":
            blocks = [block("main", "Main", level(42, 68), "alex@example.com", joined: true)]
            standbyRows = [[standby("alex.studio@example.com", waiting: state == "standby-waiting", lit: state == "standby-lit")]]
        case "standby2":
            blocks = [block("main", "Main", level(42, 68), "alex@example.com", joined: true), block("work", "Work", level(nil, nil, ago: 2 * 3600), "kim.work@example.org")]
            standbyRows = [[standby("alex.studio@example.com", lit: true), standby("alex.old@example.org")], []]
        case "one": blocks = [block("main", "Main", level(13, 88), "ultra-1@example.com")]
        case "reading", "lastknown":
            // 3 h old numbers, grey: while fresh ones are read (reading), and after a read that got no answer (lastknown)
            blocks = [block("main", "Main", level(41, 24, ago: 3 * 3600), "alex@example.com", reading: state == "reading")]
        case "full": blocks = [block("main", "Main", level(100, 64), "ultra-1@example.com"), block("work", "Work", level(31, 52, ago: 7 * 60), "ultra-2@example.com")]
        case "signedout": blocks = [block("main", "Main", level(13, 88), "ultra-1@example.com"), block("spare", "Spare", nil, nil)]
        default:
            blocks = [block("main", "Main", level(13, 88), "ultra-1@example.com"),
                      block("work", "Work", level(57, 52, ago: 7 * 60), "ultra-2@example.com"),
                      block("spare", "Spare", nil, "ultra-3@example.com")]
        }
        QCStatusMenu.fit(blocks: blocks, rows: standbyRows.flatMap { $0 })
        let w = max(blocks.map(\.frame.width).max() ?? 0, 300)
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
        var parts: [NSView] = [line("Quick chat", "⌃⇧Space"), rule()]
        for (n, b) in blocks.enumerated() {
            if n > 0 { parts.append(rule()) }
            parts.append(b)
            if n < standbyRows.count { parts += standbyRows[n] }
        }
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
