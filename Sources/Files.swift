// Files: where cl_quick keeps things, and Remove cl_quick data….
//
//   ~/Library/Application Support/cl_quick/   profiles.json, settings.json, levels.json, models.json, updates.json, work/<profile id>/
//
// Quick chats are incognito: Claude Code runs with --no-session-persistence, so a chat writes nothing. Chats saved by
// earlier versions are Claude Code sessions in the profile's folder under projects/<the work folder, each
// non-ASCII-alphanumeric UTF-16 unit a "-">/ (deleted after 30 days by default); they are only looked for and removed here.
//
// Outside it: the login item (Open at login), and any folder Sign in another account… made (a Claude Code folder, which
// Remove leaves). Remove moves any old chats and the folder above to the Trash and turns the login item off; your Claude
// Code folders and their other sessions stay.

import AppKit

enum Files {
    static var folder: URL {
        URL(fileURLWithPath: expand("~/Library/Application Support/cl_quick"))
    }
    static var profiles: URL { folder.appendingPathComponent("profiles.json") }
    static var settings: URL { folder.appendingPathComponent("settings.json") }
    static var levels: URL { folder.appendingPathComponent("levels.json") }
    /// When the update check last asked, and the newest release it saw (Updates.swift).
    static var updates: URL { folder.appendingPathComponent("updates.json") }
    /// Each profile's account's models, as Claude Code last listed them (ModelCatalog).
    static var models: URL { folder.appendingPathComponent("models.json") }
    static var work: URL { folder.appendingPathComponent("work") }

    static func read<T: Decodable>(_ type: T.Type, _ url: URL) -> T? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(type, from: d)
    }

    /// Set by the --render-… commands: a picture writes nothing.
    static var readOnly = false

    @discardableResult
    static func write<T: Encodable>(_ value: T, _ url: URL) -> Bool {
        guard !readOnly else { return false }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]; enc.dateEncodingStrategy = .iso8601
            try enc.encode(value).write(to: url, options: .atomic)
            return true
        } catch { return false }
    }

    /// The folder earlier versions' quick chats were kept in by Claude Code (this version writes none).
    static func chatsFolder(_ p: Profile) -> URL {
        URL(fileURLWithPath: p.path).appendingPathComponent("projects")
            .appendingPathComponent(QuickChatCommand.projectKey(p.workFolder))
    }

    /// One profile's old chats, saved by earlier versions: how many and how big.
    static func chats(_ p: Profile) -> (count: Int, bytes: Int64) {
        let dir = chatsFolder(p)
        var count = 0, bytes: Int64 = 0
        if let walk = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) {
            for case let f as URL in walk {
                guard let v = try? f.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), v.isRegularFile == true else { continue }
                bytes += Int64(v.fileSize ?? 0)
                if f.pathExtension == "jsonl", f.deletingLastPathComponent().standardizedFileURL == dir.standardizedFileURL { count += 1 }
            }
        }
        return (count, bytes)
    }

    static func ownBytes() -> Int64 {
        var bytes: Int64 = 0
        if let walk = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let f as URL in walk { bytes += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) }
        }
        return bytes
    }

    /// Moves every profile's old quick chats (if any) and cl_quick's own folder to the Trash; only a chats folder whose name is
    /// exactly cl_quick's own, directly in a profile's projects/, is taken. Returns what couldn't be moved.
    static func remove(_ list: [Profile]) -> [String] {
        let fm = FileManager.default
        var failed: [String] = []
        func trash(_ url: URL) {
            guard fm.fileExists(atPath: url.path) else { return }
            do { try fm.trashItem(at: url, resultingItemURL: nil) } catch { failed.append(tilde(url.path)) }
        }
        let prefix = QuickChatCommand.projectKey(work.path) + "-"
        for p in list {
            let dir = chatsFolder(p)
            let projects = URL(fileURLWithPath: p.path).appendingPathComponent("projects").standardizedFileURL
            guard dir.lastPathComponent.hasPrefix(prefix), dir.deletingLastPathComponent().standardizedFileURL == projects else { continue }
            trash(dir)
        }
        trash(folder)
        return failed
    }

    static func size(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }

    /// Shows the folder in Finder, or the nearest one above it that exists.
    static func reveal(_ url: URL) {
        var u = url
        while !FileManager.default.fileExists(atPath: u.path), u.path != "/" { u = u.deletingLastPathComponent() }
        NSWorkspace.shared.open(u)
    }
}

extension UpdateChecker {
    /// The app's one update check: this version (the bundle's YY.M.R), Settings ▸ General ▸ Updates, updates.json.
    static let shared = UpdateChecker(
        current: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0",
        enabled: { QuickChat.shared.settings.checkForUpdates },
        file: Files.updates)
}
