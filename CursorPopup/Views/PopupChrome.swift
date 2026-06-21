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
            .fill(ChatBubbleColors.panel)
    }
}

/// Cursor-like chat bubble fills: assistant stays dark, user is a lighter grey.
enum ChatBubbleColors {
    static let panel = Color(nsColor: NSColor(calibratedWhite: 0.12, alpha: 0.94))
    static let assistant = Color(nsColor: NSColor(calibratedWhite: 0.14, alpha: 0.95))
    static let user = Color(nsColor: NSColor(calibratedWhite: 0.26, alpha: 0.95))
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

struct WorkspaceNavigatorView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Text(model.workspaceLabel)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: 96)
            .help("Current workspace folder")
    }
}

struct ThinkingIndicatorView: View {
    var size: CGFloat = 18
    var lineWidth: CGFloat = 2
    var color: Color = Color.white.opacity(0.72)

    @State private var isSpinning = false

    var body: some View {
        Circle()
            .trim(from: 0.12, to: 0.88)
            .stroke(
                color,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(isSpinning ? 360 : 0))
            .animation(
                .linear(duration: 0.85).repeatForever(autoreverses: false),
                value: isSpinning
            )
            .onAppear { isSpinning = true }
            .onDisappear { isSpinning = false }
            .accessibilityLabel("Loading")
    }
}

struct InputBarLeadingChevron: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.isBrandNewChat {
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .help("Current workspace folder")
        }
    }
}

struct InputBarTrailingIndicator: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.isBrandNewChat {
            Text(model.workspaceLabel)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: 140, alignment: .trailing)
                .padding(.horizontal, 2)
                .help("Current workspace folder")
        } else {
            VStack(alignment: .trailing, spacing: 2) {
                Text(model.historyLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 140, alignment: .trailing)
                if model.canBrowseHistory {
                    Text("↑↓ history")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary.opacity(0.7))
                }
            }
            .padding(.horizontal, 2)
        }
    }
}
