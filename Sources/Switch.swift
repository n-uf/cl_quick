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
    /// The folder is on the account wanted (Claude Code confirmed it).
    case reached
    /// It ended without the account wanted, and why.
    case ended(SwitchEndReason)
}

/// Why a switch ended without reaching the account wanted. Each has its own note.
enum SwitchEndReason: Equatable {
    /// The folder changed account, but to another one (the browser was signed in as someone else): the address it is on now,
    /// and the name of another profile that account is also in use on, if there is one.
    case wrongAccount(signedIn: String, alsoOn: String?)
    /// No sign-in came in ten minutes.
    case timedOut
    /// The person declined in the browser.
    case declined
    /// The login ended well, but Claude Code didn't confirm which account it is: the folder may have changed.
    case unverified
    /// Another sign-in (another profile's, or this one asked for again) ended it.
    case replaced
    /// Claude Code's login failed, ended on nobody, or lost its window.
    case failed(ClaudeSignIn.Failure)
}

/// A switch that ended without reaching the account wanted.
struct SwitchEnded: Equatable {
    var goal: SwitchGoal
    var reason: SwitchEndReason

    /// The address that signed in instead, when another account did.
    var signedIn: String? { if case .wrongAccount(let a, _) = reason { return a } else { return nil } }
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
    /// A sign-in asked for while claude is looked for: its folder, its ticket, and how it ends if another one is asked for
    /// meanwhile (stopped, as when a new sign-in ends the one under way).
    private var pending: (folder: String, ticket: UUID, superseded: () -> Void)?

    /// Where `claude` is (off the main thread), and how a sign-in is made: the checks put stand-ins here (no Terminal, a
    /// stand-in claude, folders under build/).
    var findClaude: () -> String? = { ClaudeLocator.find()?.path }
    var makeSignIn: (_ folder: String, _ wanted: SignedInAccount?, _ claude: String) -> ClaudeSignIn = AccountSwitcher.realSignIn

    /// Made once, as cl_quick starts (the chat holds it): a sign-in script an older version left behind goes, and so do the
    /// profiles Terminal kept of earlier sign-ins (off the main thread; not while only checking or drawing).
    private init() {
        if !Files.readOnly {
            try? FileManager.default.removeItem(at: Files.folder.appendingPathComponent("sign-in.command"))
            DispatchQueue.global(qos: .utility).async { Self.sweepLeftovers() }
        }
    }

    /// Sweeps Terminal's kept profiles of cl_quick's sign-ins that nothing sweeps by itself any more: a declined or failed
    /// window left open and closed by hand later, with no sign-in after it. At start (above) and at quit (`stopForQuit`).
    /// Nothing while only checking or drawing; the checks put a stand-in here (never this Mac's Terminal preferences).
    static var sweepLeftovers: () -> Void = { if !Files.readOnly { ClaudeSignIn.sweep(work: signInWork) } }

    /// cl_quick's folder for its sign-ins' files (never the Claude Code folder).
    static var signInWork: URL { Files.folder.appendingPathComponent("sign-in") }

    /// cl_quick's ClaudeSignIn: the real Mac's tools (Terminal, the folder's own guard; no Keychain reader), its files in
    /// cl_quick's folder (sign-in/), the account confirmed by a short `claude` on the folder.
    static func realSignIn(folder: String, wanted: SignedInAccount?, claude: String) -> ClaudeSignIn {
        let f = AuthFolder(path: expand(folder), isDefault: ClaudeFolder.isDefault(folder))
        return ClaudeSignIn(folder: f, wanted: wanted, tools: .system, claude: claude,
                            confirm: SignInWord.confirm(claude: claude, workFolder: Files.work.appendingPathComponent("sign-in").path),
                            work: signInWork, title: "cl_quick", shown: tilde(f.path))
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

    /// "Try again as A" / "Sign in again" on a switch that ended: the same account wanted, begun from the folder as it is
    /// now (after a wrong account the folder is on B, so this is a switch to A, not a sign-in again). Nothing while a
    /// sign-in is waited for on that profile, or when none ended (the note it was asked from is gone).
    func tryAgain(_ p: Profile, origin: SwitchGoal.Origin) {
        guard waiting[p.id] == nil, let m = ended[p.id] else { return }
        begin(p, uuid: m.goal.wantedUUID, email: m.goal.wantedEmail, origin: origin)
    }

    /// Claude Code's sign-in on a folder, for an account (a switch) or for whoever signs in (a signed-out folder, a folder
    /// found, a new one, made by the caller first). `opened`: its window is open. `couldNotStart`: it never opened, and why
    /// (said in an alert unless the caller says it itself). `ended`: its outcome once it opened; the folders are read again
    /// first. Ends the sign-in under way, if any (one at a time).
    func signIn(folder: String, wanted: SignedInAccount? = nil, opened: @escaping () -> Void = {},
                couldNotStart: @escaping (String) -> Void = { AccountSwitcher.tell($0) },
                ended: @escaping (ClaudeSignIn.Outcome) -> Void = { _ in }) {
        // claude is looked for first, off the main thread; a drop or a stop meanwhile (or another sign-in asked for) takes
        // the ticket away, and nothing starts
        let ticket = UUID()
        let earlier = pending
        pending = (folder, ticket, { ended(.stopped) })
        earlier?.superseded()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let claude = findClaude()
            DispatchQueue.main.async { [self] in
                guard pending?.ticket == ticket else { return }
                pending = nil
                guard let claude else { return couldNotStart(ClaudeInstall.missing + ".") }
                let s = makeSignIn(folder, wanted, claude)
                active = (folder, s)
                var open = false
                s.start(onState: { state in
                    if state == .waitingForBrowser { open = true; opened() }
                }, onEnd: { [weak self] outcome in
                    if let a = self?.active, a.signIn === s { self?.active = nil }
                    // never opened, or opened but never started (Terminal ran nothing): the "couldn't start" alert, not a
                    // note on an account that "hasn't changed". The one that was open is also ended for the caller.
                    if case .failed(let f) = outcome, let why = Self.why(f, folder: folder) {
                        couldNotStart(why)
                        if !open { return }
                    }
                    ClaudeFolder.reload([folder]) { _ in
                        ProfileStore.shared.reload()
                        ended(outcome)
                    }
                })
            }
        }
    }

    /// A sign-in that didn't start, said plainly (the "couldn't start" alert); nil for a failure that only comes after the
    /// sign-in was under way (a login that failed, ended on nobody, or lost its window), which is a note on the account.
    static func why(_ f: ClaudeSignIn.Failure, folder: String) -> String? {
        switch f {
        case .folderNotReady, .locked, .alreadySigningIn, .processesUnreadable, .notOpened:
            let w = SignInWords.failure(f, folder: folder)
            return w.lead + " " + w.rest
        case .loginFailed, .noAccount, .windowClosed: return nil
        }
    }

    /// A switch's sign-in ended: the account wanted (only when Claude Code confirmed it), another one (and whether that one
    /// is also in use on another profile), or none, each with its own note (SwitchWords.ended): no sign-in in 10 minutes,
    /// declined in the browser, signed in but not confirmed, a login that failed, ended on nobody or lost its window, or one
    /// ended by another sign-in. Stop (`drop`) has already taken its note.
    private func finished(_ goal: SwitchGoal, _ outcome: ClaudeSignIn.Outcome) {
        guard waiting[goal.profileID] == goal else { return }           // dropped, or begun again, meanwhile
        switch outcome {
        case .signedIn(let a): end(goal.profileID, goal, .reached, signedIn: a.email)
        case .wrongAccount(let a, _):
            let email = a.email ?? ClaudeFolder.email(goal.folder) ?? ""
            // the folder was read again before this: it is on the account that signed in
            let uuid = ClaudeFolder.account(goal.folder).flatMap { $0.email.lowercased() == email.lowercased() ? $0.uuid : nil } ?? a.accountID ?? "email:" + email
            let also = Self.profileAlsoUsing((uuid, email), besides: goal.profileID, profiles: ProfileStore.shared.profiles,
                                             account: { ClaudeFolder.account($0.path) })
            end(goal.profileID, goal, .ended(.wrongAccount(signedIn: email, alsoOn: also)))
        case .timedOut: end(goal.profileID, goal, .ended(.timedOut))
        case .declined: end(goal.profileID, goal, .ended(.declined))
        case .unverified: end(goal.profileID, goal, .ended(.unverified))
        case .stopped: end(goal.profileID, goal, .ended(.replaced))
        case .failed(let f): end(goal.profileID, goal, .ended(.failed(f)))
        }
    }

    /// The name of another profile (not `besides`) whose folder is signed in to this account now, if one is: the account
    /// the browser signed in is then in use there too (one account never makes two profiles).
    static func profileAlsoUsing(_ account: (uuid: String, email: String), besides id: String, profiles: [Profile],
                                 account of: (Profile) -> (uuid: String, email: String)?) -> String? {
        AccountBook.profileUsing(account, among: profiles.filter { $0.id != id }.map { ($0.name, of($0)) })
    }

    /// Stops waiting for a profile's sign-in (and ends it: its `claude auth login` and its window), and dismisses a switch
    /// that ended on another account or timed out, or the "Signed in again" line.
    func drop(_ id: String) {
        if let goal = waiting[id] { stop(folder: goal.folder) }
        guard waiting[id] != nil || ended[id] != nil || signedAgain[id] != nil else { return }
        waiting[id] = nil; ended[id] = nil; signedAgain[id] = nil
        changed()
    }

    /// Ends the sign-in under way on a folder, or the one about to start (a profile removed while it signs in, Stop).
    func stop(folder: String) {
        if let p = pending, Self.sameFolder(p.folder, folder) { pending = nil }
        if let a = active, Self.sameFolder(a.folder, folder) { a.signIn.stop(); active = nil }
    }

    /// cl_quick is quitting: the sign-in under way ends now, its login and window with it (nothing waits for an outcome).
    /// Then Terminal's kept profiles are swept whether one was under way or not: an ended sign-in's window, left open to be
    /// read and closed by hand since, keeps its profile until something sweeps it.
    func stopForQuit() {
        pending = nil
        active?.signIn.stopNow()
        active = nil
        Self.sweepLeftovers()
    }

    /// Two spellings of one folder (~ or the full path, a trailing slash, a link to it).
    static func sameFolder(_ a: String, _ b: String) -> Bool {
        func key(_ s: String) -> String { URL(fileURLWithPath: expand(s)).standardizedFileURL.resolvingSymlinksInPath().path }
        return key(a) == key(b)
    }

    private func end(_ id: String, _ goal: SwitchGoal, _ outcome: SwitchOutcome, signedIn: String? = nil) {
        waiting[id] = nil
        // a sign-in landed (the account wanted, or another one): an earlier failure is behind it
        switch outcome {
        case .reached, .ended(.wrongAccount): ProfileStore.shared.signedIn(id)
        case .ended: break
        }
        switch outcome {
        case .ended(let reason): ended[id] = SwitchEnded(goal: goal, reason: reason)
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

/// The words of a switch after it ended without the account wanted: a lead and the rest, in pieces so the addresses in them
/// blur (QCWords), the same in the chat and in Settings. Each way it ended has its own: only a timeout says no sign-in came.
enum SwitchWords {
    static func ended(_ e: SwitchEnded) -> (lead: QCWords, rest: QCWords) {
        let wanted = e.goal.wantedEmail
        switch e.reason {
        case .wrongAccount(let signedIn, let also):
            // the browser was signed in as B, not A, and the profile is on B now (and B is in use elsewhere too, if it is)
            let b: QCWords = signedIn.isEmpty ? .text("someone else") : .address(signedIn)
            var rest = QCWords(" ") + QCWords.isOn(e.goal.profileName, address: signedIn.isEmpty ? nil : signedIn)
            if let also, !signedIn.isEmpty { rest = rest + .text(" ") + .address(signedIn) + .text(" is also in use on \(also).") }
            return (.text("The browser was signed in as ") + b + .text(", not ") + .address(wanted) + .text("."), rest)
        case .timedOut: return (QCWords("No sign-in in 10 minutes."), QCWords(" The account in use hasn't changed."))
        case .declined: return (QCWords("The sign-in was declined in the browser."), QCWords(" The account in use hasn't changed."))
        case .unverified:
            return (QCWords("Signed in, but Claude Code didn't confirm which account."), QCWords(" Check the account line in the menu."))
        case .replaced: return (QCWords("Another sign-in started, so this one ended."), QCWords(" The account in use hasn't changed."))
        case .failed(let f):
            let w = SignInWords.failure(f, folder: e.goal.folder)
            return (QCWords(w.lead), QCWords(" " + w.rest))
        }
    }

    /// While the sign-in is open: what to do in the browser, in order.
    static func steps(wanted: String) -> [QCWords] {
        [.text("Finish the sign-in in the browser."),
         .text("Before you press Authorize, check that “Logged in as” at the bottom of the page shows ") + .address(wanted) + .text("."),
         .text("If it doesn't, use Switch account there.")]
    }
    static let foot = "cl_quick looks for it for 10 minutes."

    /// The key that starts the same switch again: "Sign in again" when it was a sign-in again on the account in use and
    /// nobody else signed in, else "Try again as <address wanted>" (the address blurred by whoever draws it).
    static func retry(_ e: SwitchEnded) -> (title: String, address: String?) {
        e.goal.again && e.signedIn == nil ? ("Sign in again", nil) : ("Try again as ", e.goal.wantedEmail)
    }
    /// The key that keeps what happened: "Keep <the address it is on>" after a wrong account on an account no other profile
    /// uses; nil otherwise (the caller's plain dismiss: Dismiss in the chat, OK in Settings). When that account is also in use
    /// on another profile there is nothing to keep: the note still says so, and Try again as A is the one key that acts.
    static func keep(_ e: SwitchEnded) -> (title: String, address: String)? {
        guard case .wrongAccount(let b, let also) = e.reason, !b.isEmpty, also == nil else { return nil }
        return ("Keep ", b)
    }
}

/// What every way a sign-in can fail says, in plain words: what happened, then what to do. One line each, never the
/// generic "hasn't changed": the ones that stop a sign-in from starting are said in the "couldn't start" alert, the others
/// in the note on the profile.
enum SignInWords {
    static func failure(_ f: ClaudeSignIn.Failure, folder: String) -> (lead: String, rest: String) {
        let path = tilde(expand(folder))
        switch f {
        case .folderNotReady: return ("\(path) isn't there as a plain folder.", "cl_quick didn't open a sign-in.")
        case .locked: return ("Another sign-in for \(path) is starting.", "Wait a moment, then try again.")
        case .alreadySigningIn: return ("Claude Code's sign-in is already open for \(path).", "Finish it, or close its Terminal window, then try again.")
        case .processesUnreadable: return ("cl_quick couldn't tell whether Claude Code's sign-in is already open for \(path).", "It didn't open one. Try again.")
        case .notOpened: return ("Terminal didn't open the sign-in.", "Try again.")
        case .loginFailed(let status): return ("Claude Code's sign-in failed.", "It ended with an error (status \(status)); its Terminal window shows why.")
        case .noAccount: return ("The sign-in ended, but no account is signed in to this folder.", "Try again.")
        case .windowClosed: return ("The Terminal window was closed before the sign-in ended.", "Try again.")
        }
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
