// ClaudeAuth · the sign-in: Claude Code's own `claude auth login` for a profile's ONE folder, opened in a Terminal window,
// followed until it ends one way or another, and its window closed after it. The person signs in in the browser; nothing
// here sees a password or a token.
//
// Built on ClaudeAuth's own parts: the hardened script (SignInScript, Authenticator.startSignIn), the folder's cleaned
// environment (AuthFolder), the record's watch (SignInChangeWatch, RecordStamp), the one answer (FolderSignIn.answer) and the
// matching rule (SignedInAccount.match), the guard (AuthTools.mayLaunch), and Runs' process table (ProcessTable). The app's
// own verified word is a parameter (`Confirm`): cl_audit's Keychain read and Anthropic's reply, cl_quick's short `claude` and
// its `initialize` account. Until that word comes, the folder's record is only a guess.
//
// The rules:
// - One profile, one folder: nothing here makes, moves or redirects a Claude Code folder, and nothing is written into one.
//   A folder the guard refuses (isReady, cl_audit's FolderGuard) starts nothing.
// - One sign-in window per app: starting a sign-in ends the app's earlier one, window and all (also one an earlier run of
//   the app left: its script's pid is in the app's own work folder).
// - Two guards against two sign-ins on one folder: any `claude auth login` running on the folder, whoever started it (the
//   process table; one whose folder can't be told counts too, see `isLogin`), and a lock every app takes (`flock` on
//   ~/Library/Caches/n-uf/signin-<8 hex of the folder's real path's SHA-256>.lock), which closes the race between two apps
//   starting at once.
// - The window closes on a sign-in, a wrong account, a stop and a timeout. One that was declined or failed stays open to be
//   read, until Return, the next start or a stop.
// - The window: a Terminal settings file (`.terminal`: the command, run inside the login shell with `exec`, and "close if the
//   shell exited cleanly"), opened like any document, which needs no permission to control Terminal. `.scripted` (Terminal's
//   AppleScript, which asks for that permission) is there for a Mac where the settings file doesn't work.
//
// No app's screens, words or global state: the folder, the account wanted, the tools, the verified word, the app's work
// folder and the window's title are parameters. One queue for every sign-in of the process; the callbacks come on the main
// queue.

import Foundation
import ProfileCore
import Runs

public final class ClaudeSignIn {
    public enum State: Equatable {
        /// The guards passed; the script and the window are being made.
        case opening
        /// Terminal has the sign-in: the person finishes it in the browser.
        case waitingForBrowser
    }

    public enum Failure: Equatable {
        /// The folder isn't there as a plain folder, or the app's guard said no: nothing started, nothing made.
        case folderNotReady
        /// Another sign-in (this app's or another's) holds the folder's sign-in lock.
        case locked
        /// A `claude auth login` already runs on the folder, whoever started it.
        case alreadySigningIn
        /// The running processes couldn't be read (or one that may be Claude Code couldn't be): nothing started.
        case processesUnreadable
        /// The script or the window couldn't be written or opened.
        case notOpened
        /// Claude Code's login ended without a sign-in (its exit status).
        case loginFailed(status: Int32)
        /// The login ended well, but the folder names nobody.
        case noAccount
        /// The window was closed before the login ended.
        case windowClosed
    }

    public enum Outcome: Equatable {
        /// The folder is signed in to the account wanted (or to someone, when none was): verified when the app's word said so
        /// (`account.source`), else guessed from the record.
        case signedIn(SignedInAccount)
        /// Another account signed in (the browser was signed in as someone else), by SignedInAccount.match.
        case wrongAccount(signedIn: SignedInAccount, wanted: SignedInAccount)
        /// The person declined in the browser (Claude Code said so in the window).
        case declined
        case failed(Failure)
        /// `stop()`, or another sign-in of the app started.
        case stopped
        /// Nothing came within the timeout.
        case timedOut
    }

    /// The app's verified word on the folder's account now, or nil when it can't tell (then the record is taken, as a
    /// guess). Blocks; called off the main thread. cl_audit: its Keychain read and Anthropic's reply (`server`); cl_quick: a
    /// short `claude` on the folder and its `initialize` account (`process`).
    public typealias Confirm = (AuthFolder) -> SignedInAccount?

    /// How the window is opened.
    public enum Window: Equatable {
        /// A Terminal settings file, opened like a document (no permission to control Terminal asked).
        case settingsFile
        /// Terminal's AppleScript: asks for permission to control Terminal the first time.
        case scripted
    }

    /// Where every app takes the folder's sign-in lock.
    public static var sharedLocks: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches/n-uf", isDirectory: true)
    }

    public let folder: AuthFolder
    public let wanted: SignedInAccount?
    public let timeout: TimeInterval

    private let auth: Authenticator
    private let claude: String
    private let confirm: Confirm
    private let window: Window
    private let title: String
    private let shown: String?
    private let locks: URL
    private let poll: TimeInterval
    private let work: URL

    // the sign-in's files, all in the app's own work folder (owner only). The script is named after the folder's lock key:
    // its shell's command line then says which folder its `claude auth login` signs in, to any app (`isLogin`).
    var scriptURL: URL { work.appendingPathComponent("sign-in-\(Self.lockKey(folder)).command") }
    var settingsURL: URL { work.appendingPathComponent("sign-in.terminal") }
    var pidURL: URL { work.appendingPathComponent("sign-in.pid") }
    var statusURL: URL { work.appendingPathComponent("sign-in.status") }
    var declinedURL: URL { work.appendingPathComponent("sign-in.declined") }
    var lockURL: URL { locks.appendingPathComponent("signin-\(Self.lockKey(folder)).lock") }

    /// `folder`: the profile's one folder (made by the app beforehand when it is new). `wanted`: the account it should end on
    /// (by id, or by address and organisation), nil for a brand-new folder. `claude`: Claude Code's program. `work`: the app's
    /// own folder for the sign-in's files (never the Claude Code folder). `title`: the window's name. `shown`: the folder as
    /// the script's first line names it. `locks` and `poll` (how often the folder is looked at) are parameters for the checks.
    public init(folder: AuthFolder, wanted: SignedInAccount?, timeout: TimeInterval = 600, tools: AuthTools, claude: String,
                confirm: @escaping Confirm, work: URL, window: Window = .settingsFile, title: String = "Claude Code sign-in",
                shown: String? = nil, locks: URL = ClaudeSignIn.sharedLocks, poll: TimeInterval = 2) {
        self.folder = folder; self.wanted = wanted; self.timeout = timeout
        self.claude = claude; self.confirm = confirm; self.work = work; self.window = window; self.title = title
        self.shown = shown; self.locks = locks; self.poll = poll
        auth = Authenticator(folder, tools: tools)
    }

    // MARK: the one sign-in of the app

    /// Every sign-in's work, one at a time.
    private static let queue = DispatchQueue(label: "n-uf.claude-auth.sign-in")
    /// The app's sign-in now (or the last one, while its window stays open to be read).
    private static var current: ClaudeSignIn?

    private enum Phase { case idle, running, ended }
    private var phase = Phase.idle
    private var onState: (State) -> Void = { _ in }
    private var onEnd: (Outcome) -> Void = { _ in }
    private var timer: DispatchSourceTimer?
    private var lockFD: Int32 = -1
    private var started = Date()
    private var watch = SignInChangeWatch()
    private var startAccount: SignedInAccount?
    private var undecided = 0
    private var windowID: String?

    /// Starts it: the app's earlier sign-in ends, the guards are asked, the window opens, and the folder is looked at every
    /// `poll` seconds. `onState` and `onEnd` come on the main queue; `onEnd` once.
    public func start(onState: @escaping (State) -> Void = { _ in }, onEnd: @escaping (Outcome) -> Void) {
        Self.queue.async { self.begin(onState, onEnd) }
    }

    /// Ends it: the `claude auth login` in its window and the window. After a declined or failed sign-in, closes the window
    /// left open to be read. Nothing when it never started.
    public func stop() { Self.queue.async { self.end(.stopped) } }

    private func end(_ outcome: Outcome) {
        switch phase {
        case .idle: return
        case .running: finish(outcome)
        case .ended: endScript(shell: true)
        }
    }

    private func begin(_ onState: @escaping (State) -> Void, _ onEnd: @escaping (Outcome) -> Void) {
        guard phase == .idle else { return }
        phase = .running
        self.onState = onState; self.onEnd = onEnd
        // one window per app: the earlier sign-in ends, and whatever an earlier run of the app left in its work folder
        if let earlier = Self.current, earlier !== self { earlier.end(.stopped) }
        Self.current = self
        endScript(shell: true)
        guard auth.tools.mayLaunch("login", folder) else { return finish(.failed(.folderNotReady)) }
        guard takeLock() else { return finish(.failed(.locked)) }
        switch loginRuns() {
        case nil: return finish(.failed(.processesUnreadable))
        case true?: return finish(.failed(.alreadySigningIn))
        case false?: break
        }
        emit(.opening)
        guard makeWork() else { return finish(.failed(.notOpened)) }
        for u in [statusURL, declinedURL, pidURL, settingsURL] { try? FileManager.default.removeItem(at: u) }
        started = Date()
        _ = watch.look(stamp: auth.recordStamp()) { auth.record() }
        startAccount = watch.seen
        var tools = auth.tools
        tools.openTerminal = { [self] in openWindow($0) }
        let watched = SignInScript.Watch(pid: pidURL, status: statusURL, declined: declinedURL)
        switch Authenticator(folder, tools: tools).startSignIn(claude: claude, email: wanted?.email, script: scriptURL,
                                                               removesItself: true, shown: shown, watch: watched) {
        case .done: break
        case .folderNotReady: return finish(.failed(.folderNotReady))
        case .otherAccount, .failed: return finish(.failed(.notOpened))
        }
        emit(.waitingForBrowser)
        let t = DispatchSource.makeTimerSource(queue: Self.queue)
        t.schedule(deadline: .now() + poll, repeating: poll)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    // MARK: following it

    private func tick() {
        guard phase == .running else { return }
        if Date().timeIntervalSince(started) >= timeout { return finish(.timedOut) }
        if FileManager.default.fileExists(atPath: declinedURL.path) { return finish(.declined) }
        let status = loginStatus()
        if let s = status, s != 0 { return finish(.failed(.loginFailed(status: s))) }
        let changed = watch.look(stamp: auth.recordStamp()) { auth.record() } || (startAccount == nil && watch.seen != nil)
        if status == 0 || changed || undecided > 0 { return decide(loginEnded: status == 0) }
        // the window closed while the login ran (Terminal hung its shell up: it ended cleanly, before writing a status)
        if let pid = scriptPid(), !ProcessTable.runs(pid), loginStatus() == nil, !FileManager.default.fileExists(atPath: declinedURL.path) {
            finish(.failed(.windowClosed))
        }
    }

    /// The folder's account now, by the app's verified word over the record, against the account wanted.
    private func decide(loginEnded: Bool) {
        let record = auth.record()
        let answer = FolderSignIn.answer(record: record, verified: confirm(folder))
        // the verified word and the record name two accounts: Claude Code is between its two writes; a few looks more
        if answer.verdict == .differs && undecided < 3 { undecided += 1; return }
        guard let account = answer.account else {
            if loginEnded { finish(.failed(.noAccount)) } else { undecided = 0 }
            return
        }
        undecided = 0
        guard let wanted else { return finish(.signedIn(account)) }
        finish(Self.same(account, wanted, record: record) ? .signedIn(account) : .wrongAccount(signedIn: account, wanted: wanted))
    }

    /// The account signed in is the one wanted, by SignedInAccount.match. An account wanted with no organisation named (an
    /// app that keeps accounts by their id or address only) is compared without the organisation: none named there isn't
    /// "no organisation". An account wanted by its id alone can't be compared with a verified word that names no id (a
    /// running claude's): the record's id is taken then, when the record is that same address.
    static func same(_ account: SignedInAccount, _ wanted: SignedInAccount, record: SignedInAccount?) -> Bool {
        let anyOrganisation = wanted.organizationID == nil && wanted.organizationName == nil
        func asWanted(_ a: SignedInAccount) -> SignedInAccount {
            var a = a
            if anyOrganisation { a.organizationID = nil; a.organizationName = nil }
            return a
        }
        if asWanted(account).match(wanted) != .different { return true }
        guard wanted.email == nil, wanted.accountID != nil, account.accountID == nil,
              let r = record, r.match(account) != .different else { return false }
        return asWanted(r).match(wanted) != .different
    }

    private func finish(_ outcome: Outcome) {
        guard phase == .running else { return }
        phase = .ended
        timer?.cancel(); timer = nil
        switch outcome {
        case .signedIn, .wrongAccount, .stopped, .timedOut: endScript(shell: true)
        // left open to be read: only the login ends (one still waiting after a decline), the script then holds its window
        case .declined, .failed: endScript(shell: false)
        }
        releaseLock()
        for u in [statusURL, declinedURL, settingsURL] { try? FileManager.default.removeItem(at: u) }
        let done = onEnd
        DispatchQueue.main.async { done(outcome) }
    }

    private func emit(_ s: State) {
        let f = onState
        DispatchQueue.main.async { f(s) }
    }

    /// The login's exit status, once its script wrote it.
    private func loginStatus() -> Int32? {
        (try? String(contentsOf: statusURL, encoding: .utf8)).flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    // MARK: the guards

    /// The lock's name: the first 8 hex characters of the SHA-256 of the folder's real path (links resolved).
    public static func lockKey(_ folder: AuthFolder) -> String {
        AuthFolder.sha8(URL(fileURLWithPath: folder.path).resolvingSymlinksInPath().path)
    }

    private func takeLock() -> Bool {
        guard (try? FileManager.default.createDirectory(at: locks, withIntermediateDirectories: true)) != nil else { return false }
        let fd = open(lockURL.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return false }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); return false }
        lockFD = fd
        return true
    }

    private func releaseLock() {
        guard lockFD >= 0 else { return }
        flock(lockFD, LOCK_UN); close(lockFD); lockFD = -1
    }

    /// A `claude auth login` running on this folder, whoever started it, or one whose folder can't be told (refused rather
    /// than guessed); nil when the processes can't be read.
    func loginRuns() -> Bool? {
        guard let all = ProcessTable.settledTable(), !all.contains(where: \.hidden) else { return nil }
        let me = getuid()
        return all.contains { $0.uid == me && isLogin($0, in: all) != false }
    }

    /// Whether a process is Claude Code's `claude auth login` on this folder: true, false (not a login, or another folder's),
    /// or nil (a login whose folder can't be told). The folder is its CLAUDE_CONFIG_DIR (the default folder when it isn't
    /// set) where the kernel gives the environment; macOS 27 gives none for another process, and then a login started by a
    /// ClaudeSignIn (this app's or another's) is told by its script's name (`sign-in-<lock key>.command`) among its parents.
    func isLogin(_ e: ProcessTable.Entry, in table: [ProcessTable.Entry]) -> Bool? {
        guard let l = e.launch, ProcessTable.isClaudeCode(l),
              zip(l.args, l.args.dropFirst()).contains(where: { $0 == "auth" && $1 == "login" }) else { return false }
        if l.environmentRead {
            let on = l.configDir ?? (folder.home + "/.claude")
            return AuthFolder.canonical(on, home: folder.home) == AuthFolder.canonical(folder.path, home: folder.home)
        }
        var parent = e.ppid, hops = 0
        while let p = parent, p > 1, hops < 4, let up = table.first(where: { $0.pid == p }) {
            for a in up.launch?.args ?? [] {
                let name = (a as NSString).lastPathComponent
                guard name.hasPrefix("sign-in-"), name.hasSuffix(".command"), name.count == "sign-in-".count + 8 + ".command".count else { continue }
                return name == scriptURL.lastPathComponent
            }
            parent = up.ppid; hops += 1
        }
        return nil
    }

    /// A shell running one of this app's sign-in scripts (any folder's).
    private func isOwnScript(_ l: ProcessTable.Launch) -> Bool {
        l.args.contains { $0.hasPrefix(work.path + "/sign-in-") && $0.hasSuffix(".command") }
    }

    // MARK: the window

    private func makeWork() -> Bool {
        guard (try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])) != nil else { return false }
        return true
    }

    /// What the window runs: the script, in place of the login shell Terminal starts (so its clean end is the shell's).
    var command: String { "exec " + SignInScript.q(scriptURL.path) }

    /// The Terminal settings file: the command run inside the login shell, and the window closed when the shell exits cleanly
    /// (Terminal's `shellExitAction` 1, "Close if the shell exited cleanly"; `RunCommandAsShell` false is "Run inside shell").
    func settings() -> Data? {
        let plist: [String: Any] = ["type": "Window Settings", "name": title, "ProfileCurrentVersion": 2.09,
                                    "CommandString": command, "RunCommandAsShell": false, "shellExitAction": 1]
        return try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    /// The AppleScript of the `.scripted` window: it opens the command in a new window and says that window's id.
    var openScript: String {
        let c = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "tell application \"Terminal\"\nset t to do script \"\(c)\"\nreturn id of (first window whose tabs contains t)\nend tell"
    }

    static func closeScript(_ id: String) -> String {
        "tell application \"Terminal\" to close (every window whose id is \(Int(id) ?? -1))"
    }

    private func openWindow(_ script: URL) -> Bool {
        switch window {
        case .settingsFile:
            guard let data = settings(), SignInScript.write(data, to: settingsURL) else { return false }
            return auth.tools.openTerminal(settingsURL)
        case .scripted:
            guard let r = Runner.run(Program("/usr/bin/osascript", ["-e", openScript], timeout: 30, keepOutput: true)), r.ok else { return false }
            windowID = String(decoding: r.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return true
        }
    }

    // MARK: ending it

    /// The script's shell, from the pid it wrote: only while that pid still runs this script.
    private func scriptPid() -> pid_t? {
        guard let s = try? String(contentsOf: pidURL, encoding: .utf8), let pid = pid_t(s.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid > 0 else { return nil }
        return pid
    }

    /// Ends the login running in the script's window (and what it started), and the script itself when `shell`: asked first
    /// (SIGTERM; the script ends cleanly and its window closes), killed after 3 seconds (never the script's shell, whose
    /// unclean end would leave its window open). Only processes of this app's own script, found by the pid it wrote and
    /// checked by its command line; nothing else is signalled.
    private func endScript(shell: Bool) {
        guard let pid = scriptPid() else { return }
        guard let l = ProcessTable.launch(of: pid), isOwnScript(l), ProcessTable.runs(pid) else {
            try? FileManager.default.removeItem(at: pidURL)
            closeWindow()
            return
        }
        let under = Self.descendants(of: pid, in: ProcessTable.table() ?? [])
        if shell { kill(pid, SIGTERM) }
        for p in under { kill(p, SIGTERM) }
        let gone = { under.allSatisfy { !ProcessTable.runs($0) } && (!shell || !ProcessTable.runs(pid)) }
        let until = Date().addingTimeInterval(3)
        while !gone() && Date() < until { usleep(20_000) }
        if !gone() {
            for p in under where ProcessTable.runs(p) { kill(p, SIGKILL) }
            let more = Date().addingTimeInterval(1)
            while !gone() && Date() < more { usleep(20_000) }
        }
        if shell, !ProcessTable.runs(pid) {
            try? FileManager.default.removeItem(at: pidURL)
            closeWindow()
        }
    }

    /// The `.scripted` window, once its shell has ended (a settings-file window closes by itself).
    private func closeWindow() {
        guard window == .scripted, let id = windowID else { return }
        windowID = nil
        _ = Runner.run(Program("/usr/bin/osascript", ["-e", Self.closeScript(id)], timeout: 30))
    }

    /// Every process under `pid` in the table, by their parents.
    static func descendants(of pid: pid_t, in table: [ProcessTable.Entry]) -> [pid_t] {
        var out: [pid_t] = [], next = [pid]
        while let p = next.popLast() {
            for e in table where e.ppid == p && e.pid != p && !out.contains(e.pid) { out.append(e.pid); next.append(e.pid) }
        }
        return out
    }
}
