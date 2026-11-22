// QuickChatMarkdown: an answer's Markdown as blocks the chat window draws (QuickChatViews.swift). Paragraphs, headings,
// lists, quotes, rules, tables and fenced code; the inline part (bold, italics, `code`, links) is left to Foundation's own
// Markdown. While an answer streams, a fence that isn't closed yet is still a code block, so code never flashes as text.

import Foundation

enum QuickChatBlock: Equatable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case bullets([String])
    case numbered(start: Int, items: [String])
    case quote(String)
    /// A fenced block: the language (the info string's first word), the words after it (`meta`: "```html code" has
    /// "code"), and whether its closing fence has come (false while the answer is still streaming it).
    case code(language: String, text: String, meta: String = "", closed: Bool = true)
    case rule
    /// A GitHub-style table: the header's cells, how each column is aligned, and the body rows. Every row has as many
    /// cells as the header; a cell is still Markdown source (the inline part is drawn by the view).
    case table(header: [String], align: [QuickChatAlign], rows: [[String]])
}

enum QuickChatAlign: Equatable { case left, center, right }

enum QuickChatMarkdown {
    static func blocks(_ source: String) -> [QuickChatBlock] {
        var out: [QuickChatBlock] = []
        var para: [String] = [], quote: [String] = []
        var bullets: [String] = [], numbered: [String] = [], start = 1
        func flush() {
            if !para.isEmpty { out.append(.paragraph(para.joined(separator: "\n"))); para = [] }
            if !quote.isEmpty { out.append(.quote(quote.joined(separator: "\n"))); quote = [] }
            if !bullets.isEmpty { out.append(.bullets(bullets)); bullets = [] }
            if !numbered.isEmpty { out.append(.numbered(start: start, items: numbered)); numbered = [] }
        }
        let lines = source.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let t = line.trimmingCharacters(in: .whitespaces)
            if let fence = Self.fence(t) {
                flush()
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence.marker) {
                    code.append(lines[i]); i += 1
                }
                let closed = i < lines.count
                i += 1
                out.append(.code(language: fence.language, text: code.joined(separator: "\n"), meta: fence.meta, closed: closed))
                continue
            }
            if t.isEmpty { flush(); i += 1; continue }
            if let h = Self.heading(t) { flush(); out.append(.heading(level: h.level, text: h.text)); i += 1; continue }
            // a header row followed by an alignment row; a run of | lines without one stays text
            if t.contains("|"), i + 1 < lines.count, let align = Self.tableAlignment(lines[i + 1]) {
                let header = Self.cells(t)
                if header.count == align.count {
                    flush()
                    var rows: [[String]] = []
                    i += 2
                    while i < lines.count {
                        let r = lines[i].trimmingCharacters(in: .whitespaces)
                        if !r.contains("|") || Self.fence(r) != nil || Self.heading(r) != nil { break }
                        let row = Array((Self.cells(r) + Array(repeating: "", count: header.count)).prefix(header.count))
                        if row.contains(where: { !$0.isEmpty }) { rows.append(row) }      // a row that is only pipes (still streaming) isn't one yet
                        i += 1
                    }
                    out.append(.table(header: header, align: align, rows: rows))
                    continue
                }
            }
            if t == "---" || t == "***" || t == "___" { flush(); out.append(.rule); i += 1; continue }
            if t.hasPrefix(">") {
                if !para.isEmpty || !bullets.isEmpty || !numbered.isEmpty { flush() }
                quote.append(String(t.dropFirst()).trimmingCharacters(in: .whitespaces)); i += 1; continue
            }
            if let item = Self.bullet(t) {
                if !para.isEmpty || !quote.isEmpty || !numbered.isEmpty { flush() }
                bullets.append(item); i += 1; continue
            }
            if let n = Self.number(t) {
                if !para.isEmpty || !quote.isEmpty || !bullets.isEmpty { flush() }
                if numbered.isEmpty { start = n.number }
                numbered.append(n.text); i += 1; continue
            }
            // a list item's next line, indented, belongs to it
            if line.hasPrefix("  "), !bullets.isEmpty { bullets[bullets.count - 1] += " " + t; i += 1; continue }
            if line.hasPrefix("  "), !numbered.isEmpty { numbered[numbered.count - 1] += " " + t; i += 1; continue }
            if !bullets.isEmpty || !numbered.isEmpty || !quote.isEmpty { flush() }
            para.append(t); i += 1
        }
        flush()
        return out
    }

    /// A table row's cells, trimmed, without the outer pipes. A pipe splits unless it's escaped (`\|`, which is a plain
    /// pipe in the cell) or inside an inline `code` span.
    static func cells(_ line: String) -> [String] {
        let s = Array(line.trimmingCharacters(in: .whitespaces))
        var out: [String] = [], cur = ""
        var i = 0
        while i < s.count {
            let c = s[i]
            if c == "\\", i + 1 < s.count {
                if s[i + 1] == "|" { cur.append("|") } else { cur.append(c); cur.append(s[i + 1]) }
                i += 2; continue
            }
            if c == "`" {
                var n = 0
                while i + n < s.count, s[i + n] == "`" { n += 1 }
                // the code span runs to the next run of exactly as many backticks; none, and these are plain characters
                var j = i + n, close: Int? = nil
                while j < s.count {
                    if s[j] == "`" {
                        var m = 0
                        while j + m < s.count, s[j + m] == "`" { m += 1 }
                        if m == n { close = j; break }
                        j += m
                    } else { j += 1 }
                }
                if let close {
                    cur += String(s[i..<(close + n)]).replacingOccurrences(of: "\\|", with: "|")
                    i = close + n
                } else {
                    cur += String(s[i..<(i + n)]); i += n
                }
                continue
            }
            if c == "|" { out.append(cur); cur = ""; i += 1; continue }
            cur.append(c); i += 1
        }
        out.append(cur)
        if s.first == "|" { out.removeFirst() }
        if s.last == "|", out.last == "" { out.removeLast() }
        return out.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// The alignment of each column when this line is a table's alignment row (`---`, `:---`, `---:`, `:---:`, outer
    /// pipes or not); nil when it isn't one.
    static func tableAlignment(_ line: String) -> [QuickChatAlign]? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("|"), t.allSatisfy({ "|-: \t".contains($0) }) else { return nil }
        let cs = cells(t)
        guard !cs.isEmpty else { return nil }
        var out: [QuickChatAlign] = []
        for cell in cs {
            var d = Substring(cell)
            let lead = d.hasPrefix(":")
            if lead { d.removeFirst() }
            let trail = d.hasSuffix(":")
            if trail { d.removeLast() }
            guard !d.isEmpty, d.allSatisfy({ $0 == "-" }) else { return nil }
            out.append(lead && trail ? .center : trail ? .right : .left)
        }
        return out
    }

    /// "```swift" or "~~~": the marker that closes it, the language named ("" when none) and the words after it, one
    /// space apart ("```html code": "html" and "code").
    static func fence(_ t: String) -> (marker: String, language: String, meta: String)? {
        for m in ["```", "~~~"] where t.hasPrefix(m) {
            let words = String(t.dropFirst(3)).split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            return (m, words.first ?? "", words.dropFirst().joined(separator: " "))
        }
        return nil
    }

    static func heading(_ t: String) -> (level: Int, text: String)? {
        let hashes = t.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), t.dropFirst(hashes).first == " " else { return nil }
        return (hashes, String(t.dropFirst(hashes + 1)))
    }

    static func bullet(_ t: String) -> String? {
        for m in ["- ", "* ", "+ ", "• "] where t.hasPrefix(m) { return String(t.dropFirst(2)) }
        return nil
    }

    static func number(_ t: String) -> (number: Int, text: String)? {
        let digits = t.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 3, let n = Int(digits) else { return nil }
        let rest = t.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return (n, String(rest.dropFirst(2)))
    }

    /// The inline part (bold, italics, `code`, links) as Foundation reads it; the plain text when it can't. Only web and
    /// mail links stay links: an answer can't hand the Mac a file:// or an app's own link to open.
    static func inline(_ s: String) -> AttributedString {
        guard var a = try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return AttributedString(s)
        }
        let unsafe = a.runs.compactMap { run in run.link.map { safeLink($0) ? nil : run.range } ?? nil }
        for r in unsafe { a[r].link = nil }
        return a
    }

    static func safeLink(_ url: URL) -> Bool { ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") }

    /// An answer as plain text to read aloud: the Markdown marks go (bold, italics, `code` marks, link syntax, heading and list
    /// marks, table pipes and rules), the words stay, and a code block is the words "code block" (`code`) in its place, so the
    /// listener knows there was one without hearing it spelled out. Headings, list items and table rows end with a full stop
    /// when they have no punctuation, which is where the voice pauses. Empty when nothing is left to read.
    static func spoken(_ source: String, code: String = "code block") -> String {
        func plain(_ s: String) -> String {
            let a = (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
            return String(a.characters).replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func stopped(_ s: String) -> String {
            guard let last = s.last, !".!?…:;。！？".contains(last) else { return s }
            return s + "."
        }
        var out: [String] = []
        for b in blocks(source) {
            switch b {
            case .paragraph(let s), .quote(let s): out.append(plain(s))
            case .heading(_, let s): out.append(stopped(plain(s)))
            case .bullets(let items): out.append(contentsOf: items.map { stopped(plain($0)) })
            case .numbered(let start, let items): out.append(contentsOf: items.enumerated().map { "\(start + $0.offset). " + stopped(plain($0.element)) })
            case .code: out.append(stopped(code))
            case .rule: break
            case .table(let header, _, let rows): out.append(contentsOf: ([header] + rows).map { stopped($0.map(plain).filter { !$0.isEmpty }.joined(separator: ", ")) })
            }
        }
        return out.filter { !$0.isEmpty && $0 != "." }.joined(separator: "\n")
    }

    /// A whole chat as Markdown, to paste into a note or an issue: "**You:**" and the message, then "**Claude:**" and the
    /// answer, for each exchange in turn, a blank line between all of them. Bold labels, not headings: an answer has headings
    /// of its own, which stay as written, with its code blocks (fences and languages) and everything else. A picture is
    /// "[image]" and a file "[file: name]" after the message's text. An exchange with no answer (failed, or not begun) has
    /// no Claude part; one still streaming has the text so far.
    static func chat(_ exchanges: [QuickChatExchange]) -> String {
        var parts: [String] = []
        for x in exchanges {
            var mine: [String] = []
            let q = x.question.trimmingCharacters(in: .whitespacesAndNewlines)
            if !q.isEmpty { mine.append(q) }
            mine += Array(repeating: "[image]", count: x.images)
            mine += x.files.map { "[file: \($0)]" }
            if !mine.isEmpty { parts.append("**You:**\n\n" + mine.joined(separator: "\n\n")) }
            let a = x.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !a.isEmpty { parts.append("**Claude:**\n\n" + a) }
        }
        return parts.joined(separator: "\n\n")
    }
}

/// One message of the user's with what it carried and its answer, as QuickChatMarkdown.chat reads it.
struct QuickChatExchange: Equatable {
    var question: String
    /// How many pictures went with it, and the names of the files.
    var images = 0
    var files: [String] = []
    var answer = ""
}
