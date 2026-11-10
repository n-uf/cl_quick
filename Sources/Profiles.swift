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

/// An account that was signed in to a profile's folder: its address and when cl_quick last saw it there. Never a token.
struct KnownAccount: Codable, Identifiable, Equatable, Hashable {
    /// Claude Code's accountUuid (the address in lower case, behind "email:", when its file has none).
    var uuid: String
    var email: String
    var lastSeen: Date
    var id: String { uuid }

    init(uuid: String, email: String, lastSeen: Date = Date()) { self.uuid = uuid; self.email = email; self.lastSeen = lastSeen }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uuid = try c.decode(String.self, forKey: .uuid)
        email = try c.decode(String.self, forKey: .email)
        lastSeen = (try? c.decodeIfPresent(Date.self, forKey: .lastSeen)) ?? Date()
    }
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

    /// What was read from a .claude.json: it can be several MB and changes often (every Claude Code session writes it).
    /// Views, the chat and the 2 s sign-in watch read only this value, kept per folder (account, email, plan below);
    /// the file itself is read again off the main thread by `reload`, and once, on the spot, the first time a folder is
    /// looked at.
    private struct Read { var mtime: Date?; var email: String?; var uuid: String?; var plan: String? }
    private static var cache: [String: Read] = [:]
    private static var inflight = Set<String>()
    private static let lock = NSLock()
    private static let queue = DispatchQueue(label: "cl_quick.folder-reads", qos: .utility)

    /// The value kept for the folder; read from the file only when the folder was never looked at.
    private static func read(_ path: String) -> Read {
        let file = json(path)
        lock.lock(); let hit = cache[file]; lock.unlock()
        return hit ?? fresh(file)
    }

    /// Reads the files again, off the main thread, when they changed since the last look; `done` comes on the main
    /// thread with whether an account changed. A folder already being read is left to that read.
    static func reload(_ paths: [String], done: @escaping (Bool) -> Void) {
        let files = Array(Set(paths.map(json)))
        lock.lock()
        let todo = files.filter { inflight.insert($0).inserted }
        let before = todo.map { cache[$0] }
        lock.unlock()
        guard !todo.isEmpty else { DispatchQueue.main.async { done(false) }; return }
        queue.async {
            var changed = false
            for (i, f) in todo.enumerated() {
                let r = fresh(f)
                if r.email != before[i]?.email || r.uuid != before[i]?.uuid { changed = true }
                lock.lock(); inflight.remove(f); lock.unlock()
            }
            DispatchQueue.main.async { done(changed) }
        }
    }

    /// The file as it is now: parsed again only if its modification time moved.
    private static func fresh(_ file: String) -> Read {
        let mtime = (try? FileManager.default.attributesOfItem(atPath: file))?[.modificationDate] as? Date
        lock.lock(); let hit = cache[file]; lock.unlock()
        if let hit, hit.mtime == mtime { return hit }
        var r = Read(mtime: mtime)
        if let d = FileManager.default.contents(atPath: file),
           let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
           let a = j["oauthAccount"] as? [String: Any] {
            r.email = a["emailAddress"] as? String
            r.uuid = (a["accountUuid"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            if let p = a["planDisplayName"] as? String, !p.trimmingCharacters(in: .whitespaces).isEmpty {
                r.plan = p == p.lowercased() ? p.capitalized : p
            }
        }
        lock.lock(); cache[file] = r; lock.unlock()
        return r
    }

    /// The address Claude Code signed the folder in with; nil when it hasn't.
    static func email(_ path: String) -> String? { read(path).email }

    /// The account signed in to the folder: Claude Code's accountUuid (or, in a file without one, "email:" and the
    /// address in lower case) and the address. nil when it isn't signed in.
    static func account(_ path: String) -> (uuid: String, email: String)? {
        let r = read(path)
        guard let email = r.email else { return nil }
        return (r.uuid ?? "email:" + email.lowercased(), email)
    }

    /// Claude's name for the plan ("Max"), when Claude Code recorded it.
    static func plan(_ path: String) -> String? { read(path).plan }

    /// A folder cl_quick can chat on: signed in to Claude Code, and not the home folder itself.
    static func usable(_ path: String) -> Bool {
        let p = (expand(path) as NSString).standardizingPath
        return p != (NSHomeDirectory() as NSString).standardizingPath && fresh(json(p)).email != nil
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

    private init() {
        profiles = Files.read([Profile].self, Files.profiles) ?? []
        let read = Files.read([String: QuickChatLevel].self, Files.levels) ?? [:]
        levels = Self.migrated(read, profiles: profiles)
        if levels != read { Files.write(levels, Files.levels) }
    }

    static func levelKey(_ profile: String, _ account: String) -> String { profile + "|" + account }

    /// A levels.json from before accounts was keyed by profile id alone: each such week goes to the account signed in to
    /// that profile's folder now (the one it was reported on, unless it was switched meanwhile); one whose profile or
    /// account can't be told is dropped. Keys already per account stay.
    static func migrated(_ old: [String: QuickChatLevel], profiles: [Profile],
                         account: (Profile) -> String? = { ClaudeFolder.account($0.path)?.uuid }) -> [String: QuickChatLevel] {
        var out = old.filter { $0.key.contains("|") }
        for (id, l) in old where !id.contains("|") {
            guard let p = profiles.first(where: { $0.id == id }), let uuid = account(p) else { continue }
            let key = levelKey(id, uuid)
            if out[key] == nil { out[key] = l }
        }
        return out
    }

    /// The profile's week for one account: the one in use by default; nil: nothing reported on it yet.
    func level(of p: Profile, account uuid: String? = nil) -> QuickChatLevel? {
        guard let uuid = uuid ?? ClaudeFolder.account(p.path)?.uuid else { return nil }
        return levels[Self.levelKey(p.id, uuid)]
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
        var seen = Set<String>()        // account uuids and addresses already taken by an earlier folder
        for f in ClaudeFolder.found() where ClaudeFolder.usable(f) {
            guard let a = ClaudeFolder.account(f), !seen.contains(a.uuid), !seen.contains(a.email.lowercased()) else { continue }
            seen.insert(a.uuid); seen.insert(a.email.lowercased())
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

    /// The accounts signed in before and not in use now, the most recently seen first.
    func standby(_ p: Profile) -> [KnownAccount] {
        let current = ClaudeFolder.account(p.path)
        return p.accounts.filter { $0.uuid != current?.uuid }.sorted { $0.lastSeen > $1.lastSeen }
    }

    /// Whenever cl_quick looks at a profile's folder, the account signed in to it is added to the profile, or its address
    /// and last-seen time updated (found by its uuid). Addresses only; the time is kept to the hour so a busy chat
    /// doesn't write the file at every look. Main thread; not from a view's body.
    func noteAccount(of id: String, now: Date = Date()) {
        guard let p = profile(id), let a = ClaudeFolder.account(p.path) else { return }
        var q = p
        if let k = q.accounts.firstIndex(where: { $0.uuid == a.uuid })
            ?? q.accounts.firstIndex(where: { $0.email.lowercased() == a.email.lowercased() }) {
            guard q.accounts[k].uuid != a.uuid || q.accounts[k].email != a.email || now.timeIntervalSince(q.accounts[k].lastSeen) > 3600 else { return }
            // a file that first had no accountUuid and now has one: its week moves to the new key
            let old = Self.levelKey(id, q.accounts[k].uuid), new = Self.levelKey(id, a.uuid)
            if old != new, let l = levels[old], levels[new] == nil {
                levels[new] = l; levels[old] = nil
                Files.write(levels, Files.levels)
            }
            q.accounts[k].uuid = a.uuid; q.accounts[k].email = a.email; q.accounts[k].lastSeen = now
        } else {
            q.accounts.append(KnownAccount(uuid: a.uuid, email: a.email, lastSeen: now))
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
        levels = levels.filter { !$0.key.hasPrefix(id + "|") }
        Files.write(levels, Files.levels)
    }
    /// A folder already used by a profile.
    func uses(_ folder: String) -> Bool { profiles.contains { $0.path == expand(folder) } }

    /// What Claude Code said after an answer on this profile, on the account that answered.
    func record(_ id: String, account uuid: String, _ level: QuickChatLevel) {
        let key = Self.levelKey(id, uuid)
        guard profile(id) != nil, levels[key] != level else { return }      // a profile removed meanwhile stays gone
        levels[key] = level
        Files.write(levels, Files.levels)
    }
}
