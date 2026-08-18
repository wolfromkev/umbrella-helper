import SwiftUI

extension View {
    func popupPillShadow() -> some View {
        compositingGroup()
            .shadow(color: .black.opacity(0.34), radius: 26, x: 0, y: 12)
            .shadow(color: .black.opacity(0.14), radius: 8, x: 0, y: 3)
    }
}

struct PopupPillBackground: View {
    var cornerRadius: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(nsColor: NSColor(calibratedWhite: 0.12, alpha: 0.94)))
    }
}

struct SettingsToolbarButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: NSColor(calibratedWhite: 0.22, alpha: 0.95)))
                )
        }
        .buttonStyle(.plain)
        .help("Settings")
    }
}
