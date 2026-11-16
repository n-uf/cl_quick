// Switch: changing which account a profile is on. A profile is one Claude Code folder and the folder holds one signed-in
// account at a time, so switching is signing in again in the same folder, as another account: Claude Code's own
// `claude auth login`, in Terminal, finished in the browser, through ClaudeAuth's ClaudeSignIn (shared with cl_audit:
// Shared/ClaudeAuth+SignIn/). It opens the window, follows the folder every 2 s for at most 10 minutes, decides which
// account signed in, and closes the window after it. Every other sign-in (a signed-out folder, a folder found, a new one)
// goes through it too, one at a time. cl_quick never sees a password or a token, and never reads the Keychain: the
// account is confirmed by a short `claude` on the folder (its `initialize` answer, SignInWord), and until then the
// folder's .claude.json is only a guess.

import AppKit
import ClaudeAuth

/// A switch under way: which profile, the account wanted, and the account it was on when it began.
struct SwitchGoal: Equatable {
    enum Origin { case chat, settings }
    var profileID: String
    var profileName: String
    var folder: String
    /// The standby account's uuid; nil for an address typed in (Add an account…).
    var wantedUUID: String?
    var wantedEmail: String
    var fromUUID: String?
    var fromEmail: String?
    var origin: Origin
    var started = Date()

    /// Signing in again on the account already in use (Sign in again…): the folder's account is the same before and after,
    /// so only Claude Code's login ending well says it's done (ClaudeSignIn follows it).
    var again: Bool { fromUUID != nil && wantedUUID == fromUUID }

    /// The account wanted, for ClaudeSignIn: by its id when cl_quick knows one (not one made from the address), and its
    /// address.
    var wanted: SignedInAccount {
        SignedInAccount(accountID: wantedUUID.flatMap { $0.hasPrefix("email:") ? nil : $0 }, email: wantedEmail, origin: .record)
    }
}

enum SwitchOutcome: Equatable {
    /// The folder is on the account wanted.
    case reached
    /// The folder changed account, but to another one (the browser was signed in as someone else).
    case other(email: String)
    /// No sign-in came: ten minutes passed, or Claude Code's login ended without one (declined in the browser, failed, its
    /// window closed).
    case timedOut
}

/// A switch that ended without reaching the account wanted: another one signed in, or none did.
struct SwitchEnded: Equatable {
    var goal: SwitchGoal
    /// The address that signed in instead; nil: no sign-in came.
    var signedIn: String?
}

final class AccountSwitcher {
    static let shared = AccountSwitcher()
    /// Posted (main thread) whenever a switch begins, ends or is dropped, or the account signed in to a folder changed:
    /// the chat and Settings draw again. (The folder's change is posted by FolderFiles itself, whoever parsed the file.)
    static let changed = FolderFiles.accountChanged

    /// By profile id: the sign-ins being waited for.
    private(set) var waiting: [String: SwitchGoal] = [:]
    /// By profile id: the last switch that ended on another account or timed out, until it's tried again or dismissed.
    private(set) var ended: [String: SwitchEnded] = [:]
    /// By profile id: the address a sign-in again just ended on, the same account, until dismissed or something new begins.
    private(set) var signedAgain: [String: String] = [:]
    /// A switch ended (the chat carries on with it).
    var onOutcome: (SwitchGoal, SwitchOutcome) -> Void = { _, _ in }
    /// The sign-in under way (one at a time: ClaudeSignIn ends the earlier one when another starts), and its folder.
    private(set) var active: (folder: String, signIn: ClaudeSignIn)?

    /// Where `claude` is (off the main thread), and how a sign-in is made: the checks put stand-ins here (no Terminal, a
    /// stand-in claude, folders under build/).
    var findClaude: () -> String? = { ClaudeLocator.find()?.path }
    var makeSignIn: (_ folder: String, _ wanted: SignedInAccount?, _ claude: String) -> ClaudeSignIn = AccountSwitcher.realSignIn

    /// Made once, as cl_quick starts (the chat holds it): a sign-in script an older version left behind goes (not while
    /// only checking or drawing).
    private init() {
        if !Files.readOnly { try? FileManager.default.removeItem(at: Files.folder.appendingPathComponent("sign-in.command")) }
    }

    /// cl_quick's ClaudeSignIn: the real Mac's tools (Terminal, the folder's own guard; no Keychain reader), its files in
    /// cl_quick's folder (sign-in/), the account confirmed by a short `claude` on the folder.
    static func realSignIn(folder: String, wanted: SignedInAccount?, claude: String) -> ClaudeSignIn {
        let f = AuthFolder(path: expand(folder), isDefault: ClaudeFolder.isDefault(folder))
        return ClaudeSignIn(folder: f, wanted: wanted, tools: .system, claude: claude,
                            confirm: SignInWord.confirm(claude: claude, workFolder: Files.work.appendingPathComponent("sign-in").path),
                            work: Files.folder.appendingPathComponent("sign-in"), shown: tilde(f.path))
    }

    /// "Switch to …": asks first, in plain words, then opens Claude Code's sign-in and watches the folder.
    func confirmAndSwitch(_ p: Profile, uuid: String?, email: String, origin: SwitchGoal.Origin) {
        let answer = Self.runAlert(Self.confirmAlert(p, email: email))
        // the alert took the pointer: whatever was under it (the Switch to … button) got no exit, so its address goes blurred
        AddressPrivacy.shared.endHover()
        guard answer == .alertFirstButtonReturn else { return }
        begin(p, uuid: uuid, email: email, origin: origin)
    }

    /// Shows a question modally (the checks replace it: nothing is shown, cl_quick is never activated).
    static var runAlert: (NSAlert) -> NSApplication.ModalResponse = { alert in
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }

    /// The switch question. An alert's text can't blur, so the address is not in it: the words say "this account" and the
    /// address sits under them in an accessory view, blurred until the pointer is on it.
    static func confirmAlert(_ p: Profile, email: String) -> NSAlert {
        let a = NSAlert()
        a.messageText = "Switch \(p.name) to this account?"
        a.informativeText = AccountBook.switchWords(folder: tilde(p.path), isDefault: ClaudeFolder.isDefault(p.path))
        a.accessoryView = QCAddressLabel(address: email)
        a.addButton(withTitle: "Switch"); a.addButton(withTitle: "Cancel")
        return a
    }

    /// Opens the sign-in for `email` on the profile's folder and waits for ClaudeSignIn's outcome.
    func begin(_ p: Profile, uuid: String?, email: String, origin: SwitchGoal.Origin) {
        let now = ClaudeFolder.account(p.path)
        let goal = SwitchGoal(profileID: p.id, profileName: p.name, folder: p.path, wantedUUID: uuid, wantedEmail: email,
                              fromUUID: now?.uuid, fromEmail: now?.email, origin: origin)
        waiting[p.id] = goal
        ended[p.id] = nil; signedAgain[p.id] = nil
        changed()
        signIn(folder: p.path, wanted: goal.wanted, couldNotStart: { [weak self] why in
            guard self?.waiting[p.id] == goal else { return }
            self?.drop(p.id)
            Self.tell(why)
        }, ended: { [weak self] outcome in self?.finished(goal, outcome) })
    }

    /// Signs in again on the account in use: asks nothing (it changes nothing), opens Claude Code's sign-in in Terminal
    /// and follows it like a switch: the same account is "Signed in again", another one is the wrong account, and no
    /// sign-in is the timeout's note.
    func signInAgain(_ p: Profile, origin: SwitchGoal.Origin) {
        guard waiting[p.id] == nil, let now = ClaudeFolder.account(p.path) else {
            // not signed in at all: no account to wait for; Claude Code's own sign-in on the folder
            signIn(folder: p.path)
            return
        }
        begin(p, uuid: now.uuid, email: now.email, origin: origin)
    }

    /// Claude Code's sign-in on a folder, for an account (a switch) or for whoever signs in (a signed-out folder, a folder
    /// found, a new one, made by the caller first). `opened`: its window is open. `couldNotStart`: it never opened, and why
    /// (said in an alert unless the caller says it itself). `ended`: its outcome once it opened; the folders are read again
    /// first. Ends the sign-in under way, if any (one at a time).
    func signIn(folder: String, wanted: SignedInAccount? = nil, opened: @escaping () -> Void = {},
                couldNotStart: @escaping (String) -> Void = { AccountSwitcher.tell($0) },
                ended: @escaping (ClaudeSignIn.Outcome) -> Void = { _ in }) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let claude = findClaude()
            DispatchQueue.main.async { [self] in
                guard let claude else { return couldNotStart(ClaudeInstall.missing + ".") }
                let s = makeSignIn(folder, wanted, claude)
                active = (folder, s)
                var open = false
                s.start(onState: { state in
                    if state == .waitingForBrowser { open = true; opened() }
                }, onEnd: { [weak self] outcome in
                    if let a = self?.active, a.signIn === s { self?.active = nil }
                    if !open, case .failed(let f) = outcome, let why = Self.why(f, folder: folder) { return couldNotStart(why) }
                    ClaudeFolder.reload([folder]) { _ in
                        ProfileStore.shared.reload()
                        ended(outcome)
                    }
                })
            }
        }
    }

    /// A sign-in that never opened, said plainly; nil for a failure that only comes after it opened.
    static func why(_ f: ClaudeSignIn.Failure, folder: String) -> String? {
        switch f {
        case .folderNotReady: return "\(tilde(expand(folder))) isn't there as a folder."
        case .locked, .alreadySigningIn: return "Claude Code's sign-in is already open for \(tilde(expand(folder)))."
        case .processesUnreadable: return "cl_quick couldn't tell whether Claude Code's sign-in is already open for \(tilde(expand(folder)))."
        case .notOpened: return "Terminal couldn't open it."
        case .loginFailed, .noAccount, .windowClosed: return nil
        }
    }

    /// A switch's sign-in ended. A stop (Stop, or another sign-in began) leaves the switch to whoever stopped it; the rest are
    /// today's notes: the account wanted, another one, or none came (the timeout's note, also when the login ended without
    /// one).
    private func finished(_ goal: SwitchGoal, _ outcome: ClaudeSignIn.Outcome) {
        guard waiting[goal.profileID] == goal else { return }           // dropped, or begun again, meanwhile
        switch outcome {
        case .signedIn(let a): end(goal.profileID, goal, .reached, signedIn: a.email)
        case .wrongAccount(let a, _): end(goal.profileID, goal, .other(email: a.email ?? ClaudeFolder.email(goal.folder) ?? ""))
        case .timedOut, .declined, .failed: end(goal.profileID, goal, .timedOut)
        case .stopped: drop(goal.profileID)
        }
    }

    /// Stops waiting for a profile's sign-in (and ends it: its `claude auth login` and its window), and dismisses a switch
    /// that ended on another account or timed out, or the "Signed in again" line.
    func drop(_ id: String) {
        if let goal = waiting[id], let a = active, a.folder == goal.folder { a.signIn.stop(); active = nil }
        guard waiting[id] != nil || ended[id] != nil || signedAgain[id] != nil else { return }
        waiting[id] = nil; ended[id] = nil; signedAgain[id] = nil
        changed()
    }

    /// Ends the sign-in under way on a folder (a profile removed while it signs in).
    func stop(folder: String) {
        if let a = active, a.folder == folder { a.signIn.stop(); active = nil }
    }

    private func end(_ id: String, _ goal: SwitchGoal, _ outcome: SwitchOutcome, signedIn: String? = nil) {
        waiting[id] = nil
        if outcome != .timedOut { ProfileStore.shared.signedIn(id) }       // a sign-in landed: an earlier failure is behind it
        switch outcome {
        case .other(let email): ended[id] = SwitchEnded(goal: goal, signedIn: email)
        case .timedOut: ended[id] = SwitchEnded(goal: goal, signedIn: nil)
        case .reached:
            ended[id] = nil
            if goal.again { signedAgain[id] = signedIn ?? goal.wantedEmail }
        }
        ProfileStore.shared.noteAccount(of: id)          // the account now signed in is remembered
        changed()
        onOutcome(goal, outcome)
    }

    private func changed() { NotificationCenter.default.post(name: Self.changed, object: nil) }

    /// A sign-in that couldn't start: said plainly (the checks replace it: nothing is shown).
    static var tell: (String) -> Void = { why in
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "The sign-in couldn't start"
        a.informativeText = why
        a.addButton(withTitle: "OK")
        a.runModal()
    }
}

/// cl_quick's verified word on a folder's account, for ClaudeSignIn: a short `claude` on the folder, started the way the
/// quick chat starts one (QuickChatCommand: no tools, nothing kept), asked `initialize` (nothing goes to a model), and its
/// answer's `account` (SignedInAccount.process); then stopped. nil when it says nobody or doesn't answer in 20 seconds.
/// Never the Keychain. Blocks: ClaudeSignIn calls it off the main thread (the answer comes through the main queue).
enum SignInWord {
    static func confirm(claude: String, workFolder: String, wait: TimeInterval = 20) -> ClaudeSignIn.Confirm {
        return { folder in
            let p = QuickChatProcess(QuickChatCommand(claude: claude, configDir: folder.path, isDefaultDir: folder.isDefault,
                                                      workFolder: workFolder, model: ""))
            let answered = DispatchSemaphore(value: 0)
            let lock = NSLock()
            var said: ProcessIdentity?
            p.onEvent = { e in
                guard case .models(_, let who) = e else { return }
                lock.lock(); said = who; lock.unlock()
                answered.signal()
            }
            p.onExit = { _, _ in answered.signal() }
            guard (try? p.start()) != nil, p.initialize() else { p.stop(); return nil }
            _ = answered.wait(timeout: .now() + wait)
            p.stop()
            lock.lock(); let who = said; lock.unlock()
            var account: [String: Any] = [:]
            if let e = who?.email { account["email"] = e }
            if let o = who?.organization { account["organization"] = o }
            return SignedInAccount.process(account)
        }
    }
}
