// QCDictation: macOS's own Dictation into the chat's field, started and stopped by the field row's mic button.
//
// The panel stays non-activating: cl_quick never comes forward. Dictation, like typing, goes to the key window's first
// responder, and the panel becomes key without activating the app (as it does for the shortcut), so the field gets
// what is dictated, not the app behind. The button first makes the panel key and the field its first responder, then
// sends `startDictation:` down the responder chain, as the Edit menu's Start Dictation… would. (NSApplication takes
// `startDictation:`, NSTextView doesn't, on macOS 26: the action goes up the chain to the app, which starts Dictation for
// the text that has the keyboard, our field.)
//
// Stopping never goes that way. NSApplication's `stopDictation:` is the same as its `startDictation:` (on macOS 26 both
// are `[[NSDictationManager defaultManager] dictationItemSelected:]`, the Edit menu item's toggle), and the manager picks
// the action from its own idea of the state, which a never-active app doesn't keep: sent while Dictation ran, it left it
// running; sent after Dictation ended, it could start it again. Dictation is an input method (Ironwood) of the field's
// text input context, so it is ended there, as switching apps ends it (`end`).
//
// macOS doesn't say whether Dictation is running, so the button keeps its own state: on after a start, off after a stop,
// a send, a new chat or the panel hiding (each of which also stops Dictation).

import AppKit

enum QCDictation {
    static let start = Selector(("startDictation:"))
    /// NSApplication's `stopDictation:`: a toggle (see above), never sent.
    static let stop = Selector(("stopDictation:"))
    /// The text input context's own stop: hides the Dictation HUD and ends the Ironwood session, without selecting the
    /// Dictation input method (a session that isn't running stays so). Private, so only sent when the context takes it.
    static let stopSession = Selector(("_stopDictation:"))
    /// The steps that end Dictation in the field's text input context, in order (after the field commits its marked text):
    /// the input method drops its provisional text (the field has it now), the session stops, and the context gives up
    /// the keyboard and takes it back (`deactivate` ends the input method's session as switching apps does; `activate`
    /// gives the field the keyboard again, the caret where it was).
    static let discard = #selector(NSTextInputContext.discardMarkedText)
    static let deactivate = #selector(NSTextInputContext.deactivate)
    static let activate = #selector(NSTextInputContext.activate)
    static let stopSteps = [discard, stopSession, deactivate, activate]

    /// Sends an action to the target when it takes it, else down the responder chain (the key window's first responder
    /// first); whether something took it. A check replaces it, so no real Dictation ever starts or stops in one.
    static var send: (Selector, AnyObject?) -> Bool = { sel, target in
        NSApp.sendAction(sel, to: target?.responds(to: sel) == true ? target : nil, from: nil)
    }
    /// Whether the target or something in the responder chain takes an action (a check replaces it too).
    static var handles: (Selector, AnyObject?) -> Bool = { sel, target in
        target?.responds(to: sel) == true || NSApp.target(forAction: sel, to: nil, from: nil) != nil
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

    /// Ends Dictation in the field, keeping what it wrote: the field commits Dictation's marked text first, then its text
    /// input context runs `stopSteps`, each sent straight to the context and only when it takes it (never down the chain:
    /// NSApplication answers `activate` and `stopDictation:`). Each step is harmless when Dictation has ended already, and
    /// none can start it (nothing toggles, nothing selects the Dictation input method). `refocus` then makes sure the
    /// field has the keyboard; without a text input context it does the work itself (the field gives up the keyboard and
    /// takes it back). The context takes the keyboard back only while the field has it in the key window.
    static func end(for field: NSResponder?, refocus: () -> Void) {
        guard let tv = field as? NSTextView, let ctx = tv.inputContext else { refocus(); return }
        if tv.hasMarkedText() { tv.unmarkText() }
        let focused = tv.window?.isKeyWindow == true && tv.window?.firstResponder === tv
        for sel in stopSteps where ctx.responds(to: sel) {
            if sel == activate, !focused { continue }
            _ = send(sel, ctx)
        }
        refocus()
    }
}
