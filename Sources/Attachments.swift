// Attachments: files attached to a quick chat message besides pictures (Images.swift). A PDF and a text-like file
// (plain text, Markdown, CSV, JSON, code…) dropped on the panel, or copied in Finder and pasted, sit as chips next to the
// thumbnails until the message is sent, go to Claude Code as `document` blocks in the same stream-json line as the text,
// and show in the chat as chips of the message (never their content). Claude gets no file-system tools for them: it
// reads what was sent with the message, nothing else on the Mac.
//
// Incognito, like the images: a file lives only in memory, from the file (read, never copied) to the process's pipe and
// the chat's turn. No temp file, no cache, nothing for the app's folder.
//
// Limits (the same note words as the images: one muted line over the field): a PDF up to 15 MB and 100 pages, a text file
// up to 400 KB, five attachments (pictures included) a message, and per chat (the whole conversation is in every request)
// about 20 MB for everything attached (QCImages.chatCap; the API takes 32 MB a request, and a PDF goes as base64, a third
// larger, so 15 MB is the most one PDF can be), 100 PDF pages and 400 KB of text files, each counting what was sent
// earlier in the chat and what waits in the field.
//
// A file is opened without blocking and looked at through its descriptor: only a regular file is read (a link to one is
// followed; a link to /dev/zero or a pipe is refused unread), and never more than its limit plus one byte.

import AppKit
import PDFKit
import UniformTypeIdentifiers

/// One attached file: what is sent, and what its chip says. In memory only.
final class QCFile: Identifiable, Equatable {
    enum Style { case pdf, table, text }
    let id = UUID()
    let name: String
    let style: Style
    let payload: QuickChatDocumentData
    /// A PDF's page count.
    let pages: Int?
    /// What it adds to a request, in bytes: a PDF as base64, a text file as its UTF-8.
    let size: Int
    /// What it adds to the chat's text total (0 for a PDF).
    var textBytes: Int { pages == nil ? size : 0 }
    /// What its chip says under the name: "3 pages" for a PDF, its size for a text file.
    let detail: String
    /// Where it came in among the attachments (images and files share one order: the message lists them in it).
    var order = 0

    init(name: String, style: Style, payload: QuickChatDocumentData, pages: Int?, size: Int, detail: String) {
        self.name = name; self.style = style; self.payload = payload; self.pages = pages; self.size = size; self.detail = detail
    }
    static func == (a: QCFile, b: QCFile) -> Bool { a.id == b.id }

    /// The chip's symbol.
    var symbol: String {
        switch style {
        case .pdf: return "doc.richtext"
        case .table: return "chart.bar.doc.horizontal"
        case .text: return "doc.text"
        }
    }
}

enum QCFiles {
    /// A PDF's pages, at most.
    static let maxPDFPages = 100
    /// The PDF pages a chat holds, at most: the API takes 100 pages in a request, and the whole conversation is in every
    /// request, so this counts the pages sent earlier in the chat and those waiting in the field.
    static let maxChatPages = 100
    /// A text file's size, at most (1 MB of text is some 250,000 tokens: more than a request holds with room to answer).
    static let maxTextBytes = 400_000
    /// The text files a chat holds, in all (sent and waiting), at most.
    static let maxChatText = 400_000

    /// The most a PDF may be: what an empty chat holds once it is base64 (a third larger): 15 MB.
    static var pdfLimit: Int { QCImages.chatCap / 4 * 3 }

    // MARK: what a file is

    enum Kind: Equatable {
        case image
        case pdf
        case text
        /// Not read: its extension (".docx"), or its name when it has none.
        case unsupported(String)
    }

    /// Text-like files by extension, which wins over the file's type (".ts" is TypeScript here, not video).
    static let textExtensions: Set<String> = [
        "txt", "text", "md", "markdown", "csv", "tsv", "json", "jsonl", "yaml", "yml", "xml", "html", "htm", "log",
        "swift", "py", "js", "mjs", "cjs", "ts", "tsx", "jsx", "go", "rs", "java", "kt", "kts", "c", "h", "cc", "cpp", "cxx",
        "hpp", "m", "mm", "rb", "sh", "zsh", "bash", "sql", "toml", "ini", "cfg", "conf", "css", "scss", "php", "lua", "r",
        "tex", "vue", "svelte", "gradle", "properties", "env", "diff", "patch", "scala", "hs", "dart", "cs", "fs", "ps1", "jsonc",
        "json5", "rst", "adoc", "org", "asm", "tcl", "vb", "ex", "exs", "clj", "cljs", "elm", "erl", "zig", "nim", "pl", "pm",
        "bat", "cmd", "srt", "vtt", "ics", "vcf", "graphql", "gql", "proto", "tf", "hcl", "ipynb", "plist", "strings",
    ]

    /// What a file is for the chat: by extension for the usual text and code, else by its type (a PDF, a picture, anything
    /// that conforms to public.text or public.source-code), else not read.
    static func classify(_ url: URL) -> Kind {
        let ext = url.pathExtension.lowercased()
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { return .unsupported(url.lastPathComponent) }
        if textExtensions.contains(ext) { return .text }
        if ext == "pdf" { return .pdf }
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType ?? UTType(filenameExtension: ext)
        if let t = type {
            if t.conforms(to: .pdf) { return .pdf }
            if t.conforms(to: .image) { return .image }
            // rich text is markup, not the words
            if (t.conforms(to: .text) || t.conforms(to: .sourceCode)) && !t.conforms(to: .rtf) && !t.conforms(to: .rtfd) { return .text }
        }
        return .unsupported(ext.isEmpty ? url.lastPathComponent : "." + ext)
    }

    // MARK: making one

    /// Why a file wasn't taken, in the line that says so.
    enum Refusal: Error, Equatable {
        case notUTF8(String)
        case tooLarge(String, size: Int, limit: Int)
        case tooLong(String, pages: Int, limit: Int)
        case locked(String)
        case empty(String)
        case unreadable(String)

        var sentence: String {
            switch self {
            case .notUTF8(let n): return "\(QCFiles.short(n)) isn't UTF-8 text; cl_quick can't read it yet."
            case .tooLarge(let n, let size, let limit): return "\(QCFiles.short(n)) is too large: \(QCFiles.bytes(size)), up to \(QCFiles.bytes(limit))."
            case .tooLong(let n, let pages, let limit): return "\(QCFiles.short(n)) is too long: \(pages) pages, up to \(limit)."
            case .locked(let n): return "\(QCFiles.short(n)) is password-protected."
            case .empty(let n): return "\(QCFiles.short(n)) is empty."
            case .unreadable(let n): return "\(QCFiles.short(n)) couldn't be read."
            }
        }
    }

    /// Opens `url` (a link is followed) for reading only when what it names is a regular file: a link to /dev/zero, a pipe
    /// or a socket would be read forever or block, and a link's own size says nothing of its target's. Opened without
    /// blocking and looked at through the descriptor itself (fstat), so there is no gap between the look and the read.
    /// Returns the descriptor and the file's size, or nil when it isn't a regular file or can't be opened.
    static func openRegular(_ url: URL) -> (fd: Int32, size: Int)? {
        let fd = open(url.path, O_RDONLY | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { close(fd); return nil }
        return (fd, Int(st.st_size))
    }

    /// Whether `url` names a regular file (links followed), without reading it.
    static func isRegularFile(_ url: URL) -> Bool {
        guard let f = openRegular(url) else { return false }
        close(f.fd)
        return true
    }

    /// Reads and checks one PDF or text file, in memory. Off the main thread is fine (a large PDF takes a moment).
    static func prepare(_ url: URL) -> Result<QCFile, Refusal> {
        let name = url.lastPathComponent
        let kind = classify(url)
        guard kind == .pdf || kind == .text else { return .failure(.unreadable(name)) }
        guard let f = openRegular(url) else { return .failure(.unreadable(name)) }
        let handle = FileHandle(fileDescriptor: f.fd, closeOnDealloc: true)
        let limit = kind == .pdf ? pdfLimit : maxTextBytes
        // refused before it is read: what is over the limit is never loaded
        guard f.size <= limit else { return .failure(.tooLarge(name, size: f.size, limit: limit)) }
        // at most one byte past the limit is ever read, whatever the file does meanwhile
        guard let data = try? handle.read(upToCount: limit + 1) else { return .failure(.unreadable(name)) }
        guard data.count <= limit else { return .failure(.tooLarge(name, size: data.count, limit: limit)) }
        return kind == .pdf ? pdf(data, name: name) : text(data, name: name)
    }

    static func pdf(_ data: Data, name: String) -> Result<QCFile, Refusal> {
        guard data.count <= pdfLimit else { return .failure(.tooLarge(name, size: data.count, limit: pdfLimit)) }
        guard data.starts(with: Array("%PDF".utf8)) || data.prefix(1024).range(of: Data("%PDF".utf8)) != nil,
              let doc = PDFDocument(data: data), doc.pageCount > 0 else { return .failure(.unreadable(name)) }
        // locked: it needs a password to open. One that only restricts (an owner password: no printing, copying) opens
        // for anyone, and the API reads it (tried against Claude Code 2.1.318, 2026-11-13), so it is sent.
        if doc.isLocked { return .failure(.locked(name)) }
        guard doc.pageCount <= maxPDFPages else { return .failure(.tooLong(name, pages: doc.pageCount, limit: maxPDFPages)) }
        let n = doc.pageCount
        return .success(QCFile(name: name, style: .pdf, payload: QuickChatDocumentData(title: name, source: .pdf(data)), pages: n,
                               size: (data.count + 2) / 3 * 4, detail: n == 1 ? "1 page" : "\(n) pages"))
    }

    static func text(_ data: Data, name: String) -> Result<QCFile, Refusal> {
        guard data.count <= maxTextBytes else { return .failure(.tooLarge(name, size: data.count, limit: maxTextBytes)) }
        // a NUL byte is a binary file; text that isn't UTF-8 (UTF-16, a legacy encoding) isn't read as guesswork
        guard !data.contains(0), var s = String(data: data, encoding: .utf8) else { return .failure(.notUTF8(name)) }
        if s.hasPrefix("\u{FEFF}") { s.removeFirst() }
        guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .failure(.empty(name)) }
        let ext = (name as NSString).pathExtension.lowercased()
        let bytes = s.utf8.count
        return .success(QCFile(name: name, style: ext == "csv" || ext == "tsv" ? .table : .text,
                               payload: QuickChatDocumentData(title: name, source: .text(s)), pages: nil, size: bytes, detail: Self.bytes(bytes)))
    }

    // MARK: words

    /// "12 B", "3.4 KB", "15 MB": decimal units, one decimal under ten, the same in every language.
    static func bytes(_ n: Int) -> String {
        if n < 1000 { return "\(n) B" }
        var v = Double(n) / 1000
        var unit = "KB"
        if v >= 1000 { v /= 1000; unit = "MB" }
        if v >= 1000 { v /= 1000; unit = "GB" }
        let s = v >= 10 ? String(format: "%.0f", v) : String(format: "%.1f", v)
        return (s.hasSuffix(".0") ? String(s.dropLast(2)) : s) + " " + unit
    }

    /// A name for a line of words: a long one keeps its start and its end (and its extension).
    static func short(_ name: String, limit: Int = 32) -> String {
        guard name.count > limit else { return name }
        let keep = limit - 1, head = keep * 2 / 3, tail = keep - head
        return String(name.prefix(head)) + "…" + String(name.suffix(tail))
    }

    /// The line for files that can't be read: "cl_quick can't read .docx files yet." (a name when there is no extension).
    static func unsupportedLine(_ tokens: [String]) -> String? {
        var exts: [String] = [], names: [String] = []
        for t in tokens {
            if t.hasPrefix("."), t.count > 1 { if !exts.contains(t) { exts.append(t) } }
            else if !names.contains(t) { names.append(t) }
        }
        func list(_ a: [String]) -> String {
            a.count <= 1 ? (a.first ?? "") : a.dropLast().joined(separator: ", ") + " and " + a[a.count - 1]
        }
        var parts: [String] = []
        if !exts.isEmpty { parts.append(list(exts) + " files") }
        if !names.isEmpty { parts.append(list(names.map { short($0) })) }
        return parts.isEmpty ? nil : "cl_quick can't read " + parts.joined(separator: " and ") + " yet."
    }
}

enum QCAttach {
    /// The one line that says what was left out (QCNote), or nil. `files`: files are among the attachments, so the words
    /// say "attachments" where the images' own line says "images".
    static func note(unsupported: [String] = [], failures: [QCImages.Failure] = [], refusals: [QCFiles.Refusal] = [],
                     overCount: Int = 0, chatFull: Bool = false, pagesFull: Bool = false, textFull: Bool = false,
                     files: Bool = false) -> String? {
        var parts: [String] = []
        if let u = QCFiles.unsupportedLine(unsupported) { parts.append(u) }
        if failures.contains(.notAnImage) && unsupported.isEmpty { parts.append("That isn't an image Claude can read.") }
        if failures.contains(.unreadable) { parts.append("An image couldn't be read.") }
        if failures.contains(.tooManyPixels) { parts.append("An image has too many pixels to read (over 100 megapixels).") }
        if failures.contains(.tooLarge) { parts.append("An image was too large to send, even scaled down.") }
        // a few files at most are named: the line is one muted line, not a report
        for r in refusals.prefix(2) { parts.append(r.sentence) }
        if refusals.count > 2 { parts.append("\(refusals.count - 2) more couldn't be attached.") }
        let word = files ? "attachments" : "images"
        let max = QCImages.maxCount
        if overCount > 0 { parts.append("Up to \(max) \(word) go with a message; \(overCount == 1 ? "one was" : "\(overCount) were") left out.") }
        if chatFull { parts.append("This chat holds as many \(word) as it can; start a new chat (⌘N) for more.") }
        if pagesFull { parts.append("This chat holds up to \(QCFiles.maxChatPages) PDF pages; start a new chat (⌘N) for more.") }
        if textFull { parts.append("This chat holds up to \(QCFiles.bytes(QCFiles.maxChatText)) of text files; start a new chat (⌘N) for more.") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// The attachments of a message in the order they were attached, as the engine takes them.
    static func payloads(images: [QCImage], files: [QCFile]) -> [QuickChatAttachment] {
        var all: [(order: Int, at: Int, item: QuickChatAttachment)] = []
        for (i, img) in images.enumerated() { all.append((img.order, i, .image(img.payload))) }
        for (i, f) in files.enumerated() { all.append((f.order, images.count + i, .document(f.payload))) }
        return all.sorted { ($0.order, $0.at) < ($1.order, $1.at) }.map(\.item)
    }
}
