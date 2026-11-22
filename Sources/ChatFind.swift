// ChatFind: ⌘F, find in the open chat. A small bar over the top of the answers (a search field, "n of m", ▲ ▼, ✕) searches every
// message and answer of the chat, case-insensitively and as you type, highlights each match in place (a soft background, the
// current one stronger) and scrolls to the current one. Nothing is kept: the bar's text and the matches live in memory only, and
// close with the bar (Esc, ✕, ⌘W, a new chat).
//
// WHAT IS SEARCHED is what is drawn: the text of each Markdown block as the chat shows it (bold, links and `code` without their
// marks), the cells of a table, the lines of a code block and the user's own messages. NOT searched: the thinking text a click
// opens, the notes, the footers' words and the code of an html block whose page shows by default. A wide code block or
// table that scrolls sideways is brought into view up and down only, never along.
//
// HOW IT FITS THE VIEWS: every text the chat draws as a separate Text is a SEGMENT, named by (block, sub): block -1 is the user's
// message, block n the answer's n-th Markdown block, sub the item of a list or the cell of a table (header cells first, then the
// rows, row by row). QCFindEngine lists the segments of a turn from the same blocks the answer draws; the matches are character
// offsets in a segment's displayed text. A turn's QCFindMarks carries those offsets down to the views (a value, so an answer that
// is done and has no match is never drawn again), which paint them into the AttributedString they draw.

import AppKit
import SwiftUI

/// One piece of text in a turn: the message (block -1) or the sub-th text of an answer's block.
struct QCSegKey: Hashable { var block: Int; var sub: Int }

/// A match inside one segment, in Characters of the displayed text (utf16: where it starts for the text's own line lookup).
struct QCFindHit: Equatable { var start: Int; var length: Int; var utf16: Int }

/// What the view paints: a match, and whether it is the current one.
struct QCFindRange: Equatable { var start: Int; var length: Int; var current: Bool }

/// The current match is in this segment: it scrolls it into view once per token.
struct QCFindReveal: Equatable { var key: QCSegKey; var utf16: Int; var token: Int }

/// A turn's matches, as its views read them.
struct QCFindMarks: Equatable {
    var ranges: [QCSegKey: [QCFindRange]] = [:]
    var reveal: QCFindReveal? = nil

    func ranges(_ block: Int, _ sub: Int) -> [QCFindRange] { ranges[QCSegKey(block: block, sub: sub)] ?? [] }

    /// The reveal, for the segment that holds the current match (else nil).
    func reveal(_ block: Int, _ sub: Int) -> QCFindReveal? {
        guard let r = reveal, r.key == QCSegKey(block: block, sub: sub) else { return nil }
        return r
    }

    /// The utf16 length of a segment's text, for the segment that holds the current match (0 for the others: not worked out).
    func length(_ text: AttributedString, _ block: Int, _ sub: Int) -> Int {
        reveal(block, sub) == nil ? 0 : (String(text.characters) as NSString).length
    }

    /// The segment's text with its matches painted: a soft background, a stronger one (and dark text) for the current match.
    func highlighted(_ text: AttributedString, _ block: Int, _ sub: Int) -> AttributedString {
        let rs = ranges(block, sub)
        guard !rs.isEmpty else { return text }
        var a = text
        let n = a.characters.count
        for r in rs where r.start >= 0 && r.length > 0 && r.start + r.length <= n {
            let s = a.characters.index(a.characters.startIndex, offsetBy: r.start)
            let e = a.characters.index(s, offsetBy: r.length)
            a[s..<e].backgroundColor = r.current ? QCFindColor.current : QCFindColor.match
            if r.current { a[s..<e].foregroundColor = QCColor.bubble }
        }
        return a
    }
}

enum QCFindColor {
    static let match = QCColor.accent.opacity(0.30)
    static let current = QCColor.hex(0xE8A27F)
}

/// The text of each segment of a turn, and the matches in it.
enum QCFindEngine {
    /// What a turn draws as texts, in reading order: the message, then the answer's blocks.
    static func segments(question: String, answer: String) -> [(key: QCSegKey, text: String)] {
        var out: [(key: QCSegKey, text: String)] = []
        func add(_ block: Int, _ sub: Int, _ text: String) { out.append((QCSegKey(block: block, sub: sub), text)) }
        func plain(_ s: String) -> String { String(QCAnswer.inline(s).characters) }
        if !question.isEmpty { add(-1, 0, question) }
        for (i, b) in QuickChatMarkdown.blocks(answer).enumerated() {
            switch b {
            case .paragraph(let s), .quote(let s): add(i, 0, plain(s))
            case .heading(_, let s): add(i, 0, plain(s))
            case .bullets(let items), .numbered(_, let items):
                for (j, it) in items.enumerated() { add(i, j, plain(it)) }
            case .code(let lang, let code, let meta, let closed):
                // an html block whose page shows by default is not searched: its code is not on screen, so n of m counts what is seen
                if QCHTMLPreview.isHTML(lang), closed, !QCHTMLPreview.codeFirst(meta) { break }
                add(i, 0, code)
            case .rule: break
            case .table(let header, _, let rows):
                let n = header.count
                for (c, s) in header.enumerated() where !s.isEmpty { add(i, c, plain(s)) }
                for (r, row) in rows.enumerated() {
                    for (c, s) in row.enumerated() where !s.isEmpty { add(i, n + r * n + c, plain(s)) }
                }
            }
        }
        return out
    }

    /// Every match of `query` in `text`, left to right, not overlapping; case and accents don't matter.
    static func hits(_ query: String, in text: String) -> [QCFindHit] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !text.isEmpty else { return [] }
        var out: [QCFindHit] = []
        var from = text.startIndex
        var pos = 0
        while from < text.endIndex,
              let r = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: from..<text.endIndex) {
            pos += text.distance(from: from, to: r.lowerBound)
            let len = text.distance(from: r.lowerBound, to: r.upperBound)
            guard len > 0 else { break }
            out.append(QCFindHit(start: pos, length: len, utf16: text.utf16.distance(from: text.startIndex, to: r.lowerBound)))
            pos += len
            from = r.upperBound
        }
        return out
    }
}

/// A match in the chat, with where it stands (for keeping the current one while the text changes).
struct QCFindMatch: Equatable {
    var turn: UUID
    var turnIndex: Int
    var key: QCSegKey
    var hit: QCFindHit

    /// Reading order.
    func before(_ o: QCFindMatch) -> Bool {
        (turnIndex, key.block, key.sub, hit.start) < (o.turnIndex, o.key.block, o.key.sub, o.hit.start)
    }
}

/// The find bar's state: open or not, what is typed, the matches and the current one. Main thread only.
final class QCFindState: ObservableObject {
    @Published private(set) var isOpen = false
    @Published var query = "" {
        didSet { if query != oldValue { recompute(reveal: true) } }
    }
    @Published private(set) var matches: [QCFindMatch] = []
    @Published private(set) var current = 0
    /// The matches per turn, as its views read them.
    @Published private(set) var marks: [UUID: QCFindMarks] = [:]
    /// Asks the field to take the keyboard (⌘F again does too) and select what it holds.
    @Published private(set) var focusTick = 0
    private var token = 0

    /// The chat's turns (set by QuickChat).
    var turns: () -> [QuickChatTurn] = { [] }
    /// The bar went: the keyboard goes back to the chat's field (set by QuickChat).
    var onClosed: () -> Void = {}

    var hasQuery: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// "3 of 12", "No matches", or nothing while the field is empty.
    var count: String {
        guard hasQuery else { return "" }
        return matches.isEmpty ? "No matches" : "\(current + 1) of \(matches.count)"
    }

    /// ⌘F: the bar opens (or, open already, takes the keyboard and selects its text).
    func open() {
        isOpen = true
        focusTick += 1
        if hasQuery { recompute(reveal: false) }
    }

    /// Esc, ✕, ⌘W, a new chat: the bar, its text and every highlight go.
    func close() {
        guard isOpen || !query.isEmpty || !matches.isEmpty else { return }
        let was = isOpen
        isOpen = false
        query = ""                     // (recompute does nothing while closed)
        matches = []; marks = [:]; current = 0; cache = [:]
        if was { onClosed() }
    }

    /// ⌘G (1) and ⇧⌘G (-1), Return and ⇧Return in the field, ▼ and ▲: the next or the previous match, wrapping round.
    func step(_ by: Int) {
        guard !matches.isEmpty else { return }
        current = ((current + by) % matches.count + matches.count) % matches.count
        token += 1
        rebuild()
    }

    /// The chat's text changed (an answer streams): the matches follow it, the current one stays where it is.
    func turnsChanged() {
        guard isOpen, hasQuery else { return }
        recompute(reveal: false)
    }

    /// A turn's segments, by (the lengths of its message and answer): a streamed token or a keystroke re-parses only the turn that changed.
    private struct SegmentCache {
        var question: Int
        var answer: Int
        var segments: [(key: QCSegKey, text: String)]
    }
    private var cache: [UUID: SegmentCache] = [:]

    private func recompute(reveal: Bool) {
        guard isOpen else { return }
        let prior = matches.indices.contains(current) ? matches[current] : nil
        var out: [QCFindMatch] = []
        if hasQuery {
            var seen: [UUID: SegmentCache] = [:]
            for (ti, t) in turns().enumerated() {
                // a turn whose text has not changed (same lengths: an answer only grows, a message is fixed) keeps its segments
                let q = t.question.utf8.count, a = t.answer.utf8.count
                let c: SegmentCache
                if let old = cache[t.id], old.question == q, old.answer == a { c = old }
                else { c = SegmentCache(question: q, answer: a, segments: QCFindEngine.segments(question: t.question, answer: t.answer)) }
                seen[t.id] = c
                for seg in c.segments {
                    for h in QCFindEngine.hits(query, in: seg.text) { out.append(QCFindMatch(turn: t.id, turnIndex: ti, key: seg.key, hit: h)) }
                }
            }
            cache = seen
        }
        matches = out
        // the current match stays, or moves to the first one after where it was (typing on narrows the matches from there)
        current = prior.flatMap { p in out.firstIndex { !$0.before(p) } } ?? 0
        if reveal { token += 1 }
        rebuild()
    }

    private func rebuild() {
        var m: [UUID: QCFindMarks] = [:]
        for (i, x) in matches.enumerated() {
            m[x.turn, default: QCFindMarks()].ranges[x.key, default: []].append(QCFindRange(start: x.hit.start, length: x.hit.length, current: i == current))
        }
        if matches.indices.contains(current) {
            let c = matches[current]
            m[c.turn]?.reveal = QCFindReveal(key: c.key, utf16: c.hit.utf16, token: token)
        }
        if marks != m { marks = m }
    }
}

// MARK: - The bar

/// The find bar: a field, "n of m", ▲ ▼ and ✕, over the top of the answers (it never changes the window's size).
struct QCFindBar: View {
    @ObservedObject var find: QCFindState
    static let height: CGFloat = 32

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium)).foregroundColor(QCColor.muted)
            QCFindField(text: $find.query, focusTick: find.focusTick, onNext: { find.step(1) }, onPrevious: { find.step(-1) },
                        onClose: { QuickChat.shared.escape() })       // Esc: the keys list first, as everywhere else, then this bar
                .frame(maxWidth: .infinity, minHeight: 20, maxHeight: 20)
            Text(find.count).font(.system(size: 11.5).monospacedDigit()).foregroundColor(QCColor.muted).lineLimit(1).fixedSize()
            QCIconButton(symbol: "chevron.up", help: "Previous match ⇧⌘G", small: true, label: "Previous match", enabled: !find.matches.isEmpty) { find.step(-1) }
            QCIconButton(symbol: "chevron.down", help: "Next match ⌘G", small: true, label: "Next match", enabled: !find.matches.isEmpty) { find.step(1) }
            QCIconButton(symbol: "xmark", help: "Close Esc", small: true, label: "Close find") { find.close() }
        }
        .padding(.leading, 10).padding(.trailing, 4)
        .frame(height: Self.height)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(QCColor.hex(0x2B2B29)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(QCColor.line))
        .qcControl()
        .padding(.top, 6).padding(.horizontal, QCSpace.gap)
    }
}

/// The bar's search field: Return is the next match, ⇧Return the previous, Esc closes. (⌘G, ⇧⌘G and ⌘F are the panel's.)
struct QCFindField: NSViewRepresentable {
    @Binding var text: String
    let focusTick: Int
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let f = NSTextField()
        let font = NSFont.systemFont(ofSize: 13)
        f.isBordered = false; f.drawsBackground = false; f.focusRingType = .none
        f.font = font; f.textColor = NSColor(QCColor.text)
        f.placeholderAttributedString = NSAttributedString(string: "Find in chat", attributes: [.font: font, .foregroundColor: NSColor(QCColor.muted)])
        f.usesSingleLineMode = true
        f.lineBreakMode = .byClipping
        f.cell?.isScrollable = true
        f.delegate = context.coordinator
        f.stringValue = text
        return f
    }

    func updateNSView(_ f: NSTextField, context: Context) {
        context.coordinator.parent = self
        if f.stringValue != text { f.stringValue = text }
        if context.coordinator.focusTick != focusTick {
            context.coordinator.focusTick = focusTick
            DispatchQueue.main.async {
                guard let w = f.window else { return }
                w.makeFirstResponder(f)
                f.currentEditor()?.selectAll(nil)
                (f.currentEditor() as? NSTextView)?.insertionPointColor = NSColor(QCColor.accent)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: QCFindField
        var focusTick = -1
        init(_ p: QCFindField) { parent = p }

        func controlTextDidChange(_ n: Notification) {
            guard let f = n.object as? NSTextField, parent.text != f.stringValue else { return }
            parent.text = f.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            switch sel {
            case #selector(NSResponder.insertNewline(_:)):
                if textView.hasMarkedText() { return false }
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { parent.onPrevious() } else { parent.onNext() }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onClose()
                return true
            default:
                return false
            }
        }
    }
}

// MARK: - Showing and reaching a match

/// Behind a text that holds the current match: once per token it brings the match's line into view. An empty view that takes
/// no press.
struct QCFindAnchor: NSViewRepresentable {
    let reveal: QCFindReveal
    /// The text's length in utf16 units (the line lookup's own).
    let length: Int
    @Environment(\.qcChatScroll) private var scroll

    final class Marker: NSView {
        var done = 0
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> Marker { Marker() }

    func updateNSView(_ v: Marker, context: Context) {
        guard let scroll, reveal.token != v.done else { return }
        v.done = reveal.token
        let utf16 = reveal.utf16, length = length
        // after this pass's layout: the views have their places
        DispatchQueue.main.async { [weak v] in
            if let v { scroll.revealMatch(in: v, utf16: utf16, length: length) }
        }
    }
}

extension View {
    /// A text that may hold the current match: it tells the chat where it is when it does.
    func qcFindAnchor(_ reveal: QCFindReveal?, length: Int) -> some View {
        background {
            if let reveal { QCFindAnchor(reveal: reveal, length: length) }
        }
    }
}

/// Reading a text's lines from the view SwiftUI draws it in (an AppKit text interaction view behind every selectable Text: it
/// answers the accessibility text API, lines and selection included).
enum QCTextLines {
    static func isInteraction(_ v: NSView) -> Bool { String(describing: type(of: v)).hasSuffix("TextInteractionView") }

    /// All the text interaction views under a view that are shown.
    static func all(under root: NSView) -> [NSView] {
        var out: [NSView] = []
        func walk(_ v: NSView) {
            if v.isHidden { return }
            if isInteraction(v) { out.append(v); return }
            v.subviews.forEach(walk)
        }
        walk(root)
        return out
    }

    /// The text view that is drawn where `anchor` (a view over the same frame) is.
    static func interaction(under anchor: NSView) -> NSView? {
        guard let root = anchor.window?.contentView else { return nil }
        let want = anchor.convert(anchor.bounds, to: nil)
        guard want.width > 0, want.height > 0 else { return nil }
        var best: (NSView, CGFloat)?
        for v in all(under: root) {
            let r = v.convert(v.bounds, to: nil).intersection(want)
            guard !r.isNull else { continue }
            let share = r.width * r.height / max(1, min(want.width * want.height, v.bounds.width * v.bounds.height))
            if share > 0.6, share > (best?.1 ?? 0) { best = (v, share) }
        }
        return best?.0
    }

    /// The line a utf16 offset is on, and how many lines the text has.
    static func line(of utf16: Int, in v: NSView) -> (line: Int, lines: Int) {
        let n = v.accessibilityNumberOfCharacters()
        guard n > 0 else { return (0, 1) }
        let at = min(max(0, utf16), n - 1)
        return (v.accessibilityLine(for: at), v.accessibilityLine(for: n - 1) + 1)
    }
}

extension QCChatScroll {
    /// The match at a utf16 offset of the text that `anchor` is behind: its line is brought into view (see `reveal`).
    func revealMatch(in anchor: NSView, utf16: Int, length: Int) {
        if let t = QCTextLines.interaction(under: anchor), case let l = QCTextLines.line(of: utf16, in: t), l.lines > 0 {
            reveal(anchor, line: l.line, lines: l.lines, cover: QCFindBar.height + 16)
        } else {
            // no line information: the offset's share of the text's height stands for it
            let share = length > 0 ? Double(utf16) / Double(length) : 0
            reveal(anchor, line: Int(share * 1000), lines: 1000, cover: QCFindBar.height + 16)
        }
    }
}
