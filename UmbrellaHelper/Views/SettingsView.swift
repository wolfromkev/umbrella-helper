import AppKit
import SwiftUI

private enum UmbrellaSettingsTab: Hashable {
    case keybindings
    case brightness
    case simpleSnip
}

private enum KeybindingTarget: Hashable {
    case snipArea
    case snipWindow
    case snipFullScreen
    case snipRecord
    case snipText
    case brightnessDown
    case brightnessUp
    case warmthUp
    case warmthDown
    case filmMode
    case sunPreset(String)
}

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedTab: UmbrellaSettingsTab = .keybindings
    @State private var launchAtLogin = AppSettings.shared.launchAtLogin

    @State private var snipAreaHotKey = AppSettings.shared.snipAreaHotKey
    @State private var snipWindowHotKey = AppSettings.shared.snipWindowHotKey
    @State private var snipFullScreenHotKey = AppSettings.shared.snipFullScreenHotKey
    @State private var snipRecordHotKey = AppSettings.shared.snipRecordHotKey
    @State private var snipTextHotKey = AppSettings.shared.snipTextHotKey
    @State private var brightnessDownHotKey = AppSettings.shared.brightnessDownHotKey
    @State private var brightnessUpHotKey = AppSettings.shared.brightnessUpHotKey
    @State private var warmthUpHotKey = AppSettings.shared.warmthUpHotKey
    @State private var warmthDownHotKey = AppSettings.shared.warmthDownHotKey
    @State private var filmModeHotKey = AppSettings.shared.filmModeHotKey
    @State private var sunPresetHotKeys = AppSettings.shared.sunScreenPresetHotKeys
    @State private var recordingTarget: KeybindingTarget?
    @State private var shortcutConflict: String?

    var body: some View {
        TabView(selection: $selectedTab) {
            keybindingsTab
                .tabItem { Text("Keybindings") }
                .tag(UmbrellaSettingsTab.keybindings)

            BrightnessTabView(
                feature: appModel.brightnessFeature,
                onPresetsChanged: {
                    refreshPresetBindings()
                    appModel.reloadSunPresetHotKeys()
                }
            )
            .tabItem { Text("Brightness") }
            .tag(UmbrellaSettingsTab.brightness)

            SimpleSnipTabView(feature: appModel.simpleSnipFeature)
                .tabItem { Text("SimpleSnip") }
                .tag(UmbrellaSettingsTab.simpleSnip)
        }
        .padding(16)
        .onAppear {
            launchAtLogin = LaunchAtLoginManager.isEnabled
            refreshPresetBindings()
            detectShortcutConflict()
        }
    }

    private var keybindingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionCard("General") {
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, enabled in
                            AppSettings.shared.launchAtLogin = enabled
                            LaunchAtLoginManager.setEnabled(enabled)
                        }

                    HStack {
                        Text("Version \(AppUpdateChecker.currentVersion)")
                            .foregroundStyle(.secondary)
                        #if !APP_STORE
                        Spacer()
                        Button("Check for Updates…") {
                            AppUpdateChecker.prompt()
                        }
                        #endif
                    }
                }

                sectionCard("SimpleSnip") {
                    editableBindingRow("Snip area", target: .snipArea)
                    editableBindingRow("Snip window", target: .snipWindow)
                    editableBindingRow("Snip full screen", target: .snipFullScreen)
                    editableBindingRow("Record area / Stop recording", target: .snipRecord)
                    editableBindingRow("Copy text from area", target: .snipText)
                }

                sectionCard("SunScreen") {
                    editableBindingRow("Brightness down", target: .brightnessDown)
                    editableBindingRow("Brightness up", target: .brightnessUp)
                    editableBindingRow("Warmer", target: .warmthUp)
                    editableBindingRow("Cooler", target: .warmthDown)
                    editableBindingRow("Film Mode", target: .filmMode)

                    Divider()

                    ForEach(appModel.brightnessFeature.presets) { preset in
                        editableBindingRow("Preset: \(preset.name)", target: .sunPreset(preset.id))
                    }
                }

                if let shortcutConflict {
                    Text(shortcutConflict)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func editableBindingRow(_ title: String, target: KeybindingTarget) -> some View {
        HStack {
            Text(title)
            Spacer()
            HotKeyRecorderView(
                binding: binding(for: target),
                isRecording: recordingTarget == target,
                onBegin: { recordingTarget = target },
                onCommit: { commitHotKey($0, for: target) },
                onCancel: { recordingTarget = nil }
            )

            Button("Clear") {
                clearHotKey(for: target)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(!canClear(target))
        }
    }

    private func binding(for target: KeybindingTarget) -> Binding<HotKeyBinding?> {
        Binding<HotKeyBinding?>(
            get: {
                switch target {
                case .snipArea: return snipAreaHotKey
                case .snipWindow: return snipWindowHotKey
                case .snipFullScreen: return snipFullScreenHotKey
                case .snipRecord: return snipRecordHotKey
                case .snipText: return snipTextHotKey
                case .brightnessDown: return brightnessDownHotKey
                case .brightnessUp: return brightnessUpHotKey
                case .warmthUp: return warmthUpHotKey
                case .warmthDown: return warmthDownHotKey
                case .filmMode: return filmModeHotKey
                case .sunPreset(let id): return sunPresetHotKeys[id]
                }
            },
            set: { newValue in
                guard let newValue else { return }
                commitHotKey(newValue, for: target)
            }
        )
    }

    private func commitHotKey(_ binding: HotKeyBinding, for target: KeybindingTarget) {
        switch target {
        case .snipArea:
            snipAreaHotKey = binding
            AppSettings.shared.snipAreaHotKey = binding
        case .snipWindow:
            snipWindowHotKey = binding
            AppSettings.shared.snipWindowHotKey = binding
        case .snipFullScreen:
            snipFullScreenHotKey = binding
            AppSettings.shared.snipFullScreenHotKey = binding
        case .snipRecord:
            snipRecordHotKey = binding
            AppSettings.shared.snipRecordHotKey = binding
        case .snipText:
            snipTextHotKey = binding
            AppSettings.shared.snipTextHotKey = binding
        case .brightnessDown:
            brightnessDownHotKey = binding
            AppSettings.shared.brightnessDownHotKey = binding
        case .brightnessUp:
            brightnessUpHotKey = binding
            AppSettings.shared.brightnessUpHotKey = binding
        case .warmthUp:
            warmthUpHotKey = binding
            AppSettings.shared.warmthUpHotKey = binding
        case .warmthDown:
            warmthDownHotKey = binding
            AppSettings.shared.warmthDownHotKey = binding
        case .filmMode:
            filmModeHotKey = binding
            AppSettings.shared.filmModeHotKey = binding
        case .sunPreset(let id):
            sunPresetHotKeys[id] = binding
            AppSettings.shared.sunScreenPresetHotKeys = sunPresetHotKeys
        }
        recordingTarget = nil
        appModel.reloadHotKeys()
        detectShortcutConflict()
    }

    private func clearHotKey(for target: KeybindingTarget) {
        switch target {
        case .snipArea:
            snipAreaHotKey = .snipAreaDefault
            AppSettings.shared.snipAreaHotKey = .snipAreaDefault
        case .snipWindow:
            snipWindowHotKey = .snipWindowDefault
            AppSettings.shared.snipWindowHotKey = .snipWindowDefault
        case .snipFullScreen:
            snipFullScreenHotKey = .snipFullScreenDefault
            AppSettings.shared.snipFullScreenHotKey = .snipFullScreenDefault
        case .snipRecord:
            snipRecordHotKey = .recordAreaDefault
            AppSettings.shared.snipRecordHotKey = .recordAreaDefault
        case .snipText:
            snipTextHotKey = .snipTextDefault
            AppSettings.shared.snipTextHotKey = .snipTextDefault
        case .brightnessDown:
            brightnessDownHotKey = .brightnessDownDefault
            AppSettings.shared.brightnessDownHotKey = .brightnessDownDefault
        case .brightnessUp:
            brightnessUpHotKey = .brightnessUpDefault
            AppSettings.shared.brightnessUpHotKey = .brightnessUpDefault
        case .warmthUp:
            warmthUpHotKey = .warmthUpDefault
            AppSettings.shared.warmthUpHotKey = .warmthUpDefault
        case .warmthDown:
            warmthDownHotKey = .warmthDownDefault
            AppSettings.shared.warmthDownHotKey = .warmthDownDefault
        case .filmMode:
            filmModeHotKey = nil
            AppSettings.shared.filmModeHotKey = nil
        case .sunPreset(let id):
            sunPresetHotKeys.removeValue(forKey: id)
            AppSettings.shared.sunScreenPresetHotKeys = sunPresetHotKeys
        }
        appModel.reloadHotKeys()
        detectShortcutConflict()
    }

    private func canClear(_ target: KeybindingTarget) -> Bool {
        switch target {
        case .filmMode:
            return filmModeHotKey != nil
        case .sunPreset(let id):
            return sunPresetHotKeys[id] != nil
        default:
            return true
        }
    }

    private func detectShortcutConflict() {
        var all: [(String, HotKeyBinding)] = [
            ("Snip area", snipAreaHotKey),
            ("Snip window", snipWindowHotKey),
            ("Snip full screen", snipFullScreenHotKey),
            ("Record area", snipRecordHotKey),
            ("Copy text", snipTextHotKey),
            ("Brightness down", brightnessDownHotKey),
            ("Brightness up", brightnessUpHotKey),
            ("Warmer", warmthUpHotKey),
            ("Cooler", warmthDownHotKey),
        ]
        if let filmModeHotKey {
            all.append(("Film Mode", filmModeHotKey))
        }
        all += appModel.brightnessFeature.presets.compactMap { preset in
            guard let binding = sunPresetHotKeys[preset.id] else { return nil }
            return ("SunScreen: \(preset.name)", binding)
        }

        var map: [String: [String]] = [:]
        for (label, binding) in all {
            map[binding.displayName, default: []].append(label)
        }
        if let conflict = map.first(where: { $0.value.count > 1 }) {
            shortcutConflict = "Conflict: \(conflict.value.joined(separator: ", ")) all use \(conflict.key)."
        } else {
            shortcutConflict = nil
        }
    }

    private func refreshPresetBindings() {
        var sunCurrent = AppSettings.shared.sunScreenPresetHotKeys
        let sunValidIDs = Set(appModel.brightnessFeature.presets.map(\.id))
        sunCurrent = sunCurrent.filter { sunValidIDs.contains($0.key) }
        AppSettings.shared.sunScreenPresetHotKeys = sunCurrent
        sunPresetHotKeys = sunCurrent

        detectShortcutConflict()
    }

    @ViewBuilder
    private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: NSColor.controlBackgroundColor))
        )
    }
}

private struct BrightnessTabView: View {
    @ObservedObject var feature: UmbrellaBrightnessFeature
    var onPresetsChanged: () -> Void
    @State private var newPresetName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("Display") {
                    Toggle("Automatic Brightness", isOn: Binding(
                        get: { feature.isAutoMode },
                        set: { feature.setAutoMode($0) }
                    ))
                    Text("Follows a daytime curve: dim at night, brightest at midday, then dim again toward sunset. Dragging a slider turns this off.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Blue Light Removal", isOn: Binding(
                        get: { feature.isDarkroom },
                        set: { feature.setDarkroom($0) }
                    ))
                    Toggle("Keep Awake", isOn: Binding(
                        get: { feature.isKeepAwakeEnabled },
                        set: { feature.setKeepAwake($0) }
                    ))
                    Toggle("Film Mode", isOn: Binding(
                        get: { feature.isFilmModeEnabled },
                        set: { feature.setFilmMode($0) }
                    ))
                    Text("Dims external monitors; leaves the built-in MacBook display unchanged.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Brightness: \(Int(feature.brightness * 100))%")
                        Slider(
                            value: Binding(
                                get: { Double(feature.brightness) },
                                set: { feature.setBrightness(Float($0), commit: false) }
                            ),
                            in: Double(UmbrellaBrightnessFeature.minimumBrightness)...1.0
                        ) { editing in
                            if !editing { feature.commitPendingChanges() }
                        }
                        .disabled(feature.isAutoMode)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Color temperature: \(feature.isDarkroom ? "Darkroom" : "\(feature.colorTemp)K")")
                        Slider(
                            value: Binding(
                                get: { Double(feature.colorTemp) },
                                set: { feature.setColorTemp(Int($0), commit: false) }
                            ),
                            in: 1200...6500,
                            step: Double(UmbrellaBrightnessFeature.colorTempStep)
                        ) { editing in
                            if !editing { feature.commitPendingChanges() }
                        }
                        .disabled(feature.isAutoMode || feature.isDarkroom)
                    }

                    Button("Restore Display Color") {
                        feature.restoreDisplayColor()
                    }
                    .help("Reset system display color, then re-apply current Umbrella settings.")
                }

                section("Schedule") {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        let now = minutesFrom(date: context.date)
                        VStack(alignment: .leading, spacing: 8) {
                            UmbrellaDayCurveView(
                                sunriseMinutes: feature.sunriseMinutes,
                                sunsetMinutes: feature.sunsetMinutes,
                                transitionMinutes: feature.transitionMinutes,
                                nowMinutes: now
                            )
                            Text(UmbrellaSolarSchedule.statusText(
                                at: now,
                                sunrise: feature.sunriseMinutes,
                                sunset: feature.sunsetMinutes,
                                transition: feature.transitionMinutes
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            Text(scheduleAnchorsLabel)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Toggle("Use location for sunrise and sunset", isOn: Binding(
                        get: { feature.useLocationSchedule },
                        set: { feature.setUseLocationSchedule($0) }
                    ))
                    if feature.useLocationSchedule {
                        Text(feature.locationName ?? "Finding sunrise and sunset…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 16) {
                        DatePicker(
                            "Sunrise",
                            selection: Binding(
                                get: { dateFrom(minutes: feature.sunriseMinutes) },
                                set: { feature.updateSunrise(minutesFrom(date: $0)) }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        DatePicker(
                            "Sunset",
                            selection: Binding(
                                get: { dateFrom(minutes: feature.sunsetMinutes) },
                                set: { feature.updateSunset(minutesFrom(date: $0)) }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                    }
                    .disabled(feature.useLocationSchedule)

                    HStack {
                        Text("Twilight")
                        Stepper(
                            value: Binding(
                                get: { feature.transitionMinutes },
                                set: { feature.updateTransitionMinutes($0) }
                            ),
                            in: 15...240,
                            step: 5
                        ) {
                            Text("\(feature.transitionMinutes) min")
                        }
                    }
                    Text("How early brightness starts rising before sunrise, and how long it keeps falling after sunset.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Picker("Day preset", selection: Binding(
                            get: { feature.dayPresetID },
                            set: {
                                feature.dayPresetID = $0
                                feature.refreshAutoStateIfNeeded()
                            }
                        )) {
                            ForEach(feature.presets) { preset in
                                Text(preset.name).tag(preset.id)
                            }
                        }
                        Picker("Night preset", selection: Binding(
                            get: { feature.nightPresetID },
                            set: {
                                feature.nightPresetID = $0
                                feature.refreshAutoStateIfNeeded()
                            }
                        )) {
                            ForEach(feature.presets) { preset in
                                Text(preset.name).tag(preset.id)
                            }
                        }
                    }
                    Text("Night is the dim floor. Day is the midday peak. Warmth follows the same curve.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                section("Presets") {
                    Text("Star up to \(UmbrellaBrightnessFeature.maxMenuBarFavorites) presets to show them in the menu bar Screen section.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        TextField("Preset name", text: $newPresetName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                        Button("Add preset") {
                            feature.addPreset(name: newPresetName.trimmingCharacters(in: .whitespacesAndNewlines))
                            newPresetName = ""
                            onPresetsChanged()
                        }
                    }

                    ForEach(feature.presets) { preset in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Button {
                                    _ = feature.toggleMenuBarFavorite(preset.id)
                                } label: {
                                    Image(systemName: feature.isMenuBarFavorite(preset.id) ? "star.fill" : "star")
                                        .foregroundStyle(feature.isMenuBarFavorite(preset.id) ? Color.yellow : Color.secondary)
                                }
                                .buttonStyle(.plain)
                                .help(
                                    feature.isMenuBarFavorite(preset.id)
                                        ? "Remove from menu bar"
                                        : feature.menuBarFavoriteIDs.count >= UmbrellaBrightnessFeature.maxMenuBarFavorites
                                            ? "Already starring \(UmbrellaBrightnessFeature.maxMenuBarFavorites) presets"
                                            : "Show in menu bar"
                                )
                                .disabled(
                                    !feature.isMenuBarFavorite(preset.id)
                                        && feature.menuBarFavoriteIDs.count >= UmbrellaBrightnessFeature.maxMenuBarFavorites
                                )

                                TextField("Name", text: Binding(
                                    get: { preset.name },
                                    set: {
                                        var updated = preset
                                        updated.name = $0
                                        feature.updatePreset(updated)
                                        onPresetsChanged()
                                    }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 200)

                                Button("Apply") { feature.applyPreset(id: preset.id) }
                                Button("Delete") {
                                    feature.removePreset(preset.id)
                                    onPresetsChanged()
                                }
                                .foregroundStyle(.red)
                            }

                            HStack {
                                Text("Brightness")
                                Slider(
                                    value: Binding(
                                        get: { Double(preset.brightness) },
                                        set: {
                                            var updated = preset
                                            updated.brightness = Float($0)
                                            feature.updatePreset(updated)
                                        }
                                    ),
                                    in: Double(UmbrellaBrightnessFeature.minimumBrightness)...1.0
                                )
                            }

                            HStack {
                                Text("Warmth")
                                Slider(
                                    value: Binding(
                                        get: { Double(preset.colorTemp) },
                                        set: {
                                            var updated = preset
                                            updated.colorTemp = Int($0)
                                            feature.updatePreset(updated)
                                        }
                                    ),
                                    in: 1200...6500,
                                    step: 100
                                )
                                .disabled(preset.isDarkroom)
                            }

                            HStack(spacing: 16) {
                                Toggle(
                                    "Remove blue light",
                                    isOn: Binding(
                                        get: { preset.isDarkroom },
                                        set: {
                                            var updated = preset
                                            updated.isDarkroom = $0
                                            feature.updatePreset(updated)
                                        }
                                    )
                                )
                                .toggleStyle(.checkbox)

                                Toggle(
                                    "Film Mode",
                                    isOn: Binding(
                                        get: { preset.isFilmMode },
                                        set: {
                                            var updated = preset
                                            updated.isFilmMode = $0
                                            feature.updatePreset(updated)
                                        }
                                    )
                                )
                                .toggleStyle(.checkbox)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private func dateFrom(minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    private func minutesFrom(date: Date) -> Int {
        UmbrellaSolarSchedule.minutesOfDay(from: date)
    }

    private var scheduleAnchorsLabel: String {
        let midday = UmbrellaSolarSchedule.middayMinutes(
            sunrise: feature.sunriseMinutes,
            sunset: feature.sunsetMinutes
        )
        return "Sunrise \(timeLabel(minutes: feature.sunriseMinutes)) · Midday \(timeLabel(minutes: midday)) · Sunset \(timeLabel(minutes: feature.sunsetMinutes))"
    }

    private func timeLabel(minutes: Int) -> String {
        dateFrom(minutes: minutes).formatted(date: .omitted, time: .shortened)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: NSColor.controlBackgroundColor))
        )
    }
}

private final class SnipColorPanelController: NSObject {
    static let shared = SnipColorPanelController()
    private var onColor: ((NSColor) -> Void)?

    func show(color: NSColor, onChange: @escaping (NSColor) -> Void) {
        onColor = onChange
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = color
        panel.isContinuous = true
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        center(panel)
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            self?.center(panel)
        }
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        onColor?(sender.color)
    }

    private func center(_ panel: NSWindow) {
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        var frame = panel.frame
        frame.origin = NSPoint(
            x: visible.midX - frame.width / 2,
            y: visible.midY - frame.height / 2
        )
        panel.setFrame(frame, display: true)
    }
}

private struct SimpleSnipTabView: View {
    @ObservedObject var feature: UmbrellaSimpleSnipFeature

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("Permissions") {
                    HStack {
                        Text("Screen capture")
                            .frame(width: 140, alignment: .leading)
                        Text(feature.screenCaptureState.label)
                            .foregroundStyle(permissionColor(feature.screenCaptureState))
                        Spacer()
                        Button("Open Settings") { feature.openScreenCaptureSettings() }
                    }

                    HStack {
                        Text("Microphone")
                            .frame(width: 140, alignment: .leading)
                        Text(feature.microphoneState.label)
                            .foregroundStyle(permissionColor(feature.microphoneState))
                        Spacer()
                        if feature.microphoneState != .allowed {
                            Button("Request Access") { feature.requestMicrophonePermission() }
                        }
                        Button("Open Settings") { feature.openMicrophoneSettings() }
                    }
                }

                section("Folders") {
                    HStack {
                        Text("Screenshots")
                            .frame(width: 110, alignment: .leading)
                        Text(feature.screenshotFolderPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Choose…") { feature.chooseScreenshotFolder() }
                        Button("Open") { feature.openScreenshotFolder() }
                    }

                    HStack {
                        Text("Recordings")
                            .frame(width: 110, alignment: .leading)
                        Text(feature.recordingFolderPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Choose…") { feature.chooseRecordingFolder() }
                        Button("Open") { feature.openRecordingFolder() }
                    }
                }

                section("Options") {
                    Toggle("Reveal screenshot in Finder", isOn: Binding(
                        get: { feature.revealScreenshotInFinder },
                        set: {
                            feature.revealScreenshotInFinder = $0
                            feature.saveSettings()
                        }
                    ))

                    Toggle("Reveal recording in Finder", isOn: Binding(
                        get: { feature.revealRecordingInFinder },
                        set: {
                            feature.revealRecordingInFinder = $0
                            feature.saveSettings()
                        }
                    ))

                    Toggle("Record system audio", isOn: Binding(
                        get: { feature.recordSystemAudio },
                        set: {
                            feature.recordSystemAudio = $0
                            feature.saveSettings()
                        }
                    ))

                    Toggle("Record microphone", isOn: Binding(
                        get: { feature.recordMicrophone },
                        set: {
                            feature.recordMicrophone = $0
                            feature.saveSettings()
                            if $0 { feature.requestMicrophonePermission() }
                        }
                    ))
                }

                section("Colors") {
                    snipColorPicker("Screenshot", color: $feature.screenshotSelectionColor)
                    snipColorPicker("Screen Record", color: $feature.recordingSelectionColor)
                    snipColorPicker("Text copy", color: $feature.textCopySelectionColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .onAppear {
            feature.refreshPermissionState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            feature.refreshPermissionState()
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: NSColor.controlBackgroundColor))
        )
    }

    private func snipColorPicker(_ title: String, color: Binding<NSColor>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button {
                SnipColorPanelController.shared.show(color: color.wrappedValue) { picked in
                    color.wrappedValue = picked.usingColorSpace(.sRGB) ?? picked
                    feature.saveSettings()
                }
            } label: {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(nsColor: color.wrappedValue))
                    .frame(width: 44, height: 22)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title) color")
        }
    }

    private func permissionColor(_ state: UmbrellaPermissionState) -> Color {
        switch state {
        case .allowed:
            return .green
        case .notRequested:
            return .secondary
        case .notAllowed:
            return .orange
        }
    }
}
