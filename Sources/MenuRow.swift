// QCProfileMenuRow: a profile's row in the profile menu (QCMenu.profiles), a view of its own so it can hold the address
// of the profile's account in use, blurred at rest and readable only while the pointer is on it. It draws what a native
// item draws (the check mark, the level's dot, the name with its week under it, the menu's own highlight) and leaves the
// rest to the menu: the arrow keys highlight it, Return picks it (the item's action), a click picks it.
//
// The rule for addresses: blurred on screen everywhere, masked only as words (VoiceOver, an item's title, the checks).
// This file draws them blurred in the chat's profile menu (QCProfileMenuRow); the menu bar menu's standby rows are cl_kit's
// MenuRows (MenuAccountRowView, built in QCStatusMenu.standbyItem). What is blurred is a fixed stand-in, never
// the address (the AddressPrivacy module: AddressInk draws it, AddressLabel is the one in an alert's accessory view); the
// chat's views do it in AddressViews.swift.

import AddressPrivacy
import AppKit
import MenuRows

extension MenuRowColumns {
    /// Where a standby row's lamp and address sit in the menu bar's menu: the usage block's address x (27), the lamp 13 pt
    /// before it, in the block's lamp column.
    static let bar = MenuRowColumns(addressX: QCMenuUsageBlock.padX + QCMenuUsageBlock.textGap)
    /// And in the chat's profile menu, under the in-use row's dot and name (the lamp under the dot).
    static let chat = MenuRowColumns(markerX: QCProfileMenuRow.dotX, addressX: QCProfileMenuRow.textX)
}

extension MenuAccountRowView {
    /// The address's font in cl_quick's rows: as the block's account line and the profile menu's (11.5 pt).
    static let quickAddressFont = QCProfileMenuRow.addressFont
}

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
        let a = address.map { sizer.room(for: $0, blur: AddressPrivacy.shared.blur) + addressGap + copySize + copyGap } ?? 0
        return ceil(textX + max(t + a, d) + trailing)
    }

    /// Measures the room an address is given (AddressInk).
    private static let sizer = AddressInk(font: addressFont)
    /// Draws the address (its own text while readable, else the stand-in blurred) and keeps the blurred pictures.
    private let ink = AddressInk(font: QCProfileMenuRow.addressFont)

    /// The room of the address: the stand-in's while the blur is on, whatever the address (nothing moves when it is revealed).
    private var addressWidth: CGFloat { address.map { Self.sizer.room(for: $0, blur: AddressPrivacy.shared.blur) } ?? 0 }
    /// The text drawn for the address now: its own while it is readable, the stand-in at rest (never any part of it).
    var drawnAddress: String? { address.map { AddressText.drawn(address: $0, revealed: sharp, blur: true) } }
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
        // both end at the room's right edge, by the copy glyph
        ink.draw(address: address, readable: sharp, color: sub, x: a.maxX, midY: a.midY, alignRight: true, blur: AddressPrivacy.shared.blur)
        if rowHover || lit, let copy = Self.symbol("doc.on.doc", size: 11, weight: .regular, color: copyHover ? fg : sub) {
            copy.draw(in: NSRect(x: copyRect.midX - copy.size.width / 2, y: copyRect.midY - copy.size.height / 2, width: copy.size.width, height: copy.size.height))
        }
    }

    private static func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: weight).applying(.init(paletteColors: [color])))
    }

    // (the blurred stand-in is made once per colour by `ink`, and made again if the appearance changes: its colours are the system's)
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        ink.reset()
        needsDisplay = true
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
