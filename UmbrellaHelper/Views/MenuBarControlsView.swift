import AppKit
import SwiftUI

private enum MenuBarControlTarget: CaseIterable, Hashable {
    case screenBrightness
    case screenWarmth
    case lightBrightness
    case lightWarmth
}

struct MenuBarControlsView: View {
    @ObservedObject var brightnessFeature: UmbrellaBrightnessFeature
    @ObservedObject var neewerFeature: UmbrellaNeewerLightFeature
    var onOpenSettings: () -> Void

    @State private var focusedControl: MenuBarControlTarget = .screenBrightness
    @State private var scrollCarry: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Screen", systemImage: "sun.max.fill") {
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
                        set: { brightnessFeature.setBrightness(Float($0)) }
                    ),
                    range: 0.05...1.0,
                    step: Double(UmbrellaBrightnessFeature.brightnessStep)
                )

                labeledSlider(
                    target: .screenWarmth,
                    title: "Warmth",
                    valueText: brightnessFeature.isDarkroom
                        ? "Blue light off"
                        : "\(brightnessFeature.colorTemp)K",
                    value: Binding(
                        get: { Double(brightnessFeature.colorTemp) },
                        set: { brightnessFeature.setColorTemp(Int($0.rounded())) }
                    ),
                    range: 1200...6500,
                    step: Double(UmbrellaBrightnessFeature.colorTempStep),
                    enabled: !brightnessFeature.isDarkroom
                )
            }

            Divider()

            sectionHeader("Light", systemImage: "lightbulb.fill") {
                if !neewerFeature.menuBarFavoritePresets.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(neewerFeature.menuBarFavoritePresets) { preset in
                            Button(preset.name) {
                                neewerFeature.applyPreset(id: preset.id)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(!neewerFeature.hasSyncedFromLight || neewerFeature.isBusy)
                            .help("\(preset.brightness)% · \(preset.kelvin)K")
                        }
                    }
                }

                Toggle(
                    "Power",
                    isOn: Binding(
                        get: { neewerFeature.isPoweredOn },
                        set: { neewerFeature.setPoweredOn($0) }
                    )
                )
                .toggleStyle(.switch)
                .disabled(!neewerFeature.hasSyncedFromLight)
                .controlSize(.small)

                labeledSlider(
                    target: .lightBrightness,
                    title: "Brightness",
                    valueText: neewerFeature.hasSyncedFromLight ? "\(neewerFeature.brightness)%" : "…",
                    value: Binding(
                        get: { Double(neewerFeature.brightness) },
                        set: { neewerFeature.setBrightness(Int($0.rounded())) }
                    ),
                    range: Double(UmbrellaNeewerLightFeature.minBrightness)...Double(UmbrellaNeewerLightFeature.maxBrightness),
                    step: 1,
                    enabled: neewerFeature.hasSyncedFromLight,
                    onEditingChanged: { editing in
                        if !editing { neewerFeature.flushPendingApply() }
                    }
                )

                labeledSlider(
                    target: .lightWarmth,
                    title: "Warmth",
                    valueText: neewerFeature.hasSyncedFromLight ? "\(neewerFeature.kelvin)K" : "…",
                    value: Binding(
                        get: { Double(neewerFeature.kelvin) },
                        set: { neewerFeature.setKelvin(Int($0.rounded())) }
                    ),
                    range: Double(UmbrellaNeewerLightFeature.minKelvin)...Double(UmbrellaNeewerLightFeature.maxKelvin),
                    step: Double(UmbrellaNeewerLightFeature.kelvinStep),
                    enabled: neewerFeature.hasSyncedFromLight,
                    onEditingChanged: { editing in
                        if !editing { neewerFeature.flushPendingApply() }
                    }
                )

                Group {
                    if neewerFeature.isSyncingFromLight {
                        Text("Reading current light level…")
                    } else if !neewerFeature.isReachable {
                        Text("NeewerLite isn’t reachable")
                    } else if let status = neewerFeature.statusMessage {
                        Text(status)
                    } else {
                        Text("\(neewerFeature.brightness)% · \(neewerFeature.kelvin)K")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 14)
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
        // Don't nudge Neewer controls until we've read the live level.
        if !neewerFeature.hasSyncedFromLight,
           focusedControl == .lightBrightness || focusedControl == .lightWarmth {
            return false
        }

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
        case .lightBrightness:
            neewerFeature.setBrightness(neewerFeature.brightness + total)
            neewerFeature.flushPendingApply()
        case .lightWarmth:
            neewerFeature.setKelvin(
                neewerFeature.kelvin + (total * UmbrellaNeewerLightFeature.kelvinStep)
            )
            neewerFeature.flushPendingApply()
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
