// FileViews: an attached file's chip (Attachments.swift), over the field next to the pictures' thumbnails and in a sent
// message in the chat. The same height as a thumbnail (44 pt) and the same rounded outline, so a row of pictures and
// files is one height whatever it holds.

import AppKit
import SwiftUI

/// One file: its symbol, its name (cut in the middle when long, so the extension stays) and under it its page count or
/// size. Narrower when the name is short; several share the row and give each other room down to `minWidth`.
struct QCFileChip: View {
    let file: QCFile
    static let minWidth: CGFloat = 84
    static let maxWidth: CGFloat = 200

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: file.symbol).font(.system(size: 17, weight: .regular)).foregroundColor(QCColor.soft).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name).font(.system(size: 12, weight: .medium)).foregroundColor(QCColor.text)
                    .lineLimit(1).truncationMode(.middle)
                Text(file.detail).font(.system(size: 11)).foregroundColor(QCColor.muted).lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .frame(minWidth: Self.minWidth, maxWidth: Self.maxWidth, minHeight: QCAttachRow.tile, maxHeight: QCAttachRow.tile, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(QCColor.hover))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(QCColor.line))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Attached file \(file.name), \(file.detail)")
    }
}
