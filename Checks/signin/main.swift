// The sign-in's checks (Checks/signin.sh): ClaudeAuth's ClaudeSignIn as cl_quick builds it, and cl_quick's switch on top
// of it. No real Terminal: a stand-in opens the window's settings file and runs its command with /bin/sh, as Terminal's
// login shell would, with an input that stays open (a window nobody types in). No real `claude`: Checks/signin/bin/claude
// is a stand-in `claude auth login` (and the quick chat's stand-in for `initialize`). Folders, work folders and locks are
// under build/; sample addresses (example.com) only; nothing is read from or written to this Mac's own folders, and only
// processes this run started are signalled, by their pids.

import AppKit
import ClaudeAuth

Files.readOnly = true
_ = NSApplication.shared

var failed = 0, passed = 0
func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    if ok { passed += 1 } else { failed += 1; print("FAIL \(name) \(detail())") }
}
@discardableResult
func spin(until done: () -> Bool, max: TimeInterval = 15) -> Bool {
    let end = Date().addingTimeInterval(max)
    while !done(), Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
    return done()
}
func spin(_ s: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }

let env = ProcessInfo.processInfo.environment
let base = URL(fileURLWithPath: env["QC_SIGNIN_WORK"] ?? NSTemporaryDirectory() + "qc-signin-checks")
let claude = env["QC_SIGNIN_CLAUDE"] ?? ""
let fm = FileManager.default
try? fm.removeItem(at: base)
try? fm.createDirectory(at: base, withIntermediateDirectories: true)
let home = base.appendingPathComponent("home")            // the folders' home: never this Mac's own
let zdot = base.appendingPathComponent("zdot")            // the login shell's own settings: none
let locks = base.appendingPathComponent("locks")
for d in [home, zdot] { try? fm.createDirectory(at: d, withIntermediateDirectories: true) }
func uuid(_ n: Int) -> String { "00000000-0000-4000-8000-" + String(format: "%012d", n) }
func pidAlive(_ pid: pid_t) -> Bool { pid > 0 && kill(pid, 0) == 0 }

// ── the stand-in Terminal ──────────────────────────────────────────────────────────────────────────
/// Opens a sign-in's window: reads the settings file Terminal would get and runs its command the way Terminal's login shell
/// runs a command inside it (`/bin/sh -c`); its input stays open, like a window nobody types in. The shell's exit status is
/// what Terminal would close the window on ("Close if the shell exited cleanly": 0).
final class FakeTerminal {
    private let lock = NSLock()
    private(set) var opened: [URL] = []
    private(set) var shells: [Process] = []
    private var inputs: [Pipe] = []
    var settings: [String: Any] = [:]
    let conf: URL
    init(conf: URL) { self.conf = conf }

    func open(_ url: URL) -> Bool {
        lock.lock(); defer { lock.unlock() }
        opened.append(url)
        guard let d = try? Data(contentsOf: url),
              let p = (try? PropertyListSerialization.propertyList(from: d, format: nil)) as? [String: Any],
              let cmd = p["CommandString"] as? String else { return false }
        settings = p
        let sh = Process(), input = Pipe()
        sh.executableURL = URL(fileURLWithPath: "/bin/sh")
        sh.arguments = ["-c", cmd]
        sh.environment = ["PATH": "/usr/bin:/bin", "HOME": home.path, "ZDOTDIR": zdot.path, "TERM": "dumb",
                          "QC_LOGIN_CONF": conf.path, "ANTHROPIC_API_KEY": "made-up-key"]
        sh.standardInput = input
        sh.standardOutput = FileHandle.nullDevice; sh.standardError = FileHandle.nullDevice
        guard (try? sh.run()) != nil else { return false }
        inputs.append(input); shells.append(sh)
        return true
    }
    var last: Process? { lock.lock(); defer { lock.unlock() }; return shells.last }
    var count: Int { lock.lock(); defer { lock.unlock() }; return opened.count }
}

// ── one case: a folder, its stand-in login's settings, a terminal, a sign-in ─────────────────────────
final class Case {
    let name: String
    let folder: URL
    let work: URL
    let conf: URL
    let terminal: FakeTerminal
    var outcome: ClaudeSignIn.Outcome?
    var states: [ClaudeSignIn.State] = []
    var signIn: ClaudeSignIn!

    init(_ name: String, login: [String: String], make: Bool = true) {
        self.name = name
        folder = home.appendingPathComponent(".claude-\(name)")
        work = base.appendingPathComponent("work")                       // one work folder: the app's own (one per app)
        conf = base.appendingPathComponent("conf-\(name)")
        terminal = FakeTerminal(conf: conf)
        if make { try? fm.createDirectory(at: folder, withIntermediateDirectories: true) }
        try? login.map { "\($0.key)=\($0.value)" }.joined(separator: "\n").appending("\n").write(to: conf, atomically: true, encoding: .utf8)
    }

    var authFolder: AuthFolder { AuthFolder(path: folder.path, isDefault: false, home: home.path) }

    func tools() -> AuthTools {
        var t = AuthTools.system
        t.run = { _ in fatalError("no claude run is asked in a sign-in") }
        t.openTerminal = { [terminal] in terminal.open($0) }
        t.environment = { ["PATH": "/usr/bin:/bin"] }
        return t
    }

    @discardableResult
    func start(wanted: SignedInAccount?, timeout: TimeInterval = 20, confirm: @escaping ClaudeSignIn.Confirm = { _ in nil }) -> ClaudeSignIn {
        signIn = ClaudeSignIn(folder: authFolder, wanted: wanted, timeout: timeout, tools: tools(), claude: claude, confirm: confirm,
                              work: work, title: "Sample sign-in", locks: locks, poll: 0.2)
        signIn.start(onState: { [weak self] in self?.states.append($0) }, onEnd: { [weak self] in self?.outcome = $0 })
        return signIn
    }

    @discardableResult
    func waitEnd(_ max: TimeInterval = 15) -> ClaudeSignIn.Outcome? { spin(until: { outcome != nil }, max: max); return outcome }
    /// The stand-in login's pid, once it wrote it.
    var loginPid: pid_t { (try? String(contentsOf: URL(fileURLWithPath: conf.path + ".pid"), encoding: .utf8)).flatMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? -1 }
    func waitLogin() -> pid_t { spin(until: { pidAlive(loginPid) }, max: 10); return loginPid }
    /// The window's shell ended, and how: 0 is clean (Terminal closes the window).
    func shellEnded(_ max: TimeInterval = 8) -> Int32? {
        guard let s = terminal.last else { return nil }
        spin(until: { !s.isRunning }, max: max)
        return s.isRunning ? nil : s.terminationStatus
    }
    var shellRunning: Bool { terminal.last?.isRunning == true }
    func record(_ email: String, _ id: String, org: String = uuid(51), orgName: String = "Sample Org") {
        let j = #"{"oauthAccount":{"accountUuid":"\#(id)","emailAddress":"\#(email)","organizationUuid":"\#(org)","organizationName":"\#(orgName)"}}"#
        try? j.write(to: folder.appendingPathComponent(".claude.json"), atomically: true, encoding: .utf8)
    }
    func cleanUp() {
        if let s = terminal.last, s.isRunning { kill(s.processIdentifier, SIGKILL) }
        if pidAlive(loginPid) { kill(loginPid, SIGKILL) }
    }
}
/// A running claude's word, as SignedInAccount.process makes it from its `initialize` answer.
func said(_ email: String, _ org: String = "Sample Org") -> ClaudeSignIn.Confirm { { _ in SignedInAccount.process(["email": email, "organization": org]) } }
func wantedID(_ id: String) -> SignedInAccount { SignedInAccount(accountID: id, origin: .record) }

check("the stand-in claude is there", fm.isExecutableFile(atPath: claude), claude)

// ── the window: its settings file and its script ─────────────────────────────────────────────────────
do {
    let c = Case("window", login: ["login": "hang"])
    let s = c.start(wanted: SignedInAccount(email: "o'neil@example.com", origin: .record))
    spin(until: { c.states.contains(.waitingForBrowser) })
    let p = c.terminal.settings
    check("window: a Terminal settings file is opened (no AppleScript)", c.terminal.opened.last?.pathExtension == "terminal", "\(c.terminal.opened)")
    check("window: Window Settings, closed when the shell exits cleanly (shellExitAction 1), run inside the shell",
          p["type"] as? String == "Window Settings" && p["shellExitAction"] as? Int == 1 && p["RunCommandAsShell"] as? Bool == false, "\(p)")
    let script = c.work.appendingPathComponent("sign-in-\(ClaudeSignIn.lockKey(c.authFolder)).command")
    check("window: its command execs the script (named after the folder's lock key) in place of the login shell",
          p["CommandString"] as? String == "exec '\(script.path)'", "\(String(describing: p["CommandString"]))")
    check("window: its name is the app's", p["name"] as? String == "Sample sign-in")
    check("window: states opening, then waiting for the browser", c.states == [.opening, .waitingForBrowser], "\(c.states)")
    let login = c.waitLogin()
    let args = (try? String(contentsOfFile: c.conf.path + ".args", encoding: .utf8)) ?? ""
    check("script: claude auth login --claudeai --email, the address quoted", args.contains("ARG [auth]\nARG [login]\nARG [--claudeai]\nARG [--email]\nARG [o'neil@example.com]"), args)
    check("script: on this folder only, no key from the shell", args.contains("ENV CLAUDE_CONFIG_DIR=\(c.folder.path)") && args.contains("ENV KEY=<unset>"), args)
    check("script: it removed itself once started (it holds the address)", !fm.fileExists(atPath: script.path))
    let mode = ((try? fm.attributesOfItem(atPath: c.work.path))?[.posixPermissions] as? NSNumber)?.intValue
    check("work folder: owner only", mode == 0o700, "\(String(describing: mode))")
    let lines = SignInScript.lines(claude: "/sample/claude", folder: c.authFolder, email: nil, removesItself: true,
                                   watch: .init(pid: URL(fileURLWithPath: "/w/p"), status: URL(fileURLWithPath: "/w/s"), declined: URL(fileURLWithPath: "/w/d")))
    check("script: ends cleanly when asked to (TERM, HUP)", lines.contains("trap 'exit 0' TERM HUP"))
    check("script: its pid first, the login's status after", lines.contains("print -r -- $$ > '/w/p'") && lines.contains("print -r -- $s > '/w/s'"))
    check("script: Claude Code's errors still reach the window, looked through for a refusal",
          lines.contains { $0.contains("2>&1 1>&3 3>&- | tee /dev/fd/4 | { grep -F -m 1 -e 'OAuth error: access_denied' >/dev/null && : > '/w/d'; cat >/dev/null; }") }
          && lines.contains("s=${pipestatus[1]}"))
    check("script: a login that didn't end well stays on screen until Return; then a clean end",
          lines.suffix(2) == ["if [ $s -ne 0 ]; then read -r; fi", "exit 0"])
    let folderFiles = (try? fm.contentsOfDirectory(atPath: c.folder.path)) ?? []
    check("nothing written into the Claude Code folder", folderFiles.isEmpty, "\(folderFiles)")
    s.stop()
    check("stop: the outcome is stopped", c.waitEnd() == .stopped, "\(String(describing: c.outcome))")
    check("stop: the claude auth login in the window is ended", spin(until: { !pidAlive(login) }, max: 5), "pid \(login)")
    check("stop: the window's shell ends cleanly (its window closes)", c.shellEnded() == 0)
    let left = (try? fm.contentsOfDirectory(atPath: c.work.path)) ?? []
    check("stop: nothing left in the work folder", left.isEmpty, "\(left)")
    let lock = open(locks.appendingPathComponent("signin-\(AuthFolder.sha8(c.folder.resolvingSymlinksInPath().path)).lock").path, O_RDWR)
    check("stop: the folder's lock is free again", lock >= 0 && flock(lock, LOCK_EX | LOCK_NB) == 0)
    if lock >= 0 { close(lock) }
    c.cleanUp()
}

// ── each outcome ──────────────────────────────────────────────────────────────────────────────────────
do {
    let c = Case("verified", login: ["login": "ok", "email": "ann@example.com", "uuid": uuid(1), "org": uuid(51), "orgName": "Sample Org"])
    c.start(wanted: wantedID(uuid(1)), confirm: said("ann@example.com"))
    let o = c.waitEnd()
    if case .signedIn(let a)? = o {
        check("signed in: the account wanted by its id, verified by the app's word", a.accountID == uuid(1) && a.email == "ann@example.com"
              && a.source == .verified, "\(a)")
    } else { check("signed in (verified)", false, "\(String(describing: o))") }
    check("signed in: the window's shell ended cleanly by itself (its window closes)", c.shellEnded() == 0)
    c.cleanUp()
}
do {
    let c = Case("guessed", login: ["login": "ok", "email": "ann@example.com", "uuid": uuid(1), "org": uuid(51)])
    c.start(wanted: SignedInAccount(email: "Ann@Example.com", origin: .record))
    if case .signedIn(let a)? = c.waitEnd() {
        check("signed in: no word from the app, the record is a guess", a.source == .guessed && a.accountID == uuid(1), "\(a)")
    } else { check("signed in (guessed)", false, "\(String(describing: c.outcome))") }
    c.cleanUp()
}
do {
    let c = Case("again", login: ["login": "ok", "email": "ann@example.com", "uuid": uuid(1), "org": uuid(51)])
    c.record("ann@example.com", uuid(1))            // already on it: the record doesn't change, only the login's end says so
    c.start(wanted: wantedID(uuid(1)), confirm: said("ann@example.com"))
    // the record names no organisation by name, the running claude no ids: the same address, the record's id for the one wanted
    if case .signedIn(let a)? = c.waitEnd() { check("signed in again on the same account: the login's good end", a.email == "ann@example.com" && a.source == .verified, "\(a)") }
    else { check("signed in again", false, "\(String(describing: c.outcome))") }
    c.cleanUp()
}
do {
    let c = Case("new", login: ["login": "ok", "email": "new@example.com", "uuid": uuid(3), "org": uuid(51), "orgName": "Sample Org"])
    c.start(wanted: nil, confirm: said("new@example.com"))
    if case .signedIn(let a)? = c.waitEnd() { check("a brand-new folder (no account wanted): whoever signed in", a.email == "new@example.com" && a.accountID == uuid(3)) }
    else { check("new folder", false, "\(String(describing: c.outcome))") }
    c.cleanUp()
}
do {
    let c = Case("wrongid", login: ["login": "ok", "email": "ann@example.com", "uuid": uuid(2), "org": uuid(51), "orgName": "Sample Org"])
    c.start(wanted: wantedID(uuid(1)), confirm: said("ann@example.com"))
    if case .wrongAccount(let a, let w)? = c.waitEnd() {
        check("wrong account by id: another id signed in", a.accountID == uuid(2) && w.accountID == uuid(1), "\(a) \(w)")
    } else { check("wrong account by id", false, "\(String(describing: c.outcome))") }
    check("wrong account: the window's shell ended cleanly (its window closes)", c.shellEnded() == 0)
    c.cleanUp()
}
do {
    let c = Case("wrongorg", login: ["login": "ok", "email": "ann@example.com", "uuid": uuid(4), "org": uuid(52), "orgName": "Other Org"])
    c.start(wanted: SignedInAccount(email: "ann@example.com", organizationName: "Sample Org", origin: .record), confirm: said("ann@example.com", "Other Org"))
    if case .wrongAccount(let a, _)? = c.waitEnd() {
        check("wrong account by address and organisation: the same address in another organisation", a.organizationName == "Other Org", "\(a)")
    } else { check("wrong account by organisation", false, "\(String(describing: c.outcome))") }
    c.cleanUp()
    let d = Case("rightorg", login: ["login": "ok", "email": "ann@example.com", "uuid": uuid(5), "org": uuid(51), "orgName": "Sample Org"])
    d.start(wanted: SignedInAccount(email: "ANN@example.com", organizationName: "sample org", origin: .record), confirm: said("ann@example.com", "Sample Org"))
    if case .signedIn? = d.waitEnd() { check("the same address and organisation (case doesn't count): signed in", true) }
    else { check("right organisation", false, "\(String(describing: d.outcome))") }
    d.cleanUp()
    let e = Case("wrongaddr", login: ["login": "ok", "email": "bob@example.com", "uuid": uuid(6), "org": uuid(51)])
    e.start(wanted: SignedInAccount(email: "ann@example.com", origin: .record), confirm: said("bob@example.com"))
    if case .wrongAccount(let a, _)? = e.waitEnd() { check("wrong account by address", a.email == "bob@example.com") }
    else { check("wrong address", false, "\(String(describing: e.outcome))") }
    e.cleanUp()
}
do {
    let c = Case("declined", login: ["login": "declined"])
    c.start(wanted: wantedID(uuid(1)))
    check("declined: Claude Code's refusal in the window is seen", c.waitEnd() == .declined, "\(String(describing: c.outcome))")
    spin(0.5)
    check("declined: the window stays open to be read", c.shellRunning)
    c.signIn.stop()
    check("declined: stop then closes it (a clean end)", c.shellEnded() == 0)
    c.cleanUp()
}
do {
    let c = Case("declinedwait", login: ["login": "declinedwait"])
    c.start(wanted: wantedID(uuid(1)))
    let login = c.waitLogin()
    check("declined while the login still waits: declined at once", c.waitEnd() == .declined, "\(String(describing: c.outcome))")
    check("…the login left waiting is ended", spin(until: { !pidAlive(login) }, max: 5))
    spin(0.5)
    check("…and the window stays open to be read", c.shellRunning)
    c.cleanUp()
}
do {
    let c = Case("failed", login: ["login": "fail"])
    c.start(wanted: wantedID(uuid(1)))
    check("failed: the login's exit status", c.waitEnd() == .failed(.loginFailed(status: 2)), "\(String(describing: c.outcome))")
    spin(0.5)
    check("failed: the window stays open to be read", c.shellRunning)
    // the next start closes it
    let held = c.terminal.last!
    let n = Case("afterfail", login: ["login": "hang"])
    n.start(wanted: nil)
    spin(until: { !held.isRunning }, max: 8)
    check("failed: the next sign-in's start closes it (a clean end)", !held.isRunning && held.terminationStatus == 0)
    n.signIn.stop(); n.waitEnd()
    c.cleanUp(); n.cleanUp()
}
do {
    let c = Case("timeout", login: ["login": "hang"])
    c.start(wanted: wantedID(uuid(1)), timeout: 1.5)
    let login = c.waitLogin()
    check("timed out: nothing came within the timeout", c.waitEnd() == .timedOut, "\(String(describing: c.outcome))")
    check("timed out: the login is ended", spin(until: { !pidAlive(login) }, max: 5))
    check("timed out: the window's shell ended cleanly (its window closes)", c.shellEnded() == 0)
    c.cleanUp()
}
do {
    let c = Case("closed", login: ["login": "hang"])
    c.start(wanted: wantedID(uuid(1)))
    let login = c.waitLogin()
    spin(until: { fm.fileExists(atPath: c.work.appendingPathComponent("sign-in.pid").path) }, max: 5)
    // Terminal closing the window hangs up its whole session
    if let s = c.terminal.last { kill(s.processIdentifier, SIGHUP) }
    kill(login, SIGHUP)
    check("window closed while the login ran: failed, window closed", c.waitEnd() == .failed(.windowClosed), "\(String(describing: c.outcome))")
    c.cleanUp()
}

// ── one sign-in per app, and the two guards ──────────────────────────────────────────────────────────
do {
    let a = Case("first", login: ["login": "hang"])
    a.start(wanted: wantedID(uuid(1)))
    let first = a.waitLogin()
    let b = Case("second", login: ["login": "ok", "email": "bob@example.com", "uuid": uuid(2), "org": uuid(51)])
    b.start(wanted: wantedID(uuid(2)), confirm: said("bob@example.com"))
    check("a second start ends the first: stopped", a.waitEnd() == .stopped, "\(String(describing: a.outcome))")
    check("…its login is ended", spin(until: { !pidAlive(first) }, max: 5))
    check("…its window's shell ended cleanly", a.shellEnded() == 0)
    if case .signedIn? = b.waitEnd() { check("…and the second goes on", true) } else { check("second goes on", false, "\(String(describing: b.outcome))") }
    a.cleanUp(); b.cleanUp()
}
/// A `claude auth login` on a folder that this app didn't start: another app's sign-in (its script, named after the folder's
/// lock key, runs the login), or a bare one (a terminal's). Ended by its pid (and its script's) afterwards.
func otherLogin(_ c: Case, viaScript: Bool) -> (shell: Process, login: pid_t) {
    let conf = c.conf.path + "-other"
    try? "login=hang\n".write(toFile: conf, atomically: true, encoding: .utf8)
    try? fm.removeItem(atPath: conf + ".pid")
    let p = Process()
    p.environment = ["PATH": "/usr/bin:/bin", "CLAUDE_CONFIG_DIR": c.folder.path, "QC_LOGIN_CONF": conf, "HOME": home.path, "ZDOTDIR": zdot.path]
    if viaScript {
        let dir = base.appendingPathComponent("other-app")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("sign-in-\(ClaudeSignIn.lockKey(c.authFolder)).command")
        try? "#!/bin/zsh\n'\(claude)' auth login --claudeai\ns=$?\nexit $s\n".write(to: script, atomically: true, encoding: .utf8)
        p.executableURL = URL(fileURLWithPath: "/bin/zsh"); p.arguments = [script.path]
    } else {
        p.executableURL = URL(fileURLWithPath: claude); p.arguments = ["auth", "login", "--claudeai"]
    }
    p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
    try? p.run()
    spin(until: { fm.fileExists(atPath: conf + ".pid") }, max: 5)
    let pid = (try? String(contentsOfFile: conf + ".pid", encoding: .utf8)).flatMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? -1
    return (p, pid)
}
func endOther(_ o: (shell: Process, login: pid_t)) {
    if pidAlive(o.login) { kill(o.login, SIGTERM) }
    if o.shell.isRunning { kill(o.shell.processIdentifier, SIGTERM) }
    o.shell.waitUntilExit()
    spin(until: { !pidAlive(o.login) }, max: 3)
}
do {
    // another app's sign-in on the folder
    let c = Case("guard", login: ["login": "hang"])
    let other = otherLogin(c, viaScript: true)
    check("process guard: the other app's login runs", pidAlive(other.login))
    c.start(wanted: wantedID(uuid(1)))
    check("process guard: a claude auth login already on the folder (another app's): refused",
          c.waitEnd() == .failed(.alreadySigningIn), "\(String(describing: c.outcome))")
    check("process guard: no window opened", c.terminal.count == 0)
    // another folder's login doesn't count
    let d = Case("guard-other", login: ["login": "hang"])
    d.start(wanted: wantedID(uuid(1)))
    spin(until: { d.states.contains(.waitingForBrowser) || d.outcome != nil })
    check("process guard: another app's login on another folder doesn't refuse this one", d.outcome == nil && d.terminal.count == 1,
          "\(String(describing: d.outcome))")
    d.signIn.stop(); d.waitEnd()
    endOther(other)
    // a bare login (a terminal's): its folder is its CLAUDE_CONFIG_DIR where the kernel says it; where it doesn't (macOS 27),
    // it can't be told, and it refuses rather than guesses
    let bare = otherLogin(c, viaScript: false)
    let e = Case("guard-bare", login: ["login": "hang"])
    c.outcome = nil
    let s = ClaudeSignIn(folder: c.authFolder, wanted: nil, tools: c.tools(), claude: claude, confirm: { _ in nil }, work: c.work, locks: locks, poll: 0.2)
    s.start { c.outcome = $0 }
    check("process guard: a terminal's login on the folder: refused", c.waitEnd() == .failed(.alreadySigningIn), "\(String(describing: c.outcome))")
    endOther(bare)
    c.cleanUp(); d.cleanUp(); e.cleanUp()
}
do {
    let c = Case("lock", login: ["login": "hang"])
    let lockPath = locks.appendingPathComponent("signin-\(ClaudeSignIn.lockKey(c.authFolder)).lock").path
    try? fm.createDirectory(at: locks, withIntermediateDirectories: true)
    // the lock's name: 8 hex of the SHA-256 of the folder's real path, the same through a link to it
    try? fm.createSymbolicLink(at: home.appendingPathComponent("link-to-lock"), withDestinationURL: c.folder)
    let viaLink = AuthFolder(path: home.appendingPathComponent("link-to-lock").path, isDefault: false, home: home.path)
    check("lock: one name per real folder (a link to it has the same)", ClaudeSignIn.lockKey(viaLink) == ClaudeSignIn.lockKey(c.authFolder)
          && ClaudeSignIn.lockKey(c.authFolder) == AuthFolder.sha8(c.folder.resolvingSymlinksInPath().path) && ClaudeSignIn.lockKey(c.authFolder).count == 8)
    check("lock: under ~/Library/Caches/n-uf by default", ClaudeSignIn.sharedLocks.path.hasSuffix("/Library/Caches/n-uf"))
    let fd = open(lockPath, O_RDWR | O_CREAT, 0o600)          // another app holds it
    check("lock: taken by the other app", fd >= 0 && flock(fd, LOCK_EX | LOCK_NB) == 0)
    c.start(wanted: wantedID(uuid(1)))
    check("lock: held elsewhere, the start is refused", c.waitEnd() == .failed(.locked), "\(String(describing: c.outcome))")
    check("lock: no window opened", c.terminal.count == 0)
    close(fd)
    c.cleanUp()
}
do {
    let c = Case("missing", login: ["login": "ok"], make: false)
    c.start(wanted: nil)
    check("a folder that isn't there: refused", c.waitEnd() == .failed(.folderNotReady), "\(String(describing: c.outcome))")
    check("…and never made", !fm.fileExists(atPath: c.folder.path))
    check("…no window", c.terminal.count == 0)
    let real = home.appendingPathComponent("real-folder")
    try? fm.createDirectory(at: real, withIntermediateDirectories: true)
    try? fm.removeItem(at: c.folder)
    try? fm.createSymbolicLink(at: c.folder, withDestinationURL: real)
    let l = Case("missing", login: ["login": "ok"], make: false)
    l.start(wanted: nil)
    check("a link to a folder: refused (never launched through)", l.waitEnd() == .failed(.folderNotReady), "\(String(describing: l.outcome))")
    var guarded = 0
    let g = Case("guarded", login: ["login": "ok"])
    var t = g.tools(); t.mayLaunch = { what, _ in guarded += what == "login" ? 1 : 0; return false }
    let s = ClaudeSignIn(folder: g.authFolder, wanted: nil, tools: t, claude: claude, confirm: { _ in nil }, work: g.work, locks: locks, poll: 0.2)
    s.start { g.outcome = $0 }
    check("the app's guard says no (cl_audit's FolderGuard): refused", g.waitEnd() == .failed(.folderNotReady) && guarded == 1 && g.terminal.count == 0)
}

// ── cl_quick's word: a short claude's `initialize` account (never the Keychain) ──────────────────────
do {
    let c = Case("word", login: [:])
    c.record("ann@example.com", uuid(1), orgName: "Sample Org")
    let confirmWork = base.appendingPathComponent("confirm/work")
    try? fm.createDirectory(at: confirmWork, withIntermediateDirectories: true)
    let word = SignInWord.confirm(claude: claude, workFolder: confirmWork.path)
    var got: SignedInAccount?
    var done = false
    DispatchQueue.global().async { got = word(c.authFolder); DispatchQueue.main.async { done = true } }
    spin(until: { done }, max: 25)
    check("cl_quick's word: the running claude's own account (initialize), verified", got?.email == "ann@example.com"
          && got?.organizationName == "Sample Org" && got?.origin == .process, "\(String(describing: got))")
    try? "account=none\n".write(to: confirmWork.deletingLastPathComponent().appendingPathComponent("stub.conf"), atomically: true, encoding: .utf8)
    done = false; got = nil
    DispatchQueue.global().async { got = word(c.authFolder); DispatchQueue.main.async { done = true } }
    spin(until: { done }, max: 25)
    check("cl_quick's word: a claude that names nobody says nothing (the record stays a guess)", done && got == nil, "\(String(describing: got))")
}

// ── cl_quick's switch on it: today's notes ───────────────────────────────────────────────────────────
do {
    var told: [String] = []
    AccountSwitcher.tell = { told.append($0) }
    let sw = AccountSwitcher.shared
    var last: Case!
    var outcomes: [SwitchOutcome] = []
    sw.onOutcome = { _, o in outcomes.append(o) }
    sw.findClaude = { claude }
    sw.makeSignIn = { folder, wanted, cl in
        var t = last.tools()
        t.mayLaunch = { _, f in f.isReady }
        return ClaudeSignIn(folder: AuthFolder(path: folder, isDefault: false, home: home.path), wanted: wanted, timeout: 3, tools: t, claude: cl,
                            confirm: SignInWord.confirm(claude: cl, workFolder: base.appendingPathComponent("confirm/work").path),
                            work: last.work, locks: locks, poll: 0.2)
    }
    try? "".write(to: base.appendingPathComponent("confirm/stub.conf"), atomically: true, encoding: .utf8)

    func profile(_ c: Case) -> Profile { Profile(id: c.name, name: c.name, folder: c.folder.path) }
    func run(_ c: Case, uuid u: String?, email: String) -> SwitchOutcome? {
        last = c
        let before = outcomes.count
        sw.begin(profile(c), uuid: u, email: email, origin: .settings)
        check("switch \(c.name): waiting at once (the note says switching)", sw.waiting[c.name] != nil)
        spin(until: { outcomes.count > before }, max: 20)
        return outcomes.count > before ? outcomes.last : nil
    }
    let ok = Case("sw-ok", login: ["login": "ok", "email": "kim@example.com", "uuid": uuid(7), "org": uuid(51), "orgName": "Sample Org"])
    ok.record("ann@example.com", uuid(1))
    ProfileStore.shared.save([profile(ok)])
    check("switch: the account wanted is reached", run(ok, uuid: uuid(7), email: "kim@example.com") == .reached, "\(outcomes)")
    check("switch: no note left (reached)", sw.waiting[ok.name] == nil && sw.ended[ok.name] == nil)
    check("switch: its window closed", ok.shellEnded() == 0)

    let wrong = Case("sw-wrong", login: ["login": "ok", "email": "bob@example.com", "uuid": uuid(8), "org": uuid(51), "orgName": "Sample Org"])
    wrong.record("ann@example.com", uuid(1))
    check("switch: another account is the wrong-account note", run(wrong, uuid: uuid(7), email: "kim@example.com") == .other(email: "bob@example.com")
          && sw.ended[wrong.name]?.signedIn == "bob@example.com", "\(outcomes) \(String(describing: sw.ended[wrong.name]))")

    let none = Case("sw-none", login: ["login": "hang"])
    none.record("ann@example.com", uuid(1))
    check("switch: no sign-in is the timeout's note", run(none, uuid: uuid(7), email: "kim@example.com") == .timedOut
          && sw.ended[none.name] != nil && sw.ended[none.name]?.signedIn == nil)
    check("switch: …and its login is ended", spin(until: { !pidAlive(none.loginPid) }, max: 5))

    let declined = Case("sw-declined", login: ["login": "declined"])
    declined.record("ann@example.com", uuid(1))
    check("switch: a declined sign-in is the account-unchanged note (as a timeout's, sooner)",
          run(declined, uuid: uuid(7), email: "kim@example.com") == .timedOut && sw.ended[declined.name]?.signedIn == nil)

    let stop = Case("sw-stop", login: ["login": "hang"])
    stop.record("ann@example.com", uuid(1))
    last = stop
    sw.begin(profile(stop), uuid: uuid(7), email: "kim@example.com", origin: .chat)
    let login = stop.waitLogin()
    sw.drop(stop.name)
    check("switch: Stop drops the note", sw.waiting[stop.name] == nil && sw.ended[stop.name] == nil)
    check("switch: Stop ends the claude auth login in the window, and the window", spin(until: { !pidAlive(login) }, max: 5) && stop.shellEnded() == 0)

    let gone = Case("sw-gone", login: ["login": "ok"], make: false)
    last = gone
    let before = told.count
    sw.begin(profile(gone), uuid: uuid(7), email: "kim@example.com", origin: .settings)
    spin(until: { told.count > before }, max: 10)
    check("switch: a folder that isn't there: the sign-in couldn't start, said; no note left",
          told.count == before + 1 && sw.waiting[gone.name] == nil && told.last?.contains("isn't there") == true, "\(told)")
    for c in [ok, wrong, none, declined, stop] { c.cleanUp() }
}

print(failed == 0 ? "signin checks: \(passed)/\(passed) passed" : "signin checks: \(failed) failed, \(passed) passed")
exit(failed == 0 ? 0 : 1)
