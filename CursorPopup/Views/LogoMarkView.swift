import SwiftUI

struct LogoMarkView: View {
    var size: CGFloat = 22

    var body: some View {
        Image("LogoMark")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: size * 0.08, y: size * 0.04)
    }
}
