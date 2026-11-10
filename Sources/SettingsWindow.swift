// SettingsWindow: cl_quick's settings, in cl_audit's look (Faces, Style, Parts): a tile per profile, the + tile to add
// one, and General. A profile's card: its name, the account signed in to its folder with the week as Claude Code last
// reported it, whether the shortcut chats on it and whether the chat's picker offers it. General: the shortcut, the
// default model and thinking, Open at login, and where cl_quick keeps things with Remove cl_quick data….

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
        .frame(minWidth: 560, minHeight: 460)
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

// MARK: - A profile's account

/// The account signed in to a folder, as cl_audit draws an account: a lamp, the address, the plan, a display window
/// with its state, and the week in twelve segments when Claude Code has reported it.
struct AccountBox: View {
    /// The first line: the masked address, or the folder when nothing is signed in.
    var title: String
    /// The second line: the plan and the folder, or when a standby account was last seen.
    var detail: String
    /// The lamp: lit for the account in use or a folder signed in, dark for a standby account.
    var lit: Bool
    var status: String
    var tone: DisplayWindow.Tone
    /// The week as last reported on this account.
    var level: QuickChatLevel? = nil
    /// Said in place of the week when there are no numbers yet (a standby account says it; a folder just shows none).
    var noWeek: String? = nil
    var badge: AnyView? = nil
    /// Keys under the week.
    var actions: AnyView? = nil
    @Environment(\.face) private var face

    /// A folder as a whole: the account signed in to it, if any.
    init(folder: String, level: QuickChatLevel? = nil, signingIn: Bool = false, badge: AnyView? = nil, actions: AnyView? = nil) {
        let email = ClaudeFolder.email(folder)
        self.init(title: email.map(maskEmail) ?? tilde(folder),
                  detail: ([ClaudeFolder.plan(folder)].compactMap { $0 } + [tilde(folder)]).joined(separator: " · "),
                  lit: email != nil,
                  status: signingIn ? "Signing in" : email == nil ? "Not signed in" : "Signed in",
                  tone: signingIn ? .amber : email == nil ? .normal : .ok, level: level, badge: badge, actions: actions)
    }

    init(title: String, detail: String, lit: Bool, status: String, tone: DisplayWindow.Tone, level: QuickChatLevel? = nil,
         noWeek: String? = nil, badge: AnyView? = nil, actions: AnyView? = nil) {
        self.title = title; self.detail = detail; self.lit = lit; self.status = status; self.tone = tone
        self.level = level; self.noWeek = noWeek; self.badge = badge; self.actions = actions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                LED(color: face.ok, lit: lit, size: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(face.text)
                    Text(detail).font(.system(size: 11)).foregroundStyle(face.muted)
                }
                Spacer(minLength: 8)
                if let badge { badge } else { DisplayWindow(text: status, tone: tone, height: 18, size: 9) }
            }
            if let level, level.weekNow() != nil || level.full() != nil { WeekSegments(level: level) }
            else if let noWeek { Text("Week: \(noWeek)").font(.system(size: 11)).foregroundStyle(face.muted) }
            if let actions { actions }
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(WellShape(well: face.win, radius: 7))
    }
}

/// The week in cl_audit's twelve segments, its number in the level's colour, and when it resets.
struct WeekSegments: View {
    let level: QuickChatLevel
    @Environment(\.face) private var face

    var body: some View {
        let full = level.full() != nil
        let p = full ? 100 : level.weekNow()
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Week").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(face.text)
                if let r = full ? level.full()?.resets : level.weekResets {
                    Text("· resets \(TimeWords.when(r))").font(.system(size: 11)).foregroundStyle(face.muted)
                }
                Spacer()
                Text(full ? "full" : QuickChatLevel.pct(p)).font(.system(size: 12.5, weight: .bold).monospacedDigit())
                    .foregroundStyle(QuickChatLevel.color(p))
            }
            HStack(spacing: 2) {
                let lit = (p ?? 0) > 0 ? max(1, Int(((p ?? 0) / 100 * 12).rounded())) : 0
                ForEach(0..<12, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(i < lit ? Color(nsColor: Painter.segment(i)) : face.segOff)
                        .frame(height: 8)
                }
            }
            if let at = level.at {
                Text("As Claude Code reported after the last answer, \(TimeWords.when(at)).").font(.system(size: 10.5)).foregroundStyle(face.muted)
            }
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
    var level: QuickChatLevel?
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

/// An account on standby: a slim row on the same dark well, its week as last reported while it was in use and how long
/// ago, and Switch… and Forget….
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
        let l = entry.level
        return "On standby · week " + (AccountBook.standbyWeek(l?.week, at: l?.at, resets: l?.weekResets, now: now) ?? "not reported yet")
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
            SCard(title: "Accounts", line: "One account is signed in to this folder at a time. Switching signs in again here, in Terminal.") {
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
            out.append(AccountEntry(id: a.uuid, email: a.email, inUse: false,
                                    level: store.level(of: profile, account: a.uuid), signing: signing))
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

/// The + tile: the Claude Code folders found and not used yet, Choose a folder…, and Sign in another account….
struct AddPage: View {
    @ObservedObject var state: SettingsState
    @ObservedObject var store: ProfileStore
    @State private var newName = ""
    @State private var problem: String?
    @Environment(\.face) private var face

    var body: some View {
        let found = ClaudeFolder.found().filter { !store.uses($0) }
        SCard(title: "Add a profile", info: "Any Claude Code folder: ~/.claude, a ~/.claude-* folder, or one set with CLAUDE_CONFIG_DIR. cl_quick reads only its .claude.json for the account.") {
            SRow(label: "Found on this Mac", first: true, stacked: true) {
                VStack(alignment: .leading, spacing: 6) {
                    if found.isEmpty { Text("Every Claude Code folder found is a profile already.").font(.system(size: 12)).foregroundStyle(face.muted) }
                    ForEach(found, id: \.self) { f in
                        let signedIn = ClaudeFolder.email(f) != nil
                        AccountBox(folder: f, badge: AnyView(
                            Button(signedIn ? "Add" : "Not signed in") { add(f) }.buttonStyle(PillButtonStyle(compact: true)).disabled(!signedIn)))
                    }
                    if found.contains(where: { ClaudeFolder.email($0) == nil }) {
                        Text("A folder that isn't signed in: sign in with Claude Code in it first, or use Sign in another account below.")
                            .font(.system(size: 10.5)).foregroundStyle(face.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            SRow(label: "Another folder", stacked: true) {
                Button("Choose a folder…") { choose() }.buttonStyle(PillButtonStyle(compact: true))
            }
            SRow(label: "Sign in another account", info: "Makes a new folder, ~/.claude-<name>, and opens Claude Code in Terminal on it; Claude Code signs in through the browser. cl_quick never sees a password or a token.", stacked: true) {
                HStack(spacing: 8) {
                    TextField("Name, e.g. Personal", text: $newName).textFieldStyle(.plain).font(.system(size: 13)).frame(maxWidth: 200)
                    Button("Sign in…") { signIn() }.buttonStyle(PillButtonStyle(compact: true))
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if let problem { SRowLine(text: problem, color: face.danger) }
        }
    }

    private func add(_ folder: String, name: String? = nil) {
        guard !store.uses(folder) else { problem = "\(tilde(expand(folder))) is a profile already."; return }
        // one account, one profile: the folder's file is read as it is now, not as it was when the list was drawn
        if let a = ClaudeFolder.freshAccount(folder), let other = store.nameUsing(a) {
            problem = ProfileStore.inUseWords(a.email, on: other)
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
            problem = "\(tilde(url.path)) isn't a signed-in Claude Code folder. Choose one with a .claude.json that is signed in, or use Sign in another account."
            return
        }
        add(url.path)
    }

    /// A new folder, and Claude Code in Terminal on it to sign in. The profile is there at once, "signing in".
    private func signIn() {
        let n = newName.trimmingCharacters(in: .whitespaces)
        let slug = String(n.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" })
        let folder = "~/.claude-" + slug
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

struct GeneralPage: View {
    @ObservedObject var state: SettingsState
    @ObservedObject var store: ProfileStore
    @State private var loginOn = SMAppService.mainApp.status == .enabled
    @State private var chats: [(Profile, Int, Int64)] = []
    @State private var own: Int64 = 0
    @Environment(\.face) private var face

    var body: some View {
        VStack(spacing: 14) {
            SCard(title: "Quick chat", info: "A floating chat over any app. Your own Claude Code answers, on the profile's account in use, and it counts against its limits. It sends nothing but your messages; no tools.") {
                SRow(label: "Shortcut", info: "Opens the chat from any app. Registered the way macOS's own app shortcuts are, so there's no Accessibility permission to give.", first: true, stacked: true) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            SSwitch(isOn: Binding(get: { state.settings.shortcutOn }, set: { state.settings.shortcutOn = $0; state.save() }),
                                    on: "\(state.settings.shortcut.title) opens it", off: "off")
                            if state.recording == nil {
                                Picker("", selection: Binding(get: { state.settings.shortcut.id }, set: { pick($0) })) {
                                    ForEach(choices) { Text($0.title).tag($0.id) }
                                    Divider()
                                    Text("Record another…").tag("record")
                                }
                                .smallMenu().disabled(!state.settings.shortcutOn)
                            }
                        }
                        if let r = state.recording { recorderRow(r) } else { shortcutNote }
                    }
                }
                SRow(label: "Model", info: "The model a new chat starts with; the chat's own picker changes it for one chat.") {
                    Picker("", selection: Binding(get: { state.settings.model }, set: { state.settings.model = $0; state.save() })) {
                        ForEach(QuickChatModelChoice.allCases) { Text($0.title).tag($0) }
                    }.smallMenu()
                }
                SRow(label: "Thinking", info: "How long Claude thinks before it answers in a new chat. Off is fastest.") {
                    Picker("", selection: Binding(get: { state.settings.thinking }, set: { state.settings.thinking = $0; state.save() })) {
                        ForEach(QuickChatThinking.allCases) { Text($0.title).tag($0) }
                    }.smallMenu()
                }
                SRow(label: "Open at login", info: "cl_quick starts with the Mac, in the menu bar, ready for the shortcut. No Dock icon.") {
                    SSwitch(isOn: Binding(get: { loginOn }, set: { setLogin($0) }), on: "in the menu bar", off: "off")
                }
            }
            SCard(title: "Files", info: "Everything cl_quick keeps, and one button to remove it all.") {
                SRow(label: "Chats", info: "cl_quick runs Claude Code without keeping a session, so no transcript is written anywhere. A chat lives only in the running Claude Code, which ends after 15 minutes idle, on New chat (⌘N), on another profile or account, or when cl_quick quits.", first: true, stacked: true) {
                    Text("Quick chats are incognito: no message is saved on this Mac. Your messages still go to Anthropic under the profile's account.")
                        .font(.system(size: 12)).foregroundStyle(face.soft).fixedSize(horizontal: false, vertical: true)
                }
                // chats saved by earlier versions, which Remove cl_quick data… still takes
                if !chats.isEmpty {
                    SRow(label: "Old chats", info: "Quick chats saved by earlier versions: Claude Code sessions in each profile's folder under projects/, deleted by Claude Code after 30 days by default.", stacked: true) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(chats, id: \.0.id) { p, n, b in
                                Text("\(p.name): \(n == 1 ? "1 chat" : "\(n) chats"), \(Files.size(b))").font(.system(size: 12)).foregroundStyle(face.soft)
                            }
                        }
                    }
                }
                SRow(label: "cl_quick's own", stacked: true) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tilde(Files.folder.path)).font(.system(size: 11, design: .monospaced)).foregroundStyle(face.soft)
                        Text("Its profiles, settings and work folders, \(Files.size(own)). Outside it: the login item, and any folder Sign in another account… made (a Claude Code folder, which Remove leaves).")
                            .font(.system(size: 10.5)).foregroundStyle(face.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: 8) {
                    Button("Show in Finder") { Files.reveal(Files.folder) }
                    Button("Remove cl_quick data…") { confirmRemove() }
                }
                .buttonStyle(PillButtonStyle(compact: true)).padding(.top, 8)
            }
        }
        .onAppear(perform: count)
        .onDisappear { state.stopRecording() }
    }

    // MARK: Record another… (the listening itself is SettingsState's, so closing the window ends it)

    /// The five Space shortcuts, and the recorded one when it's none of them.
    private var choices: [QuickChatShortcut] {
        QuickChatShortcut.presets + (state.settings.shortcut.isPreset ? [] : [state.settings.shortcut])
    }

    private func pick(_ id: String) {
        if id == "record" { state.startRecording(); return }
        guard let s = choices.first(where: { $0.id == id }) else { return }
        state.settings.shortcut = s; state.save()
    }

    @ViewBuilder private func recorderRow(_ r: QuickChatShortcut?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                DisplayWindow(text: r?.title ?? "Press the shortcut…", tone: r == nil ? .amber : .normal, height: 22, size: 10)
                if let r, r.refused == nil {
                    Button(r.clash() == nil ? "Keep" : "Keep anyway") { state.stopRecording(keep: r) }
                }
                if r != nil { Button("Record again") { state.recording = .some(nil) } }
                Button("Cancel") { state.stopRecording() }
            }
            .buttonStyle(PillButtonStyle(compact: true))
            if let r {
                if let why = r.refused { note(why, face.danger) }
                else if let c = r.clash() { note(c + " Keep it anyway, or record another.", face.caution) }
                else { note(noClashWords(r), face.ok) }
            } else {
                note("Hold ⌘, ⌃ or ⌥ and press a key. Esc cancels. \(state.settings.shortcut.title) is off while you record, and back when you keep a new one or cancel.", face.muted)
            }
        }
    }

    @ViewBuilder private var shortcutNote: some View {
        let s = state.settings.shortcut
        if !state.settings.shortcutOn {
            note("Off: Quick chat in cl_quick's menu opens it.", face.muted)
        } else if let st = QuickChat.shared.shortcutState, st != "on" {
            note(st + " Pick another.", face.danger)
        } else if let c = s.clash() {
            note(c + " Pick another, or change it where it's set.", face.caution)
        } else {
            note(noClashWords(s), face.ok)
        }
    }

    /// Only macOS's Space shortcuts and Quick Entry are known; another key is said to be unchecked, not free.
    private func noClashWords(_ s: QuickChatShortcut) -> String {
        s.keyCode == UInt32(kVK_Space) ? "No clash found." : "Only Space shortcuts are checked for clashes."
    }

    private func note(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 10.5)).foregroundStyle(c).fixedSize(horizontal: false, vertical: true)
    }

    private func setLogin(_ on: Bool) {
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch {}
        loginOn = SMAppService.mainApp.status == .enabled
    }

    private func count() {
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
        let kim = AccountEntry(id: "u2", email: "kim@example.org", inUse: false, level: level(nil, 98, ago: 2 * 86400 + 600))
        let lee = AccountEntry(id: "u3", email: "lee@example.com", inUse: false, level: nil)
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
            var a = alex; a.inUse = false; a.plan = nil
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
            var a = alex; a.inUse = false; a.plan = nil
            let signing = page == "accounts-signing"
            tiles[0] = .init(id: "main", name: "Main", sub: "default · " + (signing ? "switching…" : "signed out"), lamp: signing ? .waiting : .broken)
            view = profile(ProfileModel(name: "Main", path: "~/.claude", entries: [a], folderSignedOut: true, folderSigning: signing, isDefault: true))
        case "accounts-other":
            // a profile that isn't the default
            at = .profile("work")
            let sam = AccountEntry(id: "u5", email: "sam@work.example", plan: "Team", inUse: true, level: level(8, 18, ago: 3 * 3600))
            view = profile(ProfileModel(name: "Work", path: "~/.claude-work", entries: [sam], inPicker: false))
        case "accounts-forget":
            // Forget…'s question: an alert, so drawn here from its words
            view = AnyView(VStack(alignment: .leading, spacing: 14) {
                profile(main)
                VStack(alignment: .leading, spacing: 8) {
                    Text(ForgetWords.title("kim@example.org")).font(.system(size: 13, weight: .bold))
                    Text(ForgetWords.detail(profile: "Main")).font(.system(size: 11.5)).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Spacer()
                        Button("Cancel") {}
                        Button("Forget") {}
                    }.buttonStyle(.sentenceKey())
                }
                .padding(16).frame(width: 340)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.2)))
                .frame(maxWidth: .infinity)
            })
        case "add-refused":
            // the + tile after a folder whose account is in use on another profile was refused (sample address and folder)
            at = .add
            view = AnyView(SCard(title: "Add a profile") {
                SRow(label: "Found on this Mac", first: true, stacked: true) {
                    AccountBox(title: maskEmail("ultra-1@example.com"), detail: "Max · ~/.claude-sample", lit: true, status: "Signed in", tone: .ok,
                               badge: AnyView(Button("Add") {}.buttonStyle(PillButtonStyle(compact: true))))
                }
                SRow(label: "Another folder", stacked: true) {
                    Button("Choose a folder…") {}.buttonStyle(PillButtonStyle(compact: true))
                }
                SRowLine(text: ProfileStore.inUseWords("ultra-1@example.com", on: "Main"), color: FaceTheme.std.danger)
            })
        default:
            at = .general
            view = AnyView(GeneralPage(state: st, store: ProfileStore.shared))
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
