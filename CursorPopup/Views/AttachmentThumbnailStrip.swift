import SwiftUI

struct AttachmentThumbnailStrip: View {
    let attachments: [PendingAttachment]
    let onRemove: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    ZStack(alignment: .topTrailing) {
                        Image(nsImage: attachment.thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        Button {
                            onRemove(attachment.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Color.black.opacity(0.65)))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 6, y: -6)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 58)
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
