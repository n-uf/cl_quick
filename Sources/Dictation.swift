// QCDictation: macOS's own Dictation into the chat's field, started and stopped by the field row's mic button.
//
// The panel stays non-activating: cl_quick never comes forward. Dictation, like typing, goes to the key window's first
// responder, and the panel becomes key without activating the app (as it does for the shortcut), so the field gets
// what is dictated, not the app behind. The button first makes the panel key and the field its first responder, then
// sends `startDictation:` down the responder chain, as the Edit menu's Start Dictation… would. (NSApplication takes both
// `startDictation:` and `stopDictation:`, NSTextView neither, on macOS 26: the action goes up the chain to the app, which
// starts Dictation for the text that has the keyboard, our field.)
//
// macOS doesn't say whether Dictation is running, so the button keeps its own state: on after a start, off after a stop,
// a send, a new chat or the panel hiding (each of which also stops Dictation).

import AppKit

enum QCDictation {
    static let start = Selector(("startDictation:"))
    static let stop = Selector(("stopDictation:"))

    /// Sends an action to the field when it takes it, else down the responder chain (the key window's first responder
    /// first); whether something took it. A check replaces it, so no real Dictation ever starts in one.
    static var send: (Selector, NSResponder?) -> Bool = { sel, field in
        NSApp.sendAction(sel, to: field?.responds(to: sel) == true ? field : nil, from: nil)
    }
    /// Whether the field or something in the responder chain takes an action (a check replaces it too).
    static var handles: (Selector, NSResponder?) -> Bool = { sel, field in
        field?.responds(to: sel) == true || NSApp.target(forAction: sel, to: nil, from: nil) != nil
    }

    /// Whether Dictation is turned off in macOS (System Settings ▸ Keyboard ▸ Dictation); a setting not found counts as
    /// on, and starting it then simply does nothing.
    static var isOff: () -> Bool = {
        (UserDefaults(suiteName: "com.apple.HIToolbox")?.object(forKey: "AppleDictationAutoEnable") as? Int) == 0
    }

    /// The one line said when it is off (once a run), and when it didn't start.
    static let offWords = "Dictation is off: System Settings ▸ Keyboard ▸ Dictation."
    static let failedWords = "Dictation didn't start. Try again, or press the Dictation key."

    /// Starts Dictation for the field (the panel's first responder); whether it was taken.
    @discardableResult static func begin(for field: NSResponder?) -> Bool { send(start, field) }

    /// Stops it with `stopDictation:` (never the start action again: a state gone stale, Dictation ended by Esc or the
    /// Dictation key, must not start it anew); where nothing takes that, the field gives up the keyboard and takes it
    /// back (`refocus`), which ends the input it had.
    static func end(for field: NSResponder?, refocus: () -> Void) {
        if handles(stop, field) { _ = send(stop, field) } else { refocus() }
    }
}
