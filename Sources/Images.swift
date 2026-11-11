// Images: pictures attached to a quick chat message. Pasted (⌘V with an image on the pasteboard, or image files copied in
// Finder) or dropped on the panel; they sit as thumbnails over the field until the message is sent, go to Claude Code as
// image blocks in the same stream-json line as the text, and show in the chat as thumbnails of the message.
//
// Incognito: an image lives only in memory, from the pasteboard to the process's pipe and the chat's turn: no temp
// file, no cache, nothing for the app's folder. An image file that is dropped or copied is only read, never copied.
// Each is scaled down in memory to at most 1568 px on its long side (what Claude reads anyway: bigger only costs time)
// and encoded as PNG, or as JPEG at 0.85 when it is a photo and PNG would be large, to stay under 3.75 MB of base64.

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

    init(payload: QuickChatImageData, thumbnail: NSImage, pixels: CGSize) {
        self.payload = payload; self.thumbnail = thumbnail; self.pixels = pixels
    }
    static func == (a: QCImage, b: QCImage) -> Bool { a.id == b.id }
}

enum QCImages {
    /// At most this many images go with one message.
    static let maxCount = 5
    /// The longest side sent, in pixels.
    static let maxSide = 1568
    /// An image's base64 stays under this many bytes (the API's limit is 5 MB; this leaves room).
    static let maxBase64 = 3_750_000
    /// A PNG over this many bytes is tried as a JPEG too, when the picture has no transparency.
    static let largePNG = 1_000_000
    static let jpegQuality = 0.85
    static let thumbnailPixels = 168

    // MARK: what a pasteboard holds

    /// Where an image comes from: its bytes (a screenshot copied, a picture dragged out of a page), or a file.
    enum Source {
        case data(Data)
        case file(URL)
    }

    /// What a paste or a drop holds for the chat: the images, and the names of files that are not images.
    struct Found {
        var sources: [Source] = []
        var notImages: [String] = []
    }

    /// The types an image travels as on a pasteboard, best first (a screenshot is PNG; Preview and browsers give TIFF).
    static let dataTypes: [NSPasteboard.PasteboardType] = [.png, NSPasteboard.PasteboardType("public.jpeg"), .tiff,
                                                           NSPasteboard.PasteboardType("public.heic")]

    private static func isImageFile(_ url: URL) -> Bool {
        guard let t = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType else {
            return UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
        }
        return t.conforms(to: .image)
    }

    /// What the pasteboard holds for the chat, or nil when it holds nothing the chat takes.
    ///
    /// Files come first (Finder gives the file's name as text too): image files are taken, and the others named, so the
    /// drop says why they weren't. Then, for a paste (not a drop), text wins over a picture: a spreadsheet's cells and a
    /// page's selection come with a picture of themselves, and the field must paste the words. Then picture data.
    /// A paste of only non-image files is the field's own (it pastes their names).
    static func found(in pb: NSPasteboard, forPaste: Bool) -> Found? {
        var f = Found()
        let urls = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if !urls.isEmpty {
            for u in urls {
                if isImageFile(u) { f.sources.append(.file(u)) } else { f.notImages.append(u.lastPathComponent) }
            }
            if f.sources.isEmpty && forPaste { return nil }
            return f
        }
        if forPaste, let s = pb.string(forType: .string), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        for item in pb.pasteboardItems ?? [] {
            for t in dataTypes {
                if let d = item.data(forType: t), !d.isEmpty { f.sources.append(.data(d)); break }
            }
        }
        return f.sources.isEmpty ? nil : f
    }

    /// Whether a drag carries something for the chat: files, or picture data (cheap: only the types are looked at, as it is
    /// asked for every move of the pointer). Dropped text is the field's own.
    static func isImageDrag(_ pb: NSPasteboard) -> Bool {
        let types = pb.types ?? []
        return types.contains(.fileURL) || dataTypes.contains { types.contains($0) }
    }

    // MARK: making one

    /// Why an image wasn't taken.
    enum Failure: Error, Equatable {
        case notAnImage
        case unreadable
        case tooLarge
    }

    /// Reads, scales down and encodes one image, in memory. Off the main thread is fine.
    static func prepare(_ source: Source) -> Result<QCImage, Failure> {
        let data: Data
        switch source {
        case .data(let d): data = d
        case .file(let u):
            guard let d = try? Data(contentsOf: u, options: [.mappedIfSafe]) else { return .failure(.unreadable) }
            data = d
        }
        return prepare(data)
    }

    static func prepare(_ data: Data) -> Result<QCImage, Failure> {
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, opts), CGImageSourceGetCount(src) > 0,
              let typeID = CGImageSourceGetType(src), let type = UTType(typeID as String), type.conforms(to: .image),
              !type.conforms(to: .pdf) else { return .failure(.notAnImage) }
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int, w > 0, h > 0
        else { return .failure(.unreadable) }
        let hasAlpha = props[kCGImagePropertyHasAlpha] as? Bool ?? false
        var side = min(maxSide, max(w, h))          // never larger than it is
        for _ in 0..<7 {
            guard let cg = scaled(src, side) else { return .failure(.unreadable) }
            if let e = encode(cg, hasAlpha: hasAlpha) {
                let pixels = CGSize(width: cg.width, height: cg.height)
                guard let thumb = scaled(src, min(thumbnailPixels, max(w, h))) else { return .failure(.unreadable) }
                let img = NSImage(cgImage: thumb, size: NSSize(width: thumb.width, height: thumb.height))
                return .success(QCImage(payload: e, thumbnail: img, pixels: pixels))
            }
            side = Int(Double(side) * 0.75)
            if side < 128 { break }
        }
        return .failure(.tooLarge)
    }

    /// The image at index 0 with its long side `side` pixels at most (never enlarged), turned upright by its orientation.
    private static func scaled(_ src: CGImageSource, _ side: Int) -> CGImage? {
        let o: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                  kCGImageSourceShouldCacheImmediately: true, kCGImageSourceThumbnailMaxPixelSize: side]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, o as CFDictionary)
    }

    /// PNG when it is small enough; for a picture without transparency, JPEG at 0.85 when PNG is large (and smaller than
    /// it). A picture with transparency stays PNG until it is scaled down far enough. nil: too big as either.
    private static func encode(_ cg: CGImage, hasAlpha: Bool) -> QuickChatImageData? {
        func fits(_ d: Data) -> Bool { (d.count + 2) / 3 * 4 <= maxBase64 }
        let png = encode(cg, type: .png, quality: nil)
        if let png, png.count <= largePNG { return QuickChatImageData(mediaType: "image/png", data: png) }
        if !hasAlpha, let jpeg = encode(cg, type: .jpeg, quality: jpegQuality), png == nil || jpeg.count < png!.count {
            if fits(jpeg) { return QuickChatImageData(mediaType: "image/jpeg", data: jpeg) }
        }
        if let png, fits(png) { return QuickChatImageData(mediaType: "image/png", data: png) }
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

    // MARK: what is said

    /// The one line that says what was left out (QCNote), or nil.
    static func note(notImages: [String], failures: [Failure], overCount: Int) -> String? {
        var parts: [String] = []
        if notImages.count == 1 { parts.append("Only images can be attached; \(notImages[0]) isn't one.") }
        else if notImages.count > 1 { parts.append("Only images can be attached; \(notImages.count) of those files aren't.") }
        if failures.contains(.notAnImage) && notImages.isEmpty { parts.append("That isn't an image Claude can read.") }
        if failures.contains(.unreadable) { parts.append("An image couldn't be read.") }
        if failures.contains(.tooLarge) { parts.append("An image was too large to send, even scaled down.") }
        if overCount > 0 { parts.append("Up to \(maxCount) images go with a message; \(overCount == 1 ? "one was" : "\(overCount) were") left out.") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
