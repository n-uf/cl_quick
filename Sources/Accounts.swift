// Accounts: the bookkeeping of a profile's accounts, on cl_kit's one account rule (ClaudeAuth and ProfileCore, vendored in
// Vendor/): the accounts remembered per profile and the keys their weeks are kept under (AccountKey: the account id and
// its organisation, so a personal plan and a Team seat on one address are two), the folders' records (the kit's one
// FolderRecordReader), and whose numbers a running claude's are (ProcessTrail, FolderSignIn.answer). Pure functions where
// it can, so Checks/run.sh checks them.

import ClaudeAuth
import Foundation
import ProfileCore

/// A seat that was signed in to a profile's folder: its key, its address and when cl_quick last saw it there. Never a token.
struct KnownAccount: Codable, Identifiable, Equatable, Hashable {
    /// The key's account: Claude Code's accountUuid, or "email:" and the address in lower case while the record named no
    /// id (AccountKey's placeholder, upgraded in place once the id appears). Called `uuid` as older builds write it.
    var uuid: String
    /// The key's organisation: its organizationUuid (or "name:" and its name until the id is known); nil while the seat
    /// isn't known (an entry an older build wrote, or a record that names no organisation). Older builds don't read it.
    var organization: String?
    var email: String
    var lastSeen: Date

    init(key: AccountKey, email: String, lastSeen: Date = Date()) {
        uuid = key.account; organization = key.organization; self.email = email; self.lastSeen = lastSeen
    }
    init(uuid: String, organization: String? = nil, email: String, lastSeen: Date = Date()) {
        self.init(key: AccountKey(account: uuid, organization: organization), email: email, lastSeen: lastSeen)
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let account = try c.decode(String.self, forKey: .uuid)
        let org = (try? c.decodeIfPresent(String.self, forKey: .organization)).flatMap { $0?.isEmpty == false ? $0 : nil }
        self.init(key: AccountKey(account: account, organization: org), email: try c.decode(String.self, forKey: .email),
                  lastSeen: (try? c.decodeIfPresent(Date.self, forKey: .lastSeen)) ?? Date())
    }

    /// The seat it is kept under (AccountKey: case doesn't count).
    var key: AccountKey { AccountKey(account: uuid, organization: organization) }
    var id: String { key.text }
    /// Known by its address only (no account id yet).
    var isPlaceholder: Bool { key.isPlaceholder }
    /// The entry as an account: its key, with its address.
    var identity: SignedInAccount { AccountBook.identity(key, email: email) }
}

/// The folders' records (.claude.json), through the kit's one reader (FolderRecordReader: named fields only, bounded, one
/// stat per look, parsed again only after a write), so a sign-in made outside cl_quick is seen at the next look. A file can
/// be several MB and changes often (every Claude Code session writes it), so `reload` parses the files on one serial
/// utility queue first where it can, and the look on the main thread then finds the parse done. Every reload is queued
/// behind the reads before it, so its `done` sees the file as it was when the reload was asked for.
enum FolderRecords {
    static let reader = FolderRecordReader()
    private static let queue = DispatchQueue(label: "cl_quick.folder-reads", qos: .utility)
    /// Posted (main thread) when a look finds the record naming someone else (another account or seat, a sign-in, a
    /// sign-out), whoever looked: a look on the main thread (the menu opening, a SwiftUI body) as much as a `reload`.
    static let accountChanged = Notification.Name("cl_quick.accountSwitch.changed")

    /// The record at `file` now. Only the look whose own parse found a change sees `changed` (the reader's rule), so each
    /// change is signalled once: by this look (`accountChanged`, on the main thread), or, with `signal` false, by the
    /// caller (`reload` tells its own caller, so that caller can note the accounts first).
    @discardableResult
    static func look(_ file: String, signal: Bool = true) -> FolderRecordReader.Look {
        let l = reader.look(path: file)
        if l.changed && signal {
            DispatchQueue.main.async { NotificationCenter.default.post(name: accountChanged, object: nil) }
        }
        return l
    }

    /// Reads the files again, off the main thread (parsing only those whose stamp moved); `done` comes on the main thread
    /// with whether one of them now names someone else (and nobody was told yet). The caller posts `accountChanged`
    /// itself on true, after its own bookkeeping.
    static func reload(_ files: [String], done: @escaping (Bool) -> Void) {
        queue.async {
            var changed = false
            for f in files where look(f, signal: false).changed { changed = true }
            DispatchQueue.main.async { done(changed) }
        }
    }
}

/// Why a profile's sign-in needs doing again; none while it works.
enum SignInProblem: Equatable {
    /// The folder has no signed-in account.
    case signedOut
    /// Claude Code's last answer on the account in use failed with authentication_failed.
    case stopped

    var words: String { self == .signedOut ? "Signed out." : "The sign-in stopped working." }
}

enum AccountBook {
    /// "Sign in again…" is for a sign-in that is broken: no account signed in to the folder, or the account in use failed
    /// to authenticate on the last answer (`failedOn`: the seat it failed on, kept in memory only). A flag for another
    /// account or seat says nothing about this one.
    static func signInProblem(signedIn: AccountKey?, failedOn: AccountKey?) -> SignInProblem? {
        guard let signedIn else { return .signedOut }
        return failedOn == signedIn ? .stopped : nil
    }

    /// What a switch affects, for its confirmation: Claude Code on the folder (in Terminal and editors for ~/.claude,
    /// the uses pointed at it with CLAUDE_CONFIG_DIR for any other), sessions running now included; not the Claude app,
    /// which runs its own claude with its own sign-in. The account is "this account": its address is shown apart from
    /// the words (under them, blurred), never in them. Its last line: the browser decides which account signs in, so it
    /// must be on this one first.
    static func switchWords(folder: String, isDefault: Bool) -> String {
        (isDefault ? "Claude Code in Terminal and editors on \(folder)" : "Claude Code pointed at \(folder) with CLAUDE_CONFIG_DIR")
            + " moves to this account, sessions running now included; the Claude app keeps its own sign-in."
            + " Finish the sign-in in Terminal and the browser as that account.\n\n" + browserFirst
    }

    /// The switch question's last line.
    static let browserFirst = "The browser must be signed in to claude.ai as this account. If it's on another one, switch it there first."

    /// "just now", "12 min ago", "3 h ago", "yesterday", "4 days ago", "3 weeks ago".
    static func ago(_ d: Date, now: Date = Date()) -> String {
        let s = max(0, now.timeIntervalSince(d))
        switch s {
        case ..<60: return "just now"
        case ..<3600: return "\(Int(s / 60)) min ago"
        case ..<86400: return "\(Int(s / 3600)) h ago"
        case ..<(2 * 86400): return "yesterday"
        case ..<(14 * 86400): return "\(Int(s / 86400)) days ago"
        default: return "\(Int(s / (7 * 86400))) weeks ago"
        }
    }

    // MARK: the seat rule (the kit's: ClaudeAuth's AccountKey and FolderSignIn, ProfileCore's one seat comparison)

    /// A key as an account, with an address beside it (the key keeps one only while it is a placeholder).
    static func identity(_ key: AccountKey, email: String?) -> SignedInAccount {
        var a = key.identity
        if a.email == nil, let e = email, !e.isEmpty { a.email = e }
        return a
    }

    /// Another account or seat: two keys (each with its address) that the one seat comparison tells apart. A placeholder
    /// upgraded to its id, or a seat that was only not known, is the same one.
    static func anotherSeat(_ a: AccountKey?, _ aEmail: String?, _ b: AccountKey?, _ bEmail: String?) -> Bool {
        guard let a, let b else { return false }
        return identity(a, email: aEmail).match(identity(b, email: bEmail)) == .different
    }

    /// The entry of a profile's list an account is (the record's account in use, or the account numbers belong to): the
    /// same key, else the same seat (AccountKey.match), else an entry of that account whose seat isn't known (an entry an
    /// older build wrote, before seats). nil: none of them.
    static func entryIndex(for a: SignedInAccount, in list: [KnownAccount]) -> Int? {
        if let k = AccountKey(a), let i = list.firstIndex(where: { $0.key == k }) { return i }
        if let i = list.firstIndex(where: { $0.key.match(a) == .seat }) { return i }
        return list.firstIndex { $0.organization == nil && $0.key.match(a) == .seatNotKnown }
    }

    /// The profile's account in use, as its list knows it: the entry the record is (entryIndex), else one made from the
    /// record. nil when the folder isn't signed in.
    static func inUse(_ record: SignedInAccount?, in list: [KnownAccount]) -> KnownAccount? {
        guard let r = record, let key = AccountKey(r) else { return nil }
        if let i = entryIndex(for: r, in: list) { return list[i] }
        return KnownAccount(key: key, email: r.email ?? "")
    }

    /// Notes the account the record names in a profile's list: found by entryIndex, its address and last-seen time
    /// updated (kept to the hour), its key upgraded as the kit does (an "email:" placeholder to the account id, a "name:"
    /// one to the organisation's id of the same seat; never onto another seat, and never a seat given to an entry whose
    /// seat isn't known: the record is only a guess, the numbers' own source names that). A new seat is added. Returns
    /// whether the list changed, and the key it replaced when the key itself was upgraded.
    @discardableResult
    static func note(_ list: inout [KnownAccount], _ r: SignedInAccount, now: Date = Date()) -> (changed: Bool, replaced: AccountKey?) {
        guard let key = AccountKey(r) else { return (false, nil) }
        guard let i = entryIndex(for: r, in: list) else {
            list.append(KnownAccount(key: key, email: r.email ?? "", lastSeen: now))
            return (true, nil)
        }
        let old = list[i]
        var up = old.key.upgraded(with: r) ?? old.key
        if up != old.key, list.contains(where: { $0.key == up }) { up = old.key }      // never two entries for one seat
        let email = r.email ?? old.email
        guard up != old.key || email != old.email || now.timeIntervalSince(old.lastSeen) > 3600 else { return (false, nil) }
        list[i] = KnownAccount(key: up, email: email, lastSeen: now)
        return (true, up != old.key ? old.key : nil)
    }

    /// The name of the profile the account is maybe in use on (SignedInAccount.maybeSame: the same seat, or the same
    /// account whose seat isn't known), among profiles given as (name, the account signed in to its folder now); nil when
    /// no profile uses it. A personal plan and a Team seat on one address are two: each may be one profile's.
    static func profileUsing(_ account: SignedInAccount, among profiles: [(name: String, inUse: SignedInAccount?)]) -> String? {
        profiles.first { p in p.inUse.map { $0.maybeSame(account) } ?? false }?.name
    }

    /// A profile's standby accounts: its list but the account in use (the record's), tidied by the kit's rule
    /// (StandbyTidy, per seat: one entry per seat, never the account in use, an entry whose seat isn't known joining its
    /// account's one seat), the most recently seen first. A personal plan and a Team seat on one address are two.
    static func standby(_ list: [KnownAccount], inUse record: SignedInAccount?) -> [KnownAccount] {
        let own = record.flatMap { entryIndex(for: $0, in: list) }
        let rest = list.indices.filter { $0 != own }.map { list[$0] }
        let ownSeat = record.flatMap(AccountKey.init).flatMap(seat)
        let tidied = StandbyTidy.merge([], into: rest.map(standbyEntry), inUse: ownSeat)
        return tidied.map(knownAccount).sorted { $0.lastSeen > $1.lastSeen }
    }

    /// A key as ProfileCore's seat; nil for an address placeholder (no account id yet).
    static func seat(_ k: AccountKey) -> Seat? { k.isPlaceholder ? nil : Seat(account: k.account, organization: k.organization) }

    private static func standbyEntry(_ a: KnownAccount) -> StandbyAccount {
        StandbyAccount(email: a.email, seat: seat(a.key), addedAt: nil, id: a.id, lastInUse: a.lastSeen)
    }

    private static func knownAccount(_ s: StandbyAccount) -> KnownAccount {
        let key = s.seat.map { AccountKey(account: $0.account, organization: $0.organization) }
            ?? AccountKey(text: s.id) ?? AccountKey(account: AccountKey.addressPrefix + s.email.lowercased())
        return KnownAccount(key: key, email: s.email, lastSeen: s.lastInUse ?? .distantPast)
    }

    // MARK: whose numbers a running claude's are

    /// Whose the numbers a running claude reports are (the kit's FolderSignIn.answer(record:trail:).numbersBelongTo): its
    /// own word's account (with the launch record's ids when it named the seat it started on), kept for that account even
    /// when the record names another one now (never put on the record's); while it said nothing, the record's account
    /// while the record still names the seat it started on. nil: nobody's.
    static func numbersOwner(record: SignedInAccount?, trail: ProcessTrail) -> SignedInAccount? {
        FolderSignIn.answer(record: record, trail: trail).numbersBelongTo
    }

    /// The running claude is the account the folder is on now and the one `target` (the chat's account) names. A chat is
    /// incognito, so its conversation lives only in that process: it goes on only then. A chat begun on no account never
    /// goes on on one that appears.
    static func processOn(record: SignedInAccount?, trail: ProcessTrail, target: AccountKey?, targetEmail: String? = nil) -> Bool {
        guard let r = record, let target else { return false }
        let a = FolderSignIn.answer(record: r, trail: trail)
        switch a.verdict {
        case .verified, .seatNotKnown: break
        case .guessed: guard a.numbersBelongTo != nil else { return false }
        case .differs, .none: return false
        }
        return identity(target, email: targetEmail).match(r) != .different
    }

    /// Numbers that belong to `owner` are the account `target` names (the chat's own level).
    static func owns(_ target: AccountKey?, email: String?, _ owner: SignedInAccount) -> Bool {
        guard let target else { return false }
        return identity(target, email: email).match(owner) != .different
    }

    // MARK: the levels' keys

    /// The key a week is kept under: the profile and the seat, "<profile id>|<account>" while the seat isn't known (as
    /// older builds wrote it), "<profile id>|<account>|<organisation>" once it is (AccountKey.text). An older build reads
    /// a seat's key as a miss: it shows no numbers until its next usage ask.
    static func levelKey(_ profile: String, _ key: AccountKey) -> String { profile + "|" + key.text }

    /// A level key read back: its profile and its seat; nil for a key from before accounts (the profile id alone) or one
    /// that isn't a key.
    static func parseLevelKey(_ key: String) -> (profile: String, key: AccountKey)? {
        guard let bar = key.firstIndex(of: "|"), let k = AccountKey(text: String(key[key.index(after: bar)...])) else { return nil }
        return (String(key[..<bar]), k)
    }

    /// Where numbers that belong to `owner` are kept in a profile: the entry of its seat, else an entry of its account
    /// whose seat isn't known, upgraded in place to the seat the numbers' own source named (`upgrade`: that entry and the
    /// key it had; AccountKey.upgraded(with:seatOfTheNumbers:)), else the owner's own key (kept, not dropped: an account
    /// cl_quick hasn't noted yet, or a word that names no id). Never two keys: the numbers go to one seat.
    static func numbersKey(for owner: SignedInAccount, in list: [KnownAccount]) -> (key: AccountKey, upgrade: (index: Int, from: AccountKey)?)? {
        if let k = AccountKey(owner), let i = list.firstIndex(where: { $0.key == k }) { return (list[i].key, nil) }
        if let i = list.firstIndex(where: { $0.key.match(owner) == .seat }) { return (list[i].key, nil) }
        if let i = list.firstIndex(where: { $0.organization == nil && $0.key.match(owner) == .seatNotKnown }),
           let up = list[i].key.upgraded(with: owner, seatOfTheNumbers: true), up.seatKnown, !list.contains(where: { $0.key == up }) {
            return (up, (i, list[i].key))
        }
        return AccountKey(owner).map { ($0, nil) }
    }

    /// The numbers kept for `owner` before new ones are applied on them: its seat's, or those of the entry whose seat
    /// isn't known that the new ones upgrade (numbersKey).
    static func numbersBase<V>(for owner: SignedInAccount, profile: String, accounts: [KnownAccount], levels: [String: V]) -> V? {
        guard let r = numbersKey(for: owner, in: accounts) else { return nil }
        return levels[levelKey(profile, r.key)] ?? r.upgrade.flatMap { levels[levelKey(profile, $0.from)] }
    }

    /// New numbers that belong to `owner`, kept: under its seat (numbersKey). An entry whose seat wasn't known is upgraded
    /// in place to the seat the numbers' source named, and its old numbers move with it (the new ones are applied on them
    /// first: numbersBase), never copied onto both seats; nothing else changes. nil when `owner` names nobody.
    static func recording<V>(_ level: V, for owner: SignedInAccount, profile: String, accounts: [KnownAccount],
                             levels: [String: V]) -> (accounts: [KnownAccount], levels: [String: V])? {
        guard let r = numbersKey(for: owner, in: accounts) else { return nil }
        var list = accounts, kept = levels
        if let u = r.upgrade {
            list[u.index].uuid = r.key.account; list[u.index].organization = r.key.organization
            kept[levelKey(profile, u.from)] = nil
        }
        kept[levelKey(profile, r.key)] = level
        return (list, kept)
    }

    /// A key upgraded in place (an address placeholder given its id, a name placeholder its organisation's id): a week of
    /// the profile kept under a placeholder that the record upgrades to `to` (numbers kept for an account before it was
    /// noted) moves to `to`, unless `to` has one already (never two, never one dropped).
    static func upgradingLevels<V>(_ levels: [String: V], profile: String, to: AccountKey, record: SignedInAccount) -> [String: V] {
        var out = levels
        let target = levelKey(profile, to)
        for (key, v) in levels.sorted(by: { $0.key < $1.key }) {
            guard out[target] == nil, let p = parseLevelKey(key), p.profile == profile, p.key != to,
                  p.key.isPlaceholder || p.key.organization?.hasPrefix(AccountKey.namePrefix) == true,
                  p.key.upgraded(with: record) == to else { continue }
            out[target] = v; out[key] = nil
        }
        return out
    }

    /// The keys in the kit's form (AccountKey: lower case): a key written in another case moves to its normal one, unless
    /// that one is there already (then both stay). Keys from before accounts, and anything that isn't a key, stay as they
    /// are. A key an older build wrote ("<profile>|<uuid>") is already a key whose seat isn't known: it stays.
    static func normalizedKeys<V>(_ levels: [String: V]) -> [String: V] {
        var out = levels
        for (key, v) in levels.sorted(by: { $0.key < $1.key }) {
            guard let p = parseLevelKey(key) else { continue }
            let normal = levelKey(p.profile, p.key)
            guard normal != key, out[normal] == nil else { continue }
            out[normal] = v; out[key] = nil
        }
        return out
    }

    /// A levels.json from before accounts was keyed by profile id alone. Each such week goes to the seat `placed` names
    /// for that profile (the one signed in now, the one it was most likely reported on); one that can't be placed (no such
    /// profile, or none signed in yet) is kept as it is, to be placed by a later start. Keys already per account stay, and
    /// win over a week moved onto the same key.
    static func migrated<V>(_ old: [String: V], placed: (String) -> AccountKey?) -> [String: V] {
        var out: [String: V] = [:]
        for (key, v) in old {
            guard !key.contains("|") else { out[key] = v; continue }
            if let seat = placed(key) {
                let to = levelKey(key, seat)
                if old[to] == nil { out[to] = v }
            } else {
                out[key] = v
            }
        }
        return out
    }

    /// Every week of a profile: each seat's, and a legacy one under the bare profile id.
    static func removing<V>(profile id: String, from levels: [String: V]) -> [String: V] {
        levels.filter { $0.key != id && !$0.key.hasPrefix(id + "|") }
    }

    /// Forgets a standby account of a profile: it leaves the list and its week goes (levelKey). The account in use (the
    /// entry the record is, entryIndex, a placeholder or an entry whose seat isn't known included) can't be forgotten, nor
    /// one that isn't in the list: nil. Nothing else moves.
    static func forgetting<V>(_ key: AccountKey, of profile: String, accounts: [KnownAccount], levels: [String: V],
                              inUse record: SignedInAccount?) -> (accounts: [KnownAccount], levels: [String: V])? {
        guard accounts.contains(where: { $0.key == key }) else { return nil }
        if let r = record {
            if AccountKey(r) == key { return nil }
            if let i = entryIndex(for: r, in: accounts), accounts[i].key == key { return nil }
        }
        var kept = levels
        kept[levelKey(profile, key)] = nil
        return (accounts.filter { $0.key != key }, kept)
    }
}

/// The one-time backup of a stored file before this build first rewrites it: profiles.json and levels.json move to seat
/// keys (account id and organisation), so the file as it was before is kept beside it, once.
enum StoredKeys {
    /// The backup's name: the file's, then ".pre-26.11.4" (profiles.json.pre-26.11.4).
    static let backupExtension = "pre-26.11.4"

    static func backup(of file: URL) -> URL { file.appendingPathExtension(backupExtension) }

    /// Copies `file` to its backup unless a backup is there already (never overwritten: the first one is the file as an
    /// older build left it) or there is no file yet (nothing to keep). True when a backup is there afterwards.
    @discardableResult
    static func keepBackup(of file: URL, files: FileManager = .default) -> Bool {
        let b = backup(of: file)
        if files.fileExists(atPath: b.path) { return true }
        guard files.fileExists(atPath: file.path) else { return false }
        return (try? files.copyItem(at: file, to: b)) != nil       // copyItem never replaces a file already there
    }
}
