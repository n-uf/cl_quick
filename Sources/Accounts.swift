// Accounts: the bookkeeping of a profile's accounts that needs nothing but Foundation, so Checks/run.sh can check it:
// the accounts remembered per profile, and the keys the weeks are kept under.

import Foundation

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

    /// A uuid made from the address, for a file without an accountUuid.
    var isPlaceholder: Bool { uuid.hasPrefix("email:") }
}

/// What was read from a folder's .claude.json.
struct FolderRead {
    var mtime: Date?
    var email: String?
    var uuid: String?
    var plan: String?
}

/// The .claude.json files, read for the account in them. A file can be several MB and changes often (every Claude Code
/// session writes it), so the value read is kept per file; everything on the main thread reads the kept value, and the
/// file is read again on one serial utility queue. Every reload is queued behind the reads before it, so its `done`
/// always sees the file as it was when the reload was asked for, even if another read of it was under way.
enum FolderFiles {
    private static var cache: [String: FolderRead] = [:]
    private static let lock = NSLock()
    private static let queue = DispatchQueue(label: "cl_quick.folder-reads", qos: .utility)

    /// The value kept for the file; read from it only when it was never looked at.
    static func kept(_ file: String) -> FolderRead {
        lock.lock(); let hit = cache[file]; lock.unlock()
        return hit ?? fresh(file)
    }

    /// Reads the files again, off the main thread (parsing only those whose modification time moved); `done` comes on
    /// the main thread with whether an account changed since the value kept before these reads.
    static func reload(_ files: [String], done: @escaping (Bool) -> Void) {
        queue.async {
            var changed = false
            for f in files {
                lock.lock(); let before = cache[f]; lock.unlock()
                let r = fresh(f)
                if r.email != before?.email || r.uuid != before?.uuid { changed = true }
            }
            DispatchQueue.main.async { done(changed) }
        }
    }

    /// The file as it is now: parsed again only if its modification time moved.
    static func fresh(_ file: String) -> FolderRead {
        let mtime = (try? FileManager.default.attributesOfItem(atPath: file))?[.modificationDate] as? Date
        lock.lock(); let hit = cache[file]; lock.unlock()
        if let hit, hit.mtime == mtime { return hit }
        var r = FolderRead(mtime: mtime)
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
}

/// The accounts a chat's `claude` and its session started on. What the process reports (a week, a full limit) belongs
/// to that account, whatever the chat's target says by then: the folder may have changed account while an answer was on
/// its way. A session belongs to its account too: it is gone on only on the account it began on.
struct AccountTrail {
    private(set) var process: String?
    private(set) var session: String?

    mutating func processStarted(on uuid: String?) { process = uuid }
    mutating func processEnded() { process = nil }
    /// The running `claude` began its session: on the account it started on.
    mutating func sessionStarted() { session = process }
    mutating func sessionCleared() { session = nil }

    /// The account a report from the running `claude` is recorded on.
    var reportAccount: String? { process }
    /// A session goes on only on the account it began on (no session yet: nothing to carry across).
    func canResume(on uuid: String?) -> Bool { session == nil || session == uuid }
}

enum AccountBook {
    /// The key a week is kept under: the profile and the account, "<profile id>|<account uuid>".
    static func levelKey(_ profile: String, _ account: String) -> String { profile + "|" + account }

    /// A levels.json from before accounts was keyed by profile id alone. Each such week goes to the account `placed`
    /// names for that profile (the one signed in now, the one it was most likely reported on); one that can't be placed
    /// (no such profile, or none signed in yet) is kept as it is, to be placed by a later start. Keys already per
    /// account stay, and win over a week moved onto the same key.
    static func migrated<V>(_ old: [String: V], placed: (String) -> String?) -> [String: V] {
        var out: [String: V] = [:]
        for (key, v) in old {
            guard !key.contains("|") else { out[key] = v; continue }
            if let uuid = placed(key) {
                let to = levelKey(key, uuid)
                if old[to] == nil { out[to] = v }
            } else {
                out[key] = v
            }
        }
        return out
    }

    /// Every week of a profile: each account's, and a legacy one under the bare profile id.
    static func removing<V>(profile id: String, from levels: [String: V]) -> [String: V] {
        levels.filter { $0.key != id && !$0.key.hasPrefix(id + "|") }
    }

    /// Forgets a standby account of a profile: it leaves the list and its week goes (key "<profile>|<uuid>"). The account
    /// in use can't be forgotten, nor one that isn't in the list: nil. Nothing else moves.
    static func forgetting<V>(_ uuid: String, of profile: String, accounts: [KnownAccount], levels: [String: V],
                              inUse: String?) -> (accounts: [KnownAccount], levels: [String: V])? {
        guard uuid != inUse, accounts.contains(where: { $0.uuid == uuid }) else { return nil }
        var kept = levels
        kept[levelKey(profile, uuid)] = nil
        return (accounts.filter { $0.uuid != uuid }, kept)
    }

    /// Notes the account signed in now in a profile's list. It is found by its uuid; the address finds it only when the
    /// stored uuid is a placeholder made from that address (a file that had no accountUuid, and now has one), so two
    /// accounts that share an address (two organizations) stay two. The time is kept to the hour. Returns whether the
    /// list changed, and the uuid it replaced when a placeholder became a real one.
    @discardableResult
    static func note(_ list: inout [KnownAccount], uuid: String, email: String, now: Date = Date()) -> (changed: Bool, replaced: String?) {
        let k = list.firstIndex { $0.uuid == uuid }
            ?? list.firstIndex { $0.isPlaceholder && $0.email.lowercased() == email.lowercased() }
        guard let k else {
            list.append(KnownAccount(uuid: uuid, email: email, lastSeen: now))
            return (true, nil)
        }
        let old = list[k]
        guard old.uuid != uuid || old.email != email || now.timeIntervalSince(old.lastSeen) > 3600 else { return (false, nil) }
        list[k] = KnownAccount(uuid: uuid, email: email, lastSeen: now)
        return (true, old.uuid != uuid ? old.uuid : nil)
    }
}
