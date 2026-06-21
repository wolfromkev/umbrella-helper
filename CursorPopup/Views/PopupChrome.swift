import Combine
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

@MainActor
private final class LoadingPhaseClock: ObservableObject {
    @Published var phase: TimeInterval = 0
    private var cancellable: AnyCancellable?

    func start() {
        guard cancellable == nil else { return }
        phase = Date().timeIntervalSinceReferenceDate
        cancellable = Timer.publish(every: 1.0 / 30, tolerance: 0.01, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in
                self?.phase = date.timeIntervalSinceReferenceDate
            }
    }

    func stop() {
        cancellable?.cancel()
        cancellable = nil
    }
}

private struct AnimatedLoadingPhase<Content: View>: View {
    @StateObject private var clock = LoadingPhaseClock()
    @ViewBuilder var content: (TimeInterval) -> Content

    var body: some View {
        content(clock.phase)
            .onAppear { clock.start() }
            .onDisappear { clock.stop() }
    }
}

struct PencilPulseView: View {
    var size: CGFloat = 18
    var phase: TimeInterval

    var body: some View {
        let pulse = (sin(phase * 3) + 1) / 2

        GeometricPencilShape()
            .fill(Color.white.opacity(0.55 + pulse * 0.35))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(sin(phase * 2.5) * 6))
            .accessibilityHidden(true)
    }
}

private struct BouncingDotsView: View {
    var dotSize: CGFloat
    var dotColor: Color
    var phase: TimeInterval

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(dotColor)
                    .frame(width: dotSize, height: dotSize)
                    .offset(y: CGFloat(sin(phase * 5 + Double(index) * 1.2)) * 4)
            }
        }
        .frame(width: dotSize * 3 + 10, height: dotSize + 10)
    }
}

struct ThinkingIndicatorView: View {
    var label: String? = "Thinking…"
    var dotSize: CGFloat = 6
    var dotColor: Color = .secondary
    var showsPencil: Bool = false

    var body: some View {
        AnimatedLoadingPhase { phase in
            HStack(spacing: 10) {
                if showsPencil {
                    PencilPulseView(size: 18, phase: phase)
                }

                BouncingDotsView(dotSize: dotSize, dotColor: dotColor, phase: phase)

                if let label {
                    Text(label)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: showsPencil ? 132 : 92, minHeight: 28, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "Thinking")
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
