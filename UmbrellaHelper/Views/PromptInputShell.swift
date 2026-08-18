import SwiftUI

struct PromptInputShell<Content: View>: View {
    var showsBackground: Bool = true
    var horizontalPadding: CGFloat = 18
    var verticalPadding: CGFloat = 14
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background {
            if showsBackground {
                PopupPillBackground(cornerRadius: 22)
            }
        }
    }
}
