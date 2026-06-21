import SwiftUI

struct LogoMarkView: View {
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.10, blue: 0.10),
                            Color(red: 0.06, green: 0.06, blue: 0.06),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            GeometricPencilShape()
                .fill(Color.white.opacity(0.92))
                .padding(size * 0.24)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: size * 0.08, y: size * 0.04)
    }
}
