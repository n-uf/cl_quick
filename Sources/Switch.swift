// Switch: changing which account a profile is on. A profile is one Claude Code folder and the folder holds one signed-in
// account at a time, so switching is signing in again in the same folder, as another account: Claude Code's own
// `claude auth login` (SignIn.swift), in Terminal, finished in the browser. The browser's claude.ai session decides which
// account signs in, so the result is checked: the folder's .claude.json is looked at every 2 s, for at most 10 minutes,
// until its account changes. cl_quick never sees a password or a token, and touches no Keychain.

import AppKit

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
    /// so only Claude Code's login ending says it's done (SignIn.marker).
    var again: Bool { fromUUID != nil && wantedUUID == fromUUID }
}

enum SwitchOutcome: Equatable {
    /// The folder is on the account wanted.
    case reached
    /// The folder changed account, but to another one (the browser was signed in as someone else).
    case other(email: String)
    /// Ten minutes passed with no change.
    case timedOut
}

/// A switch that ended without reaching the account wanted: another one signed in, or nothing did in 10 minutes.
struct SwitchEnded: Equatable {
    var goal: SwitchGoal
    /// The address that signed in instead; nil: no sign-in came in the 10 minutes.
    var signedIn: String?
}

final class AccountSwitcher {
    static let shared = AccountSwitcher()
    /// Posted (main thread) whenever a switch begins, ends or is dropped, or the account signed in to a folder changed:
    /// the chat and Settings draw again.
    static let changed = Notification.Name("cl_quick.accountSwitch.changed")
    /// How long a sign-in is waited for, and how often the folder is looked at.
    static let giveUp: TimeInterval = 10 * 60
    static let every: TimeInterval = 2

    /// By profile id: the sign-ins being waited for.
    private(set) var waiting: [String: SwitchGoal] = [:]
    /// By profile id: the last switch that ended on another account or timed out, until it's tried again or dismissed.
    private(set) var ended: [String: SwitchEnded] = [:]
    /// By profile id: the address a sign-in again just ended on, the same account, until dismissed or something new begins.
    private(set) var signedAgain: [String: String] = [:]
    /// A switch ended (the chat carries on with it).
    var onOutcome: (SwitchGoal, SwitchOutcome) -> Void = { _, _ in }
    private var timer: Timer?

    /// "Switch to …": asks first, in plain words, then opens Claude Code's sign-in and watches the folder.
    func confirmAndSwitch(_ p: Profile, uuid: String?, email: String, origin: SwitchGoal.Origin) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Switch \(p.name) to \(maskEmail(email))?"
        a.informativeText = "Every Claude Code session using \(tilde(p.path)) moves to that account when it next renews its sign-in. Claude Code's sign-in opens in Terminal; finish it in the browser as that account."
        a.addButton(withTitle: "Switch"); a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        begin(p, uuid: uuid, email: email, origin: origin)
    }

    /// Opens the sign-in for `email` on the profile's folder and waits for the folder's account to change.
    func begin(_ p: Profile, uuid: String?, email: String, origin: SwitchGoal.Origin) {
        let now = ClaudeFolder.account(p.path)
        waiting[p.id] = SwitchGoal(profileID: p.id, profileName: p.name, folder: p.path, wantedUUID: uuid, wantedEmail: email,
                                   fromUUID: now?.uuid, fromEmail: now?.email, origin: origin)
        ended[p.id] = nil; signedAgain[p.id] = nil
        // a sign-in again leaves a marker when Claude Code's login ends; one left by an earlier try says nothing now
        let again = waiting[p.id]?.again == true
        SignIn.clearMarker(p.id)
        startTimer()
        changed()
        SignIn.open(folder: p.path, email: email, marker: again ? SignIn.marker(for: p.id) : nil) { [weak self] why in
            guard let why else { return }
            self?.drop(p.id)
            SignIn.tell(why)
        }
    }

    /// Signs in again on the account in use: asks nothing (it changes nothing), opens Claude Code's sign-in in Terminal
    /// and watches the result like a switch: the same account is "Signed in again", another one is the wrong account,
    /// and no sign-in in 10 minutes is a timeout.
    func signInAgain(_ p: Profile, origin: SwitchGoal.Origin) {
        guard waiting[p.id] == nil, let now = ClaudeFolder.freshAccount(p.path) else {
            // not signed in at all: nothing to watch for a given account; Claude Code's own sign-in, as before
            SignIn.open(folder: p.path) { why in if let why { SignIn.tell(why) } }
            return
        }
        begin(p, uuid: now.uuid, email: now.email, origin: origin)
    }

    /// Stops waiting for a profile's sign-in, and dismisses a switch that ended on another account or timed out, or the
    /// "Signed in again" line.
    func drop(_ id: String) {
        guard waiting[id] != nil || ended[id] != nil || signedAgain[id] != nil else { return }
        waiting[id] = nil; ended[id] = nil; signedAgain[id] = nil
        SignIn.clearMarker(id)
        if waiting.isEmpty { timer?.invalidate(); timer = nil }
        changed()
    }

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.every, repeats: true) { [weak self] _ in self?.look() }
    }

    /// One look at every folder being waited for: the files are read off the main thread, and what they said is judged
    /// here, on the main thread, from the value kept.
    func look() {
        guard !waiting.isEmpty else { return }
        ClaudeFolder.reload(waiting.values.map(\.folder)) { [weak self] _ in self?.judge() }
    }

    /// Every sign-in waited for: on the account wanted, on another, or past the 10 minutes.
    func judge(now: Date = Date()) {
        for (id, goal) in waiting {
            if now.timeIntervalSince(goal.started) > Self.giveUp { end(id, goal, .timedOut); continue }
            guard let cur = ClaudeFolder.account(goal.folder) else { continue }       // signed out for a moment: still waiting
            if goal.again {
                // the same account is no news until Claude Code's login says it ended well; another account is news at once
                if cur.uuid == goal.fromUUID { if SignIn.finished(id) { end(id, goal, .reached, signedIn: cur.email) }; continue }
                end(id, goal, .other(email: cur.email)); continue
            }
            if cur.uuid == goal.fromUUID, cur.email.lowercased() == goal.fromEmail?.lowercased() { continue }
            end(id, goal, Self.reached(goal, cur) ? .reached : .other(email: cur.email))
        }
    }

    /// The account signed in is the one wanted: by uuid, or by address (an address typed in has no uuid yet).
    static func reached(_ goal: SwitchGoal, _ now: (uuid: String, email: String)) -> Bool {
        goal.wantedUUID == now.uuid || now.email.lowercased() == goal.wantedEmail.lowercased()
    }

    private func end(_ id: String, _ goal: SwitchGoal, _ outcome: SwitchOutcome, signedIn: String? = nil) {
        waiting[id] = nil
        SignIn.clearMarker(id)
        switch outcome {
        case .other(let email): ended[id] = SwitchEnded(goal: goal, signedIn: email)
        case .timedOut: ended[id] = SwitchEnded(goal: goal, signedIn: nil)
        case .reached:
            ended[id] = nil
            if goal.again { signedAgain[id] = signedIn ?? goal.wantedEmail }
        }
        if waiting.isEmpty { timer?.invalidate(); timer = nil }
        ProfileStore.shared.noteAccount(of: id)          // the account now signed in is remembered
        changed()
        onOutcome(goal, outcome)
    }

    private func changed() { NotificationCenter.default.post(name: Self.changed, object: nil) }
}

extension SignIn {
    /// A sign-in that couldn't start: said plainly.
    static func tell(_ why: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "The sign-in couldn't start"
        a.informativeText = why
        a.addButton(withTitle: "OK")
        a.runModal()
    }
}
