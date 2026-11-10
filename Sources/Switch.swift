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
}

enum SwitchOutcome: Equatable {
    /// The folder is on the account wanted.
    case reached
    /// The folder changed account, but to another one (the browser was signed in as someone else).
    case other(email: String)
    /// Ten minutes passed with no change.
    case timedOut
}

/// A switch that ended on another account than the one wanted.
struct SwitchMismatch: Equatable {
    var goal: SwitchGoal
    var signedIn: String
}

final class AccountSwitcher {
    static let shared = AccountSwitcher()
    /// Posted (main thread) whenever a switch begins, ends or is dropped: the chat and Settings draw again.
    static let changed = Notification.Name("cl_quick.accountSwitch.changed")
    /// How long a sign-in is waited for, and how often the folder is looked at.
    static let giveUp: TimeInterval = 10 * 60
    static let every: TimeInterval = 2

    /// By profile id: the sign-ins being waited for.
    private(set) var waiting: [String: SwitchGoal] = [:]
    /// By profile id: the last switch that ended on another account, until it's tried again or dropped.
    private(set) var mismatch: [String: SwitchMismatch] = [:]
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
        mismatch[p.id] = nil
        startTimer()
        changed()
        SignIn.open(folder: p.path, email: email) { [weak self] why in
            guard let why else { return }
            self?.drop(p.id)
            SignIn.tell(why)
        }
    }

    /// Stops waiting for a profile's sign-in, and forgets a switch that ended on another account.
    func drop(_ id: String) {
        guard waiting[id] != nil || mismatch[id] != nil else { return }
        waiting[id] = nil; mismatch[id] = nil
        if waiting.isEmpty { timer?.invalidate(); timer = nil }
        changed()
    }

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.every, repeats: true) { [weak self] _ in self?.look() }
    }

    /// One look at every folder being waited for.
    func look(now: Date = Date()) {
        for (id, goal) in waiting {
            if now.timeIntervalSince(goal.started) > Self.giveUp { end(id, goal, .timedOut); continue }
            guard let cur = ClaudeFolder.account(goal.folder) else { continue }       // signed out for a moment: still waiting
            if cur.uuid == goal.fromUUID, cur.email.lowercased() == goal.fromEmail?.lowercased() { continue }
            end(id, goal, Self.reached(goal, cur) ? .reached : .other(email: cur.email))
        }
    }

    /// The account signed in is the one wanted: by uuid, or by address (an address typed in has no uuid yet).
    static func reached(_ goal: SwitchGoal, _ now: (uuid: String, email: String)) -> Bool {
        goal.wantedUUID == now.uuid || now.email.lowercased() == goal.wantedEmail.lowercased()
    }

    private func end(_ id: String, _ goal: SwitchGoal, _ outcome: SwitchOutcome) {
        waiting[id] = nil
        if case .other(let email) = outcome { mismatch[id] = SwitchMismatch(goal: goal, signedIn: email) }
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
