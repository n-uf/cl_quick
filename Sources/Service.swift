// "Ask cl_quick": the macOS Services entry (Info.plist NSServices, written by build.sh). Select text in any app, then
// right-click ▸ Services ▸ Ask cl_quick (or the app menu ▸ Services, or a shortcut set in System Settings ▸ Keyboard ▸
// Keyboard Shortcuts ▸ Services). The selected text arrives here from the other app through a pasteboard that macOS fills,
// so no Accessibility permission is involved, and cl_quick opens its bar with the text in the field, ready to edit and
// not sent. Nothing about the selection is stored anywhere: it goes into the field and nowhere else.
//
// The field gets the selection as a Markdown quote ("> " before every line), then a blank line, with the caret after it:
// the question is typed under the quote, and Claude reads it as quoted text. A field that already has text keeps it; the
// quote comes after it, a blank line between. A selection longer than `cap` characters is cut there, and a line says so.

import AppKit

final class QCServiceProvider: NSObject {
    static let shared = QCServiceProvider()

    /// The most characters of a selection that go into the field.
    static let cap = 20_000
    /// The line over the field when the selection was cut (the same note line as Dictation's).
    static let capNote = "The selection was cut to its first 20,000 characters."

    /// At launch: macOS sends the Services requests to this object, and asks for the service list to be read again, so
    /// the entry shows without a logout (it is asked for once; the entry itself comes from Info.plist).
    static func register() {
        NSApp.servicesProvider = shared
        NSUpdateDynamicServices()
    }

    /// The Services message (Info.plist NSMessage). The selection comes in `pboard` as plain text; nothing goes back.
    @objc func askAboutSelection(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let text = pboard.string(forType: .string) else {
            error.pointee = "cl_quick got no text from the selection." as NSString
            return
        }
        QuickChat.shared.openWith(text: text)
    }

    /// The field's new text for a selection, and whether the selection was cut. An empty (or blank) selection changes
    /// nothing. Pure, for the checks.
    static func field(existing: String, selection: String) -> (text: String, cut: Bool) {
        var s = selection.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return (existing, false) }
        var cut = false
        if s.count > cap {
            s = String(s.prefix(cap)).trimmingCharacters(in: .whitespacesAndNewlines)
            cut = true
        }
        let quote = s.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces).isEmpty ? ">" : "> " + $0 }
            .joined(separator: "\n")
        let before = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        return ((before.isEmpty ? "" : before + "\n\n") + quote + "\n\n", cut)
    }
}
