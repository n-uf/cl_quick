// QuickChatViews: the quick chat's bar and chat window (QuickChat.swift), in Claude's own dark colours rather than
// cl_audit's front panel: it should feel like Claude. The bar is a field over one row of keys; the first message turns it
// into a chat window: the account line on top, the chat, and the field at the bottom. Answers are Markdown in a serif,
// code blocks have Copy, and each answer says which model gave it.

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
/// the hosting view reports as its intrinsic height: QuickChat.fit). Around the visible card is a transparent margin the
/// system's resize zones are in (the frame's outer 3 pt on the edges, 9 pt at the corners), so they take nothing from what
/// is inside the card: a drag that starts on the card is always a move.
struct QuickChatRoot: View {
    static let width: CGFloat = 520            // the first width of the card
    static let windowHeight: CGFloat = 580     // the chat's first height
    static let minWidth: CGFloat = 320         // the key row fits on one line from here (QCControls drops the week, then words)
    static let minWindowHeight: CGFloat = 220  // header, a line of chat and the field at one line; a taller field asks for more
    static let margin: CGFloat = 4             // the thin transparent margin around the card: where the system's resize zones are
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
        VStack(alignment: .leading, spacing: 12) {
            if let p = model.barProblem { QCProblemView(problem: p, model: model, answered: false) }
            else if model.switchNotice != nil { QCSwitchView(model: model) }
            else if model.blocked { QCProblemView(problem: .limitFull, model: model, answered: false) }
            if let note = model.accountNote { QCNote(text: note).padding(.horizontal, 8) }
            QCField(model: model, placeholder: "Ask anything", size: 17, grows: true)
                .padding(.horizontal, 8)
            QCControls(model: model, inBar: true)
        }
        .padding(EdgeInsets(top: 16, leading: 10, bottom: 10, trailing: 10))
        .frame(maxHeight: .infinity, alignment: .top)       // a bar dragged taller gives the height to the field
        .qcDraggable()
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(QCColor.surface.opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(QCColor.line))
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
                    .overlay(VStack(alignment: .leading, spacing: 0) { turns }.padding(.horizontal, 20).padding(.bottom, 12),
                             alignment: .bottom)
                    .clipped()
            } else {
                // the chat is at least as tall as the scroll view, so the empty space below a short one drags too
                GeometryReader { geo in
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                turns
                                Color.clear.frame(height: 1).id("end")
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)
                            .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .topLeading)
                            .qcDraggable()
                        }
                        .onChange(of: model.scrollTick) { _ in proxy.scrollTo("end", anchor: .bottom) }
                        .onAppear { proxy.scrollTo("end", anchor: .bottom) }
                    }
                }
                .frame(minHeight: 44)         // a line of chat stays, whatever the window
            }
            VStack(alignment: .leading, spacing: 8) {
                QCField(model: model, placeholder: "Reply…", size: 15).padding(.horizontal, 8)
                QCControls(model: model, inBar: false)
            }
            .padding(EdgeInsets(top: 12, leading: 8, bottom: 8, trailing: 8))
            .qcDraggable()
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(QCColor.surface))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(QCColor.line))
            .padding([.horizontal, .bottom], 12)
        }
        .frame(maxHeight: .infinity)
        .qcDraggable()
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(QCColor.window.opacity(0.98)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(QCColor.line))
    }

    @ViewBuilder private var turns: some View {
        if let note = model.accountNote { QCNote(text: note).padding(.top, 14) }
        ForEach(Array(model.turns.enumerated()), id: \.element.id) { i, t in
            QCTurnView(turn: t, last: i == model.turns.count - 1, model: model)
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
    @State private var hover = false
    @State private var nameHover = false
    @State private var line = QCLineState()
    @Environment(\.qcHover) private var pictureHover

    var body: some View {
        let on = hover || pictureHover
        HStack(spacing: 8) {
            QCHeaderInfo(target: model.target, level: model.level, openProfile: {
                // Settings opens and the chat steps aside (hidden, not closed: the shortcut brings it back as it was)
                if let id = model.target?.profileID { model.openSettings(id); model.hide() }
            }, nameHover: $nameHover, reveal: on, state: $line)
            Spacer(minLength: 8)
            // a tight pair, each a 24 pt target
            HStack(spacing: 0) {
                QCIconButton(symbol: "square.and.pencil", help: "New chat", width: 24) { model.newChat() }
                QCIconButton(symbol: "xmark", help: "Hide (Esc)", width: 24) { model.hide() }
            }
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 6, trailing: 13))
        .qcDraggable(hover: $hover)       // the pointer anywhere on the line: hover, without taking the mouse from the drag
        .overlay(alignment: .topLeading) {
            // the line can't hold everything: on hover, a card under it does
            let email = line.addressComplete ? nil : model.target?.email
            let meters = (!line.metersComplete ? model.level : nil).flatMap { QCHeaderLine.hasMeters($0) ? $0 : nil }
            if on, email != nil || meters != nil {
                QCHeaderCard(email: email, level: meters).offset(x: 12, y: 46).allowsHitTesting(false)
            }
        }
    }
}

/// What the header line left out, under the header: the whole address and/or the meters (session and week, each with its
/// share and when it resets).
struct QCHeaderCard: View {
    let email: String?
    let level: QuickChatLevel?

    var body: some View {
        let full = level?.full()
        let all = QCHeaderDetail.steps[0]
        VStack(alignment: .leading, spacing: 7) {
            if let email { Text(email).font(.system(size: 12)).foregroundColor(QCColor.soft).lineLimit(1) }
            if let level {
                QCLevelGroup(label: "session", short: "5h", p: level.fiveHourNow(), full: full?.id == "5h" ? full : nil, resets: level.fiveHourResets, detail: all)
                QCLevelGroup(label: "week", short: "wk", p: level.weekNow(), full: full?.id == "wk" ? full : nil, resets: level.weekResets, detail: all)
            }
        }
        .fixedSize()
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(QCColor.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(QCColor.line))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
    }
}

/// Set while drawing a picture: the header as if the pointer were over it.
private struct QCHoverKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var qcHover: Bool {
        get { self[QCHoverKey.self] }
        set { self[QCHoverKey.self] = newValue }
    }
}

/// How much of the header's account line is drawn. Never an ellipsis: the line takes the first step that fits the width it
/// has (ViewThatFits: measured, no fixed thresholds), richest first, so the numbers show whenever there is room for them.
/// As the window narrows it drops parts in this order:
///   1. "resets Sun 13:00" loses its word: "Sun 13:00";
///   2. the reset times go;
///   3. both labels shorten together: "session" / "week" become "5h" / "wk";
///   4. the percentages go (bars only; "full" stays), labels first full again, then short;
///   5. the labels go, both;
///   6. the address smudge is cut to a short one;
///   7. the address goes (and a profile name too long for the window on its own is cut: the only ellipsis).
/// The address is drawn at its own width (`natural`) only where the line has room to spare after the numbers: at each of
/// the first levels the natural width comes before the capped one (96 pt), so the numbers win over the address's width.
/// The address keeps its width on hover; it un-blurs there. While the pointer is on the header, a card under it shows
/// what the line couldn't: the whole address, and both meters with percentage and reset time (the tooltip has the
/// meters as words).
struct QCHeaderDetail: Equatable {
    enum Resets { case words, time, none }
    enum Labels { case full, short, none }
    enum Address { case natural, capped, short, none }
    var resets: Resets
    var pct: Bool
    var labels: Labels
    var address: Address = .capped

    /// All the meters say: the reset times are there (the word "resets" or not).
    var showsMeters: Bool { resets != .none }

    static let steps: [QCHeaderDetail] = [
        .init(resets: .words, pct: true, labels: .full, address: .natural),
        .init(resets: .words, pct: true, labels: .full),
        .init(resets: .time, pct: true, labels: .full, address: .natural),
        .init(resets: .time, pct: true, labels: .full),
        .init(resets: .none, pct: true, labels: .full, address: .natural),
        .init(resets: .none, pct: true, labels: .full),
        .init(resets: .none, pct: true, labels: .short),
        .init(resets: .none, pct: false, labels: .full),
        .init(resets: .none, pct: false, labels: .short),
        .init(resets: .none, pct: false, labels: .none),
        .init(resets: .none, pct: false, labels: .none, address: .short),
        .init(resets: .none, pct: false, labels: .none, address: .none),
    ]
}

/// What the line on screen leaves out (told by the step that is shown), so the hover card adds exactly that.
struct QCLineState: Equatable {
    var metersComplete = true
    var addressComplete = true
}

/// The profile, its address (smudged) and the session and week meters.
struct QCHeaderInfo: View {
    let target: QuickChatTarget?
    let level: QuickChatLevel?
    /// The profile's name was clicked.
    let openProfile: () -> Void
    @Binding var nameHover: Bool
    /// The pointer is on the header: the address is un-blurred.
    let reveal: Bool
    /// What the line on screen leaves out: told by the step that is shown.
    @Binding var state: QCLineState

    var body: some View {
        let steps = QCHeaderDetail.steps
        ViewThatFits(in: .horizontal) {
            ForEach(steps.indices, id: \.self) { i in
                QCHeaderLine(target: target, level: level, detail: steps[i], openProfile: openProfile, nameHover: $nameHover, reveal: reveal)
                    .fixedSize()
                    .onAppear { state = QCLineState(metersComplete: steps[i].showsMeters, addressComplete: steps[i].address == .natural) }
            }
            // a profile name too long for the window even on its own: the one case with an ellipsis, so the line never
            // pushes the buttons off the panel
            QCHeaderLine(target: target, level: level, detail: steps[steps.count - 1], openProfile: openProfile, nameHover: $nameHover,
                         reveal: reveal, flexible: true)
                .onAppear { state = QCLineState(metersComplete: false, addressComplete: false) }
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
    let reveal: Bool
    /// The name may give way (be cut) to what the window has room for.
    var flexible = false

    var body: some View {
        HStack(spacing: 8) {
            if let t = target {
                QCProfileName(name: t.name, hover: $nameHover, action: openProfile).layoutPriority(flexible ? -1 : 0)
                // a plain label: a drag that starts on it moves the panel
                if detail.address != .none, let e = t.email { QCBlurred(text: e, mode: detail.address, reveal: reveal).allowsHitTesting(false) }
            }
            if let l = level {
                let full = l.full()
                HStack(spacing: 12) {
                    QCLevelGroup(label: "session", short: "5h", p: l.fiveHourNow(), full: full?.id == "5h" ? full : nil,
                                 resets: l.fiveHourResets, detail: detail)
                    QCLevelGroup(label: "week", short: "wk", p: l.weekNow(), full: full?.id == "wk" ? full : nil,
                                 resets: l.weekResets, detail: detail)
                }
                .padding(.leading, 4)
                .help(Self.tooltip(l))        // the meters take the pointer (a tooltip needs it); the labels leave it to the drag
            }
        }
    }

    /// Whether there is any meter to show.
    static func hasMeters(_ l: QuickChatLevel) -> Bool {
        l.full() != nil || l.fiveHourNow() != nil || l.weekNow() != nil
    }

    /// The same numbers as words, for the tooltip and VoiceOver: both windows with their share and reset.
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
            Text(name).font(.system(size: 12.5, weight: .semibold)).foregroundColor(QCColor.text).lineLimit(1)
                .padding(.horizontal, 6).padding(.vertical, 3)
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

/// The address as a smudge: the real text, cut to at most 96 pt (48 when `short`) and blurred.
struct QCBlurred: View {
    let text: String
    var mode: QCHeaderDetail.Address = .capped
    /// The pointer is on the header: the blur fades out (and back in when it leaves).
    var reveal = false

    var body: some View {
        Text(text).font(.system(size: 12)).foregroundColor(QCColor.soft).lineLimit(1).fixedSize()
            .frame(minWidth: 0, maxWidth: mode == .natural ? .infinity : mode == .short ? 48 : 96, alignment: .leading).clipped()
            .padding(.horizontal, 4)
            .blur(radius: reveal ? 0 : 4.5)
            .animation(.easeOut(duration: 0.18), value: reveal)
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
            let share = full != nil ? 100 : p
            let color = QuickChatLevel.color(share)
            let when = (full?.resets ?? resets)
            HStack(spacing: 5) {
                if detail.labels != .none {
                    Text(detail.labels == .full ? label : short).font(.system(size: 12)).foregroundColor(QCColor.muted).lineLimit(1)
                }
                ZStack(alignment: .leading) {
                    Capsule().fill(QCColor.text.opacity(0.13))
                    Capsule().fill(color).frame(width: 38 * CGFloat(min(100, share ?? 0)) / 100)
                }
                .frame(width: 38, height: 4)
                if full != nil || detail.pct {
                    Text(full != nil ? "full" : QuickChatLevel.pct(share))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundColor(color).lineLimit(1)
                }
                if let when, detail.resets != .none {
                    Text(detail.resets == .words ? "resets \(TimeWords.when(when))" : TimeWords.when(when))
                        .font(.system(size: 12)).foregroundColor(QCColor.muted).lineLimit(1)
                }
            }
        }
    }
}

// MARK: - One question and its answer

struct QCTurnView: View {
    let turn: QuickChatTurn
    let last: Bool
    @ObservedObject var model: QuickChatModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer(minLength: 70)
                Text(turn.question)
                    .font(.system(size: 14.5))
                    .foregroundColor(QCColor.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(QCColor.bubble))
            }
            .padding(.top, 14)
            if turn.thinkingTitle != nil { QCThought(turn: turn) }
            if !turn.answer.isEmpty {
                QCAnswer(text: turn.answer).equatable()
            }
            if turn.phase == .waiting || turn.phase == .streaming { QCPulse() }
            if turn.phase == .done || turn.phase == .stopped { footer }
            if let p = turn.problem, turn.phase == .failed {
                QCProblemView(problem: p, model: model, answered: !turn.answer.isEmpty, last: last)
            }
        }
        .padding(.bottom, 4)
    }

    private var footer: some View {
        HStack(spacing: 2) {
            QCCopyIcon(text: turn.answer)
            if last { QCIconButton(symbol: "arrow.clockwise", help: "Ask again", small: true) { model.again() } }
            Text(words).font(.system(size: 12)).foregroundColor(QCColor.muted).padding(.leading, 6)
        }
        .padding(.leading, -7)
    }

    private var words: String {
        let who = turn.model.isEmpty ? "Claude" : turn.model
        if turn.phase == .stopped { return "\(who) · stopped by you" }
        var s = "answered by \(who)"
        if let th = turn.thinkingTitle { s += ", thinking \(th.lowercased())" }
        if let sec = turn.seconds { s += " · " + QCFormat.seconds(sec) }
        return s
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
                .font(.system(size: 13)).foregroundColor(QCColor.muted)
            }
            .buttonStyle(.plain)
            .disabled(turn.thinking.isEmpty)
            if open, !turn.thinking.isEmpty {
                Text(turn.thinking).font(.system(size: 13)).foregroundColor(QCColor.muted).lineSpacing(2)
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
            Text(Self.inline(s)).font(.system(size: level <= 2 ? 17 : 15.5, weight: .semibold, design: .serif))
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
                        Text("\(start + i).").font(.system(size: 15, design: .serif)).foregroundColor(QCColor.muted)
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

    private func prose(_ s: String) -> some View {
        Text(Self.inline(s))
            .font(.system(size: 15.5, design: .serif))
            .foregroundColor(QCColor.text)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    /// Inline Markdown, with `code` in the mono font and a warm colour.
    static func inline(_ s: String) -> AttributedString {
        var a = QuickChatMarkdown.inline(s)
        for run in a.runs where run.inlinePresentationIntent?.contains(.code) == true {
            a[run.range].font = .system(size: 13.5, design: .monospaced)
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
            HStack {
                Text(language.isEmpty ? "code" : language).font(.system(size: 12)).foregroundColor(QCColor.muted)
                Spacer()
                QCCopyLabel(text: code)
            }
            .padding(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 4))
            Rectangle().fill(QCColor.line).frame(height: 1)
            if rendering {        // a picture can't draw a scroll view
                codeText.frame(maxWidth: .infinity, alignment: .leading).clipped()
            } else {
                ScrollView(.horizontal, showsIndicators: false) { codeText }
            }
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(QCColor.code))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(QCColor.line))
    }

    private var codeText: some View {
        Text(code)
            .font(.system(size: 12.5, design: .monospaced))
            .foregroundColor(QCColor.codeText)
            .textSelection(.enabled)
            .fixedSize()
            .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
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

    /// The row on one line, whatever the width (ViewThatFits, richest first): the bar's week meter goes first, then the
    /// thinking key keeps just its bulb (lit while thinking is on), then the profile key keeps just its dot.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(level: true, thinkingWords: true, profileWords: true)
            row(level: false, thinkingWords: true, profileWords: true)
            row(level: false, thinkingWords: false, profileWords: true)
            row(level: false, thinkingWords: false, profileWords: false)
        }
    }

    private func row(level showLevel: Bool, thinkingWords: Bool, profileWords: Bool) -> some View {
        HStack(spacing: 4) {
            if let t = model.target {
                QCChip(title: profileWords ? t.name : "", dot: QuickChatLevel.color(model.blocked ? 100 : model.level?.weekNow()), help: "Profile: \(t.name)") { pickProfile() }
            }
            QCChip(title: model.modelTitle, help: "Model") { pickModel() }
            QCChip(title: thinkingWords ? (model.effectiveThinking == .off ? "Thinking off" : model.effectiveThinking.title) : "", symbol: "lightbulb",
                   lit: model.effectiveThinking != .off,
                   help: model.effectiveThinking == .off ? "Thinking off" : "Thinking \(model.effectiveThinking.title.lowercased())") { pickThinking() }
            Spacer(minLength: 4)
            if inBar, showLevel, let l = model.level, l.weekNow() != nil || l.full() != nil {
                QCLevelView(level: l).padding(.horizontal, 6)
            }
            if model.busy {
                Button(action: model.stop) {
                    Image(systemName: "stop.fill").font(.system(size: 11, weight: .bold))
                        .frame(width: 34, height: 34).foregroundColor(QCColor.bubble)
                        .background(Circle().fill(QCColor.text))
                }
                .buttonStyle(.plain).help("Stop")
            } else {
                let empty = model.field.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.blocked
                Button(action: model.send) {
                    Image(systemName: "arrow.up").font(.system(size: 14, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .foregroundColor(empty ? QCColor.text.opacity(0.38) : .white)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(empty ? QCColor.text.opacity(0.1) : QCColor.send))
                }
                .buttonStyle(.plain).disabled(empty).help("Send (Return)")
            }
        }
    }

    private func pickProfile() {
        let list = model.pickable()
        QCMenu.pop(header: "Profile", items: list.map { p, l in
            let f = l?.full()
            let words = f != nil ? "full" : l?.weekNow().map { "week \(Int($0.rounded()))%" } ?? "no numbers yet"
            return QCMenu.Item(title: p.name, detail: words, on: p.id == model.target?.profileID) { model.pickProfile(p.id) }
        }, footer: "Weeks as last reported. A new chat goes back to the default. Add or change profiles in Settings.")
    }

    private func pickModel() {
        QCMenu.pop(header: "Model", items: model.modelChoices.map { m in
            QCMenu.Item(title: m.title, detail: m.detail, on: m.choice == model.resolvedModel.family) { model.choose(m.choice) }
        }, footer: "For this chat. New chat goes back to the default in Settings.")
    }

    private func pickThinking() {
        QCMenu.pop(header: "Thinking", items: model.thinkingSteps.map { t in
            QCMenu.Item(title: t.title, detail: t.blurb, on: t == model.effectiveThinking) { model.choose(t) }
        }, footer: "For this chat. New chat goes back to the default in Settings.")
    }
}

/// A picker's key: its title and a chevron; it opens a menu.
struct QCChip: View {
    let title: String
    var symbol: String? = nil
    var lit = false
    /// A small dot before the title (the profile's level colour).
    var dot: Color? = nil
    var help = ""
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
                if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .medium)).foregroundColor(lit ? QCColor.accent : QCColor.soft) }
                if !title.isEmpty { Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1) }
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).opacity(0.7)
            }
            .foregroundColor(hover ? QCColor.text : QCColor.soft)
            .padding(.horizontal, 9).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(hover ? QCColor.hover : .clear))
        }
        .buttonStyle(.plain).help(help).onHover { hover = $0 }
    }
}

/// The pickers' menus: macOS's own, at the pointer; each item its name and a few words in grey.
enum QCMenu {
    struct Item {
        let title: String
        let detail: String
        let on: Bool
        let action: () -> Void
    }

    private final class Handler: NSObject {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
        @objc func fire() { run() }
    }

    static func pop(header: String, items: [Item], footer: String) {
        let m = NSMenu(); m.autoenablesItems = false
        let h = NSMenuItem(title: header, action: nil, keyEquivalent: ""); h.isEnabled = false
        m.addItem(h)
        for it in items {
            let handler = Handler(it.action)
            let i = NSMenuItem(title: it.title, action: #selector(Handler.fire), keyEquivalent: "")
            i.target = handler
            i.representedObject = handler      // the menu item keeps its handler alive
            i.state = it.on ? .on : .off
            let s = NSMutableAttributedString(string: it.title, attributes: [.font: NSFont.menuFont(ofSize: 0)])
            s.append(NSAttributedString(string: "   " + it.detail, attributes: [
                .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.secondaryLabelColor]))
            i.attributedTitle = s
            m.addItem(i)
        }
        m.addItem(.separator())
        let f = NSMenuItem(title: footer, action: nil, keyEquivalent: ""); f.isEnabled = false
        m.addItem(f)
        m.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
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
    var small = false
    /// A narrower target than the default 28 or 30 pt.
    var width: CGFloat? = nil
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: small ? 12 : 13, weight: .medium))
                .frame(width: width ?? (small ? 28 : 30), height: small ? 28 : 30)
                .foregroundColor(hover ? QCColor.text : QCColor.muted)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hover ? QCColor.hover : .clear))
        }
        .buttonStyle(.plain).help(help).onHover { hover = $0 }
    }
}

/// Copy under an answer: its icon turns into a tick for a moment.
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

/// Copy in a code block's header: "Copy", then "Copied" for a moment.
struct QCCopyLabel: View {
    let text: String
    @State private var done = false
    var body: some View {
        Button {
            QCCopy.put(text); done = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { done = false }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: done ? "checkmark" : "doc.on.doc").font(.system(size: 11))
                Text(done ? "Copied" : "Copy").font(.system(size: 12))
            }
            .foregroundColor(QCColor.muted).padding(.horizontal, 8).frame(height: 26)
        }
        .buttonStyle(.plain)
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
        let m = QuickChatModel()
        var target = QuickChatTarget(Profile(id: "main", name: "Main", folder: "~/.claude-sample"))
        target.email = "ultra-1@example.com"
        m.target = target
        m.knownModels[.haiku] = "Haiku 5.5"
        // Claude Code's list as an account with all four families gives it (models3: no Fable; models2: Haiku and Sonnet)
        let efforts = ["low", "medium", "high", "xhigh", "max"]
        var list: [QuickChatModelEntry] = [
            .init(value: "claude-haiku-5-5", displayName: "Haiku 5.5", efforts: ["low", "medium", "high"]),
            .init(value: "claude-sonnet-5-5", displayName: "Sonnet 5.5", efforts: Array(efforts.prefix(4))),
            .init(value: "claude-opus-5-5", displayName: "Opus 5.5", efforts: efforts),
            .init(value: "claude-fable-5-2", displayName: "Fable 5.2", efforts: efforts),
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
        switch state {
        case "typing": m.field = q1
        case "notinstalled": m.field = q1; m.barProblem = .notInstalled
        case "streaming": var t = t1; t.answer = String(a1.prefix(90)); t.phase = .streaming; m.turns = [t]
        case "answer": m.turns = [t1]
        case "failed": var t = t1; t.answer = String(a1.prefix(60)); t.phase = .failed
            t.problem = .stopped(detail: "claude exited with code 1: API Error: Connection error."); m.turns = [t]
        case "notsigned": var t = QuickChatTurn(question: q1); t.phase = .failed; t.problem = .notSignedIn(profile: "Main", id: "main"); m.turns = [t]
        case "thinking", "short", "tint-fable", "tint-extra", "tint-max", "tint-fablemax", "models3", "models2",
             "hover-model-up", "hover-model-down", "hover-thinking-up", "hover-thinking-down", "hover-max-down":
            var t2 = QuickChatTurn(question: "And only the PID, for a script?",
                                   answer: "Add `-t`, which prints bare PIDs:\n```zsh\nkill $(lsof -t -iTCP:3000 -sTCP:LISTEN)\n```",
                                   thinking: "They want only the PIDs.", model: "Sonnet 5.5", thinkingTitle: "High")
            t2.phase = .done; t2.seconds = 7.8; t2.thinkingSeconds = 5
            m.choice = .sonnet; m.knownModels[.sonnet] = "Sonnet 5.5"; m.thinking = .high; m.turns = [t1, t2]
            // the step controls: which family and thinking step each picture shows
            switch state {
            case "tint-fable": m.choice = .fable; m.thinking = .high
            case "tint-extra", "models3": m.choice = .opus; m.thinking = .xhigh
            case "tint-max", "hover-max-down": m.choice = .opus; m.thinking = .max
            case "tint-fablemax": m.choice = .fable; m.thinking = .max
            case "models2": m.choice = .haiku; m.thinking = .off
            case "hover-model-up", "hover-model-down", "hover-thinking-up", "hover-thinking-down": m.choice = .opus; m.thinking = .high
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
        // reported), header-long (a long profile name and address), each also with -hover (the pointer on it)
        if state.hasPrefix("header") {
            var l = QuickChatLevel()
            l.week = 58; l.weekResets = Date().addingTimeInterval(3 * 86400)
            if !state.contains("nosession") { l.fiveHour = 41; l.fiveHourResets = Date().addingTimeInterval(2 * 3600 + 600) }
            if state.contains("full") { l.week = 100; l.weekResets = Date().addingTimeInterval(26 * 3600) }
            m.level = l
            if state.contains("long") {
                target.name = state.contains("verylong") ? "Work – client project, EU team" : "Personal-work"
                target.email = "long.address.name@example.com"; m.target = target
            }
            let width = ProcessInfo.processInfo.environment["QC_RENDER_WIDTH"].flatMap { Double($0) }.map { CGFloat($0) } ?? QuickChatRoot.width
            let header = QCHeader(model: m).environment(\.qcRendering, true).environment(\.qcHover, state.contains("hover") && !state.contains("namehover"))
                .environment(\.qcNameHover, state.contains("namehover"))
                .frame(width: width).background(QCColor.window).padding(.bottom, 80)       // room for the hover card under it
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
