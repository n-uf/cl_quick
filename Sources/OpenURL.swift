// Opening cl_quick from other apps: cl-quick://chat?folder=<percent-encoded absolute Claude Code folder> (or just
// cl-quick://chat). A URL can come from any web page or app, so it can only pick among the existing profiles and open the
// bar: it never sends a message, fills the field, changes a profile or a setting, starts a sign-in, or reads the folder it
// names. The folder is matched on strings alone, after canonicalising; nothing of it is logged.

import Foundation

enum QCOpenURL {
    /// `nil`: not for cl_quick (another scheme, host or path), do nothing. Otherwise the profile to open the chat on
    /// (`id` nil: no profile asked for, so what `open()` picks) and whether a folder was named that no profile uses.
    static func profileID(for url: URL, profiles: [Profile], home: String) -> (id: String?, unmatched: Bool)? {
        guard url.scheme?.lowercased() == "cl-quick",
              let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.host?.lowercased() == "chat", c.path.isEmpty || c.path == "/" else { return nil }
        // only `folder` counts; any other query item is ignored. An empty one is none.
        guard let named = c.queryItems?.first(where: { $0.name == "folder" })?.value, !named.isEmpty else { return (nil, false) }
        guard let wanted = standard(expanded(named, home: home)) else { return (nil, true) }
        for p in profiles {
            let own = expanded(p.folder, home: home)
            // the profile's own folder is trusted, so it is also looked at with its symlinks resolved; the folder in the
            // URL is never touched (no stat, no read): it is compared as written, with . and .. and a trailing / removed
            if standard(own) == wanted || resolved(own) == wanted { return (p.id, false) }
        }
        return (nil, true)
    }

    /// `~` and `~/…` as the home folder.
    private static func expanded(_ path: String, home: String) -> String {
        path == "~" ? home : path.hasPrefix("~/") ? home + path.dropFirst(1) : path
    }

    /// An absolute path with . and .. and a trailing / removed, by string work alone (URL(fileURLWithPath:) is given
    /// isDirectory so it doesn't stat); nil for anything not absolute.
    private static func standard(_ path: String) -> String? {
        guard path.hasPrefix("/"), !path.contains("\0") else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true).standardized.path
    }

    /// A profile's folder with its symlinks resolved (trusted: it is one the user added).
    private static func resolved(_ path: String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true).resolvingSymlinksInPath().path
    }
}

extension QuickChat {
    /// Opens the bar for a cl-quick:// URL, as the menu bar's profile click does (open(profile:)): a chat under way on
    /// that profile stays, another profile gets a new chat. A folder no profile uses opens it on the default one, with a
    /// quiet line over the field. Nothing else comes of a URL.
    func handle(openURL url: URL) {
        guard let r = QCOpenURL.profileID(for: url, profiles: store.profiles, home: NSHomeDirectory()) else { return }
        open(profile: r.id)
        if r.unmatched, let name = model.target?.name { model.say("No profile uses that folder; on \(name).") }
    }
}
