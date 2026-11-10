// QuickChatViews: the quick chat's bar and chat window (QuickChat.swift), in Claude's own dark colours rather than
// cl_audit's front panel: it should feel like Claude. The bar is a field over one row of controls; the first message
// turns it into a chat window: the account line on top, the chat, and the field box at the bottom, all on one 10 pt
// outer gap (QCSpace). Answers are Markdown in the system font, code blocks have Copy, and the last answer says which
// model gave it. The profile, the model and thinking are pickers that open a menu.

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
/// the hosting view reports as its intrinsic height: QuickChat.fit). Around the visible card is an 8 pt rim the resize
/// handles are in (ResizeHandles.swift), so they take nothing from what is inside the card: a drag that starts on the card
/// is always a move.
struct QuickChatRoot: View {
    static let width: CGFloat = 520            // the first width of the card
    static let windowHeight: CGFloat = 580     // the chat's first height
    static let minWidth: CGFloat = 320         // the key row fits on one line from here (QCControls drops the week, then words)
    static let minWindowHeight: CGFloat = 220  // header, a line of chat and the field at one line; a taller field asks for more
    static let margin: CGFloat = 8             // the rim around the card: where the resize handles are (ResizeHandles.swift)
    @ObservedObject var model: QuickChatModel
    @Environment(\.qcRendering) private var rendering

    var body: some View {
        Group {
            if model.isWindow { QCWindow(model: model) } else { QCBar(model: model) }
        }
        .frame(minWidth: Self.minWidth, maxWidth: .infinity,
               minHeight: model.isWindow ? Self.minWindowHeight : nil, maxHeight: .infinity, alignment: .top)
        .padding(rendering ? 0 : Self.margin)
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
                QCField(model: model, placeholder: "Reply…", size: 15)
                QCControls(model: model, inBar: false)
            }
            .padding(QCSpace.boxPadding)
            .qcDraggable()
            .background(RoundedRectangle(cornerRadius: QCSpace.boxCorner, style: .continuous).fill(QCColor.surface))
            .overlay(RoundedRectangle(cornerRadius: QCSpace.boxCorner, style: .continuous).strokeBorder(QCColor.line))
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
extension EnvironmentValues {
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
struct QCBlurred: View {
    let text: String
    /// The pointer is in the hover zone: the capsule shows the whole address. Kept by the header (the line's candidates
    /// replace each other while the pointer is on it).
    @Binding var hover: Bool
    @Environment(\.qcAddressHover) private var pictureHover
    private var reveal: Bool { hover || pictureHover }

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
                if grown {
                    capsule(fullWidth, blurred: false)
                        .background(Capsule().fill(QCColor.window))      // opaque: the meters under it don't show through
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
                }
            }
            .overlay(alignment: .leading) {
                Color.clear
                    .frame(width: (grown ? fullWidth : restWidth) + Self.zoneLeading + Self.zoneOther, height: Self.height + 2 * Self.zoneOther)
                    .contentShape(Rectangle())
                    .onHover { hover = $0 }
                    .offset(x: -Self.zoneLeading)
            }
            .fixedSize()
            .zIndex(1)
            .onDisappear { hover = false }
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

/// The row under the field: the model and thinking pickers, in the bar the profile's week, then the send (or stop) key.
struct QCControls: View {
    @ObservedObject var model: QuickChatModel
    var inBar: Bool

    /// The row on one line, whatever the width (ViewThatFits, richest first): the bar's week meter drops its number,
    /// then the model shows its family only ("Opus") and thinking says "Off" for "Thinking off", then the meter goes,
    /// then the profile key keeps just its dot.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(level: 2, wide: true, profileWords: true)
            row(level: 1, wide: true, profileWords: true)
            row(level: 1, wide: false, profileWords: true)
            row(level: 0, wide: false, profileWords: true)
            row(level: 0, wide: false, profileWords: false)
        }
    }

    /// `level`: the bar's week meter with its number (2), the meter alone (1), none (0).
    private func row(level showLevel: Int, wide: Bool, profileWords: Bool) -> some View {
        HStack(spacing: 2) {
            if let t = model.target {
                QCChip(title: profileWords ? t.name : "", dot: QuickChatLevel.color(model.blocked ? 100 : model.level?.weekNow()),
                       help: "Profile: \(t.name). For this chat; a new chat starts on the default.") { pickProfile() }
            }
            QCChip(title: wide ? model.modelTitle : model.resolvedModel.family.title,
                   help: "Model. For this chat; a new chat starts on the default in Settings.") { pickModel() }
            QCChip(title: model.effectiveThinking == .off ? (wide ? "Thinking off" : "Off") : model.effectiveThinking.title,
                   help: "Thinking: \(model.effectiveThinking == .off ? "off" : model.effectiveThinking.title.lowercased()). For this chat; a new chat starts on the default in Settings.") { pickThinking() }
            Spacer(minLength: 4)
            if inBar, showLevel > 0, let l = model.level, l.weekNow() != nil || l.full() != nil {
                QCLevelView(level: l, number: showLevel == 2).padding(.trailing, 8)
            }
            if model.busy {
                Button(action: model.stop) {
                    Image(systemName: "stop.fill").font(.system(size: 10, weight: .bold))
                        .frame(width: QCSpace.row, height: QCSpace.row).foregroundColor(QCColor.bubble)
                        .background(Circle().fill(QCColor.text))
                }
                .buttonStyle(.plain).help("Stop")
            } else {
                let empty = model.field.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.blocked
                Button(action: model.send) {
                    Image(systemName: "arrow.up").font(.system(size: 13, weight: .semibold))
                        .frame(width: QCSpace.row, height: QCSpace.row)
                        .foregroundColor(empty ? QCColor.text.opacity(0.38) : .white)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(empty ? QCColor.text.opacity(0.1) : QCColor.send))
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

    /// The model's menu: the families the account has, each with Claude Code's few words for it.
    private func pickModel() {
        let now = model.resolvedModel.family
        // a list with none of the four families (only "default", or models of other names): the one family asked for
        let choices = model.modelChoices.isEmpty ? [(choice: now, title: now.title, detail: now.blurb)] : model.modelChoices
        QCMenu.pop(QCMenu.build(header: "Model", items: choices.map { m in
            QCMenu.Item(title: m.title, detail: m.detail, on: m.choice == now) { model.choose(m.choice) }
        }, actions: []))
    }

    /// Thinking's menu: Off, then the steps the model takes.
    private func pickThinking() {
        QCMenu.pop(QCMenu.build(header: "Thinking", items: model.thinkingSteps.map { t in
            QCMenu.Item(title: t.title, detail: t.blurb, on: t == model.effectiveThinking) { model.choose(t) }
        }, actions: []))
    }
}

/// The profile picker's key: a dot, its title and a chevron; it opens a menu.
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
                if !title.isEmpty { Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1) }
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).opacity(0.7)
            }
            .foregroundColor(hover ? QCColor.text : QCColor.soft)
            .padding(.horizontal, QCSpace.keyPadding).frame(height: QCSpace.row)
            .background(RoundedRectangle(cornerRadius: QCSpace.keyCorner, style: .continuous).fill(hover ? QCColor.hover : .clear))
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
            Item(title: p.name, detail: weekWords(l), dot: NSColor(QuickChatLevel.color(l?.full() != nil ? 100 : l?.weekNow())),
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
                        onSubmit: { model.send() }, onEscape: { model.hide() }, onCaps: { caps = $0 })
                .frame(minHeight: height, maxHeight: grows ? .infinity : height)
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
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.borderType = .noBorder
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

final class QCTextView: NSTextView {
    var placeholder: NSAttributedString? { didSet { needsDisplay = true } }
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
        // Claude Code's list as an account with all four families gives it
        let efforts = ["low", "medium", "high", "xhigh", "max"]
        let list: [QuickChatModelEntry] = [
            .init(value: "claude-haiku-5-5", displayName: "Haiku 5.5", efforts: ["low", "medium", "high"]),
            .init(value: "claude-sonnet-5-5", displayName: "Sonnet 5.5", efforts: Array(efforts.prefix(4))),
            .init(value: "claude-opus-5-5", displayName: "Opus 5.5", efforts: efforts),
            .init(value: "claude-fable-5-2", displayName: "Fable 5.2", efforts: efforts),
        ]
        ModelCatalog.shared.set(list, profile: target.profileID, account: target.accountUUID)
        var level = QuickChatLevel()
        level.week = 62; level.weekResets = Date().addingTimeInterval(3 * 86400)
        m.level = level
        let q1 = "How do I find which process is using port 3000 on macOS?"
        let a1 = "Use `lsof`:\n```zsh\nlsof -nP -iTCP:3000 -sTCP:LISTEN\n```\nThe **PID** column is the process. Stop it with `kill <PID>`.\n- `-nP` keeps addresses and ports as numbers, which is faster.\n- `-sTCP:LISTEN` shows only the server, not its clients."
        var t1 = QuickChatTurn(question: q1, answer: a1, model: "Haiku 5.5"); t1.phase = .done; t1.seconds = 2.4
        switch state {
        case "typing": m.field = q1
        case "notinstalled": m.field = q1; m.barProblem = .notInstalled
        case "streaming": var t = t1; t.answer = String(a1.prefix(90)); t.phase = .streaming; m.turns = [t]
        case "answer": m.turns = [t1]
        case "failed": var t = t1; t.answer = String(a1.prefix(60)); t.phase = .failed
            t.problem = .stopped(detail: "claude exited with code 1: API Error: Connection error."); m.turns = [t]
        case "notsigned": var t = QuickChatTurn(question: q1); t.phase = .failed; t.problem = .notSignedIn(profile: "Main", id: "main"); m.turns = [t]
        case "thinking", "short":
            var t2 = QuickChatTurn(question: "And only the PID, for a script?",
                                   answer: "Add `-t`, which prints bare PIDs:\n```zsh\nkill $(lsof -t -iTCP:3000 -sTCP:LISTEN)\n```",
                                   thinking: "They want only the PIDs.", model: "Sonnet 5.5", thinkingTitle: "High")
            t2.phase = .done; t2.seconds = 7.8; t2.thinkingSeconds = 5
            m.choice = .sonnet; m.knownModels[.sonnet] = "Sonnet 5.5"; m.thinking = .high; m.turns = [t1, t2]
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
            if state == "switching" { m.switchNotice = .waiting(wanted: "ultra-2@example.com") }
            if state == "wrong" { m.switchNotice = .wrong(signedIn: "ultra-3@example.com", wanted: "ultra-2@example.com") }
            if state == "timedout" { m.switchNotice = .timedOut(wanted: "ultra-2@example.com") }
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
        // meters: their card, the address still blurred) or -hover-address (the pointer on the address capsule)
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
            ?? (state == "short" ? QuickChatRoot.minWindowHeight : QuickChatRoot.windowHeight)
        let view = QuickChatRoot(model: m).environment(\.qcRendering, true)
            .frame(width: width, height: m.isWindow ? height : state == "bar-tall" ? 170 : nil)
            .padding(30).background(Color(white: 0.1))
        let r = ImageRenderer(content: view)
        r.scale = 2
        if let tiff = r.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
    }
}
