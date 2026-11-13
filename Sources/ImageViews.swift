// ImageViews: the attached images' thumbnails over the field (each with a ✕), and a sent message's images in the chat.
// The row is one fixed height whatever it holds (one tile or five, or the tiles of images still being read), so the bar
// grows once, when the first image comes, and never again as more are added.

import AppKit
import SwiftUI

/// One thumbnail: the picture filled into a rounded square.
struct QCImageTile: View {
    let image: QCImage
    var side: CGFloat = QCAttachRow.tile
    var body: some View {
        Image(nsImage: image.thumbnail).resizable().scaledToFill()
            .frame(width: side, height: side).clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(QCColor.line))
            .accessibilityLabel("Attached image")
    }
}

/// A picture or a file of a message, in the order they were attached.
enum QCAttachItem: Identifiable {
    case image(QCImage)
    case file(QCFile)
    var id: UUID { switch self { case .image(let i): return i.id; case .file(let f): return f.id } }
    var order: Int { switch self { case .image(let i): return i.order; case .file(let f): return f.order } }

    static func all(images: [QCImage], files: [QCFile]) -> [QCAttachItem] {
        let items = images.map { QCAttachItem.image($0) } + files.map { QCAttachItem.file($0) }
        return items.enumerated().sorted { ($0.element.order, $0.offset) < ($1.element.order, $1.offset) }.map(\.element)
    }
}

/// The pictures and files attached to the message being written, in a row over the field; each can be removed.
struct QCAttachRow: View {
    @ObservedObject var model: QuickChatModel
    /// A thumbnail's side (and a file chip's height).
    static let tile: CGFloat = 44

    var body: some View {
        if !model.images.isEmpty || !model.files.isEmpty || model.preparing > 0 {
            HStack(spacing: 8) {
                ForEach(QCAttachItem.all(images: model.images, files: model.files)) { item in
                    switch item {
                    case .image(let img):
                        QCImageTile(image: img).overlay(alignment: .topTrailing) { remove(img) }
                    case .file(let file):
                        // the ✕ sits half over the chip's corner, off its text
                        QCFileChip(file: file)
                            .overlay(alignment: .topTrailing) { QCRemoveImageButton(label: "Remove file") { model.removeFile(file.id) }.offset(x: 6, y: -6) }
                    }
                }
                ForEach(0..<model.preparing, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(QCColor.hover)
                        .frame(width: Self.tile, height: Self.tile)
                        .overlay(Group { if #available(macOS 13, *) { ProgressView().controlSize(.small) } })
                }
                Spacer(minLength: 0)
            }
            .frame(height: Self.tile)
        }
    }

    /// The ✕ in a tile's corner: a 24 pt target (the whole of it takes the press, never the window's drag), a small dark
    /// disc with the cross, and the pointing hand. Built like the other icon buttons (QCIconButton: the control marker in
    /// the label, the hand and the hover on the button).
    private func remove(_ img: QCImage) -> some View { QCRemoveImageButton { model.removeImage(img.id) } }
}

struct QCRemoveImageButton: View {
    var label = "Remove image"
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundColor(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.black.opacity(hover ? 0.9 : 0.72)))
                .frame(width: 24, height: 24)
                .qcControl()
        }
        .buttonStyle(.plain)
        .qcPointingHand()
        .onHover { hover = $0 }
        .help("Remove")
        .accessibilityLabel(label)
    }
}

/// A sent message's pictures and files in the chat, small, right-aligned above its bubble like the bubble itself (their
/// chips, never what is in them).
struct QCSentAttachments: View {
    let images: [QCImage]
    let files: [QCFile]
    static let side: CGFloat = 44
    var body: some View {
        HStack(spacing: 4) {
            ForEach(QCAttachItem.all(images: images, files: files)) { item in
                switch item {
                case .image(let img): QCImageTile(image: img, side: Self.side)
                case .file(let file): QCFileChip(file: file)
                }
            }
        }
    }
}

extension View {
    /// The card outlined in Claude's clay while a drag with images is over the panel (it takes no press).
    func qcDropOutline(_ on: Bool, corner: CGFloat) -> some View {
        overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(QCColor.accent, lineWidth: 2)
            .opacity(on ? 1 : 0).allowsHitTesting(false))
    }
}
