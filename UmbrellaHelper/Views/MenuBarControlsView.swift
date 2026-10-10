import AppKit
import SwiftUI

private enum MenuBarControlTarget: CaseIterable, Hashable {
    case screenBrightness
    case screenWarmth
}

struct MenuBarControlsView: View {
    @ObservedObject var brightnessFeature: UmbrellaBrightnessFeature
    @ObservedObject var snipFeature: UmbrellaSimpleSnipFeature
    var onOpenSettings: () -> Void
    var onRunCapture: (@escaping () -> Void) -> Void

    @State private var focusedControl: MenuBarControlTarget = .screenBrightness
    @State private var scrollCarry: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Screen", systemImage: "sun.max.fill") {
                Toggle(
                    "Automatic",
                    isOn: Binding(
                        get: { brightnessFeature.isAutoMode },
                        set: { brightnessFeature.setAutoMode($0) }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.small)

                if brightnessFeature.isAutoMode {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        let now = UmbrellaSolarSchedule.minutesOfDay(from: context.date)
                        VStack(alignment: .leading, spacing: 4) {
                            UmbrellaDayCurveView(
                                sunriseMinutes: brightnessFeature.sunriseMinutes,
                                sunsetMinutes: brightnessFeature.sunsetMinutes,
                                transitionMinutes: brightnessFeature.transitionMinutes,
                                nowMinutes: now,
                                height: 44
                            )
                            Text(
                                UmbrellaSolarSchedule.statusText(
                                    at: now,
                                    sunrise: brightnessFeature.sunriseMinutes,
                                    sunset: brightnessFeature.sunsetMinutes,
                                    transition: brightnessFeature.transitionMinutes
                                )
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        }
                    }
                }

                if !brightnessFeature.menuBarFavoritePresets.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(brightnessFeature.menuBarFavoritePresets) { preset in
                            Button(preset.name) {
                                brightnessFeature.applyPreset(id: preset.id)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help(presetHelp(preset))
                        }
                    }
                }

                labeledSlider(
                    target: .screenBrightness,
                    title: "Brightness",
                    valueText: "\(Int((brightnessFeature.brightness * 100).rounded()))%",
                    value: Binding(
                        get: { Double(brightnessFeature.brightness) },
                        set: { brightnessFeature.setBrightness(Float($0), commit: false) }
                    ),
                    range: Double(UmbrellaBrightnessFeature.minimumBrightness)...1.0,
                    step: Double(UmbrellaBrightnessFeature.brightnessStep),
                    onEditingChanged: { editing in
                        if !editing { brightnessFeature.commitPendingChanges() }
                    }
                )

                labeledSlider(
                    target: .screenWarmth,
                    title: "Warmth",
                    valueText: brightnessFeature.isDarkroom
                        ? "Blue light off"
                        : "\(brightnessFeature.colorTemp)K",
                    value: Binding(
                        get: { Double(brightnessFeature.colorTemp) },
                        set: { brightnessFeature.setColorTemp(Int($0.rounded()), commit: false) }
                    ),
                    range: 1200...6500,
                    step: Double(UmbrellaBrightnessFeature.colorTempStep),
                    enabled: !brightnessFeature.isDarkroom,
                    onEditingChanged: { editing in
                        if !editing { brightnessFeature.commitPendingChanges() }
                    }
                )

                Button("Restore display color") {
                    brightnessFeature.restoreDisplayColor()
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .help("Reset system display color, then re-apply Umbrella brightness settings.")
            }

            Divider()

            sectionHeader("SimpleSnip", systemImage: "record.circle") {
                captureRow("Snip area", shortcut: AppSettings.shared.snipAreaHotKey.displayName) {
                    snipFeature.takeAreaSnip()
                }
                captureRow("Snip window", shortcut: AppSettings.shared.snipWindowHotKey.displayName) {
                    snipFeature.takeWindowSnip()
                }
                captureRow("Snip full screen", shortcut: AppSettings.shared.snipFullScreenHotKey.displayName) {
                    snipFeature.takeFullScreenSnip()
                }
                captureRow("Copy text", shortcut: AppSettings.shared.snipTextHotKey.displayName) {
                    snipFeature.copyTextFromAreaSnip()
                }
                captureRow(
                    snipFeature.isRecording ? "Stop recording" : "Record area",
                    shortcut: AppSettings.shared.snipRecordHotKey.displayName,
                    emphasized: snipFeature.isRecording
                ) {
                    snipFeature.toggleRecording()
                }
            }

            Divider()

            HStack(alignment: .firstTextBaseline) {
                Button(action: onOpenSettings) {
                    Label("Settings…", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .controlSize(.small)

                Spacer()

                Text("← → or side-scroll")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(width: 280)
        .background(
            MenuBarControlsEventCatcher { event in
                handleControlEvent(event)
            }
        )
    }

    @ViewBuilder
    private func sectionHeader<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)

            content()
        }
    }

    private func captureRow(
        _ title: String,
        shortcut: String,
        emphasized: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            onRunCapture(action)
        } label: {
            HStack(spacing: 8) {
                Text(title)
                Spacer(minLength: 8)
                Text(shortcut)
                    .foregroundStyle(emphasized ? Color.red.opacity(0.85) : Color.secondary)
            }
            .font(.caption)
            .foregroundStyle(emphasized ? Color.red : Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(title) — \(shortcut)")
    }

    private func presetHelp(_ preset: UmbrellaSunPreset) -> String {
        var parts = [
            "\(Int((preset.brightness * 100).rounded()))%",
            preset.isDarkroom ? "blue light off" : "\(preset.colorTemp)K",
        ]
        if preset.isFilmMode {
            parts.append("film mode")
        }
        return parts.joined(separator: " · ")
    }

    private func labeledSlider(
        target: MenuBarControlTarget,
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        enabled: Bool = true,
        onEditingChanged: ((Bool) -> Void)? = nil
    ) -> some View {
        let isFocused = focusedControl == target && enabled

        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.caption.weight(isFocused ? .semibold : .regular))
                Spacer()
                Text(valueText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step) { editing in
                onEditingChanged?(editing)
            }
                .controlSize(.small)
                .disabled(!enabled)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isFocused ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(isFocused ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .opacity(enabled ? 1 : 0.55)
        .onTapGesture {
            guard enabled else { return }
            focusedControl = target
        }
        .onHover { hovering in
            guard enabled, hovering else { return }
            focusedControl = target
        }
    }

    private func handleControlEvent(_ event: NSEvent) -> Bool {
        switch event.type {
        case .keyDown:
            return handleKeyDown(event)
        case .scrollWheel:
            return handleScroll(event)
        default:
            return false
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let boost = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 123, 125: // left, down → decrease
            nudgeFocused(by: -1, boosted: boost)
            return true
        case 124, 126: // right, up → increase
            nudgeFocused(by: 1, boosted: boost)
            return true
        case 48: // tab / shift-tab cycle focus
            cycleFocus(backward: event.modifierFlags.contains(.shift))
            return true
        default:
            return false
        }
    }

    private func handleScroll(_ event: NSEvent) -> Bool {
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        // Prefer side-scroll / tilt wheel; fall back to vertical only when clearly dominant.
        let delta: CGFloat
        if abs(dx) >= abs(dy), abs(dx) > 0.01 {
            delta = dx
        } else if abs(dy) > 0.01, event.modifierFlags.contains(.shift) {
            // Shift + regular scroll is a common side-scroll substitute.
            delta = dy
        } else if abs(dx) > 0.01 {
            delta = dx
        } else {
            return false
        }

        // Accumulate so tiny tilt-wheel ticks don't each count as a full step.
        scrollCarry += delta
        let threshold: CGFloat = 14
        var steps = 0
        while scrollCarry >= threshold {
            steps += 1
            scrollCarry -= threshold
        }
        while scrollCarry <= -threshold {
            steps -= 1
            scrollCarry += threshold
        }

        // Never jump more than one control step per scroll event.
        if steps > 1 {
            steps = 1
            scrollCarry = 0
        } else if steps < -1 {
            steps = -1
            scrollCarry = 0
        }

        guard steps != 0 else { return true }
        nudgeFocused(by: steps, boosted: event.modifierFlags.contains(.option))
        return true
    }

    private func cycleFocus(backward: Bool) {
        let all = MenuBarControlTarget.allCases
        guard let index = all.firstIndex(of: focusedControl) else { return }
        let next = backward
            ? all[(index + all.count - 1) % all.count]
            : all[(index + 1) % all.count]
        focusedControl = next
    }

    private func nudgeFocused(by steps: Int, boosted: Bool) {
        guard steps != 0 else { return }
        let multiplier = boosted ? 5 : 1
        let total = steps * multiplier

        switch focusedControl {
        case .screenBrightness:
            brightnessFeature.setBrightness(
                brightnessFeature.brightness + Float(total) * UmbrellaBrightnessFeature.brightnessStep
            )
        case .screenWarmth:
            brightnessFeature.setColorTemp(
                brightnessFeature.colorTemp + (total * UmbrellaBrightnessFeature.colorTempStep)
            )
        }
    }
}

/// Makes the popover accept arrow keys and horizontal scroll while open.
private struct MenuBarControlsEventCatcher: NSViewRepresentable {
    var handler: (NSEvent) -> Bool

    func makeNSView(context: Context) -> MenuBarControlsKeyView {
        let view = MenuBarControlsKeyView()
        view.handler = handler
        return view
    }

    func updateNSView(_ nsView: MenuBarControlsKeyView, context: Context) {
        nsView.handler = handler
    }
}

private final class MenuBarControlsKeyView: NSView {
    var handler: ((NSEvent) -> Bool)?
    private var localMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            installMonitorIfNeeded()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.window?.makeFirstResponder(self)
            }
        } else {
            removeMonitor()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Let clicks reach SwiftUI controls; this view only catches key/scroll monitors.
        nil
    }

    private func installMonitorIfNeeded() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel]) { [weak self] event in
            guard let self, let handler = self.handler else { return event }
            return handler(event) ? nil : event
        }
    }

    private func removeMonitor() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    deinit {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }
}
