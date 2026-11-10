// Chat: cl_quick's floating chat, its state and its controller. A bar first; the first message turns it into a chat window
// that stays floating over any app, on every Space, until Esc hides it. It never brings anything else forward.
//
// It answers through your own Claude Code (Engine.swift), on the profile you pick (Profiles.swift), on that profile's
// account in use, and counts against its limits. One `claude` at a time, closed after 2 minutes idle; the next message
// goes on with the session. The bar and the window are ChatViews.swift.

import AppKit
import SwiftUI

// MARK: - Settings

/// The model a chat answers with: a family, or whatever the profile itself uses in Claude Code.
enum QuickChatModelChoice: String, CaseIterable, Codable, Identifiable {
    case haiku, sonnet, opus, profile
    var id: String { rawValue }
    /// For `--model`; "" leaves it to the profile.
    var flag: String { self == .profile ? "" : rawValue }
    var title: String {
        switch self {
        case .haiku: return "Haiku"
        case .sonnet: return "Sonnet"
        case .opus: return "Opus"
        case .profile: return "Profile's default"
        }
    }
    /// A few words in its picker.
    func blurb(profile: String) -> String {
        switch self {
        case .haiku: return "fast, light on the week"
        case .sonnet: return "for harder questions"
        case .opus: return "the most capable; uses the week fastest"
        case .profile: return "what \(profile) uses in Claude Code"
        }
    }
}

/// How long Claude thinks before it answers: off, or Claude Code's effort.
enum QuickChatThinking: String, CaseIterable, Codable, Identifiable {
    case off, low, medium, high, xhigh
    var id: String { rawValue }
    var effort: String? { self == .off ? nil : rawValue }
    var title: String {
        switch self {
        case .off: return "Off"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .xhigh: return "Extra"
        }
    }
    var blurb: String {
        switch self {
        case .off: return "answers at once"
        case .low: return "thinks briefly first"
        case .medium: return "thinks a while first"
        case .high: return "for harder questions"
        case .xhigh: return "thinks longest; uses the week fastest"
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

    var isWindow: Bool { !turns.isEmpty }
    var busy: Bool { turns.last?.busy ?? false }
    var modelTitle: String { knownModels[choice] ?? choice.title }
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
    /// Switch to …: the controller asks first, then opens Claude Code's sign-in and watches the folder.
    var switchTo: (QuickChatSwitchOffer) -> Void = { _ in }
    /// Sign in again, as the account that was wanted (after another one signed in).
    var signInAgain: () -> Void = {}
    /// Stop waiting for a sign-in, or forget one that went wrong.
    var dropSwitch: () -> Void = {}
    /// Sign in to the profile's folder (its Claude Code isn't signed in).
    var signIn: (String) -> Void = { _ in }

    private var process: QuickChatProcess?
    private var processKey = ""
    private var session: String?
    /// The current `claude` started its session (its first line came): one that ends before can't go on with it.
    private var processStarted = false
    private var pending = "", pendingThinking = ""
    private var flushWork: DispatchWorkItem?
    private var idleTimer: Timer?
    /// The account line last drawn as full: a limit that resets is drawn again even though its numbers didn't change.
    private var drawnBlocked = false
    /// Counts new chats: a look for claude that finishes after the chat moved on starts nothing.
    private var generation = 0
    /// A `claude` sits idle this long after an answer, then it's closed; the next message goes on with the session.
    static let idleSeconds: TimeInterval = 2 * 60

    // MARK: keys

    func send() {
        let q = field.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !busy, !blocked else { return }
        guard target != nil else { barProblem = .noProfile; return }
        field = ""
        barProblem = nil
        turns.append(QuickChatTurn(question: q, thinkingTitle: thinking.effort == nil ? nil : thinking.title))
        scrollTick += 1
        ask(q)
    }

    /// Stop: the answer ends where it is; the session goes on with the next message.
    func stop() {
        guard busy, let i = turns.indices.last else { return }
        flush()
        turns[i].phase = .stopped
        turns[i].seconds = Date().timeIntervalSince(turns[i].started)
        // the process goes at once, so the next message never meets one still stopping; the session stays
        closeProcess()
    }

    /// Retry a failed answer, or ask the last question again.
    func again() {
        guard !busy, let i = turns.indices.last else { return }
        turns[i].answer = ""; turns[i].thinking = ""; turns[i].problem = nil; turns[i].phase = .waiting
        turns[i].started = Date(); turns[i].seconds = nil
        turns[i].thinkingTitle = thinking.effort == nil ? nil : thinking.title
        scrollTick += 1
        ask(turns[i].question)
    }

    /// A new chat: the process goes, the session stays in Claude Code's folder, the pickers go back to the defaults.
    /// `keepField`: what you typed stays (another profile was picked).
    func newChat(keepField: Bool = false) {
        generation += 1
        closeProcess()
        session = nil
        turns = []
        if !keepField { field = "" }
        barProblem = nil
        accountNote = nil
        dropSwitch()
        let d = defaults()
        choice = d.model; thinking = d.thinking
        focusTick += 1
    }

    /// The pickers: from the next message on (a new `claude` goes on with the session).
    func choose(_ c: QuickChatModelChoice) { choice = c; focusTick += 1 }
    func choose(_ t: QuickChatThinking) { thinking = t; focusTick += 1 }

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

    /// The profile is on another account now: a new chat on the same profile (a session may not go on across accounts),
    /// what was typed (or the question the full limit stopped) is sent, and one line says where it is.
    /// The caller has set the new target.
    func continueSwitched(note: String) {
        let q = pendingQuestion()
        newChat(keepField: true)
        field = q
        accountNote = note
        send()
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
        guard let target else { fail(.noProfile); return }
        let gen = generation
        resolveClaude { [weak self] path in
            guard let self, gen == self.generation else { return }
            guard let path else { self.fail(.notInstalled); return }
            let cmd = QuickChatCommand(claude: path, configDir: target.configDir, isDefaultDir: target.isDefaultDir,
                                       workFolder: target.workFolder, model: self.choice.flag, effort: self.thinking.effort,
                                       resume: self.session)
            // the same `claude` while nothing it runs with changed; a new one goes on with the session
            let key = [path, target.configDir, target.email ?? "", cmd.model, cmd.effort ?? ""].joined(separator: "|")
            if self.process?.isRunning != true || key != self.processKey {
                self.closeProcess()
                let p = QuickChatProcess(cmd)
                p.onEvent = { [weak self, weak p] e in guard let self, let p, p === self.process else { return }; self.handle(e) }
                p.onExit = { [weak self, weak p] status, tail in
                    guard let self, let p, p === self.process else { return }
                    self.exited(status, tail)
                }
                do { try p.start() } catch {
                    self.fail(.stopped(detail: "Claude Code couldn't start: \(error.localizedDescription)")); return
                }
                self.process = p
                self.processKey = key
                self.processStarted = false
            }
            self.idleTimer?.invalidate()
            if self.process?.send(q) != true { self.fail(.stopped(detail: "Claude Code didn't take the message.")) }
        }
    }

    private func handle(_ e: QuickChatEvent) {
        guard let i = turns.indices.last else { return }
        switch e {
        case .started(let s, let model):
            session = s
            processStarted = true
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
            } else if QuickChatParse.isLimit(error: error, text: text) {
                turns[i].problem = .limitFull
            } else if let error, turns[i].answer.isEmpty, pending.isEmpty {
                turns[i].problem = .refused(text: text.isEmpty ? error : text)
            }
        case .limit(let type, let used, let status, let resets):
            var l = level ?? QuickChatLevel()
            l.apply(type: type, used: used, status: status, resets: resets)
            level = l
            if let t = target, let u = t.accountUUID { levelReported(t.profileID, u, l) }
        case .done(let isError, let text, let ms, let s):
            flush()
            if !s.isEmpty { session = s }
            guard turns[i].busy else { return }
            turns[i].seconds = ms > 0 ? Double(ms) / 1000 : Date().timeIntervalSince(turns[i].started)
            if isError, turns[i].problem == nil, QuickChatParse.isLimit(error: nil, text: text) { turns[i].problem = .limitFull }
            if isError || turns[i].problem != nil {
                turns[i].phase = .failed
                if turns[i].problem == nil { turns[i].problem = .refused(text: text.isEmpty ? "Claude Code couldn't answer." : text) }
                // a full limit Claude Code refused on before it reported one: the account line says so too
                if turns[i].problem == .limitFull, level?.full() == nil {
                    var l = level ?? QuickChatLevel()
                    l.refusedUntil = l.refusedUntil ?? Date().addingTimeInterval(3600)
                    level = l
                    if let t = target, let u = t.accountUUID { levelReported(t.profileID, u, l) }
                }
            } else {
                if turns[i].answer.isEmpty { turns[i].answer = text }
                turns[i].phase = .done
            }
            scrollTick += 1
            idleTimer?.invalidate()
            idleTimer = Timer.scheduledTimer(withTimeInterval: Self.idleSeconds, repeats: false) { [weak self] _ in
                guard let self, !self.busy else { return }
                self.closeProcess()
            }
        case .ignored:
            break
        }
    }

    private func setModel(_ id: String, turn i: Int) {
        let name = QuickChatParse.modelName(id)
        turns[i].model = name
        knownModels[choice] = name
    }

    private func exited(_ status: Int32, _ tail: String) {
        process = nil
        processKey = ""
        flush()
        // it ended before its session began (a session to go on with that is gone, say): Retry starts a new one
        if !processStarted { session = nil }
        guard let i = turns.indices.last, turns[i].busy else { return }
        var detail = "claude exited with code \(status)"
        if !tail.isEmpty { detail += ": \(tail)" }
        fail(.stopped(detail: detail))
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
    }

    private func closeProcess() {
        idleTimer?.invalidate()
        process?.onEvent = { _ in }
        process?.onExit = { _, _ in }
        process?.stop()
        process = nil
        processKey = ""
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
        model.levelReported = { [weak self] id, account, l in self?.store.record(id, account: account, l); self?.refresh() }
        model.switchTo = { [weak self] o in
            guard let self, let id = self.model.target?.profileID, let p = self.store.profile(id) else { return }
            self.switcher.confirmAndSwitch(p, uuid: o.uuid, email: o.email, origin: .chat)
            self.panel?.makeKey()
        }
        model.signInAgain = { [weak self] in
            guard let self, let id = self.model.target?.profileID, let p = self.store.profile(id),
                  let m = self.switcher.mismatch[id] else { return }
            self.switcher.begin(p, uuid: m.goal.wantedUUID, email: m.goal.wantedEmail, origin: .chat)
        }
        model.dropSwitch = { [weak self] in
            if let id = self?.model.target?.profileID { self?.switcher.drop(id) }
        }
        model.signIn = { [weak self] id in
            guard let p = self?.store.profile(id) else { return }
            SignIn.open(folder: p.path) { why in if let why { SignIn.tell(why) } }
        }
        switcher.onOutcome = { [weak self] goal, outcome in self?.switched(goal, outcome) }
        NotificationCenter.default.addObserver(forName: AccountSwitcher.changed, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        hotKey.onPress = { [weak self] in self?.toggle() }
        applyShortcut()
    }

    /// A switch begun in the chat ended. On the account wanted: a new chat on the same profile sends what was typed;
    /// on another one, the notice says so. A switch begun in Settings only updates the account line.
    private func switched(_ goal: SwitchGoal, _ outcome: SwitchOutcome) {
        guard goal.origin == .chat, outcome == .reached, model.target?.profileID == goal.profileID,
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
        guard let id = model.target?.profileID, store.profile(id) != nil else { model.update(target: nil, level: nil, offer: nil); return }
        store.noteAccount(of: id)
        guard let p = store.profile(id) else { return }
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
            ?? switcher.mismatch[id].map { .wrong(signedIn: $0.signedIn, wanted: $0.goal.wantedEmail) }
        model.update(target: QuickChatTarget(p), level: store.level(of: p), offer: others.first,
                     switchOffer: standby.first?.1, notice: notice)
    }

    func toggle() { isOpen ? hide() : open() }

    private func applyShortcut() {
        hotKey.unregister()
        // a shortcut that could never have been kept (a hand-edited settings.json): ⌥Space instead
        if settings.shortcut.refused != nil { settings.shortcut = .optionSpace }
        shortcutState = settings.shortcutOn ? (hotKey.register(settings.shortcut) ?? "on") : nil
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
        model.target = pick.map(QuickChatTarget.init)
        refresh()
        if pick != nil, model.barProblem == .noProfile { model.barProblem = nil }
        let p = panel ?? makePanel()
        if !placed { place(p); placed = true }
        p.orderFrontRegardless()
        p.makeKey()
        model.focusTick += 1
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
        let root = QuickChatRoot(model: model) { [weak self] size in self?.fit(size) }
        p.contentView = QuickChatHostingView(rootView: root)
        panel = p
        return p
    }

    /// The panel takes the size of what it shows, its top edge staying where it is.
    private func fit(_ size: CGSize) {
        guard let p = panel, size.width > 0, size.height > 0 else { return }
        var f = p.frame
        guard abs(f.width - size.width) > 0.5 || abs(f.height - size.height) > 0.5 else { return }
        let top = f.maxY
        f.size = size
        f.origin.y = top - size.height
        if let vis = p.screen?.visibleFrame, f.minY < vis.minY { f.origin.y = vis.minY }
        p.setFrame(f, display: true)
        p.invalidateShadow()
    }

    /// The first time: centred on the screen with the mouse, its top a quarter of the way down.
    private func place(_ p: QuickChatPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let vis = screen?.visibleFrame else { return }
        let w = QuickChatRoot.width
        let top = vis.maxY - vis.height * 0.22
        p.setFrame(NSRect(x: vis.midX - w / 2, y: top - 140, width: w, height: 140), display: false)
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
final class QuickChatPanel: NSPanel {
    var onEscape: () -> Void = {}
    var onNewChat: () -> Void = {}

    /// cl_quick has no menu bar of its own, so the Edit keys are handled here: cut, copy, paste, select all, undo and
    /// redo go to whatever has the keyboard (the field, or a selected answer); ⌘N starts a new chat, ⌘W hides.
    override func performKeyEquivalent(with e: NSEvent) -> Bool {
        let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
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
        super.init(contentRect: NSRect(x: 0, y: 0, width: QuickChatRoot.width, height: 140),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape() }
}

/// Drags the panel from anywhere that isn't a key or the field.
final class QuickChatHostingView: NSHostingView<QuickChatRoot> {
    override var mouseDownCanMoveWindow: Bool { true }
}
