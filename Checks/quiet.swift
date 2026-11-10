// The checks that open the real panel (Checks/panel, Checks/bars) run beside the operator's own work, so they must never
// show anything or take the keyboard. `CheckQuiet.start()` makes this program an accessory app (no Dock icon, no menu
// bar) and turns on QCQuiet (Sources/Chat.swift: the panel lives against a stand-in screen far off every real one,
// ordered in invisible and click-through, and never becomes the key window). The guard then watches, every 20 ms of
// run-loop time and at every `CheckQuiet.verify` call: a visible window of this program whose frame touches any real
// screen, a key window, or this program becoming the active app stops the run at once (exit 3, everything ordered out),
// so a check that would disturb the session fails loudly instead.

import AppKit

enum CheckQuiet {
    private static var timer: Timer?

    static func start() {
        QCQuiet.on = true
        NSApplication.shared.setActivationPolicy(.accessory)
        let t = Timer(timeInterval: 0.02, repeats: true) { _ in verify("while running") }
        RunLoop.main.add(t, forMode: .common)
        RunLoop.main.add(t, forMode: .eventTracking)
        timer = t
    }

    /// Stops the run if anything of this program could be seen or could take the keyboard.
    static func verify(_ when: String) {
        if NSApp.isActive { stop("the check program became the active app (\(when))") }
        if let k = NSApp.keyWindow { stop("a window took the keyboard: \(type(of: k)) \(k.frame) (\(when))") }
        let screens = NSScreen.screens.map(\.frame)
        for w in NSApp.windows where w.isVisible {
            if let s = screens.first(where: { $0.intersects(w.frame) }) {
                stop("a visible window is on a screen: \(type(of: w)) \(w.frame) on \(s) (\(when))")
            }
            if w is QuickChatPanel, w.alphaValue > 0 {
                stop("the panel is ordered in visible: alpha \(w.alphaValue) (\(when))")
            }
        }
    }

    private static func stop(_ why: String) {
        NSApp.windows.forEach { $0.orderOut(nil) }
        FileHandle.standardError.write("GUARD FAIL: \(why)\n".data(using: .utf8)!)
        print("GUARD FAIL: \(why)")
        exit(3)
    }
}
