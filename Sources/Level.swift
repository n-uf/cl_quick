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
            let isFive = (fiveHour ?? 0) > (week ?? 0)
            return FullLimit(id: isFive ? "5h" : "wk", resets: until)
        }
        return nil
    }

    /// The week as last reported, unless it has reset since (then unknown until the next answer).
    func weekNow(_ now: Date = Date()) -> Double? {
        if let r = weekResets, r <= now { return nil }
        return week
    }

    /// Room for a question: not held back, and the week known.
    func room(_ now: Date = Date()) -> Bool { full(now) == nil && weekNow(now) != nil }

    static func color(_ p: Double?) -> Color { Color(nsColor: Painter.color(p, stale: false)) }
    static func pct(_ p: Double?) -> String { p.map { "\(Int($0.rounded()))%" } ?? "–" }
}

/// The level in the chat's account line and the bar: a thin meter in the level's colour, then the number.
struct QCLevelView: View {
    let level: QuickChatLevel
    var long = true

    var body: some View {
        let full = level.full()
        let p = full != nil ? 100 : level.weekNow()
        HStack(spacing: 6) {
            ZStack(alignment: .leading) {
                Capsule().fill(QCColor.text.opacity(0.13))
                Capsule().fill(QuickChatLevel.color(p)).frame(width: 38 * CGFloat(min(100, p ?? 0)) / 100)
            }
            .frame(width: 38, height: 4)
            Text(full != nil ? "full" : QuickChatLevel.pct(p))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundColor(p == nil ? QCColor.muted : QuickChatLevel.color(p))
            if long, let words = words(full) {
                Text(words).font(.system(size: 12)).foregroundColor(QCColor.muted).lineLimit(1)
            }
        }
        .help(full != nil ? "Full" : "The week, as Claude Code last reported it")
    }

    private func words(_ full: FullLimit?) -> String? {
        if let full { return full.resets.map { "\(full.name) · resets \(TimeWords.when($0))" } ?? full.name }
        return level.weekResets.map { "week · resets \(TimeWords.when($0))" }
    }
}
