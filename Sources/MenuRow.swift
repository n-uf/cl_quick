// QCProfileMenuRow: a profile's row in the profile menu (QCMenu.profiles), a view of its own so it can hold the address
// of the profile's account in use, blurred at rest and readable only while the pointer is on it. It draws what a native
// item draws (the check mark, the level's dot, the name with its week under it, the menu's own highlight) and leaves the
// rest to the menu: the arrow keys highlight it, Return picks it (the item's action), a click picks it.
//
// The rule for addresses: blurred on screen everywhere, masked only as words (VoiceOver, an item's title, the checks).
// This file draws them blurred in the menus (QCProfileMenuRow, QCSwitchMenuRow) and in an alert's accessory view
// (QCAddressLabel); the chat's views do it in AddressViews.swift.

import AppKit
import CoreImage

final class QCProfileMenuRow: NSView {
    let title: String
    let detail: String
    let dot: NSColor?
    let on: Bool
    /// The address of the profile's account in use (never a standby one's), or nil when none is known.
    let address: String?
    let pick: () -> Void

    /// The pointer is on the address: it is drawn readable.
    private(set) var revealed = false
    /// The address is drawn readable: the pointer is on it, or addresses are not blurred (AddressPrivacy).
    var sharp: Bool { revealed || !AddressPrivacy.shared.blur }
    /// The pointer is on the row: the copy glyph shows after the address.
    private(set) var rowHover = false
    /// The pointer is on the copy glyph.
    private(set) var copyHover = false
    /// "Copied" shows in the address's place until then.
    private(set) var copiedUntil: Date?
    /// For pictures: drawn as if the menu highlighted it.
    var highlighted = false
    /// Where a copy goes (the general pasteboard; a check passes its own).
    var pasteboard = NSPasteboard.general

    static let height: CGFloat = 40
    static let titleFont = NSFont.menuFont(ofSize: 0)
    static let detailFont = NSFont.menuFont(ofSize: 11)
    static let addressFont = NSFont.systemFont(ofSize: 11.5)
    static let checkX: CGFloat = 11, dotX: CGFloat = 27, textX: CGFloat = 41, trailing: CGFloat = 12
    static let copySize: CGFloat = 14, copyGap: CGFloat = 6, addressGap: CGFloat = 18
    static let copiedFor: TimeInterval = 1.1

    init(title: String, detail: String, dot: NSColor?, on: Bool, address: String?, pick: @escaping () -> Void) {
        self.title = title; self.detail = detail; self.dot = dot; self.on = on; self.address = address; self.pick = pick
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width(title: title, detail: detail, address: address), height: Self.height))
        autoresizingMask = [.width]
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel(title + ", " + detail + (on ? ", in use" : ""))
    }
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    override var isFlipped: Bool { true }

    /// The least width that shows it all: the name with the address and its copy glyph after it, or the week.
    static func width(title: String, detail: String, address: String?) -> CGFloat {
        let t = (title as NSString).size(withAttributes: [.font: titleFont]).width
        let d = (detail as NSString).size(withAttributes: [.font: detailFont]).width
        let a = address.map { ($0 as NSString).size(withAttributes: [.font: addressFont]).width + addressGap + copySize + copyGap } ?? 0
        return ceil(textX + max(t + a, d) + trailing)
    }

    private var addressWidth: CGFloat { address.map { ceil(($0 as NSString).size(withAttributes: [.font: Self.addressFont]).width) } ?? 0 }
    /// Where the copy glyph is: at the row's right, on the name's line.
    var copyRect: NSRect {
        NSRect(x: bounds.maxX - Self.trailing - Self.copySize, y: 5, width: Self.copySize, height: 18)
    }
    /// Where the address is: just before the copy glyph, on the name's line.
    var addressRect: NSRect {
        NSRect(x: copyRect.minX - Self.copyGap - addressWidth, y: 5, width: addressWidth, height: 18)
    }

    // MARK: the pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    // (entering and leaving also redraw: the menu's highlight follows the pointer)
    override func mouseEntered(with e: NSEvent) { hover(at: convert(e.locationInWindow, from: nil)); needsDisplay = true }
    override func mouseMoved(with e: NSEvent) { hover(at: convert(e.locationInWindow, from: nil)) }
    override func mouseExited(with e: NSEvent) { hover(at: nil); needsDisplay = true }

    /// The pointer at a point of the row (nil: it left): only on the address (with a 3 pt margin) is it readable.
    func hover(at p: NSPoint?) {
        let r = address != nil && p.map { addressRect.insetBy(dx: -3, dy: -3).contains($0) } == true
        let c = address != nil && p.map { copyRect.insetBy(dx: -3, dy: -3).contains($0) } == true
        let h = p != nil
        guard r != revealed || c != copyHover || h != rowHover else { return }
        revealed = r; copyHover = c; rowHover = h
        needsDisplay = true
    }

    /// A click is a release on the row: one released outside it (the press was on it) does nothing.
    override func mouseUp(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        guard bounds.contains(p) else { return }
        press(at: p)
    }

    /// A click at a point of the row: on the copy glyph it copies the address and says "Copied" (the menu stays open);
    /// anywhere else it closes the menu and picks the profile.
    func press(at p: NSPoint) {
        if let a = address, copyRect.insetBy(dx: -3, dy: -3).contains(p) {
            guard Self.copy(a, to: pasteboard) else { return }
            let until = Date().addingTimeInterval(Self.copiedFor)
            copiedUntil = until
            needsDisplay = true
            // a timer in the menu's own run loop mode too, or "Copied" would stay until the menu closes
            let t = Timer(timeInterval: Self.copiedFor, repeats: false) { [weak self] _ in
                guard let self, self.copiedUntil == until else { return }
                self.copiedUntil = nil
                self.needsDisplay = true
            }
            RunLoop.main.add(t, forMode: .common)
            return
        }
        enclosingMenuItem?.menu?.cancelTracking()
        // once the menu has closed, not inside its tracking loop
        let pick = self.pick
        DispatchQueue.main.async { pick() }
    }

    /// VoiceOver's press picks the profile, as a click does.
    override func accessibilityPerformPress() -> Bool {
        enclosingMenuItem?.menu?.cancelTracking()
        let pick = self.pick
        DispatchQueue.main.async { pick() }
        return true
    }

    /// For pictures: "Copied" in the address's place, without touching the pasteboard.
    func showCopiedForPicture() { copiedUntil = .distantFuture; needsDisplay = true }

    /// Puts the whole address on the pasteboard as plain text (cleared first). An empty one puts nothing there (false).
    /// (`pasteboard`: the general one; a check passes its own.)
    @discardableResult
    static func copy(_ address: String, to pasteboard: NSPasteboard = .general) -> Bool {
        let a = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty else { return false }
        pasteboard.clearContents()
        return pasteboard.setString(a, forType: .string)
    }

    // MARK: drawing

    override func draw(_ dirty: NSRect) {
        let lit = highlighted || enclosingMenuItem?.isHighlighted == true
        if lit {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0), xRadius: 4, yRadius: 4).fill()
        }
        let fg: NSColor = lit ? .selectedMenuItemTextColor : .labelColor
        let sub: NSColor = lit ? NSColor.selectedMenuItemTextColor.withAlphaComponent(0.75) : .secondaryLabelColor
        let line1 = NSRect(x: 0, y: 5, width: bounds.width, height: 18)
        if on, let check = Self.symbol("checkmark", size: 11, weight: .semibold, color: fg) {
            check.draw(in: NSRect(x: Self.checkX, y: line1.midY - check.size.height / 2, width: check.size.width, height: check.size.height))
        }
        if let dot {
            dot.setFill()
            NSBezierPath(ovalIn: NSRect(x: Self.dotX, y: line1.midY - 4, width: 8, height: 8)).fill()
        }
        let titleSize = (title as NSString).size(withAttributes: [.font: Self.titleFont])
        (title as NSString).draw(at: NSPoint(x: Self.textX, y: line1.midY - titleSize.height / 2), withAttributes: [.font: Self.titleFont, .foregroundColor: fg])
        (detail as NSString).draw(at: NSPoint(x: Self.textX, y: 23), withAttributes: [.font: Self.detailFont, .foregroundColor: sub])
        guard let address else { return }
        let a = addressRect
        if copiedUntil != nil {
            let words = "Copied" as NSString
            let s = words.size(withAttributes: [.font: Self.addressFont])
            words.draw(at: NSPoint(x: a.maxX - s.width, y: a.midY - s.height / 2), withAttributes: [.font: Self.addressFont, .foregroundColor: fg])
            if let tick = Self.symbol("checkmark", size: 10, weight: .bold, color: fg) {
                tick.draw(in: NSRect(x: copyRect.midX - tick.size.width / 2, y: copyRect.midY - tick.size.height / 2, width: tick.size.width, height: tick.size.height))
            }
            return
        }
        if sharp {
            let s = (address as NSString).size(withAttributes: [.font: Self.addressFont])
            (address as NSString).draw(at: NSPoint(x: a.minX, y: a.midY - s.height / 2), withAttributes: [.font: Self.addressFont, .foregroundColor: sub])
        } else if let img = blurredAddress(sub, lit: lit) {
            img.draw(in: NSRect(x: a.minX - Self.blurPad, y: a.midY - img.size.height / 2, width: img.size.width, height: img.size.height))
        }
        if rowHover || lit, let copy = Self.symbol("doc.on.doc", size: 11, weight: .regular, color: copyHover ? fg : sub) {
            copy.draw(in: NSRect(x: copyRect.midX - copy.size.width / 2, y: copyRect.midY - copy.size.height / 2, width: copy.size.width, height: copy.size.height))
        }
    }

    private static func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: weight).applying(.init(paletteColors: [color])))
    }

    /// The blurred address, made once for each look (lit or not), not on every draw; made again if the appearance
    /// changes (its colours are the system's).
    private var blurCache: [Bool: NSImage] = [:]
    private func blurredAddress(_ color: NSColor, lit: Bool) -> NSImage? {
        guard let address else { return nil }
        if let img = blurCache[lit] { return img }
        let img = Self.blurred(address, color: color)
        blurCache[lit] = img
        return img
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        blurCache = [:]
        needsDisplay = true
    }

    static let blurPad: CGFloat = 6
    /// The address drawn and blurred (a Gaussian blur, so it reads as an address's shape and nothing more), in the
    /// address font or the one given.
    static func blurred(_ text: String, color: NSColor, font: NSFont = addressFont) -> NSImage? {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let s = (text as NSString).size(withAttributes: attrs)
        let size = NSSize(width: ceil(s.width) + 2 * blurPad, height: ceil(s.height) + 2 * blurPad)
        let sharp = NSImage(size: size, flipped: false) { _ in
            (text as NSString).draw(at: NSPoint(x: blurPad, y: blurPad), withAttributes: attrs)
            return true
        }
        guard let cg = sharp.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let ci = CIImage(cgImage: cg)
        let soft = ci.clampedToExtent().applyingGaussianBlur(sigma: 2.4).cropped(to: ci.extent)
        let rep = NSCIImageRep(ciImage: soft)
        let out = NSImage(size: size)
        out.addRepresentation(rep)
        return out
    }
}

/// A line of a profile's Switch account › submenu: "Switch to " + the standby account's address + "…", drawn by hand
/// like QCProfileMenuRow (and with its blur): the address is blurred at rest and sharp while the line is highlighted
/// (the menu's highlight follows the pointer and the arrow keys). A click closes the menu and runs the switch, as the
/// item's action does for Return. While a sign-in for the profile is waited for the line is dimmed and does nothing.
final class QCSwitchMenuRow: NSView {
    /// The whole address, for drawing only; the words and the accessibility label hold it masked.
    let address: String
    let enabled: Bool
    let pick: () -> Void
    /// For pictures: drawn as if the menu highlighted it.
    var highlighted = false

    static let font = NSFont.menuFont(ofSize: 0)
    /// As tall as the blurred address's picture (the text's height and the blur's reach above and below), so the blur
    /// is never cut; a little taller than a native item.
    static let height: CGFloat = ceil(("Ag" as NSString).size(withAttributes: [.font: font]).height) + 2 * QCProfileMenuRow.blurPad
    static let lead: CGFloat = 14, trailing: CGFloat = 14
    static let before = "Switch to ", after = "…"

    /// The line as words (VoiceOver, the item's title): the address masked.
    static func words(_ address: String) -> String { before + AddressPrivacy.words(address) + after }

    init(address: String, enabled: Bool, pick: @escaping () -> Void) {
        self.address = address; self.enabled = enabled; self.pick = pick
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width(address), height: Self.height))
        autoresizingMask = [.width]
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel(Self.words(address))
        setAccessibilityEnabled(enabled)
    }
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    override var isFlipped: Bool { true }

    private static func w(_ s: String) -> CGFloat { ceil((s as NSString).size(withAttributes: [.font: font]).width) }
    /// The least width that shows the line: the address is as wide blurred as it is sharp.
    static func width(_ address: String) -> CGFloat { lead + w(before) + w(address) + w(after) + trailing }

    /// Whether the line is lit by the menu (the address is sharp then); a dimmed line never is.
    var lit: Bool { enabled && (highlighted || enclosingMenuItem?.isHighlighted == true) }
    /// The address is drawn readable: the line is lit, or addresses are not blurred (AddressPrivacy).
    var sharp: Bool { lit || !AddressPrivacy.shared.blur }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func mouseEntered(with e: NSEvent) { needsDisplay = true }
    override func mouseExited(with e: NSEvent) { needsDisplay = true }
    /// A click is a release on the row: one released outside it (the press was on it) does nothing.
    override func mouseUp(with e: NSEvent) {
        guard bounds.contains(convert(e.locationInWindow, from: nil)) else { return }
        press()
    }

    /// A click: closes the menu, then runs the switch (not inside the menu's tracking loop). Nothing while dimmed.
    func press() {
        guard enabled else { return }
        enclosingMenuItem?.menu?.cancelTracking()
        let pick = self.pick
        DispatchQueue.main.async { pick() }
    }

    /// VoiceOver's press does the same.
    override func accessibilityPerformPress() -> Bool {
        guard enabled else { return false }
        press()
        return true
    }

    override func draw(_ dirty: NSRect) {
        let on = lit
        if on {
            // a native item's height, centred (the row is taller, for the blur)
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: 5, y: bounds.midY - 11, width: bounds.width - 10, height: 22), xRadius: 4, yRadius: 4).fill()
        }
        let fg: NSColor = !enabled ? .disabledControlTextColor : on ? .selectedMenuItemTextColor : .labelColor
        let attrs: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: fg]
        func put(_ s: String, at x: CGFloat) {
            let h = (s as NSString).size(withAttributes: attrs).height
            (s as NSString).draw(at: NSPoint(x: x, y: bounds.midY - h / 2), withAttributes: attrs)
        }
        var x = Self.lead
        put(Self.before, at: x); x += Self.w(Self.before)
        if sharp {
            put(address, at: x)
        } else if let img = blurredAddress(fg) {
            img.draw(in: NSRect(x: x - QCProfileMenuRow.blurPad, y: bounds.midY - img.size.height / 2, width: img.size.width, height: img.size.height))
        }
        x += Self.w(address)
        put(Self.after, at: x)
    }

    /// The blurred address, made once for the look it is drawn in (the lit look never shows it), made again if the
    /// appearance changes (its colour is the system's).
    private var blurCache: NSImage?
    private func blurredAddress(_ color: NSColor) -> NSImage? {
        if let blurCache { return blurCache }
        blurCache = QCProfileMenuRow.blurred(address, color: color, font: Self.font)
        return blurCache
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        blurCache = nil
        needsDisplay = true
    }
}

/// An address on its own line in an alert's accessory view (an NSAlert's text can't blur): drawn blurred, sharp while
/// the pointer is on it. The whole address is for drawing only; its accessibility label is the masked one.
final class QCAddressLabel: NSView {
    let address: String
    /// The pointer is on it: drawn readable.
    private(set) var revealed = false

    static let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    /// The frame holds the blur's reach on every side.
    static var pad: CGFloat { QCProfileMenuRow.blurPad }

    init(address: String) {
        self.address = address
        let s = (address as NSString).size(withAttributes: [.font: Self.font])
        super.init(frame: NSRect(x: 0, y: 0, width: ceil(s.width) + 2 * Self.pad, height: ceil(s.height) + 2 * Self.pad))
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(AddressPrivacy.words(address))
    }
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func mouseEntered(with e: NSEvent) { reveal(true) }
    override func mouseExited(with e: NSEvent) { reveal(false) }
    func reveal(_ on: Bool) { guard on != revealed else { return }; revealed = on; needsDisplay = true }

    /// Drawn readable: the pointer is on it, or addresses are not blurred (AddressPrivacy).
    var sharp: Bool { revealed || !AddressPrivacy.shared.blur }

    override func draw(_ dirty: NSRect) {
        if sharp {
            (address as NSString).draw(at: NSPoint(x: Self.pad, y: Self.pad), withAttributes: [.font: Self.font, .foregroundColor: NSColor.labelColor])
        } else if let img = blurCache ?? QCProfileMenuRow.blurred(address, color: .labelColor, font: Self.font) {
            blurCache = img
            img.draw(in: NSRect(origin: .zero, size: img.size))
        }
    }
    private var blurCache: NSImage?
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        blurCache = nil
        needsDisplay = true
    }
}
