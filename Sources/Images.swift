// Images: pictures attached to a quick chat message. Pasted (⌘V with an image on the pasteboard, or image files copied in
// Finder) or dropped on the panel; they sit as thumbnails over the field until the message is sent, go to Claude Code as
// image blocks in the same stream-json line as the text, and show in the chat as thumbnails of the message. PDFs and
// text files attach the same way (Attachments.swift); the paste and drop rules here sort a pasteboard's contents for both.
//
// Incognito: an image lives only in memory, from the pasteboard to the process's pipe and the chat's turn: no temp
// file, no cache, nothing for the app's folder. An image file that is dropped or copied is only read, never copied.
// Each is scaled down in memory to at most 1568 px on its long side (what Claude reads anyway: bigger only costs time)
// and encoded as PNG, or as JPEG at 0.85 (transparency flattened onto white) when PNG is over about 1 MB of base64. The
// pictures stay in the conversation, so a chat holds at most about 20 MB of them (the API takes 32 MB a request).

import AppKit
import ImageIO
import UniformTypeIdentifiers

/// One attached image: the bytes that are sent, and a small picture of them. In memory only.
final class QCImage: Identifiable, Equatable {
    let id = UUID()
    let payload: QuickChatImageData
    /// What is drawn (a few times the size of its tile, so a small tile stays sharp).
    let thumbnail: NSImage
    /// The size that is sent, in pixels.
    let pixels: CGSize
    /// What it adds to a request: its bytes as base64.
    var base64Size: Int { (payload.data.count + 2) / 3 * 4 }
    /// Where it came in among the attachments (images and files share one order: the message lists them in it).
    var order = 0

    init(payload: QuickChatImageData, thumbnail: NSImage, pixels: CGSize) {
        self.payload = payload; self.thumbnail = thumbnail; self.pixels = pixels
    }
    static func == (a: QCImage, b: QCImage) -> Bool { a.id == b.id }
}

enum QCImages {
    /// At most this many attachments (pictures and files together, Attachments.swift) go with one message.
    static let maxCount = 5
    /// The longest side sent, in pixels.
    static let maxSide = 1568
    /// An image's base64 stays under this many bytes: Claude reduces a picture to about 1.15 MP anyway, and every image
    /// stays in the conversation for the rest of the chat.
    static let maxBase64 = 1_000_000
    /// The images one chat holds (its process's conversation), in bytes of base64: the API refuses a request over 32 MB,
    /// and the whole conversation is in every request.
    static let chatCap = 20_000_000
    /// A picture file of more bytes than this is refused unread (a 100-megapixel JPEG or HEIC is well under it; an uncompressed one of that size isn't).
    static let maxFileBytes = 256_000_000
    /// A picture of more pixels than this (width × height) is refused unread.
    static let maxPixels = 100_000_000
    static let jpegQuality = 0.85
    static let thumbnailPixels = 168

    // MARK: what a pasteboard holds

    /// Where an image comes from: its bytes (a screenshot copied, a picture dragged out of a page), or a file.
    enum Source {
        case data(Data)
        case file(URL)
    }

    /// What a paste or a drop holds for the chat, in the order it came: images, PDF and text files, and what can't be read
    /// (an extension, or a name when there is none: ".docx").
    struct Found {
        enum Item { case image(Source), file(URL) }
        var items: [Item] = []
        var unsupported: [String] = []

        init(items: [Item] = [], unsupported: [String] = []) { self.items = items; self.unsupported = unsupported }
        init(sources: [Source] = [], files: [URL] = [], unsupported: [String] = []) {
            self.init(items: sources.map { .image($0) } + files.map { .file($0) }, unsupported: unsupported)
        }
        var sources: [Source] { items.compactMap { if case .image(let s) = $0 { return s }; return nil } }
        var files: [URL] { items.compactMap { if case .file(let u) = $0 { return u }; return nil } }
    }

    /// The types an image travels as on a pasteboard, best first (a screenshot is PNG; Preview and browsers give TIFF).
    static let dataTypes: [NSPasteboard.PasteboardType] = [.png, NSPasteboard.PasteboardType("public.jpeg"), .tiff,
                                                           NSPasteboard.PasteboardType("public.heic")]

    /// What the pasteboard holds for the chat, or nil when it holds nothing the chat takes.
    ///
    /// Files come first (Finder gives the file's name as text too): image files, PDFs and text-like files are taken
    /// (QCFiles.classify), and the others named, so the drop says why they weren't. Then, for a paste (not a drop), text
    /// wins over a picture: a spreadsheet's cells and a page's selection come with a picture of themselves, and the field
    /// must paste the words. Then picture data. A paste of only files the chat can't take is the field's own (it pastes
    /// their names).
    static func found(in pb: NSPasteboard, forPaste: Bool) -> Found? {
        var f = Found()
        let urls = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if !urls.isEmpty {
            for u in urls {
                switch QCFiles.classify(u) {
                case .image: f.items.append(.image(.file(u)))
                case .pdf, .text: f.items.append(.file(u))
                case .unsupported(let token): f.unsupported.append(token)
                }
            }
            if f.items.isEmpty && forPaste { return nil }
            return f
        }
        if forPaste, let s = pb.string(forType: .string), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        for item in pb.pasteboardItems ?? [] {
            for t in dataTypes {
                if let d = item.data(forType: t), !d.isEmpty { f.items.append(.image(.data(d))); break }
            }
        }
        return f.items.isEmpty ? nil : f
    }

    /// Whether a drag carries something for the chat: files, or picture data (cheap: only the types are looked at, as it is
    /// asked for every move of the pointer). Dropped text is the field's own.
    static func isImageDrag(_ pb: NSPasteboard) -> Bool {
        let types = pb.types ?? []
        return types.contains(.fileURL) || dataTypes.contains { types.contains($0) }
    }

    /// Whether the text field keeps a drop for itself: text with no files (the paste rule: a selection dragged out of Word,
    /// Excel, Numbers or Pages comes with a picture of itself, and the field must take the words). Files of any kind are
    /// the chat's, as are pictures: it takes the ones it can read and says why it left the others (a drop of only
    /// files it can't read used to insert their paths in the field; it names them as refused now).
    static func fieldKeepsDrop(_ pb: NSPasteboard) -> Bool {
        let urls = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if !urls.isEmpty { return false }
        return (pb.types ?? []).contains(.string)
    }

    // MARK: making one

    /// Why an image wasn't taken.
    enum Failure: Error, Equatable {
        case notAnImage
        case unreadable
        case tooLarge
        /// More than `maxPixels`: refused before it is decoded.
        case tooManyPixels
    }

    /// Reads, scales down and encodes one image, in memory. Off the main thread is fine.
    static func prepare(_ source: Source) -> Result<QCImage, Failure> {
        let data: Data
        switch source {
        case .data(let d): data = d
        case .file(let u):
            // only a regular file (a link to one is followed): a link to /dev/zero or a pipe would be read forever. Its size
            // is looked at before anything is read (a picture file over `maxFileBytes` is refused unread: on a network or
            // removable volume reading it would take minutes), and it is read from the descriptor that was looked at.
            guard let f = QCFiles.openRegular(u) else { return .failure(.unreadable) }
            let handle = FileHandle(fileDescriptor: f.fd, closeOnDealloc: true)
            guard f.size <= maxFileBytes else { return .failure(.tooLarge) }
            let d: Data
            do { d = try handle.read(upToCount: maxFileBytes + 1) ?? Data() } catch { return .failure(.unreadable) }
            guard d.count <= maxFileBytes else { return .failure(.tooLarge) }
            data = d
        }
        return prepare(data)
    }

    static func prepare(_ data: Data) -> Result<QCImage, Failure> {
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, opts), CGImageSourceGetCount(src) > 0,
              let typeID = CGImageSourceGetType(src), let type = UTType(typeID as String), type.conforms(to: .image),
              !type.conforms(to: .pdf) else { return .failure(.notAnImage) }
        // the file's primary image: not always the first (a HEIC may lead with a thumbnail or an auxiliary picture)
        let index = CGImageSourceGetPrimaryImageIndex(src)
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, index, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int, w > 0, h > 0
        else { return .failure(.unreadable) }
        // refused before any decoding: a picture this large would take a gigabyte or more of memory to read
        guard w * h <= maxPixels else { return .failure(.tooManyPixels) }
        // decoded once, at the size that is sent; the smaller passes and the thumbnail are drawn from that
        var side = min(maxSide, max(w, h))          // never larger than it is
        guard let base = scaled(src, index, side) else { return .failure(.unreadable) }
        for _ in 0..<7 {
            guard let cg = resized(base, side: side) else { return .failure(.unreadable) }
            if let e = encode(cg) {
                let pixels = CGSize(width: cg.width, height: cg.height)
                guard let thumb = resized(base, side: thumbnailPixels) else { return .failure(.unreadable) }
                let img = NSImage(cgImage: thumb, size: NSSize(width: thumb.width, height: thumb.height))
                return .success(QCImage(payload: e, thumbnail: img, pixels: pixels))
            }
            side = Int(Double(side) * 0.75)
            if side < 128 { break }
        }
        return .failure(.tooLarge)
    }

    /// `cg` with its long side `side` pixels at most (never enlarged), drawn at high quality; `cg` itself when it is that
    /// small already. Keeps an alpha channel only when it has one.
    private static func resized(_ cg: CGImage, side: Int) -> CGImage? {
        let long = max(cg.width, cg.height)
        guard long > side, side > 0 else { return cg }
        let k = Double(side) / Double(long)
        let w = max(1, Int((Double(cg.width) * k).rounded())), h = max(1, Int((Double(cg.height) * k).rounded()))
        let alpha: Bool
        switch cg.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: alpha = false
        default: alpha = true
        }
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast).rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// The image at `index` with its long side `side` pixels at most (never enlarged), turned upright by its orientation.
    private static func scaled(_ src: CGImageSource, _ index: Int, _ side: Int) -> CGImage? {
        let o: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                  kCGImageSourceShouldCacheImmediately: true, kCGImageSourceThumbnailMaxPixelSize: side]
        return CGImageSourceCreateThumbnailAtIndex(src, index, o as CFDictionary)
    }

    /// PNG when it fits the target; else JPEG at 0.85 (transparency flattened onto white) when that fits. nil: too big as
    /// either, so the caller scales it down further.
    private static func encode(_ cg: CGImage) -> QuickChatImageData? {
        func fits(_ d: Data) -> Bool { (d.count + 2) / 3 * 4 <= maxBase64 }
        if let png = encode(cg, type: .png, quality: nil), fits(png) { return QuickChatImageData(mediaType: "image/png", data: png) }
        if let jpeg = encode(cg, type: .jpeg, quality: jpegQuality), fits(jpeg) { return QuickChatImageData(mediaType: "image/jpeg", data: jpeg) }
        return nil
    }

    private static func encode(_ cg: CGImage, type: UTType, quality: Double?) -> Data? {
        var image = cg
        if type == .jpeg {
            // JPEG has no transparency: flattened on white
            guard let ctx = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            guard let flat = ctx.makeImage() else { return nil }
            image = flat
        }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil) else { return nil }
        var props: [CFString: Any] = [:]
        if let quality { props[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}
