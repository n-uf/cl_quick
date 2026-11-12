// Profiles: the Claude Code folders cl_quick chats on, picked by you (Settings), with the account signed in to each and
// its week as Claude Code last reported it. cl_quick reads only each folder's own .claude.json for the account; it never
// touches the Keychain and reads no usage of its own.
//
// Its files, all in ~/Library/Application Support/cl_quick/: profiles.json, settings.json, levels.json, and work/<id>/
// (the folders Claude Code runs the chats in).

import Foundation

func expand(_ path: String) -> String { (path as NSString).expandingTildeInPath }

/// The same path with the home folder written as ~.
func tilde(_ path: String) -> String {
    let home = NSHomeDirectory()
    return path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
}

/// you@example.com → y••••••@example.com
func maskEmail(_ email: String) -> String {
    guard let at = email.firstIndex(of: "@") else { return email }
    let local = email[..<at]
    return String(local.prefix(1)) + String(repeating: "•", count: max(3, min(local.count - 1, 7))) + email[at...]
}

/// One Claude Code folder cl_quick chats on, with the accounts that have been signed in to it. One of them is in use
/// (the one its .claude.json says); the others are standby: signing in again in the same folder switches to one.
struct Profile: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var name: String
    /// As written (~ allowed).
    var folder: String
    /// Offered in the chat's profile picker.
    var inPicker = true
    /// Every account cl_quick has seen signed in to the folder, the one in use among them.
    var accounts: [KnownAccount] = []

    init(id: String, name: String, folder: String, inPicker: Bool = true, accounts: [KnownAccount] = []) {
        self.id = id; self.name = name; self.folder = folder; self.inPicker = inPicker; self.accounts = accounts
    }
    /// Tolerant: a field added later never makes older profiles.json files unreadable.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        folder = try c.decode(String.self, forKey: .folder)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ClaudeFolder.suggestedName(folder)
        inPicker = (try? c.decodeIfPresent(Bool.self, forKey: .inPicker)) ?? true
        accounts = (try? c.decodeIfPresent([KnownAccount].self, forKey: .accounts)) ?? []
    }

    var path: String { expand(folder) }
    /// The plain ~/.claude: Claude Code runs on it without CLAUDE_CONFIG_DIR, as in Terminal.
    var isDefaultFolder: Bool { ClaudeFolder.isDefault(path) }
    var workFolder: String { Files.work.appendingPathComponent(id).path }
}

/// What a Claude Code folder says about itself, read from its .claude.json (never the Keychain).
enum ClaudeFolder {
    static func isDefault(_ path: String) -> Bool { expand(path) == expand("~/.claude") }

    /// The plain ~/.claude keeps its .claude.json in the home folder; any other folder keeps it inside.
    static func json(_ path: String) -> String {
        isDefault(path) ? expand("~/.claude.json") : (expand(path) as NSString).appendingPathComponent(".claude.json")
    }

    /// The folder's file as it is now: stat'ed at every look, parsed again only when it changed (FolderFiles.fresh).
    private static func read(_ path: String) -> FolderRead { FolderFiles.fresh(json(path)) }

    /// Parses the folders' files off the main thread where they changed, so the next look finds the parse done; `done`
    /// comes on the main thread, after those reads, with whether an account changed.
    static func reload(_ paths: [String], done: @escaping (Bool) -> Void) {
        FolderFiles.reload(Array(Set(paths.map(json))), done: done)
    }

    /// The address Claude Code signed the folder in with; nil when it hasn't.
    static func email(_ path: String) -> String? { read(path).email }

    /// THE ACCOUNT IN USE on a profile, the one answer every part of cl_quick asks for it: the chat's target, the bar,
    /// the menu, Settings, the switch watch, the offers, the menu's refresh. Claude Code's accountUuid (or, in a file
    /// without one, "email:" and the address in lower case) and the address; nil when the folder isn't signed in.
    ///
    /// The rule: it is the folder's .claude.json `oauthAccount` as the file is NOW (stat'ed at every look, parsed again
    /// when its modification time moved), never a copy kept from before, so a sign-in made outside cl_quick (`claude auth
    /// login`, /login in Terminal, cl_audit) is seen at the next look. The file is only what was written last, though:
    /// what a running `claude` reports belongs to the account THAT process says it is (its `initialize` answer,
    /// AccountTrail), and it is recorded only while that is still the account this function returns.
    static func account(_ path: String) -> (uuid: String, email: String)? {
        let r = read(path)
        guard let email = r.email else { return nil }
        return (r.uuid ?? "email:" + email.lowercased(), email)
    }

    /// The organization of the account in use (Claude Code's organizationName), when the file names one.
    static func organization(_ path: String) -> String? { read(path).organization }

    /// The organizationUuid of that account: the same after the organization is renamed.
    static func organizationUuid(_ path: String) -> String? { read(path).organizationUuid }

    /// Claude's name for the plan ("Max"), when Claude Code recorded it.
    static func plan(_ path: String) -> String? { read(path).plan }

    /// A folder cl_quick can chat on: signed in to Claude Code, and not the home folder itself.
    static func usable(_ path: String) -> Bool {
        let p = (expand(path) as NSString).standardizingPath
        // the file as it is now (as every look is): a folder signed in since it was last looked at is accepted
        return p != (NSHomeDirectory() as NSString).standardizingPath && email(p) != nil
    }

    /// ~/.claude and every ~/.claude-* folder, the plain one first. `home` is for the checks.
    static func found(home: String = NSHomeDirectory()) -> [String] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: home)) ?? [])
            .filter { $0 == ".claude" || $0.hasPrefix(".claude-") }
            .filter { n in
                var dir: ObjCBool = false
                return FileManager.default.fileExists(atPath: (home as NSString).appendingPathComponent(n), isDirectory: &dir) && dir.boolValue
            }
            .sorted { a, b in a == ".claude" ? true : b == ".claude" ? false : a < b }
        return names.map { "~/" + $0 }
    }

    /// A name for a folder: Main for ~/.claude, Work for ~/.claude-work.
    static func suggestedName(_ folder: String) -> String {
        let last = (folder as NSString).lastPathComponent
        if last == ".claude" { return "Main" }
        let rest = last.hasPrefix(".claude-") ? String(last.dropFirst(8)) : last.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard let f = rest.first else { return last }
        return f.uppercased() + rest.dropFirst()
    }
}

/// The profiles, the default one, and each one's week as Claude Code last reported it. Main thread only.
final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()

    @Published private(set) var profiles: [Profile] = []
    /// Each account's week as last reported, kept per profile and account: "<profile id>|<account uuid>". A switch shows
    /// the account's own last week, not the one it replaced.
    @Published private(set) var levels: [String: QuickChatLevel] = [:]
    /// By profile id: the account (uuid) Claude Code's last answer failed to authenticate on. In memory only: the chat
    /// sets it, a good answer or a sign-in that landed clears it, and cl_quick starting afresh forgets it.
    @Published private(set) var authFailed: [String: String] = [:]

    private init() {
        profiles = Files.read([Profile].self, Files.profiles) ?? []
        let read = Files.read([String: QuickChatLevel].self, Files.levels) ?? [:]
        levels = Self.migrated(read, profiles: profiles)
        if levels != read { Files.write(levels, Files.levels) }
    }

    static func levelKey(_ profile: String, _ account: String) -> String { AccountBook.levelKey(profile, account) }

    /// A levels.json from before accounts (AccountBook.migrated): each week goes to the account signed in to that
    /// profile's folder now; one that can't be placed stays under its old key.
    static func migrated(_ old: [String: QuickChatLevel], profiles: [Profile],
                         account: (Profile) -> String? = { ClaudeFolder.account($0.path)?.uuid }) -> [String: QuickChatLevel] {
        AccountBook.migrated(old) { id in profiles.first { $0.id == id }.flatMap(account) }
    }

    /// What was last recorded for one account of the profile (the one in use by default), however old; nil: nothing
    /// reported on it yet. Numbers are recorded only for the account in use at the time, from a `claude` that was that
    /// account (`record`, AccountTrail.owner), so these are its own, but they may be from long ago (its last time in use,
    /// or a plan since changed): what is shown and acted on goes through `shownLevel`.
    func level(of p: Profile, account uuid: String? = nil) -> QuickChatLevel? {
        guard let uuid = uuid ?? ClaudeFolder.account(p.path)?.uuid else { return nil }
        return levels[Self.levelKey(p.id, uuid)]
    }

    /// The numbers the chat shows and acts on for the profile's account in use now: only fresh ones
    /// (QuickChatLevel.freshFor). Older numbers never draw a full limit, a refusal, an "Ask on …" or a switch offer:
    /// the bar asks Claude Code again as it opens (get_usage) and shows them once they come.
    func shownLevel(of p: Profile, now: Date = Date()) -> QuickChatLevel? {
        level(of: p).flatMap { $0.isFresh(now) ? $0 : nil }
    }

    var hasProfiles: Bool { !profiles.isEmpty }
    func profile(_ id: String?) -> Profile? { profiles.first { $0.id == id } }

    func save(_ list: [Profile]) {
        profiles = list
        Files.write(list, Files.profiles)
    }

    /// The first run: every folder found that is signed in, named after the folder. Two folders signed in to the same
    /// account never make two profiles: ~/.claude comes first, and a later folder on the same account is left out.
    func adoptFound() {
        guard profiles.isEmpty else { return }
        var list: [Profile] = []
        for f in ClaudeFolder.found() where ClaudeFolder.usable(f) {
            guard let a = ClaudeFolder.account(f),
                  AccountBook.profileUsing(a, among: list.map { ($0.name, $0.accounts.first.map { (uuid: $0.uuid, email: $0.email) }) }) == nil
            else { continue }
            list.append(Profile(id: Self.newID(f, taken: list.map(\.id)), name: ClaudeFolder.suggestedName(f), folder: f,
                                accounts: [KnownAccount(uuid: a.uuid, email: a.email)]))
        }
        save(list)
    }

    /// An id made from the folder's name: "main", "work", "work-2".
    static func newID(_ folder: String, taken: [String]) -> String {
        let base = ClaudeFolder.suggestedName(folder).lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        var id = String(base).isEmpty ? "profile" : String(base), n = 2
        let start = id
        while taken.contains(id) { id = "\(start)-\(n)"; n += 1 }
        return id
    }

    // MARK: accounts

    /// The profile's account in use now (the folder's .claude.json), as a KnownAccount.
    func inUse(_ p: Profile) -> KnownAccount? {
        ClaudeFolder.account(p.path).map { a in p.accounts.first { $0.uuid == a.uuid } ?? KnownAccount(uuid: a.uuid, email: a.email) }
    }

    /// What is wrong with the profile's sign-in, if anything (SignInProblem): as the folder's file says now.
    func signInProblem(_ p: Profile) -> SignInProblem? {
        AccountBook.signInProblem(signedIn: ClaudeFolder.account(p.path), failedOn: authFailed[p.id])
    }

    /// The chat's answer on an account: it failed to authenticate (flag set), or it worked (flag cleared).
    func authResult(_ id: String, account uuid: String, failed: Bool) {
        guard profile(id) != nil else { return }
        if failed { if authFailed[id] != uuid { authFailed[id] = uuid } }
        else if authFailed[id] != nil { authFailed[id] = nil }
    }

    /// A sign-in landed on the profile's folder: whatever failed before is behind it.
    func signedIn(_ id: String) { if authFailed[id] != nil { authFailed[id] = nil } }

    /// The accounts signed in before and not in use now, the most recently seen first.
    func standby(_ p: Profile) -> [KnownAccount] {
        let current = ClaudeFolder.account(p.path)
        return p.accounts.filter { $0.uuid != current?.uuid }.sorted { $0.lastSeen > $1.lastSeen }
    }

    /// Whenever cl_quick looks at a profile's folder, the account signed in to it is added to the profile, or its address
    /// and last-seen time updated (found by its uuid). Addresses only; the time is kept to the hour so a busy chat
    /// doesn't write the file at every look. Main thread; not from a view's body.
    func noteAccount(of id: String, now: Date = Date()) {
        guard let p = profile(id) else { return }
        // signed out: that is the problem now, and signing back in (even as the same account) starts clean
        guard let a = ClaudeFolder.account(p.path) else { if authFailed[id] != nil { authFailed[id] = nil }; return }
        // a failure was on another account than the one signed in now: it doesn't come back if that one does
        if let failed = authFailed[id], failed != a.uuid { authFailed[id] = nil }
        var q = p
        let r = AccountBook.note(&q.accounts, uuid: a.uuid, email: a.email, now: now)
        guard r.changed else { return }
        // a file that first had no accountUuid and now has one: its week moves to the new key
        if let was = r.replaced {
            let old = AccountBook.levelKey(id, was), new = AccountBook.levelKey(id, a.uuid)
            if let l = levels[old], levels[new] == nil {
                levels[new] = l; levels[old] = nil
                Files.write(levels, Files.levels)
            }
        }
        update(q)
    }

    /// Every profile's folder looked at once (Settings opens, the menu opens, cl_quick starts).
    func noteAccounts() { profiles.map(\.id).forEach { noteAccount(of: $0) } }

    /// The folders' files read again off the main thread (all the profiles', or the named ones); then their accounts
    /// are noted, and if one changed, AccountSwitcher.changed is posted so the chat and Settings draw again.
    func reload(_ ids: [String]? = nil) {
        let paths = profiles.filter { ids?.contains($0.id) ?? true }.map(\.path)
        ClaudeFolder.reload(paths) { [weak self] changed in
            self?.noteAccounts()
            if changed { NotificationCenter.default.post(name: AccountSwitcher.changed, object: nil) }
        }
    }

    func add(_ p: Profile) { save(profiles + [p]); noteAccount(of: p.id) }
    func update(_ p: Profile) { save(profiles.map { $0.id == p.id ? p : $0 }) }
    /// cl_quick forgets the profile; its folder and sessions stay.
    func remove(_ id: String) {
        save(profiles.filter { $0.id != id })
        levels = AccountBook.removing(profile: id, from: levels)
        Files.write(levels, Files.levels)
    }
    /// A folder already used by a profile.
    func uses(_ folder: String) -> Bool { profiles.contains { $0.path == expand(folder) } }

    /// The name of the profile whose folder has this account signed in now, if any: one account never
    /// makes two profiles.
    func nameUsing(_ account: (uuid: String, email: String)) -> String? {
        AccountBook.profileUsing(account, among: profiles.map { ($0.name, ClaudeFolder.account($0.path)) })
    }

    /// What is said when a folder's account is in use on another profile.
    static func inUseWords(_ email: String, on profile: String) -> String { "\(maskEmail(email)) is already in use on \(profile)." }

    /// cl_quick forgets a standby account of a profile, and its week. The account in use (as the folder's file says right
    /// now) is never forgotten. Returns whether it was.
    @discardableResult
    func forget(account uuid: String, of id: String) -> Bool {
        guard let p = profile(id) else { return false }
        let now = ClaudeFolder.account(p.path)
        guard let r = AccountBook.forgetting(uuid, of: id, accounts: p.accounts, levels: levels,
                                             inUse: now?.uuid, inUseEmail: now?.email) else { return false }
        var q = p
        q.accounts = r.accounts
        update(q)
        if r.levels != levels { levels = r.levels; Files.write(levels, Files.levels) }
        return true
    }

    /// What Claude Code said on this profile, on the account that answered. Recorded only while that is the account in
    /// use (ClaudeFolder.account, the file as it is now): numbers are never kept under an account the folder has left,
    /// nor put on the one it moved to (the callers check the process too: AccountTrail.owner).
    func record(_ id: String, account uuid: String, _ level: QuickChatLevel) {
        let key = Self.levelKey(id, uuid)
        guard let p = profile(id), levels[key] != level else { return }      // a profile removed meanwhile stays gone
        guard ClaudeFolder.account(p.path)?.uuid == uuid else { return }
        levels[key] = level
        Files.write(levels, Files.levels)
    }
}
