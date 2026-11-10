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

/// One Claude Code folder cl_quick chats on.
struct Profile: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var name: String
    /// As written (~ allowed).
    var folder: String
    /// Offered in the chat's profile picker.
    var inPicker = true

    init(id: String, name: String, folder: String, inPicker: Bool = true) {
        self.id = id; self.name = name; self.folder = folder; self.inPicker = inPicker
    }
    /// Tolerant: a field added later never makes older profiles.json files unreadable.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        folder = try c.decode(String.self, forKey: .folder)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ClaudeFolder.suggestedName(folder)
        inPicker = (try? c.decodeIfPresent(Bool.self, forKey: .inPicker)) ?? true
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

    /// What was read from a .claude.json, kept until the file changes: it can be several MB.
    private struct Read { var mtime: Date?; var email: String?; var plan: String? }
    private static var cache: [String: Read] = [:]
    private static let lock = NSLock()

    private static func read(_ path: String) -> Read {
        let file = json(path)
        let mtime = (try? FileManager.default.attributesOfItem(atPath: file))?[.modificationDate] as? Date
        lock.lock(); let hit = cache[file]; lock.unlock()
        if let hit, hit.mtime == mtime { return hit }
        var r = Read(mtime: mtime)
        if let d = FileManager.default.contents(atPath: file),
           let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
           let a = j["oauthAccount"] as? [String: Any] {
            r.email = a["emailAddress"] as? String
            if let p = a["planDisplayName"] as? String, !p.trimmingCharacters(in: .whitespaces).isEmpty {
                r.plan = p == p.lowercased() ? p.capitalized : p
            }
        }
        lock.lock(); cache[file] = r; lock.unlock()
        return r
    }

    /// The address Claude Code signed the folder in with; nil when it hasn't.
    static func email(_ path: String) -> String? { read(path).email }

    /// Claude's name for the plan ("Max"), when Claude Code recorded it.
    static func plan(_ path: String) -> String? { read(path).plan }

    /// A folder cl_quick can chat on: signed in to Claude Code, and not the home folder itself.
    static func usable(_ path: String) -> Bool {
        let p = (expand(path) as NSString).standardizingPath
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
    @Published private(set) var levels: [String: QuickChatLevel] = [:]

    private init() {
        profiles = Files.read([Profile].self, Files.profiles) ?? []
        levels = Files.read([String: QuickChatLevel].self, Files.levels) ?? [:]
    }

    var hasProfiles: Bool { !profiles.isEmpty }
    func profile(_ id: String?) -> Profile? { profiles.first { $0.id == id } }

    func save(_ list: [Profile]) {
        profiles = list
        Files.write(list, Files.profiles)
    }

    /// The first run: every folder found that is signed in, named after the folder.
    func adoptFound() {
        guard profiles.isEmpty else { return }
        var list: [Profile] = []
        for f in ClaudeFolder.found() where ClaudeFolder.usable(f) {
            list.append(Profile(id: Self.newID(f, taken: list.map(\.id)), name: ClaudeFolder.suggestedName(f), folder: f))
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

    func add(_ p: Profile) { save(profiles + [p]) }
    func update(_ p: Profile) { save(profiles.map { $0.id == p.id ? p : $0 }) }
    /// cl_quick forgets the profile; its folder and sessions stay.
    func remove(_ id: String) {
        save(profiles.filter { $0.id != id })
        levels[id] = nil
        Files.write(levels, Files.levels)
    }
    /// A folder already used by a profile.
    func uses(_ folder: String) -> Bool { profiles.contains { $0.path == expand(folder) } }

    /// What Claude Code said after an answer on this profile.
    func record(_ id: String, _ level: QuickChatLevel) {
        guard profile(id) != nil, levels[id] != level else { return }      // a profile removed meanwhile stays gone
        levels[id] = level
        Files.write(levels, Files.levels)
    }
}
