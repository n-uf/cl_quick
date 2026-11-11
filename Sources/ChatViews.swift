// QuickChatViews: the quick chat's bar and chat window (QuickChat.swift), in Claude's own dark colours rather than
// cl_audit's front panel: it should feel like Claude. The bar is a field over one row of controls; the first message
// turns it into a chat window: the account line on top, the chat, and the field box at the bottom, all on one 10 pt
// outer gap (QCSpace). Answers are Markdown in the system font, code blocks have Copy, and the last answer says which
// model gave it. The profile is a picker that opens a menu; the model and thinking are bars picked directly
// (QCStepControl).

import AppKit
import SwiftUI

/// Claude's dark colours.
enum QCColor {
    static func hex(_ v: UInt32, _ a: Double = 1) -> Color {
        Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255, opacity: a)
    }
    static let window = hex(0x262624)
    static let surface = hex(0x30302E)
    static let bubble = hex(0x141413)
    static let code = hex(0x1F1E1D)
    static let line = hex(0xDEDCD1, 0.16)
    static let text = hex(0xFAF9F5)
    static let soft = hex(0xC2C0B6)
    static let muted = hex(0x9C9A92)
    static let accent = hex(0xD97757)
    /// The steps that use the limits faster (Fable, Extra, Max): their bars, and the warm control's edge.
    static let ember = hex(0xE8875F)
    static let send = hex(0xC6613F)
    static let hover = hex(0xFAF9F5, 0.07)
    static let inlineCode = hex(0xF0B39A)
    static let codeText = hex(0xE8E6DC)
    static let crimson = hex(0xEB445B)
}

/// Set while drawing to a picture (`--render-quick-chat`): the field is drawn as text, the chat without a scroll view.
private struct QCRenderingKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var qcRendering: Bool {
        get { self[QCRenderingKey.self] }
        set { self[QCRenderingKey.self] = newValue }
    }
}

/// The panel is as wide as the user made it (the bar and the chat share the width). Both modes fill the panel: the chat's
/// answers scroll inside it, the bar's field takes any height above its own (the bar's least height is its content's, which
/// the hosting view reports as its intrinsic height: QuickChat.fit). The card fills the panel, so macOS's own resize zones
/// (QuickChatPanel) lie on its visible edges; the panel's transparent title bar is no safe area.
struct QuickChatRoot: View {
    static let width: CGFloat = 520            // the first width of the card
    static let windowHeight: CGFloat = 580     // the chat's first height
    static let minWidth: CGFloat = 320         // the key row fits on one line from here (QCControls drops the week, then words)
    static let minWindowHeight: CGFloat = 220  // header, a line of chat and the field at one line; a taller field asks for more
    static let margin: CGFloat = 0             // none: the card's edges are the window's, where macOS's resize zones are
    @ObservedObject var model: QuickChatModel
    @Environment(\.qcRendering) private var rendering

    var body: some View {
        Group {
            if model.isWindow { QCWindow(model: model) } else { QCBar(model: model) }
        }
        .frame(minWidth: Self.minWidth, maxWidth: .infinity,
               minHeight: model.isWindow ? Self.minWindowHeight : nil, maxHeight: .infinity, alignment: .top)
        .padding(rendering ? 0 : Self.margin)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - The bar

struct QCBar: View {
    @ObservedObject var model: QuickChatModel

    var body: some View {
        // the field box on its own: the same text size and rows as in the window, with the window's corners
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let p = model.barProblem { QCProblemView(problem: p, model: model, answered: false) }
                else if model.switchNotice != nil { QCSwitchView(model: model) }
                else if model.blocked { QCProblemView(problem: .limitFull, model: model, answered: false) }
            }
            .padding(.bottom, 4)
            if let note = model.accountNote { QCNote(text: note) }
            QCField(model: model, placeholder: "Ask anything", size: 15, grows: true)
            QCControls(model: model, inBar: true)
        }
        .padding(QCSpace.barPadding)
        .frame(maxHeight: .infinity, alignment: .top)       // a bar dragged taller gives the height to the field
        .qcDraggable()
        .background(RoundedRectangle(cornerRadius: QCSpace.corner, style: .continuous).fill(QCColor.surface.opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: QCSpace.corner, style: .continuous).strokeBorder(QCColor.line))
    }
}

// MARK: - The chat window

struct QCWindow: View {
    @ObservedObject var model: QuickChatModel
    @Environment(\.qcRendering) private var rendering

    var body: some View {
        VStack(spacing: 0) {
            QCHeader(model: model).zIndex(1)         // its hover card hangs over the chat
            if rendering {
                // a picture can't draw a scroll view: the chat's end, clipped to the window, as if scrolled down
                Color.clear
                    .overlay(VStack(alignment: .leading, spacing: 0) { turns }.padding(Self.chatPadding), alignment: .bottom)
                    .clipped()
                    .overlay(alignment: .top) { fade }
            } else {
                // the chat is at least as tall as the scroll view, so the empty space below a short one drags too
                GeometryReader { geo in
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                turns
                                Color.clear.frame(height: 1).id("end")
                            }
                            .padding(Self.chatPadding)
                            .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .topLeading)
                            .qcDraggable()
                        }
                        .onChange(of: model.scrollTick) { _ in proxy.scrollTo("end", anchor: .bottom) }
                        .onAppear { proxy.scrollTo("end", anchor: .bottom) }
                    }
                }
                .overlay(alignment: .top) { fade }
                .frame(minHeight: 44)         // a line of chat stays, whatever the window
            }
            // the field box: 10 pt from the window's sides and bottom, its text and controls 12 pt inside it
            VStack(alignment: .leading, spacing: 8) {
                // the whole box above the picker row is the field: its padding and the gap to the row press into it
                QCField(model: model, placeholder: "Reply…", size: 15,
                        area: EdgeInsets(top: QCSpace.boxPadding.top, leading: QCSpace.boxPadding.leading, bottom: 8, trailing: QCSpace.boxPadding.trailing))
                QCControls(model: model, inBar: false)
            }
            .padding(QCSpace.boxPadding)
            .qcDraggable()
            .background(RoundedRectangle(cornerRadius: QCSpace.boxCorner, style: .continuous).fill(QCColor.surface))
            .overlay(RoundedRectangle(cornerRadius: QCSpace.boxCorner, style: .continuous).strokeBorder(QCColor.line)
                .allowsHitTesting(false))          // the outline takes no press: its edge is the field's too
            .padding([.horizontal, .bottom], QCSpace.gap)
        }
        .frame(maxHeight: .infinity)
        .qcDraggable()
        .background(RoundedRectangle(cornerRadius: QCSpace.corner, style: .continuous).fill(QCColor.window.opacity(0.98)))
        .overlay(RoundedRectangle(cornerRadius: QCSpace.corner, style: .continuous).strokeBorder(QCColor.line))
    }

    /// The answers start on the same 10 pt line as the header's name and the field box.
    static let chatPadding = EdgeInsets(top: 4, leading: QCSpace.gap, bottom: 12, trailing: QCSpace.gap)

    /// The answers scroll under the header through a short fade, not a hard edge.
    private var fade: some View {
        LinearGradient(colors: [QCColor.window, QCColor.window.opacity(0)], startPoint: .top, endPoint: .bottom)
            .frame(height: 10).allowsHitTesting(false)
    }

    @ViewBuilder private var turns: some View {
        if let note = model.accountNote { QCNote(text: note).padding(.top, 14) }
        ForEach(Array(model.turns.enumerated()), id: \.element.id) { i, t in
            QCTurnView(turn: t, first: i == 0 && model.accountNote == nil, last: i == model.turns.count - 1, model: model)
        }
        // the chat ended (idle, a crash, Stop that didn't stop): said once, under the turns that are left to read
        if let e = model.ended { QCEndNote(text: e.line).padding(.top, 12) }
        // a switch of account under way (or gone wrong) is said under the chat, in place of the full limit's own notice
        if model.switchNotice != nil {
            QCSwitchView(model: model).padding(.top, 12)
        } else if model.blocked, model.turns.last?.problem != .limitFull {
            // a limit filled since the last answer: said once, under the chat, with where to ask instead
            QCProblemView(problem: .limitFull, model: model, answered: false).padding(.top, 12)
        }
    }
}

/// The account line: the profile and the address signed in to its folder (masked), its week, then New chat and Hide.
struct QCHeader: View {
    @ObservedObject var model: QuickChatModel
    /// The pointer is on the meters: their card shows what the line had to leave out.
    @State private var meterHover = false
    @State private var nameHover = false
    /// The pointer is on the address capsule itself: the only thing that un-blurs the address.
    @State private var addressHover = false
    @State private var line = QCLineState()
    @Environment(\.qcHover) private var pictureHover

    var body: some View {
        let on = meterHover || pictureHover
        // identity on the left (name, address), usage on the right next to New chat and Hide; 40 pt high, centred, the
        // name on the window's 10 pt line and the ✕ glyph about as far in from the right
        HStack(spacing: 8) {
            QCHeaderInfo(target: model.target, level: model.level, openProfile: {
                // Settings opens and the chat steps aside (hidden, not closed: the shortcut brings it back as it was)
                if let id = model.target?.profileID { model.openSettings(id); model.hide() }
            }, nameHover: $nameHover, addressHover: $addressHover, meterHover: $meterHover, state: $line)
            .zIndex(1)         // a grown address capsule is drawn over the buttons too
            HStack(spacing: 0) {
                QCIconButton(symbol: "square.and.pencil", help: "New chat (⌘N)", size: QCSpace.row) { model.newChat() }
                QCIconButton(symbol: "xmark", help: "Hide (Esc)", size: QCSpace.row) { model.hide() }
            }
        }
        .padding(.leading, QCSpace.gap).padding(.trailing, 3)
        .frame(height: QCSpace.header)
        .qcDraggable()
        .overlay(alignment: .topTrailing) {
            // a card under the meters, right-aligned to the 10 pt line, only for what the line had to leave out: while
            // the pointer is on the meters, their dropped parts. (The address has no card: the capsule itself grows.)
            let rows = on ? QCHeaderCard.rows(model.level, shown: line.detail) : []
            if !rows.isEmpty {
                QCHeaderCard(rows: rows)
                    .padding(.trailing, QCSpace.gap).offset(y: QCSpace.header - 2).allowsHitTesting(false)
            }
        }
    }
}

/// What the header line left out, under the header: for each window only the parts of its meter the line dropped (its
/// share, when it resets, its label when none is left). The bar and anything the line shows are not repeated; the
/// window's name is the row's key. A label only cut to "5h" or "wk" is not a loss.
struct QCHeaderCard: View {
    struct Row: Identifiable {
        let id: String
        let label: String
        var share: (text: String, color: Color)?
        var resets: String?
    }

    let rows: [Row]

    /// The rows for the dropped parts of the meters the line shows (`shown`); none when the line has them all.
    static func rows(_ level: QuickChatLevel?, shown: QCHeaderDetail) -> [Row] {
        guard let l = level else { return [] }
        let full = l.full()
        func row(_ id: String, _ label: String, _ p: Double?, _ f: FullLimit?, _ resets: Date?) -> Row? {
            guard f != nil || p != nil else { return nil }
            let share = f != nil ? 100 : p
            let when = f?.resets ?? resets
            var r = Row(id: id, label: label)
            if f == nil, !shown.pct { r.share = (QuickChatLevel.pct(share), QuickChatLevel.color(share)) }
            if shown.resets == .none, let when { r.resets = "resets \(TimeWords.when(when))" }
            // a label cut to "5h" or "wk" is not a loss; a label that is gone is, and the row says which window it is
            return r.share == nil && r.resets == nil && shown.labels != .none ? nil : r
        }
        return [row("5h", "session", l.fiveHourNow(), full?.id == "5h" ? full : nil, l.fiveHourResets),
                row("wk", "week", l.weekNow(), full?.id == "wk" ? full : nil, l.weekResets)].compactMap { $0 }
    }

    var body: some View {
        // a grid, so the labels and numbers of the rows line up
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
            ForEach(rows) { r in
                GridRow {
                    Text(r.label).foregroundColor(QCColor.muted)
                    if let share = r.share { Text(share.text).fontWeight(.semibold).foregroundColor(share.color) }
                    if let when = r.resets { Text(when).foregroundColor(QCColor.muted) }
                }
                .font(.system(size: 12).monospacedDigit()).lineLimit(1)
            }
        }
        .fixedSize()
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(QCColor.surface))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(QCColor.line))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
    }
}

/// Set while drawing a picture: the header as if the pointer were over it (the meters' card), or over the address capsule.
private struct QCHoverKey: EnvironmentKey { static let defaultValue = false }
private struct QCAddressHoverKey: EnvironmentKey { static let defaultValue = false }
private struct QCAddressCopiedKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// Set while drawing a picture: the address capsule as just after a click copied it.
    var qcAddressCopied: Bool {
        get { self[QCAddressCopiedKey.self] }
        set { self[QCAddressCopiedKey.self] = newValue }
    }
    var qcHover: Bool {
        get { self[QCHoverKey.self] }
        set { self[QCHoverKey.self] = newValue }
    }
    var qcAddressHover: Bool {
        get { self[QCAddressHoverKey.self] }
        set { self[QCAddressHoverKey.self] = newValue }
    }
}

/// How much of the header's account line is drawn. Never an ellipsis: the line takes the first step that fits the width it
/// has (ViewThatFits: measured, no fixed thresholds), richest first, so the numbers show whenever there is room for them.
/// With room, the line shows everything: "week ▬ 58% · resets Fri 00:29", the session the same way. As the window
/// narrows it drops parts in this order:
///   1. both labels shorten together: "session" / "week" become "5h" / "wk";
///   2. the address leaves the line;
///   3. the reset times go (labels full again, then short, the address back while it fits);
///   4. the percentages go (bars only; "full" stays), labels first full again, then short;
///   5. the labels go, both (and a profile name too long for the window on its own is cut: the only ellipsis).
/// The address sits in a capsule at most 132 pt wide, blurred at rest; while the pointer is on the capsule (or the margin
/// around it) the capsule grows to show it whole. While the pointer is on the meters, a card under them shows only
/// what the line dropped (a window's share, reset or label), nothing it already shows, and no card at all when it
/// dropped nothing.
struct QCHeaderDetail: Equatable {
    enum Resets { case words, none }
    enum Labels { case full, short, none }
    var resets: Resets = .none
    var pct: Bool
    var labels: Labels
    var address = true

    static let steps: [QCHeaderDetail] = [
        .init(resets: .words, pct: true, labels: .full),
        .init(resets: .words, pct: true, labels: .short),
        .init(resets: .words, pct: true, labels: .short, address: false),
        .init(pct: true, labels: .full),
        .init(pct: true, labels: .short),
        .init(pct: true, labels: .short, address: false),
        .init(pct: false, labels: .full, address: false),
        .init(pct: false, labels: .short, address: false),
        .init(pct: false, labels: .none, address: false),
    ]
}

/// What the line on screen shows (told by the step that is shown): the hover card adds the rest.
struct QCLineState: Equatable {
    var detail = QCHeaderDetail.steps[0]
}

/// The profile, its address (smudged) and the session and week meters.
struct QCHeaderInfo: View {
    let target: QuickChatTarget?
    let level: QuickChatLevel?
    /// The profile's name was clicked.
    let openProfile: () -> Void
    @Binding var nameHover: Bool
    /// The pointer is on the address capsule: the address is un-blurred. Kept by the header (the candidates replace each other).
    @Binding var addressHover: Bool
    /// The pointer is on the meters. Kept by the header too.
    @Binding var meterHover: Bool
    /// What the line on screen shows: told by the step that is shown.
    @Binding var state: QCLineState

    var body: some View {
        let steps = QCHeaderDetail.steps
        // each candidate is measured at its ideal width (its spacer at its least) and, once picked, spreads to the width
        // the header gives it, so the meters sit on the right next to the buttons
        ViewThatFits(in: .horizontal) {
            ForEach(steps.indices, id: \.self) { i in
                QCHeaderLine(target: target, level: level, detail: steps[i], openProfile: openProfile, nameHover: $nameHover,
                             addressHover: $addressHover, meterHover: $meterHover)
                    .onAppear { state = QCLineState(detail: steps[i]) }
            }
            // a profile name too long for the window even on its own: the one case with an ellipsis, so the line never
            // pushes the buttons off the panel
            QCHeaderLine(target: target, level: level, detail: steps[steps.count - 1], openProfile: openProfile, nameHover: $nameHover,
                         addressHover: $addressHover, meterHover: $meterHover, flexible: true)
                .onAppear { state = QCLineState(detail: steps[steps.count - 1]) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(QCHeaderLine.spoken(target: target, level: level))
        .accessibilityAction(named: "Open profile in Settings", openProfile)
    }
}

struct QCHeaderLine: View {
    let target: QuickChatTarget?
    let level: QuickChatLevel?
    let detail: QCHeaderDetail
    let openProfile: () -> Void
    @Binding var nameHover: Bool
    @Binding var addressHover: Bool
    @Binding var meterHover: Bool
    /// The name may give way (be cut) to what the window has room for.
    var flexible = false

    var body: some View {
        HStack(spacing: 8) {
            if let t = target {
                // the name's hover fill reaches 6 pt past its text, which sits on the 10 pt line
                QCProfileName(name: t.name, hover: $nameHover, action: openProfile).padding(.leading, -6)
                    .layoutPriority(flexible ? -1 : 0)
                if detail.address, let e = t.email { QCBlurred(text: e, hover: $addressHover) }
            }
            Spacer(minLength: 0)
            if let l = level {
                let full = l.full()
                HStack(spacing: 12) {
                    QCLevelGroup(label: "session", short: "5h", p: l.fiveHourNow(), full: full?.id == "5h" ? full : nil,
                                 resets: l.fiveHourResets, detail: detail)
                    QCLevelGroup(label: "week", short: "wk", p: l.weekNow(), full: full?.id == "wk" ? full : nil,
                                 resets: l.weekResets, detail: detail)
                }
                .fixedSize()
                // a drag that starts on the meters moves the panel; the card shows what the line dropped, so no tooltip
                .qcDraggable(hover: $meterHover)
                .onDisappear { meterHover = false }
            }
        }
    }

    /// Whether there is any meter to show.
    static func hasMeters(_ l: QuickChatLevel) -> Bool {
        l.full() != nil || l.fiveHourNow() != nil || l.weekNow() != nil
    }

    /// The same numbers as words, for VoiceOver: both windows with their share and reset.
    static func tooltip(_ level: QuickChatLevel?) -> String {
        guard let l = level else { return "" }
        let full = l.full()
        func line(_ name: String, _ p: Double?, _ f: FullLimit?, _ resets: Date?) -> String? {
            guard f != nil || p != nil else { return nil }
            let when = (f?.resets ?? resets).map { ", resets \(TimeWords.when($0))" } ?? ""
            return f != nil ? "\(name): full\(when)" : "\(name): \(QuickChatLevel.pct(p)) used\(when)"
        }
        return [line("Session (5-hour window)", l.fiveHourNow(), full?.id == "5h" ? full : nil, l.fiveHourResets),
                line("Week", l.weekNow(), full?.id == "wk" ? full : nil, l.weekResets)].compactMap { $0 }.joined(separator: "\n")
    }

    static func spoken(target: QuickChatTarget?, level: QuickChatLevel?) -> String {
        var parts: [String] = []
        if let t = target { parts.append(t.name); if let e = t.email { parts.append(maskEmail(e)) } }
        let words = tooltip(level)
        if !words.isEmpty { parts.append(words.replacingOccurrences(of: "\n", with: ". ")) }
        return parts.joined(separator: ", ")
    }
}

/// The profile's name, a button to its page in Settings: a soft highlight and the pointing hand while the pointer is on it.
struct QCProfileName: View {
    let name: String
    /// Kept by the header, not here: the line's candidates (ViewThatFits) replace each other while the pointer is on it.
    @Binding var hover: Bool
    let action: () -> Void
    @Environment(\.qcNameHover) private var pictureHover

    var body: some View {
        Button(action: action) {
            Text(name).font(.system(size: 13, weight: .semibold)).foregroundColor(QCColor.text).lineLimit(1)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hover || pictureHover ? QCColor.hover : .clear))
                .qcControl()
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .onDisappear { hover = false }
        .qcPointingHand()
        .help("\(name) in Settings")
    }
}

/// Set while drawing a picture: the profile's name as if the pointer were on it.
private struct QCNameHoverKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var qcNameHover: Bool {
        get { self[QCNameHoverKey.self] }
        set { self[QCNameHoverKey.self] = newValue }
    }
}

/// The address in a capsule: the real text, cut to the capsule's at most 132 pt, blurred at rest. While the pointer is on
/// the capsule or the margin around it (not the meters, the name or the buttons) the capsule grows to the whole address,
/// readable, drawn above whatever is next to it with its own opaque background; it returns to its size when the pointer
/// leaves. The blur stays inside the capsule, so it has a clear edge rather than a smear.
/// A click anywhere in the hover zone copies the whole address (`copy`): the capsule says "Copied" with a tick for about
/// a second, drawn over it like the grown one (nothing else moves), then is the address again. The zone is a control
/// (never a move) with the pointing hand; VoiceOver has the same as its action "Copy address".
struct QCBlurred: View {
    let text: String
    /// The pointer is in the hover zone: the capsule shows the whole address. Kept by the header (the line's candidates
    /// replace each other while the pointer is on it).
    @Binding var hover: Bool
    @Environment(\.qcAddressHover) private var pictureHover
    @Environment(\.qcAddressCopied) private var pictureCopied
    private var reveal: Bool { hover || pictureHover }
    /// The address was just copied: "Copied" shows until `copiedFor` has passed (a later click starts it again).
    @State private var copiedAt: Int = 0
    @State private var copied = false
    private var showCopied: Bool { copied || pictureCopied }
    static let copiedFor: TimeInterval = 1.1

    /// Puts the whole address on the pasteboard, as plain text (the pasteboard cleared first). An empty one (no account
    /// known) puts nothing there and says false. (`pasteboard`: the general one; a check passes its own.)
    @discardableResult
    static func copy(_ address: String, to pasteboard: NSPasteboard = .general) -> Bool {
        let a = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty else { return false }
        pasteboard.clearContents()
        return pasteboard.setString(a, forType: .string)
    }

    private func copyNow() {
        guard Self.copy(text) else { return }
        copiedAt += 1
        let mine = copiedAt
        withAnimation(.easeOut(duration: 0.12)) { copied = true }
        // one shot: only the latest click's turns "Copied" back into the address
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.copiedFor) {
            if copiedAt == mine { withAnimation(.easeOut(duration: 0.18)) { copied = false } }
        }
    }

    /// "Copied" with a tick, in a capsule at least `width` wide, opaque over what it covers.
    private func copiedBadge(_ width: CGFloat) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark").font(.system(size: 9.5, weight: .bold))
            Text("Copied").font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(QCColor.text).fixedSize()
        .padding(.horizontal, Self.inset).frame(minWidth: width, minHeight: Self.height, maxHeight: Self.height)
        .background(Capsule().fill(QCColor.text.opacity(0.1)))
        .background(Capsule().fill(QCColor.window))
        .overlay(Capsule().strokeBorder(QCColor.text.opacity(0.08)))
    }

    static let font = NSFont.systemFont(ofSize: 12)
    static let maxWidth: CGFloat = 132, inset: CGFloat = 7, height: CGFloat = 18
    /// The margin around the capsule that also counts as on it, so the pointer can rest beside the text: 8 pt on the
    /// left (the gap to the name), 10 pt on the others. The zone grows with the capsule.
    static let zoneLeading: CGFloat = 8, zoneOther: CGFloat = 10

    /// The capsule's width when it shows the whole address.
    private var fullWidth: CGFloat { ceil((text as NSString).size(withAttributes: [.font: Self.font]).width) + 2 * Self.inset }
    private var restWidth: CGFloat { min(fullWidth, Self.maxWidth) }
    private var grown: Bool { reveal && fullWidth > restWidth }

    /// A capsule `width` wide with the address in it, blurred or not.
    private func capsule(_ width: CGFloat, blurred: Bool) -> some View {
        Text(text).font(.system(size: 12)).foregroundColor(QCColor.soft).lineLimit(1).fixedSize()
            .frame(width: width - 2 * Self.inset, alignment: .leading).clipped()
            .blur(radius: blurred ? 3.4 : 0)
            .padding(.horizontal, Self.inset).frame(height: Self.height)
            .background(Capsule().fill(QCColor.text.opacity(0.06)))
            .overlay(Capsule().strokeBorder(QCColor.text.opacity(0.05)))
            .clipShape(Capsule())
    }

    var body: some View {
        // the line lays out the resting capsule; the grown one and the hover zone are overlays, so nothing else moves
        capsule(restWidth, blurred: !reveal)
            .animation(.easeOut(duration: 0.18), value: reveal)
            .overlay(alignment: .leading) {
                if showCopied {
                    copiedBadge(grown ? fullWidth : restWidth)
                } else if grown {
                    capsule(fullWidth, blurred: false)
                        .background(Capsule().fill(QCColor.window))      // opaque: the meters under it don't show through
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
                }
            }
            .overlay(alignment: .leading) {
                Color.clear
                    .frame(width: (grown ? fullWidth : restWidth) + Self.zoneLeading + Self.zoneOther, height: Self.height + 2 * Self.zoneOther)
                    .qcControl()         // the hover zone: a press here is never a move
                    .onHover { hover = $0 }
                    .onTapGesture { copyNow() }
                    .qcPointingHand()
                    .help("Copy address")
                    .offset(x: -Self.zoneLeading)
            }
            .fixedSize()
            .zIndex(1)
            .onDisappear { hover = false }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(showCopied ? "Address copied" : "Account address")
            .accessibilityAction(named: "Copy address") { copyNow() }
    }
}

/// One window's meter: its label, a thin bar in the level's colour, then the share and when it resets (as far as the
/// detail says). A full limit says "full" whatever the detail. Nothing at all while the window isn't known.
struct QCLevelGroup: View {
    let label: String
    let short: String
    let p: Double?
    let full: FullLimit?
    let resets: Date?
    let detail: QCHeaderDetail

    var body: some View {
        if full != nil || p != nil {
            HStack(spacing: 5) { parts }
        }
    }

    @ViewBuilder private var parts: some View {
        let share = full != nil ? 100 : p
        let color = QuickChatLevel.color(share)
        let when = (full?.resets ?? resets)
        let size: CGFloat = 11.5
        let bar: CGFloat = 24
        if detail.labels != .none {
            Text(detail.labels == .full ? label : short).font(.system(size: size)).foregroundColor(QCColor.muted).lineLimit(1)
        }
        ZStack(alignment: .leading) {
            Capsule().fill(QCColor.text.opacity(0.13))
            Capsule().fill(color).frame(width: bar * CGFloat(min(100, share ?? 0)) / 100)
        }
        .frame(width: bar, height: 4)
        if full != nil || detail.pct {
            Text(full != nil ? "full" : QuickChatLevel.pct(share))
                .font(.system(size: size, weight: .semibold).monospacedDigit()).foregroundColor(color).lineLimit(1)
        }
        if let when, detail.resets != .none {
            Text("· resets \(TimeWords.when(when))")
                .font(.system(size: size)).foregroundColor(QCColor.muted).lineLimit(1)
        }
    }
}

// MARK: - One question and its answer

/// A question in its bubble, then the answer. Under the last answer its actions (Copy, Ask again) and who answered;
/// under earlier ones the same row only while the pointer is on that turn (its room is kept, so nothing moves).
struct QCTurnView: View {
    let turn: QuickChatTurn
    let first: Bool
    let last: Bool
    @ObservedObject var model: QuickChatModel
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer(minLength: 56)        // a bubble is at most about 82% of the chat's width
                Text(turn.question)
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .foregroundColor(QCColor.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(QCColor.bubble))
            }
            // after the previous turn's actions row: about 32 pt between an answer and the next question
            .padding(.top, first ? 0 : 4)
            if turn.thinkingTitle != nil { QCThought(turn: turn).padding(.top, 12) }
            if !turn.answer.isEmpty {
                QCAnswer(text: turn.answer).equatable().padding(.top, turn.thinkingTitle != nil ? 4 : 10)
            }
            if turn.phase == .waiting || turn.phase == .streaming { QCPulse().padding(.top, 10) }
            if turn.phase == .done || turn.phase == .stopped {
                let shown = last || hover
                // hidden, it still takes the pointer: moving down from the answer onto Copy keeps the turn hovered
                footer.padding(.top, 4).opacity(shown ? 1 : 0)
            }
            if let p = turn.problem, turn.phase == .failed {
                QCProblemView(problem: p, model: model, answered: !turn.answer.isEmpty, last: last)
                    .padding(.top, 12).padding(.bottom, 8)
            }
        }
        .onHover { hover = $0 }
    }

    /// 24 pt: Copy and Ask again (their glyphs on the chat's edge), then "Opus 5.5 · high · 7.8 s".
    private var footer: some View {
        HStack(spacing: 0) {
            QCCopyIcon(text: turn.answer)
            if last { QCIconButton(symbol: "arrow.clockwise", help: "Ask again", small: true) { model.again() } }
            Text(words).font(.system(size: 12)).foregroundColor(QCColor.muted).lineLimit(1).padding(.leading, 4)
        }
        .frame(height: QCSpace.small)
        .padding(.leading, -5)
    }

    private var words: String {
        let who = turn.model.isEmpty ? "Claude" : turn.model
        if turn.phase == .stopped { return "\(who) · stopped" }
        var parts = [who]
        if let th = turn.thinkingTitle { parts.append(th.lowercased()) }
        if let sec = turn.seconds { parts.append(QCFormat.seconds(sec)) }
        return parts.joined(separator: " · ")
    }
}

/// "Thinking…" while it thinks, then "Thought for 5 s"; a click shows what it thought (as Claude Code reports it).
struct QCThought: View {
    let turn: QuickChatTurn
    @State private var open = false

    var body: some View {
        let thinking = turn.busy && turn.answer.isEmpty
        VStack(alignment: .leading, spacing: 6) {
            Button { open.toggle() } label: {
                HStack(spacing: 5) {
                    Text(thinking ? "Thinking…" : turn.thinkingSeconds.map { "Thought for " + QCFormat.seconds($0) } ?? "Thought")
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).rotationEffect(.degrees(open ? 90 : 0))
                }
                .font(.system(size: 12.5)).foregroundColor(QCColor.muted).frame(height: 20)
                .qcControl()
            }
            .buttonStyle(.plain)
            .disabled(turn.thinking.isEmpty)
            if open, !turn.thinking.isEmpty {
                Text(turn.thinking).font(.system(size: 12.5)).foregroundColor(QCColor.muted).lineSpacing(3)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 12)
                    .overlay(Rectangle().fill(QCColor.line).frame(width: 2), alignment: .leading)
            }
        }
    }
}

enum QCFormat {
    /// 2.4 s, 12 s, 1 min 5 s.
    static func seconds(_ s: Double) -> String {
        if s < 10 { return String(format: "%.1f s", s) }
        if s < 60 { return "\(Int(s.rounded())) s" }
        let m = Int(s) / 60, r = Int(s) % 60
        return r == 0 ? "\(m) min" : "\(m) min \(r) s"
    }
}

/// An answer's Markdown, block by block (QuickChatMarkdown.swift). Equatable on its text, so an answer that's done isn't
/// parsed and drawn again while a later one streams.
struct QCAnswer: View, Equatable {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(QuickChatMarkdown.blocks(text).enumerated()), id: \.offset) { _, b in block(b) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func block(_ b: QuickChatBlock) -> some View {
        switch b {
        case .paragraph(let s):
            prose(s)
        case .heading(let level, let s):
            Text(Self.inline(s)).font(.system(size: level <= 2 ? 17 : 15, weight: .semibold))
                .foregroundColor(QCColor.text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                    HStack(alignment: .firstTextBaseline, spacing: 8) { Text("•").foregroundColor(QCColor.muted); prose(it) }
                }
            }
        case .numbered(let start, let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, it in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(start + i).").font(.system(size: 14).monospacedDigit()).foregroundColor(QCColor.muted)
                        prose(it)
                    }
                }
            }
        case .quote(let s):
            prose(s).padding(.leading, 12)
                .overlay(Rectangle().fill(QCColor.line).frame(width: 2), alignment: .leading)
        case .code(let lang, let code):
            QCCodeBlock(language: lang, code: code)
        case .rule:
            Rectangle().fill(QCColor.line).frame(height: 1)
        }
    }

    /// The system font at 14 on 21 pt lines: one family across the window.
    private func prose(_ s: String) -> some View {
        Text(Self.inline(s))
            .font(.system(size: 14))
            .foregroundColor(QCColor.text)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    /// Inline Markdown, with `code` in the mono font and a warm colour.
    static func inline(_ s: String) -> AttributedString {
        var a = QuickChatMarkdown.inline(s)
        for run in a.runs where run.inlinePresentationIntent?.contains(.code) == true {
            a[run.range].font = .system(size: 12.5, design: .monospaced)
            a[run.range].foregroundColor = QCColor.inlineCode
        }
        return a
    }
}

struct QCCodeBlock: View {
    let language: String
    let code: String
    @Environment(\.qcRendering) private var rendering

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // a 28 pt top row: the language, and Copy as an icon
            HStack(spacing: 0) {
                Text(language.isEmpty ? "code" : language).font(.system(size: 11.5)).foregroundColor(QCColor.muted)
                Spacer()
                QCCopyIcon(text: code)
            }
            .padding(.leading, 12).padding(.trailing, 2)
            .frame(height: QCSpace.row)
            Rectangle().fill(QCColor.line).frame(height: 1)
            if rendering {        // a picture can't draw a scroll view
                codeText.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading).clipped()
            } else {
                ScrollView(.horizontal, showsIndicators: false) { codeText }
            }
        }
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(QCColor.code))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(QCColor.line))
    }

    private var codeText: some View {
        Text(code)
            .font(.system(size: 12.5, design: .monospaced))
            .lineSpacing(3)
            .foregroundColor(QCColor.codeText)
            .textSelection(.enabled)
            .fixedSize()
            .padding(EdgeInsets(top: 8, leading: 12, bottom: 10, trailing: 12))
    }
}

/// Claude's waiting mark: an orange dot that breathes.
struct QCPulse: View {
    @State private var on = false
    var body: some View {
        Circle().fill(QCColor.accent).frame(width: 9, height: 9)
            .opacity(on ? 1 : 0.3)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

// MARK: - Why an answer didn't come

struct QCProblemView: View {
    let problem: QuickChatProblem
    @ObservedObject var model: QuickChatModel
    var answered: Bool
    var last = true

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(QCColor.crimson).frame(width: 8, height: 8).padding(.top, 5)
            VStack(alignment: .leading, spacing: 7) {
                (Text(title).fontWeight(.semibold).foregroundColor(QCColor.text) + Text(more.isEmpty ? "" : " " + more))
                    .font(.system(size: 13)).foregroundColor(QCColor.soft).fixedSize(horizontal: false, vertical: true)
                if let d = detail {
                    Text(d).font(.system(size: 11.5, design: .monospaced)).foregroundColor(QCColor.muted)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) { keys }
            }
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(QCColor.crimson.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(QCColor.crimson.opacity(0.38)))
    }

    private var title: String {
        switch problem {
        case .notInstalled: return ClaudeInstall.missing + "."
        case .notSignedIn(let name, _): return "\(name)'s Claude Code isn't signed in."
        case .stopped: return "Claude Code stopped before the answer was done."
        case .refused(let text): return text
        case .noProfile: return "There's no profile to chat on yet."
        case .limitFull:
            let f = model.level?.full()
            let who = model.target?.name ?? "This profile"
            return "\(who)'s \(f?.name ?? "week") is full" + (f?.resets.map { ", resets " + TimeWords.when($0) } ?? "") + "."
        }
    }

    private var more: String {
        switch problem {
        case .notInstalled: return "The quick chat answers through it."
        case .notSignedIn: return "Its sign-in opens in Terminal. Then try again."
        case .stopped: return answered ? "What arrived is kept above." : ""
        case .refused: return ""
        case .noProfile: return "Pick a Claude Code folder in Settings."
        case .limitFull:
            func room(_ who: String, _ week: Double?) -> String {
                week.map { "\(who) has room (\(Int($0.rounded()))% at its last answer)." } ?? "\(who) has no numbers yet."
            }
            var parts: [String] = []
            if let o = model.offer { parts.append(room(o.name, o.week)) }
            if let s = model.switchOffer { parts.append(room("Standby " + maskEmail(s.email), s.week)) }
            return parts.joined(separator: " ")
        }
    }

    private var detail: String? {
        if case .stopped(let d) = problem { return d }
        return nil
    }

    @ViewBuilder private var keys: some View {
        switch problem {
        case .notInstalled:
            QCButton(title: "Install…") { NSWorkspace.shared.open(ClaudeInstall.docs) }
            QCButton(title: "Try again", ghost: true) { retry() }
        case .notSignedIn(_, let id):
            QCButton(title: "Sign in…") { model.signIn(id) }
            QCButton(title: "Try again", ghost: true) { retry() }
        case .stopped, .refused:
            if last { QCButton(title: "Retry") { retry() } }
        case .noProfile:
            QCButton(title: "Open Settings") { model.openSettings(nil) }
        case .limitFull:
            if let o = model.offer { QCButton(title: "Ask on \(o.name)") { model.askOnOffer() } }
            if let s = model.switchOffer, model.switchNotice == nil {
                QCButton(title: "Switch to \(maskEmail(s.email))…", ghost: model.offer != nil) { model.switchTo(s) }
            }
        }
    }

    private func retry() { if model.isWindow { model.again() } else { model.barProblem = nil; model.send() } }
}

/// A switch of the profile to another account: while Claude Code's sign-in is open, when the browser signed in as
/// someone else, or when no sign-in came in 10 minutes (the last two can be dismissed). Drawn in place of the full
/// limit's notice.
struct QCSwitchView: View {
    @ObservedObject var model: QuickChatModel

    var body: some View {
        if let n = model.switchNotice {
            let waiting: Bool = { if case .waiting = n { return true } else { return false } }()
            let tint = waiting ? QCColor.accent : QCColor.crimson
            HStack(alignment: .top, spacing: 10) {
                if waiting { QCPulse().padding(.top, 3) } else { Circle().fill(tint).frame(width: 8, height: 8).padding(.top, 5) }
                VStack(alignment: .leading, spacing: 7) {
                    (Text(title(n)).fontWeight(.semibold).foregroundColor(QCColor.text) + Text(more(n)))
                        .font(.system(size: 13)).foregroundColor(QCColor.soft).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        if waiting { QCButton(title: "Stop waiting", ghost: true) { model.dropSwitch() } }
                        else {
                            QCButton(title: "Sign in again") { model.signInAgain() }
                            QCButton(title: "Dismiss", ghost: true) { model.dropSwitch() }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.38)))
        }
    }

    private func title(_ n: QuickChatSwitchNotice) -> String {
        switch n {
        case .waiting: return "Waiting for the sign-in…"
        case .wrong(let signedIn, let wanted): return "Signed in as \(maskEmail(signedIn)), not \(maskEmail(wanted))."
        case .timedOut: return "No sign-in in 10 minutes."
        }
    }

    private func more(_ n: QuickChatSwitchNotice) -> String {
        switch n {
        case .waiting(let wanted): return " Finish it in Terminal and the browser as \(maskEmail(wanted))."
        case .wrong: return ""
        case .timedOut: return " The account in use hasn't changed."
        }
    }
}

/// One line at the top of a chat: where it is now ("Main is on p•••@example.com now.").
struct QCNote: View {
    let text: String
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(Color(nsColor: Painter.green)).frame(width: 7, height: 7)
            Text(text).font(.system(size: 12.5)).foregroundColor(QCColor.muted).lineLimit(2)
            Spacer(minLength: 0)
        }
    }
}

/// The plain line under a chat that ended ("This chat ended after 15 minutes idle. Nothing was saved."): the turns above
/// stay to read, and the next message starts a new chat.
struct QCEndNote: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Circle().fill(QCColor.muted).frame(width: 7, height: 7).padding(.top, 5)
            Text(text).font(.system(size: 12.5)).foregroundColor(QCColor.muted).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - The keys

/// The row under the field: the profile picker, the model and thinking controls, in the bar the profile's week, then the
/// send (or stop) key.
struct QCControls: View {
    @ObservedObject var model: QuickChatModel
    var inBar: Bool

    /// The row on one line, whatever the width (ViewThatFits, richest first): the profile key keeps just its dot, then
    /// the bar's usage indicator goes. The pill and the usage indicator are as wide for every value they can show, so
    /// which row is drawn depends on the width alone: picking a model or a level, or the limits changing, never moves
    /// anything.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(usage: true, profileWords: true)
            row(usage: true, profileWords: false)
            row(usage: false, profileWords: true)
            row(usage: false, profileWords: false)
        }
    }

    /// `usage`: the bar's usage indicator (in the window the header has the limits).
    private func row(usage: Bool, profileWords: Bool) -> some View {
        HStack(spacing: 2) {
            if let t = model.target {
                // the dot takes the colour of the limit closest to full, as the usage indicator and the header do
                QCChip(title: profileWords ? t.name : "", dot: QuickChatLevel.color(model.blocked ? 100 : model.level?.binding()?.p),
                       help: "Profile: \(t.name). For this chat; a new chat starts on the default.") { pickProfile() }
            }
            QCStepsPill(model: model, bars: { AnyView(HStack(spacing: 4) {
                modelSteps()
                Rectangle().fill(QCColor.line).frame(width: 1, height: 18)
                thinkingSteps()
            }) })
            .zIndex(1)          // its bars, when open, are drawn over the rest of the row
            Spacer(minLength: 4)
            if inBar, usage {
                if let l = model.level, l.binding() != nil {
                    QCUsageView(level: l).padding(.trailing, 6)
                } else {
                    Color.clear.frame(width: QCUsageView.width, height: 4).padding(.trailing, 6)
                }
            }
            if model.busy {
                Button(action: model.stop) {
                    Image(systemName: "stop.fill").font(.system(size: 10, weight: .bold))
                        .frame(width: QCSpace.row, height: QCSpace.row).foregroundColor(QCColor.bubble)
                        .background(Circle().fill(QCColor.text))
                        .qcControl()
                }
                .buttonStyle(.plain).help("Stop")
            } else {
                let empty = model.field.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.blocked
                Button(action: model.send) {
                    Image(systemName: "arrow.up").font(.system(size: 13, weight: .semibold))
                        .frame(width: QCSpace.row, height: QCSpace.row)
                        .foregroundColor(empty ? QCColor.text.opacity(0.38) : .white)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(empty ? QCColor.text.opacity(0.1) : QCColor.send))
                        .qcControl()
                }
                .buttonStyle(.plain).disabled(empty).help("Send (Return)")
            }
        }
        // the first control's text sits on the box's padding, its hover fill reaching past it
        .padding(.leading, -QCSpace.keyPadding)
    }

    /// The profiles with their weeks, then Add a profile… (so a single profile still has something to offer).
    private func pickProfile() {
        QCMenu.pop(QCMenu.profiles(model.pickable(), on: model.target?.profileID, pick: { model.pickProfile($0) }, add: {
            model.openSettings(SettingsWindow.addPage); model.hide()
        }))
    }

    /// The model: a bar per family the account has, Haiku → Sonnet → Opus → Fable; a click on one picks it. The label is
    /// the family ("Opus"); the hover tip has the version ("Opus 5.5").
    private func modelSteps() -> some View {
        let now = model.resolvedModel.family
        let choices = model.modelChoices
        let thinkingCostly = QuickChatModels.costly(effort: model.effectiveThinking.effort)
        return QCStepControl(
            what: "Model", key: "m", keys: "⌥⌘← ⌥⌘→",
            steps: choices.map { .init(title: $0.title, label: $0.choice.title, costly: QuickChatModels.costly($0.choice)) },
            index: choices.firstIndex { $0.choice == now }, offSlot: false,
            tint: QuickChatModels.tint(own: QuickChatModels.costly(now), other: thinkingCostly),
            pick: { [weak model] j in
                guard let model, model.modelChoices.indices.contains(j) else { return }
                model.choose(model.modelChoices[j].choice)
            },
            step: { [weak model] in model?.stepModel($0) ?? false })
    }

    /// Thinking: Off (a dash), then a bar per level Low … Max. The levels the model doesn't take stay in their place,
    /// faint and inert, so changing the model never changes the control's width. Short labels ("Med"); the hover tip has
    /// the full name.
    private func thinkingSteps() -> some View {
        let all = QuickChatThinking.allCases
        let takes = model.thinkingSteps
        let now = model.effectiveThinking
        let modelName = model.modelTitle
        return QCStepControl(
            what: "Thinking", key: "t", keys: "⌥⌘↓ ⌥⌘↑",
            steps: all.map { t in
                .init(title: t == .off ? "Thinking off" : t.title, label: t == .medium ? "Med" : t.title,
                      costly: QuickChatModels.costly(effort: t.effort), takes: takes.contains(t),
                      why: takes.contains(t) ? nil : "\(modelName) doesn't take \(t.title)")
            },
            index: all.firstIndex(of: now), offSlot: true,
            tint: QuickChatModels.tint(own: QuickChatModels.costly(effort: now.effort), other: QuickChatModels.costly(model.resolvedModel.family)),
            pick: { [weak model] j in
                guard let model, all.indices.contains(j), model.thinkingSteps.contains(all[j]) else { return }
                model.choose(all[j])
            },
            step: { [weak model] in model?.stepThinking($0) ?? false })
    }
}

/// The model and thinking in the row, small: "Opus · High" in one fixed width (the longest pair it can show, so a
/// change never makes it wobble), warm while either costs more. A click opens the bars over the row, anchored at the
/// pill and drawn above the rest of the row (no part of its layout); a click on a bar picks it, and they stay open for
/// another pick; a click outside them, Esc, a click on the pill again, ⌘W or hiding the panel closes them. The scroll
/// wheel over the pill steps thinking (sideways, the model), as the ⌥⌘ arrows do. Nothing in the row moves, open or not.
struct QCStepsPill: View {
    @ObservedObject var model: QuickChatModel
    /// The model and thinking bars, as they open.
    let bars: () -> AnyView
    @State private var hover = false
    /// This drawn pill, owner of the open bars' frame in QCStepTargets.
    @State private var token = UUID()
    @Environment(\.qcRendering) private var rendering

    static let font = NSFont.systemFont(ofSize: 13, weight: .medium)
    static func short(_ t: QuickChatThinking) -> String { t == .medium ? "Med" : t.title }
    static func words(_ f: QuickChatModelChoice, _ t: QuickChatThinking) -> String { "\(f.title) · \(short(t))" }
    /// As wide as the longest pair of any family and level ("Sonnet · Extra").
    static let textWidth: CGFloat = ceil(QuickChatModelChoice.allCases.flatMap { f in
        QuickChatThinking.allCases.map { (words(f, $0) as NSString).size(withAttributes: [.font: font]).width }
    }.max() ?? 0) + 1

    var body: some View {
        let open = model.controlsOpen
        let f = model.resolvedModel.family, t = model.effectiveThinking
        let mc = QuickChatModels.costly(f), tc = QuickChatModels.costly(effort: t.effort)
        let tint = mc && tc ? 2 : (mc || tc ? 1 : 0)
        Button { model.controlsOpen.toggle() } label: {
            HStack(spacing: 5) {
                Text(Self.words(f, t)).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    .frame(width: Self.textWidth, alignment: .leading)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).opacity(0.7)
                    .rotationEffect(.degrees(open ? 180 : 0))
            }
            .foregroundColor(tint == 2 ? QCColor.hex(0xFFDCCB) : tint == 1 ? QCColor.hex(0xF1C3AE) : hover || open ? QCColor.text : QCColor.soft)
            .padding(.horizontal, QCSpace.keyPadding).frame(height: QCSpace.row)
            .background(RoundedRectangle(cornerRadius: QCSpace.keyCorner, style: .continuous)
                .fill(tint > 0 ? QCColor.accent.opacity(tint == 2 ? 0.27 : 0.13) : hover || open ? QCColor.hover : .clear))
            .overlay(RoundedRectangle(cornerRadius: QCSpace.keyCorner, style: .continuous).strokeBorder(tint == 2 ? QCColor.ember.opacity(0.4) : .clear))
            .qcControl()
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .qcPointingHand()
        .help("\(model.modelTitle), thinking \(t == .off ? "off" : t.title.lowercased()): click to change (⌥⌘ arrows step them)")
        .background(rendering ? nil : GeometryReader { g in
            Color.clear
                .onAppear { register(g.frame(in: .global)) }
                .onChange(of: g.frame(in: .global)) { register($0) }
        })
        // VoiceOver: the pill itself; the open bars are their own adjustable elements
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Model and thinking")
        .accessibilityValue("\(model.modelTitle), thinking \(t.title)")
        .accessibilityAddTraits(.isButton)
        .overlay(alignment: .leading) {
            if open {
                // exactly the row's height, so nothing hangs over the field above (an AppKit view that would draw over
                // it) or below the card; 4 pt left of the pill, by layout (the frame it reports is where it is drawn)
                bars()
                    .padding(.horizontal, 4)
                    .background(RoundedRectangle(cornerRadius: QCSpace.keyCorner + 2, style: .continuous).fill(QCColor.hex(0x2B2B29)))
                    .overlay(RoundedRectangle(cornerRadius: QCSpace.keyCorner + 2, style: .continuous).strokeBorder(QCColor.line))
                    .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
                    .fixedSize()
                    .background(rendering ? nil : GeometryReader { g in
                        Color.clear
                            .onAppear { QCStepTargets.shared.opened(g.frame(in: .global), token: token) }
                            .onChange(of: g.frame(in: .global)) { QCStepTargets.shared.opened($0, token: token) }
                            .onDisappear { QCStepTargets.shared.closed(token: token) }
                    })
                    .padding(.leading, -4)
            }
        }
    }

    /// Where the pill is and what it does, for a click outside, the scroll wheel (and the checks); the model held weakly.
    private func register(_ frame: CGRect) {
        let m = model
        QCStepTargets.shared.pill(.init(frame: frame, toggle: { [weak m] in m?.controlsOpen.toggle() },
                                        close: { [weak m] in m?.controlsOpen = false },
                                        stepThinking: { [weak m] in m?.stepThinking($0) ?? false },
                                        stepModel: { [weak m] in m?.stepModel($0) ?? false }))
    }
}

/// A step control (the model, thinking): a short label and a bar per step, rising. The bars up to and including the one
/// in use are filled bright (the text colour, or ember when the step in use costs more) and a dot sits under the one in
/// use; the bars above it are a faint fill, never tinted, so only what is in use looks lit. Each bar is a target of its
/// own (5 pt drawn in an 8 × 28 pt column; the columns touch, a control: a press there never moves the window): a click
/// picks that step. Thinking's Off is a dash before the bars. The pointer on a bar lights it, the label shows its short
/// name and a tip just above (a small window of its own, so it draws over the field and is no part of the row) its full
/// name; the scroll wheel and the ⌥⌘ arrows step it. The control is as wide for every step: its label is sized for the
/// longest short name, so nothing in it or the row moves when the value changes. While the step in use costs more
/// (Fable, Extra, Max) the control is warm (warmer when both controls are).
struct QCStepControl: View {
    struct Step {
        /// The full name (the tooltip, VoiceOver) and the label's words.
        let title: String
        let label: String
        let costly: Bool
        /// The model takes this step (thinking levels it doesn't are shown faint and do nothing).
        var takes = true
        var why: String? = nil
    }

    let what: String
    /// "m" or "t": its name in QCStepTargets and in a picture's hover (`--render-quick-chat hover-m2`).
    let key: String
    /// The keys that step it, for the hover tip.
    let keys: String
    let steps: [Step]
    /// The step in use (nil: none of them).
    let index: Int?
    /// The first step is Off, drawn as a dash rather than a bar.
    let offSlot: Bool
    /// 0 plain, 1 warm, 2 warmer.
    let tint: Int
    let pick: (Int) -> Void
    /// A step up (1) or down (-1), for the scroll wheel.
    let step: (Int) -> Bool
    @State private var hover: Int?
    /// This drawn control, in QCStepTargets.
    @State private var token = UUID()
    @Environment(\.qcStepHover) private var pictureHover
    @Environment(\.qcRendering) private var rendering

    /// A bar's target (the columns touch, so the targets tile) and the bar drawn in it.
    static let column: CGFloat = 8
    static let bar: CGFloat = 5
    static let labelFont = NSFont.systemFont(ofSize: 13, weight: .medium)

    private var hovered: Int? {
        if let p = pictureHover, p.hasPrefix(key) { return Int(p.dropFirst()) }
        return hover
    }
    /// As wide as the longest label it can show.
    private var labelWidth: CGFloat {
        ceil(steps.map { ($0.label as NSString).size(withAttributes: [.font: Self.labelFont]).width }.max() ?? 0) + 1
    }

    var body: some View {
        let inUse = index.flatMap { steps.indices.contains($0) ? steps[$0] : nil }
        // what is in use: bright, or ember when it costs more; only the bars up to it take this colour
        let lit = inUse?.costly == true ? QCColor.ember : QCColor.text
        let fg = tint == 2 ? QCColor.hex(0xFFDCCB) : tint == 1 ? QCColor.hex(0xF1C3AE) : QCColor.soft
        HStack(spacing: 0) {
            let h = hovered.flatMap { steps.indices.contains($0) ? steps[$0] : nil }
            Text((h ?? inUse)?.label ?? "")
                .font(.system(size: 13, weight: .medium)).lineLimit(1)
                .foregroundColor(h == nil ? fg : !h!.takes ? QCColor.muted : QCColor.text)
                .frame(width: labelWidth, alignment: .leading)
                .padding(.leading, QCSpace.keyPadding).padding(.trailing, 3)
            ForEach(steps.indices, id: \.self) { j in column(j, lit: lit) }
        }
        .frame(height: QCSpace.row)
        // a picture can't show the tip's own window: it draws the tip where the window would be
        .overlay(alignment: .topLeading) {
            if rendering, let j = hovered, steps.indices.contains(j) {
                let x = QCSpace.keyPadding + labelWidth + 3 + Self.column * (CGFloat(j) + 0.5)
                QCStepTipView(text: steps[j].why ?? steps[j].title, costly: steps[j].costly && steps[j].takes, muted: !steps[j].takes, keys: keys)
                    .fixedSize().frame(width: 0, height: 0, alignment: .bottom).offset(x: x, y: -4)
            }
        }
        .background(RoundedRectangle(cornerRadius: QCSpace.keyCorner, style: .continuous).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: QCSpace.keyCorner, style: .continuous).strokeBorder(tint == 2 ? QCColor.ember.opacity(0.4) : .clear))
        .qcControl()      // the label too: a press anywhere on the control never moves the window
        .background(rendering ? nil : GeometryReader { g in
            Color.clear
                .onAppear { QCStepTargets.shared.control(key, g.frame(in: .global), bars: steps.count, token: token, step: step) }
                .onChange(of: g.frame(in: .global)) { QCStepTargets.shared.control(key, $0, bars: steps.count, token: token, step: step) }
                .onChange(of: steps.count) { QCStepTargets.shared.control(key, g.frame(in: .global), bars: $0, token: token, step: step) }
                .onDisappear { QCStepTargets.shared.drop(key, token: token) }
        })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(what)
        .accessibilityValue(index.flatMap { steps.indices.contains($0) ? steps[$0].title : nil } ?? "")
        .accessibilityAdjustableAction { d in _ = step(d == .increment ? 1 : -1) }
    }

    /// One step's target: an 8 × 28 column with its bar (or Off's dash) at the bottom, and under the one in use a dot.
    @ViewBuilder private func column(_ j: Int, lit litColour: Color) -> some View {
        let s = steps[j]
        let isOff = offSlot && j == 0
        let bars = steps.count - (offSlot ? 1 : 0)
        let nth = j - (offSlot ? 1 : 0)
        let height: CGFloat = isOff ? 2 : bars <= 1 ? 15 : 6 + 9 * CGFloat(nth) / CGFloat(bars - 1)
        // filled: Off when it is in use; a bar when it is at or below the one in use (and the one in use isn't Off)
        let on = index.map { isOff ? $0 == 0 : (j <= $0 && !(offSlot && $0 == 0)) } ?? false
        let pointed = hovered == j && s.takes
        let color: Color = !s.takes ? QCColor.text.opacity(0.06)
            : on ? litColour
            : QCColor.text.opacity(pointed ? 0.45 : 0.16)
        ZStack(alignment: .bottom) {
            if pointed { RoundedRectangle(cornerRadius: 3, style: .continuous).fill(QCColor.hover).frame(width: Self.column, height: 24).padding(.bottom, 2) }
            RoundedRectangle(cornerRadius: 1).fill(color)
                .frame(width: isOff ? 6 : Self.bar, height: height)
                .padding(.bottom, 8)
            if index == j { Circle().fill(litColour).frame(width: 3, height: 3).padding(.bottom, 3) }
        }
        .frame(width: Self.column, height: QCSpace.row, alignment: .bottom)
        .qcControl()
        .onTapGesture { if s.takes { pick(j) } }
        .onHover { inside in
            if inside {
                hover = j
                QCFloat.shared.show(AnyView(QCStepTipView(text: s.why ?? s.title, costly: s.costly && s.takes, muted: !s.takes, keys: keys)),
                                    above: QCStepTargets.shared.bars["\(key)\(j)"]?.frame ?? .zero)
            } else if hover == j {
                hover = nil
                QCFloat.shared.hide()
            }
        }
        .onDisappear { if hover == j { QCFloat.shared.hide() } }
        .modifier(QCHandIf(on: s.takes))      // a level the model doesn't take does nothing: no pointing hand
        .background(rendering ? nil : GeometryReader { g in
            Color.clear
                .onAppear { QCStepTargets.shared.bar(key, j, g.frame(in: .global), token: token) { if s.takes { pick(j) } } }
                .onChange(of: g.frame(in: .global)) { f in QCStepTargets.shared.bar(key, j, f, token: token) { if s.takes { pick(j) } } }
        })
    }

    private var fill: Color {
        let warm = tint == 2 ? 0.27 : tint == 1 ? 0.13 : 0
        return warm > 0 ? QCColor.accent.opacity(warm) : .clear
    }
}

/// The hover tip's look: the step's full name ("Sonnet 5.5", "Medium"), "uses limits faster" for a costly one, and the
/// keys that step the control.
struct QCStepTipView: View {
    let text: String
    let costly: Bool
    let muted: Bool
    let keys: String
    var body: some View {
        (Text(text).fontWeight(.semibold).foregroundColor(muted ? QCColor.muted : QCColor.text)
            + Text(costly ? " · uses limits faster" : "").foregroundColor(QCColor.hex(0xF1B59B))
            + Text("  " + keys).foregroundColor(QCColor.muted))
            .font(.system(size: 11.5)).lineLimit(1).fixedSize()
            .padding(.horizontal, 8).frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(QCColor.hex(0x1C1C1B)))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(QCColor.line))
            .environment(\.colorScheme, .dark)
    }
}

/// A small window of its own just above a part of the row (a bar's tip, the usage card): it draws over the field (an
/// AppKit view that anything drawn in the row's own view would sit under) and takes no part in the row's layout or the
/// mouse. One window, made the first time; a child of the panel, so it moves with it, and taken away when the pointer
/// leaves or the panel hides.
final class QCFloat {
    static let shared = QCFloat()
    enum Align { case center, trailing }
    private var window: NSPanel?
    private var host: NSHostingView<AnyView>?

    /// Shows a view above a frame of the panel's hosting view (its top-left space), centred on it or right-aligned with
    /// it, kept inside the panel's width.
    func show(_ view: AnyView, above frame: CGRect, align: Align = .center) {
        guard frame != .zero, let panel = NSApp.windows.first(where: { $0 is QuickChatPanel && $0.isVisible }),
              let cv = panel.contentView else { return }
        let w: NSPanel
        if let window, let host { host.rootView = view; w = window } else {
            w = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = true
            w.ignoresMouseEvents = true; w.isReleasedWhenClosed = false
            let h = NSHostingView(rootView: view)
            w.contentView = h
            window = w; host = h
        }
        let size = host!.fittingSize
        // the frame's top edge, from the hosting view's top-left space to the screen
        let anchor = align == .center ? frame.midX : frame.maxX
        let top = cv.convert(NSPoint(x: anchor, y: cv.isFlipped ? frame.minY : cv.bounds.height - frame.minY), to: nil)
        let onScreen = panel.convertPoint(toScreen: top)
        var x = align == .center ? onScreen.x - size.width / 2 : onScreen.x - size.width
        x = min(max(x, panel.frame.minX + 4), panel.frame.maxX - 4 - size.width)
        w.setFrame(NSRect(x: x, y: onScreen.y + 2, width: size.width, height: size.height), display: true)
        if w.parent !== panel { w.parent?.removeChildWindow(w); panel.addChildWindow(w, ordered: .above) }
        w.orderFront(nil)
    }

    func hide() {
        guard let w = window else { return }
        w.parent?.removeChildWindow(w)
        w.orderOut(nil)
    }
}

/// The pointing hand only where a click does something.
private struct QCHandIf: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.qcPointingHand() } else { content }
    }
}

/// Where the step controls and their bars are in the panel (the hosting view's top-left coordinates), kept as SwiftUI
/// lays them out (no polling): the scroll wheel finds the control under the pointer here, and Checks/bars.sh clicks each
/// bar's centre through it. Only the row on screen reports (ViewThatFits draws one candidate); each key is overwritten
/// by whichever row is drawn. Main thread.
final class QCStepTargets {
    static let shared = QCStepTargets()
    private(set) var controls: [String: (frame: CGRect, step: (Int) -> Bool)] = [:]
    private(set) var bars: [String: (frame: CGRect, pick: () -> Void)] = [:]
    /// Which drawn control (its token) owns each key: a row that went (the bar became the window, another width picked
    /// another row) can't overwrite or remove the one on screen.
    private var owners: [String: UUID] = [:]
    private var monitor: Any?
    private var scrolled: (key: String, sum: CGFloat)?

    /// A control laid out: its frame, and how many bars it has now (a profile with fewer families leaves none behind).
    func control(_ key: String, _ frame: CGRect, bars count: Int, token: UUID, step: @escaping (Int) -> Bool) {
        owners[key] = token
        controls[key] = (frame, step)
        for k in bars.keys where k.hasPrefix(key) && (Int(k.dropFirst(key.count)) ?? 0) >= count { bars[k] = nil }
        if monitor == nil { watchScrolls() }
    }
    /// Other parts of the row the checks look at (the usage indicator and its rows, the open bars), by name.
    private(set) var marks: [String: CGRect] = [:]
    func mark(_ key: String, _ frame: CGRect) { marks[key] = frame }

    /// The "Opus · High" pill: where it is, what a click on it does, how the open bars close, and what the scroll wheel
    /// over it steps (up and down thinking, sideways the model, as the ⌥⌘ arrows do).
    struct Pill {
        var frame: CGRect
        var toggle: () -> Void
        var close: () -> Void
        var stepThinking: (Int) -> Bool
        var stepModel: (Int) -> Bool
    }
    private(set) var pill: Pill?
    private var presses: Any?
    func pill(_ p: Pill) {
        pill = p
        if monitor == nil { watchScrolls() }
        if presses == nil {
            // a click anywhere else in the panel closes the open bars, and still does what it does there (one local
            // monitor, an event handler: nothing is polled)
            presses = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] e in
                self?.press(e)
                return e
            }
        }
    }

    /// The open bars' panel, drawn over the row: its frame, owned by the pill that opened it (a row that went can't
    /// clear the one on screen).
    private var open: (frame: CGRect, token: UUID)?
    func opened(_ frame: CGRect, token: UUID) { open = (frame, token) }
    func closed(token: UUID) { if open?.token == token { open = nil } }
    var openFrame: CGRect? { open?.frame }

    /// A mouse-down in the panel (the monitor's, or a check's event): while the bars are open, a press outside them and
    /// the pill closes them (a press on the pill is the pill's own: it closes them itself).
    func press(_ e: NSEvent) {
        guard let w = e.window as? QuickChatPanel, let cv = w.contentView else { return }
        var p = cv.convert(e.locationInWindow, from: nil)
        if !cv.isFlipped { p.y = cv.bounds.height - p.y }
        pressed(at: p)
    }
    /// A press at a point of the hosting view.
    func pressed(at p: CGPoint) {
        guard let pill, let open = open?.frame else { return }
        if !open.contains(p) && !pill.frame.contains(p) { pill.close() }
    }

    func bar(_ control: String, _ j: Int, _ frame: CGRect, token: UUID, pick: @escaping () -> Void) {
        guard owners[control] == nil || owners[control] == token else { return }
        bars["\(control)\(j)"] = (frame, pick)
    }
    /// The control went: its entries go, unless another drawn one has taken its key since.
    func drop(_ key: String, token: UUID) {
        guard owners[key] == token else { return }
        owners[key] = nil
        controls[key] = nil
        for k in bars.keys where k.hasPrefix(key) { bars[k] = nil }
    }

    /// The scroll wheel (or two fingers) over a step control steps it: up or right is a step up. One local monitor (an
    /// event handler, not a timer), set up with the first control.
    private func watchScrolls() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
            guard let self, let w = e.window as? QuickChatPanel, w.isVisible, let cv = w.contentView else { return e }
            var p = cv.convert(e.locationInWindow, from: nil)
            if !cv.isFlipped { p.y = cv.bounds.height - p.y }
            let inverted: CGFloat = e.isDirectionInvertedFromDevice ? -1 : 1
            let sideways = abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY)
            let d = (sideways ? -e.scrollingDeltaX : e.scrollingDeltaY) * inverted
            return self.scroll(at: p, by: d, precise: e.hasPreciseScrollingDeltas,
                               began: e.phase.contains(.began) || e.phase.contains(.mayBegin),
                               momentum: e.momentumPhase != [], sideways: sideways) ? nil : e
        }
    }

    /// A scroll of `d` (up or right positive) at a point of the hosting view: whether a step control or the pill took
    /// it (the open bars before the pill they cover; over the pill, up and down steps thinking and sideways the model).
    /// A wheel's notch is a step. A trackpad gesture belongs to what it began over: its deltas add up to 24 pt a step and
    /// its momentum is taken and steps nothing; a gesture that began anywhere else (the chat scrolling onto the row)
    /// passes through whole, momentum too.
    @discardableResult func scroll(at p: CGPoint, by d: CGFloat, precise: Bool, began: Bool, momentum: Bool = false,
                                   sideways: Bool = false) -> Bool {
        let over = controls.first(where: { $0.value.frame.contains(p) })?.key
            ?? (pill.map { $0.frame.contains(p) } == true ? (sideways ? "pill-m" : "pill-t") : nil)
        let key: String
        if precise {
            if began && !momentum { scrolled = over.map { ($0, 0) } }
            guard let owner = scrolled?.key else { return false }
            if momentum { return true }
            key = owner
        } else {
            guard let over else { return false }
            if scrolled?.key != over { scrolled = (over, 0) }
            key = over
        }
        guard let step = controls[key]?.step ?? (key == "pill-m" ? pill?.stepModel : key == "pill-t" ? pill?.stepThinking : nil) else { return false }
        let threshold: CGFloat = precise ? 24 : 0.9
        var sum = (scrolled?.sum ?? 0) + d
        while abs(sum) >= threshold {
            _ = step(sum > 0 ? 1 : -1)
            sum -= sum > 0 ? threshold : -threshold
        }
        scrolled = (key, sum)
        return true
    }
}

/// Set while drawing a picture: a step control as if the pointer were on one of its bars ("m2": the model's third,
/// "t0": thinking's Off).
private struct QCStepHoverKey: EnvironmentKey { static let defaultValue: String? = nil }
extension EnvironmentValues {
    var qcStepHover: String? {
        get { self[QCStepHoverKey.self] }
        set { self[QCStepHoverKey.self] = newValue }
    }
}

/// The profile picker's key: a dot, then its title and a chevron (a narrow row: the dot alone); it opens a menu.
struct QCChip: View {
    let title: String
    /// A small dot before the title (the profile's level colour).
    var dot: Color? = nil
    var help = ""
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
                // with no title (a narrow row) the dot alone, without its chevron, so the step controls keep their labels
                if !title.isEmpty {
                    Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).opacity(0.7)
                }
            }
            .foregroundColor(hover ? QCColor.text : QCColor.soft)
            .padding(.horizontal, QCSpace.keyPadding).frame(height: QCSpace.row)
            .background(RoundedRectangle(cornerRadius: QCSpace.keyCorner, style: .continuous).fill(hover ? QCColor.hover : .clear))
            .qcControl()     // its gaps and padding too, never a move
        }
        .buttonStyle(.plain).help(help).onHover { hover = $0 }
    }
}

/// The profile menu: macOS's own, at the pointer. A heading, the profiles (a dot in the level's colour, the week and its
/// reset in grey under the name), a line, then Add a profile…. No footer: what it used to say is the picker's tooltip.
enum QCMenu {
    struct Item {
        let title: String
        let detail: String
        var dot: NSColor? = nil
        var on = false
        let action: () -> Void
    }

    private final class Handler: NSObject {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
        @objc func fire() { run() }
    }

    /// The profile menu for the profiles the picker offers.
    static func profiles(_ list: [(Profile, QuickChatLevel?)], on: String?, pick: @escaping (String) -> Void, add: @escaping () -> Void) -> NSMenu {
        build(header: "Profile", items: list.map { p, l in
            Item(title: p.name, detail: weekWords(l), dot: NSColor(QuickChatLevel.color(l?.binding()?.p)),
                 on: p.id == on) { pick(p.id) }
        }, actions: [Item(title: "Add a profile…", detail: "", action: add)])
    }

    /// "week 67%, resets Sun 13:00", "week full until Thu 09:00", "no numbers yet".
    static func weekWords(_ l: QuickChatLevel?) -> String {
        guard let l else { return "no numbers yet" }
        if let f = l.full() { return "\(f.name) full" + (f.resets.map { " until \(TimeWords.when($0))" } ?? "") }
        guard let w = l.weekNow() else { return "no numbers yet" }
        return "week \(Int(w.rounded()))%" + (l.weekResets.map { ", resets \(TimeWords.when($0))" } ?? "")
    }

    static func build(header: String, items: [Item], actions: [Item]) -> NSMenu {
        let m = NSMenu(); m.autoenablesItems = false
        if #available(macOS 14, *) { m.addItem(.sectionHeader(title: header)) }
        else { let h = NSMenuItem(title: header, action: nil, keyEquivalent: ""); h.isEnabled = false; m.addItem(h) }
        for it in items {
            let i = item(it)
            i.state = it.on ? .on : .off
            if let c = it.dot { i.image = dot(c) }
            if #available(macOS 15, *) {
                i.subtitle = it.detail         // under the name: the menu stays narrow
            } else {
                // the subtitle shows from macOS 15 on (14.4 has the property but doesn't show it with an attributed title,
                // and 13 lacks it): before that, the words in grey after the name
                let s = NSMutableAttributedString(string: it.title, attributes: [.font: NSFont.menuFont(ofSize: 0)])
                s.append(NSAttributedString(string: "   " + it.detail, attributes: [
                    .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.secondaryLabelColor]))
                i.attributedTitle = s
            }
            m.addItem(i)
        }
        if !actions.isEmpty { m.addItem(.separator()) }
        for a in actions { m.addItem(item(a)) }
        return m
    }

    static func pop(_ m: NSMenu) { m.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil) }

    private static func item(_ it: Item) -> NSMenuItem {
        let handler = Handler(it.action)
        let i = NSMenuItem(title: it.title, action: #selector(Handler.fire), keyEquivalent: "")
        i.target = handler
        i.representedObject = handler      // the menu item keeps its handler alive
        return i
    }

    /// An 8 pt dot in a 12 pt square, drawn once per menu.
    private static func dot(_ c: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { r in
            c.setFill()
            NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 8, height: 8)).fill()
            return true
        }
    }
}

struct QCButton: View {
    let title: String
    var ghost = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(ghost ? QCColor.text : QCColor.bubble)
                .padding(.horizontal, 12).frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ghost ? QCColor.hover : QCColor.text))
                .qcControl()
        }
        .buttonStyle(.plain)
    }
}

struct QCIconButton: View {
    let symbol: String
    let help: String
    /// A 24 pt target with a smaller glyph (an answer's actions, a code block's Copy); else 28.
    var small = false
    var size: CGFloat? = nil
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        let side = size ?? (small ? QCSpace.small : QCSpace.row)
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: small ? 12 : 13.5, weight: .medium))
                .frame(width: side, height: side)
                .foregroundColor(hover ? QCColor.text : QCColor.muted)
                .background(RoundedRectangle(cornerRadius: small ? 6 : QCSpace.keyCorner, style: .continuous).fill(hover ? QCColor.hover : .clear))
                .qcControl()     // the whole target
        }
        .buttonStyle(.plain).help(help).onHover { hover = $0 }
    }
}

/// Copy under an answer and in a code block's top row: its icon turns into a tick for a moment.
struct QCCopyIcon: View {
    let text: String
    @State private var done = false
    var body: some View {
        QCIconButton(symbol: done ? "checkmark" : "doc.on.doc", help: "Copy", small: true) {
            QCCopy.put(text); done = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { done = false }
        }
    }
}

enum QCCopy {
    static func put(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}

// MARK: - The field

/// The message field: grows to six lines, Return sends, Shift-Return adds a line, Esc hides the chat.
struct QCField: View {
    @ObservedObject var model: QuickChatModel
    let placeholder: String
    let size: CGFloat
    /// The bar's field takes the height the panel has beyond its own (a bar dragged taller); the chat's stays its own.
    var grows = false
    /// How far past the field the press area reaches (QCFieldArea): the gap down to the picker row, and in the chat the
    /// box's padding, so the whole box above the picker row is the field.
    var area = EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0)
    @State private var height: CGFloat = 24
    @State private var caps = false
    @Environment(\.qcRendering) private var rendering

    var body: some View {
        if rendering {
            Text(model.field.isEmpty ? placeholder : model.field)
                .font(.system(size: size)).foregroundColor(model.field.isEmpty ? QCColor.muted : QCColor.text)
                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        } else {
            QCTextField(text: $model.field, height: $height, placeholder: placeholder, size: size, focusTick: model.focusTick,
                        onSubmit: { model.send() }, onEscape: { model.escape() }, onCaps: { caps = $0 })
                .frame(minHeight: height, maxHeight: grows ? .infinity : height)
                .background(QCFieldArea().padding(EdgeInsets(top: -area.top, leading: -area.leading, bottom: -area.bottom, trailing: -area.trailing)))
                .onChange(of: height) { _ in model.fieldChanged() }
                .overlay(alignment: .topTrailing) {
                    // macOS's own Caps Lock badge would land on the keys below (QuickChatPanel.addChildWindow): this says it
                    if caps {
                        Image(systemName: "capslock.fill").font(.system(size: size * 0.7, weight: .medium)).foregroundColor(QCColor.muted)
                            .help("Caps Lock is on").allowsHitTesting(false)
                    }
                }
        }
    }
}

struct QCTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    let placeholder: String
    let size: CGFloat
    let focusTick: Int
    let onSubmit: () -> Void
    let onEscape: () -> Void
    var onCaps: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = QCFieldScroll()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.borderType = .noBorder
        // no automatic insets: since the panel is titled (its title bar transparent and hidden), AppKit insets a scroll
        // view under the title bar by the bar's height, which pushed the bar's text out of its field
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsetsZero
        // a flipped clip view: the text sits at the TOP of the field. (The default clip view isn't flipped, so the text view
        // sat at its bottom, in the bar even below what the clip view shows: no caret, no placeholder, and a press in the
        // field hit the scroll view instead of the text.)
        let clip = QCFlippedClip()
        clip.drawsBackground = false
        scroll.contentView = clip
        let tv = QCTextView()
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = true
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.insertionPointColor = NSColor(QCColor.accent)
        scroll.documentView = tv
        context.coordinator.textView = tv
        tv.onWidth = { [weak c = context.coordinator] in c?.measure() }     // the panel was resized: the lines wrap anew
        tv.onCaps = { [weak c = context.coordinator] on in DispatchQueue.main.async { c?.parent.onCaps(on) } }
        apply(tv)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = context.coordinator.textView else { return }
        if tv.string != text { tv.string = text }
        apply(tv)
        if context.coordinator.focusTick != focusTick {
            context.coordinator.focusTick = focusTick
            DispatchQueue.main.async {
                tv.window?.makeFirstResponder(tv)
                // Caps Lock may have been pressed while the panel was hidden (the field's own mark stands for macOS's badge)
                onCaps(NSEvent.modifierFlags.contains(.capsLock))
            }
        }
        context.coordinator.measure()
    }

    private func apply(_ tv: QCTextView) {
        let font = NSFont.systemFont(ofSize: size)
        tv.font = font
        tv.textColor = NSColor(QCColor.text)
        tv.typingAttributes = [.font: font, .foregroundColor: NSColor(QCColor.text)]
        tv.placeholder = NSAttributedString(string: placeholder, attributes: [.font: font, .foregroundColor: NSColor(QCColor.muted)])
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: QCTextField
        weak var textView: QCTextView?
        var focusTick = -1
        init(_ p: QCTextField) { parent = p }

        func textDidChange(_ n: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
            measure()
        }

        func textView(_ tv: NSTextView, doCommandBy sel: Selector) -> Bool {
            switch sel {
            case #selector(NSResponder.insertNewline(_:)):
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { tv.insertNewlineIgnoringFieldEditor(nil); return true }
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEscape()
                return true
            default:
                return false
            }
        }

        /// One line up to six: the field grows with the text, then scrolls.
        func measure() {
            guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
            lm.ensureLayout(for: tc)
            let line = (tv.font ?? .systemFont(ofSize: parent.size)).boundingRectForFont.height
            let used = max(line, lm.usedRect(for: tc).height)
            let h = min(ceil(used), ceil(line * 6))
            if abs(h - parent.height) > 0.5 { DispatchQueue.main.async { self.parent.height = h } }
        }
    }
}

/// The field's clip view: flipped, so the text starts at the top.
final class QCFlippedClip: NSClipView {
    override var isFlipped: Bool { true }
}

/// The field's scroll view: the text view is never shorter than what the field shows, so all of the field (a bar dragged
/// taller gives its extra height to it) is the text: a press anywhere there puts the caret in, under the I-beam.
final class QCFieldScroll: NSScrollView {
    override func tile() {
        super.tile()
        guard let tv = documentView as? NSTextView else { return }
        let h = contentSize.height
        if abs(tv.minSize.height - h) > 0.5 { tv.minSize = NSSize(width: 0, height: h) }
        if tv.frame.height < h - 0.5 { tv.setFrameSize(NSSize(width: tv.frame.width, height: h)) }
        // the text fits: it shows from its top. (Resizing the field kept an old scroll offset, which put the text above or
        // below what the field shows.) Taller text (past six lines) keeps its scroll, so the caret stays in view.
        if tv.frame.height <= h + 0.5, contentView.bounds.origin != .zero {
            contentView.scroll(to: .zero)
            reflectScrolledClipView(contentView)
        }
    }
}

/// The field box's empty part around the field (the box's padding, the gap above the picker row): a press there is a
/// press in the field (focus, the caret at the nearest place, at the end below the text), under the I-beam, never a
/// move. It finds the window's field itself, so it needs no wiring.
struct QCFieldArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { QCFieldAreaView() }
    func updateNSView(_ view: NSView, context: Context) {}
}

final class QCFieldAreaView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The field this area belongs to: the window's text field nearest to it (there is one per mode).
    var field: QCTextView? {
        guard let content = window?.contentView else { return nil }
        let mine = convert(bounds, to: nil)
        var best: (QCTextView, CGFloat)?
        func walk(_ v: NSView) {
            if let tv = v as? QCTextView {
                let r = tv.enclosingScrollView.map { $0.convert($0.bounds, to: nil) } ?? tv.convert(tv.bounds, to: nil)
                let d = r.intersects(mine) ? 0 : hypot(r.midX - mine.midX, r.midY - mine.midY)
                if best == nil || d < best!.1 { best = (tv, d) }
            }
            v.subviews.forEach(walk)
        }
        walk(content)
        return best?.0
    }

    override func mouseDown(with event: NSEvent) {
        guard let tv = field else { return }
        window?.makeFirstResponder(tv)
        tv.mouseDown(with: event)        // the caret where the press is nearest (the text view clamps it to its text)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.cursorUpdate, .mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func cursorUpdate(with event: NSEvent) { NSCursor.iBeam.set() }
    override func mouseEntered(with event: NSEvent) { NSCursor.iBeam.set() }
    override func mouseMoved(with event: NSEvent) { NSCursor.iBeam.set() }
}

final class QCTextView: NSTextView {
    var placeholder: NSAttributedString? { didSet { needsDisplay = true } }
    // The I-beam while the panel isn't the key window too (the text view's own cursor rects work only in the key window).
    private var beam: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let b = beam { removeTrackingArea(b) }
        let b = NSTrackingArea(rect: .zero, options: [.cursorUpdate, .mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(b)
        beam = b
    }
    override func cursorUpdate(with event: NSEvent) { NSCursor.iBeam.set() }
    override func mouseEntered(with event: NSEvent) { NSCursor.iBeam.set() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// Called when the width changes (the panel is resized).
    var onWidth: (() -> Void)?
    override func setFrameSize(_ s: NSSize) {
        let was = frame.width
        super.setFrameSize(s)
        if abs(was - s.width) > 0.5 { onWidth?() }
    }
    override func draw(_ r: NSRect) {
        super.draw(r)
        if string.isEmpty, let p = placeholder { p.draw(at: NSPoint(x: textContainerOrigin.x, y: textContainerOrigin.y)) }
    }
    /// Called with whether Caps Lock is on, when it changes and when the field takes the keyboard.
    var onCaps: ((Bool) -> Void)?
    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        onCaps?(event.modifierFlags.contains(.capsLock))
    }
    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        let ok = super.becomeFirstResponder()
        onCaps?(NSEvent.modifierFlags.contains(.capsLock))
        return ok
    }
}

// MARK: - A picture of it, for checking (`--render-quick-chat OUT.png STATE`)

enum QuickChatRender {
    @MainActor static func write(to path: String, state: String) {
        // the profile menu can't be drawn to a picture: menu-one and menu-several write what it holds, as text
        if state.hasPrefix("menu") {
            var main = QuickChatLevel(); main.week = 67; main.weekResets = Date().addingTimeInterval(4 * 86400)
            var work = QuickChatLevel(); work.week = 12
            var spare = QuickChatLevel(); spare.week = 100; spare.weekResets = Date().addingTimeInterval(2 * 86400)
            var list: [(Profile, QuickChatLevel?)] = [(Profile(id: "main", name: "Main", folder: "~/.claude-sample"), main)]
            if state == "menu-several" {
                list += [(Profile(id: "work", name: "Work", folder: "~/.claude-work"), work),
                         (Profile(id: "spare", name: "Spare", folder: "~/.claude-spare"), spare),
                         (Profile(id: "lab", name: "Lab", folder: "~/.claude-lab"), nil)]
            }
            let menu = QCMenu.profiles(list, on: "main", pick: { _ in }, add: {})
            let lines = menu.items.map { i -> String in
                if i.isSeparatorItem { return "———" }
                var sub = ""
                if #available(macOS 15, *) { sub = i.subtitle.map { "  /  " + $0 } ?? "" }
                let title = i.attributedTitle?.string ?? i.title
                return (i.state == .on ? "✓ " : "  ") + (i.image != nil ? "● " : "") + title + sub + (i.isEnabled ? "" : "  (heading)")
            }
            try? (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
            return
        }
        let m = QuickChatModel()
        var target = QuickChatTarget(Profile(id: "main", name: "Main", folder: "~/.claude-sample"))
        target.email = "ultra-1@example.com"
        m.target = target
        m.knownModels[.haiku] = "Haiku 5.5"
        // Claude Code's list as an account with all four families gives it: each by name alone, the version in its
        // description (models3: no Fable; models2: Haiku and Sonnet)
        let efforts = ["low", "medium", "high", "xhigh", "max"]
        var list: [QuickChatModelEntry] = [
            .init(value: "haiku", displayName: "Haiku", description: "Haiku 5.5 · Fastest for quick answers", efforts: ["low", "medium", "high"]),
            .init(value: "sonnet", displayName: "Sonnet", description: "Sonnet 5.5 · Efficient for routine tasks", efforts: Array(efforts.prefix(4))),
            .init(value: "opus", displayName: "Opus", description: "Opus 5.5 · Best for everyday, complex tasks", efforts: efforts),
            .init(value: "claude-fable-5-1[1m]", displayName: "Fable", description: "Fable 5.1 · Most capable", efforts: efforts),
        ]
        if state.hasPrefix("models3") { list.removeLast() }
        if state.hasPrefix("models2") { list.removeLast(2) }
        ModelCatalog.shared.set(list, profile: target.profileID, account: target.accountUUID)
        var level = QuickChatLevel()
        level.week = 62; level.weekResets = Date().addingTimeInterval(3 * 86400)
        m.level = level
        let q1 = "How do I find which process is using port 3000 on macOS?"
        let a1 = "Use `lsof`:\n```zsh\nlsof -nP -iTCP:3000 -sTCP:LISTEN\n```\nThe **PID** column is the process. Stop it with `kill <PID>`.\n- `-nP` keeps addresses and ports as numbers, which is faster.\n- `-sTCP:LISTEN` shows only the server, not its clients."
        var t1 = QuickChatTurn(question: q1, answer: a1, model: "Haiku 5.5"); t1.phase = .done; t1.seconds = 2.4
        // any state with -open: the model and thinking bars open over the row ("bar-open", "tint-fablemax-open")
        let base = state.hasSuffix("-open") ? String(state.dropLast("-open".count)) : state
        m.controlsOpen = base != state
        switch base {
        case "typing": m.field = q1
        // the bar's usage indicator: the 5-hour window higher, the week higher, the 5-hour window full
        case "usage-5h": level.fiveHour = 78; level.fiveHourResets = Date().addingTimeInterval(2 * 3600); level.week = 20; m.level = level
        case "usage-wk": level.fiveHour = 30; level.fiveHourResets = Date().addingTimeInterval(2 * 3600); level.week = 85; m.level = level
        case "usage-full": level.fiveHour = 100; level.fiveHourResets = Date().addingTimeInterval(2 * 3600); level.week = 64; m.level = level
        case "notinstalled": m.field = q1; m.barProblem = .notInstalled
        case "streaming": var t = t1; t.answer = String(a1.prefix(90)); t.phase = .streaming; m.turns = [t]
        case "answer": m.turns = [t1]
        case "failed": var t = t1; t.answer = String(a1.prefix(60)); t.phase = .failed
            t.problem = .stopped(detail: "claude exited with code 1: API Error: Connection error."); m.turns = [t]
        case "notsigned": var t = QuickChatTurn(question: q1); t.phase = .failed; t.problem = .notSignedIn(profile: "Main", id: "main"); m.turns = [t]
        case "thinking", "short", "haiku", "tint-fable", "tint-extra", "tint-max", "tint-fablemax", "models3", "models2",
             _ where base.hasPrefix("hover-"):
            var t2 = QuickChatTurn(question: "And only the PID, for a script?",
                                   answer: "Add `-t`, which prints bare PIDs:\n```zsh\nkill $(lsof -t -iTCP:3000 -sTCP:LISTEN)\n```",
                                   thinking: "They want only the PIDs.", model: "Sonnet 5.5", thinkingTitle: "High")
            t2.phase = .done; t2.seconds = 7.8; t2.thinkingSeconds = 5
            m.choice = .sonnet; m.knownModels[.sonnet] = "Sonnet 5.5"; m.thinking = .high; m.turns = [t1, t2]
            // the model and thinking controls: which family and level each picture shows (hover-…: open, the pointer on a bar)
            if state.hasPrefix("hover-") { m.controlsOpen = true }
            switch base {
            case "haiku": m.choice = .haiku; m.thinking = .medium       // Haiku takes Low to High: Extra and Max are faint
            case "tint-fable": m.choice = .fable; m.thinking = .high
            case "tint-extra", "models3": m.choice = .opus; m.thinking = .xhigh
            case "tint-max": m.choice = .opus; m.thinking = .max
            case "tint-fablemax": m.choice = .fable; m.thinking = .max
            case "models2": m.choice = .sonnet; m.thinking = .medium
            case _ where base.hasPrefix("hover-"): m.choice = .opus; m.thinking = .high
            default: break
            }
        case "full":
            m.field = q1
            level.week = 100; level.weekResets = Date().addingTimeInterval(26 * 3600); m.level = level
            m.offer = QuickChatOffer(profileID: "work", name: "Work", week: 18)
        case "switch", "switching", "wrong", "timedout":
            // a full week, with the profile's standby account offered besides Ask on …
            m.field = q1
            level.week = 100; level.weekResets = Date().addingTimeInterval(26 * 3600); m.level = level
            m.offer = QuickChatOffer(profileID: "work", name: "Work", week: 18)
            m.switchOffer = QuickChatSwitchOffer(uuid: "u2", email: "ultra-2@example.com", week: nil)
            if base == "switching" { m.switchNotice = .waiting(wanted: "ultra-2@example.com") }
            if base == "wrong" { m.switchNotice = .wrong(signedIn: "ultra-3@example.com", wanted: "ultra-2@example.com") }
            if base == "timedout" { m.switchNotice = .timedOut(wanted: "ultra-2@example.com") }
        case "switched":
            // after a switch: a new chat on the same profile, the typed question sent, one line on where it is
            var t = QuickChatTurn(question: q1); t.phase = .waiting
            target.email = "ultra-2@example.com"; m.target = target
            m.level = nil
            m.accountNote = "Main is on \(maskEmail("ultra-2@example.com")) now."
            m.turns = [t]
        case "ended-idle": m.turns = [t1]; m.ended = .idle
        case "ended-stopped": var t = t1; t.answer = String(a1.prefix(60)); t.phase = .stopped; m.turns = [t]; m.ended = .stopped
        case "ended-failed": var t = t1; t.answer = String(a1.prefix(60)); t.phase = .failed
            t.problem = .stopped(detail: "claude exited with code 1: API Error: Connection error."); m.turns = [t]; m.ended = .failed
        case "ended-closed": m.turns = [t1]; m.ended = .closed
        case "level95": level.week = 96; m.level = level; m.turns = [t1]
        default: break
        }
        // the chat's account line alone, at a width (QC_RENDER_WIDTH, 520): header, header-nosession (no 5-hour number
        // reported), header-long (a long profile name and address), header-longaddr (a long address only), each also with -hover-meter (the pointer on the
        // meters: their card, the address still blurred) or -hover-address (the pointer on the address capsule), and
        // -copied (the capsule just after a click copied the address; with -hover-address too, over the grown capsule)
        if state.hasPrefix("header") {
            var l = QuickChatLevel()
            l.week = 58; l.weekResets = Date().addingTimeInterval(3 * 86400)
            if !state.contains("nosession") { l.fiveHour = 41; l.fiveHourResets = Date().addingTimeInterval(2 * 3600 + 600) }
            if state.contains("full") { l.week = 100; l.weekResets = Date().addingTimeInterval(26 * 3600) }
            m.level = l
            if state.contains("longaddr") {
                target.email = "alexandra.longname@example.com"; m.target = target
            } else if state.contains("long") {
                target.name = state.contains("verylong") ? "Work – client project, EU team" : "Personal-work"
                target.email = "alexandra.longname@example.com"; m.target = target
            }
            let width = ProcessInfo.processInfo.environment["QC_RENDER_WIDTH"].flatMap { Double($0) }.map { CGFloat($0) } ?? QuickChatRoot.width
            let header = QCHeader(model: m).environment(\.qcRendering, true).environment(\.qcHover, state.contains("hover-meter"))
                .environment(\.qcAddressHover, state.contains("hover-address"))
                .environment(\.qcAddressCopied, state.contains("copied"))
                .environment(\.qcNameHover, state.contains("namehover"))
                .frame(width: width).background(QCColor.window).padding(.bottom, 80)       // room for the meters' card under it
                .environment(\.colorScheme, .dark).padding(20).background(Color(white: 0.1))
            let r = ImageRenderer(content: header)
            r.scale = 2
            if let tiff = r.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            return
        }
        // the panel gives the root its size: the first width, and for the chat the first height (bar-tall: a bar dragged
        // taller, 72 pt above its content's; short: the smallest window); QC_RENDER_WIDTH and QC_RENDER_HEIGHT set others
        let env = ProcessInfo.processInfo.environment
        let width = env["QC_RENDER_WIDTH"].flatMap { Double($0) }.map { CGFloat($0) } ?? QuickChatRoot.width
        let height = env["QC_RENDER_HEIGHT"].flatMap { Double($0) }.map { CGFloat($0) }
            ?? (base == "short" ? QuickChatRoot.minWindowHeight : QuickChatRoot.windowHeight)
        // hover-m2: the pointer on the model's third bar; hover-t0: on thinking's Off
        let stepHover: String? = state.hasPrefix("hover-") ? String(state.dropFirst("hover-".count)) : nil
        let view = QuickChatRoot(model: m).environment(\.qcRendering, true).environment(\.qcStepHover, stepHover)
            .frame(width: width, height: m.isWindow ? height : base == "bar-tall" ? 170 : nil)
            .padding(30).background(Color(white: 0.1))
        let r = ImageRenderer(content: view)
        r.scale = 2
        if let tiff = r.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
    }
}
