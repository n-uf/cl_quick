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
            ProfileStore.shared.noteAccounts()
            let used = Set(ProfileStore.shared.profiles.map(\.path))
            self.signingIn = self.signingIn.filter { ClaudeFolder.email($0) == nil && used.contains($0) }
            if Date().timeIntervalSince(self.since) > 600 { self.signingIn = [] }
            self.tick += 1
            if self.signingIn.isEmpty { self.timer?.invalidate() }
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
    let folder: String
    var level: QuickChatLevel? = nil
    var signingIn = false
    var badge: AnyView? = nil
    @Environment(\.face) private var face

    var body: some View {
        let email = ClaudeFolder.email(folder)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                LED(color: face.ok, lit: email != nil, size: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(email.map(maskEmail) ?? tilde(folder)).font(.system(size: 13, weight: .semibold)).foregroundStyle(face.text)
                    Text(([ClaudeFolder.plan(folder)].compactMap { $0 } + [tilde(folder)]).joined(separator: " · "))
                        .font(.system(size: 11)).foregroundStyle(face.muted)
                }
                Spacer(minLength: 8)
                if let badge { badge }
                else if signingIn { DisplayWindow(text: "Signing in", tone: .amber, height: 18, size: 9) }
                else { DisplayWindow(text: email == nil ? "Not signed in" : "Signed in", tone: email == nil ? .normal : .ok, height: 18, size: 9) }
            }
            if let level { WeekSegments(level: level) }
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

struct ProfilePage: View {
    @ObservedObject var state: SettingsState
    @ObservedObject var store: ProfileStore
    let profile: Profile
    @State private var name = ""
    @Environment(\.face) private var face

    var body: some View {
        SCard(title: "Profile", info: "A Claude Code folder cl_quick chats on, with the account signed in to it. The chat answers on that account and counts against its limits.") {
            SRow(label: "Name", first: true) {
                TextField("", text: $name, onCommit: rename).textFieldStyle(.plain).font(.system(size: 13)).frame(maxWidth: 220)
                    .onAppear { name = profile.name }
                    .onChange(of: profile.id) { _ in name = profile.name }
            }
            SRow(label: "Account", info: "Read from the folder's own Claude Code file, never the Keychain. The week is what Claude Code reported after the last answer on this profile; cl_quick reads no usage of its own.", stacked: true) {
                AccountBox(folder: profile.path, level: store.levels[profile.id], signingIn: state.signingIn.contains(profile.path))
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

    private func rename() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != profile.name else { name = profile.name; return }
        var p = profile; p.name = n; store.update(p)
    }

    private func confirmRemove() {
        let a = NSAlert()
        a.messageText = "Remove \(profile.name) from cl_quick?"
        a.informativeText = "cl_quick forgets it. The folder \(tilde(profile.path)), its sign-in and its sessions stay as they are."
        a.addButton(withTitle: "Remove"); a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
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
                SRow(label: "Chats", info: "Claude Code sessions, kept by Claude Code in each profile's folder under projects/, and deleted after 30 days by default.", first: true, stacked: true) {
                    VStack(alignment: .leading, spacing: 4) {
                        if chats.isEmpty { Text("None yet.").font(.system(size: 12)).foregroundStyle(face.muted) }
                        ForEach(chats, id: \.0.id) { p, n, b in
                            Text("\(p.name): \(n == 1 ? "1 chat" : "\(n) chats"), \(Files.size(b))").font(.system(size: 12)).foregroundStyle(face.soft)
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
        a.informativeText = "This moves \(n == 1 ? "1 quick chat" : "\(n) quick chats") and cl_quick's profiles, settings and work folders to the Trash. Open at login turns off and cl_quick quits. Your Claude Code folders, their sign-ins and their other sessions stay; you can bring these back from the Trash."
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
