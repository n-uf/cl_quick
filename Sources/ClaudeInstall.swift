// ClaudeInstall: the words and the install help for when Claude Code (`claude`) isn't on this Mac. Where it is comes from
// cl_kit's one claude finder (Runs' ClaudeFinder: the usual places, the login shell, Volta, nvm, npm's prefix, and last
// the Claude app's own copy; a real install always wins over the app's copy), the same as cl_audit's.

import AppKit

enum ClaudeInstall {
    /// Claude Code's own installer for macOS (code.claude.com/docs/en/setup).
    static let command = "curl -fsSL https://claude.ai/install.sh | bash"
    static let docs = URL(string: "https://code.claude.com/docs/en/setup")!

    /// The reason shown next to every sign-in key that needs Claude Code when it isn't there.
    static let missing = "Claude Code isn't installed on this Mac"
    static let missingInstall = missing + " · Install…"

    static func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }

    /// For places without a window of their own (a Dock icon's menu): says why and offers the command and the docs.
    static func showAlert() {
        guard Thread.isMainThread else { DispatchQueue.main.async { showAlert() }; return }
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = missing
        a.informativeText = "Signing in needs it. Paste this in Terminal, then try again:\n\n\(command)"
        a.addButton(withTitle: "Copy the command")
        a.addButton(withTitle: "Open the install page")
        a.addButton(withTitle: "Not now")
        switch a.runModal() {
        case .alertFirstButtonReturn: copyCommand()
        case .alertSecondButtonReturn: NSWorkspace.shared.open(docs)
        default: break
        }
    }
}
