// Profiles: the Claude Code folders cl_quick chats on, picked by you (Settings), with the account signed in to each and
// its week as Claude Code last reported it. cl_quick reads only each folder's own .claude.json for the account (through
// the kit's FolderRecordReader, Accounts.swift); it never touches the Keychain and reads no usage of its own.
//
// Its files, all in ~/Library/Application Support/cl_quick/: profiles.json, settings.json, levels.json, and work/<id>/
// (the folders Claude Code runs the chats in).

import ClaudeAuth
import Foundation

func expand(_ path: String) -> String { (path as NSString).expandingTildeInPath }

/// The same path with the home folder written as ~.
func tilde(_ path: String) -> String {
    let home = NSHomeDirectory()
    return path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
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

    /// Parses the folders' files off the main thread where they changed, so the next look finds the parse done; `done`
    /// comes on the main thread, after those reads, with whether an account changed.
    static func reload(_ paths: [String], done: @escaping (Bool) -> Void) {
        FolderRecords.reload(Array(Set(paths.map(json))), done: done)
    }

    /// The address Claude Code signed the folder in with; nil when it names none.
    static func email(_ path: String) -> String? { account(path)?.email }

    /// THE ACCOUNT CLAUDE CODE'S RECORD NAMES on a profile's folder, the one read every part of cl_quick asks for it: the
    /// chat's target, the bar, the menu, Settings, the switch watch, the offers, the menu's refresh. Its account id,
    /// address, organisation (id and name) and plan, as the record says them (guessed: SignedInAccount.record); nil when
    /// the folder isn't signed in (the record names no id and no address).
    ///
    /// The rule (the kit's, decided 2026-11-22): it is the folder's .claude.json `oauthAccount` as the file is NOW (one stat
    /// at every look, parsed again when its stamp moved: FolderRecordReader), never a copy kept from before, so a sign-in
    /// made outside cl_quick (`claude auth login`, /login in Terminal, cl_audit) is seen at the next look. The record is
    /// only what was written last, though: what a running `claude` reports belongs to the account THAT process says it is
    /// (its `initialize` answer, ProcessTrail and FolderSignIn.answer: AccountBook.numbersOwner), never moved onto the
    /// record's when the two disagree.
    static func account(_ path: String) -> SignedInAccount? { FolderRecords.look(json(path)).account }

    /// Claude's name for the plan ("Max"), when Claude Code recorded it.
    static func plan(_ path: String) -> String? {
        account(path)?.plan.map { $0 == $0.lowercased() ? $0.capitalized : $0 }
    }

    /// A folder cl_quick can chat on: signed in to Claude Code, and not the home folder itself.
    static func usable(_ path: String) -> Bool {
        let p = (expand(path) as NSString).standardizingPath
        // the file as it is now (as every look is): a folder signed in since it was last looked at is accepted
        return p != (NSHomeDirectory() as NSString).standardizingPath && account(p) != nil
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
    /// Each seat's week as last reported, kept per profile and seat (AccountBook.levelKey: "<profile id>|<account>" while
    /// the seat isn't known, "<profile id>|<account>|<organisation>" once it is). A switch shows the seat's own last week,
    /// not the one it replaced.
    @Published private(set) var levels: [String: QuickChatLevel] = [:]
    /// By profile id: the seat Claude Code's last answer failed to authenticate on. In memory only: the chat sets it, a
    /// good answer or a sign-in that landed clears it, and cl_quick starting afresh forgets it.
    @Published private(set) var authFailed: [String: AccountKey] = [:]

    private init() {
        profiles = Files.read([Profile].self, Files.profiles) ?? []
        let read = Files.read([String: QuickChatLevel].self, Files.levels) ?? [:]
        // keys as the kit writes them (AccountKey); one an older build wrote ("<profile>|<uuid>") is a seat not known yet,
        // upgraded in place only when the numbers' own source names its seat (record)
        levels = AccountBook.normalizedKeys(Self.migrated(read, profiles: profiles))
        if levels != read { write(levels, Files.levels) }
    }

    /// The files this run has backed up (or found backed up) before its first rewrite of them.
    private var backedUp: Set<URL> = []

    /// Writes one of the store's files (profiles.json, levels.json); before this run's first rewrite of it, the file as
    /// it was is kept once beside it (StoredKeys.keepBackup: profiles.json.pre-26.11.4), never over a backup already there.
    /// Nothing while only checking or drawing (Files.readOnly).
    @discardableResult
    private func write<T: Encodable>(_ value: T, _ url: URL) -> Bool {
        guard !Files.readOnly else { return false }
        if !backedUp.contains(url) {
            try? FileManager.default.createDirectory(at: Files.folder, withIntermediateDirectories: true)
            StoredKeys.keepBackup(of: url)
            backedUp.insert(url)
        }
        return Files.write(value, url)
    }

    static func levelKey(_ profile: String, _ key: AccountKey) -> String { AccountBook.levelKey(profile, key) }

    /// A levels.json from before accounts (AccountBook.migrated): each week goes to the seat signed in to that profile's
    /// folder now; one that can't be placed stays under its old key.
    static func migrated(_ old: [String: QuickChatLevel], profiles: [Profile],
                         account: (Profile) -> AccountKey? = { AccountBook.inUse(ClaudeFolder.account($0.path), in: $0.accounts)?.key })
        -> [String: QuickChatLevel] {
        AccountBook.migrated(old) { id in profiles.first { $0.id == id }.flatMap(account) }
    }

    /// What was last recorded for one seat of the profile (the one in use by default), however old; nil: nothing
    /// reported on it yet. Numbers are recorded for the seat they belong to (`record`, AccountBook.numbersOwner), so these
    /// are its own, but they may be from long ago (its last time in use, or a plan since changed): what is shown and acted
    /// on goes through `shownLevel`.
    func level(of p: Profile, account key: AccountKey? = nil) -> QuickChatLevel? {
        guard let key = key ?? inUse(p)?.key else { return nil }
        return levels[Self.levelKey(p.id, key)]
    }

    /// The numbers kept for the seat `owner` is, in profile `id`, for new ones to be applied on (AccountBook.numbersBase).
    func base(_ id: String, for owner: SignedInAccount) -> QuickChatLevel? {
        guard let p = profile(id) else { return nil }
        return AccountBook.numbersBase(for: owner, profile: id, accounts: p.accounts, levels: levels)
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
        write(list, Files.profiles)
    }

    /// The first run: every folder found that is signed in, named after the folder. Two folders signed in to the same
    /// account never make two profiles: ~/.claude comes first, and a later folder on the same account is left out.
    func adoptFound() {
        guard profiles.isEmpty else { return }
        var list: [Profile] = []
        for f in ClaudeFolder.found() where ClaudeFolder.usable(f) {
            guard let a = ClaudeFolder.account(f), let key = AccountKey(a),
                  AccountBook.profileUsing(a, among: list.map { ($0.name, $0.accounts.first?.identity) }) == nil
            else { continue }
            list.append(Profile(id: Self.newID(f, taken: list.map(\.id)), name: ClaudeFolder.suggestedName(f), folder: f,
                                accounts: [KnownAccount(key: key, email: a.email ?? "")]))
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

    /// The profile's account in use now (the folder's .claude.json), as its list knows it (AccountBook.inUse: the entry
    /// of its seat, or of its account while the seat isn't known).
    func inUse(_ p: Profile) -> KnownAccount? { AccountBook.inUse(ClaudeFolder.account(p.path), in: p.accounts) }

    /// What is wrong with the profile's sign-in, if anything (SignInProblem): as the folder's file says now.
    func signInProblem(_ p: Profile) -> SignInProblem? {
        AccountBook.signInProblem(signedIn: inUse(p)?.key, failedOn: authFailed[p.id])
    }

    /// The chat's answer on an account (the one its numbers belong to): it failed to authenticate (flag set on that seat),
    /// or it worked (flag cleared).
    /// Only an answer from the account in use counts (AccountBook.answersForFolder): a stale process on another account
    /// never sets or clears the flag.
    func authResult(_ id: String, account: SignedInAccount, failed: Bool) {
        guard let p = profile(id) else { return }
        let record = ClaudeFolder.account(p.path)
        guard AccountBook.answersForFolder(account, record: record) else { return }
        if failed {
            guard let key = AccountBook.inUse(record, in: p.accounts)?.key else { return }
            if authFailed[id] != key { authFailed[id] = key }
        }
        else if authFailed[id] != nil { authFailed[id] = nil }
    }

    /// A sign-in landed on the profile's folder: whatever failed before is behind it.
    func signedIn(_ id: String) { if authFailed[id] != nil { authFailed[id] = nil } }

    /// The seats signed in before and not in use now, tidied per seat (AccountBook.standby, the kit's StandbyTidy), the
    /// most recently seen first.
    func standby(_ p: Profile) -> [KnownAccount] { AccountBook.standby(p.accounts, inUse: ClaudeFolder.account(p.path)) }

    /// Whenever cl_quick looks at a profile's folder, the seat signed in to it is added to the profile, or its address and
    /// last-seen time updated (AccountBook.note). Addresses only; the time is kept to the hour so a busy chat doesn't
    /// write the file at every look. Main thread; not from a view's body.
    func noteAccount(of id: String, now: Date = Date()) {
        guard let p = profile(id) else { return }
        // signed out: that is the problem now, and signing back in (even as the same account) starts clean
        guard let a = ClaudeFolder.account(p.path) else { if authFailed[id] != nil { authFailed[id] = nil }; return }
        // a failure was on another seat than the one signed in now: it doesn't come back if that one does
        if let failed = authFailed[id], failed != AccountBook.inUse(a, in: p.accounts)?.key { authFailed[id] = nil }
        var q = p
        let r = AccountBook.note(&q.accounts, a, now: now)
        guard r.changed else { return }
        // a key upgraded in place (a record that first had no accountUuid and now has one): its week moves with it, and so
        // do numbers kept under a placeholder of that seat before it was noted (never two, never one dropped)
        if let now = AccountBook.inUse(a, in: q.accounts)?.key {
            var moved = levels
            if let was = r.replaced {
                let old = AccountBook.levelKey(id, was), new = AccountBook.levelKey(id, now)
                if let l = moved[old], moved[new] == nil { moved[new] = l; moved[old] = nil }
            }
            moved = AccountBook.upgradingLevels(moved, profile: id, to: now, record: a)
            if moved != levels { levels = moved; write(levels, Files.levels) }
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
        write(levels, Files.levels)
    }
    /// A folder already used by a profile.
    func uses(_ folder: String) -> Bool { profiles.contains { $0.path == expand(folder) } }

    /// The name of the profile whose folder has this account (maybe the same seat) signed in now, if any: one seat never
    /// makes two profiles.
    func nameUsing(_ account: SignedInAccount) -> String? {
        AccountBook.profileUsing(account, among: profiles.map { ($0.name, ClaudeFolder.account($0.path)) })
    }

    /// cl_quick forgets a standby seat of a profile, and its week. The account in use (as the folder's file says right
    /// now) is never forgotten. Returns whether it was.
    @discardableResult
    func forget(account key: AccountKey, of id: String) -> Bool {
        guard let p = profile(id) else { return false }
        guard let r = AccountBook.forgetting(key, of: id, accounts: p.accounts, levels: levels,
                                             inUse: ClaudeFolder.account(p.path)) else { return false }
        var q = p
        q.accounts = r.accounts
        update(q)
        if r.levels != levels { levels = r.levels; write(levels, Files.levels) }
        return true
    }

    /// What Claude Code said on this profile, kept for the account it belongs to (`owner`: the kit's numbersBelongTo,
    /// AccountBook.numbersOwner): under that seat, also when the folder has moved to another account since (the numbers are
    /// still that seat's own), never under the account the folder is on now unless it is that seat. An entry whose seat
    /// wasn't known (from before seats) is upgraded in place to the seat the numbers named (AccountBook.recording).
    func record(_ id: String, account owner: SignedInAccount, _ level: QuickChatLevel) {
        guard let p = profile(id),                                             // a profile removed meanwhile stays gone
              let r = AccountBook.recording(level, for: owner, profile: id, accounts: p.accounts, levels: levels) else { return }
        if r.accounts != p.accounts { var q = p; q.accounts = r.accounts; update(q) }
        guard r.levels != levels else { return }
        levels = r.levels
        write(levels, Files.levels)
    }
}
