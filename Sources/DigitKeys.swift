// The digit keys of the chat panel, one table: ⌘ digits pick the model and its thinking, ⌃ digits place the panel on its
// screen, ⌃⌥ digits size it. They are matched by KEY CODE (the
// number row and the keypad), never by the character, so they work on every layout (Cyrillic and the rest) and with
// Caps Lock. The panel (QuickChatPanel) reads the table, QuickChat does what a key says, and the keys list
// (QCKeysView) is drawn from the same rows.

import AppKit
import Carbon.HIToolbox

/// Where on its screen the panel sits: one of six places (⌃1 … ⌃6).
struct QCSpot: Equatable {
    enum Across { case left, centre, right }
    enum Down { case bottom, top }
    var across: Across
    var down: Down
}

/// The panel's size (⌃⌥1 … ⌃⌥5).
enum QCPanelSize: Equatable, CaseIterable {
    case small, standard, large, tall, wide

    var title: String {
        switch self {
        case .small: return "Small"
        case .standard: return "Standard"
        case .large: return "Large"
        case .tall: return "Tall"
        case .wide: return "Wide"
        }
    }

    /// The size asked for, before any clamping, on a screen whose visible frame is `vis`; `current` is the panel's now.
    /// Tall keeps the width and takes the screen's height; Wide is 960 wide and 70% of the screen's height.
    func target(current: NSSize, in vis: NSRect) -> NSSize {
        switch self {
        case .small: return NSSize(width: 420, height: 440)
        case .standard: return NSSize(width: QuickChatRoot.width, height: QuickChatRoot.windowHeight)
        case .large: return NSSize(width: 720, height: 760)
        case .tall: return NSSize(width: current.width, height: vis.height)
        case .wide: return NSSize(width: 960, height: (vis.height * 0.7).rounded())
        }
    }
}

enum QCDigitAction: Equatable {
    case model(QuickChatModelChoice, QuickChatThinking)
    case place(QCSpot)
    case size(QCPanelSize)
}

enum QCDigitKeys {
    /// The digit a key code is: the number row and the keypad (the keypad's keys carry the numeric-pad flag, which the
    /// modifiers compared below leave out).
    static func digit(keyCode: UInt16) -> Int? {
        let row: [Int: Int] = [kVK_ANSI_1: 1, kVK_ANSI_2: 2, kVK_ANSI_3: 3, kVK_ANSI_4: 4, kVK_ANSI_5: 5,
                               kVK_ANSI_6: 6, kVK_ANSI_7: 7, kVK_ANSI_8: 8, kVK_ANSI_9: 9, kVK_ANSI_0: 0,
                               kVK_ANSI_Keypad1: 1, kVK_ANSI_Keypad2: 2, kVK_ANSI_Keypad3: 3, kVK_ANSI_Keypad4: 4,
                               kVK_ANSI_Keypad5: 5, kVK_ANSI_Keypad6: 6, kVK_ANSI_Keypad7: 7, kVK_ANSI_Keypad8: 8,
                               kVK_ANSI_Keypad9: 9, kVK_ANSI_Keypad0: 0]
        return row[Int(keyCode)]
    }

    /// One modifier combination and what its digits do. Another group (the next set of keys) is another row here.
    struct Group {
        let flags: NSEvent.ModifierFlags
        let actions: [Int: QCDigitAction]
    }

    static let groups: [Group] = [
        // ⌘ digits: the model and how long it thinks
        Group(flags: [.command], actions: [
            1: .model(.sonnet, .medium),
            2: .model(.opus, .medium),
            3: .model(.opus, .high),
            4: .model(.fable, .high),
        ]),
        // ⌃ digits: the panel's place on its screen, bottom row first
        Group(flags: [.control], actions: [
            1: .place(QCSpot(across: .left, down: .bottom)),
            2: .place(QCSpot(across: .centre, down: .bottom)),
            3: .place(QCSpot(across: .right, down: .bottom)),
            4: .place(QCSpot(across: .left, down: .top)),
            5: .place(QCSpot(across: .centre, down: .top)),
            6: .place(QCSpot(across: .right, down: .top)),
        ]),
        // ⌃⌥ digits: the panel's size
        Group(flags: [.control, .option], actions: [
            1: .size(.small), 2: .size(.standard), 3: .size(.large), 4: .size(.tall), 5: .size(.wide),
        ]),
    ]

    private static let modifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    /// What a key press asks for, or nil when it is none of these keys (exactly the group's modifiers, a digit's key code).
    static func action(for e: NSEvent) -> QCDigitAction? {
        guard e.type == .keyDown, let d = digit(keyCode: e.keyCode) else { return nil }
        let flags = e.modifierFlags.intersection(modifiers)
        return groups.first { $0.flags == flags }?.actions[d]
    }

    /// The keys list's rows for these keys, in the order of the groups.
    static let rows: [(String, String)] = [
        ("⌘1  ⌘2", "Sonnet, Opus: Medium"),
        ("⌘3  ⌘4", "Opus, Fable: High"),
        ("⌃1 – ⌃6", "Place: bottom row, top row (left, centre, right)"),
        ("⌃⌥1 – ⌃⌥5", "Size: " + QCPanelSize.allCases.map(\.title).joined(separator: ", ")),
    ]
}

/// Where the panel goes on a screen, and how a resize keeps its place: plain functions, for the checks.
enum QCGeometry {
    /// The gap above the bottom of the visible frame the panel first opens at (just above the Dock).
    static let bottomGap: CGFloat = 85

    /// The origin that puts a panel of `size` at `spot` in `vis`: its corner or edge centre at the frame's edge (the sides
    /// and the top flush with the visible frame, as the app's clamps leave them; the bottom `bottomGap` above it, as the
    /// first opening does), never outside `vis`.
    static func origin(for spot: QCSpot, size: NSSize, in vis: NSRect) -> NSPoint {
        let x: CGFloat
        switch spot.across {
        case .left: x = vis.minX
        case .centre: x = vis.midX - size.width / 2
        case .right: x = vis.maxX - size.width
        }
        let y = spot.down == .top ? vis.maxY - size.height : min(vis.minY + bottomGap, vis.maxY - size.height)
        return NSPoint(x: x, y: y)
    }

    /// The nearest of the six places to a frame. A frame that touches an edge of `vis` is at that edge, however large it is
    /// (a big panel put at the bottom left has its centre well inside the screen): left or right by the side it touches,
    /// bottom by a bottom edge at or below the first opening's gap (`bottomGap`), top by a top edge at the frame's top.
    /// Only a frame touching none falls back to its centre's third of the screen across and its half down. A frame that
    /// touches both ends of an axis (as tall as the screen, as wide) is no place on that axis: `hint`, the last place
    /// the keys put it at, decides there, else the top and the centre.
    static func nearest(_ f: NSRect, in vis: NSRect, hint: QCSpot? = nil) -> QCSpot {
        let eps: CGFloat = 1
        let left = f.minX <= vis.minX + eps, right = f.maxX >= vis.maxX - eps
        let top = f.maxY >= vis.maxY - eps, bottom = f.minY <= vis.minY + bottomGap + eps
        let across: QCSpot.Across
        if left && right { across = hint?.across ?? .centre }
        else if left { across = .left }
        else if right { across = .right }
        else { across = f.midX < vis.minX + vis.width / 3 ? .left : f.midX > vis.maxX - vis.width / 3 ? .right : .centre }
        let down: QCSpot.Down
        if top && bottom { down = hint?.down ?? .top }
        else if top { down = .top }
        else if bottom { down = .bottom }
        else { down = f.midY < vis.midY ? .bottom : .top }
        return QCSpot(across: across, down: down)
    }

    /// `f` at the width and height asked for, held to the least sizes and to `vis` less the app's edge margin
    /// (QuickChatRoot.margin), the corner or edge centre of its place (`spot`, else its nearest) staying where it is (a
    /// bottom-right panel keeps its bottom-right corner), and the whole frame inside `vis`. `height` nil: the height stays
    /// (the bar's follows its content).
    static func resized(_ f: NSRect, width: CGFloat, height: CGFloat?, in vis: NSRect, minWidth: CGFloat, minHeight: CGFloat,
                        spot: QCSpot? = nil) -> NSRect {
        let margin = QuickChatRoot.margin
        let w = min(max(width, minWidth), vis.width - 2 * margin)
        let h = min(max(height ?? f.height, minHeight), vis.height - 2 * margin)
        let spot = spot ?? nearest(f, in: vis)
        var r = NSRect(x: f.minX, y: f.minY, width: w, height: h)
        switch spot.across {
        case .left: r.origin.x = f.minX
        case .centre: r.origin.x = f.midX - w / 2
        case .right: r.origin.x = f.maxX - w
        }
        r.origin.y = spot.down == .bottom ? f.minY : f.maxY - h
        r.origin.x = min(max(r.minX, vis.minX), vis.maxX - w)
        r.origin.y = min(max(r.minY, vis.minY), vis.maxY - h)
        return r
    }
}
