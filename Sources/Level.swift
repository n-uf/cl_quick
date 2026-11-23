// Level: a profile's week (and 5-hour limit) as Claude Code reported it after the last answer on it (what is kept, and
// how a report changes it), and how it shows: by ProfileCore's rules (cl_kit), the same as cl_audit's. Its time words,
// its colour level (green, amber from 50%, red from 80%, crimson from 95%), its ages (fresh, last known, not shown), what
// holds the account back and the week-only rule are the kit's (ProfileDisplay); only the colours themselves and the
// words around them are cl_quick's.

import AppKit
import ProfileCore
import SwiftUI

/// The level colours under cl_audit's names, which Faces.swift uses as it is. Which one a share takes is ProfileCore's
/// one level rule (Level.of).
enum Painter {
    static let green = NSColor(srgbRed: 0x22 / 255, green: 0xc5 / 255, blue: 0x5e / 255, alpha: 1)
    static let amber = NSColor(srgbRed: 0xf5 / 255, green: 0x9e / 255, blue: 0x0b / 255, alpha: 1)
    static let red = NSColor(srgbRed: 0xef / 255, green: 0x44 / 255, blue: 0x44 / 255, alpha: 1)
    static let crimson = NSColor(displayP3Red: 0xeb / 255, green: 0x44 / 255, blue: 0x5b / 255, alpha: 1)
    static let grey = NSColor(srgbRed: 0x6b / 255, green: 0x72 / 255, blue: 0x80 / 255, alpha: 1)
    /// A level's colour: grey for none (no number, or old numbers).
    static func color(_ level: Level) -> NSColor {
        switch level {
        case .none: return grey
        case .green: return green
        case .amber: return amber
        case .red: return red
        case .crimson: return crimson
        }
    }
    static func color(_ p: Double?, stale: Bool) -> NSColor { color(Level.of(p, stale: stale)) }
    /// One of twelve segments (0 = first): six green, three amber, two red, the last crimson.
    static func segment(_ i: Int) -> NSColor { i < 6 ? green : i < 9 ? amber : i < 11 ? red : crimson }
}

extension HeldBack.Window {
    /// The window's id as the views and their marks name it: "5h", "wk"; "any" when Claude Code refused but neither
    /// window is known to be the full one (both reported below 100%, or no numbers): then no window is drawn full, only
    /// the account is held back.
    var id: String {
        switch self {
        case .fiveHour: return "5h"
        case .week: return "wk"
        case .any: return "any"
        }
    }
}

extension HeldBack {
    /// "5-hour limit", "week", or "limit" when no window is known to be the one.
    var name: String { window == .fiveHour ? "5-hour limit" : window == .week ? "week" : "limit" }

    /// The notice for a full limit, naming the window that is full as the header shows it, and when it resets:
    /// "Main's 5-hour limit is full, resets 23:20." / "Main's week is full, resets Thu 19:00.". When no window can be
    /// named it names none: "Main's limit is full, resets 23:20." (the refusal's end), or "Main's limit is full."
    static func sentence(_ held: HeldBack?, who: String, now: Date = Date()) -> String {
        guard let h = held else { return "\(who)'s limit is full." }
        return "\(who)'s \(h.name) is full" + (h.resets.map { ", resets " + TimeWords.when($0, now: now) } ?? "") + "."
    }
}

extension ProfileDisplay {
    /// A window's number as it shows now ("5h", "wk"; nil: not known, or not shown).
    func number(_ id: String) -> Double? { id == "5h" ? usage?.fiveHour : usage?.weekly }

    /// What holds the account back, when it is this window.
    func held(_ id: String) -> HeldBack? { heldBack.flatMap { $0.window.id == id ? $0 : nil } }

    /// A window's share as drawn: 100 for the one that holds the account back, else its number.
    func share(_ id: String) -> Double? { held(id) != nil ? 100 : number(id) }

    /// When a window resets: the end of what holds it back, else its number's reset.
    func resets(_ id: String) -> Date? { held(id)?.resets ?? (id == "5h" ? usage?.fiveHourResets : usage?.weeklyResets) }

    /// The window closest to full: the one that holds the account back, else the higher share, the 5-hour window on a
    /// tie; nil while neither is known. What the bar's indicator and the profile's dot show, so neither reads as "plenty
    /// left" while the other window is nearly full. A refusal that names no window marks none full (the fuller share
    /// shows as it is).
    var binding: (id: String, p: Double)? {
        if let h = heldBack, h.window != .any { return (h.window.id, 100) }
        switch (usage?.fiveHour, usage?.weekly) {
        case let (a?, b?): return a >= b ? ("5h", a) : ("wk", b)
        case let (a?, nil): return ("5h", a)
        case let (nil, b?): return ("wk", b)
        default: return nil
        }
    }
}

struct QuickChatLevel: Codable, Equatable {
    var week: Double?
    var weekResets: Date?
    var fiveHour: Double?
    var fiveHourResets: Date?
    /// When Claude Code last said the account is refusing (rate_limit_event "rejected"), and until when.
    var refusedUntil: Date?
    /// When that refusal was said (nil in a levels.json from before this was kept: as old as can be).
    var refusedAt: Date?
    /// The window that carried that refusal, "5h" or "wk"; nil when it isn't known (a refusal that named none, both
    /// windows locked, or a levels.json from before this was kept). Only that window's number can say the refusal is over.
    var refusedOn: String?
    /// When Claude Code reported it.
    var at: Date?

    init() {}

    /// cl_quick's ages, by ProfileCore's rules (its Core/README): numbers count as the account's state now for 5 minutes
    /// after Claude Code gave them (fresh: they act). Older ones are only what it said last (the plan may have changed
    /// since, or another account been in use): nothing is drawn full, refused or offered elsewhere on them, and the menu
    /// shows them grey as last known (ProfileStore.shownLevel, QCMenuProfile); past an hour not at all, except a full limit
    /// or a refusal whose known end is still ahead, grey, until then (`datedFullStays`).
    static let ages = Headline.Ages(freshFor: 5 * 60, hiddenAfter: 3600, datedFullStays: true)
    /// The same, never hidden by age: Settings shows the last numbers however old (the caption says when).
    static let settingsAges = Headline.Ages(freshFor: 5 * 60, hiddenAfter: nil, datedFullStays: true)

    /// The numbers as ProfileCore reads them (no report time: as old as can be).
    var usage: Usage {
        Usage(fiveHour: fiveHour, fiveHourResets: fiveHourResets, weekly: week, weeklyResets: weekResets,
              fetchedAt: at ?? .distantPast, source: "claude")
    }

    /// A refusal standing on the account, as ProfileCore takes it.
    var refusal: Refusal? {
        refusedUntil.map { Refusal(until: $0, at: refusedAt ?? .distantPast, on: refusedOn == "5h" ? .fiveHour : refusedOn == "wk" ? .week : .unknown) }
    }

    /// How old the numbers are now. No report time (a levels.json from before it was kept) is as old as can be, never
    /// fresh.
    func age(_ now: Date = Date(), ages: Headline.Ages = QuickChatLevel.ages) -> Headline.Age {
        Headline.age(at ?? .distantPast, now: now, ages: ages)
    }

    /// The one display value (ProfileCore's ProfileDisplay): the numbers as they may show, how old they are (`tier`),
    /// what holds the account back (`heldBack`: while fresh any, else only one whose known end is still ahead) and the
    /// week-only rule (`hasFiveHour`). Judged by `at` and `ages`, or by the age the caller already judged (`age`).
    func display(_ now: Date = Date(), ages: Headline.Ages = QuickChatLevel.ages, age given: Headline.Age? = nil) -> ProfileDisplay {
        var answer = Headline.of(Headline.Owner(), signedIn: true, readAt: at ?? .distantPast, now: now, ages: ages)
        if let given { answer.age = given }
        return ProfileDisplay.make(answer, read: usage, sign: .ok, inUse: true, ages: ages, refusal: refusal, now: now)
    }

    /// What the chat draws and acts on: numbers it already took as the account's now (ProfileStore.shownLevel, or the
    /// answer just given), so they act however long the chat stays open.
    func current(_ now: Date = Date()) -> ProfileDisplay { display(now, age: .fresh) }

    /// What Claude Code said after an answer (rate_limit_event): "seven_day" or "five_hour", the share used as a fraction
    /// (0…1, as Claude Code 2.1.318 takes it from the API's headers; `get_usage` gives percent), refusing or not. Only
    /// the two account-wide windows say anything about the account: a per-model week (seven_day_opus,
    /// seven_day_sonnet), the overage-included week or overage refusing holds back that model or that spend, not the
    /// account (the refused answer says so itself), so it neither sets nor lifts a refusal.
    mutating func apply(type: String?, used: Double?, status: String?, resets: Date?, now: Date = Date()) {
        let pct = used.map { min(100, max(0, $0 * 100)) }
        switch type {
        case "seven_day"?: if let pct { week = pct }; if let resets { weekResets = resets }
        case "five_hour"?: if let pct { fiveHour = pct }; if let resets { fiveHourResets = resets }
        default: break
        }
        let accountWide = type == nil || type == "five_hour" || type == "seven_day"
        guard accountWide else { return }
        if status == "rejected" {
            refusedUntil = resets ?? now.addingTimeInterval(3600); refusedAt = now
            refusedOn = type == "five_hour" ? "5h" : type == "seven_day" ? "wk" : nil
        }
        else if status == "allowed" { refusedUntil = nil; refusedAt = nil; refusedOn = nil }
        at = now
    }

    /// What `get_usage` said: both windows as they are now (0…100), and whether either holds the account back. When
    /// Claude Code says the limits aren't available (`rate_limits` null: its usage endpoint gave nothing), nothing
    /// changes and false comes back: the last numbers stay, as old as they were (never made fresh by an empty answer).
    @discardableResult
    mutating func apply(usage u: QuickChatUsage, now: Date = Date()) -> Bool {
        guard u.available, u.fiveHour?.used != nil || u.week?.used != nil else { return false }
        // a window given is taken whole: its reset as given too (none, for a window that hasn't started), so an old reset
        // already past never hides the number it just gave
        if let w = u.fiveHour, let p = w.used { fiveHour = p; fiveHourResets = w.resets }
        if let w = u.week, let p = w.used { week = p; weekResets = w.resets }
        let lockedIds = [("5h", u.fiveHour), ("wk", u.week)].filter { $0.1?.locked == true }.map(\.0)
        let locked = [u.fiveHour, u.week].compactMap { $0 }.filter(\.locked)
        // a lock lasts until the window that holds it resets (the later one when both do)
        if !locked.isEmpty {
            // the window that holds it, when one does; unknown when both do, or when it differs from the one a refusal
            // still standing was said on
            let was = refusedUntil.map { $0 > now } == true ? refusedOn : nil
            refusedOn = lockedIds.count == 1 && (was == nil || was == lockedIds[0]) ? lockedIds[0] : nil
            refusedUntil = max(refusedUntil ?? .distantPast, locked.compactMap(\.resets).max() ?? now.addingTimeInterval(3600))
            refusedAt = now
        } else if refusedUntil != nil, now.timeIntervalSince(refusedAt ?? .distantPast) >= Self.ages.freshFor,
                  [u.fiveHour?.used, u.week?.used].compactMap({ $0 }).allSatisfy({ $0.rounded() < 100 }),
                  // the answer must speak for the window that refused: both given, or that one among them (get_usage can
                  // give a single window, and the absent one may be the refuser)
                  (u.fiveHour?.used != nil && u.week?.used != nil)
                    || (refusedOn == "5h" && u.fiveHour?.used != nil) || (refusedOn == "wk" && u.week?.used != nil) {
            // the windows have room and nothing is locked: a refusal said before now is over (a raised plan, a reset
            // granted, or one read on another account). One said in the last minutes stays: it may come from a limit
            // get_usage doesn't show, and ends at its own time or on a rate_limit_event "allowed"
            refusedUntil = nil; refusedAt = nil; refusedOn = nil
        }
        at = now
        return true
    }

    /// A share's colour (never grey: the chat draws only numbers that are the account's now).
    static func color(_ p: Double?) -> Color { Color(nsColor: Painter.color(p, stale: false)) }
    static func pct(_ p: Double?) -> String { p.map { "\(Int($0.rounded()))%" } ?? "–" }
}

/// The account's limits in the bar's row, small: two thin bars, the 5-hour window over the week, each in its level's
/// colour, and on the row of the higher one its label before the bars and its share after them, both in that level's
/// colour ("5h ▬ 78%", "wk ▬ 85%", "5h ▬ full"). The label and share each keep one width, so a change never shifts
/// anything. A row short of room drops the share first (`says` .label: "5h ▬"), a narrow one keeps the bars alone
/// (.bars). The pointer on it shows both windows with their resets above it (QCFloat, a window of its own), only what
/// the row doesn't say. (The chat's header has both with their reset times.)
struct QCUsageView: View {
    /// What it says beside its bars: the label and share, the label alone, or nothing.
    enum Says { case all, label, bars }
    let level: QuickChatLevel
    var says = Says.all
    @State private var frame: CGRect = .zero
    @State private var hovering = false
    @Environment(\.qcRendering) private var rendering

    static let font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
    private static func widest(_ words: [String]) -> CGFloat {
        ceil(words.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0) + 1
    }
    /// As wide whatever they say: the label ("5h", "wk") and the share ("9%", "100%", "full").
    static let labelWidth = widest(["5h", "wk"]), shareWidth = widest(["100%", "full"])
    /// The tracks: 24 × 3 pt, the 5-hour window's 3 pt above the week's, the pair centred on the row.
    static let bar: CGFloat = 24, track: CGFloat = 3, trackGap: CGFloat = 3, gap: CGFloat = 3
    static func width(_ says: Says) -> CGFloat {
        switch says {
        case .all: return labelWidth + gap + bar + gap + shareWidth
        case .label: return labelWidth + gap + bar
        case .bars: return bar
        }
    }

    var body: some View {
        let d = level.current()
        let b = d.binding
        let full = d.heldBack
        // three columns (label, tracks, share), each two cells as tall as a track: a word sits exactly level with the
        // track it describes, and the tracks stay one tight pair whatever is known
        HStack(spacing: Self.gap) {
            if says != .bars {
                column(d) { id in
                    slot(b?.id == id ? id : nil, width: Self.labelWidth, align: .trailing, colour: b?.p, mark: "usage-label")
                }
            }
            column(d) { id in track(id, d.share(id)) }
            if says == .all {
                column(d) { id in
                    slot(b.flatMap { $0.id == id ? ($0.p.rounded() >= 100 && full != nil ? "full" : QuickChatLevel.pct($0.p)) : nil },
                         width: Self.shareWidth, align: .leading, colour: b?.p, mark: "usage-share")
                }
            }
        }
        .frame(width: Self.width(says), height: QCSpace.row)
        .contentShape(Rectangle())
        .qcControl()
        .background(rendering ? nil : GeometryReader { g in
            Color.clear
                .onAppear { frame = g.frame(in: .global) }
                .onChange(of: g.frame(in: .global)) { frame = $0 }
        })
        .qcMark("usage")
        .onHover { inside in
            hovering = inside
            if inside { QCFloat.shared.show(AnyView(QCUsageCard(level: level, rowShowsShare: says == .all)), above: frame, align: .trailing) } else { QCFloat.shared.hide() }
        }
        // new numbers while the card is up: the card says them
        .onChange(of: level) { l in if hovering { QCFloat.shared.show(AnyView(QCUsageCard(level: l, rowShowsShare: says == .all)), above: frame, align: .trailing) } }
        .onDisappear { if hovering { hovering = false; QCFloat.shared.hide() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(QCHeaderLine.tooltip(level).replacingOccurrences(of: "\n", with: ". "))
    }

    /// A column's two cells, the 5-hour window's over the week's, each a track tall; the week's alone, centred, for an
    /// account with no 5-hour window (ProfileDisplay.hasFiveHour, the week-only rule).
    private func column<V: View>(_ d: ProfileDisplay, @ViewBuilder _ cell: @escaping (String) -> V) -> some View {
        VStack(spacing: Self.trackGap) {
            if d.hasFiveHour { cell("5h").frame(height: Self.track) }
            cell("wk").frame(height: Self.track)
        }
    }

    /// A window's track: its share in its level's colour on a faint fill, or, with no number yet, a faint outline in
    /// the same place.
    /// (One view whatever is known, only its colours change: the track never goes and comes back.)
    private func track(_ id: String, _ p: Double?) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(QCColor.text.opacity(p == nil ? 0 : 0.13))
            Capsule().fill(QuickChatLevel.color(p)).frame(width: Self.bar * CGFloat(min(100, p ?? 0)) / 100)
            Capsule().strokeBorder(QCColor.text.opacity(p == nil ? 0.16 : 0), lineWidth: 0.75)
        }
        .frame(width: Self.bar, height: Self.track)
        .qcMark("usage-\(id)")
    }

    /// A fixed-width slot: the words in the level's colour, centred on its cell (they stand out of it above and below,
    /// beside the tracks), or nothing.
    @ViewBuilder private func slot(_ words: String?, width: CGFloat, align: Alignment, colour p: Double?, mark: String) -> some View {
        Group {
            if let words {
                Text(words).font(Font(Self.font)).lineLimit(1).fixedSize().foregroundColor(QuickChatLevel.color(p)).qcMark(mark)
            } else {
                Color.clear
            }
        }
        .frame(width: width, alignment: align)
    }
}

/// Both windows under the pointer, in the header's words: each with its bar, share and reset; the share the row
/// already shows is left out (with no share on the row, both shares are given).
struct QCUsageCard: View {
    let level: QuickChatLevel
    var rowShowsShare = true
    /// The window whose share the row already shows, left out of the card: none when the row has the bars alone.
    static func leftOut(_ level: QuickChatLevel, rowShowsShare: Bool) -> String? { rowShowsShare ? level.current().binding?.id : nil }
    var body: some View {
        let b = Self.leftOut(level, rowShowsShare: rowShowsShare)
        let d = level.current()
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 5) {
            if d.hasFiveHour {
                line("5h", d.share("5h"), d.resets("5h"), shown: b == "5h")
            }
            line("wk", d.share("wk"), d.resets("wk"), shown: b == "wk")
        }
        .font(.system(size: 12)).foregroundColor(QCColor.muted)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(QCColor.hex(0x2B2B29)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(QCColor.line))
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private func line(_ id: String, _ p: Double?, _ resets: Date?, shown: Bool) -> some View {
        GridRow {
            Text(id)
            ZStack(alignment: .leading) {
                Capsule().fill(QCColor.text.opacity(0.13))
                Capsule().fill(QuickChatLevel.color(p)).frame(width: 40 * CGFloat(min(100, p ?? 0)) / 100)
            }
            .frame(width: 40, height: 4)
            Text(shown || p == nil ? "" : QuickChatLevel.pct(p)).fontWeight(.semibold).monospacedDigit().foregroundColor(QuickChatLevel.color(p))
            Text(p == nil ? "no numbers yet" : resets.map { "resets \(TimeWords.when($0))" } ?? "")
        }
    }
}
