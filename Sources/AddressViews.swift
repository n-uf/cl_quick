// An account address in the chat's sentences: blurred at rest and sharp while the pointer is on it, like the menu's
// (QCProfileMenuRow). A sentence that holds one carries it apart from the words around it (QCWords), so only the
// address blurs and the sentence keeps its layout and wrapping. As words (VoiceOver, the checks) the address is masked.

import SwiftUI
import AppKit
import AddressPrivacy

// The blur itself (the stand-in, the hover gate, the views, the setting) is the AddressPrivacy module, cl_kit's Privacy/ (Vendor/).
// What stays here is the chat's sentence in pieces, which draws its addresses through it.

extension AddressPrivacy {
    /// Takes cl_quick's own setting (Settings ▸ General ▸ App ▸ Blur addresses; on unless turned off): as the app starts and
    /// whenever Settings changes it. The module keeps no setting of its own.
    func apply(_ s: QuickChatSettings) { apply(blur: s.blurAddresses) }
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
    /// The text the sentence draws while no address is revealed: with the blur on, the stand-in where each address is
    /// (never any part of it); with the blur off, the address.
    func drawn(revealed: Bool = false, blur: Bool = AddressPrivacy.shared.blur) -> String {
        pieces.map { $0.isAddress ? AddressText.drawn(address: $0.text, revealed: revealed, blur: blur) : $0.text }.joined()
    }
    /// The sentence as words (VoiceOver, the checks): every address masked, never in full (in full only with the
    /// blur turned off, AddressPrivacy).
    var spoken: String { pieces.map { $0.isAddress ? AddressPrivacy.words($0.text) : $0.text }.joined() }
    var isEmpty: Bool { pieces.isEmpty }
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
/// in lines like text and the address is a BlurredAddress among them. The sentence is one element for VoiceOver,
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
        BlurredAddress(address: p.text, size: size, reserve: false).fontWeight(p.strong ? .semibold : .regular).foregroundColor(p.strong ? strongColor : color)
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
