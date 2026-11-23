// StatusIcon: the menu bar icon carries the usage of one account, the account in use on the profile the shortcut opens
// (Make default; else the first profile). Its chat bubble fills from the bottom with the fuller limit's share (the
// 5-hour window or the week, whichever is closer to full: ProfileDisplay.binding), in the menu bar's own colour, so the
// amount reads from the height in any look and for colour-blind eyes. Colour comes in only when it matters: amber from
// 80%, crimson when a limit holds the account back, with the time to its reset beside the bubble ("1h 42m"). No numbers
// (none yet, signed out, a broken sign-in, or every window reset since): a dashed outline. Nothing else in the menu bar
// changes width, but for that countdown.
//
// The numbers are the ones the menu shows (levels.json, Claude Code's `get_usage`, the same ProfileCore rules): last
// known ones too, however old, as long as their window hasn't reset since; the menu reads fresh ones as it opens.
// Nothing new is read for the icon. It is redrawn when the numbers or the profiles change, when the menu opens, and
// every 30 seconds (a reset that passes, the countdown).

import AppKit
import Combine
import ProfileCore

/// What the icon shows, as numbers and words (the image is drawn from it; the checks read it).
struct QCStatusIconState: Equatable {
    /// The fuller limit's share, 0…100; nil: no numbers (the dashed outline).
    var p: Double?
    /// 80% or more: the fill is amber.
    var warn = false
    /// A limit holds the account back: the bubble is full, crimson, with `countdown` beside it.
    var full = false
    /// "1h 42m" to the reset while full; nil when it isn't known.
    var countdown: String?
    /// For VoiceOver: "cl_quick, Main: 46% of the 5-hour limit used".
    var spoken = "cl_quick"

    static let warnFrom: Double = 80

    /// The icon for a profile's account in use: `level` its numbers as last reported (nil: none), `signedIn` false when
    /// no account is signed in or its sign-in is broken.
    static func make(name: String?, level: QuickChatLevel?, signedIn: Bool, now: Date = Date()) -> QCStatusIconState {
        let who = name.map { "cl_quick, \($0)" } ?? "cl_quick"
        guard signedIn, let d = level?.display(now) else { return QCStatusIconState(spoken: who + ": no usage numbers") }
        // what holds the account back: while fresh any, else a saved full limit whose end is still ahead
        if let h = d.heldBack {
            let left = h.resets.map { TimeWords.countdown($0, now: now) }
            return QCStatusIconState(p: 100, full: true, countdown: left,
                                     spoken: who + ": \(h.name) full" + (left.map { ", back in \($0)" } ?? ""))
        }
        guard let b = d.binding else { return QCStatusIconState(spoken: who + ": no usage numbers") }
        let p = min(max(b.p, 0), 100)
        let window = b.id == "5h" ? "5-hour limit" : "week"
        return QCStatusIconState(p: p, warn: p.rounded() >= warnFrom,
                                 spoken: who + ": \(QuickChatLevel.pct(p)) of the \(window) used" + (d.tier == .fresh ? "" : ", last known"))
    }
}

// MARK: - The image

enum QCStatusIconImage {
    /// The icon's size in points, as an SF Symbol in the menu bar.
    static let size = NSSize(width: 16, height: 16)
    static let amber = NSColor(srgbRed: 0xff / 255, green: 0x9f / 255, blue: 0x0a / 255, alpha: 1)

    /// The bubble in a 16-point square, y down: a rounded body 14 × 10.4 and a tail at the lower left.
    static func bubble() -> NSBezierPath {
        let r: CGFloat = 2.2, l: CGFloat = 1, t: CGFloat = 1.5, rt: CGFloat = 15, b: CGFloat = 11.9
        let p = NSBezierPath()
        p.move(to: NSPoint(x: l + r, y: t))
        p.appendArc(from: NSPoint(x: rt, y: t), to: NSPoint(x: rt, y: t + r), radius: r)
        p.appendArc(from: NSPoint(x: rt, y: b), to: NSPoint(x: rt - r, y: b), radius: r)
        p.line(to: NSPoint(x: 7.1, y: b))
        p.line(to: NSPoint(x: 4.1, y: 14.4))
        p.line(to: NSPoint(x: 4.1, y: b))
        p.appendArc(from: NSPoint(x: l, y: b), to: NSPoint(x: l, y: b - r), radius: r)
        p.appendArc(from: NSPoint(x: l, y: t), to: NSPoint(x: l + r, y: t), radius: r)
        p.close()
        p.lineWidth = 1.3
        p.lineJoinStyle = .round
        return p
    }

    /// The icon for a state. Plain (no colour) it is a template image, so macOS draws it in the menu bar's colour; amber
    /// and crimson ones aren't, and draw the outline in the label colour of the menu bar they are drawn on.
    static func image(_ s: QCStatusIconState) -> NSImage {
        let colour: NSColor? = s.full ? Painter.crimson : s.warn ? amber : nil
        let img = NSImage(size: size, flipped: true) { _ in
            let ink = colour == nil ? NSColor.black : NSColor.labelColor
            let path = bubble()
            guard let p = s.p else {
                // no numbers: a dashed outline, dimmed
                ink.withAlphaComponent(0.55).setStroke()
                path.setLineDash([1.6, 1.4], count: 2, phase: 0)
                path.stroke()
                return true
            }
            // the share is the height inside the body's outline (from 11.25 up to 2.15 at 100%), so 12% still shows
            // above the stroke; the tail fills with any share above none
            if p > 0 {
                let top = 11.25 - 9.1 * CGFloat(p) / 100
                NSGraphicsContext.saveGraphicsState()
                path.addClip()
                (colour ?? ink.withAlphaComponent(0.85)).setFill()
                NSRect(x: 0, y: top, width: size.width, height: 14.4 - top).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
            ink.setStroke()
            path.stroke()
            return true
        }
        img.isTemplate = colour == nil
        img.accessibilityDescription = s.spoken
        return img
    }
}

// MARK: - The menu bar item

/// Keeps the menu bar item's icon (and the countdown beside it) in step with the numbers.
final class QCStatusIcon {
    private weak var button: NSStatusBarButton?
    /// The profile whose account the icon shows: the default one, else the first.
    private let profile: () -> Profile?
    private let store: ProfileStore
    private var watch: Set<AnyCancellable> = []
    private var timer: Timer?
    private(set) var state = QCStatusIconState(spoken: "cl_quick")

    init(button: NSStatusBarButton?, store: ProfileStore = .shared, profile: @escaping () -> Profile?) {
        self.button = button
        self.store = store
        self.profile = profile
        button?.imagePosition = .imageLeading
        button?.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        // the store says it will change before it has: read it once it has
        store.$levels.map { _ in () }.merge(with: store.$profiles.map { _ in () }).sink { [weak self] _ in
            DispatchQueue.main.async { self?.update() }
        }.store(in: &watch)
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.update() }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        timer = t
        update(force: true)
    }

    deinit { timer?.invalidate() }

    /// Draws the icon again when what it shows has changed.
    func update(now: Date = Date(), force: Bool = false) {
        let p = profile()
        let signedIn = p.map { ClaudeFolder.account($0.path) != nil && store.signInProblem($0) == nil } ?? false
        let s = QCStatusIconState.make(name: p?.name, level: p.flatMap { store.level(of: $0) }, signedIn: signedIn, now: now)
        guard force || s != state else { return }
        state = s
        button?.image = QCStatusIconImage.image(s)
        button?.title = s.countdown.map { " " + $0 } ?? ""
        button?.setAccessibilityLabel(s.spoken)
    }
}

// MARK: - A picture

/// `--render-icon OUT.png`: the icon at each state (no numbers, 12%, 46%, 68%, 88%, full with its countdown) on a dark
/// and a light menu bar, at twice the size.
enum QCStatusIconRender {
    static func write(to path: String) {
        _ = NSApplication.shared
        let now = Date()
        func level(_ five: Double?, _ week: Double?) -> QuickChatLevel {
            var l = QuickChatLevel()
            l.fiveHour = five; l.fiveHourResets = five == nil ? nil : now.addingTimeInterval(102 * 60)
            l.week = week; l.weekResets = week == nil ? nil : now.addingTimeInterval(29 * 3600)
            l.at = now.addingTimeInterval(-20)
            return l
        }
        let states: [QCStatusIconState] = [
            .make(name: "Main", level: nil, signedIn: true, now: now),
            .make(name: "Main", level: level(12, 8), signedIn: true, now: now),
            .make(name: "Main", level: level(46, 24), signedIn: true, now: now),
            .make(name: "Main", level: level(31, 68), signedIn: true, now: now),
            .make(name: "Main", level: level(88, 40), signedIn: true, now: now),
            .make(name: "Main", level: level(100, 52), signedIn: true, now: now),
        ]
        let scale: CGFloat = 2, cell: CGFloat = 70, barH: CGFloat = 24
        let width = cell * CGFloat(states.count) + 40          // room for the full one's countdown
        let size = NSSize(width: width * scale, height: barH * 2 * scale)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.scaleBy(x: scale, y: scale)
        for (row, dark) in [true, false].enumerated() {
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
            let y = CGFloat(1 - row) * barH
            (dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
            NSRect(x: 0, y: y, width: width, height: barH).fill()
            appearance.performAsCurrentDrawingAppearance {
                let fg = dark ? NSColor.white : NSColor.black
                for (i, s) in states.enumerated() {
                    let img = QCStatusIconImage.image(s)
                    let r = NSRect(x: CGFloat(i) * cell + 10, y: y + (barH - 16) / 2, width: 16, height: 16)
                    if img.isTemplate {
                        // as the menu bar draws a template image: its shape in the bar's colour
                        let tinted = NSImage(size: img.size, flipped: false) { b in
                            img.draw(in: b); fg.set(); b.fill(using: .sourceAtop); return true
                        }
                        tinted.draw(in: r)
                    } else {
                        img.draw(in: r)
                    }
                    if let c = s.countdown {
                        (" " + c as NSString).draw(at: NSPoint(x: r.maxX + 1, y: y + 5),
                                                   withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular), .foregroundColor: fg])
                    }
                }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
