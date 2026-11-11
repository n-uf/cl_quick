// Updates: tells the operator when a newer cl_quick has been released. Nothing is downloaded or installed by the app.
//
// About once a day (and a little after launch, never at the same instant) it asks GitHub for the latest release
// (GET https://api.github.com/repos/n-uf/cl_quick/releases/latest), anonymously: no token, no cookies, only a generic
// User-Agent, "cl_quick". The release's tag (vYY.M.R) is compared with the app's own version (YY.M.R), each part as a
// number. A newer one shows "Update available: 26.11.3" in the menu bar menu; the item opens the release's page in the
// browser. No releases yet (404) shows nothing. 403 or 429 (GitHub's rate limit) is tried again the next day.
// Settings ▸ General ▸ Updates turns it off; off makes no request at all.
//
// It keeps two things in updates.json beside settings.json: when it last asked and the newest release seen (version and
// page). Nothing about chats. Foundation only, so Checks/run.sh checks all of it (a stand-in fetcher, no network).

import Foundation

/// The pure part: which tags are versions, and which is newer.
enum UpdateVersion {
    /// "v26.11.3" or "26.11.3" as [26, 11, 3]; anything else (a pre-release suffix, two parts, letters) is nil.
    static func parse(_ s: String) -> [Int]? {
        var t = Substring(s.trimmingCharacters(in: .whitespacesAndNewlines))
        if t.first == "v" || t.first == "V" { t = t.dropFirst() }
        let parts = t.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var out: [Int] = []
        for p in parts {
            guard !p.isEmpty, p.count <= 6, p.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(p) else { return nil }
            out.append(n)
        }
        return out
    }

    /// The tag is a well-formed version and greater than the current one, part by part; equal is not newer, and a
    /// malformed tag (or a malformed current version) is never newer.
    static func isNewer(_ tag: String, than current: String) -> Bool {
        guard let a = parse(tag), let b = parse(current) else { return false }
        return a.lexicographicallyPrecedes(b) == false && a != b
    }

    /// The tag without its "v": "26.11.3".
    static func shown(_ tag: String) -> String? { parse(tag).map { $0.map(String.init).joined(separator: ".") } }

    /// The page to open: the release's own on github.com over https, else the project's releases page.
    static func page(_ html: String?) -> URL {
        if let html, let u = URL(string: html), u.scheme == "https", u.host == "github.com" { return u }
        return URL(string: "https://github.com/n-uf/cl_quick/releases/latest")!
    }
}

/// What asking GitHub came to.
enum UpdateFetch: Equatable {
    /// The latest release: its tag and page.
    case release(tag: String, page: String?)
    /// 404: no release yet.
    case none
    /// 403 or 429: GitHub's rate limit; the next day.
    case limited
    /// Any other answer, or one that couldn't be read.
    case other
    /// No answer (offline, timed out): again in an hour.
    case offline
}

/// What is kept: when it last asked and the newest release it saw.
struct UpdateState: Codable, Equatable {
    var lastCheck: Date? = nil
    var latest: String? = nil        // "26.11.3"
    var page: String? = nil
}

final class UpdateChecker {
    typealias Fetcher = (@escaping (UpdateFetch) -> Void) -> Void

    static let interval: TimeInterval = 24 * 3600
    static let retryAfterOffline: TimeInterval = 3600

    private let current: String
    private let enabled: () -> Bool
    private let fetch: Fetcher
    private let now: () -> Date
    private let file: URL?
    private var timer: Timer?
    private var asking = false
    private(set) var state: UpdateState
    /// Called (on the main thread) when what is known changed.
    var changed: () -> Void = {}

    /// `file` nil: nothing is kept (the checks).
    init(current: String, enabled: @escaping () -> Bool, fetch: @escaping Fetcher = UpdateChecker.github,
         now: @escaping () -> Date = Date.init, file: URL?) {
        self.current = current; self.enabled = enabled; self.fetch = fetch; self.now = now; self.file = file
        if let file, let d = try? Data(contentsOf: file) {
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            state = (try? dec.decode(UpdateState.self, from: d)) ?? UpdateState()
        } else { state = UpdateState() }
    }

    /// The newer release to show, or nil: none known, not newer than this one (after an update, the notice goes by
    /// itself), or the check is off.
    var available: (version: String, page: URL)? {
        guard enabled(), let v = state.latest, UpdateVersion.isNewer(v, than: current) else { return nil }
        return (v, UpdateVersion.page(state.page))
    }

    /// Asks GitHub if it is on and a day has passed since it last asked; otherwise does nothing at all.
    func checkIfDue() {
        guard enabled(), !asking else { return }
        let t = now()
        if let last = state.lastCheck, t.timeIntervalSince(last) < Self.interval, t >= last { return }
        asking = true
        // recorded before the answer: a restart while it is under way doesn't ask again
        state.lastCheck = t
        save()
        fetch { [weak self] result in self?.finish(result) }
    }

    private func finish(_ r: UpdateFetch) {
        asking = false
        let before = state
        switch r {
        case .release(let tag, let page):
            if let v = UpdateVersion.shown(tag) { state.latest = v; state.page = page } else { state.latest = nil; state.page = nil }
        case .none:
            state.latest = nil; state.page = nil
        case .limited, .other:
            break                       // what was known stays; asked again tomorrow
        case .offline:
            state.lastCheck = now().addingTimeInterval(Self.retryAfterOffline - Self.interval)
        }
        save()
        if state != before { changed() }
    }

    /// The first look a little after launch (45 to 90 s, so it isn't at the launch instant), then once an hour whether
    /// a day has passed (that costs nothing: no request until it has).
    func start(firstAfter delay: TimeInterval = Double.random(in: 45...90)) {
        timer?.invalidate()
        let t = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in self?.checkIfDue() }
        t.tolerance = 300
        RunLoop.main.add(t, forMode: .common)
        timer = t
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.checkIfDue() }
    }

    private func save() {
        guard let file else { return }
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]; enc.dateEncodingStrategy = .iso8601
        guard let d = try? enc.encode(state) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? d.write(to: file, options: .atomic)
    }

    // MARK: GitHub

    /// The one request: anonymous, a generic User-Agent, no cookies, nothing cached, answered on the main thread.
    static func github(_ done: @escaping (UpdateFetch) -> Void) {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpCookieStorage = nil
        cfg.httpShouldSetCookies = false
        cfg.urlCache = nil
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 30
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/n-uf/cl_quick/releases/latest")!)
        req.setValue("cl_quick", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let session = URLSession(configuration: cfg)
        session.dataTask(with: req) { data, resp, error in
            let result = answer(data: data, status: (resp as? HTTPURLResponse)?.statusCode, failed: error != nil)
            session.finishTasksAndInvalidate()
            DispatchQueue.main.async { done(result) }
        }.resume()
    }

    /// GitHub's answer as a result (a pure function, checked). Drafts and pre-releases are not offered.
    static func answer(data: Data?, status: Int?, failed: Bool) -> UpdateFetch {
        guard !failed, let status else { return .offline }
        switch status {
        case 200:
            guard let data, let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let tag = o["tag_name"] as? String else { return .other }
            if (o["draft"] as? Bool) == true || (o["prerelease"] as? Bool) == true { return .none }
            return .release(tag: tag, page: o["html_url"] as? String)
        case 404: return .none
        case 403, 429: return .limited
        default: return .other
        }
    }
}
