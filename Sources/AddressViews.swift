// An account address in the chat's sentences: blurred at rest and sharp while the pointer is on it, like the menu's
// (QCProfileMenuRow). A sentence that holds one carries it apart from the words around it (QCWords), so only the
// address blurs and the sentence keeps its layout and wrapping. As words (VoiceOver, the checks) the address is masked.

import SwiftUI
import AppKit

/// Whether account addresses are blurred (Settings ▸ General ▸ Blur addresses; on unless it was turned off). On: an
/// address is blurred until the pointer is on it, and as words (VoiceOver, an item's title) it is masked. Off: it is
/// drawn in full and sharp, and the words hold it in full. Drawn views read it as they are drawn, so a change reaches the
/// chat at once and the menus the next time they open.
final class AddressPrivacy: ObservableObject {
    static let shared = AddressPrivacy()
    @Published var blur = true

    /// Counts the times a pointer's hover was cut short without a mouse-exit: the panel ordered out under the pointer
    /// (it gets no exit), a modal alert that took the pointer, the window covered. Views that reveal an address on hover
    /// drop it when this changes (QCHoverGate).
    @Published private(set) var hoverEnded = 0
    func endHover() { hoverEnded += 1 }

    /// Takes the setting (as the app starts and whenever Settings changes it).
    func apply(_ s: QuickChatSettings) { if blur != s.blurAddresses { blur = s.blurAddresses } }

    /// An address as words: masked while blurring, else in full.
    static func words(_ address: String) -> String { shared.blur ? maskEmail(address) : address }
}

/// A sentence in pieces: words and, apart from them, the addresses in it (whole, for drawing only).
struct QCWords: Equatable {
    struct Piece: Equatable {
        var text: String
        var isAddress = false
        /// Drawn semibold in the strong colour (the lead of a notice).
        var strong = false
    }
    var pieces: [Piece] = []

    init() {}
    init(_ text: String) { if !text.isEmpty { pieces = [Piece(text: text)] } }
    static func text(_ s: String) -> QCWords { QCWords(s) }
    static func address(_ a: String) -> QCWords { var w = QCWords(); w.pieces = [Piece(text: a, isAddress: true)]; return w }
    static func + (l: QCWords, r: QCWords) -> QCWords { var w = l; w.pieces += r.pieces; return w }

    /// The chat's line after an account changed: "Main is on <address> now." (no address known: "another account").
    static func isOn(_ name: String, address: String?) -> QCWords {
        .text("\(name) is on ") + (address.map { .address($0) } ?? .text("another account")) + .text(" now.")
    }

    /// The same words, semibold in the strong colour (the addresses too).
    var strong: QCWords {
        var w = self
        for i in w.pieces.indices { w.pieces[i].strong = true }
        return w
    }

    /// The whole addresses in it, in order (for drawing).
    var addresses: [String] { pieces.filter(\.isAddress).map(\.text) }
    /// The sentence as words (VoiceOver, the checks): every address masked, never in full (in full only with the
    /// blur turned off, AddressPrivacy).
    var spoken: String { pieces.map { $0.isAddress ? AddressPrivacy.words($0.text) : $0.text }.joined() }
    var isEmpty: Bool { pieces.isEmpty }
}

/// Whether the pointer is on something that reveals an address. SwiftUI's onHover reports only enters and exits, and a
/// window hidden or covered under the pointer, or a modal alert, sends no exit: so the hover also ends when
/// `AddressPrivacy.hoverEnded` changes, and is not taken up again until the pointer enters anew.
struct QCHoverGate: Equatable {
    private(set) var on = false
    private var seen: Int
    init(seen: Int = AddressPrivacy.shared.hoverEnded) { self.seen = seen }
    /// The pointer entered (true) or left (false).
    mutating func pointer(_ inside: Bool) { on = inside }
    /// The counter's value now: a change ends the hover.
    mutating func sync(_ ended: Int) { if ended != seen { seen = ended; on = false } }
}

/// An address that is blurred at rest and sharp while the pointer is on it (or while `revealed`, when a button around
/// it carries the pointer). Its accessibility label is the masked address. The blur is the menu's: a Gaussian blur of
/// about a fifth of the text size (the menu's is 2.4 pt on 11.5 pt text).
struct QCBlurredAddress: View {
    let address: String
    var size: CGFloat = 12.5
    var revealed = false
    @State private var gate = QCHoverGate()
    @ObservedObject private var privacy = AddressPrivacy.shared

    /// The blur radius for a text size: none while the address is meant to be read (or the blur is turned off).
    static func blurRadius(size: CGFloat, revealed: Bool, blur: Bool = true) -> CGFloat {
        revealed || !blur ? 0 : (size * 0.21).rounded(toPlaces: 2)
    }

    var body: some View {
        Text(address)
            .lineLimit(1)
            .blur(radius: Self.blurRadius(size: size, revealed: gate.on || revealed, blur: privacy.blur))
            .contentShape(Rectangle())
            .onHover { gate.pointer($0) }
            .onChange(of: privacy.hoverEnded) { gate.sync($0) }
            .accessibilityLabel(AddressPrivacy.words(address))
    }
}

private extension CGFloat {
    func rounded(toPlaces n: Int) -> CGFloat { let m = pow(10, CGFloat(n)); return (self * m).rounded() / m }
}

/// Lays tokens out in lines that wrap at the width given, a space between them: the way text wraps, for a sentence
/// that holds a view (the blurred address) among its words.
/// At most `maxRows` lines (like Text's lineLimit): what doesn't fit is placed far outside the layout, for QCSentence to
/// clip away. A token wider than the width offered takes that width, so its text truncates instead of overflowing.
struct QCFlow: Layout {
    var gap: CGFloat
    var maxRows: Int? = nil
    /// Where tokens that don't fit are put: past anything a sentence's clip shows.
    static let away: CGFloat = 400

    typealias Row = [(index: Int, size: CGSize)]
    private func lines(_ subviews: Subviews, width: CGFloat) -> (rows: [Row], cut: [Int], height: CGFloat, widest: CGFloat) {
        var rows: [Row] = [[]]
        var cut: [Int] = []
        var x: CGFloat = 0, widest: CGFloat = 0
        for (i, s) in subviews.enumerated() {
            if !cut.isEmpty { cut.append(i); continue }
            var size = s.sizeThatFits(.unspecified)
            size.width = min(size.width, width)
            let first = rows[rows.count - 1].isEmpty
            if !first, x + gap + size.width > width {
                if let m = maxRows, rows.count >= m { cut.append(i); continue }
                rows.append([]); x = 0
            }
            x += (rows[rows.count - 1].isEmpty ? 0 : gap) + size.width
            rows[rows.count - 1].append((index: i, size: size))
            widest = max(widest, x)
        }
        let height = rows.reduce(CGFloat(0)) { $0 + ($1.map(\.size.height).max() ?? 0) }
        return (rows, cut, height, widest)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let l = lines(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: l.widest, height: l.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let l = lines(subviews, width: bounds.width)
        var y = bounds.minY
        for row in l.rows {
            let h = row.map(\.size.height).max() ?? 0
            var x = bounds.minX
            for (index, size) in row {
                subviews[index].place(at: CGPoint(x: x, y: y + (h - size.height) / 2), anchor: .topLeading, proposal: ProposedViewSize(size))
                x += size.width + gap
            }
            y += h
        }
        for i in l.cut { subviews[i].place(at: CGPoint(x: bounds.maxX + Self.away, y: bounds.minY), anchor: .topLeading, proposal: .zero) }
    }
}

/// A sentence of QCWords. With no address in it, it is one Text, as every note always was; with one, the words flow
/// in lines like text and the address is a QCBlurredAddress among them. The sentence is one element for VoiceOver,
/// with the addresses masked. The font is the caller's.
struct QCSentence: View {
    let words: QCWords
    var size: CGFloat = 12.5
    var color: Color
    var strongColor: Color = QCColor.text
    var lineLimit: Int? = nil
    @ObservedObject private var privacy = AddressPrivacy.shared

    static let bleed: CGFloat = 10

    private func styled(_ p: QCWords.Piece) -> Text {
        p.strong ? Text(p.text).fontWeight(.semibold).foregroundColor(strongColor) : Text(p.text).foregroundColor(color)
    }
    private func blurred(_ p: QCWords.Piece) -> some View {
        QCBlurredAddress(address: p.text, size: size).fontWeight(p.strong ? .semibold : .regular).foregroundColor(p.strong ? strongColor : color)
    }

    /// The pieces cut at their spaces into tokens that don't break: an address keeps the punctuation next to it.
    static func tokens(_ words: QCWords) -> [[QCWords.Piece]] {
        var tokens: [[QCWords.Piece]] = [[]]
        for p in words.pieces {
            if p.isAddress { tokens[tokens.count - 1].append(p); continue }
            for (i, part) in p.text.split(separator: " ", omittingEmptySubsequences: false).enumerated() {
                if i > 0 { tokens.append([]) }
                if !part.isEmpty { tokens[tokens.count - 1].append(QCWords.Piece(text: String(part), strong: p.strong)) }
            }
        }
        return tokens.filter { !$0.isEmpty }
    }

    var body: some View {
        // (with the blur off the address is plain text in the sentence: one Text, as with no address at all)
        if words.addresses.isEmpty || !privacy.blur {
            words.pieces.reduce(Text("")) { $0 + styled($1) }.lineLimit(lineLimit)
        } else {
            let spaceW = (" " as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size)]).width
            QCFlow(gap: spaceW, maxRows: lineLimit) {
                ForEach(Array(Self.tokens(words).enumerated()), id: \.offset) { _, token in
                    HStack(spacing: 0) {
                        ForEach(Array(token.enumerated()), id: \.offset) { _, p in
                            if p.isAddress { blurred(p) }
                            else { styled(p).lineLimit(1) }
                        }
                    }
                }
            }
            // what the line limit cuts is far outside; the clip is wider than the sentence by the blur's reach, so it
            // doesn't cut the blurred address at the top and bottom
            .padding(Self.bleed).clipped().padding(-Self.bleed)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(words.spoken)
        }
    }
}
