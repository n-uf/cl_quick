// Shortcut: the chat's shortcut. Five Space shortcuts to pick from, or Record another… for any key held with ⌘, ⌃ or ⌥.
//
// It's registered the way macOS's own app shortcuts are (RegisterEventHotKey), so macOS asks for no Accessibility
// permission and it sees no other key. Before it's kept, it's checked against macOS's own shortcuts that use Space
// (Spotlight, Finder's search, the input sources, as this Mac has them) and the Claude app's Quick Entry; a key without
// ⌘, ⌃ or ⌥, or one of macOS's fixed app keys (⌘Q, ⌘W, ⌘H, ⌘M, ⌘Tab), is never kept. Registering it also fails, and says
// so, when another app holds it already.

import AppKit
import Carbon.HIToolbox

struct QuickChatShortcut: Codable, Equatable, Hashable, Identifiable {
    /// The key (Carbon's virtual key code) and its name as shown ("Space", "K", "F5").
    var keyCode: UInt32
    var key: String
    /// Carbon's modifier flags (cmdKey, shiftKey, optionKey, controlKey).
    var carbonModifiers: UInt32

    var id: String { "\(keyCode)-\(carbonModifiers)" }

    static let optionSpace = Self(keyCode: UInt32(kVK_Space), key: "Space", carbonModifiers: UInt32(optionKey))
    static let controlOptionSpace = Self(keyCode: UInt32(kVK_Space), key: "Space", carbonModifiers: UInt32(controlKey | optionKey))
    static let optionShiftSpace = Self(keyCode: UInt32(kVK_Space), key: "Space", carbonModifiers: UInt32(optionKey | shiftKey))
    static let controlSpace = Self(keyCode: UInt32(kVK_Space), key: "Space", carbonModifiers: UInt32(controlKey))
    static let commandSpace = Self(keyCode: UInt32(kVK_Space), key: "Space", carbonModifiers: UInt32(cmdKey))
    static let presets: [Self] = [.optionSpace, .controlOptionSpace, .optionShiftSpace, .controlSpace, .commandSpace]
    var isPreset: Bool { Self.presets.contains(self) }

    private var has: (control: Bool, option: Bool, shift: Bool, command: Bool) {
        (carbonModifiers & UInt32(controlKey) != 0, carbonModifiers & UInt32(optionKey) != 0,
         carbonModifiers & UInt32(shiftKey) != 0, carbonModifiers & UInt32(cmdKey) != 0)
    }

    /// "⌃⌥Space", in macOS's own order.
    var title: String {
        let h = has
        return (h.control ? "⌃" : "") + (h.option ? "⌥" : "") + (h.shift ? "⇧" : "") + (h.command ? "⌘" : "") + key
    }

    /// The same modifiers as macOS writes them in its own shortcuts' settings (NSEvent's flags).
    var cocoaModifiers: Int {
        let h = has
        return (h.control ? 1 << 18 : 0) | (h.option ? 1 << 19 : 0) | (h.shift ? 1 << 17 : 0) | (h.command ? 1 << 20 : 0)
    }

    /// From a key pressed while recording.
    init(event e: NSEvent) {
        keyCode = UInt32(e.keyCode)
        key = Self.name(e)
        let f = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        carbonModifiers = (f.contains(.control) ? UInt32(controlKey) : 0) | (f.contains(.option) ? UInt32(optionKey) : 0)
            | (f.contains(.shift) ? UInt32(shiftKey) : 0) | (f.contains(.command) ? UInt32(cmdKey) : 0)
    }

    init(keyCode: UInt32, key: String, carbonModifiers: UInt32) {
        self.keyCode = keyCode; self.key = key; self.carbonModifiers = carbonModifiers
    }

    /// Older settings named a preset ("optionSpace"); newer ones hold the keys.
    init(from decoder: Decoder) throws {
        if let name = try? decoder.singleValueContainer().decode(String.self) {
            self = Self.preset(named: name) ?? .optionSpace
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try c.decode(UInt32.self, forKey: .keyCode)
        key = try c.decode(String.self, forKey: .key)
        carbonModifiers = try c.decode(UInt32.self, forKey: .carbonModifiers)
    }

    /// cl_audit's names for the presets.
    static func preset(named n: String) -> Self? {
        ["optionSpace": .optionSpace, "controlOptionSpace": .controlOptionSpace, "optionShiftSpace": .optionShiftSpace,
         "controlSpace": .controlSpace, "commandSpace": .commandSpace][n]
    }

    private static func name(_ e: NSEvent) -> String {
        let special: [Int: String] = [kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab", kVK_Delete: "Delete",
            kVK_Escape: "Esc", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
            kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"]
        if let s = special[Int(e.keyCode)] { return s }
        return (e.charactersIgnoringModifiers ?? "?").uppercased()
    }

    /// Why it can't be the shortcut at all, or nil.
    var refused: String? {
        let h = has
        guard h.control || h.option || h.command else { return "\(title) would type into whatever has the keyboard. Hold ⌘, ⌃ or ⌥ too." }
        if h.command, !h.control, !h.option, !h.shift {
            let fixed: [Int: String] = [kVK_ANSI_Q: "quits the app you're in", kVK_ANSI_W: "closes the window you're in",
                                        kVK_ANSI_H: "hides the app you're in", kVK_ANSI_M: "minimises the window you're in",
                                        kVK_Tab: "switches apps"]
            if let does = fixed[Int(keyCode)] { return "\(title) \(does). Pick another." }
        }
        return nil
    }

    /// Who else uses it on this Mac, in words, or nil when nothing known does. macOS's own come from its settings
    /// (com.apple.symbolichotkeys; one never changed there is as macOS ships it).
    func clash(symbolic: [String: Any]? = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys")) -> String? {
        // macOS's shortcuts that use Space: id, what it does, its usual modifiers, and whether it's on as macOS ships
        let system: [(id: String, does: String, usual: Int, onByDefault: Bool)] = [
            ("64", "opens Spotlight", 1 << 20, true), ("65", "opens a Finder search window", 1 << 20 | 1 << 19, false),
            ("60", "switches to the previous input source", 1 << 18, true),
            ("61", "switches to the next input source", 1 << 18 | 1 << 19, false)]
        for s in system {
            if let entry = symbolic?[s.id] as? [String: Any] {
                guard (entry["enabled"] as? NSNumber)?.boolValue ?? false,
                      let params = (entry["value"] as? [String: Any])?["parameters"] as? [NSNumber], params.count >= 3,
                      params[1].uint32Value == keyCode, params[2].intValue == cocoaModifiers else { continue }
                return "\(title) \(s.does) in macOS."
            } else if s.onByDefault, keyCode == UInt32(kVK_Space), s.usual == cocoaModifiers {
                return "\(title) \(s.does) in macOS."
            }
        }
        // the Claude app's Quick Entry is ⌥Space unless changed there; only worth saying where the app is
        if self == .optionSpace, NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") != nil {
            return "\(title) also opens the Claude app's Quick Entry when that's turned on."
        }
        return nil
    }
}

/// The registered shortcut. Main thread only.
final class QuickChatHotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onPress: () -> Void = {}

    /// Registers it (any earlier one goes first). nil: done; otherwise why not, in words.
    func register(_ s: QuickChatShortcut) -> String? {
        unregister()
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let me = Unmanaged.passUnretained(self).toOpaque()
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, data in
                guard let data else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<QuickChatHotKey>.fromOpaque(data).takeUnretainedValue()
                DispatchQueue.main.async { hotKey.onPress() }
                return noErr
            }, 1, &spec, me, &handler)
            guard status == noErr else { return "macOS didn't take it (\(status))." }
        }
        let id = EventHotKeyID(signature: OSType(0x7163_6874), id: 1)    // 'qcht'
        let status = RegisterEventHotKey(s.keyCode, s.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
        switch status {
        case noErr: return nil
        case OSStatus(eventHotKeyExistsErr): return "Another app already uses \(s.title)."
        default: return "macOS didn't take \(s.title) (\(status))."
        }
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }

    var isRegistered: Bool { ref != nil }
}
