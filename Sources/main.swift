// cl_quick: a floating Claude chat on a shortcut, answered by your own Claude Code on the profile you pick, on that
// profile's account in use, counting against its limits. A small menu bar app with no Dock icon (LSUIElement), its own
// login item, and one `claude` at a time.
//
// Command line, for checking:
//   --render-quick-chat OUT.png STATE   the bar or the chat window with sample data (bar, typing, notinstalled,
//                                       streaming, answer, failed, notsigned, thinking, full, level95; with accounts:
//                                       switch (a full week with Switch to…), switching (waiting for the sign-in),
//                                       wrong (another account signed in), timedout (no sign-in in 10 minutes),
//                                       switched (the new chat's first line); incognito: ended-idle, ended-stopped,
//                                       ended-failed, ended-closed (the line under a chat that ended))
//   --render-settings OUT.png PAGE      the settings window with sample profiles: a profile (profile, accounts-one,
//                                       accounts-two, accounts-switching, accounts-wrong, accounts-timedout,
//                                       accounts-again, accounts-stopped, accounts-signedout, accounts-signing,
//                                       accounts-other, accounts-forget), Add a profile (add, first, add-refused,
//                                       add-empty) and General (general, general-clash, general-off,
//                                       general-recording, general-taken, general-fable, general-haiku,
//                                       general-nolist)
//   --version

import AppKit
import SwiftUI

let args = CommandLine.arguments

if args.count >= 2, args[1] == "--version" {
    print(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
    exit(0)
}

if args.count >= 4, args[1] == "--render-quick-chat" {
    Files.readOnly = true
    if #available(macOS 14, *) { MainActor.assumeIsolated { QuickChatRender.write(to: args[2], state: args[3]) } }
    exit(0)
}

if args.count >= 4, args[1] == "--render-settings" {
    Files.readOnly = true
    if #available(macOS 14, *) { MainActor.assumeIsolated { SettingsRender.write(to: args[2], page: args[3]) } }
    exit(0)
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var item: NSStatusItem?
    private let chat = QuickChat.shared

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // the first run: the Claude Code folders found become profiles, and cl_audit's quick chat settings come along
        let store = ProfileStore.shared
        var s = chat.settings
        let firstRun = !store.hasProfiles && !FileManager.default.fileExists(atPath: Files.profiles.path)
        if firstRun { store.adoptFound() }
        if !s.importedFromAudit {
            s.importFromAuditOnce()
            chat.settingsChanged(s)
        }
        chat.openSettings = { id in SettingsWindow.shared.show(profile: id) }
        chat.start()
        let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        it.button?.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "cl_quick")
        it.button?.image?.isTemplate = true
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        it.menu = menu
        item = it
        if firstRun { SettingsWindow.shared.show(profile: nil, firstRun: true) }
    }

    func applicationWillTerminate(_ note: Notification) { chat.shutdown() }

    /// The menu: Quick chat with its shortcut, each profile's week as last reported, Settings… and Quit.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let open = NSMenuItem(title: "Quick chat", action: #selector(openChat), keyEquivalent: "")
        open.target = self
        if chat.settings.shortcutOn, chat.shortcutState == "on" {
            open.attributedTitle = NSAttributedString(string: "Quick chat   \(chat.settings.shortcut.title)")
        }
        menu.addItem(open)
        menu.addItem(.separator())
        let store = ProfileStore.shared
        store.noteAccounts()
        store.reload()          // off the main thread; the next look at the menu has what changed
        for p in store.profiles {
            let l = store.level(of: p)
            let words = l?.full() != nil ? "full" : l?.weekNow().map { "week \(Int($0.rounded()))%" } ?? "no numbers yet"
            let i = NSMenuItem(title: "\(p.name)   \(words)", action: #selector(openProfile(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = p.id
            menu.addItem(i)
        }
        if !store.profiles.isEmpty { menu.addItem(.separator()) }
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(NSMenuItem(title: "Quit cl_quick", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func openChat() { chat.open() }
    @objc private func openProfile(_ sender: NSMenuItem) { chat.open(profile: sender.representedObject as? String) }
    @objc private func openSettings() { SettingsWindow.shared.show(profile: nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
