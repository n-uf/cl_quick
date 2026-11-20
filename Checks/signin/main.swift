// The sign-in's checks (Checks/signin.sh): ClaudeAuth's ClaudeSignIn as cl_quick builds it, and cl_quick's switch on top
// of it. No real Terminal: a stand-in opens the window's settings file and runs its command with /bin/sh, as Terminal's
// login shell would, with an input that stays open (a window nobody types in). No real `claude`: Checks/signin/bin/claude
// is a stand-in `claude auth login` (and the quick chat's stand-in for `initialize`). Folders, work folders and locks are
// under build/; sample addresses (example.com) only; nothing is read from or written to this Mac's own folders, and only
// processes this run started are signalled, by their pids.

import AppKit
import ClaudeAuth
import Runs

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

// ── the stand-in Terminal preferences ──────────────────────────────────────────────────────────────
/// What Terminal keeps in its preferences ("Window Settings", and the names its default and startup settings point at), in
/// memory: this Mac's Terminal preferences are never read or written. Like Terminal, `keep` stores the profile of a settings
/// file it opens under the FILE's base name (not the plist's `name`), " 1", " 2"… added to a name it already holds.
final class FakePrefs {
    private let lock = NSLock()
    private var profiles: [String: Any] = [:]
    private var inUse: Set<String> = []
    private(set) var reads = 0, writes = 0
    var readable = true

    var tool: TerminalProfiles {
        TerminalProfiles(read: { [self] in
            lock.lock(); defer { lock.unlock() }
            reads += 1
            return readable ? (profiles, inUse) : nil
        }, write: { [self] in
            lock.lock(); defer { lock.unlock() }
            writes += 1
            profiles = $0
        })
    }
    func put(_ name: String, command: String, inUse use: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        profiles[name] = ["type": "Window Settings", "name": name, "CommandString": command]
        if use { inUse.insert(name) }
    }
    func keep(file: URL, plist: [String: Any]) {
        lock.lock(); defer { lock.unlock() }
        let base = file.deletingPathExtension().lastPathComponent
        var name = base, n = 0
        while profiles[name] != nil { n += 1; name = "\(base) \(n)" }
        profiles[name] = plist
    }
    var names: [String] { lock.lock(); defer { lock.unlock() }; return profiles.keys.sorted() }
    func command(_ name: String) -> String? { lock.lock(); defer { lock.unlock() }; return (profiles[name] as? [String: Any])?["CommandString"] as? String }
    /// The profiles whose command runs in a work folder, but for the ones Terminal's default or startup settings name.
    func left(in work: URL) -> [String] {
        lock.lock(); let pinned = inUse; lock.unlock()
        return names.filter { !pinned.contains($0) && command($0)?.contains(work.path + "/") == true }
    }
    func reset() { lock.lock(); profiles = [:]; inUse = []; reads = 0; writes = 0; readable = true; lock.unlock() }
}
let prefs = FakePrefs()

// ── the stand-in Terminal ──────────────────────────────────────────────────────────────────────────
/// Opens a sign-in's window: reads the settings file Terminal would get and runs its command the way Terminal's login shell
/// runs a command inside it (`/bin/sh -c`); its input stays open, like a window nobody types in. The shell's exit status is
/// what Terminal would close the window on ("Close if the shell exited cleanly": 0). It keeps the profile in `prefs`, as
/// Terminal does.
final class FakeTerminal {
    private let lock = NSLock()
    private(set) var opened: [URL] = []
    private(set) var shells: [Process] = []
    private var inputs: [Pipe] = []
    var settings: [String: Any] = [:]
    let conf: URL
    /// Says it opened the file, but never runs it (a Terminal that never started the script).
    var neverStarts = false
    /// Runs this shell body in place of the script's command (it gets the script's path, so the shell's command line names it):
    /// a window whose shell the check shapes (one that ignores TERM). Nothing is passed to it but that path.
    var shellBody: String?
    init(conf: URL) { self.conf = conf }

    func open(_ url: URL) -> Bool {
        lock.lock(); defer { lock.unlock() }
        opened.append(url)
        if let d = try? Data(contentsOf: url), let p = (try? PropertyListSerialization.propertyList(from: d, format: nil)) as? [String: Any] {
            prefs.keep(file: url, plist: p)
        }
        if neverStarts { return true }
        guard let d = try? Data(contentsOf: url),
              let p = (try? PropertyListSerialization.propertyList(from: d, format: nil)) as? [String: Any],
              let cmd = p["CommandString"] as? String else { return false }
        settings = p
        let sh = Process(), input = Pipe()
        sh.executableURL = URL(fileURLWithPath: "/bin/sh")
        if let body = shellBody {
            // the command is "exec '<script>'": the script's path is what a window's shell carries in its command line
            let path = cmd.hasPrefix("exec '") && cmd.hasSuffix("'") ? String(cmd.dropFirst(6).dropLast()) : cmd
            sh.arguments = ["-c", body, "stand-in", path]
        } else {
            sh.arguments = ["-c", cmd]
        }
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
    func start(wanted: SignedInAccount?, timeout: TimeInterval = 20, startGrace: TimeInterval = 10, lateSweep: TimeInterval = 0.3,
               confirm: @escaping ClaudeSignIn.Confirm = { _ in nil }) -> ClaudeSignIn {
        signIn = ClaudeSignIn(folder: authFolder, wanted: wanted, timeout: timeout, tools: tools(), claude: claude, confirm: confirm,
                              work: work, title: "Sample app", startGrace: startGrace, terminalProfiles: prefs.tool, lateSweep: lateSweep,
                              locks: locks, poll: 0.2)
        signIn.start(onState: { [weak self] in self?.states.append($0) }, onEnd: { [weak self] in self?.outcome = $0 })
        return signIn
    }

    /// A stand-in word that answers only once the login has ended (the script wrote its status 0; up to 5 s, polled every 20 ms;
    /// the word is asked on its own queue): every ask it counts is then after the end, which is the asks the product counts.
    func afterEnd(_ answer: @escaping ClaudeSignIn.Confirm) -> ClaudeSignIn.Confirm {
        let status = work.appendingPathComponent("sign-in.status")
        return { folder in
            let until = Date().addingTimeInterval(5)
            while Date() < until {
                if let s = try? String(contentsOf: status, encoding: .utf8), Int32(s.trimmingCharacters(in: .whitespacesAndNewlines)) == 0 { break }
                usleep(20_000)
            }
            return answer(folder)
        }
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
    // the app's work folder already there, open to others: it is made owner only
    try? fm.createDirectory(at: base.appendingPathComponent("work"), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
    let c = Case("window", login: ["login": "hang"])
    // Terminal's preferences hold what earlier sign-ins left (a stale command each), and profiles that aren't this app's
    let workPath = c.work.path
    prefs.reset()
    prefs.put("Sample app sign-in", command: "exec '\(workPath)/sign-in-aaaaaaaa.command'")
    prefs.put("Sample app sign-in 1", command: "exec '\(workPath)/sign-in-bbbbbbbb.command'")
    prefs.put("Basic", command: "/bin/zsh -l")
    prefs.put("Other app sign-in", command: "exec '\(base.path)/other-work/sign-in-cccccccc.command'")
    prefs.put("Lookalike", command: "exec '\(workPath)-2/sign-in-dddddddd.command'")
    prefs.put("Pinned", command: "exec '\(workPath)/sign-in-eeeeeeee.command'", inUse: true)
    let s = c.start(wanted: SignedInAccount(email: "o'neil@example.com", origin: .record))
    spin(until: { c.states.contains(.waitingForBrowser) })
    let p = c.terminal.settings
    check("profiles: the start swept the leftovers of earlier sign-ins (this app's work folder, never Terminal's default profile)",
          prefs.names == ["Basic", "Lookalike", "Other app sign-in", "Pinned", "Sample app sign-in"], "\(prefs.names)")
    check("profiles: …Terminal kept this sign-in's own profile, named after the settings file", prefs.command("Sample app sign-in")?.contains(workPath + "/sign-in-") == true
          && prefs.command("Sample app sign-in")?.contains("aaaaaaaa") == false, "\(String(describing: prefs.command("Sample app sign-in")))")
    check("window: a Terminal settings file is opened (no AppleScript)", c.terminal.opened.last?.pathExtension == "terminal", "\(c.terminal.opened)")
    check("window: the file is named after the app (\"<title> sign-in.terminal\")", c.terminal.opened.last?.lastPathComponent == "Sample app sign-in.terminal", "\(c.terminal.opened)")
    check("window: Window Settings, closed when the shell exits cleanly (shellExitAction 1), run inside the shell",
          p["type"] as? String == "Window Settings" && p["shellExitAction"] as? Int == 1 && p["RunCommandAsShell"] as? Bool == false, "\(p)")
    let script = c.work.appendingPathComponent("sign-in-\(ClaudeSignIn.lockKey(c.authFolder)).command")
    check("window: its command execs the script (named after the folder's lock key) in place of the login shell",
          p["CommandString"] as? String == "exec '\(script.path)'", "\(String(describing: p["CommandString"]))")
    let name = p["name"] as? String ?? ""
    check("window: the plist's name is the file's base name (Terminal names the profile after the file)",
          name == "Sample app sign-in" && name == s.profileName && c.terminal.opened.last?.deletingPathExtension().lastPathComponent == name, name)
    check("window: a title with a slash or colon makes a plain file name", ClaudeSignIn(folder: c.authFolder, wanted: nil, tools: c.tools(), claude: claude,
          confirm: { _ in nil }, work: c.work, title: "A/B: app", terminalProfiles: prefs.tool).profileName == "A-B- app sign-in")
    check("window: states opening, then waiting for the browser", c.states == [.opening, .waitingForBrowser], "\(c.states)")
    let login = c.waitLogin()
    let args = (try? String(contentsOfFile: c.conf.path + ".args", encoding: .utf8)) ?? ""
    check("script: claude auth login --claudeai --email, the address quoted", args.contains("ARG [auth]\nARG [login]\nARG [--claudeai]\nARG [--email]\nARG [o'neil@example.com]"), args)
    check("script: on this folder only, no key from the shell", args.contains("ENV CLAUDE_CONFIG_DIR=\(c.folder.path)") && args.contains("ENV KEY=<unset>"), args)
    check("script: it removed itself once started (it holds the address)", !fm.fileExists(atPath: script.path))
    let mode = ((try? fm.attributesOfItem(atPath: c.work.path))?[.posixPermissions] as? NSNumber)?.intValue
    check("work folder: one already there (0755) is made owner only", mode == 0o700, "\(String(describing: mode))")
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
    check("profiles: the stop took this sign-in's profile; the others stay (Terminal's default one too)",
          spin(until: { prefs.names == ["Basic", "Lookalike", "Other app sign-in", "Pinned"] }, max: 3), "\(prefs.names)")
    check("profiles: …nothing but those removals was written (one write at the start, one at the stop)", prefs.writes == 2, "\(prefs.writes)")
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
    check("signed in: Terminal's kept profile for it is gone", spin(until: { prefs.left(in: c.work).isEmpty }, max: 4), "\(prefs.names)")
    c.cleanUp()
}
do {
    let c = Case("guessed", login: ["login": "ok", "email": "ann@example.com", "uuid": uuid(1), "org": uuid(51)])
    var asked = 0
    // the stand-in login writes the record and exits before the script writes the status: a tick in that gap asks the word
    // once before the end, which the product doesn't count, so the stand-in waits for the end before it answers
    c.start(wanted: SignedInAccount(email: "Ann@Example.com", origin: .record), confirm: c.afterEnd { _ in asked += 1; return nil })
    if case .unverified(let a)? = c.waitEnd() {
        check("no word from the app: the record's guess ends unverified, never signed in", a.source == .guessed && a.accountID == uuid(1), "\(a)")
    } else { check("unverified (no word)", false, "\(String(describing: c.outcome))") }
    check("…after the word was asked again (3 times in all once the login ended)", asked == 3, "\(asked)")
    check("…and its window closed", c.shellEnded() == 0)
    c.cleanUp()
}
do {
    // an ask before the login ended (the record changed first) doesn't count against the 3 tries: 3 asks after the end, however
    // many came before. The stand-in login holds 1 s between writing the record and ending, so the early ask is surely before
    // the status exists (one ask, as the record changed once), and the counts are exact.
    let c = Case("early-ask", login: ["login": "ok", "email": "ann@example.com", "uuid": uuid(1), "org": uuid(51), "hold": "1"])
    let lock = NSLock()
    var before = 0, after = 0
    let status = c.work.appendingPathComponent("sign-in.status")
    c.start(wanted: SignedInAccount(email: "Ann@Example.com", origin: .record), confirm: { _ in
        let ended = (try? String(contentsOf: status, encoding: .utf8)).flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) } == 0
        lock.lock(); if ended { after += 1 } else { before += 1 }; lock.unlock()
        return nil
    })
    let o = c.waitEnd()
    lock.lock(); let (b, a) = (before, after); lock.unlock()
    // The early ask is the one before the end (the record changed with the login still held), well before the status: a counted
    // early ask would leave 2 after.
    check("no word: one ask came before the login ended and it doesn't count: exactly 3 after it",
          { if case .unverified? = o { return true } else { return false } }() && b == 1 && a == 3, "\(String(describing: o)) before \(b) after \(a)")
    c.cleanUp()
}
do {
    // the word disagrees with the record at first (the record a step behind), then agrees: confirmed after the retries
    let c = Case("catchup", login: ["login": "ok", "email": "ann@example.com", "uuid": uuid(1), "org": uuid(51), "orgName": "Sample Org"])
    var asked = 0
    c.start(wanted: wantedID(uuid(1)), confirm: { _ in asked += 1; return SignedInAccount.process(["email": asked < 3 ? "bob@example.com" : "ann@example.com", "organization": "Sample Org"]) })
    if case .signedIn(let a)? = c.waitEnd() { check("the word catching up with the record: signed in on the third ask", a.accountID == uuid(1) && asked == 3, "\(a) \(asked)") }
    else { check("catch-up", false, "\(String(describing: c.outcome)) \(asked)") }
    c.cleanUp()
}
do {
    // the word keeps naming another account than the record (stale): never a match, unverified
    let c = Case("stale", login: ["login": "ok", "email": "ann@example.com", "uuid": uuid(1), "org": uuid(51), "orgName": "Sample Org"])
    c.start(wanted: wantedID(uuid(1)), confirm: said("bob@example.com"))
    if case .unverified(let a)? = c.waitEnd() { check("the word and a stale record never agreeing: unverified, the word's account", a.email == "bob@example.com", "\(a)") }
    else { check("stale record", false, "\(String(describing: c.outcome))") }
    c.cleanUp()
}
do {
    // the same address in another organisation, the word without an id: the id wanted is compared with the record's only
    // when the record agrees with the word; here it doesn't (the record is the wanted seat's, the word another's)
    let c = Case("seat", login: ["login": "ok", "email": "ann@example.com", "uuid": uuid(1), "org": uuid(51), "orgName": "Sample Org"])
    c.start(wanted: SignedInAccount(accountID: uuid(1), email: "ann@example.com", origin: .record), confirm: said("ann@example.com", "Other Org"))
    if case .unverified? = c.waitEnd() { check("a same-address seat in another organisation, the record disagreeing: not taken for the one wanted", true) }
    else { check("same-address seat", false, "\(String(describing: c.outcome))") }
    c.cleanUp()
    // …and where the record agrees with the word (the other seat's own id), it is the wrong account
    let d = Case("seat2", login: ["login": "ok", "email": "ann@example.com", "uuid": uuid(9), "org": uuid(59), "orgName": "Other Org"])
    d.start(wanted: SignedInAccount(accountID: uuid(1), email: "ann@example.com", origin: .record), confirm: said("ann@example.com", "Other Org"))
    if case .wrongAccount(let a, _)? = d.waitEnd() { check("…the record agreeing names the other seat's id: wrong account", a.accountID == uuid(9), "\(a)") }
    else { check("same-address seat, record agreeing", false, "\(String(describing: d.outcome))") }
    d.cleanUp()
}
do {
    // the record changes while the login still runs, and the word disagrees: nothing ends it (its sign-in isn't written yet)
    let c = Case("running", login: ["login": "hang"])
    c.start(wanted: wantedID(uuid(1)), confirm: said("ann@example.com"))
    let login = c.waitLogin()
    c.record("bob@example.com", uuid(2))
    spin(2)
    check("a login still running is never ended on the word and the record disagreeing", c.outcome == nil && pidAlive(login), "\(String(describing: c.outcome))")
    c.signIn.stop(); c.waitEnd()
    c.cleanUp()
    // …but when the word and the record agree on another account, it ends at once: the wrong account
    let d = Case("running2", login: ["login": "hang"])
    d.start(wanted: wantedID(uuid(1)), confirm: said("bob@example.com"))
    let login2 = d.waitLogin()
    d.record("bob@example.com", uuid(2))
    if case .wrongAccount(let a, _)? = d.waitEnd() { check("…the word and the record agreeing on another account: wrong account early", a.accountID == uuid(2), "\(a)") }
    else { check("early wrong account", false, "\(String(describing: d.outcome))") }
    check("…and its login is ended", spin(until: { !pidAlive(login2) }, max: 5))
    d.cleanUp()
}
do {
    // the word blocks for long: Stop doesn't wait for it, and its late answer is dropped
    let c = Case("slowword", login: ["login": "ok", "email": "ann@example.com", "uuid": uuid(1), "org": uuid(51), "orgName": "Sample Org"])
    let gate = DispatchSemaphore(value: 0)
    c.start(wanted: wantedID(uuid(1)), confirm: { _ in _ = gate.wait(timeout: .now() + 20); return SignedInAccount.process(["email": "ann@example.com"]) })
    spin(until: { fm.fileExists(atPath: c.work.appendingPathComponent("sign-in.status").path) }, max: 10)
    spin(0.5)
    let t = Date()
    c.signIn.stop()
    check("a word that blocks: Stop ends it at once (stopped)", c.waitEnd(5) == .stopped && Date().timeIntervalSince(t) < 4, "\(String(describing: c.outcome))")
    gate.signal(); spin(0.5)
    check("…and the word's late answer changes nothing", c.outcome == .stopped)
    c.cleanUp()
}
do {
    let c = Case("nostart", login: ["login": "hang"])
    c.terminal.neverStarts = true
    c.start(wanted: wantedID(uuid(1)), startGrace: 1)
    check("Terminal never started the script: failed, not opened", c.waitEnd() == .failed(.notOpened), "\(String(describing: c.outcome))")
    let left = ((try? fm.contentsOfDirectory(atPath: c.work.path)) ?? []).filter { $0.hasSuffix(".command") }
    check("…and its script is gone (a late Terminal finds nothing to run)", left.isEmpty, "\(left)")
    check("…and the profile Terminal kept for the window it never ran is gone too", spin(until: { prefs.left(in: c.work).isEmpty }, max: 4), "\(prefs.names)")
}
do {
    let c = Case("quit", login: ["login": "hang"])
    c.start(wanted: wantedID(uuid(1)))
    let login = c.waitLogin()
    spin(until: { fm.fileExists(atPath: c.work.appendingPathComponent("sign-in.pid").path) }, max: 5)
    check("quit: Terminal holds the window's profile while it is open", prefs.left(in: c.work).count == 1, "\(prefs.names)")
    c.signIn.stopNow()
    check("quit mid-sign-in (stopNow): the login is ended before it returns", !pidAlive(login))
    check("quit: …and Terminal's kept profile is gone before it returns too", prefs.left(in: c.work).isEmpty, "\(prefs.names)")
    check("…and the window's shell ends cleanly", c.shellEnded(3) == 0)
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
    check("wrong account: Terminal's kept profile is gone", spin(until: { prefs.left(in: c.work).isEmpty }, max: 4), "\(prefs.names)")
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
    check("declined: …and its profile stays with it (nothing is taken from an open window)", prefs.left(in: c.work).count == 1, "\(prefs.names)")
    c.signIn.stop()
    check("declined: stop then closes it (a clean end)", c.shellEnded() == 0)
    check("declined: …and Terminal's kept profile goes with the closed window", spin(until: { prefs.left(in: c.work).isEmpty }, max: 4), "\(prefs.names)")
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
    check("failed: …and its profile goes at that start (the next one's own is the only one left)",
          spin(until: { prefs.left(in: n.work).count == 1 }, max: 8) && prefs.names.contains("Sample app sign-in") && !prefs.names.contains("Sample app sign-in 1"), "\(prefs.names)")
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
    check("timed out: Terminal's kept profile is gone", spin(until: { prefs.left(in: c.work).isEmpty }, max: 4), "\(prefs.names)")
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
    check("…the hung-up login is gone, and no status was written", !pidAlive(login)
          && !fm.fileExists(atPath: c.work.appendingPathComponent("sign-in.status").path))
    c.cleanUp()
}

// ── Terminal's kept profiles: when they are swept, and what is never touched ─────────────────────────────
do {
    // the tool alone: only the exact command a sign-in writes (exec + the quoted script of the folder); never the default or
    // startup profile; a command that merely mentions the folder stays; no write for nothing
    let t = FakePrefs()
    let dir = "/sample/app's/work", quoted = SignInScript.q(dir + "/sign-in-12345678.command")
    t.put("mine", command: "exec \(quoted)")
    t.put("mine upper", command: "exec " + SignInScript.q(dir + "/sign-in-ABCDEF01.command"))
    t.put("mine startup", command: "exec \(quoted)", inUse: true)
    t.put("plain", command: "exec \(dir)/sign-in-12345678.command")
    t.put("mentions", command: "cd \(SignInScript.q(dir + "/")); ls")
    t.put("mentions the script", command: "exec \(quoted); ls")
    t.put("a url", command: "open \(SignInScript.q("https://example.com" + dir + "/"))")
    t.put("short hex", command: "exec " + SignInScript.q(dir + "/sign-in-1234567.command"))
    t.put("not hex", command: "exec " + SignInScript.q(dir + "/sign-in-1234567g.command"))
    t.put("a subfolder", command: "exec " + SignInScript.q(dir + "/sub/sign-in-12345678.command"))
    t.put("other", command: "exec '/sample/other/sign-in-12345678.command'")
    t.put("sibling", command: "exec '\(dir)-2/sign-in-12345678.command'")
    t.put("no command", command: "")
    let gone = t.tool.remove(commandsRunningIn: dir)
    check("profiles tool: removes only the profiles whose command is the folder's sign-in script (quoted, an apostrophe in the folder, any hex case)",
          gone == ["mine", "mine upper"] && t.names == ["a url", "mentions", "mentions the script", "mine startup", "no command", "not hex", "other", "plain",
                                                       "short hex", "sibling", "a subfolder"].sorted(), "\(gone) \(t.names)")
    check("profiles tool: a profile that merely mentions the folder, or the plain form, is kept", t.names.contains("mentions") && t.names.contains("plain")
          && t.names.contains("mentions the script") && t.names.contains("a url"))
    check("profiles tool: a default or startup profile stays, though its command matches", t.names.contains("mine startup"))
    check("profiles tool: one write; a second run finds nothing and writes nothing", t.tool.remove(commandsRunningIn: dir).isEmpty && t.writes == 1, "\(t.writes)")
    check("profiles tool: an empty folder matches nothing", t.tool.remove(commandsRunningIn: "").isEmpty && t.writes == 1)
    // a folder that isn't absolute or is too short removes nothing, though a command has that very shape
    let w = FakePrefs()
    for f in ["/", "/sample", "/sample/work", "sample/app/work", "~/app/work"] {
        w.put("p" + f, command: "exec " + SignInScript.q(f + "/sign-in-12345678.command"))
        w.put("url" + f, command: "open https://example.com/x/")
    }
    let before = w.names
    check("profiles tool: \"/\", a short or a relative folder remove nothing and write nothing",
          ["/", "/sample", "/sample/work", "sample/app/work", "~/app/work"].allSatisfy { w.tool.remove(commandsRunningIn: $0).isEmpty }
          && w.writes == 0 && w.names == before, "\(w.writes)")
    check("profiles tool: three components is enough", w.tool.remove(commandsRunningIn: "/sample/app/work").isEmpty && w.writes == 0)
    t.readable = false
    check("profiles tool: preferences that can't be read: nothing removed, nothing written", t.tool.remove(commandsRunningIn: "/sample/app/work") == [] && t.writes == 1)
    // Terminal's own write between the read and ours is kept: the profiles are read again and only the chosen names go
    let racing = FakePrefs()
    racing.put("mine", command: "exec " + SignInScript.q("/sample/app/work/sign-in-12345678.command"))
    racing.put("changed", command: "exec " + SignInScript.q("/sample/app/work/sign-in-87654321.command"))
    var seen = 0, written: [String: Any] = [:]
    let inner = racing.tool
    let live = TerminalProfiles(read: {
        seen += 1
        let r = inner.read()
        if seen == 1 {                       // Terminal's own write, after our first read
            racing.put("new by Terminal", command: "/bin/zsh -l")
            racing.put("changed", command: "/bin/zsh -l")
        }
        return r
    }, write: { written = $0; inner.write($0) })
    let removed = live.remove(commandsRunningIn: "/sample/app/work")
    check("profiles tool: read again before the write: a profile Terminal changed is kept, one it added is in the copy written",
          removed == ["mine"] && Set(written.keys) == ["changed", "new by Terminal"] && seen == 2, "\(removed) \(written.keys.sorted()) \(seen)")
}
do {
    // a sign-in sweeps at its start and at each end; unreadable preferences never stop one
    prefs.reset()
    let c = Case("sweeps", login: ["login": "hang"])
    c.start(wanted: wantedID(uuid(1)), lateSweep: 2)          // the late sweep comes 2 s after the end: time to put the profile in first
    spin(until: { c.states.contains(.waitingForBrowser) })
    check("profiles: swept at the start", prefs.reads >= 1, "\(prefs.reads)")
    let atStart = prefs.writes
    c.signIn.stop(); c.waitEnd()
    // the stop's own sweep took the profile Terminal kept for the window (a write); it has run by the time the outcome came
    check("profiles: swept at the end (stopped): the window's kept profile is taken at once", prefs.writes == atStart + 1 && prefs.left(in: c.work).isEmpty,
          "\(prefs.writes) \(atStart) \(prefs.names)")
    // a read can't tell the late sweep from the first one (a sweep that finds something reads twice), so a profile that only
    // turns up after the stop's sweep must go in the late one: one more write, nobody else sweeping
    prefs.put("Sample app sign-in late", command: "exec " + SignInScript.q(c.work.path + "/sign-in-12345678.command"))
    check("profiles: …and once more after the window had closed itself (the late sweep takes what came after the first)",
          spin(until: { prefs.writes == atStart + 2 }, max: 6) && prefs.left(in: c.work).isEmpty, "\(prefs.writes) \(atStart) \(prefs.names)")
    c.cleanUp()
    // a refused start (the folder isn't there) sweeps at its start and at its end too
    prefs.reset()
    let m = Case("sweeps-missing", login: ["login": "ok"], make: false)
    m.start(wanted: nil)
    check("profiles: a start that is refused is swept at its start and at its end", m.waitEnd() == .failed(.folderNotReady) && prefs.reads >= 2, "\(prefs.reads)")
    // unreadable preferences
    prefs.reset(); prefs.readable = false
    let u = Case("sweeps-unreadable", login: ["login": "ok", "email": "ann@example.com", "uuid": uuid(1), "org": uuid(51), "orgName": "Sample Org"])
    u.start(wanted: wantedID(uuid(1)), confirm: said("ann@example.com"))
    if case .signedIn? = u.waitEnd() { check("profiles: Terminal's preferences unreadable: the sign-in goes on, nothing written", prefs.writes == 0, "\(prefs.writes)") }
    else { check("profiles: unreadable preferences", false, "\(String(describing: u.outcome))") }
    u.cleanUp()
    prefs.reset()
}
do {
    // the static sweep's pid-file guard, alone (the only guard at start-up, when no sign-in of this run is `current`): a window
    // of an earlier run, its script's pid in the work folder's sign-in.pid and the script in its command line, keeps its
    // profile. The work folder is one no sign-in of this run has used, so what the process's own last sign-in knows
    // about its window can't be what holds it. Its own Terminal-preferences stand-in: an earlier block's late sweep, on the
    // shared one, can't be counted as a read here.
    let mine = FakePrefs()
    let earlier = base.appendingPathComponent("earlier-run/work")
    try? fm.createDirectory(at: earlier, withIntermediateDirectories: true)
    let script = earlier.appendingPathComponent("sign-in-abcdef01.command").path
    func shell(_ named: String) -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "trap 'exit 0' TERM HUP; while :; do sleep 0.1; done", "stand-in", named]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try? p.run()
        spin(until: { ProcessTable.launch(of: p.processIdentifier)?.args.contains(named) == true }, max: 3)
        return p
    }
    func names(_ p: Process) { try? "\(p.processIdentifier)\n".write(to: earlier.appendingPathComponent("sign-in.pid"), atomically: true, encoding: .utf8) }
    func put() { mine.reset(); mine.put("Sample app sign-in", command: "exec " + SignInScript.q(script)) }
    let standIn = mine.tool
    func sweep() { ClaudeSignIn.sweep(work: earlier, terminalProfiles: standIn) }
    let open = shell(script)
    names(open)
    put(); sweep()
    check("sweep: a script of the work folder still running from an earlier run keeps its profile (the pid file alone)",
          mine.names == ["Sample app sign-in"] && mine.reads == 0, "\(mine.names) \(mine.reads)")
    // …a pid that runs something else (the pid was reused) doesn't: the command line must name the script
    let other = shell("/not/the/work/sign-in-abcdef01.command")
    names(other); put(); sweep()
    check("sweep: a pid that runs something else holds nothing", mine.names.isEmpty, "\(mine.names)")
    // …and the window gone (its shell ended), the profile goes
    names(open); put()
    open.terminate(); open.waitUntilExit()
    sweep()
    check("sweep: the earlier run's window gone, its profile goes", mine.names.isEmpty, "\(mine.names)")
    other.terminate(); other.waitUntilExit()
}
/// A window's shell that ignores TERM (and the TERM its children get), ends cleanly on HUP (Terminal's hang-up), and has
/// declined its sign-in: the window stays open to be read, as a real declined one does.
func deafShell(_ c: Case) -> String {
    "trap '' TERM; trap 'exit 0' HUP; printf '%s\\n' $$ > '\(c.work.path)/sign-in.pid'; : > '\(c.work.path)/sign-in.declined'; "
        + "while :; do (trap - TERM; exec sleep 0.1); done"
}
/// Waits for whatever the sign-in's queue still does (a stop's wait for the shell): the static sweep takes that queue, and
/// is handed a Terminal stand-in with nothing in it.
func settle(_ work: URL) { ClaudeSignIn.sweep(work: work, terminalProfiles: FakePrefs().tool) }
do {
    // stopping an ended window whose shell doesn't end when asked: the profile stays; once the shell dies, a stop takes it
    prefs.reset()
    let c = Case("deaf", login: ["login": "hang"])
    c.terminal.shellBody = deafShell(c)
    c.start(wanted: wantedID(uuid(1)))
    check("deaf shell: its sign-in is declined, the window left open to be read", c.waitEnd() == .declined && c.shellRunning, "\(String(describing: c.outcome))")
    c.signIn.stop()
    settle(c.work)                                       // the stop has waited out its 3 s (and the 1 s after the kill)
    check("deaf shell: stopped, the shell is still there (TERM ignored; it is never killed)", c.shellRunning)
    check("deaf shell: …and its profile stays with the window still open", prefs.left(in: c.work).count == 1, "\(prefs.names)")
    if let s = c.terminal.last { kill(s.processIdentifier, SIGHUP) }
    check("deaf shell: the hang-up ends it cleanly", c.shellEnded() == 0)
    c.signIn.stop()
    check("deaf shell: …and a stop once it is gone takes its profile", spin(until: { prefs.left(in: c.work).isEmpty }, max: 4), "\(prefs.names)")
    c.cleanUp()
}
do {
    // a new sign-in's start while the earlier window's shell outlives the start's wait (it ignores TERM): one window per app, so
    // the start is refused (already signing in), and the earlier window keeps its pid file (its only handle) and its profile
    // through every later sweep
    prefs.reset()
    let d = Case("deaf-earlier", login: ["login": "hang"])
    d.terminal.shellBody = deafShell(d)
    d.start(wanted: wantedID(uuid(1)))
    check("deaf shell: its sign-in is declined, the window left open", d.waitEnd() == .declined && d.shellRunning, "\(String(describing: d.outcome))")
    let pidFile = d.work.appendingPathComponent("sign-in.pid")
    let pidBefore = try? String(contentsOf: pidFile, encoding: .utf8)
    let n = Case("deaf-next", login: ["login": "hang"])
    n.start(wanted: wantedID(uuid(1)))
    check("start: the earlier window's shell outlived the start's wait: refused, already signing in, no window of its own",
          n.waitEnd(25) == .failed(.alreadySigningIn) && n.terminal.count == 0, "\(String(describing: n.outcome)) \(n.terminal.count)")
    check("start: …the earlier window's shell is still there, its pid file untouched and its profile kept",
          d.shellRunning && pidBefore != nil && (try? String(contentsOf: pidFile, encoding: .utf8)) == pidBefore && prefs.left(in: d.work).count == 1,
          "\(d.shellRunning) \(String(describing: pidBefore)) \(prefs.names)")
    // the refused start's own end, its stop, and the start-up or quit sweep: none takes an open window's profile
    n.signIn.stop()
    let tool = prefs.tool
    ClaudeSignIn.sweep(work: d.work, terminalProfiles: tool)                       // after the stop on the queue
    spin(0.5)
    check("start: …and the later sweeps (its end, its stop, the static one) leave it", d.shellRunning && prefs.left(in: d.work).count == 1, "\(d.shellRunning) \(prefs.names)")
    d.cleanUp(); n.cleanUp()
    prefs.reset()
}
do {
    // the start-up sweep reads nothing of Terminal's for someone who never signed in (no sign-in work folder)
    // (its own Terminal-preferences stand-in: another block's late sweep on the shared one can't count as a read)
    let mine = FakePrefs()
    let never = base.appendingPathComponent("never-signed-in/work")
    mine.put("Sample app sign-in", command: "exec " + SignInScript.q(never.path + "/sign-in-12345678.command"))
    let standIn = mine.tool
    AccountSwitcher.sweepWork(never, terminalProfiles: standIn)
    check("start-up sweep: no sign-in work folder: Terminal's preferences aren't read, nothing is taken", mine.reads == 0 && mine.names == ["Sample app sign-in"],
          "\(mine.reads) \(mine.names)")
    try? fm.createDirectory(at: never, withIntermediateDirectories: true)
    AccountSwitcher.sweepWork(never, terminalProfiles: standIn)
    check("start-up sweep: …with the folder there, what an earlier run left is taken", mine.names.isEmpty, "\(mine.names)")
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
    // a bare login run by a platform binary (the bash stand-in): the kernel gives no environment for it and there is no
    // ClaudeSignIn script above it, so its folder can't be told: it refuses rather than guesses (any folder)
    let bare = otherLogin(c, viaScript: false)
    check("the bash stand-in's environment isn't readable (a platform binary)",
          ProcessTable.launch(of: bare.login).map { !$0.environmentRead } == true)
    let e = Case("guard-bare", login: ["login": "hang"])
    e.start(wanted: wantedID(uuid(1)))
    check("process guard: a login whose folder can't be told: refused", e.waitEnd() == .failed(.alreadySigningIn), "\(String(describing: e.outcome))")
    endOther(bare)
    c.cleanUp(); d.cleanUp(); e.cleanUp()
}
// the environment branch: an ad-hoc built stand-in `claude` (not a platform binary: the kernel gives its environment), started
// bare with CLAUDE_CONFIG_DIR as given
do {
    let adhoc = env["QC_SIGNIN_ADHOC"] ?? ""
    check("the ad-hoc stand-in claude is there", fm.isExecutableFile(atPath: adhoc), adhoc)
    func bareLogin(_ dir: String?) -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: adhoc); p.arguments = ["auth", "login", "--claudeai"]
        var e = ["PATH": "/usr/bin:/bin", "HOME": home.path]
        if let dir { e["CLAUDE_CONFIG_DIR"] = dir }
        p.environment = e
        try? p.run()
        spin(until: { ProcessTable.launch(of: p.processIdentifier) != nil }, max: 3)
        return p
    }
    func attempt(_ name: String) -> ClaudeSignIn.Outcome? {
        let c = Case(name, login: ["login": "hang"])
        c.start(wanted: wantedID(uuid(1)))
        spin(until: { c.states.contains(.waitingForBrowser) || c.outcome != nil })
        let o = c.outcome
        if o == nil { c.signIn.stop(); c.waitEnd() }
        c.cleanUp()
        return o
    }
    let target = home.appendingPathComponent(".claude-env-same")
    let same = bareLogin(target.path)
    let l = ProcessTable.launch(of: same.processIdentifier)
    check("the ad-hoc stand-in's environment is read: its CLAUDE_CONFIG_DIR", l?.environmentRead == true && l?.configDir == target.path,
          "\(String(describing: l))")
    check("environment: a login on this folder (by its CLAUDE_CONFIG_DIR): refused", attempt("env-same") == .failed(.alreadySigningIn))
    check("environment: …another folder's isn't", attempt("env-other") == nil)
    same.terminate(); same.waitUntilExit()
    for (what, dir) in [("relative", "rel/.claude-x"), ("empty", ""), ("~-led", "~/.claude-env-same")] {
        let p = bareLogin(dir)
        check("environment: a CLAUDE_CONFIG_DIR that can't be told (\(what)): refused for any folder", attempt("env-\(what)") == .failed(.alreadySigningIn))
        p.terminate(); p.waitUntilExit()
    }
    let unset = bareLogin(nil)
    check("environment: CLAUDE_CONFIG_DIR unset is the default folder: another folder isn't refused", attempt("env-unset") == nil)
    unset.terminate(); unset.waitUntilExit()
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
    let s = ClaudeSignIn(folder: g.authFolder, wanted: nil, tools: t, claude: claude, confirm: { _ in nil }, work: g.work,
                         terminalProfiles: prefs.tool, lateSweep: 0.3, locks: locks, poll: 0.2)
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
    var switchGrace: TimeInterval = 10
    sw.onOutcome = { _, o in outcomes.append(o) }
    sw.findClaude = { claude }
    sw.makeSignIn = { folder, wanted, cl in
        var t = last.tools()
        t.mayLaunch = { _, f in f.isReady }
        return ClaudeSignIn(folder: AuthFolder(path: folder, isDefault: false, home: home.path), wanted: wanted, timeout: 3, tools: t, claude: cl,
                            confirm: SignInWord.confirm(claude: cl, workFolder: base.appendingPathComponent("confirm/work").path),
                            work: last.work, startGrace: switchGrace, terminalProfiles: prefs.tool, lateSweep: 0.3, locks: locks, poll: 0.2)
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
    check("switch: another account is the wrong-account note (bob signed in, in use nowhere else)",
          run(wrong, uuid: uuid(7), email: "kim@example.com") == .ended(.wrongAccount(signedIn: "bob@example.com", alsoOn: nil))
          && sw.ended[wrong.name]?.signedIn == "bob@example.com", "\(outcomes) \(String(describing: sw.ended[wrong.name]))")
    // …and when that account is also in use on another profile, the note says which
    let elsewhere = Case("sw-elsewhere", login: ["login": "hang"])
    elsewhere.record("bob@example.com", uuid(8))
    ProfileStore.shared.save([profile(ok), profile(elsewhere)])
    let wrong2 = Case("sw-wrong2", login: ["login": "ok", "email": "bob@example.com", "uuid": uuid(8), "org": uuid(51), "orgName": "Sample Org"])
    wrong2.record("ann@example.com", uuid(1))
    check("switch: the account that signed in is also in use on another profile: the note names it",
          run(wrong2, uuid: uuid(7), email: "kim@example.com") == .ended(.wrongAccount(signedIn: "bob@example.com", alsoOn: "sw-elsewhere")), "\(outcomes)")
    check("switch: its words say so, the addresses apart from them (blurred)", {
        guard let e = sw.ended[wrong2.name] else { return false }
        let w = SwitchWords.ended(e)
        return w.rest.spoken.hasSuffix(" \(maskEmail("bob@example.com")) is also in use on sw-elsewhere.") && w.rest.addresses == ["bob@example.com", "bob@example.com"]
    }(), "\(String(describing: sw.ended[wrong2.name]))")
    ProfileStore.shared.save([profile(ok)])

    // "Try again as A" after a wrong account: the same account wanted (its id and address), begun from the folder as it is now,
    // on B, so a switch to A, never a sign-in again; nothing while one is waited for; "Keep B" (drop) clears the note and the
    // folder stays on B
    sw.tryAgain(profile(ok), origin: .chat)
    check("retry: with no ended switch for the profile, nothing begins", sw.waiting[ok.name] == nil && ok.terminal.count == 1)
    check("retry: the note was for A (kim) and the folder is on B (bob)", sw.ended[wrong.name]?.goal.wantedEmail == "kim@example.com"
          && ClaudeFolder.account(wrong.folder.path)?.email == "bob@example.com")
    last = wrong
    let outcomesBeforeRetry = outcomes.count, opensBeforeRetry = wrong.terminal.count
    sw.tryAgain(profile(wrong), origin: .chat)
    let retried = sw.waiting[wrong.name]
    sw.tryAgain(profile(wrong), origin: .chat)            // pressed again while it waits: nothing more
    check("retry: begins with the goal's id and address, from the folder's account now (B): a switch, not a sign-in again",
          retried?.wantedUUID == uuid(7) && retried?.wantedEmail == "kim@example.com" && retried?.fromEmail == "bob@example.com"
          && retried?.again == false && retried?.origin == .chat && sw.ended[wrong.name] == nil, "\(String(describing: retried))")
    spin(until: { outcomes.count > outcomesBeforeRetry }, max: 20)
    check("retry: …one sign-in opened, not two, and it ended on bob again (the wrong account)", outcomes.count == outcomesBeforeRetry + 1
          && outcomes.last == .ended(.wrongAccount(signedIn: "bob@example.com", alsoOn: nil)) && wrong.terminal.count == opensBeforeRetry + 1, "\(outcomes) \(wrong.terminal.count)")
    sw.drop(wrong.name)                                    // "Keep B"
    check("keep: the note goes, nothing waits, and the folder stays on B", sw.ended[wrong.name] == nil && sw.waiting[wrong.name] == nil
          && ClaudeFolder.account(wrong.folder.path)?.email == "bob@example.com")
    // a wrong account after a sign-in again: Try again as A is a switch from B
    let againWrong = Case("sw-againwrong", login: ["login": "ok", "email": "bob@example.com", "uuid": uuid(8), "org": uuid(51), "orgName": "Sample Org"])
    againWrong.record("kim@example.com", uuid(7))
    last = againWrong
    let beforeAgain = outcomes.count
    sw.signInAgain(profile(againWrong), origin: .chat)
    let againGoal = sw.waiting[againWrong.name]
    spin(until: { outcomes.count > beforeAgain }, max: 20)
    check("retry: a sign-in again that ended on another account is a wrong account (the goal was a sign-in again)",
          againGoal?.again == true && outcomes.last == .ended(.wrongAccount(signedIn: "bob@example.com", alsoOn: nil)) && sw.ended[againWrong.name]?.goal.again == true,
          "\(String(describing: againGoal)) \(outcomes)")
    sw.tryAgain(profile(againWrong), origin: .settings)
    check("retry: …Try again as A then begins a switch from B (not a sign-in again), as Settings asks",
          sw.waiting[againWrong.name].map { $0.again == false && $0.wantedEmail == "kim@example.com" && $0.fromEmail == "bob@example.com" && $0.origin == .settings } == true,
          "\(String(describing: sw.waiting[againWrong.name]))")
    sw.drop(againWrong.name)
    spin(until: { sw.active == nil }, max: 5)
    againWrong.cleanUp()

    let none = Case("sw-none", login: ["login": "hang"])
    none.record("ann@example.com", uuid(1))
    check("switch: no sign-in is the timeout's note", run(none, uuid: uuid(7), email: "kim@example.com") == .ended(.timedOut)
          && sw.ended[none.name] != nil && sw.ended[none.name]?.signedIn == nil)
    check("switch: …and its login is ended", spin(until: { !pidAlive(none.loginPid) }, max: 5))

    let declined = Case("sw-declined", login: ["login": "declined"])
    declined.record("ann@example.com", uuid(1))
    check("switch: a declined sign-in has its own note, at once (not the timeout's)",
          run(declined, uuid: uuid(7), email: "kim@example.com") == .ended(.declined) && sw.ended[declined.name]?.signedIn == nil
          && sw.ended[declined.name].map { SwitchWords.ended($0).lead.spoken != SwitchWords.ended(SwitchEnded(goal: $0.goal, reason: .timedOut)).lead.spoken } == true)

    let failedLogin = Case("sw-failed", login: ["login": "fail"])
    failedLogin.record("ann@example.com", uuid(1))
    check("switch: a login that fails says so (its status), not \"hasn't changed\"",
          run(failedLogin, uuid: uuid(7), email: "kim@example.com") == .ended(.failed(.loginFailed(status: 2)))
          && sw.ended[failedLogin.name].map { SwitchWords.ended($0).lead.spoken + SwitchWords.ended($0).rest.spoken } == "Claude Code's sign-in failed. It ended with an error (status 2); its Terminal window shows why.")

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

    // Terminal opens the sign-in but never runs it: the "couldn't start" alert (not the account-unchanged note), and the
    // sign-in that had opened is over for the caller too
    let nostart = Case("sw-nostart", login: ["login": "hang"])
    nostart.terminal.neverStarts = true
    nostart.record("ann@example.com", uuid(1))
    last = nostart
    switchGrace = 1
    let toldBefore = told.count, outcomesBefore = outcomes.count
    sw.begin(profile(nostart), uuid: uuid(7), email: "kim@example.com", origin: .settings)
    spin(until: { told.count > toldBefore }, max: 10)
    spin(0.5)
    switchGrace = 10
    check("switch: a window Terminal never ran is the \"couldn't start\" alert, with its own line",
          told.count == toldBefore + 1 && told.last == "Terminal didn't open the sign-in. Try again.", "\(told)")
    check("switch: …and no note is left (not \"hasn't changed\"), nothing waits", sw.waiting[nostart.name] == nil && sw.ended[nostart.name] == nil
          && outcomes.count == outcomesBefore, "\(outcomes)")
    // every way a sign-in fails has its own plain line
    let failures: [ClaudeSignIn.Failure] = [.folderNotReady, .locked, .alreadySigningIn, .processesUnreadable, .notOpened,
                                            .loginFailed(status: 2), .noAccount, .windowClosed]
    let lines = failures.map { SignInWords.failure($0, folder: "~/.claude-x") }
    check("failures: each has a line of its own, none the generic one", Set(lines.map(\.lead)).count == failures.count
          && lines.allSatisfy { !($0.lead + $0.rest).contains("hasn't changed") && !$0.lead.isEmpty && !$0.rest.isEmpty }, "\(lines)")
    check("failures: the ones that stop a start are alerts, in the same words as the lines; the others are notes",
          failures.prefix(5).allSatisfy { AccountSwitcher.why($0, folder: "~/.claude-x") == SignInWords.failure($0, folder: "~/.claude-x").lead + " " + SignInWords.failure($0, folder: "~/.claude-x").rest }
          && failures.suffix(3).allSatisfy { AccountSwitcher.why($0, folder: "~/.claude-x") == nil })
    check("failures: the lines", lines.map { $0.lead + " " + $0.rest } == [
        "~/.claude-x isn't there as a plain folder. cl_quick didn't open a sign-in.",
        "Another sign-in for ~/.claude-x is starting. Wait a moment, then try again.",
        "Claude Code's sign-in is already open for ~/.claude-x. Finish it, or close its Terminal window, then try again.",
        "cl_quick couldn't tell whether Claude Code's sign-in is already open for ~/.claude-x. It didn't open one. Try again.",
        "Terminal didn't open the sign-in. Try again.",
        "Claude Code's sign-in failed. It ended with an error (status 2); its Terminal window shows why.",
        "The sign-in ended, but no account is signed in to this folder. Try again.",
        "The Terminal window was closed before the sign-in ended. Try again."], "\(lines)")

    // Claude Code doesn't confirm the account (its `initialize` names nobody): not reached, the account-unchanged note
    try? "account=none\n".write(to: base.appendingPathComponent("confirm/stub.conf"), atomically: true, encoding: .utf8)
    let unconfirmed = Case("sw-unconfirmed", login: ["login": "ok", "email": "kim@example.com", "uuid": uuid(7), "org": uuid(51), "orgName": "Sample Org"])
    unconfirmed.record("ann@example.com", uuid(1))
    check("switch: a sign-in Claude Code never confirmed is not reached, and has its own line (the folder may have changed)",
          run(unconfirmed, uuid: uuid(7), email: "kim@example.com") == .ended(.unverified) && sw.ended[unconfirmed.name]?.signedIn == nil
          && sw.ended[unconfirmed.name].map { SwitchWords.ended($0).lead.spoken + SwitchWords.ended($0).rest.spoken }
              == "Signed in, but Claude Code didn't confirm which account. Check the account line in the menu.", "\(outcomes)")
    try? "".write(to: base.appendingPathComponent("confirm/stub.conf"), atomically: true, encoding: .utf8)

    // Stop while claude is still looked for: nothing starts afterwards
    let early = Case("sw-early", login: ["login": "hang"])
    last = early
    sw.findClaude = { usleep(800_000); return claude }
    sw.begin(profile(early), uuid: uuid(7), email: "kim@example.com", origin: .settings)
    sw.drop(early.name)
    spin(2)
    check("switch: Stop before the sign-in started: none starts afterwards", early.terminal.count == 0 && sw.active == nil && sw.waiting[early.name] == nil)
    sw.findClaude = { claude }

    // a sign-in on another profile ends this one, and this one's note says so (the account-unchanged note), never silently
    let first = Case("sw-first", login: ["login": "hang"])
    first.record("ann@example.com", uuid(1))
    last = first
    sw.begin(profile(first), uuid: uuid(7), email: "kim@example.com", origin: .settings)
    let firstLogin = first.waitLogin()
    let second = Case("sw-second", login: ["login": "hang"])
    last = second
    sw.begin(profile(second), uuid: uuid(7), email: "kim@example.com", origin: .settings)
    spin(until: { sw.ended[first.name] != nil }, max: 10)
    check("switch: another profile's sign-in ends this one with its own note, not silently",
          sw.waiting[first.name] == nil && sw.ended[first.name]?.reason == .replaced && !pidAlive(firstLogin))
    spin(until: { second.states.contains(.waitingForBrowser) }, max: 10)
    // stop(folder:) finds the sign-in however the folder is spelled
    let secondLogin = second.waitLogin()
    sw.stop(folder: second.folder.path + "/")
    check("switch: stop(folder:) with another spelling of the folder ends it", spin(until: { !pidAlive(secondLogin) }, max: 5) && sw.active == nil)
    check("switch: two spellings of one folder are one", AccountSwitcher.sameFolder(second.folder.path, second.folder.path + "/./")
          && !AccountSwitcher.sameFolder(second.folder.path, first.folder.path))
    sw.drop(second.name)

    // a declined window left open and closed by hand later, with no sign-in after it: nothing but the sweep at quit (and at
    // start) takes its profile. Terminal's preferences are the stand-in's; the sweep is handed them, never the real ones.
    prefs.reset()
    sw.drop(first.name); sw.drop(second.name)
    spin(until: { sw.active == nil }, max: 5)
    let lateWork = declined.work
    var sweeps = 0
    let standIn = prefs.tool
    func sweepNow() { ClaudeSignIn.sweep(work: lateWork, terminalProfiles: standIn) }
    AccountSwitcher.sweepLeftovers = { sweeps += 1; sweepNow() }
    let left = Case("sw-left", login: ["login": "declined"])
    left.record("ann@example.com", uuid(1))
    check("switch: a declined sign-in's window is left open to be read", run(left, uuid: uuid(7), email: "kim@example.com") == .ended(.declined) && left.shellRunning)
    sw.drop(left.name)
    check("sweep: while that window is open its profile stays (the static sweep leaves a window in use alone)",
          { sweepNow(); return !prefs.left(in: lateWork).isEmpty }(), "\(prefs.names)")
    if let s = left.terminal.last { kill(s.processIdentifier, SIGKILL) }          // closed by hand
    check("sweep: …and closed by hand, with no sign-in after it, it stays until a sweep comes", spin(until: { !left.shellRunning }, max: 5)
          && { spin(1); return !prefs.left(in: lateWork).isEmpty }(), "\(prefs.names)")
    sw.stopForQuit()
    check("sweep: quitting sweeps it (stopForQuit, though no sign-in is under way)", sweeps == 1 && prefs.left(in: lateWork).isEmpty, "\(sweeps) \(prefs.names)")
    // not while a sign-in runs
    let running = Case("sw-running", login: ["login": "hang"])
    running.record("ann@example.com", uuid(1))
    last = running
    sw.begin(profile(running), uuid: uuid(7), email: "kim@example.com", origin: .settings)
    spin(until: { running.states.contains(.waitingForBrowser) || !prefs.left(in: lateWork).isEmpty }, max: 10)
    _ = running.waitLogin()
    sweepNow()
    check("sweep: a sign-in under way keeps its profile", !prefs.left(in: lateWork).isEmpty, "\(prefs.names)")
    sw.drop(running.name)
    spin(until: { prefs.left(in: lateWork).isEmpty }, max: 5)
    AccountSwitcher.sweepLeftovers = {}
    for c in [ok, wrong, wrong2, elsewhere, none, declined, failedLogin, nostart, stop, unconfirmed, first, second, left, running] { c.cleanUp() }
}

// ── the words a switch ends on (the same in the chat and in Settings) ────────────────────────────────
do {
    func goal(again: Bool = false) -> SwitchGoal {
        SwitchGoal(profileID: "main", profileName: "Main", folder: "~/.claude", wantedUUID: uuid(7), wantedEmail: "kim@example.com",
                   fromUUID: again ? uuid(7) : uuid(1), fromEmail: "alex@example.com", origin: .settings)
    }
    func ended(_ r: SwitchEndReason, again: Bool = false) -> SwitchEnded { SwitchEnded(goal: goal(again: again), reason: r) }
    func line(_ e: SwitchEnded) -> String { let w = SwitchWords.ended(e); return w.lead.spoken + w.rest.spoken }
    let b = maskEmail("bob@example.com"), k = maskEmail("kim@example.com")
    check("words: a wrong account says the browser was signed in as B, not A, and Main is on B now",
          line(ended(.wrongAccount(signedIn: "bob@example.com", alsoOn: nil))) == "The browser was signed in as \(b), not \(k). Main is on \(b) now.")
    check("words: …and that B is also in use on the other profile, when it is",
          line(ended(.wrongAccount(signedIn: "bob@example.com", alsoOn: "Work"))) == "The browser was signed in as \(b), not \(k). Main is on \(b) now. \(b) is also in use on Work.")
    let w = SwitchWords.ended(ended(.wrongAccount(signedIn: "bob@example.com", alsoOn: "Work")))
    check("words: the addresses are pieces of their own (blurred), never in the plain words",
          w.lead.addresses == ["bob@example.com", "kim@example.com"] && w.rest.addresses == ["bob@example.com", "bob@example.com"]
          && !w.lead.pieces.filter { !$0.isAddress }.contains { $0.text.contains("@") })
    AddressPrivacy.shared.blur = false
    check("words: with Blur addresses off the words hold them in full", line(ended(.wrongAccount(signedIn: "bob@example.com", alsoOn: nil)))
          == "The browser was signed in as bob@example.com, not kim@example.com. Main is on bob@example.com now.")
    AddressPrivacy.shared.blur = true
    check("words: declined is its own note, at once", line(ended(.declined)) == "The sign-in was declined in the browser. The account in use hasn't changed.")
    check("words: a timeout says no sign-in came", line(ended(.timedOut)) == "No sign-in in 10 minutes. The account in use hasn't changed.")
    check("words: unconfirmed doesn't say the account hasn't changed (the folder may have)",
          line(ended(.unverified)) == "Signed in, but Claude Code didn't confirm which account. Check the account line in the menu."
          && !line(ended(.unverified)).contains("hasn't changed"))
    check("words: one ended by another sign-in", line(ended(.replaced)) == "Another sign-in started, so this one ended. The account in use hasn't changed.")
    check("words: a failed login, a login that ended on nobody, a window that was closed: their own lines",
          line(ended(.failed(.noAccount))) == "The sign-in ended, but no account is signed in to this folder. Try again."
          && line(ended(.failed(.windowClosed))) == "The Terminal window was closed before the sign-in ended. Try again."
          && line(ended(.failed(.loginFailed(status: 1)))).hasPrefix("Claude Code's sign-in failed."))
    let reasons: [SwitchEndReason] = [.wrongAccount(signedIn: "bob@example.com", alsoOn: nil), .timedOut, .declined, .unverified, .replaced,
                                      .failed(.loginFailed(status: 1)), .failed(.noAccount), .failed(.windowClosed)]
    check("words: every way a switch ends has a lead of its own", Set(reasons.map { SwitchWords.ended(ended($0)).lead.spoken }).count == reasons.count)
    // the waiting note: what to do in the browser, in order, the address apart from the words
    let steps = SwitchWords.steps(wanted: "kim@example.com")
    check("waiting: finish it in the browser; before Authorize check \"Logged in as\" shows the address; if not, Switch account there",
          steps.map(\.spoken) == ["Finish the sign-in in the browser.",
                                  "Before you press Authorize, check that “Logged in as” at the bottom of the page shows \(k).",
                                  "If it doesn't, use Switch account there."] && steps[1].addresses == ["kim@example.com"] && steps[0].addresses.isEmpty && steps[2].addresses.isEmpty)
    // the keys
    let wrongKeys = (SwitchWords.retry(ended(.wrongAccount(signedIn: "bob@example.com", alsoOn: nil))), SwitchWords.keep(ended(.wrongAccount(signedIn: "bob@example.com", alsoOn: nil))))
    check("keys: after a wrong account: \"Try again as A\" (the same switch) and \"Keep B\"",
          wrongKeys.0.title == "Try again as " && wrongKeys.0.address == "kim@example.com" && wrongKeys.1?.title == "Keep " && wrongKeys.1?.address == "bob@example.com")
    // B also in use on another profile: nothing to keep, so only Try again as A and the plain dismiss; the line still says so
    let alsoKeys = (SwitchWords.retry(ended(.wrongAccount(signedIn: "bob@example.com", alsoOn: "Work"))), SwitchWords.keep(ended(.wrongAccount(signedIn: "bob@example.com", alsoOn: "Work"))))
    check("keys: after a wrong account on one also in use on another profile: Try again as A, and no Keep B (the plain dismiss)",
          alsoKeys.0.title == "Try again as " && alsoKeys.0.address == "kim@example.com" && alsoKeys.1 == nil
          && line(ended(.wrongAccount(signedIn: "bob@example.com", alsoOn: "Work"))).hasSuffix("is also in use on Work."))
    check("keys: …and no Keep when nobody signed in (an empty address), as before",
          SwitchWords.keep(ended(.wrongAccount(signedIn: "", alsoOn: nil))) == nil)
    check("keys: other endings keep their one dismiss (no Keep), and retry as the account wanted",
          SwitchWords.keep(ended(.declined)) == nil && SwitchWords.retry(ended(.declined)).address == "kim@example.com")
    check("keys: a sign-in again that never came is just Sign in again; a wrong account on one is still Try again as A",
          SwitchWords.retry(ended(.timedOut, again: true)).title == "Sign in again" && SwitchWords.retry(ended(.timedOut, again: true)).address == nil
          && SwitchWords.retry(ended(.wrongAccount(signedIn: "bob@example.com", alsoOn: nil), again: true)).address == "kim@example.com")
    // "also in use on": another profile, by id or address, never the profile itself
    let main = Profile(id: "main", name: "Main", folder: "/x/main"), work = Profile(id: "work", name: "Work", folder: "/x/work")
    let onBob: (Profile) -> (uuid: String, email: String)? = { _ in (uuid(8), "Bob@Example.com") }
    let onWork: (Profile) -> (uuid: String, email: String)? = { $0.id == "work" ? onBob($0) : nil }
    check("also in use: the profile itself doesn't count",
          AccountSwitcher.profileAlsoUsing(("u", "bob@example.com"), besides: "main", profiles: [main], account: onBob) == nil)
    check("also in use: another profile on the same account (by address, in any case) is named",
          AccountSwitcher.profileAlsoUsing((uuid(9), "bob@example.com"), besides: "main", profiles: [main, work], account: onWork) == "Work")
    check("also in use: another profile on a different account isn't",
          AccountSwitcher.profileAlsoUsing((uuid(9), "carl@example.com"), besides: "main", profiles: [main, work], account: onWork) == nil)
}

// ── Settings' "signing in": an earlier sign-in's late end never takes the newer one's away ─────────────
do {
    let sw = AccountSwitcher.shared
    let c = Case("st-folder", login: ["login": "hang"])
    sw.makeSignIn = { folder, wanted, cl in
        ClaudeSignIn(folder: AuthFolder(path: folder, isDefault: false, home: home.path), wanted: wanted, timeout: 30, tools: c.tools(), claude: cl,
                     confirm: { _ in nil }, work: c.work, terminalProfiles: prefs.tool, lateSweep: 0.3, locks: locks, poll: 0.2)
    }
    let state = SettingsState()
    state.signIn(folder: c.folder.path)
    spin(until: { state.signingIn.contains(c.folder.path) }, max: 10)
    let firstLogin = c.waitLogin()
    state.signIn(folder: c.folder.path)               // a new sign-in on the same folder ends the first (stopped)
    spin(until: { !pidAlive(firstLogin) }, max: 8)
    spin(1.5)
    check("settings: the first sign-in's end doesn't take the second's \"signing in\" away", state.signingIn.contains(c.folder.path))
    sw.stop(folder: c.folder.path)
    spin(until: { !state.signingIn.contains(c.folder.path) }, max: 10)
    check("settings: …the second's own end does", !state.signingIn.contains(c.folder.path))
    c.cleanUp()
}

print(failed == 0 ? "signin checks: \(passed)/\(passed) passed" : "signin checks: \(failed) failed, \(passed) passed")
exit(failed == 0 ? 0 : 1)
