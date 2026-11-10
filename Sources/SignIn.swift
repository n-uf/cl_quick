// SignIn: signing a Claude Code folder in, through Claude Code itself. One folder holds one signed-in account at a time,
// so signing in again is how a profile renews its sign-in or changes account. cl_quick never sees a password or a token:
// it opens Terminal with `claude auth login` on the folder, and the browser does the rest.

import AppKit

enum SignIn {
    /// Opens Terminal running `claude auth login` on the folder (made if it isn't there). `email` fills in the sign-in
    /// page's address. Returns why it couldn't, or nil. Looks for claude off the main thread; `done` comes on it.
    static func open(folder: String, email: String? = nil, done: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let claude = ClaudeLocator.find()?.path
            DispatchQueue.main.async { done(start(folder: folder, email: email, claude: claude)) }
        }
    }

    private static func start(folder: String, email: String?, claude: String?) -> String? {
        guard let claude else { return ClaudeInstall.missing + "." }
        let path = expand(folder)
        do { try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true) } catch {
            return "\(tilde(path)) can't be made: \(error.localizedDescription)"
        }
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        var login = "\(q(claude)) auth login"
        if let email, !email.isEmpty { login += " --email \(q(email))" }
        // the plain ~/.claude runs without CLAUDE_CONFIG_DIR, as Terminal does
        let dir = ClaudeFolder.isDefault(path) ? "unset CLAUDE_CONFIG_DIR\n" : "export CLAUDE_CONFIG_DIR=\(q(path))\n"
        let text = "#!/bin/zsh\n# cl_quick: Claude Code's sign-in for \(tilde(path)). Close this window when it says you're signed in.\n"
            // a key or another provider from the shell's own settings would sign it in some other way: not here
            + "unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN CLAUDE_CODE_OAUTH_TOKEN CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY\n"
            + dir + "exec \(login)\n"
        let script = Files.folder.appendingPathComponent("sign-in.command")
        do {
            try FileManager.default.createDirectory(at: Files.folder, withIntermediateDirectories: true)
            try text.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        } catch { return "The sign-in couldn't start: \(error.localizedDescription)" }
        NSWorkspace.shared.open(script)
        return nil
    }
}
