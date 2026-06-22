import SwiftUI

private enum AttachmentThumbnailMetrics {
    static let width: CGFloat = 72
    static let height: CGFloat = 52
    static let removeButtonSize: CGFloat = 18
    /// Room for the remove badge to sit on the corner without using offset (offset breaks hit testing).
    static let removeButtonBleed: CGFloat = 6
    static let cellWidth = width + removeButtonBleed
    static let cellHeight = height + removeButtonBleed
}

private struct AttachmentThumbnailCell: View {
    let attachment: PendingAttachment
    let onRemove: () -> Void

    var body: some View {
        Color.clear
            .frame(
                width: AttachmentThumbnailMetrics.cellWidth,
                height: AttachmentThumbnailMetrics.cellHeight
            )
            .overlay(alignment: .bottomLeading) {
                Image(nsImage: attachment.thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: AttachmentThumbnailMetrics.width,
                        height: AttachmentThumbnailMetrics.height
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .overlay(alignment: .topTrailing) {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(
                            width: AttachmentThumbnailMetrics.removeButtonSize,
                            height: AttachmentThumbnailMetrics.removeButtonSize
                        )
                        .background(Circle().fill(Color.black.opacity(0.65)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Remove image")
            }
    }
}

struct AttachmentThumbnailStrip: View {
    let attachments: [PendingAttachment]
    let onRemove: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    AttachmentThumbnailCell(attachment: attachment) {
                        onRemove(attachment.id)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: AttachmentThumbnailMetrics.cellHeight)
    }
}

struct MessageImageStrip: View {
    let imagePaths: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(imagePaths, id: \.self) { path in
                if let image = NSImage(contentsOfFile: path) {
                    Image(nsImage: AttachmentStore.makeThumbnail(image, maxSide: 96))
                        .resizable()
                        .scaledToFill()
                        .frame(width: 96, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }
}

struct PromptInputShell<Content: View>: View {
    let attachments: [PendingAttachment]
    let onRemoveAttachment: (UUID) -> Void
    var showsBackground: Bool = true
    var horizontalPadding: CGFloat = 18
    var verticalPadding: CGFloat = 14
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !attachments.isEmpty {
                AttachmentThumbnailStrip(attachments: attachments, onRemove: onRemoveAttachment)
            }
            content()
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, attachments.isEmpty ? verticalPadding : 12)
        .background {
            if showsBackground {
                PopupPillBackground(cornerRadius: 22)
            }
        }
    }
}
