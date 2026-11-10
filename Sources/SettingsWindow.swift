// SettingsWindow: cl_quick's settings, in cl_audit's look (Faces, Style, Parts): General, a tile per profile with its
// lamp, and the + tile to add one. A profile's page in three layers: its name and folder; its accounts (the one in use
// with its 5 hours and week, standby ones with their week as last reported, Add an account…); how the chat uses it
// (the default, the picker); then Remove. General: one grid for the shortcut, the model and thinking new chats start
// with, and Open at login, then one strip for cl_quick's own data. No (i): a plain line where something needs saying.

import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

enum SettingsPage: Hashable {
    case general, profile(String), add
}

final class SettingsState: ObservableObject {
    @Published var page: SettingsPage = .general
    @Published var settings = QuickChat.shared.settings
    /// Folders being signed in (Sign in another account…): the box says so until Claude Code has signed them in.
    @Published var signingIn: Set<String> = []
    @Published var tick = 0
    private var timer: Timer?
    private var since = Date()
    private var switchWatch: NSObjectProtocol?

    init() {
        // a switch of account began, ended or was dropped (the chat's or this window's): the cards are drawn again
        switchWatch = NotificationCenter.default.addObserver(forName: AccountSwitcher.changed, object: nil, queue: .main) { [weak self] _ in
            self?.tick += 1
        }
    }
    deinit { if let switchWatch { NotificationCenter.default.removeObserver(switchWatch) } }

    // MARK: Record another…

    /// nil: not recording; .some(nil): listening; .some(keys): what was pressed.
    @Published var recording: QuickChatShortcut?? = nil
    private var monitor: Any?
    /// The settings window: only its own key presses are recorded.
    weak var window: NSWindow?

    func startRecording() {
        stopListening()
        recording = .some(nil)
        QuickChat.shared.pauseShortcut(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, let w = self.window, e.window === w else { return e }
            let mods = e.modifierFlags.intersection([.command, .control, .option, .shift])
            if e.keyCode == UInt16(kVK_Escape), mods.isEmpty { self.stopRecording(); return nil }
            self.recording = .some(QuickChatShortcut(event: e))
            return nil
        }
    }

    /// Ends recording, keeping the keys pressed or the old shortcut; the shortcut is registered again either way.
    func stopRecording(keep s: QuickChatShortcut? = nil) {
        guard recording != nil else { return }
        stopListening()
        recording = nil
        if let s { settings.shortcut = s; save() }
        QuickChat.shared.pauseShortcut(false)
    }

    private func stopListening() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// While a sign-in is under way, its folder is looked at every 2 s; after 10 minutes it's given up.
    func watchSignIns() {
        timer?.invalidate()
        since = Date()
        guard !signingIn.isEmpty else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            // the folders' files are read off the main thread; what they said is judged from the value kept
            ClaudeFolder.reload(Array(self.signingIn)) { [weak self] _ in
                guard let self else { return }
                ProfileStore.shared.noteAccounts()
                let used = Set(ProfileStore.shared.profiles.map(\.path))
                self.signingIn = self.signingIn.filter { ClaudeFolder.email($0) == nil && used.contains($0) }
                if Date().timeIntervalSince(self.since) > 600 { self.signingIn = [] }
                self.tick += 1
                if self.signingIn.isEmpty { self.timer?.invalidate() }
            }
        }
    }

    func save() { QuickChat.shared.settingsChanged(settings) }
}

final class SettingsWindow {
    static let shared = SettingsWindow()
    let state = SettingsState()
    private var window: NSWindow?

    /// Opens the window (and brings cl_quick forward, as a settings window should) on a profile's card, or General.
    func show(profile: String?, firstRun: Bool = false) {
        state.settings = QuickChat.shared.settings
        ProfileStore.shared.noteAccounts()
        ProfileStore.shared.reload()
        let first = ProfileStore.shared.profiles.first?.id
        // the first run: the first profile found, or Add a profile when none was
        state.page = profile.map(SettingsPage.profile) ?? (firstRun ? (first.map(SettingsPage.profile) ?? .add) : .general)
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 660), styleMask: [.titled, .closable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "cl_quick Settings"
            w.isReleasedWhenClosed = false
            w.appearance = NSAppearance(named: .darkAqua)
            w.contentView = NSHostingView(rootView: SettingsRoot(state: state, store: ProfileStore.shared).face(.std))
            w.center()
            window = w
            state.window = w
            // closed or left mid-recording: the old shortcut is back and nothing listens any more
            for name in [NSWindow.willCloseNotification, NSWindow.didResignKeyNotification] {
                NotificationCenter.default.addObserver(forName: name, object: w, queue: .main) { [weak self] _ in
                    self?.state.stopRecording()
                }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsRoot: View {
    @ObservedObject var state: SettingsState
    @ObservedObject var store: ProfileStore
    @Environment(\.face) private var face

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                let _ = state.tick           // a switch or a sign-in moved: the lamps are drawn again
                SettingsTiles(profiles: store.profiles.map { tile(for: $0) }, page: state.page) { state.page = $0 }
                switch state.page {
                case .general: GeneralPage(state: state, store: store)
                case .add: AddPage(state: state, store: store)
                case .profile(let id):
                    if let p = store.profile(id) { ProfilePage(state: state, store: store, profile: p) }
                    else { GeneralPage(state: state, store: store) }
                }
            }
            .padding(18)
        }
        .frame(minWidth: 600, minHeight: 460)          // the shortcut's seven choices in one row
        .background(RaisedShape(finish: face.chassis, radius: 0))
    }

    private var defaultID: String? { state.settings.defaultProfile ?? store.profiles.first?.id }

    /// A profile's tile: its lamp (signed in, waiting for a sign-in, or broken), its name, and the account in use.
    private func tile(for p: Profile) -> SettingsTiles.Item {
        let waiting = AccountSwitcher.shared.waiting[p.id] != nil || state.signingIn.contains(p.path)
        let problem = store.signInProblem(p)
        let lamp: Lamp = waiting ? .waiting : problem != nil ? .broken : .ok
        let who = waiting ? "switching…" : problem == .signedOut ? "signed out" : store.inUse(p)?.email ?? tilde(p.path)
        return .init(id: p.id, name: p.name, sub: (p.id == defaultID ? "default · " : "") + who, lamp: lamp)
    }
}

/// A profile's health, the same lamp wherever the profile is drawn: green signed in, amber waiting for a sign-in, red
/// when its sign-in is broken.
enum Lamp { case ok, waiting, broken
    func color(_ face: FaceTheme) -> Color { self == .ok ? face.ok : self == .waiting ? face.caution : face.danger }
}

/// The strip: General, a tile per profile with its lamp, and + for Add a profile.
struct SettingsTiles: View {
    struct Item: Identifiable { let id: String; let name: String; let sub: String; let lamp: Lamp }
    let profiles: [Item]
    let page: SettingsPage
    var pick: (SettingsPage) -> Void = { _ in }
    @Environment(\.face) private var face

    var body: some View {
        FlowTiles {
            TileKey(selected: page == .general) { TileText(title: "General", sub: "shortcut · new chats") }
                .onTapGesture { pick(.general) }
            ForEach(profiles) { p in
                TileKey(selected: page == .profile(p.id), leading: 10) {
                    HStack(spacing: 8) {
                        LED(color: p.lamp.color(face), size: 7)
                        TileText(title: p.name, sub: p.sub)
                    }
                }
                .onTapGesture { pick(.profile(p.id)) }
            }
            TileKey(selected: page == .add) { Text("+").font(.system(size: 20, weight: .light)).frame(minWidth: 14) }
                .onTapGesture { pick(.add) }
                .help("Add a profile")
        }
        .padding(9)
        .background(SurfaceShape(surface: face.strip, radius: 8))
    }
}

/// The tiles in rows that wrap.
struct FlowTiles<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        if #available(macOS 13, *) { WrapLayout(spacing: 8) { content } } else { HStack(spacing: 8) { content } }
    }
}

struct WrapLayout: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let d = s.sizeThatFits(.unspecified)
            if x > 0, x + d.width > width { y += row + spacing; x = 0; row = 0 }
            x += d.width + spacing; row = max(row, d.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let d = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + d.width > bounds.maxX { y += row + spacing; x = bounds.minX; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(d))
            x += d.width + spacing; row = max(row, d.height)
        }
    }
}

// MARK: - Pages

/// One account of a profile, as its card draws it.
struct AccountEntry: Identifiable, Equatable {
    var id: String
    var email: String
    /// The plan, for the account in use (read from the folder's file).
    var plan: String? = nil
    /// The one signed in to the folder now; the others are standby.
    var inUse: Bool
    /// The account in use only: its limits as Claude Code last reported them. A standby account shows none.
    var level: QuickChatLevel?
    /// A standby account: when cl_quick last saw it signed in to the folder.
    var lastSeen: Date? = nil
    /// A sign-in for it is being waited for.
    var signing = false
    /// The account in use, when its sign-in is broken: said in a line, with Sign in again…. Nil: it works, no button.
    var problem: SignInProblem? = nil
}

/// The 5-hour limit and the week in cl_audit's twelve segments, each with its number and when it resets, as Claude
/// Code reported them after the last answer.
struct LimitBars: View {
    let level: QuickChatLevel
    var now = Date()
    @Environment(\.face) private var face

    var body: some View {
        let full = level.full(now)
        VStack(alignment: .leading, spacing: 8) {
            bar("5 hours", full?.id == "5h" ? 100 : level.fiveHourResets.map { $0 <= now } == true ? nil : level.fiveHour,
                full?.id == "5h" ? full?.resets : level.fiveHourResets, full: full?.id == "5h")
            bar("Week", full?.id == "wk" ? 100 : level.weekNow(now), full?.id == "wk" ? full?.resets : level.weekResets, full: full?.id == "wk")
        }
    }

    private func bar(_ name: String, _ p: Double?, _ resets: Date?, full: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(name).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(face.text)
                if let resets, resets > now { Text("· resets \(TimeWords.when(resets, now: now))").font(.system(size: 11)).foregroundStyle(face.muted) }
                Spacer()
                Text(full ? "full" : QuickChatLevel.pct(p)).font(.system(size: 12, weight: .bold).monospacedDigit())
                    .foregroundStyle(p == nil ? face.muted : QuickChatLevel.color(p))
            }
            HStack(spacing: 2) {
                let lit = (p ?? 0) > 0 ? max(1, Int(((p ?? 0) / 100 * 12).rounded())) : 0
                ForEach(0..<12, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(i < lit ? Color(nsColor: Painter.segment(i)) : face.segOff)
                        .frame(height: 7)
                }
            }
        }
    }
}

/// A sentence in a tinted box, with its keys: what went wrong or what's under way, and what to do about it.
struct NoticeBox<Keys: View>: View {
    enum Tone { case ok, waiting, bad }
    let tone: Tone
    let title: String
    var text: String = ""
    @ViewBuilder let keys: Keys
    @Environment(\.face) private var face

    var body: some View {
        let c = tone == .ok ? face.ok : tone == .waiting ? face.caution : face.danger
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                LED(color: c, size: 7).alignmentGuide(.firstTextBaseline) { d in d[.bottom] }
                (Text(title).fontWeight(.semibold).foregroundColor(face.text) + Text(text.isEmpty ? "" : " " + text).foregroundColor(face.soft))
                    .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) { keys }.buttonStyle(.sentenceKey()).padding(.leading, 15)
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(c.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(c.opacity(0.4), lineWidth: 1))
    }
}

/// The account in use: the big one, first, on the same dark well as the standby rows; its lamp, address, plan, the
/// "In use" tag and both limits. Sign in again… is here only while its sign-in is broken.
struct InUseBox: View {
    let entry: AccountEntry
    let profileName: String
    var busy = false
    var signInAgain: () -> Void = {}
    @Environment(\.face) private var face

    var body: some View {
        let broken = entry.problem != nil
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                LED(color: broken ? face.danger : entry.signing ? face.caution : face.ok, size: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.email).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(face.text).lineLimit(1).truncationMode(.middle)
                    Text(detail).font(.system(size: 11)).foregroundStyle(face.muted).lineLimit(1)
                }
                Spacer(minLength: 8)
                DisplayWindow(text: entry.signing ? "Signing in" : broken ? "Sign-in broken" : "In use",
                              tone: entry.signing ? .amber : broken ? .warn : .ok, height: 18, size: 9)
            }
            if broken, !entry.signing {
                NoticeBox(tone: .bad, title: "The sign-in stopped working.", text: "The chat can't answer on \(profileName) until you sign in again.") {
                    Button("Sign in again…", action: signInAgain).buttonStyle(.sentenceKey(next: true)).disabled(busy)
                }
            }
            if let level = entry.level, level.at != nil {
                LimitBars(level: level).saturation(broken ? 0 : 1).opacity(broken ? 0.6 : 1)
            } else {
                Text("No limits yet: Claude Code reports them with the first answer.").font(.system(size: 11)).foregroundStyle(face.muted)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(WellShape(well: face.win, radius: 7))
    }

    private var detail: String {
        let at = entry.level?.at.map { "as Claude Code reported after the last answer, \(TimeWords.when($0))" }
        return ([entry.plan, at].compactMap { $0 }).joined(separator: " · ")
    }
}

/// A folder with no account signed in: said plainly, with Sign in again… (or the sign-in being waited for).
struct SignedOutBox: View {
    let path: String
    let profileName: String
    var signing = false
    var busy = false
    var signIn: () -> Void = {}
    var showTerminal: () -> Void = {}
    @Environment(\.face) private var face

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                LED(color: signing ? face.caution : face.danger, size: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No account signed in").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(face.text)
                    Text(tilde(path)).font(.system(size: 11, design: .monospaced)).foregroundStyle(face.muted)
                }
                Spacer(minLength: 8)
                DisplayWindow(text: signing ? "Signing in" : "Signed out", tone: signing ? .amber : .warn, height: 18, size: 9)
            }
            if signing {
                NoticeBox(tone: .waiting, title: "Waiting for the sign-in.", text: "Finish it in Terminal and the browser.") {
                    Button("Show Terminal", action: showTerminal)
                }
            } else {
                NoticeBox(tone: .bad, title: "Signed out.", text: "Claude Code on this folder isn't signed in, so the chat can't answer on \(profileName).") {
                    Button("Sign in again…", action: signIn).buttonStyle(.sentenceKey(next: true)).disabled(busy)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(WellShape(well: face.win, radius: 7))
    }
}

/// An account on standby: a slim row on the same dark well, when it was last in use, and Switch… and Forget…. No usage:
/// one folder holds one sign-in, so a standby account's limits aren't known here, and an old week isn't shown.
struct StandbyRow: View {
    let entry: AccountEntry
    var busy = false
    var switchTo: () -> Void = {}
    var forget: () -> Void = {}
    var now = Date()
    @Environment(\.face) private var face

    var body: some View {
        HStack(spacing: 9) {
            LED(color: face.caution, lit: entry.signing, size: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.email).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(face.text).lineLimit(1).truncationMode(.middle)
                Text(detail).font(.system(size: 11)).foregroundStyle(entry.signing ? face.caution : face.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            if !entry.signing {
                HStack(spacing: 6) {
                    Button("Switch…", action: switchTo)
                    Button("Forget…", action: forget)
                }
                .buttonStyle(.sentenceKey()).disabled(busy)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(WellShape(well: face.win, radius: 7))
    }

    private var detail: String {
        if entry.signing { return "Waiting for its sign-in…" }
        return (["On standby", entry.plan, entry.lastSeen.map { "last in use " + AccountBook.ago($0, now: now) }]
            .compactMap { $0 }).joined(separator: " · ")
    }
}

/// What the Forget… question says (the alert and its picture for checking).
enum ForgetWords {
    static func title(_ email: String) -> String { "Forget \(email)?" }
    static func detail(profile: String) -> String {
        "cl_quick drops this account from \(profile)'s list, with its week. Nothing is signed out and no session is touched; it comes back if it's signed in on this folder again."
    }
}

/// At the top of a profile's accounts, one notice at a time: a sign-in being waited for (Show Terminal, Stop), a switch
/// that ended without the account wanted, because another one signed in or because 10 minutes passed (Try … again…,
/// OK), or a sign-in again that worked (OK).
struct SwitchNotice: View {
    var waiting: SwitchGoal?
    var ended: SwitchEnded?
    /// The address a sign-in again just ended on: the same account.
    var signedAgain: String?
    var profileName = ""
    var showTerminal: () -> Void = {}
    var drop: () -> Void = {}
    var retry: (SwitchGoal) -> Void = { _ in }

    var body: some View {
        if let waiting {
            NoticeBox(tone: .waiting, title: waiting.again ? "Signing in again as \(waiting.wantedEmail)." : "Switching to \(waiting.wantedEmail).",
                      text: "Finish the sign-in in the browser as that address. cl_quick looks for it for 10 minutes.") {
                Button("Show Terminal", action: showTerminal)
                Button("Stop", action: drop)
            }
        } else if let m = ended {
            NoticeBox(tone: .bad,
                      title: m.signedIn.map { "\($0) signed in, not \(m.goal.wantedEmail)." } ?? "No sign-in in 10 minutes.",
                      text: m.signedIn.map { "The browser was signed in as someone else. \(profileName) is on \($0) now." }
                        ?? "The account in use hasn't changed.") {
                // named after the account the switch was for, so it doesn't read as the in-use account's own Sign in again…;
                // a sign-in again that never came is just that again
                Button(m.goal.again && m.signedIn == nil ? "Sign in again…" : "Try \(m.goal.wantedEmail) again…") { retry(m.goal) }
                Button("OK", action: drop)
            }
        } else if let signedAgain {
            NoticeBox(tone: .ok, title: "Signed in again as \(signedAgain).") {
                Button("OK", action: drop)
            }
        }
    }
}

/// What a profile's page shows, apart from its own controls: everything the page and its pictures draw from.
struct ProfileModel {
    var name: String
    var path: String
    /// The account in use first (none when the folder is signed out), then the standby ones.
    var entries: [AccountEntry]
    /// No account signed in to the folder; `folderSigning`: its sign-in (Sign in again… or a new folder) is waited for.
    var folderSignedOut = false
    var folderSigning = false
    var waiting: SwitchGoal? = nil
    var ended: SwitchEnded? = nil
    var signedAgain: String? = nil
    var isDefault = false
    var inPicker = true
    /// A sign-in is being waited for: switching and adding wait.
    var busy: Bool { waiting != nil || folderSigning }
}

/// What a profile's page does: the page's own actions, handed in so its pictures can draw it with none.
struct ProfileActions {
    var reveal: () -> Void = {}
    var showTerminal: () -> Void = {}
    var switchTo: (AccountEntry) -> Void = { _ in }
    var forget: (AccountEntry) -> Void = { _ in }
    var signInAgain: () -> Void = {}
    var signInSignedOut: () -> Void = {}
    var drop: () -> Void = {}
    var retry: (SwitchGoal) -> Void = { _ in }
    var makeDefault: () -> Void = {}
    var setInPicker: (Bool) -> Void = { _ in }
    var remove: () -> Void = {}
}

/// A profile's page in three layers: who it is (its name and folder), its accounts, and how the chat uses it; then
/// Remove, alone and quiet, with what it leaves behind.
struct ProfileContent<Name: View, Add: View>: View {
    let model: ProfileModel
    var actions = ProfileActions()
    @ViewBuilder let nameField: Name
    @ViewBuilder let addAccount: Add
    @Environment(\.face) private var face

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    nameField
                    Text(tilde(model.path)).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(face.muted).padding(.leading, 2)
                }
                Spacer(minLength: 8)
                Button("Show in Finder", action: actions.reveal).buttonStyle(.sentenceKey())
            }
            SCard(title: "Accounts", line: "One account is signed in to this folder at a time. Switching moves "
                  + (ClaudeFolder.isDefault(model.path) ? "Claude Code in Terminal and editors" : "Claude Code pointed at \(tilde(model.path))")
                  + " to the other account, sessions running now included; the Claude app keeps its own sign-in.") {
                VStack(alignment: .leading, spacing: 8) {
                    SwitchNotice(waiting: model.waiting, ended: model.ended, signedAgain: model.signedAgain, profileName: model.name,
                                 showTerminal: actions.showTerminal, drop: actions.drop, retry: actions.retry)
                    if model.folderSignedOut {
                        SignedOutBox(path: model.path, profileName: model.name, signing: model.folderSigning, busy: model.waiting != nil,
                                     signIn: actions.signInSignedOut, showTerminal: actions.showTerminal)
                    }
                    ForEach(model.entries) { e in
                        if e.inUse { InUseBox(entry: e, profileName: model.name, busy: model.busy, signInAgain: actions.signInAgain) }
                        else { StandbyRow(entry: e, busy: model.busy, switchTo: { actions.switchTo(e) }, forget: { actions.forget(e) }) }
                    }
                    if model.entries.allSatisfy(\.inUse), !model.folderSignedOut {
                        Text("No other account on this folder yet. Add one to switch between them here.")
                            .font(.system(size: 11.5)).foregroundStyle(face.muted)
                    }
                    addAccount
                }
                .padding(.bottom, 4)
            }
            SCard(title: "In the chat") {
                LineRow(title: "The shortcut opens on \(model.name)", sub: "One profile is the default; the chat can change it for one chat.", first: true) {
                    if model.isDefault { DisplayWindow(text: "Default", tone: .ok, height: 20, size: 9) }
                    else { Button("Make default", action: actions.makeDefault).buttonStyle(.sentenceKey()) }
                }
                LineRow(title: "Offered in the chat's picker", sub: "And suggested when another profile's week is full.") {
                    SSwitch(isOn: Binding(get: { model.inPicker }, set: actions.setInPicker), on: "", off: "")
                }
            }
            HStack(spacing: 12) {
                Text("Removing leaves the folder, its sign-in and its sessions as they are.").font(.system(size: 11)).foregroundStyle(face.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Remove from cl_quick…", action: actions.remove).buttonStyle(.sentenceKey())
            }
            .padding(.horizontal, 2)
        }
    }
}

/// A row with its words on the left (a title and a short line under it) and its control on the right.
struct LineRow<Control: View>: View {
    let title: String
    var sub: String? = nil
    var first = false
    @ViewBuilder let control: Control
    @Environment(\.face) private var face

    var body: some View {
        VStack(spacing: 0) {
            if !first { EngravedRule() }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 12.5)).foregroundStyle(face.text)
                    if let sub { Text(sub).font(.system(size: 11)).foregroundStyle(face.muted).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 8)
                control
            }
            .padding(.vertical, 7)
        }
    }
}

/// A row of General's grid: the label in a fixed column, the control right beside it, every row the same.
struct GridLine<Control: View>: View {
    let label: String
    var first = false
    @ViewBuilder let control: Control
    @Environment(\.face) private var face
    static var labelWidth: CGFloat { 104 }

    var body: some View {
        VStack(spacing: 0) {
            if !first { EngravedRule() }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(label).font(.system(size: 12.5)).foregroundStyle(face.text).frame(width: Self.labelWidth, alignment: .leading)
                    .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
                control.alignmentGuide(.firstTextBaseline) { _ in 14 }      // the middle of the first control's 28 pt
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
        }
    }
}

/// Add an account…: a key that opens a small form with its own label, Sign in… and Cancel.
struct AddAccountForm: View {
    @Binding var open: Bool
    @Binding var address: String
    var problem: String? = nil
    var inUse: String? = nil
    var busy = false
    var signIn: () -> Void = {}
    @Environment(\.face) private var face

    var body: some View {
        if !open {
            Button("Add an account…") { open = true }.buttonStyle(.sentenceKey()).disabled(busy)
        } else {
            VStack(alignment: .leading, spacing: 7) {
                Text("Address of the account to add").font(.system(size: 12)).foregroundStyle(face.soft)
                HStack(spacing: 8) {
                    SField(placeholder: "name@domain", text: $address, width: 240, onCommit: { if ProfilePage.looksLikeAddress(address) { signIn() } })
                    Button("Sign in…", action: signIn).buttonStyle(.sentenceKey(next: true))
                        .disabled(!ProfilePage.looksLikeAddress(address) || busy)
                    Button("Cancel") { open = false; address = "" }.buttonStyle(.sentenceKey())
                }
                if let problem { Text(problem).font(.system(size: 11)).foregroundStyle(face.danger) }
                Text("Claude Code's sign-in opens in Terminal; finish it in the browser as this address."
                     + (inUse.map { " \($0) stays here on standby." } ?? ""))
                    .font(.system(size: 11)).foregroundStyle(face.muted).fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }
    }
}

struct ProfilePage: View {
    @ObservedObject var state: SettingsState
    @ObservedObject var store: ProfileStore
    let profile: Profile
    @State private var name = ""
    @State private var address = ""
    @State private var adding = false
    @State private var problem: String?
    @Environment(\.face) private var face

    private var switcher: AccountSwitcher { .shared }

    var body: some View {
        let waiting = switcher.waiting[profile.id]
        let model = ProfileModel(
            name: profile.name, path: profile.path, entries: entries(waiting),
            folderSignedOut: store.inUse(profile) == nil, folderSigning: state.signingIn.contains(profile.path),
            waiting: waiting, ended: switcher.ended[profile.id], signedAgain: switcher.signedAgain[profile.id],
            isDefault: (state.settings.defaultProfile ?? store.profiles.first?.id) == profile.id, inPicker: profile.inPicker)
        ProfileContent(model: model, actions: actions) {
            SField(placeholder: "Name", text: $name, width: 240, size: 16, weight: .semibold, onCommit: rename)
                .onAppear { name = profile.name; store.noteAccount(of: profile.id) }
                .onChange(of: profile.id) { _ in name = profile.name; problem = nil; address = ""; adding = false }
        } addAccount: {
            AddAccountForm(open: $adding, address: $address, problem: problem, inUse: store.inUse(profile)?.email,
                           busy: model.busy, signIn: addAccount)
        }
    }

    private var actions: ProfileActions {
        ProfileActions(
            reveal: { Files.reveal(URL(fileURLWithPath: profile.path)) },
            showTerminal: { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")) },
            switchTo: { e in switcher.confirmAndSwitch(profile, uuid: e.id, email: e.email, origin: .settings) },
            forget: { e in confirmForget(e) },
            signInAgain: { switcher.signInAgain(profile, origin: .settings) },
            signInSignedOut: { signInSignedOut() },
            drop: { switcher.drop(profile.id) },
            retry: { g in switcher.begin(profile, uuid: g.wantedUUID, email: g.wantedEmail, origin: .settings) },
            makeDefault: { state.settings.defaultProfile = profile.id; state.save() },
            setInPicker: { on in var p = profile; p.inPicker = on; store.update(p) },
            remove: { confirmRemove() })
    }

    /// Sign in again… on a folder with no account: Claude Code's sign-in in Terminal, and the folder is watched until an
    /// account is in it (the same watch a new folder gets), 10 minutes at most.
    private func signInSignedOut() {
        SignIn.open(folder: profile.path) { why in
            if let why { SignIn.tell(why); return }
            state.signingIn.insert(profile.path)
            state.watchSignIns()
        }
    }

    /// The account in use first, then the standby ones.
    private func entries(_ waiting: SwitchGoal?) -> [AccountEntry] {
        var out: [AccountEntry] = []
        if let u = store.inUse(profile) {
            out.append(AccountEntry(id: u.uuid, email: u.email, plan: ClaudeFolder.plan(profile.path),
                                    inUse: true, level: store.level(of: profile, account: u.uuid), signing: waiting?.again == true,
                                    problem: store.signInProblem(profile)))
        }
        for a in store.standby(profile) {
            let signing = waiting.map { $0.wantedUUID == a.id || $0.wantedEmail.lowercased() == a.email.lowercased() } ?? false
            // no level: a standby account shows no usage (an old week stays in levels.json, unshown)
            out.append(AccountEntry(id: a.uuid, email: a.email, inUse: false, level: nil, lastSeen: a.lastSeen, signing: signing))
        }
        return out
    }

    /// Something@something.something, no spaces: Claude Code's own sign-in page checks the rest.
    static func looksLikeAddress(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.contains(" "), let at = t.firstIndex(of: "@"), at != t.startIndex else { return false }
        let host = t[t.index(after: at)...]
        return host.contains(".") && !host.hasPrefix(".") && !host.hasSuffix(".") && !host.contains("@")
    }

    private func addAccount() {
        let a = address.trimmingCharacters(in: .whitespaces)
        if store.inUse(profile)?.email.lowercased() == a.lowercased() { problem = "\(a) is the account in use already."; return }
        problem = nil
        let known = profile.accounts.first { $0.email.lowercased() == a.lowercased() }
        switcher.confirmAndSwitch(profile, uuid: known?.uuid, email: known?.email ?? a, origin: .settings)
        address = ""
        adding = false
    }

    private func rename() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != profile.name else { name = profile.name; return }
        var p = profile; p.name = n; store.update(p)
    }

    /// Forget… on a standby account: asks first.
    private func confirmForget(_ e: AccountEntry) {
        guard !e.inUse else { return }
        let a = NSAlert()
        a.messageText = ForgetWords.title(e.email)
        a.informativeText = ForgetWords.detail(profile: profile.name)
        a.addButton(withTitle: "Forget"); a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        if store.forget(account: e.id, of: profile.id) {
            NotificationCenter.default.post(name: AccountSwitcher.changed, object: nil)      // the chat's switch offer too
        }
    }

    private func confirmRemove() {
        let a = NSAlert()
        a.messageText = "Remove \(profile.name) from cl_quick?"
        a.informativeText = "cl_quick forgets it. The folder \(tilde(profile.path)), its sign-in and its sessions stay as they are."
        a.addButton(withTitle: "Remove"); a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        switcher.drop(profile.id)
        store.remove(profile.id)
        QuickChat.shared.refresh()          // a chat on the removed profile ends with its claude
        state.signingIn.remove(profile.path)
        if state.settings.defaultProfile == profile.id { state.settings.defaultProfile = nil; state.save() }
        state.page = .general
    }
}

/// A Claude Code folder found on this Mac and not a profile yet: the account signed in there, and the profile already
/// using that account, if one is (then it can't be added: one account, one profile).
struct FoundFolder: Identifiable {
    var path: String
    var email: String?
    var plan: String?
    var takenBy: String?
    var id: String { path }
}

/// Add a profile, in two parts: the folders found on this Mac (Add, Sign in… for one that isn't signed in, or why it
/// can't be added), and somewhere else (Choose a folder…, or a new account in a new folder you name).
struct AddContent<NewName: View>: View {
    let found: [FoundFolder]
    var problem: String? = nil
    var newFolder = "~/.claude-<name>"
    var canSignIn = false
    var add: (String) -> Void = { _ in }
    var signInFound: (String) -> Void = { _ in }
    var choose: () -> Void = {}
    var signInNew: () -> Void = {}
    var dismiss: () -> Void = {}
    @ViewBuilder let newName: NewName
    @Environment(\.face) private var face

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add a profile").font(.system(size: 16, weight: .semibold)).foregroundStyle(face.text)
                Text("A profile is one Claude Code folder, with the account signed in there.").font(.system(size: 11.5)).foregroundStyle(face.muted)
            }
            .padding(.horizontal, 2)
            SCard(title: "Found on this Mac") {
                VStack(alignment: .leading, spacing: 8) {
                    if found.isEmpty {
                        Text("Every Claude Code folder on this Mac is a profile already.").font(.system(size: 11.5)).foregroundStyle(face.muted)
                    }
                    ForEach(found) { f in row(f) }
                }
                .padding(.bottom, 4)
            }
            SCard(title: "Somewhere else") {
                LineRow(title: "A folder Claude Code uses elsewhere", sub: "One set with CLAUDE_CONFIG_DIR, say.", first: true) {
                    Button("Choose a folder…", action: choose).buttonStyle(.sentenceKey())
                }
                if let problem {
                    NoticeBox(tone: .bad, title: problem) { Button("OK", action: dismiss) }.padding(.bottom, 6)
                }
                EngravedRule()
                VStack(alignment: .leading, spacing: 7) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("A new account, in a new folder").font(.system(size: 12.5)).foregroundStyle(face.text)
                        Text("Makes the folder and opens Claude Code's sign-in in Terminal.").font(.system(size: 11)).foregroundStyle(face.muted)
                    }
                    HStack(spacing: 8) {
                        newName
                        Text(newFolder).font(.system(size: 11, design: .monospaced)).foregroundStyle(face.muted).lineLimit(1)
                        Spacer(minLength: 8)
                        Button("Sign in…", action: signInNew).buttonStyle(.sentenceKey()).disabled(!canSignIn)
                    }
                }
                .padding(.vertical, 7)
            }
        }
    }

    private func row(_ f: FoundFolder) -> some View {
        HStack(spacing: 9) {
            LED(color: face.ok, lit: f.email != nil && f.takenBy == nil, size: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(tilde(f.path)).font(.system(size: 12.5, weight: .semibold, design: .monospaced)).foregroundStyle(face.text).lineLimit(1)
                Text(detail(f)).font(.system(size: 11)).foregroundStyle(face.muted).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if f.takenBy == nil {
                if f.email != nil { Button("Add") { add(f.path) }.buttonStyle(.sentenceKey(next: true)) }
                else { Button("Sign in…") { signInFound(f.path) }.buttonStyle(.sentenceKey()) }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(WellShape(well: face.win, radius: 7))
        .opacity(f.takenBy == nil ? 1 : 0.6)
    }

    private func detail(_ f: FoundFolder) -> String {
        guard let email = f.email else { return "Not signed in" }
        if let other = f.takenBy { return "\(email) is already on \(other): one account, one profile" }
        return ([email, f.plan].compactMap { $0 }).joined(separator: " · ")
    }
}

/// The + tile: the Claude Code folders found and not used yet, Choose a folder…, and a new account in a new folder.
struct AddPage: View {
    @ObservedObject var state: SettingsState
    @ObservedObject var store: ProfileStore
    @State private var newName = ""
    @State private var problem: String?
    @Environment(\.face) private var face

    var body: some View {
        let found = ClaudeFolder.found().filter { !store.uses($0) }.map { f -> FoundFolder in
            let a = ClaudeFolder.account(f)
            return FoundFolder(path: f, email: a?.email, plan: ClaudeFolder.plan(f), takenBy: a.flatMap { store.nameUsing($0) })
        }
        AddContent(found: found, problem: problem, newFolder: AddPage.folder(for: newName),
                   canSignIn: !newName.trimmingCharacters(in: .whitespaces).isEmpty,
                   add: { add($0) }, signInFound: signInFound, choose: choose, signInNew: signIn, dismiss: { problem = nil }) {
            SField(placeholder: "Name, e.g. Personal", text: $newName, width: 150, onCommit: { if !newName.trimmingCharacters(in: .whitespaces).isEmpty { signIn() } })
        }
    }

    /// A folder refused because its account is already on another profile: why, and what to do instead.
    static func refusedWords(folder: String, email: String, profile: String) -> String {
        "\(tilde(expand(folder))) is signed in as \(email), which is already on \(profile). Switch \(profile)'s account instead, or sign this folder in as someone else."
    }

    /// The folder a new account's name makes: ~/.claude-<name>, in small letters, anything else a dash.
    static func folder(for name: String) -> String {
        let n = name.trimmingCharacters(in: .whitespaces)
        return "~/.claude-" + (n.isEmpty ? "<name>" : String(n.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }))
    }

    /// A folder found that isn't signed in: Claude Code's sign-in on it in Terminal, then it's a profile, "signing in",
    /// until an account is in it (10 minutes at most).
    private func signInFound(_ f: String) {
        SignIn.open(folder: f) { why in
            if let why { problem = why; return }
            add(f)
            if store.uses(f) {
                state.signingIn.insert(expand(f))
                state.watchSignIns()
            }
        }
    }

    private func add(_ folder: String, name: String? = nil) {
        guard !store.uses(folder) else { problem = "\(tilde(expand(folder))) is a profile already."; return }
        // one account, one profile: the folder's file is read as it is now, not as it was when the list was drawn
        if let a = ClaudeFolder.freshAccount(folder), let other = store.nameUsing(a) {
            problem = AddPage.refusedWords(folder: folder, email: a.email, profile: other)
            return
        }
        let p = Profile(id: ProfileStore.newID(folder, taken: store.profiles.map(\.id)), name: name ?? ClaudeFolder.suggestedName(folder), folder: tilde(expand(folder)))
        store.add(p)
        problem = nil
        state.page = .profile(p.id)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        panel.message = "Choose a Claude Code folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // only a Claude Code folder that is signed in: any other would get Claude Code's files written into it
        guard ClaudeFolder.usable(url.path) else {
            problem = "\(tilde(url.path)) isn't a signed-in Claude Code folder. Choose one that is signed in, or sign a new account in, below."
            return
        }
        add(url.path)
    }

    /// A new folder, and Claude Code in Terminal on it to sign in. The profile is there at once, "signing in".
    private func signIn() {
        let n = newName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        let folder = AddPage.folder(for: n)
        guard !FileManager.default.fileExists(atPath: expand(folder)) else { problem = "\(folder) is there already: add it with Choose a folder…."; return }
        // the full look for claude can take a few seconds (the login shell): off the main thread
        DispatchQueue.global(qos: .userInitiated).async {
            let claude = ClaudeLocator.find()?.path
            DispatchQueue.main.async { startSignIn(name: n, folder: folder, claude: claude) }
        }
    }

    private func startSignIn(name n: String, folder: String, claude: String?) {
        guard let claude else { problem = ClaudeInstall.missing + "."; return }
        do { try FileManager.default.createDirectory(atPath: expand(folder), withIntermediateDirectories: true) } catch {
            problem = "\(folder) can't be made: \(error.localizedDescription)"; return
        }
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let script = Files.folder.appendingPathComponent("sign-in.command")
        let text = "#!/bin/zsh\n# cl_quick: Claude Code on \(folder), to sign in. Close this window when it says you're signed in.\n"
            // a key or another provider from the shell's own settings would sign it in some other way: not here
            + "unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN CLAUDE_CODE_OAUTH_TOKEN CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY\n"
            + "export CLAUDE_CONFIG_DIR=\(q(expand(folder)))\nexec \(q(claude))\n"
        do {
            try FileManager.default.createDirectory(at: Files.folder, withIntermediateDirectories: true)
            try text.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        } catch { problem = "The sign-in couldn't start: \(error.localizedDescription)"; return }
        NSWorkspace.shared.open(script)
        add(folder, name: n)
        state.signingIn.insert(expand(folder))
        state.watchSignIns()
        newName = ""
    }
}

/// What a picture of General draws in place of this Mac's own state.
struct GeneralSample {
    var own: Int64 = 625
    var clash: String? = nil
    var login = true
    var registered: String? = nil
}

/// General: one card, one grid (four labels on the left, every control in the column beside them), then one quiet strip
/// for cl_quick's own data.
struct GeneralPage: View {
    @ObservedObject var state: SettingsState
    @ObservedObject var store: ProfileStore
    var sample: GeneralSample? = nil
    @State private var loginOn = SMAppService.mainApp.status == .enabled
    @State private var chats: [(Profile, Int, Int64)] = []
    @State private var own: Int64 = 0
    @Environment(\.face) private var face

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("General").font(.system(size: 16, weight: .semibold)).foregroundStyle(face.text).padding(.horizontal, 2)
            SCard(title: "") {
                GridLine(label: "Shortcut", first: true) {
                    VStack(alignment: .leading, spacing: 7) {
                        if let r = state.recording { recorderRow(r) }
                        else {
                            KeySegments(choices: shortcutChoices, selected: shortcutSelected, pick: pick)
                            shortcutNote
                        }
                    }
                }
                GridLine(label: "Model") {
                    KeySegments(choices: QuickChatModelChoice.allCases.map { .init(id: $0.rawValue, title: $0.title) },
                                selected: state.settings.model.rawValue) { id in
                        if let m = QuickChatModelChoice(rawValue: id) { state.settings.model = m; state.save() }
                    }
                }
                GridLine(label: "Thinking") {
                    KeySegments(choices: QuickChatThinking.allCases.map { .init(id: $0.rawValue, title: $0.title) },
                                selected: state.settings.thinking.rawValue) { id in
                        if let t = QuickChatThinking(rawValue: id) { state.settings.thinking = t; state.save() }
                    }
                }
                GridLine(label: "Open at login") {
                    SSwitch(isOn: Binding(get: { sample?.login ?? loginOn }, set: { setLogin($0) }), on: "", off: "")
                }
            }
            HStack(spacing: 10) {
                Text(dataWords).font(.system(size: 11)).foregroundStyle(face.muted).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Show in Finder") { Files.reveal(Files.folder) }
                Button("Remove…") { confirmRemove() }
            }
            .buttonStyle(.sentenceKey())
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.14)))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.white.opacity(0.05), lineWidth: 1))
        }
        .onAppear(perform: count)
        .onDisappear { state.stopRecording() }
    }

    /// Incognito in one sentence, the size of cl_quick's own files, and old chats from earlier versions while any are left.
    private var dataWords: String {
        let n = chats.reduce(0) { $0 + $1.1 }, b = chats.reduce(Int64(0)) { $0 + $1.2 }
        return "Quick chats are incognito: nothing is saved on this Mac. cl_quick's own settings, \(Files.size(sample?.own ?? own))."
            + (n == 0 ? "" : " Old quick chats from earlier versions: \(n), \(Files.size(b)).")
    }

    // MARK: The shortcut (Record another…'s listening is SettingsState's, so closing the window ends it)

    /// The five Space shortcuts, Other… (the recorded one, when it's none of them) and Off.
    private var shortcutChoices: [KeySegments.Choice] {
        let s = state.settings.shortcut
        return QuickChatShortcut.presets.map { .init(id: $0.id, title: $0.title) }
            + [.init(id: "record", title: s.isPreset ? "Other…" : s.title), .init(id: "off", title: "Off")]
    }

    private var shortcutSelected: String {
        !state.settings.shortcutOn ? "off" : state.settings.shortcut.isPreset ? state.settings.shortcut.id : "record"
    }

    private func pick(_ id: String) {
        if id == "off" { state.settings.shortcutOn = false; state.save(); return }
        if id == "record" { state.startRecording(); return }
        guard let s = QuickChatShortcut.presets.first(where: { $0.id == id }) else { return }
        state.settings.shortcut = s; state.settings.shortcutOn = true; state.save()
    }

    @ViewBuilder private func recorderRow(_ r: QuickChatShortcut?) -> some View {
        HStack(spacing: 6) {
            DisplayWindow(text: r?.title ?? "Press the shortcut…", tone: r == nil ? .amber : .normal, height: 22, size: 10)
            if let r, r.refused == nil {
                Button(r.clash() == nil ? "Keep" : "Keep anyway") { state.settings.shortcutOn = true; state.stopRecording(keep: r) }
                    .buttonStyle(.sentenceKey(next: true))
            }
            if r != nil { Button("Record again") { state.recording = .some(nil) } }
            Button("Cancel") { state.stopRecording() }
        }
        .buttonStyle(.sentenceKey())
        if let r {
            if let why = r.refused { note(why, face.danger, lamp: true) }
            else if let c = r.clash() { note(c + " Keep it anyway, or record another.", face.caution, lamp: true) }
        } else {
            note("Hold ⌘, ⌃ or ⌥ and press a key. Esc cancels.", face.muted)
        }
    }

    /// Only what needs saying: a shortcut macOS wouldn't take, or one that clashes, with a one-click way out.
    @ViewBuilder private var shortcutNote: some View {
        let s = state.settings.shortcut
        if state.settings.shortcutOn {
            if let st = sample?.registered ?? QuickChat.shared.shortcutState, st != "on" {
                note(st + " Pick another.", face.danger, lamp: true)
            } else if let c = sample != nil ? sample?.clash : s.clash() {
                VStack(alignment: .leading, spacing: 3) {
                    note(c, face.caution, lamp: true)
                    if let free = QuickChatShortcut.presets.first(where: { $0 != s && (sample != nil || $0.clash() == nil) }) {
                        Button("Pick \(free.title) instead") { pick(free.id) }
                            .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.hex(0x9cc7ff))
                            .padding(.leading, 12)
                    }
                }
            }
        }
    }

    private func note(_ t: String, _ c: Color, lamp: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if lamp { LED(color: c, size: 6).alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 1 } }
            Text(t).font(.system(size: 11)).foregroundStyle(c == face.muted ? c : c.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func setLogin(_ on: Bool) {
        guard sample == nil else { return }
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch {}
        loginOn = SMAppService.mainApp.status == .enabled
    }

    private func count() {
        guard sample == nil else { return }
        let list = store.profiles
        DispatchQueue.global(qos: .utility).async {
            let c = list.map { p -> (Profile, Int, Int64) in let x = Files.chats(p); return (p, x.count, x.bytes) }
            let o = Files.ownBytes()
            DispatchQueue.main.async { chats = c.filter { $0.1 > 0 }; own = o }
        }
    }

    private func confirmRemove() {
        let n = chats.reduce(0) { $0 + $1.1 }
        let a = NSAlert()
        a.messageText = "Move cl_quick's data to the Trash?"
        let old = n == 0 ? "" : "\(n == 1 ? "1 old quick chat" : "\(n) old quick chats") saved by earlier versions and "
        a.informativeText = "This moves \(old)cl_quick's profiles, settings and work folders to the Trash. Open at login turns off and cl_quick quits. Your Claude Code folders, their sign-ins and their other sessions stay; you can bring these back from the Trash."
        a.addButton(withTitle: "Move to Trash"); a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        QuickChat.shared.closeForRemoval()
        try? SMAppService.mainApp.unregister()
        let failed = Files.remove(store.profiles)
        if !failed.isEmpty {
            let b = NSAlert(); b.messageText = "Some of it couldn't be moved"; b.informativeText = failed.joined(separator: "\n"); b.runModal()
        }
        NSApp.terminate(nil)
    }
}

// MARK: - A picture of it, for checking (`--render-settings OUT.png PAGE`)

enum SettingsRender {
    @MainActor static func write(to path: String, page: String) {
        let st = SettingsState()
        SField.drawing = true
        let view: AnyView
        let now = Date()
        var lvl = QuickChatLevel(); lvl.week = 62; lvl.weekResets = now.addingTimeInterval(3 * 86400); lvl.at = now
        // sample accounts only: the one in use with both limits, standby ones with their week as last reported
        func level(_ five: Double?, _ week: Double, ago: TimeInterval = 0) -> QuickChatLevel {
            var l = QuickChatLevel()
            l.fiveHour = five; l.fiveHourResets = five == nil ? nil : now.addingTimeInterval(2.5 * 3600)
            l.week = week; l.weekResets = now.addingTimeInterval(3 * 86400 - ago); l.at = now.addingTimeInterval(-ago)
            return l
        }
        let alex = AccountEntry(id: "u1", email: "alex@example.com", plan: "Max", inUse: true, level: level(34, 62, ago: 600))
        let kim = AccountEntry(id: "u2", email: "kim@example.org", inUse: false, level: nil, lastSeen: now.addingTimeInterval(-2 * 86400 - 600))
        let lee = AccountEntry(id: "u3", email: "lee@example.com", inUse: false, level: nil, lastSeen: now.addingTimeInterval(-9 * 86400))
        let goal = SwitchGoal(profileID: "main", profileName: "Main", folder: "~/.claude", wantedUUID: "u2",
                              wantedEmail: "kim@example.org", fromUUID: "u1", fromEmail: "alex@example.com", origin: .settings)
        var tiles: [SettingsTiles.Item] = [.init(id: "main", name: "Main", sub: "default · alex@example.com", lamp: .ok),
                                           .init(id: "work", name: "Work", sub: "sam@work.example", lamp: .ok)]
        var at: SettingsPage = .profile("main")
        func profile(_ m: ProfileModel, adding: Bool = false, address: String = "") -> AnyView {
            AnyView(ProfileContent(model: m) {
                Text(m.name).font(.system(size: 16, weight: .semibold)).padding(.horizontal, 7).frame(width: 240, height: 29, alignment: .leading)
                    .background(WellShape(well: FaceTheme.std.win, radius: 4))
            } addAccount: {
                AddAccountForm(open: .constant(adding), address: .constant(address), inUse: m.entries.first(where: \.inUse)?.email, busy: m.busy)
            })
        }
        let main = ProfileModel(name: "Main", path: "~/.claude", entries: [alex, kim], isDefault: true)
        switch page {
        case "profile", "accounts":
            view = profile(main)
        case "accounts-one":
            // one account only, with Add an account… opened
            view = profile(ProfileModel(name: "Main", path: "~/.claude", entries: [alex], isDefault: true), adding: true, address: "kim@example.org")
        case "accounts-two":
            view = profile(ProfileModel(name: "Main", path: "~/.claude", entries: [alex, kim, lee], isDefault: true))
        case "accounts-switching":
            var k = kim; k.signing = true
            tiles[0] = .init(id: "main", name: "Main", sub: "default · switching…", lamp: .waiting)
            view = profile(ProfileModel(name: "Main", path: "~/.claude", entries: [alex, k], waiting: goal, isDefault: true))
        case "accounts-wrong":
            // the browser signed in someone else: robin is in use now, alex went to standby
            let robin = AccountEntry(id: "u4", email: "robin@example.net", plan: "Pro", inUse: true, level: nil)
            var a = alex; a.inUse = false; a.plan = nil; a.level = nil; a.lastSeen = now.addingTimeInterval(-30)
            tiles[0] = .init(id: "main", name: "Main", sub: "default · robin@example.net", lamp: .ok)
            view = profile(ProfileModel(name: "Main", path: "~/.claude", entries: [robin, a, kim], ended: SwitchEnded(goal: goal, signedIn: "robin@example.net"), isDefault: true))
        case "accounts-timedout":
            view = profile(ProfileModel(name: "Main", path: "~/.claude", entries: [alex, kim], ended: SwitchEnded(goal: goal, signedIn: nil), isDefault: true))
        case "accounts-again":
            view = profile(ProfileModel(name: "Main", path: "~/.claude", entries: [alex, kim], signedAgain: "alex@example.com", isDefault: true))
        case "accounts-stopped":
            var a = alex; a.problem = .stopped
            tiles[0] = .init(id: "main", name: "Main", sub: "default · alex@example.com", lamp: .broken)
            view = profile(ProfileModel(name: "Main", path: "~/.claude", entries: [a, kim], isDefault: true))
        case "accounts-signedout", "accounts-signing":
            // a folder with no account signed in (its earlier account on standby), or its sign-in being waited for
            var a = alex; a.inUse = false; a.plan = nil; a.level = nil; a.lastSeen = now.addingTimeInterval(-3 * 3600)
            let signing = page == "accounts-signing"
            tiles[0] = .init(id: "main", name: "Main", sub: "default · " + (signing ? "switching…" : "signed out"), lamp: signing ? .waiting : .broken)
            view = profile(ProfileModel(name: "Main", path: "~/.claude", entries: [a], folderSignedOut: true, folderSigning: signing, isDefault: true))
        case "accounts-other":
            // a profile that isn't the default
            at = .profile("work")
            let sam = AccountEntry(id: "u5", email: "sam@work.example", plan: "Team", inUse: true, level: level(8, 18, ago: 3 * 3600))
            view = profile(ProfileModel(name: "Work", path: "~/.claude-work", entries: [sam], inPicker: false))
        case "accounts-forget", "accounts-confirm":
            // Forget…'s question, or Switch…'s (what a switch affects): alerts, so drawn here from their words
            let confirm = page == "accounts-confirm"
            view = AnyView(VStack(alignment: .leading, spacing: 14) {
                profile(main)
                VStack(alignment: .leading, spacing: 8) {
                    Text(confirm ? "Switch Main to \(maskEmail("kim@example.org"))?" : ForgetWords.title("kim@example.org")).font(.system(size: 13, weight: .bold))
                    Text(confirm ? AccountBook.switchWords(folder: "~/.claude", email: maskEmail("kim@example.org"), isDefault: true)
                                 : ForgetWords.detail(profile: "Main")).font(.system(size: 11.5)).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Spacer()
                        Button("Cancel") {}
                        Button(confirm ? "Switch" : "Forget") {}
                    }.buttonStyle(.sentenceKey())
                }
                .padding(16).frame(width: 340)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.2)))
                .frame(maxWidth: .infinity)
            })
        case "add", "first", "add-refused", "add-empty":
            // the + tile: folders found (one to add, one not signed in, one whose account is on Work); after a chosen
            // folder was refused; with nothing left to add; the first run (no profiles yet)
            at = .add
            if page == "first" { tiles = [] }
            let found: [FoundFolder] = page == "add-empty" ? [] : [
                FoundFolder(path: "~/.claude-lab", email: "lee@example.com", plan: "Pro"),
                FoundFolder(path: "~/.claude-test", email: nil),
                FoundFolder(path: "~/.claude-old", email: "sam@work.example", takenBy: "Work")]
            view = AnyView(AddContent(found: page == "first" ? [FoundFolder(path: "~/.claude", email: "alex@example.com", plan: "Max")] + found.dropLast() : found,
                                      problem: page == "add-refused" ? AddPage.refusedWords(folder: "~/Projects/.claude-x", email: "sam@work.example", profile: "Work") : nil,
                                      newFolder: AddPage.folder(for: "Personal"), canSignIn: true) {
                SField(placeholder: "Name, e.g. Personal", text: .constant("Personal"), width: 150)
            })
        default:
            // General with sample settings: ⌃Space with nothing to say, ⌥Space clashing with Quick Entry, the shortcut
            // off, Other… listening for keys, and a shortcut another app holds
            at = .general
            st.settings.shortcut = page == "general-clash" || page == "general-taken" ? .optionSpace : .controlSpace
            st.settings.shortcutOn = page != "general-off"
            st.settings.model = .haiku
            st.settings.thinking = .off
            if page == "general-recording" { st.recording = .some(nil) }
            let sample = GeneralSample(clash: page == "general-clash" ? QuickChatShortcut.optionSpace.title + " also opens the Claude app's Quick Entry, if that's turned on." : nil,
                                       registered: page == "general-taken" ? "Another app already uses ⌥Space." : nil)
            view = AnyView(GeneralPage(state: st, store: ProfileStore.shared, sample: sample))
        }
        let whole = VStack(alignment: .leading, spacing: 14) {
            SettingsTiles(profiles: tiles, page: at)
            view
        }
        let r = ImageRenderer(content: whole.padding(18).frame(width: 640).face(.std)
            .background(RaisedShape(finish: FaceTheme.std.chassis, radius: 0)))
        r.scale = 2
        if let tiff = r.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
    }
}
