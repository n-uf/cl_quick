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

/// The images attached to the message being written, in a row over the field; each can be removed.
struct QCAttachRow: View {
    @ObservedObject var model: QuickChatModel
    /// A thumbnail's side.
    static let tile: CGFloat = 44

    var body: some View {
        if !model.images.isEmpty || model.preparing > 0 {
            HStack(spacing: 8) {
                ForEach(model.images) { img in
                    QCImageTile(image: img)
                        .overlay(alignment: .topTrailing) { remove(img) }
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
    /// disc with the cross, and the pointing hand.
    private func remove(_ img: QCImage) -> some View {
        Button { model.removeImage(img.id) } label: {
            Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundColor(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.black.opacity(0.72)))
                .frame(width: 24, height: 24)
                .qcControl()
        }
        .buttonStyle(.plain)
        .qcPointingHand()
        .help("Remove")
        .accessibilityLabel("Remove image")
    }
}

/// A sent message's images in the chat, small, right-aligned above its bubble like the bubble itself.
struct QCSentImages: View {
    let images: [QCImage]
    static let side: CGFloat = 44
    var body: some View {
        HStack(spacing: 4) {
            ForEach(images) { QCImageTile(image: $0, side: Self.side) }
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
