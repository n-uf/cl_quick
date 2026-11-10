// Chat: cl_quick's floating chat, its state and its controller. A bar first; the first message turns it into a chat window
// that stays floating over any app, on every Space, until Esc hides it. It never brings anything else forward.
//
// It answers through your own Claude Code (Engine.swift), on the profile you pick (Profiles.swift), on that profile's
// account in use, and counts against its limits. One `claude` at a time. A chat is incognito: nothing is saved, the
// conversation lives only in the running `claude`, and it ends with it (15 minutes idle, ⌘N, a crash, another profile
// or account, quitting); the next message starts a new chat. The bar and the window are ChatViews.swift.

import AppKit
import Combine
import SwiftUI

// MARK: - Settings

// The model a chat answers with (QuickChatModelChoice) is in Engine.swift, with Claude Code's list (Models.swift).

/// How long Claude thinks before it answers: off, or Claude Code's effort (the steps the model takes, Models.swift).
enum QuickChatThinking: String, CaseIterable, Codable, Identifiable {
    case off, low, medium, high, xhigh, max
    var id: String { rawValue }
    var effort: String? { self == .off ? nil : rawValue }
    var title: String {
        switch self {
        case .off: return "Off"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .xhigh: return "Extra"
        case .max: return "Max"
        }
    }
    /// A few words in the thinking menu.
    var blurb: String {
        switch self {
        case .off: return "answers at once"
        case .low: return "thinks briefly first"
        case .medium: return "thinks a while first"
        case .high: return "for harder questions"
        case .xhigh: return "thinks long; uses the week fast"
        case .max: return "thinks longest; uses the week fastest"
        }
    }
}

struct QuickChatSettings: Codable, Equatable {
    /// The shortcut opens the chat from any app. On by default: it's what cl_quick is for.
    var shortcutOn = true
    var shortcut: QuickChatShortcut = .optionSpace
    /// The profile the shortcut chats on; nil: the first.
    var defaultProfile: String? = nil
    var model: QuickChatModelChoice = .haiku
    var thinking: QuickChatThinking = .off
    /// cl_audit's quick chat settings were looked at once, on the first run.
    var importedFromAudit = false

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shortcutOn = (try? c.decodeIfPresent(Bool.self, forKey: .shortcutOn)) ?? true
        shortcut = (try? c.decodeIfPresent(QuickChatShortcut.self, forKey: .shortcut)) ?? .optionSpace
        defaultProfile = try? c.decodeIfPresent(String.self, forKey: .defaultProfile)
        model = (try? c.decodeIfPresent(QuickChatModelChoice.self, forKey: .model)) ?? .haiku
        thinking = (try? c.decodeIfPresent(QuickChatThinking.self, forKey: .thinking)) ?? .off
        importedFromAudit = (try? c.decodeIfPresent(Bool.self, forKey: .importedFromAudit)) ?? false
    }

    static func load() -> QuickChatSettings { Files.read(QuickChatSettings.self, Files.settings) ?? .init() }
    func save() { Files.write(self, Files.settings) }

    /// The first run: the shortcut, model and thinking from cl_audit's own quick chat, if it had one; once.
    mutating func importFromAuditOnce() {
        guard !importedFromAudit else { return }
        importedFromAudit = true
        let old = URL(fileURLWithPath: expand("~/Library/Application Support/usage-n-uf/quick-chat/settings.json"))
        guard let d = try? Data(contentsOf: old), let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return }
        if let on = o["shortcutOn"] as? Bool { shortcutOn = on }
        if let s = (o["shortcut"] as? String).flatMap(QuickChatShortcut.preset(named:)) { shortcut = s }
        if let m = (o["model"] as? String).flatMap(QuickChatModelChoice.init(rawValue:)) { model = m }
        if let t = (o["thinking"] as? String).flatMap(QuickChatThinking.init(rawValue:)) { thinking = t }
    }
}

// MARK: - A chat

/// The profile a chat answers on, and the account signed in to its folder.
struct QuickChatTarget: Equatable {
    var profileID: String
    var name: String
    var configDir: String
    var isDefaultDir: Bool
    /// The account signed in to the folder now, as its file says (never a token).
    var email: String?
    var accountUUID: String?
    var workFolder: String

    init(_ p: Profile) {
        profileID = p.id; name = p.name; configDir = p.path; isDefaultDir = p.isDefaultFolder
        let a = ClaudeFolder.account(p.path)
        email = a?.email; accountUUID = a?.uuid; workFolder = p.workFolder
    }
}

/// Why an answer didn't come.
enum QuickChatProblem: Equatable {
    case notInstalled
    case notSignedIn(profile: String, id: String)
    /// `claude` ended before the answer was done: its exit and the end of what it wrote.
    case stopped(detail: String)
    /// Claude Code answered with an error of its own.
    case refused(text: String)
    case noProfile
    /// A limit of the profile's account is full (the level says which and until when; the offer, where to ask instead).
    case limitFull
}

struct QuickChatTurn: Identifiable, Equatable {
    enum Phase: Equatable { case waiting, streaming, done, stopped, failed }
    let id = UUID()
    var question: String
    var answer = ""
    var thinking = ""
    /// The model that answered ("Haiku 5.5"), from Claude Code.
    var model = ""
    /// Its thinking setting when asked; nil: off.
    var thinkingTitle: String? = nil
    var started = Date()
    var seconds: Double? = nil
    /// How long it thought before the answer began.
    var thinkingSeconds: Double? = nil
    var phase: Phase = .waiting
    var problem: QuickChatProblem? = nil

    var busy: Bool { phase == .waiting || phase == .streaming }
}

/// Why a chat ended while its turns are still on screen. The conversation lived only in its `claude`, so a chat that
/// ended is gone: the next message starts a new one.
enum QuickChatEnd: Equatable {
    /// 15 minutes with no message.
    case idle
    /// Stop, and Claude Code didn't stop the answer in time.
    case stopped
    /// Claude Code crashed, couldn't start, or needs another sign-in; the failed question can be asked again.
    case failed
    /// Claude Code ended on its own while the chat sat idle.
    case closed

    /// The plain line under the chat.
    var line: String {
        switch self {
        case .idle: return "This chat ended after 15 minutes idle. Nothing was saved."
        case .stopped: return "Stop ended this chat. Nothing was saved."
        case .failed: return "This chat ended. Retry asks the last question in a new chat."
        case .closed: return "Claude Code ended, and this chat with it. Nothing was saved."
        }
    }
}

/// Another profile with room, offered while this one's limit is full.
struct QuickChatOffer: Equatable {
    var profileID: String
    var name: String
    /// Its week at its last answer; nil: it hasn't answered anything yet.
    var week: Double?
}

/// Another account of the chat's own profile, on standby, offered while a limit is full: signing in again as it moves the
/// profile (and every Claude Code session using its folder) to it.
struct QuickChatSwitchOffer: Equatable {
    var uuid: String
    var email: String
    /// Its week at its last answer; nil: it hasn't answered anything yet.
    var week: Double?
}

/// A switch of the chat's profile to another account, shown where the limit notice would be.
enum QuickChatSwitchNotice: Equatable {
    /// Claude Code's sign-in is open in Terminal; the folder is looked at every 2 s.
    case waiting(wanted: String)
    /// The browser signed in as someone else.
    case wrong(signedIn: String, wanted: String)
    /// No sign-in came in 10 minutes.
    case timedOut(wanted: String)
}

/// The chat's state, drawn by ChatViews and driven by its keys. Main thread only.
final class QuickChatModel: ObservableObject {
    @Published var turns: [QuickChatTurn] = []
    @Published var field = ""
    /// A problem shown in the bar, before the chat has a message (Claude Code missing, no profile).
    @Published var barProblem: QuickChatProblem?
    @Published var target: QuickChatTarget?
    @Published var choice: QuickChatModelChoice = .haiku
    @Published var thinking: QuickChatThinking = .off
    /// The full name each choice answered with last ("Haiku 5.5"), for its key.
    @Published var knownModels: [QuickChatModelChoice: String] = [:]
    /// Asks the field to take the keyboard.
    @Published var focusTick = 0
    /// Asks the window to scroll to the end.
    @Published var scrollTick = 0
    /// The profile's week, as Claude Code last reported it (Level.swift).
    @Published var level: QuickChatLevel?
    /// While a limit is full: the profile with the most room, for Ask on ….
    @Published var offer: QuickChatOffer?
    /// While a limit is full: the profile's standby account with the most room, for Switch to ….
    @Published var switchOffer: QuickChatSwitchOffer?
    /// A switch under way or gone wrong, in place of the limit notice.
    @Published var switchNotice: QuickChatSwitchNotice?
    /// One line after a switch: "Main is on p•••@example.com now."
    @Published var accountNote: String?
    /// Set while the turns on screen belong to a chat that has ended (its `claude` is gone): said under the chat.
    @Published var ended: QuickChatEnd?

    var isWindow: Bool { !turns.isEmpty }
    var busy: Bool { turns.last?.busy ?? false }
    var modelTitle: String { resolvedModel.entry?.displayName ?? knownModels[choice] ?? choice.title }
    /// A limit holds the account back: nothing is sent until it resets or another profile is picked.
    var blocked: Bool { level?.full() != nil }

    // set by QuickChat
    var resolveClaude: (@escaping (String?) -> Void) -> Void = { $0(nil) }
    var hide: () -> Void = {}
    var openSettings: (String?) -> Void = { _ in }
    var defaults: () -> QuickChatSettings = { .init() }
    /// The profiles the picker offers, with their levels.
    var pickable: () -> [(Profile, QuickChatLevel?)] = { [] }
    /// Another profile was picked: the controller moves the chat there.
    var pickProfile: (String) -> Void = { _ in }
    /// Claude Code reported the account's limits after an answer: the profile, its account's uuid, the level.
    var levelReported: (String, String, QuickChatLevel) -> Void = { _, _, _ in }
    /// The field has more or fewer lines now: the panel may need to grow to hold it (QuickChat.fit).
    var fieldChanged: () -> Void = {}
    /// An answer failed to authenticate (true) or worked (false), on the account the `claude` started on: profile, account.
    var authResult: (String, String, Bool) -> Void = { _, _, _ in }
    /// Switch to …: the controller asks first, then opens Claude Code's sign-in and watches the folder.
    var switchTo: (QuickChatSwitchOffer) -> Void = { _ in }
    /// Sign in again, as the account that was wanted (after another one signed in).
    var signInAgain: () -> Void = {}
    /// Stop waiting for a sign-in, or forget one that went wrong.
    var dropSwitch: () -> Void = {}
    /// Sign in to the profile's folder (its Claude Code isn't signed in).
    var signIn: (String) -> Void = { _ in }
    /// The profile's target with its folder's file read again (off the main thread), before a message is sent.
    var freshTarget: (String, @escaping (QuickChatTarget?) -> Void) -> Void = { _, done in done(nil) }

    private var process: QuickChatProcess?
    private var processKey = ""
    /// The account the running `claude` started on: what it reports belongs to it, and the chat goes on only on it.
    private var trail = AccountTrail()
    /// The model and thinking the running `claude` has now; the pickers change them with control requests.
    private var appliedModel = "", appliedEffort: String?
    /// The question being answered reached `claude` (not still waiting for the folder to be read or `claude` to be found).
    private var messageSent = false
    /// Answers Stop gave up on whose `done` is still to come (see StaleAnswers), and the wait's limit.
    private var stale = StaleAnswers()
    private var staleTimer: Timer?
    private var pending = "", pendingThinking = ""
    private var flushWork: DispatchWorkItem?
    private var idleTimer: Timer?
    /// The account line last drawn as full: a limit that resets is drawn again even though its numbers didn't change.
    private var drawnBlocked = false
    /// Counts new chats: a look for claude that finishes after the chat moved on starts nothing.
    private var generation = 0
    /// A chat ends this long after its last answer (window open or hidden); nothing is kept.
    static let idleSeconds: TimeInterval = 15 * 60
    /// Stop waits this long without a word from Claude Code for it to end the answer (longer while it has said nothing
    /// yet, a cold start); then the chat ends instead of hanging.
    static let stopSeconds: TimeInterval = 5
    static let coldStopSeconds: TimeInterval = 20
    /// The last line `claude` printed, and whether this `claude` has printed any.
    private var lastEvent = Date.distantPast
    private var spoken = false
    /// The `set_model` requests in flight (id → the model asked), and the model Claude Code last confirmed it runs.
    private var modelRequests: [String: String] = [:]
    private var confirmedModel = ""

    // MARK: keys

    func send() {
        let q = field.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !busy, !blocked else { return }
        guard target != nil else { barProblem = .noProfile; return }
        field = ""
        barProblem = nil
        // the chat on screen ended: this message starts a new one, with nothing from the old one
        if ended != nil { turns = []; ended = nil; accountNote = nil }
        turns.append(QuickChatTurn(question: q, thinkingTitle: effectiveThinking.effort == nil ? nil : effectiveThinking.title))
        scrollTick += 1
        ask(q)
    }

    /// Stop: the answer ends where it is and the chat goes on, the conversation staying in the same `claude` (an
    /// interrupt control request). If it can't be asked, or doesn't end the answer in a few seconds, the chat ends.
    func stop() {
        guard busy, let i = turns.indices.last else { return }
        flush()
        turns[i].phase = .stopped
        turns[i].seconds = Date().timeIntervalSince(turns[i].started)
        pending = ""; pendingThinking = ""
        // a message still waiting for its folder to be read (ask()) is let go: Retry or a new message asks on its own
        generation += 1
        // one that never reached `claude` needs no interrupt
        guard messageSent, let p = process, p.isRunning else { return }
        messageSent = false
        stale.abandon()
        if p.interrupt() { armStale() } else { endChat(.stopped) }
    }

    /// Retry a failed answer, or ask the last question again. A chat that ended is gone: the question is asked in a new one.
    func again() {
        guard !busy, let i = turns.indices.last else { return }
        if ended != nil {
            let q = turns[i].question
            turns = [QuickChatTurn(question: q, thinkingTitle: effectiveThinking.effort == nil ? nil : effectiveThinking.title)]
            ended = nil; accountNote = nil
            scrollTick += 1
            ask(q)
            return
        }
        turns[i].answer = ""; turns[i].thinking = ""; turns[i].problem = nil; turns[i].phase = .waiting
        turns[i].started = Date(); turns[i].seconds = nil
        turns[i].thinkingTitle = effectiveThinking.effort == nil ? nil : effectiveThinking.title
        scrollTick += 1
        ask(turns[i].question)
    }

    /// A new chat: the process goes and the old chat with it (nothing was saved), the pickers go back to the defaults.
    /// `keepField`: what you typed stays (another profile was picked). `dropsSwitch`: a switch of account under way or
    /// gone wrong is forgotten too (not when the chat starts anew because the account changed, which is what it says).
    func newChat(keepField: Bool = false, dropsSwitch: Bool = true) {
        generation += 1
        closeProcess()
        ended = nil
        turns = []
        if !keepField { field = "" }
        barProblem = nil
        accountNote = nil
        if dropsSwitch { dropSwitch() }
        let d = defaults()
        choice = d.model; thinking = d.thinking
        focusTick += 1
    }

    /// The pickers: from the next message on (the running `claude` is told, so the chat keeps its conversation).
    func choose(_ c: QuickChatModelChoice) { choice = c; focusTick += 1 }
    func choose(_ t: QuickChatThinking) { thinking = t; focusTick += 1 }

    /// The ⌥⌘ arrows: the model a family up or down among those the account has, thinking a step up or down among the
    /// model's. Past either end nothing changes (false). The keyboard stays where it is (a selected answer keeps its
    /// selection); a click on a control goes through choose(), which hands the keyboard back to the field.
    @discardableResult func stepModel(_ by: Int) -> Bool {
        guard let c = QuickChatModels.step(modelChoices.map(\.choice), from: resolvedModel.family, by: by) else { return false }
        choice = c
        return true
    }
    @discardableResult func stepThinking(_ by: Int) -> Bool {
        guard let t = QuickChatModels.step(thinkingSteps, from: effectiveThinking, by: by) else { return false }
        thinking = t
        return true
    }

    /// Ask on …: the chat moves to the profile offered and sends the question there. The full one isn't changed.
    func askOnOffer() {
        guard let o = offer else { return }
        let q = pendingQuestion()
        pickProfile(o.profileID)
        field = q
        send()
    }

    /// What would be asked again on another profile or account: what's typed, else the question a full limit stopped.
    func pendingQuestion() -> String {
        field.isEmpty ? (turns.last?.problem == .limitFull ? turns.last?.question ?? "" : "") : field
    }

    /// The profile is on another account now: a new chat on the same profile (a chat may not go on across accounts),
    /// what was typed (or the question the full limit stopped) is sent, and one line says where it is.
    /// The caller has set the new target.
    func continueSwitched(note: String) {
        let q = pendingQuestion()
        newChat(keepField: true)
        field = q
        accountNote = note
        send()
    }

    /// The profile's folder is on another account than this chat's. A chat belongs to its account, so a new chat
    /// starts on the same profile; what was typed (or the question a full limit stopped) stays in the field, and one
    /// line says where it is. Not while an answer is on its way: the next message meets the same rule in ask().
    func accountChanged(to t: QuickChatTarget) {
        let q = pendingQuestion()
        newChat(keepField: true, dropsSwitch: false)
        field = q
        forgetAccount()
        target = t
        accountNote = "\(t.name) is on \(maskEmail(t.email ?? "another account")) now."
    }

    /// The chat's profile points at another folder now (a profile removed and added again on another folder, say): its
    /// `claude` was started on the old one, and the conversation lives only in it, so the chat ends and a new one starts
    /// on the same profile. What was typed stays.
    func folderChanged(to t: QuickChatTarget) {
        let q = pendingQuestion()
        newChat(keepField: true, dropsSwitch: false)
        field = q
        forgetAccount()
        target = t
        accountNote = "\(t.name) uses another folder now. New chat."
    }

    /// The chat's profile was removed: the chat ends with its `claude` (nothing is left running for a profile that's gone).
    func profileRemoved() {
        guard target != nil else { return }
        newChat(keepField: true)
        forgetAccount()
        target = nil
    }

    /// Another profile: its own account line, nothing carried over from the last one.
    func forgetAccount() { level = nil; offer = nil; switchOffer = nil; switchNotice = nil; drawnBlocked = false }

    /// The profile, its account and its level as they are now, the offers while its limit is full, and a switch under way.
    func update(target new: QuickChatTarget?, level: QuickChatLevel?, offer: QuickChatOffer?,
                switchOffer: QuickChatSwitchOffer? = nil, notice: QuickChatSwitchNotice? = nil) {
        if new != target { target = new }
        if level != self.level { self.level = level }
        else if drawnBlocked != blocked { objectWillChange.send() }     // a full limit reset: drawn again
        drawnBlocked = blocked
        let o = blocked ? offer : nil
        if o != self.offer { self.offer = o }
        let s = blocked ? switchOffer : nil
        if s != self.switchOffer { self.switchOffer = s }
        if notice != self.switchNotice { self.switchNotice = notice }
    }

    // MARK: talking to Claude Code

    private func ask(_ q: String) {
        guard let first = target else { fail(.noProfile); return }
        let gen = generation
        messageSent = false
        resolveClaude { [weak self] path in
            guard let self, gen == self.generation else { return }
            guard let path else { self.fail(.notInstalled); return }
            // the folder may have changed account since the chat last looked: its file is read again (off the main thread)
            self.freshTarget(first.profileID) { fresh in
                guard gen == self.generation, let i = self.turns.indices.last, self.turns[i].busy else { return }     // stopped meanwhile
                // the profile is gone (removed while the folder was being read): nothing to ask on
                guard fresh != nil else { self.fail(.noProfile); return }
                if let fresh, fresh != self.target {
                    let was = self.target?.accountUUID
                    self.target = fresh
                    // the folder moved to another account: the account line starts over and says where it is
                    if let was, let now = fresh.accountUUID, was != now {
                        self.forgetAccount()
                        self.accountNote = "\(fresh.name) is on \(maskEmail(fresh.email ?? "another account")) now."
                    }
                }
                guard let target = self.target else { self.fail(.noProfile); return }
                self.start(q, path: path, target: target)
            }
        }
    }

    private func start(_ q: String, path: String, target: QuickChatTarget) {
        let cmd = QuickChatCommand(claude: path, configDir: target.configDir, isDefaultDir: target.isDefaultDir,
                                   workFolder: target.workFolder, model: resolvedModel.value, effort: effectiveThinking.effort)
        // the same `claude` while what it runs on is the same: the conversation lives only in it. The model and thinking
        // aren't part of the key, they're changed in the running one. The account's uuid, not just its address: two
        // accounts may share one, and must not share a running claude.
        let key = [path, target.configDir, target.workFolder, target.accountUUID ?? target.email ?? ""].joined(separator: "|")
        let goesOn = process?.isRunning == true && key == processKey && trail.canContinue(on: target.accountUUID)
        if goesOn {
            if cmd.model != appliedModel {
                if let id = process?.setModel(cmd.model) { modelRequests[id] = cmd.model }
                appliedModel = cmd.model
            }
            if cmd.effort != appliedEffort { process?.setThinking(cmd.effort); appliedEffort = cmd.effort }
        } else {
            // another account, folder or `claude`, or none running: a new chat begins, so nothing said before is on
            // screen as if the new `claude` knew it
            closeProcess()
            if turns.count > 1, let last = turns.last {
                turns = [last]
                accountNote = (accountNote.map { $0 + " " } ?? "") + "New chat; nothing from the last one was carried over."
            }
            let p = QuickChatProcess(cmd)
            p.onEvent = { [weak self, weak p] e in guard let self, let p, p === self.process else { return }; self.handle(e) }
            p.onExit = { [weak self, weak p] status, tail in
                guard let self, let p, p === self.process else { return }
                self.exited(status, tail)
            }
            do { try p.start() } catch {
                fail(.stopped(detail: "Claude Code couldn't start: \(error.localizedDescription)")); return
            }
            process = p
            p.initialize()          // the account's models, for the pickers (nothing goes to a model)
            processKey = key
            appliedModel = cmd.model
            confirmedModel = cmd.model
            appliedEffort = cmd.effort
            trail.processStarted(on: target.accountUUID)      // what it reports belongs to this account
        }
        idleTimer?.invalidate()
        messageSent = process?.send(q) == true
        if !messageSent { fail(.stopped(detail: "Claude Code didn't take the message.")) }
    }

    private func handle(_ e: QuickChatEvent) {
        lastEvent = Date(); spoken = true
        guard let i = turns.indices.last else { return }
        // what Claude Code still says about an answer Stop gave up on is dropped, up to its `done`
        switch stale.fate(of: e) {
        case .pass: break
        case .drop: return
        case .endsOne:
            if !stale.waiting {
                staleTimer?.invalidate(); staleTimer = nil
                if !busy { armIdle() }
            }
            return
        }
        switch e {
        case .started(_, let model):
            if !model.isEmpty { setModel(model, turn: i) }
        case .text(let t):
            // the answer begins: how long it thought before
            if turns[i].thinkingTitle != nil, turns[i].thinkingSeconds == nil, turns[i].answer.isEmpty, pending.isEmpty {
                turns[i].thinkingSeconds = Date().timeIntervalSince(turns[i].started)
            }
            pending += t
            scheduleFlush()
        case .thinking(let t):
            pendingThinking += t
            scheduleFlush()
        case .message(let text, let model, let error):
            if !model.isEmpty, !model.hasPrefix("<") { setModel(model, turn: i) }
            if error == "authentication_failed", let target {
                turns[i].problem = .notSignedIn(profile: target.name, id: target.profileID)
                if let u = trail.reportAccount { authResult(target.profileID, u, true) }
            } else if QuickChatParse.isLimit(error: error, text: text) {
                turns[i].problem = .limitFull
            } else if let error, turns[i].answer.isEmpty, pending.isEmpty {
                turns[i].problem = .refused(text: text.isEmpty ? error : text)
            }
        case .limit(let type, let used, let status, let resets):
            var l = level ?? QuickChatLevel()
            l.apply(type: type, used: used, status: status, resets: resets)
            reportLevel(l)
        case .done(let isError, let text, let ms, _):
            flush()
            guard turns[i].busy else { return }
            messageSent = false
            turns[i].seconds = ms > 0 ? Double(ms) / 1000 : Date().timeIntervalSince(turns[i].started)
            if isError, turns[i].problem == nil, QuickChatParse.isLimit(error: nil, text: text) { turns[i].problem = .limitFull }
            if isError || turns[i].problem != nil {
                turns[i].phase = .failed
                if turns[i].problem == nil { turns[i].problem = .refused(text: text.isEmpty ? "Claude Code couldn't answer." : text) }
                // a full limit Claude Code refused on before it reported one: the account line says so too
                if turns[i].problem == .limitFull, level?.full() == nil {
                    var l = level ?? QuickChatLevel()
                    l.refusedUntil = l.refusedUntil ?? Date().addingTimeInterval(3600)
                    reportLevel(l)
                }
            } else {
                if turns[i].answer.isEmpty { turns[i].answer = text }
                turns[i].phase = .done
                if let t = target, let u = trail.reportAccount { authResult(t.profileID, u, false) }      // it signed in fine
            }
            // the chat may have ended meanwhile (reporting the level can refresh the profile): nothing more to draw
            guard turns.indices.contains(i) else { return }
            scrollTick += 1
            // a `claude` that says it isn't signed in is let go: Retry (after signing in) asks in a new chat
            if case .notSignedIn? = turns[i].problem { endChat(.failed) } else { armIdle() }
        case .control(let id, let error, _):
            // a refused `set_model` leaves the model Claude Code confirmed last answering, so the next message asks again
            if let asked = modelRequests.removeValue(forKey: id) {
                if error == nil { confirmedModel = asked }
                else if appliedModel == asked { appliedModel = confirmedModel }
            }
        case .models(let list):
            // the account this `claude` started on: its models (the next message asks for the newest of the family)
            if let t = target { ModelCatalog.shared.set(list, profile: t.profileID, account: trail.reportAccount ?? t.accountUUID) }
            objectWillChange.send()
        case .ignored:
            break
        }
    }

    /// What Claude Code said about its limits is the account the `claude` started on, not whatever the target says now
    /// (the folder may have changed account while the answer was on its way). The account line shows it only while the
    /// target is still that account.
    private func reportLevel(_ l: QuickChatLevel) {
        guard let t = target, let u = trail.reportAccount else { return }
        if u == t.accountUUID { level = l }
        levelReported(t.profileID, u, l)
    }

    /// The model an answer came from, as Claude Code says it. It names the picker's choice only when it is that family: a
    /// `set_model` Claude Code refused leaves the old model answering, and that name isn't the new choice's.
    private func setModel(_ id: String, turn i: Int) {
        let name = QuickChatParse.modelName(id)
        turns[i].model = name
        if name.lowercased().hasPrefix(choice.rawValue) { knownModels[choice] = name }
    }

    private func exited(_ status: Int32, _ tail: String) {
        // the conversation lived only in this process: it is gone with it. What it printed last is drawn first.
        flush()
        closeProcess()
        guard !turns.isEmpty else { return }
        guard let i = turns.indices.last, turns[i].busy else { ended = ended ?? .closed; return }
        var detail = "claude exited with code \(status)"
        if !tail.isEmpty { detail += ": \(tail)" }
        fail(.stopped(detail: detail))
    }

    /// The chat ends: its `claude` goes and the turns stay on screen to read, with a line saying why. The next message
    /// (or Retry, which asks the last question) starts a new chat.
    private func endChat(_ kind: QuickChatEnd) {
        closeProcess()
        guard !turns.isEmpty else { return }
        ended = kind
    }

    /// 15 minutes with no message: the chat ends, window open or hidden.
    private func armIdle() {
        idleTimer?.invalidate()
        let t = Timer(timeInterval: Self.idleSeconds, repeats: false) { [weak self] _ in
            guard let self, !self.busy, self.process != nil, !self.stale.waiting else { return }
            self.endChat(.idle)
        }
        t.tolerance = 30
        RunLoop.main.add(t, forMode: .common)
        idleTimer = t
    }

    /// Stop was asked and Claude Code hasn't ended the answer: the chat ends instead of hanging on it. It is silence that
    /// counts: 5 seconds with nothing from `claude`, or 20 while it has not said anything yet (a cold start); every line
    /// it prints, the aborted answer's included, starts the wait over; but never more than a minute in all.
    private func armStale() {
        staleTimer?.invalidate()
        let from = Date()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
            guard let self, self.stale.waiting else { timer.invalidate(); return }
            let limit = self.spoken ? Self.stopSeconds : Self.coldStopSeconds
            guard Date().timeIntervalSince(max(self.lastEvent, from)) >= limit || Date().timeIntervalSince(from) >= 60 else { return }
            timer.invalidate()
            if self.busy { self.fail(.stopped(detail: "Claude Code didn't stop the answer in time.")) } else { self.endChat(.stopped) }
        }
        RunLoop.main.add(t, forMode: .common)
        staleTimer = t
    }

    private func fail(_ p: QuickChatProblem) {
        guard let i = turns.indices.last, turns[i].busy else {
            if turns.isEmpty { barProblem = p }
            return
        }
        // nothing asked yet and Claude Code isn't there: the bar says so and keeps the question
        if p == .notInstalled || p == .noProfile, turns.count == 1, turns[i].answer.isEmpty {
            field = turns[i].question
            turns = []
            barProblem = p
            return
        }
        turns[i].phase = .failed
        turns[i].problem = p
        turns[i].seconds = Date().timeIntervalSince(turns[i].started)
        scrollTick += 1
        // `claude` stopped or isn't signed in: its conversation is gone, Retry asks this question in a new chat
        switch p {
        case .stopped, .notSignedIn: endChat(.failed)
        default: break
        }
    }

    private func closeProcess() {
        idleTimer?.invalidate(); idleTimer = nil
        staleTimer?.invalidate(); staleTimer = nil
        stale.reset()
        messageSent = false
        spoken = false; lastEvent = .distantPast
        modelRequests = [:]
        process?.onEvent = { _ in }
        process?.onExit = { _, _ in }
        process?.stop()
        process = nil
        processKey = ""
        trail.processEnded()
        pending = ""; pendingThinking = ""
    }

    /// Answer pieces are drawn at most every 50 ms.
    private func scheduleFlush() {
        guard flushWork == nil else { return }
        let w = DispatchWorkItem { [weak self] in self?.flush() }
        flushWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: w)
    }

    private func flush() {
        flushWork?.cancel(); flushWork = nil
        guard let i = turns.indices.last, !pending.isEmpty || !pendingThinking.isEmpty else { return }
        if turns[i].busy {
            turns[i].answer += pending
            turns[i].thinking += pendingThinking
            if !pending.isEmpty { turns[i].phase = .streaming }
            scrollTick += 1
        }
        pending = ""; pendingThinking = ""
    }

    /// Shut down (cl_quick quits).
    func shutdown() { closeProcess() }
}

// MARK: - The controller

final class QuickChat {
    static let shared = QuickChat()

    let model = QuickChatModel()
    let store = ProfileStore.shared
    let switcher = AccountSwitcher.shared
    private(set) var settings = QuickChatSettings.load()
    private var panel: QuickChatPanel?
    private var claudePath: String?
    private var looking: [(String?) -> Void] = []
    private var placed = false
    private weak var host: QuickChatHostingView?
    private var modeWatch: AnyCancellable?
    /// The chat's height as the user left it (for this run, like the place and the width). nil: the first height.
    private var chatHeight: CGFloat?
    /// The panel's top edge as it was when the bar turned into the chat (or back): fit() puts it back.
    private var topAnchor: CGFloat?
    /// How much taller than its content the user made the bar (for this run).
    private var barExtra: CGFloat = 0
    /// Whether the panel is already sized for the chat: from then on the size is the user's, and fit() leaves it alone.
    private var sizedForChat = false
    private let hotKey = QuickChatHotKey()
    /// The shortcut: "on", or why it isn't registered; nil while it's turned off. Shown in Settings.
    private(set) var shortcutState: String?
    /// Opens Settings (main.swift), on a profile's card or General.
    var openSettings: (String?) -> Void = { _ in }

    var isOpen: Bool { panel?.isVisible == true }

    func start() {
        model.choice = settings.model
        model.thinking = settings.thinking
        model.resolveClaude = { [weak self] done in self?.resolveClaude(done) ?? done(nil) }
        model.hide = { [weak self] in self?.hide() }
        model.openSettings = { [weak self] id in self?.openSettings(id) }
        model.defaults = { [weak self] in self?.settings ?? .init() }
        model.pickable = { [weak self] in
            guard let self else { return [] }
            return self.store.profiles.filter(\.inPicker).map { ($0, self.store.level(of: $0)) }
        }
        model.pickProfile = { [weak self] id in self?.move(to: id) }
        // refresh() may end the chat (profile removed, account or folder changed): never from inside the answer's own handling
        model.fieldChanged = { [weak self] in DispatchQueue.main.async { self?.fit() } }
        model.levelReported = { [weak self] id, account, l in
            self?.store.record(id, account: account, l)
            DispatchQueue.main.async { self?.refresh() }
        }
        // the flag is only set or cleared here (the store publishes it to Settings); no refresh, so nothing ends the chat
        model.authResult = { [weak self] id, account, failed in self?.store.authResult(id, account: account, failed: failed) }
        model.switchTo = { [weak self] o in
            guard let self, let id = self.model.target?.profileID, let p = self.store.profile(id) else { return }
            self.switcher.confirmAndSwitch(p, uuid: o.uuid, email: o.email, origin: .chat)
            self.panel?.makeKey()
        }
        model.signInAgain = { [weak self] in
            guard let self, let id = self.model.target?.profileID, let p = self.store.profile(id),
                  let m = self.switcher.ended[id] else { return }
            self.switcher.begin(p, uuid: m.goal.wantedUUID, email: m.goal.wantedEmail, origin: .chat)
        }
        model.dropSwitch = { [weak self] in
            if let id = self?.model.target?.profileID { self?.switcher.drop(id) }
        }
        model.signIn = { [weak self] id in
            guard let p = self?.store.profile(id) else { return }
            SignIn.open(folder: p.path) { why in if let why { SignIn.tell(why) } }
        }
        model.freshTarget = { [weak self] id, done in
            guard let self, let p = self.store.profile(id) else { done(nil); return }
            ClaudeFolder.reload([p.path]) { _ in
                self.store.noteAccount(of: id)
                done(self.store.profile(id).map(QuickChatTarget.init))
                self.refresh()          // the account line, offers and notices of the account now in use
            }
        }
        switcher.onOutcome = { [weak self] goal, outcome in self?.switched(goal, outcome) }
        NotificationCenter.default.addObserver(forName: AccountSwitcher.changed, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        hotKey.onPress = { [weak self] in self?.toggle() }
        applyShortcut()
    }

    /// A switch begun in the chat ended. On the account wanted: a new chat on the same profile sends what was typed;
    /// on another one, the notice says so. A switch begun in Settings only updates the account line.
    private func switched(_ goal: SwitchGoal, _ outcome: SwitchOutcome) {
        guard goal.origin == .chat, outcome == .reached, !goal.again, model.target?.profileID == goal.profileID,
              let p = store.profile(goal.profileID) else { refresh(); return }
        model.forgetAccount()
        model.target = QuickChatTarget(p)          // the account signed in now: its address and uuid, for the next `claude`
        refresh()
        model.continueSwitched(note: "\(p.name) is on \(maskEmail(model.target?.email ?? goal.wantedEmail)) now.")
        if !isOpen { open(profile: p.id) }
    }

    /// Settings changed (the settings window): the shortcut is registered again and the next new chat uses the defaults.
    func settingsChanged(_ s: QuickChatSettings) {
        settings = s
        s.save()
        applyShortcut()
    }

    /// The chat's profile, its account and its level now, and while its limit is full the profile with the most room.
    func refresh() {
        guard let id = model.target?.profileID, store.profile(id) != nil else {
            model.profileRemoved()
            model.update(target: nil, level: nil, offer: nil)
            return
        }
        store.noteAccount(of: id)
        guard let p = store.profile(id) else { return }
        // the profile uses another folder (or work folder) than the chat's: its `claude` is on the old one, so a new chat
        // starts. While an answer is on its way the next message meets the same rule in start().
        let now = QuickChatTarget(p)
        if let old = model.target, old.profileID == id, old.configDir != now.configDir || old.workFolder != now.workFolder, !model.busy {
            model.folderChanged(to: now)
        }
        // the folder is on another account than the chat's (a switch from Settings, a sign-in as someone else, Sign in
        // again…, or one outside cl_quick): a chat belongs to its account, so a new chat starts and says so
        if let old = model.target, old.profileID == id, let was = old.accountUUID, let to = now.accountUUID, was != to, !model.busy {
            model.accountChanged(to: now)
        }
        // the most room first; one that hasn't answered anything yet comes after, as it may have room too
        let others = store.profiles.filter { $0.inPicker && $0.id != id }
            .compactMap { o -> QuickChatOffer? in
                guard let l = store.level(of: o) else { return QuickChatOffer(profileID: o.id, name: o.name, week: nil) }
                guard l.full() == nil else { return nil }
                return QuickChatOffer(profileID: o.id, name: o.name, week: l.weekNow())
            }
            .sorted { ($0.week ?? 101) < ($1.week ?? 101) }
        // the same for the profile's own standby accounts (the most recently seen first among equals)
        let standby = store.standby(p).enumerated()
            .compactMap { i, a -> (Int, QuickChatSwitchOffer)? in
                let l = store.level(of: p, account: a.uuid)
                guard l?.full() == nil else { return nil }
                return (i, QuickChatSwitchOffer(uuid: a.uuid, email: a.email, week: l?.weekNow()))
            }
            .sorted { a, b in
                let x = a.1.week ?? 101, y = b.1.week ?? 101
                return x != y ? x < y : a.0 < b.0
            }
        let notice: QuickChatSwitchNotice? = switcher.waiting[id].map { .waiting(wanted: $0.wantedEmail) }
            ?? switcher.ended[id].map { e in
                e.signedIn.map { .wrong(signedIn: $0, wanted: e.goal.wantedEmail) } ?? .timedOut(wanted: e.goal.wantedEmail)
            }
        model.update(target: now, level: store.level(of: p), offer: others.first,
                     switchOffer: standby.first?.1, notice: notice)
    }

    func toggle() { isOpen ? hide() : open() }

    private func applyShortcut() {
        hotKey.unregister()
        // a shortcut that could never have been kept (a hand-edited settings.json): ⌥Space instead
        if settings.shortcut.refused != nil { settings.shortcut = .optionSpace }
        // (not while only checking: `Files.readOnly`, so a check never takes the shortcut from the installed app)
        shortcutState = settings.shortcutOn && !Files.readOnly ? (hotKey.register(settings.shortcut) ?? "on") : nil
    }

    /// While a new shortcut is recorded the current one is let go, so any keys can be pressed; then it's back.
    func pauseShortcut(_ paused: Bool) { if paused { hotKey.unregister() } else { applyShortcut() } }

    /// Opens the bar (or the chat as it was) over whatever is in front. `profile`: chat on that one.
    /// The shortcut names none: a chat under way stays on its profile, a new one goes to the default profile.
    func open(profile: String? = nil) {
        let list = store.profiles
        let wanted = profile ?? (model.isWindow ? model.target?.profileID : nil) ?? settings.defaultProfile
        let pick = list.first { $0.id == wanted } ?? list.first
        if let t = model.target, let p = pick, t.profileID != p.id { model.newChat(); model.forgetAccount() }
        // the same profile keeps its target: refresh() sees whether its folder moved to another account since
        if model.target?.profileID != pick?.id { model.target = pick.map(QuickChatTarget.init) }
        refresh()
        if pick != nil, model.barProblem == .noProfile { model.barProblem = nil }
        let p = panel ?? makePanel()
        // where the user left it stays (for this run); the first time, or when that place is on no screen now: centred
        if !placed || !isOnScreen(p) { place(p); placed = true }
        clampToScreen(p)
        p.orderFrontRegardless()
        p.makeKey()
        model.focusTick += 1
        store.reload(pick.map { [$0.id] })      // the account may have changed since: read off the main thread, drawn again
        if claudePath == nil { resolveClaude { _ in } }   // look early, off the main thread
    }

    /// The profile picker: a new chat on that profile; what you typed stays.
    private func move(to id: String) {
        guard let p = store.profile(id), p.id != model.target?.profileID else { return }
        model.newChat(keepField: true)
        model.forgetAccount()
        model.target = QuickChatTarget(p)
        refresh()
    }

    func hide() { panel?.orderOut(nil) }

    func shutdown() { hotKey.unregister(); model.shutdown() }

    /// Its data is about to go (Remove cl_quick data…): the chat closes and its claude with it.
    func closeForRemoval() { hide(); model.newChat(); model.forgetAccount() }

    private func makePanel() -> QuickChatPanel {
        let p = QuickChatPanel()
        p.onEscape = { [weak self] in self?.hide() }
        p.onNewChat = { [weak self] in self?.model.newChat() }
        p.onStep = { [weak self] model, by in
            guard let m = self?.model else { return }
            if model { m.stepModel(by) } else { m.stepThinking(by) }
        }
        p.onResized = { [weak self] in
            guard let self, let p = self.panel, let host = self.host else { return }
            // the user finished sizing it (macOS's own live resize): the chat keeps its height; the bar keeps the height it
            // was given beyond its content's; both keep the width (the frame's own)
            if self.model.isWindow { self.chatHeight = p.frame.height }
            else { self.barExtra = max(0, p.frame.height - max(0, host.intrinsicContentSize.height)) }
            self.keepOnScreen(p)
        }
        // macOS does the sizing: the panel is resizable, and the content's own frames (QuickChatRoot: from 320 wide, the
        // chat from 220 tall, the bar from its content's height) are the window's least size
        let host = QuickChatHostingView(rootView: QuickChatRoot(model: model))
        host.onIntrinsicChange = { [weak self] in self?.fit() }
        p.contentView = host
        panel = p
        self.host = host
        // the first message turns the bar into the chat, ⌘N back
        // (this runs just BEFORE the change: the top edge is noted then, as the content's new least height may already have
        // moved the frame by the time fit() runs)
        modeWatch = model.$turns.map { !$0.isEmpty }.removeDuplicates().dropFirst()
            .sink { [weak self] _ in
                if let p = self?.panel, p.isIdle { self?.topAnchor = p.frame.maxY }
                DispatchQueue.main.async { self?.fit() }
            }
        return p
    }

    /// Sets the panel's HEIGHT from what the content and the user say, the top edge staying where it is. It never touches the
    /// width, never runs while the user moves or resizes the panel (a move or a live resize owns the frame then), and never
    /// changes a size the user set except to hold the content:
    /// - the bar is as tall as its content (Shift-Return lines) plus what the user gave it beyond that;
    /// - the chat takes the user's height (the first one until the user sizes it) once, when the first message turns the
    ///   bar into it; after that it is the user's (the content's own least height, which macOS enforces, holds a taller field).
    /// (Internal, not private, so Checks/panel can call it.)
    func fit() {
        guard let p = panel, let host, p.isIdle else { return }
        let vis = (p.screen ?? NSScreen.main)?.visibleFrame
        let chat = model.isWindow
        if chat, sizedForChat { return }
        if !chat { sizedForChat = false }
        host.layoutSubtreeIfNeeded()         // the content for the mode we are in now, before anything is read or set
        var h: CGFloat
        if chat {
            h = chatHeight ?? QuickChatRoot.windowHeight + 2 * QuickChatRoot.margin
        } else {
            let natural = host.intrinsicContentSize.height
            guard natural > 0 else { return }      // not measured yet (NSView.noIntrinsicMetric is -1)
            h = natural + barExtra
        }
        if let vis { h = min(h, vis.height) }
        var f = p.frame
        let top = topAnchor ?? f.maxY       // the top edge where the mode change found it
        topAnchor = nil
        if abs(f.height - h) > 0.5 || abs(f.maxY - top) > 0.5 {
            f.size.height = h
            f.origin.y = top - h
            if let vis, f.minY < vis.minY { f.origin.y = vis.minY }
            p.setFrame(f, display: true)
        }
        // the chat is the user's from here on, once it really has its height (else the next change tries again)
        if chat { sizedForChat = abs(p.frame.height - h) <= 0.5 }
        p.invalidateShadow()
    }

    /// After the user sized it: an edge dragged past the screen's visible frame (under the menu bar, over the Dock, off a
    /// side) leaves the panel back inside it. The size already fits (QuickChatPanel.windowWillResize).
    private func keepOnScreen(_ p: NSPanel) {
        guard let vis = (p.screen ?? NSScreen.main)?.visibleFrame else { return }
        var f = p.frame
        f.origin.x = min(max(f.minX, vis.minX), vis.maxX - f.width)
        f.origin.y = min(max(f.minY, vis.minY), vis.maxY - f.height)
        if f != p.frame { p.setFrame(f, display: true); p.invalidateShadow() }
    }

    /// On opening: the size held to the screen it's on (a smaller display than last time).
    private func clampToScreen(_ p: NSPanel) {
        guard let vis = (p.screen ?? NSScreen.main)?.visibleFrame else { return }
        var f = p.frame
        let w = min(f.width, vis.width), h = min(f.height, vis.height)
        guard abs(w - f.width) > 0.5 || abs(h - f.height) > 0.5 else { return }
        let top = f.maxY
        f.size = NSSize(width: w, height: h)
        f.origin.y = top - h
        p.setFrame(f, display: false)
    }

    /// The first time: centred on the screen with the mouse, its top a quarter of the way down.
    private func place(_ p: QuickChatPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let vis = screen?.visibleFrame else { return }
        let w = min(p.frame.width, vis.width)           // the size it has now: a fall-back for a lost place keeps it
        let top = vis.maxY - vis.height * 0.22
        let h = min(p.frame.height, vis.height)
        p.setFrame(NSRect(x: vis.midX - w / 2, y: max(vis.minY, top - h), width: w, height: h), display: false)
    }

    /// Whether the panel's top strip (where it's grabbed) shows on some screen, clear of the menu bar and the Dock.
    private func isOnScreen(_ p: NSPanel) -> Bool {
        let f = p.frame
        let strip = NSRect(x: f.minX, y: f.maxY - 44, width: f.width, height: 44)
        return NSScreen.screens.contains { s in
            let i = s.visibleFrame.intersection(strip)
            return !i.isNull && i.width >= 80 && i.height >= 24
        }
    }

    /// Where `claude` is: found once, off the main thread (ClaudeLocator), and again when it's gone.
    private func resolveClaude(_ done: @escaping (String?) -> Void) {
        if let p = claudePath, ClaudeLocator.isExecutable(p) { done(p); return }
        claudePath = nil
        looking.append(done)
        guard looking.count == 1 else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = ClaudeLocator.find()?.path
            DispatchQueue.main.async {
                guard let self else { return }
                self.claudePath = found
                let waiting = self.looking
                self.looking = []
                waiting.forEach { $0(found) }
            }
        }
    }
}

// MARK: - The panel

/// A floating panel that takes the keyboard without bringing cl_quick (or anything else) forward, on every Space and
/// over full-screen apps.
final class QuickChatPanel: NSPanel, NSWindowDelegate {
    var onEscape: () -> Void = {}
    var onNewChat: () -> Void = {}
    /// ⌥⌘ arrows: the model (true) or thinking (false) a step up (1) or down (-1).
    var onStep: (Bool, Int) -> Void = { _, _ in }

    // MOVING and SIZING are the user's, and macOS's: the panel is a resizable window, its resize zones are the system's (on
    // its outer edges and corners only), and moving is the drag surface's performDrag (DragSurface.swift) from any empty
    // area. While either is under way nothing else may change the frame (QuickChat.fit looks at `isIdle`).
    /// Set around a window drag (QCDragView).
    var isMoving = false
    /// Between the system's "will start" and "did end" of a live resize.
    private(set) var isLiveResizing = false
    var isIdle: Bool { !isMoving && !isLiveResizing && !inLiveResize }
    /// The user finished sizing it.
    var onResized: () -> Void = {}
    func windowWillStartLiveResize(_ n: Notification) { isLiveResizing = true }
    func windowDidEndLiveResize(_ n: Notification) {
        isLiveResizing = false
        onResized()
    }
    /// Dragging an edge never takes it past the screen it's on.
    func windowWillResize(_ sender: NSWindow, to size: NSSize) -> NSSize {
        guard let vis = (sender.screen ?? NSScreen.main)?.visibleFrame else { return size }
        return NSSize(width: min(size.width, vis.width), height: min(size.height, vis.height))
    }

    /// cl_quick has no menu bar of its own, so the Edit keys are handled here: cut, copy, paste, select all, undo and
    /// redo go to whatever has the keyboard (the field, or a selected answer); ⌘N starts a new chat, ⌘W hides.
    override func performKeyEquivalent(with e: NSEvent) -> Bool {
        let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // ⌥⌘↑ ⌥⌘↓ step thinking, ⌥⌘→ ⌥⌘← the model: free in the field (its ⌥ and ⌘ arrows move the caret, ⌥⌘ ones
        // nothing) and not a macOS shortcut. At the last step the key does nothing and is still taken.
        if flags.intersection([.command, .option, .control, .shift]) == [.command, .option],
           let k = e.charactersIgnoringModifiers?.unicodeScalars.first.map({ Int($0.value) }) {
            switch k {
            case NSUpArrowFunctionKey: onStep(false, 1); return true
            case NSDownArrowFunctionKey: onStep(false, -1); return true
            case NSRightArrowFunctionKey: onStep(true, 1); return true
            case NSLeftArrowFunctionKey: onStep(true, -1); return true
            default: break
            }
        }
        guard flags.contains(.command), !flags.contains(.control), !flags.contains(.option),
              let key = e.charactersIgnoringModifiers?.lowercased() else { return super.performKeyEquivalent(with: e) }
        let shift = flags.contains(.shift)
        var action: Selector?
        switch key {
        case "x": action = #selector(NSText.cut(_:))
        case "c": action = #selector(NSText.copy(_:))
        case "v": action = #selector(NSText.paste(_:))
        case "a": action = #selector(NSText.selectAll(_:))
        case "z": action = shift ? Selector(("redo:")) : Selector(("undo:"))
        case "n" where !shift: onNewChat(); return true
        case "w" where !shift: onEscape(); return true
        default: break
        }
        if let action, NSApp.sendAction(action, to: nil, from: self) { return true }
        return super.performKeyEquivalent(with: e)
    }

    init() {
        // the card's width and a thin transparent margin around it, which holds the system's resize zones (they are the
        // frame's outer 3 pt on the edges, 9 pt at the corners): so none of the card's own area ever resizes it
        super.init(contentRect: NSRect(x: 0, y: 0, width: QuickChatRoot.width + 2 * QuickChatRoot.margin, height: 140),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView, .resizable], backing: .buffered, defer: false)
        delegate = self
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false     // dragging is QCDragSurface's (DragSurface.swift), from the empty areas only
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
    }

    /// With Caps Lock on, macOS (not cl_quick) puts its own round "⇪" badge under the caret, in a text-input window of its
    /// own (TUINSWindow, a remote view) that it adds to the key window as a child. In the bar that lands on the picker row, so
    /// that window is kept invisible; the field shows a small Caps Lock mark of its own instead (QCField).
    override func addChildWindow(_ child: NSWindow, ordered place: NSWindow.OrderingMode) {
        super.addChildWindow(child, ordered: place)
        if NSEvent.modifierFlags.contains(.capsLock), String(describing: type(of: child)).hasPrefix("TUI") {
            child.alphaValue = 0
            child.ignoresMouseEvents = true
        }
    }

    /// Caps Lock off again: a text-input window kept invisible for it is back to normal (macOS may reuse it).
    override func sendEvent(_ event: NSEvent) {
        if event.type == .flagsChanged, !event.modifierFlags.contains(.capsLock) {
            for w in childWindows ?? [] where String(describing: type(of: w)).hasPrefix("TUI") && w.alphaValue == 0 {
                w.alphaValue = 1
                w.ignoresMouseEvents = false
            }
        }
        super.sendEvent(event)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape() }
}

/// The panel's content. It doesn't drag by itself (its SwiftUI views catch the mouse): QCDragSurface does, behind them.
final class QuickChatHostingView: NSHostingView<QuickChatRoot> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Called (once per turn of the run loop) when the content's ideal size changed: a line more in the field, say.
    var onIntrinsicChange: () -> Void = {}
    private var told = false
    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        guard !told else { return }
        told = true
        DispatchQueue.main.async { [weak self] in self?.told = false; self?.onIntrinsicChange() }
    }
}
