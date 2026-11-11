// Level: a profile's week (and 5-hour limit) as Claude Code reported it after the last answer on it, its colour, and
// whether a limit holds the account back. Colours as in cl_audit: green, amber from 50%, red from 80%, crimson from 95%.

import AppKit
import SwiftUI

/// Short times, the same everywhere: "11:38" today, "Thu 09:00" within 6 days, "11 Nov" further.
enum TimeWords {
    static func when(_ d: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        let days = abs(cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: now)).day ?? 0)
        f.dateFormat = days == 0 ? "HH:mm" : (1...6).contains(days) ? "EEE HH:mm"
            : cal.component(.year, from: d) == cal.component(.year, from: now) ? "d MMM" : "d MMM yyyy"
        return f.string(from: d)
    }
}

/// The level colours under cl_audit's names, which Faces.swift uses as it is.
enum Painter {
    static let green = NSColor(srgbRed: 0x22 / 255, green: 0xc5 / 255, blue: 0x5e / 255, alpha: 1)
    static let amber = NSColor(srgbRed: 0xf5 / 255, green: 0x9e / 255, blue: 0x0b / 255, alpha: 1)
    static let red = NSColor(srgbRed: 0xef / 255, green: 0x44 / 255, blue: 0x44 / 255, alpha: 1)
    static let crimson = NSColor(displayP3Red: 0xeb / 255, green: 0x44 / 255, blue: 0x5b / 255, alpha: 1)
    static let grey = NSColor(srgbRed: 0x6b / 255, green: 0x72 / 255, blue: 0x80 / 255, alpha: 1)
    static func color(_ p: Double?, stale: Bool) -> NSColor {
        guard let p, !stale else { return grey }
        return p.rounded() >= 95 ? crimson : p >= 80 ? red : p >= 50 ? amber : green
    }
    /// One of twelve segments (0 = first): six green, three amber, two red, the last crimson.
    static func segment(_ i: Int) -> NSColor { i < 6 ? green : i < 9 ? amber : i < 11 ? red : crimson }
}

/// The limit that holds an account back, and when it resets.
struct FullLimit: Equatable {
    let id: String          // "5h" or "wk"
    let resets: Date?
    var name: String { id == "5h" ? "5-hour limit" : "week" }
}

struct QuickChatLevel: Codable, Equatable {
    var week: Double?
    var weekResets: Date?
    var fiveHour: Double?
    var fiveHourResets: Date?
    /// When Claude Code last said the account is refusing (rate_limit_event "rejected"), and until when.
    var refusedUntil: Date?
    /// When Claude Code reported it.
    var at: Date?

    init() {}

    /// What Claude Code said after an answer: "seven_day" or "five_hour", the share used (0…1), refusing or not.
    mutating func apply(type: String?, used: Double?, status: String?, resets: Date?, now: Date = Date()) {
        let pct = used.map { min(100, max(0, $0 * 100)) }
        switch type {
        case "seven_day"?: if let pct { week = pct }; if let resets { weekResets = resets }
        case "five_hour"?: if let pct { fiveHour = pct }; if let resets { fiveHourResets = resets }
        default: break
        }
        if status == "rejected" { refusedUntil = resets ?? now.addingTimeInterval(3600) }
        else if status == "allowed" { refusedUntil = nil }
        at = now
    }

    /// What `get_usage` said: both windows as they are now (0…100), and whether either holds the account back. When
    /// Claude Code says the limits aren't available, nothing changes: the last numbers stay.
    mutating func apply(usage u: QuickChatUsage, now: Date = Date()) {
        guard u.available, u.fiveHour != nil || u.week != nil else { return }
        if let w = u.fiveHour { if let p = w.used { fiveHour = p }; if let r = w.resets { fiveHourResets = r } }
        if let w = u.week { if let p = w.used { week = p }; if let r = w.resets { weekResets = r } }
        let locked = [u.fiveHour, u.week].compactMap { $0 }.filter(\.locked)
        // a lock lasts until the window that holds it resets (the later one when both do). No lock here never lifts a
        // refusal Claude Code made: it may come from a limit get_usage files elsewhere, so it ends at its own time or
        // on a rate_limit_event "allowed"
        if !locked.isEmpty { refusedUntil = max(refusedUntil ?? .distantPast, locked.compactMap(\.resets).max() ?? now.addingTimeInterval(3600)) }
        at = now
    }

    private static func holding(_ p: Double?, _ resets: Date?, _ now: Date) -> Bool {
        (p.map { $0.rounded() >= 100 } ?? false) && (resets.map { $0 > now } ?? true)
    }

    /// The full limit that holds the account back now, if any: of the full ones, the one that resets last.
    func full(_ now: Date = Date()) -> FullLimit? {
        let five = Self.holding(fiveHour, fiveHourResets, now), wk = Self.holding(week, weekResets, now)
        if five && wk { return (fiveHourResets ?? .distantFuture) > (weekResets ?? .distantFuture) ? FullLimit(id: "5h", resets: fiveHourResets) : FullLimit(id: "wk", resets: weekResets) }
        if wk { return FullLimit(id: "wk", resets: weekResets) }
        if five { return FullLimit(id: "5h", resets: fiveHourResets) }
        if let until = refusedUntil, until > now {
            // refused with neither window reported full: name the one that can be. A window known to have room isn't
            // it (a week at 53% never is); with both known, the fuller; with neither, the 5-hour one, which fills far
            // more often. (The old guess compared an unknown 5-hour share as 0 and named the week.)
            let five = fiveHourNow(now), wk = weekNow(now)
            let isFive: Bool
            switch (five, wk) {
            case let (f?, w?): isFive = f >= w
            case (nil, _?): isFive = true
            case let (f?, nil): isFive = f.rounded() >= 100
            case (nil, nil): isFive = true
            }
            return FullLimit(id: isFive ? "5h" : "wk", resets: until)
        }
        return nil
    }

    /// The notice for a full limit, naming the window that is full as the header shows it, and when it resets:
    /// "Main's 5-hour limit is full, resets 23:20." / "Main's week is full, resets Thu 19:00.". With no numbers at all it
    /// names no window ("Main's limit is full.") rather than guess one.
    static func fullSentence(_ level: QuickChatLevel?, who: String, now: Date = Date()) -> String {
        guard let f = level?.full(now) else { return "\(who)'s limit is full." }
        return "\(who)'s \(f.name) is full" + (f.resets.map { ", resets " + TimeWords.when($0) } ?? "") + "."
    }

    /// The week as last reported, unless it has reset since (then unknown until the next answer).
    func weekNow(_ now: Date = Date()) -> Double? {
        if let r = weekResets, r <= now { return nil }
        return week
    }

    /// The 5-hour session window as last reported, unless it has reset since.
    func fiveHourNow(_ now: Date = Date()) -> Double? {
        if let r = fiveHourResets, r <= now { return nil }
        return fiveHour
    }

    /// Room for a question: not held back, and the week known.
    func room(_ now: Date = Date()) -> Bool { full(now) == nil && weekNow(now) != nil }

    static func color(_ p: Double?) -> Color { Color(nsColor: Painter.color(p, stale: false)) }
    static func pct(_ p: Double?) -> String { p.map { "\(Int($0.rounded()))%" } ?? "–" }

    /// The window closest to full now: a full one (it holds the account back), else the higher share, the 5-hour
    /// window on a tie; nil while neither is known. What the bar's indicator and the profile's dot show, so neither reads
    /// as "plenty left" while the other window is nearly full.
    func binding(_ now: Date = Date()) -> (id: String, p: Double)? {
        if let f = full(now) { return (f.id, 100) }
        switch (fiveHourNow(now), weekNow(now)) {
        case let (a?, b?): return a >= b ? ("5h", a) : ("wk", b)
        case let (a?, nil): return ("5h", a)
        case let (nil, b?): return ("wk", b)
        default: return nil
        }
    }
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
        let b = level.binding()
        let full = level.full()
        let p5 = full?.id == "5h" ? 100 : level.fiveHourNow(), pw = full?.id == "wk" ? 100 : level.weekNow()
        // three columns (label, tracks, share), each two cells as tall as a track: a word sits exactly level with the
        // track it describes, and the tracks stay one tight pair whatever is known
        HStack(spacing: Self.gap) {
            if says != .bars {
                column { id in
                    slot(b?.id == id ? id : nil, width: Self.labelWidth, align: .trailing, colour: b?.p, mark: "usage-label")
                }
            }
            column { id in track(id, id == "5h" ? p5 : pw) }
            if says == .all {
                column { id in
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

    /// A column's two cells, the 5-hour window's over the week's, each a track tall.
    private func column<V: View>(@ViewBuilder _ cell: @escaping (String) -> V) -> some View {
        VStack(spacing: Self.trackGap) {
            cell("5h").frame(height: Self.track)
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
    static func leftOut(_ level: QuickChatLevel, rowShowsShare: Bool) -> String? { rowShowsShare ? level.binding()?.id : nil }
    var body: some View {
        let b = Self.leftOut(level, rowShowsShare: rowShowsShare)
        let full = level.full()
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 5) {
            line("5h", full?.id == "5h" ? 100 : level.fiveHourNow(), full?.id == "5h" ? full?.resets : level.fiveHourResets, shown: b == "5h")
            line("wk", full?.id == "wk" ? 100 : level.weekNow(), full?.id == "wk" ? full?.resets : level.weekResets, shown: b == "wk")
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
