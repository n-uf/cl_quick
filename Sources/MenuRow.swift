// QCProfileMenuRow: a profile's row in the profile menu (QCMenu.profiles), a view of its own so it can hold the address
// of the profile's account in use, blurred at rest and readable only while the pointer is on it. It draws what a native
// item draws (the check mark, the level's dot, the name with its week under it, the menu's own highlight) and leaves the
// rest to the menu: the arrow keys highlight it, Return picks it (the item's action), a click picks it.
//
// The rule for addresses: blurred on screen everywhere, masked only as words (VoiceOver, an item's title, the checks).
// This file draws them blurred in the menus (QCProfileMenuRow, QCStandbyMenuRow) and in an alert's accessory view
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
        closeMenuThen(pick)
    }

    /// VoiceOver's press picks the profile, as a click does.
    override func accessibilityPerformPress() -> Bool {
        closeMenuThen(pick)
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

extension NSView {
    /// A click on a menu item's view: closes the menu, then runs `pick` once it has closed (not inside the menu's
    /// tracking loop, where a modal question or a window would not take the keyboard).
    func closeMenuThen(_ pick: @escaping () -> Void) {
        enclosingMenuItem?.menu?.cancelTracking()
        DispatchQueue.main.async { pick() }
    }

    /// The release of a click is on the view: a release outside it (the press was on it) is no click.
    func releasedOn(_ e: NSEvent) -> Bool { bounds.contains(convert(e.locationInWindow, from: nil)) }
}

/// A profile's standby account as a row of its group in the menu: under the block of the profile (its account in use
/// and the bars), dimmed, a hollow lamp, the address and "· standby", laid out as the block's account line is (the same
/// lamp column, address x and fonts). It shows no usage. Drawn by hand like the block and QCProfileMenuRow: the
/// address is blurred at rest and sharp while the row is highlighted (the menu's highlight follows the pointer and the
/// arrow keys), and a quiet "Switch…" shows at the right then. A click anywhere on it closes the menu and asks the
/// switch question (the item's action does the same for Return). While a sign-in for the profile is waited for the
/// row is dimmed further, never lit, and does nothing.
final class QCStandbyMenuRow: NSView {
    /// The whole address, for drawing only; the words and the accessibility label hold it masked.
    let address: String
    let enabled: Bool
    let pick: () -> Void
    /// For pictures: drawn as if the menu highlighted it.
    var highlighted = false

    static let tag = " · standby", hint = "Switch…"
    /// As the block's account line: the lamp's column, the address's x, the fonts.
    static let lampX = QCMenuUsageBlock.padX, addressX = QCMenuUsageBlock.padX + QCMenuUsageBlock.textGap
    static let addressFont = QCProfileMenuRow.addressFont, tagFont = QCMenuUsageBlock.accountFont
    static let hintGap: CGFloat = 18

    /// Where the lamp and the address sit: the menu bar's block's (`bar`), or the chat's profile menu's, under the
    /// in-use row's dot and name (`chat`).
    struct Columns: Equatable {
        let lampX: CGFloat, addressX: CGFloat
        static let bar = Columns(lampX: QCStandbyMenuRow.lampX, addressX: QCStandbyMenuRow.addressX)
        static let chat = Columns(lampX: QCProfileMenuRow.dotX, addressX: QCProfileMenuRow.textX)
    }
    let columns: Columns
    /// As tall as the blurred address's picture (the text's height and the blur's reach above and below), so the blur
    /// is never cut; the highlight is a native item's height, centred.
    static let height: CGFloat = ceil(("Ag" as NSString).size(withAttributes: [.font: addressFont]).height) + 2 * QCProfileMenuRow.blurPad
    static let highlightH: CGFloat = 22

    /// The item's title (type-ahead, Return): the address masked, and that it stands by.
    static func title(_ address: String) -> String { AddressPrivacy.words(address) + tag }
    /// What VoiceOver reads: the address masked, "standby", "switch" (the action).
    static func spoken(_ address: String) -> String { AddressPrivacy.words(address) + ", standby, switch" }

    init(address: String, enabled: Bool, columns: Columns = .bar, pick: @escaping () -> Void) {
        self.address = address; self.enabled = enabled; self.columns = columns; self.pick = pick
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width(address, columns: columns), height: Self.height))
        autoresizingMask = [.width]
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel(Self.spoken(address))
        setAccessibilityEnabled(enabled)
    }
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    override var isFlipped: Bool { true }

    private static func w(_ s: String, _ f: NSFont) -> CGFloat { ceil((s as NSString).size(withAttributes: [.font: f]).width) }
    /// The least width that shows it all (nothing is cut): the address (as wide blurred as sharp), its tag and "Switch…".
    static func width(_ address: String, columns: Columns = .bar) -> CGFloat {
        columns.addressX + w(address, addressFont) + w(tag, tagFont) + hintGap + w(hint, tagFont) + QCMenuUsageBlock.padX
    }

    /// Whether the row is lit by the menu (the address is sharp then); a dimmed row never is.
    var lit: Bool { enabled && (highlighted || enclosingMenuItem?.isHighlighted == true) }
    /// The address is drawn readable: the row is lit, or addresses are not blurred (AddressPrivacy).
    var sharp: Bool { lit || !AddressPrivacy.shared.blur }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func mouseEntered(with e: NSEvent) { needsDisplay = true }
    override func mouseExited(with e: NSEvent) { needsDisplay = true }
    override func mouseUp(with e: NSEvent) { if releasedOn(e) { press() } }

    /// A click anywhere on the row: closes the menu, then runs the switch question. Nothing while dimmed.
    func press() {
        guard enabled else { return }
        closeMenuThen(pick)
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
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: 5, y: bounds.midY - Self.highlightH / 2, width: bounds.width - 10, height: Self.highlightH), xRadius: 4, yRadius: 4).fill()
        }
        // dimmed (a step below the account in use), dimmed further while a sign-in is waited for, light on the highlight
        let fg: NSColor = on ? .selectedMenuItemTextColor : enabled ? .tertiaryLabelColor : NSColor.labelColor.withAlphaComponent(0.14)
        let sub: NSColor = on ? NSColor.selectedMenuItemTextColor.withAlphaComponent(0.75) : fg
        let mid = bounds.midY
        QCMenuUsageBlock.drawLamp(on ? NSColor.selectedMenuItemTextColor.withAlphaComponent(0.85) : fg, hollow: true, x: columns.lampX, midY: mid)
        let width = Self.w(address, Self.addressFont)
        if sharp {
            QCMenuUsageBlock.drawText(address, Self.addressFont, sub, x: columns.addressX, midY: mid)
        } else if let img = blurredAddress(fg) {
            img.draw(in: NSRect(x: columns.addressX - QCProfileMenuRow.blurPad, y: mid - img.size.height / 2, width: img.size.width, height: img.size.height))
        }
        QCMenuUsageBlock.drawText(Self.tag, Self.tagFont, sub, x: columns.addressX + width, midY: mid)
        if on {
            let hintW = Self.w(Self.hint, Self.tagFont)
            QCMenuUsageBlock.drawText(Self.hint, Self.tagFont, sub, x: bounds.maxX - QCMenuUsageBlock.padX - hintW, midY: mid)
        }
    }

    /// The blurred address, made once for the look it is drawn in (the lit look never shows it), made again if the
    /// appearance changes (its colour is the system's).
    private var blurCache: NSImage?
    private func blurredAddress(_ color: NSColor) -> NSImage? {
        if let blurCache { return blurCache }
        blurCache = QCProfileMenuRow.blurred(address, color: color, font: Self.addressFont)
        return blurCache
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        blurCache = nil
        needsDisplay = true
    }
}

/// "Add an account…" as the last row of a profile's group in a menu, after its standby rows: a small plus in the lamp
/// column and the words in the address column, dimmed like a standby row and lit by the menu's highlight. A click
/// anywhere on it closes the menu and runs `pick` (the item's action does the same for Return). While a sign-in for the
/// profile is waited for it is dimmed further, never lit, and does nothing.
final class QCAddAccountMenuRow: NSView {
    let enabled: Bool
    let columns: QCStandbyMenuRow.Columns
    let pick: () -> Void
    /// For pictures: drawn as if the menu highlighted it.
    var highlighted = false

    static let title = "Add an account…"

    init(enabled: Bool, columns: QCStandbyMenuRow.Columns = .bar, pick: @escaping () -> Void) {
        self.enabled = enabled; self.columns = columns; self.pick = pick
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width(columns: columns), height: QCStandbyMenuRow.height))
        autoresizingMask = [.width]
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel(Self.title)
        setAccessibilityEnabled(enabled)
    }
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    override var isFlipped: Bool { true }

    /// The least width that shows it all.
    static func width(columns: QCStandbyMenuRow.Columns = .bar) -> CGFloat {
        columns.addressX + ceil((title as NSString).size(withAttributes: [.font: QCStandbyMenuRow.addressFont]).width) + QCMenuUsageBlock.padX
    }

    /// Whether the row is lit by the menu; a dimmed row never is.
    var lit: Bool { enabled && (highlighted || enclosingMenuItem?.isHighlighted == true) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func mouseEntered(with e: NSEvent) { needsDisplay = true }
    override func mouseExited(with e: NSEvent) { needsDisplay = true }
    override func mouseUp(with e: NSEvent) { if releasedOn(e) { press() } }

    /// A click anywhere on the row: closes the menu, then runs `pick`. Nothing while dimmed.
    func press() {
        guard enabled else { return }
        closeMenuThen(pick)
    }
    override func accessibilityPerformPress() -> Bool {
        guard enabled else { return false }
        press()
        return true
    }

    override func draw(_ dirty: NSRect) {
        let on = lit
        if on {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: 5, y: bounds.midY - QCStandbyMenuRow.highlightH / 2, width: bounds.width - 10, height: QCStandbyMenuRow.highlightH), xRadius: 4, yRadius: 4).fill()
        }
        let fg: NSColor = on ? .selectedMenuItemTextColor : enabled ? .tertiaryLabelColor : NSColor.labelColor.withAlphaComponent(0.14)
        let mid = bounds.midY
        // the plus, as wide as the lamps are
        let c = columns.lampX + QCMenuUsageBlock.dotSize / 2, r = QCMenuUsageBlock.dotSize / 2 - 0.6
        let plus = NSBezierPath()
        plus.move(to: NSPoint(x: c - r, y: mid)); plus.line(to: NSPoint(x: c + r, y: mid))
        plus.move(to: NSPoint(x: c, y: mid - r)); plus.line(to: NSPoint(x: c, y: mid + r))
        plus.lineWidth = 1.2; plus.lineCapStyle = .round
        fg.setStroke(); plus.stroke()
        QCMenuUsageBlock.drawText(Self.title, QCStandbyMenuRow.addressFont, fg, x: columns.addressX, midY: mid)
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

    // A modal alert (NSAlert.runModal) gets no enter and exit from the tracking area above, so while the label is in a
    // window the pointer's place is also read every 50 ms, in every run loop mode (the modal one included), and the
    // address is readable exactly while the pointer is on the label.
    private var poll: Timer?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        poll?.invalidate(); poll = nil
        guard let w = window else { reveal(false); return }
        w.acceptsMouseMovedEvents = true
        var shown = false
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] t in
            guard let self, let w = self.window else { t.invalidate(); return }
            if w.isVisible { shown = true; self.follow(inWindow: w.mouseLocationOutsideOfEventStream) }
            else if shown { t.invalidate(); self.reveal(false) }     // the alert has closed
        }
        RunLoop.main.add(t, forMode: .common)
        poll = t
    }
    /// The pointer at a point of the window (nil: it is nowhere): the address is readable while it is on the label.
    func follow(inWindow p: NSPoint?) { reveal(p.map { bounds.contains(convert($0, from: nil)) } ?? false) }

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
