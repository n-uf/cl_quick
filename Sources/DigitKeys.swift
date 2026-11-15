// The digit keys of the chat panel, one table: ⌘ digits pick the model and its thinking, ⌃ digits place the panel on its
// screen. They are matched by KEY CODE (the
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

enum QCDigitAction: Equatable {
    case model(QuickChatModelChoice, QuickChatThinking)
    case place(QCSpot)
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
    ]
}

/// Where the panel goes on a screen: plain functions, for the checks.
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
}
