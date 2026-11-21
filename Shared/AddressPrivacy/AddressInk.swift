// The AppKit layer of AddressPrivacy: drawing an address in a view's draw(_:) or any NSGraphicsContext (a menu row, a Dock
// tile image), and an address on its own line (an alert's accessory view). What is drawn blurred is the stand-in
// (AddressText.standIn), never the address; the address is drawn only while it is readable.
//
// Layout: an address is given the STAND-IN's room (`room`) and no more, whatever the address, so its length is never in a
// neighbour's position. A readable address longer than that is truncated (a tail ellipsis), a shorter one leaves room.

import AppKit
import CoreImage

/// Draws addresses in one font, for a view's `draw(_:)` (or any current graphics context): the address sharp while it is
/// readable, else the stand-in blurred (the blurred picture is made once per colour and kept; `reset()` drops them, for an
/// appearance change).
public final class AddressInk {
    /// How far the blur reaches around the text: the pictures are this much larger on every side.
    public static let blurPad: CGFloat = 6
    /// The blur's radius on the picture's own text (a Gaussian, so it reads as a smudge and nothing more).
    public static let sigma: CGFloat = 2.4

    public let font: NSFont
    public init(font: NSFont) { self.font = font }

    private var cache: [(NSColor, NSImage)] = []

    /// The room an address is given while it is hidden: the stand-in's width in this font (never more, never less).
    public var room: CGFloat { ceil((AddressText.standIn as NSString).size(withAttributes: [.font: font]).width) }
    /// The room for an address under the setting: the stand-in's while the blur is on, whatever the address; its own width
    /// while the blur is off (there is nothing to hide then, and no reason to cut it).
    public func room(for address: String, blur: Bool) -> CGFloat {
        blur ? room : ceil((address as NSString).size(withAttributes: [.font: font]).width)
    }
    /// The height of a line of text in this font.
    public var lineHeight: CGFloat { ceil(("Ag" as NSString).size(withAttributes: [.font: font]).height) }

    /// Drops the pictures made (the colours of a dynamic appearance changed).
    public func reset() { cache = [] }

    /// Draws the address (`readable`: its own text, sharp, truncated to the room) or the stand-in (blurred) with its middle
    /// at `midY`, from `x` rightwards, or ending at `x` with `alignRight`. The colour is the caller's. Nothing is animated:
    /// what is drawn changes instantly.
    /// `blur`: the setting (true: the room is the stand-in's; false: the address's own, uncut).
    public func draw(address: String, readable: Bool, color: NSColor, x: CGFloat, midY: CGFloat, alignRight: Bool = false, blur: Bool = true) {
        let w = room(for: address, blur: blur)
        if readable {
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byTruncatingTail
            style.alignment = alignRight ? .right : .left
            let h = lineHeight
            (address as NSString).draw(in: NSRect(x: alignRight ? x - w : x, y: midY - h / 2, width: w, height: h),
                                       withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
        } else if let img = standIn(color) {
            let left = alignRight ? x - img.size.width + Self.blurPad : x - Self.blurPad
            img.draw(in: NSRect(x: left, y: midY - img.size.height / 2, width: img.size.width, height: img.size.height))
        }
    }

    /// The stand-in blurred, in a colour (made once).
    public func standIn(_ color: NSColor) -> NSImage? {
        if let hit = cache.first(where: { $0.0 == color }) { return hit.1 }
        guard let img = Self.blurred(AddressText.standIn, color: color, font: font) else { return nil }
        cache.append((color, img))
        return img
    }

    /// Text drawn and blurred (a Gaussian blur), as a picture with `blurPad` of room on every side. Callers pass the
    /// stand-in: the blur of real text keeps what it says.
    public static func blurred(_ text: String, color: NSColor, font: NSFont) -> NSImage? {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let s = (text as NSString).size(withAttributes: attrs)
        let size = NSSize(width: ceil(s.width) + 2 * blurPad, height: ceil(s.height) + 2 * blurPad)
        let sharp = NSImage(size: size, flipped: false) { _ in
            (text as NSString).draw(at: NSPoint(x: blurPad, y: blurPad), withAttributes: attrs)
            return true
        }
        guard let cg = sharp.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let ci = CIImage(cgImage: cg)
        let soft = ci.clampedToExtent().applyingGaussianBlur(sigma: Double(sigma)).cropped(to: ci.extent)
        let out = NSImage(size: size)
        out.addRepresentation(NSCIImageRep(ciImage: soft))
        return out
    }
}

/// An address on its own line in an alert's accessory view (an NSAlert's text can't blur): the stand-in blurred, the
/// address sharp while the pointer is on it. Its width is the stand-in's, whatever the address (a longer address is
/// truncated while revealed). Its accessibility label is "hidden address" while blurred. The reveal ends when the pointer
/// leaves, the alert closes, the window loses focus or the app is deactivated.
public final class AddressLabel: NSView {
    public let address: String
    /// A test override of the setting (nil: the app's, AddressPrivacy.shared).
    public let blur: Bool?
    /// The pointer is on it: drawn readable.
    public private(set) var revealed = false

    public static let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    private let ink = AddressInk(font: AddressLabel.font)
    private var observers: [NSObjectProtocol] = []
    /// The frame holds the blur's reach on every side.
    public static var pad: CGFloat { AddressInk.blurPad }

    public init(address: String, blur: Bool? = nil) {
        self.address = address
        self.blur = blur
        let ink = AddressInk(font: Self.font)
        let on = blur ?? AddressPrivacy.shared.blur
        super.init(frame: NSRect(x: 0, y: 0, width: ink.room(for: address, blur: on) + 2 * Self.pad, height: ink.lineHeight + 2 * Self.pad))
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(AddressText.sentence(address: address, blur: on))
    }
    public required init?(coder: NSCoder) { fatalError("not from a nib") }
    deinit { observers.forEach(NotificationCenter.default.removeObserver); poll?.invalidate() }

    public override var isFlipped: Bool { true }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    public override func mouseEntered(with e: NSEvent) { reveal(true) }
    public override func mouseExited(with e: NSEvent) { reveal(false) }
    public func reveal(_ on: Bool) { guard on != revealed else { return }; revealed = on; needsDisplay = true }

    // A modal alert (NSAlert.runModal) gets no enter and exit from the tracking area above, so while the label is in a
    // window the pointer's place is also read every 50 ms, in every run loop mode (the modal one included), and the
    // address is readable exactly while the pointer is on the label, the alert is on screen and the app is active.
    private var poll: Timer?
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        poll?.invalidate(); poll = nil
        observers.forEach(NotificationCenter.default.removeObserver); observers = []
        guard let w = window else { reveal(false); return }
        w.acceptsMouseMovedEvents = true
        // the window closes or loses focus, the app is deactivated or hidden, a menu opens: the reveal ends
        let nc = NotificationCenter.default
        for (name, object) in [(NSWindow.willCloseNotification, w as AnyObject?), (NSWindow.didResignKeyNotification, w),
                               (NSApplication.didResignActiveNotification, nil), (NSApplication.didHideNotification, nil),
                               (NSMenu.didBeginTrackingNotification, nil)] {
            observers.append(nc.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in self?.reveal(false) })
        }
        var shown = false
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] t in
            guard let self, let w = self.window else { t.invalidate(); return }
            if w.isVisible { shown = true; self.follow(inWindow: NSApp.isActive ? w.mouseLocationOutsideOfEventStream : nil) }
            else if shown { t.invalidate(); self.reveal(false) }     // the alert has closed
        }
        RunLoop.main.add(t, forMode: .common)
        poll = t
    }
    /// The pointer at a point of the window (nil: it is nowhere): the address is readable while it is on the label.
    public func follow(inWindow p: NSPoint?) { reveal(p.map { bounds.contains(convert($0, from: nil)) } ?? false) }

    /// Whether the address is blurred now: the override, or the app's setting.
    public var blurred: Bool { blur ?? AddressPrivacy.shared.blur }
    /// Drawn readable: the pointer is on it, or addresses are not blurred.
    public var sharp: Bool { revealed || !blurred }
    /// The text drawn now: the address while readable, else the stand-in (never any part of the address).
    public var drawnText: String { AddressText.drawn(address: address, revealed: sharp, blur: true) }

    public override func draw(_ dirty: NSRect) {
        ink.draw(address: address, readable: sharp, color: .labelColor, x: Self.pad, midY: bounds.midY, blur: blurred)
    }
    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        ink.reset()
        needsDisplay = true
    }
}
