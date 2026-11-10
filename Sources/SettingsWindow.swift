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
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 600), styleMask: [.titled, .closable, .resizable],
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
                tiles
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
        .frame(minWidth: 520, minHeight: 460)
        .background(RaisedShape(finish: face.chassis, radius: 0))
    }

    private var tiles: some View {
        FlowTiles {
            TileKey(selected: state.page == .general) { TileText(title: "General", sub: "chat · shortcut · files") }
                .onTapGesture { state.page = .general }
            ForEach(store.profiles) { p in
                TileKey(selected: state.page == .profile(p.id)) {
                    TileText(title: p.name, sub: tilde(p.path) + (p.id == defaultID ? " · default" : ""))
                }
                .onTapGesture { state.page = .profile(p.id) }
            }
            TileKey(selected: state.page == .add) { Text("+").font(.system(size: 20, weight: .light)).frame(minWidth: 14) }
                .onTapGesture { state.page = .add }
                .help("Add a profile")
        }
        .padding(9)
        .background(SurfaceShape(surface: face.strip, radius: 8))
    }

    private var defaultID: String? { state.settings.defaultProfile ?? store.profiles.first?.id }
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
    init(folder: String, level: QuickChatLevel? = nil, signingIn: Bool = false, badge: AnyView? = nil) {
        let email = ClaudeFolder.email(folder)
        self.init(title: email.map(maskEmail) ?? tilde(folder),
                  detail: ([ClaudeFolder.plan(folder)].compactMap { $0 } + [tilde(folder)]).joined(separator: " · "),
                  lit: email != nil,
                  status: signingIn ? "Signing in" : email == nil ? "Not signed in" : "Signed in",
                  tone: signingIn ? .amber : email == nil ? .normal : .ok, level: level, badge: badge)
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

/// What one account's box on a profile's card shows.
struct AccountEntry: Identifiable, Equatable {
    var id: String
    var email: String
    var detail: String
    /// The one signed in to the folder now; the others are standby.
    var inUse: Bool
    var level: QuickChatLevel?
    /// A sign-in for it is being waited for.
    var signing = false
}

/// A profile's accounts: the one in use ("In use", its week, Sign in again…), then the standby ones ("Standby", their
/// last week or "no numbers yet", Switch to this account…).
struct AccountList: View {
    let entries: [AccountEntry]
    /// A sign-in is being waited for: switching waits.
    var busy = false
    var switchTo: (AccountEntry) -> Void = { _ in }
    var signInAgain: (AccountEntry) -> Void = { _ in }
    /// Only a standby account can be forgotten.
    var forget: (AccountEntry) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(entries) { e in
                AccountBox(title: maskEmail(e.email), detail: e.detail, lit: e.inUse,
                           status: e.signing ? "Signing in" : e.inUse ? "In use" : "Standby",
                           tone: e.signing ? .amber : e.inUse ? .ok : .normal,
                           level: e.level, noWeek: "no numbers yet",
                           actions: AnyView(HStack(spacing: 8) {
                               if e.inUse { Button("Sign in again…") { signInAgain(e) }.disabled(busy) }
                               else {
                                   Button("Switch to this account…") { switchTo(e) }.disabled(busy)
                                   Button("Forget…") { forget(e) }.disabled(busy)
                               }
                           }.buttonStyle(PillButtonStyle(compact: true))))
            }
        }
    }
}

/// What the Forget… question says (the alert and its picture for checking).
enum ForgetWords {
    static func title(_ email: String) -> String { "Forget \(maskEmail(email))?" }
    static func detail(profile: String) -> String {
        "cl_quick drops this account from \(profile)'s list, with its week. Nothing is signed out and no session is touched; it comes back if it's signed in on this folder again."
    }
}

/// Under a profile's accounts: a sign-in being waited for (Show Terminal, Stop waiting), or a switch that ended without
/// the account wanted, because another one signed in or because 10 minutes passed (Switch to … again…, Dismiss).
struct SwitchLines: View {
    var waiting: SwitchGoal?
    var ended: SwitchEnded?
    /// The address a sign-in again just ended on: the same account.
    var signedAgain: String?
    var showTerminal: () -> Void = {}
    var drop: () -> Void = {}
    var signInAgain: (SwitchGoal) -> Void = { _ in }
    @Environment(\.face) private var face

    var body: some View {
        if let signedAgain, waiting == nil, ended == nil {
            SRowLine(text: "Signed in again as \(maskEmail(signedAgain)).", color: face.ok)
            Button("Dismiss", action: drop).buttonStyle(PillButtonStyle(compact: true))
        } else if let waiting {
            SRowLine(text: "Waiting for the sign-in… Finish it in Terminal and the browser as \(maskEmail(waiting.wantedEmail)). cl_quick looks at the folder every 2 s, for 10 minutes.", color: face.caution)
            HStack(spacing: 8) {
                Button("Show Terminal", action: showTerminal)
                Button("Stop waiting", action: drop)
            }.buttonStyle(PillButtonStyle(compact: true))
        } else if let m = ended {
            SRowLine(text: m.signedIn.map { "Signed in as \(maskEmail($0)), not \(maskEmail(m.goal.wantedEmail))." }
                        ?? "No sign-in in 10 minutes. The account in use hasn't changed.", color: face.danger)
            HStack(spacing: 8) {
                // named after the account the switch was for, so it doesn't read as the in-use account's own Sign in again…;
                // a sign-in again that never came is just that again
                Button(m.goal.again && m.signedIn == nil ? "Sign in again…" : "Switch to \(maskEmail(m.goal.wantedEmail)) again…") { signInAgain(m.goal) }
                Button("Dismiss", action: drop)
            }.buttonStyle(PillButtonStyle(compact: true))
        }
    }
}

struct ProfilePage: View {
    @ObservedObject var state: SettingsState
    @ObservedObject var store: ProfileStore
    let profile: Profile
    @State private var name = ""
    @State private var address = ""
    @State private var problem: String?
    @Environment(\.face) private var face

    private var switcher: AccountSwitcher { .shared }

    var body: some View {
        let waiting = switcher.waiting[profile.id], ended = switcher.ended[profile.id]
        SCard(title: "Profile", info: "A Claude Code folder cl_quick chats on, with its accounts: the one signed in now, in use, and the others on standby. The chat answers on the account in use and counts against its limits.") {
            SRow(label: "Name", first: true) {
                TextField("", text: $name, onCommit: rename).textFieldStyle(.plain).font(.system(size: 13)).frame(maxWidth: 220)
                    .onAppear { name = profile.name; store.noteAccount(of: profile.id) }
                    .onChange(of: profile.id) { _ in name = profile.name; problem = nil; address = "" }
            }
            SRow(label: "Accounts", info: "A folder holds one signed-in account at a time. Switching signs in again in this same folder, as the other account, so every Claude Code session using it moves to that account. Read from the folder's own Claude Code file, never the Keychain. The week is what Claude Code reported after the last answer on that account; cl_quick reads no usage of its own.", stacked: true) {
                VStack(alignment: .leading, spacing: 6) {
                    if store.inUse(profile) == nil {
                        AccountBox(folder: profile.path, signingIn: state.signingIn.contains(profile.path))
                    }
                    AccountList(entries: entries(waiting), busy: waiting != nil,
                                switchTo: { e in switcher.confirmAndSwitch(profile, uuid: e.id, email: e.email, origin: .settings) },
                                signInAgain: { _ in switcher.signInAgain(profile, origin: .settings) },
                                forget: { e in confirmForget(e) })
                    SwitchLines(waiting: waiting, ended: ended, signedAgain: switcher.signedAgain[profile.id],
                                showTerminal: { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")) },
                                drop: { switcher.drop(profile.id) },
                                signInAgain: { g in switcher.begin(profile, uuid: g.wantedUUID, email: g.wantedEmail, origin: .settings) })
                }
            }
            SRow(label: "Another account", info: "Signs in again in this folder, as that address: Claude Code's sign-in opens in Terminal and the browser decides which account signs in. The account becomes the one in use, and the one now in use stays here on standby.", stacked: true) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        TextField("Address, e.g. you@example.com", text: $address).textFieldStyle(.plain).font(.system(size: 13)).frame(maxWidth: 230)
                        Button("Add an account…") { addAccount() }.buttonStyle(PillButtonStyle(compact: true))
                            .disabled(!Self.looksLikeAddress(address) || waiting != nil)
                    }
                    if let problem { SRowLine(text: problem, color: face.danger) }
                }
            }
            SRow(label: "Default", info: "The profile the shortcut chats on. The chat's picker changes it for one chat.") {
                SSwitch(isOn: Binding(get: { (state.settings.defaultProfile ?? store.profiles.first?.id) == profile.id },
                                      set: { if $0 { state.settings.defaultProfile = profile.id; state.save() } }),
                        on: "the shortcut chats on \(profile.name)", off: "not the default")
            }
            SRow(label: "In the chat", info: "Offered in the chat's profile picker, and as somewhere to ask when another profile's week is full.") {
                SSwitch(isOn: Binding(get: { profile.inPicker }, set: { var p = profile; p.inPicker = $0; store.update(p) }),
                        on: "in the profile picker", off: "left out")
            }
            HStack(spacing: 8) {
                Button("Show in Finder") { Files.reveal(URL(fileURLWithPath: profile.path)) }
                if state.signingIn.contains(profile.path) { Button("Show Terminal") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")) } }
                Button("Remove from cl_quick…") { confirmRemove() }
            }
            .buttonStyle(PillButtonStyle(compact: true)).padding(.top, 8)
        }
    }

    /// The account in use first, then the standby ones.
    private func entries(_ waiting: SwitchGoal?) -> [AccountEntry] {
        var out: [AccountEntry] = []
        if let u = store.inUse(profile) {
            out.append(AccountEntry(id: u.uuid, email: u.email,
                                    detail: ([ClaudeFolder.plan(profile.path)].compactMap { $0 } + [tilde(profile.path)]).joined(separator: " · "),
                                    inUse: true, level: store.level(of: profile, account: u.uuid), signing: waiting?.again == true))
        }
        for a in store.standby(profile) {
            let signing = waiting.map { $0.wantedUUID == a.id || $0.wantedEmail.lowercased() == a.email.lowercased() } ?? false
            out.append(AccountEntry(id: a.uuid, email: a.email, detail: "Last in use \(TimeWords.when(a.lastSeen))", inUse: false,
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
        if store.inUse(profile)?.email.lowercased() == a.lowercased() { problem = "\(maskEmail(a)) is the account in use already."; return }
        problem = nil
        let known = profile.accounts.first { $0.email.lowercased() == a.lowercased() }
        switcher.confirmAndSwitch(profile, uuid: known?.uuid, email: known?.email ?? a, origin: .settings)
        address = ""
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
                    Text("Quick chats are incognito: nothing is saved on this Mac. Your messages still go to Anthropic under the profile's account.")
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
        let view: AnyView
        var lvl = QuickChatLevel(); lvl.week = 62; lvl.weekResets = Date().addingTimeInterval(3 * 86400); lvl.at = Date()
        switch page {
        case "profile":
            view = AnyView(VStack(alignment: .leading, spacing: 14) {
                SCard(title: "Profile") {
                    SRow(label: "Name", first: true) { Text("Main").font(.system(size: 13)) }
                    SRow(label: "Account", stacked: true) {
                        AccountBox(folder: "~/.claude-sample", level: lvl, badge: AnyView(DisplayWindow(text: "Signed in", tone: .ok, height: 18, size: 9)))
                    }
                    SRow(label: "Default") { SSwitch(isOn: .constant(true), on: "the shortcut chats on Main", off: "not the default") }
                    SRow(label: "In the chat") { SSwitch(isOn: .constant(true), on: "in the profile picker", off: "left out") }
                }
            })
        case "accounts", "accounts-timedout", "accounts-forget", "accounts-again":
            // one account in use with its week, one on standby with no numbers yet (sample addresses only); the second
            // page after a sign-in that never came; the third with Forget…'s question (an alert, so drawn here from its words)
            let goal = SwitchGoal(profileID: "main", profileName: "Main", folder: "~/.claude", wantedUUID: "u2",
                                  wantedEmail: "ultra-2@example.com", fromUUID: "u1", fromEmail: "ultra-1@example.com", origin: .settings)
            view = AnyView(VStack(alignment: .leading, spacing: 14) {
                SCard(title: "Profile") {
                    SRow(label: "Name", first: true) { Text("Main").font(.system(size: 13)) }
                    SRow(label: "Accounts", stacked: true) {
                        AccountList(entries: [
                            AccountEntry(id: "u1", email: "ultra-1@example.com", detail: "Max · ~/.claude", inUse: true, level: lvl),
                            AccountEntry(id: "u2", email: "ultra-2@example.com", detail: "Last in use \(TimeWords.when(Date().addingTimeInterval(-2 * 86400)))", inUse: false, level: nil),
                        ])
                        if page == "accounts-timedout" { SwitchLines(ended: SwitchEnded(goal: goal, signedIn: nil)) }
                        if page == "accounts-again" { SwitchLines(signedAgain: "ultra-1@example.com") }
                    }
                    SRow(label: "Another account", stacked: true) {
                        HStack(spacing: 8) {
                            Text(verbatim: "Address, e.g. you@example.com").font(.system(size: 13)).foregroundStyle(FaceTheme.std.muted)
                            Button("Add an account…") {}.buttonStyle(PillButtonStyle(compact: true)).disabled(true)
                        }
                    }
                    SRow(label: "Default") { SSwitch(isOn: .constant(true), on: "the shortcut chats on Main", off: "not the default") }
                    SRow(label: "In the chat") { SSwitch(isOn: .constant(true), on: "in the profile picker", off: "left out") }
                    HStack(spacing: 8) {
                        Button("Show in Finder") {}
                        Button("Remove from cl_quick…") {}
                    }
                    .buttonStyle(PillButtonStyle(compact: true)).padding(.top, 8)
                }
                if page == "accounts-forget" {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(ForgetWords.title("ultra-2@example.com")).font(.system(size: 13, weight: .bold))
                        Text(ForgetWords.detail(profile: "Main")).font(.system(size: 11.5)).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            Spacer()
                            Button("Cancel") {}
                            Button("Forget") {}
                        }.buttonStyle(PillButtonStyle(compact: true))
                    }
                    .padding(16).frame(width: 340)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.2)))
                    .frame(maxWidth: .infinity)
                }
            })
        case "add-refused":
            // the + tile after a folder whose account is in use on another profile was refused (sample address and folder)
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
            view = AnyView(GeneralPage(state: st, store: ProfileStore.shared))
        }
        let r = ImageRenderer(content: view.padding(18).frame(width: 560).face(.std)
            .background(RaisedShape(finish: FaceTheme.std.chassis, radius: 0)))
        r.scale = 2
        if let tiff = r.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
    }
}
