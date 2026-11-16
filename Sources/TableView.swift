// TableView: a Markdown table in an answer (QuickChatBlock.table), drawn as a grid in the answer's own style. The header
// is semibold, the rows are told apart by thin lines (the code block's and the quote's colour), a column is aligned as
// the alignment row says, and a cell is inline Markdown like a paragraph. Column widths fit their content; when the
// answer is narrower than that, the cells wrap inside their columns, and a table with so many columns that wrapping
// can't make it fit scrolls sideways inside its own frame, as a code block's long lines do.

import SwiftUI

/// The columns' widths for a table. `floor` is the narrowest a column is wrapped to (its longest word, and no less than
/// `QCTableLayout.comfort` unless its whole text is shorter); `ideal` is its text on one line.
enum QCTableWidths {
    /// The narrowest a column is wrapped to when it has more text than that: about eleven characters and its padding.
    static let comfort: CGFloat = 96
    /// A column's cap when the table scrolls: a long cell wraps at this width instead of making a very wide column.
    static let scrolling: CGFloat = 240

    static func floors(min: [CGFloat], ideal: [CGFloat]) -> [CGFloat] {
        zip(min, ideal).map { max($0, Swift.min($1, comfort)) }
    }

    /// The widths in `avail` points: each column's ideal when they all fit, else the floors plus what's left over shared
    /// out by how much more each column would like. Never less than the floors (the table then scrolls).
    static func fit(floor: [CGFloat], ideal: [CGFloat], avail: CGFloat) -> [CGFloat] {
        guard ideal.reduce(0, +) > avail else { return ideal }
        let base = floor.reduce(0, +)
        guard base < avail else { return floor }
        let want = zip(ideal, floor).map { $0 - $1 }, wanted = want.reduce(0, +)
        guard wanted > 0 else { return floor }
        let spare = avail - base
        return zip(floor, want).map { $0 + $1 * spare / wanted }
    }

    /// The widths when the table scrolls: ideal, but no wider than `scrolling`, and no narrower than the floors.
    static func scrolled(floor: [CGFloat], ideal: [CGFloat]) -> [CGFloat] {
        zip(floor, ideal).map { max($0, Swift.min($1, scrolling)) }
    }
}

/// The cells of a table, header first, `columns` to a row, laid out as a grid: a row is as tall as its tallest cell and a
/// column as wide as `QCTableWidths` says. Asked for its ideal size (nil width) it answers with the narrowest it wraps to,
/// so ViewThatFits (QCTableView) can tell whether wrapping makes it fit; given a width it uses it.
struct QCTableLayout: Layout {
    let columns: Int
    /// True inside a scroll view: no width is given, the columns take their (capped) ideal widths.
    let scrolling: Bool
    /// True where nothing scrolls (a picture): the table reports no more than it is given, and what doesn't fit is clipped.
    var contain = false

    struct Cache { var floor: [CGFloat] = [], ideal: [CGFloat] = [] }

    func makeCache(subviews: Subviews) -> Cache {
        var c = Cache()
        guard columns > 0 else { return c }
        var min = Array(repeating: CGFloat(0), count: columns), ideal = min
        for (i, v) in subviews.enumerated() {
            let col = i % columns
            min[col] = max(min[col], v.sizeThatFits(ProposedViewSize(width: 0, height: nil)).width)
            ideal[col] = max(ideal[col], v.sizeThatFits(.unspecified).width)
        }
        c.ideal = zip(ideal, min).map { max($0, $1) }
        c.floor = QCTableWidths.floors(min: min, ideal: c.ideal)
        return c
    }

    private func widths(_ proposal: ProposedViewSize, _ cache: Cache) -> [CGFloat] {
        if scrolling { return QCTableWidths.scrolled(floor: cache.floor, ideal: cache.ideal) }
        guard let w = proposal.width, w.isFinite else { return cache.floor }
        return QCTableWidths.fit(floor: cache.floor, ideal: cache.ideal, avail: w)
    }

    private func rowHeights(_ subviews: Subviews, _ widths: [CGFloat]) -> [CGFloat] {
        stride(from: 0, to: subviews.count, by: columns).map { start in
            (0..<columns).reduce(CGFloat(0)) { h, c in
                let i = start + c
                return i < subviews.count ? max(h, subviews[i].sizeThatFits(ProposedViewSize(width: widths[c], height: nil)).height) : h
            }
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        guard columns > 0, !subviews.isEmpty else { return .zero }
        let w = widths(proposal, cache)
        var width = w.reduce(0, +)
        if contain, let given = proposal.width, given.isFinite { width = min(width, given) }
        return CGSize(width: width, height: rowHeights(subviews, w).reduce(0, +))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        guard columns > 0, !subviews.isEmpty else { return }
        let w = widths(ProposedViewSize(width: bounds.width, height: nil), cache)
        let heights = rowHeights(subviews, w)
        var y = bounds.minY
        for (row, h) in heights.enumerated() {
            var x = bounds.minX
            for c in 0..<columns {
                let i = row * columns + c
                if i < subviews.count {
                    subviews[i].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: w[c], height: h))
                }
                x += w[c]
            }
            y += h
        }
    }
}

struct QCTableView: View {
    let header: [String]
    let align: [QuickChatAlign]
    let rows: [[String]]
    @Environment(\.qcRendering) private var rendering

    private var columns: Int { header.count }

    var body: some View {
        // wrapped to the width when that fits, else its own scroll view; a picture can't draw one, so it clips instead
        ViewThatFits(in: .horizontal) {
            grid(scrolling: false)
            if rendering {
                grid(scrolling: true, contain: true).clipped()
            } else {
                ScrollView(.horizontal, showsIndicators: true) { grid(scrolling: true) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(QCColor.line))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func grid(scrolling: Bool, contain: Bool = false) -> some View {
        QCTableLayout(columns: columns, scrolling: scrolling, contain: contain) {
            ForEach(0..<columns, id: \.self) { c in cell(header[c], column: c, head: true) }
            ForEach(0..<rows.count, id: \.self) { r in
                ForEach(0..<columns, id: \.self) { c in cell(rows[r][c], column: c, head: false) }
            }
        }
    }

    /// One cell: inline Markdown at 13 pt, aligned as its column says, with the row's separator on its top edge (the
    /// header sits on the code block's fill instead).
    private func cell(_ s: String, column c: Int, head: Bool) -> some View {
        let a = align[c]
        return Text(s.isEmpty ? AttributedString(" ") : QCAnswer.inline(s))
            .font(.system(size: 13, weight: head ? .semibold : .regular))
            .foregroundColor(QCColor.text)
            .lineSpacing(3)
            .multilineTextAlignment(a == .right ? .trailing : a == .center ? .center : .leading)
            .textSelection(.enabled)
            .padding(EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: a == .right ? .topTrailing : a == .center ? .top : .topLeading)
            .background(head ? QCColor.code : Color.clear)
            .overlay(alignment: .top) { if !head { Rectangle().fill(QCColor.line).frame(height: 1) } }
    }
}

// MARK: - Samples for the pictures (`--render-quick-chat OUT.png table`, table-wide, table-scroll, table-inline)

enum QCTableRender {
    static func turn(_ state: String) -> QuickChatTurn {
        let answer: String
        switch state {
        case "table-wide":
            answer = """
            Four plans side by side:

            | Plan | Seats | Storage | Price per month | Support |
            |:---|---:|---:|---:|:---:|
            | Free | 1 | 5 GB | $0 | Community forum |
            | Team | Up to 25 | 200 GB | $12 per seat | Email, next business day |
            | Business | Unlimited | 2 TB | $30 per seat | Chat and email, within 4 hours |
            | Enterprise | Unlimited | Custom | Ask sales | A named contact |

            Prices are samples.
            """
        case "table-scroll":
            answer = """
            | Region | Jan | Feb | Mar | Apr | May | Jun | Jul | Aug | Sep | Oct |
            |---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
            | North | 1,204 | 1,310 | 1,298 | 1,405 | 1,512 | 1,498 | 1,602 | 1,587 | 1,640 | 1,711 |
            | South | 982 | 1,004 | 1,120 | 1,095 | 1,210 | 1,188 | 1,260 | 1,301 | 1,277 | 1,350 |
            | East | 1,540 | 1,498 | 1,610 | 1,702 | 1,688 | 1,750 | 1,820 | 1,799 | 1,860 | 1,934 |
            """
        case "table-inline":
            answer = """
            | Command | What it does | Docs |
            |:---|:---:|---:|
            | `ls -la` | **Lists** all files, with *details* | [man ls](https://example.com/ls) |
            | `a \\| b` | Pipes `a` into `b` | [man bash](https://example.com/bash) |
            | `rm` | | |
            """
        default:
            answer = """
            | | **Individual** | **Organization** |
            |---|---|---|
            | **Who it's for** | One person, under their own legal name | A company, nonprofit, or other legal entity |
            | **Team members** | Only you | Can invite members with roles (Admin, Developer, etc.) |
            | **Fee** | Same annual fee | Same annual fee |
            """
        }
        var t = QuickChatTurn(question: "Compare the account types.", answer: answer, model: "Haiku 5.5")
        t.phase = .done; t.seconds = 3.1
        return t
    }
}
