// The digit keys of the chat panel, one table: ⌘ digits pick the model and its thinking. They are matched by KEY CODE (the
// number row and the keypad), never by the character, so they work on every layout (Cyrillic and the rest) and with
// Caps Lock. The panel (QuickChatPanel) reads the table, QuickChat does what a key says, and the keys list
// (QCKeysView) is drawn from the same rows.

import AppKit
import Carbon.HIToolbox

enum QCDigitAction: Equatable {
    case model(QuickChatModelChoice, QuickChatThinking)
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
    ]
}
