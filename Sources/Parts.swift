// Parts: the settings window's pieces, taken as they are from cl_audit (Settings.swift and SettingsLayout.swift):
// tiles, cards, rows, the (i), the on/off switch and the segmented choice. The look itself is Faces.swift and Style.swift.

import SwiftUI

enum SwitchProgress: Equatable { case working, done, failed(String) }

/// On/off: the lamp switch (LEDSwitchKey), then a few words that follow the state ("shown and alerted" / "left out");
/// no words when both are empty (a label already beside it). Every on/off in cl_audit is this switch. A change shows
/// while it's under way: the LED pulses green turning on, red turning off, and the words say "turning on…" /
/// "turning off…"; clicks wait until it's done. An instant setting pulses once, briefly, as a confirmation. A slow
/// one (`progress`: an app installed or removed, an icon the agent puts up) pulses until the work is really done; if
/// it fails, two red blinks, the switch goes back, and one grey line under it says why.
struct SSwitch: View {
    @Binding var isOn: Bool
    let on: String
    let off: String
    /// Shorter "on" words for a narrow column (340 pt), used only when the full ones don't fit.
    var onShort: String? = nil
    /// A slow change: how far the change to this state, started then, has got; asked every half second. A provider
    /// that undoes a failed change itself leaves the switch nothing to put back. nil: an instant setting.
    var progress: ((Bool, Date) -> SwitchProgress)? = nil
    /// Offscreen renders only: a moment of a change to draw.
    var moment: Moment? = nil
    enum Moment { case changing(to: Bool), failing, failed(why: String) }

    @State private var target: Bool?            // a change under way, to this state
    @State private var since = Date()
    @State private var failing = false          // its two red blinks
    @State private var why: String?             // the last change failed: why, under the switch
    @Environment(\.face) private var face
    @Environment(\.isEnabled) private var enabled

    /// How long a change pulses at least: an instant setting's confirmation.
    static let brief: UInt64 = 600_000_000

    private var changingTo: Bool? {
        if let moment { if case .changing(let t) = moment { return t }; return nil }
        return target
    }
    private var blinking: Bool {
        if let moment { if case .failing = moment { return true }; return false }
        return failing
    }
    private var reason: String? {
        if let moment { if case .failed(let w) = moment { return w }; return nil }
        return target == nil ? why : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                // a Toggle, so VoiceOver has a switch; its clicks go through flip()
                Toggle("", isOn: Binding(get: { isOn }, set: { _ in flip() }))
                    .toggleStyle(LEDSwitchStyle(pulse: changingTo.map(FaceTheme.changing(to:)), failing: blinking))
                    .labelsHidden()
                if !(on.isEmpty && off.isEmpty) { words }
            }
            if let reason { Text(reason).font(.system(size: 11)).foregroundStyle(face.muted).lineLimit(1).help(reason) }
        }
        .alignmentGuide(.rowLine) { _ in 11 }          // the middle of the key, with or without the line under it
        .task(id: target) { await follow() }
    }

    @ViewBuilder private var words: some View {
        if let t = changingTo {
            word(t ? "turning on…" : "turning off…")
        } else if isOn, let onShort {
            ViewThatFits(in: .horizontal) { word(on).fixedSize(); word(onShort) }
        } else if !(isOn ? on : off).isEmpty {
            word(isOn ? on : off)
        }
    }

    private func word(_ s: String) -> some View {
        Text(s).font(.system(size: 11.5)).foregroundStyle(face.muted).lineLimit(1).opacity(enabled ? 1 : 0.6)
    }

    private func flip() {
        guard target == nil, !failing, moment == nil else { return }       // a second click while it changes: ignored
        let t = !isOn
        why = nil
        since = Date()
        isOn = t
        target = t
    }

    /// The change under way, followed to its end.
    @MainActor private func follow() async {
        guard let t = target else { return }
        try? await Task.sleep(nanoseconds: Self.brief)
        guard let progress else { target = nil; return }
        while !Task.isCancelled {
            switch progress(t, since) {
            case .done:
                target = nil
                return
            case .failed(let w):
                failing = true
                try? await Task.sleep(nanoseconds: 700_000_000)
                why = w
                let undo = isOn == t                     // the provider may have put it back already
                target = nil                             // (ends this task once it returns)
                failing = false
                if undo { isOn = !t }
                return
            case .working:
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }
}

/// Two or three short choices beside a row's label: segments in a recessed track, the chosen one raised.
struct SSegments<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    var enabled: (Value) -> Bool = { _ in true }
    let title: (Value) -> String

    var body: some View {
        PillPicker(options: options, selection: Binding(get: { selection }, set: { if enabled($0) { selection = $0 } }),
                   compact: true, fill: true, title: title)
            .frame(maxWidth: .infinity)
            .alignmentGuide(.rowLine) { d in d[VerticalAlignment.center] }
    }
}

/// The looks of a large thing (a usage panel, a dashboard card, the widget) under a row's label: the choices as
/// segments and, under them, one large preview of the chosen look, together in one pane. Small things (Dock icon
/// styles, menu bar styles and colours) are tiles instead (STiles).

struct SRowLine: View {
    let text: String
    var color: Color? = nil
    @Environment(\.face) private var face

    var body: some View {
        Text(text).font(.system(size: 10.5)).foregroundStyle(color ?? face.muted)
            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 4)
    }
}

/// A card's preview, at its foot: "Preview" and what it shows, then the same states left to right (not running or no

/// A tile in the profile strip: a wide key; the chosen one latched down with its strip lit.
struct TileKey<Content: View>: View {
    let selected: Bool
    var leading: CGFloat = 12
    var trailing: CGFloat = 12
    @ViewBuilder let content: Content
    @Environment(\.face) private var face

    var body: some View {
        content
            .foregroundStyle(face.legend)
            .shadow(color: face.legendShadow, radius: 0, y: face.legendShadowY)
            .padding(.leading, leading).padding(.trailing, trailing)
            .frame(minHeight: 42)
            .background(RaisedShape(finish: selected ? face.keyDown : face.key, radius: 4, pressed: selected))
            .overlay { if selected { LampStrip() } }
            .contentShape(Rectangle())
    }
}

/// What a profile includes: Usage in the Dock and Claude window, two keys side by side with what the current choice

struct TileText: View {
    let title: String
    let sub: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10.5, weight: .bold)).tracking(1).textCase(.uppercase).lineLimit(1)
            Text(sub).font(.system(size: 10.5)).opacity(0.65).lineLimit(1)
        }
        .fixedSize()
    }
}

// MARK: - Cards and rows

/// A settings card: a raised module with a printed label, an engraved rule after it, and its rows.
struct SCard<Content: View>: View {
    let title: String
    var info: String? = nil
    @ViewBuilder let content: Content
    @Environment(\.face) private var face

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Printed(text: title)
                if let info { InfoDot(text: info) }
                EngravedRule(dark: face.light ? .black(0.28) : nil).frame(minWidth: 12)
            }
            .padding(.bottom, 4)
            VStack(spacing: 0) { content }
        }
        .padding(.horizontal, 14).padding(.top, 13).padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RaisedShape(finish: face.module, radius: face.moduleRadius))
    }
}

/// A settings row: the label in a fixed column and the control right after it (never pushed to the card's
/// far edge), or, for wide controls, the label above the control.
extension VerticalAlignment {
    private enum RowLine: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[VerticalAlignment.center] }
    }
    /// The line a settings row's label lines up with: the middle of its control, or a field's own line when the field
    /// has a message under it.
    static let rowLine = VerticalAlignment(RowLine.self)
}

struct SRow<Control: View>: View {
    let label: String
    var info: String? = nil
    var first = false
    var stacked = false
    var picture: AnyView? = nil        // a small illustration inside the (i)
    @ViewBuilder let control: Control
    @Environment(\.face) private var face

    static var labelWidth: CGFloat { 146 }      // the longest label with its (i): "Usage in the Dock"
    /// A card with long values (accounts, paths, the address row) narrower than this stacks its rows, so they show
    /// whole: New profile's Claude Code card and Settings ▸ a profile ▸ Claude Code (one rule for both).
    static var stackBelow: CGFloat { 480 }

    var body: some View {
        VStack(spacing: 0) {
            if !first { EngravedRule() }
            if stacked {
                VStack(alignment: .leading, spacing: 6) { title; control }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .rowLine, spacing: 10) {
                    title.frame(width: Self.labelWidth, alignment: .leading)
                    control
                }
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)     // no spacer: its spacing would take 10 pt
            }
        }
    }

    private var title: some View {
        HStack(spacing: 5) {
            Text(label).font(.system(size: 12.5)).foregroundStyle(face.soft).lineLimit(1)
            if let info { InfoDot(text: info, picture: picture) }
        }
    }
}

/// Hands its content the width of the settings column it's in (SettingsColumns sets it), read where the card is drawn:
/// a card built by a page above the columns can't read the column's environment itself.

struct InfoDot: View {
    let text: String
    var picture: AnyView? = nil
    @State private var open = false
    @State private var hover = false

    var body: some View {
        Button { open.toggle() } label: {
            Image(systemName: open ? "info.circle.fill" : "info.circle")
                .font(.system(size: 10.5))
                .foregroundStyle(hover || open ? Color.secondary : Color.secondary.opacity(0.6))
                .frame(width: 16, height: 16)          // a bigger target than the glyph
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(text)
        .accessibilityLabel("About this setting")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 9) {
                Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                if let picture { picture }
            }
            .frame(width: 260, alignment: .leading).padding(12)
        }
    }
}



extension View {
    /// The on/off switch: a small key with an LED, green while on.
    func smallSwitch() -> some View {
        toggleStyle(LEDSwitchStyle()).labelsHidden()
    }
    func smallMenu() -> some View { labelsHidden().pickerStyle(.menu).controlSize(.small).fixedSize() }
}

