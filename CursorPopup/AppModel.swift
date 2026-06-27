import AppKit
import AVFoundation
import Carbon.HIToolbox
import Combine
import CoreGraphics
import CoreMedia
import ScreenCaptureKit
import SwiftUI
import Vision

@MainActor
final class AppModel: ObservableObject {
    @Published var isSettingsVisible = false
    @Published var isNotionTaskVisible = false
    @Published var notionTaskTitle = ""
    @Published var notionSelectedCategory = NotionFieldSelection.none
    @Published var notionSelectedPriority = NotionFieldSelection.none
    @Published var notionDueDate: Date? = nil
    @Published var notionSchema: NotionDatabaseSchema?
    @Published var isLoadingNotionSchema = false
    @Published var notionSchemaError: String?
    @Published var isNotionSubmitting = false
    @Published var notionStatusMessage: String?
    @Published var notionErrorMessage: String?
    @Published var lastCreatedNotionTaskURL: URL?

    let settings = AppSettings.shared
    private let settingsPanelController = SettingsPanelController()
    private let notionTaskPanelController = NotionTaskPanelController()
    private let notionTaskHotKey = GlobalHotKey(registrationID: 3)
    private let snipAreaHotKey = GlobalHotKey(registrationID: 5)
    private let snipWindowHotKey = GlobalHotKey(registrationID: 6)
    private let snipFullScreenHotKey = GlobalHotKey(registrationID: 7)
    private let snipRecordHotKey = GlobalHotKey(registrationID: 8)
    private let snipTextHotKey = GlobalHotKey(registrationID: 13)
    private let brightnessDownHotKey = GlobalHotKey(registrationID: 9)
    private let brightnessUpHotKey = GlobalHotKey(registrationID: 10)
    private let warmthUpHotKey = GlobalHotKey(registrationID: 11)
    private let warmthDownHotKey = GlobalHotKey(registrationID: 12)
    private var sunPresetHotKeys: [String: GlobalHotKey] = [:]
    private var nextSunPresetHotKeyID: UInt32 = 200
    let brightnessFeature = UmbrellaBrightnessFeature()
    let simpleSnipFeature = UmbrellaSimpleSnipFeature()
    let neewerHUDBridge = UmbrellaNeewerHUDBridge()

    var notionTaskHasKeyboardFocus: Bool {
        notionTaskPanelController.hasKeyboardFocus
    }

    func start() {
        ActiveScreenTracker.start()
        settingsPanelController.configure(model: self)
        notionTaskPanelController.configure(model: self)
        settings.bootstrapNotionConfiguration()
        brightnessFeature.start()
        simpleSnipFeature.start()
        neewerHUDBridge.start()
        reloadHotKeys()

        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            settings.launchAtLogin = true
        }

        if settings.launchAtLogin {
            LaunchAtLoginManager.setEnabled(true)
        }
    }

    private var isNotionConfigured: Bool {
        guard let token = KeychainStorage.notionToken, !token.isEmpty else { return false }
        return !settings.notionDatabaseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func stop() {
        ActiveScreenTracker.stop()
        notionTaskHotKey.unregister()
        snipAreaHotKey.unregister()
        snipWindowHotKey.unregister()
        snipFullScreenHotKey.unregister()
        snipRecordHotKey.unregister()
        snipTextHotKey.unregister()
        brightnessDownHotKey.unregister()
        brightnessUpHotKey.unregister()
        warmthUpHotKey.unregister()
        warmthDownHotKey.unregister()
        sunPresetHotKeys.values.forEach { $0.unregister() }
        sunPresetHotKeys.removeAll()
        settingsPanelController.closePanel()
        notionTaskPanelController.closePanel()
        brightnessFeature.stop()
        simpleSnipFeature.stop()
        neewerHUDBridge.stop()
    }

    func reloadHotKeys() {
        notionTaskHotKey.register(hotKeyID: settings.notionTaskHotKey) { [weak self] in
            Task { @MainActor in self?.toggleNotionTask() }
        }
        snipAreaHotKey.register(hotKeyID: settings.snipAreaHotKey) { [weak self] in
            Task { @MainActor in self?.simpleSnipFeature.takeAreaSnip() }
        }
        snipWindowHotKey.register(hotKeyID: settings.snipWindowHotKey) { [weak self] in
            Task { @MainActor in self?.simpleSnipFeature.takeWindowSnip() }
        }
        snipFullScreenHotKey.register(hotKeyID: settings.snipFullScreenHotKey) { [weak self] in
            Task { @MainActor in self?.simpleSnipFeature.takeFullScreenSnip() }
        }
        snipRecordHotKey.register(hotKeyID: settings.snipRecordHotKey) { [weak self] in
            Task { @MainActor in self?.simpleSnipFeature.toggleRecording() }
        }
        snipTextHotKey.register(hotKeyID: settings.snipTextHotKey) { [weak self] in
            Task { @MainActor in self?.simpleSnipFeature.copyTextFromAreaSnip() }
        }
        brightnessDownHotKey.register(hotKeyID: settings.brightnessDownHotKey) { [weak self] in
            Task { @MainActor in self?.brightnessFeature.adjustBrightness(by: -UmbrellaBrightnessFeature.brightnessStep) }
        }
        brightnessUpHotKey.register(hotKeyID: settings.brightnessUpHotKey) { [weak self] in
            Task { @MainActor in self?.brightnessFeature.adjustBrightness(by: UmbrellaBrightnessFeature.brightnessStep) }
        }
        warmthUpHotKey.register(hotKeyID: settings.warmthUpHotKey) { [weak self] in
            Task { @MainActor in self?.brightnessFeature.adjustColorTemp(by: -UmbrellaBrightnessFeature.colorTempStep) }
        }
        warmthDownHotKey.register(hotKeyID: settings.warmthDownHotKey) { [weak self] in
            Task { @MainActor in self?.brightnessFeature.adjustColorTemp(by: UmbrellaBrightnessFeature.colorTempStep) }
        }
        reloadSunPresetHotKeys()
    }

    func reloadSunPresetHotKeys() {
        sunPresetHotKeys.values.forEach { $0.unregister() }
        sunPresetHotKeys.removeAll()
        nextSunPresetHotKeyID = 200

        for preset in brightnessFeature.presets {
            guard let binding = settings.sunScreenPresetHotKeys[preset.id] else { continue }
            let id = nextSunPresetHotKeyID
            nextSunPresetHotKeyID += 1
            let hotKey = GlobalHotKey(registrationID: id)
            hotKey.register(hotKeyID: binding) { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.brightnessFeature.applyPreset(id: preset.id)
                }
            }
            sunPresetHotKeys[preset.id] = hotKey
        }
    }

    func showSettings() {
        if isSettingsVisible {
            settingsPanelController.showPanel()
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        settingsPanelController.showPanel()
        isSettingsVisible = true
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideSettings() {
        guard isSettingsVisible else { return }
        settingsPanelController.closePanel()
        isSettingsVisible = false
    }

    func toggleNotionTask() {
        if isNotionTaskVisible {
            hideNotionTask()
        } else {
            showNotionTask()
        }
    }

    func showNotionTask() {
        resetNotionTaskState(clearTitle: true)
        notionTaskPanelController.showPanel()
        isNotionTaskVisible = true
        loadNotionSchema()
        NSApp.activate(ignoringOtherApps: true)
        notionTaskPanelController.focusTaskField()
    }

    func hideNotionTask() {
        guard isNotionTaskVisible else { return }
        isNotionTaskVisible = false
        notionTaskPanelController.closePanel()
        resetNotionTaskState(clearTitle: true)
    }

    var canSubmitNotionTask: Bool {
        !notionTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isNotionSubmitting
    }

    func submitNotionTask() {
        let trimmed = notionTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSubmitNotionTask else { return }
        guard let schema = notionSchema else {
            notionErrorMessage = notionSchemaError ?? "Notion options are still loading."
            notionTaskPanelController.resizeToFitContent()
            return
        }

        let input = NotionTaskInput(
            title: trimmed,
            category: NotionFieldSelection.value(from: notionSelectedCategory),
            priority: NotionFieldSelection.value(from: notionSelectedPriority),
            dueDate: notionDueDate
        )

        hideNotionTask()

        Task {
            do {
                _ = try await NotionAPIClient.shared.createTask(input, schema: schema)
            } catch {
                await MainActor.run {
                    presentNotionTaskError(error.localizedDescription)
                }
            }
        }
    }

    private func presentNotionTaskError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Could not add Notion task"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    func refreshNotionTaskLayout() {
        if isNotionTaskVisible {
            notionTaskPanelController.resizeToFitContent()
        }
    }

    func loadNotionSchema(force: Bool = false) {
        guard !isLoadingNotionSchema else { return }
        if !force, notionSchema != nil { return }

        isLoadingNotionSchema = true
        notionSchemaError = nil
        refreshNotionTaskLayout()

        Task {
            do {
                let schema = try await NotionAPIClient.shared.fetchDatabaseSchema()
                await MainActor.run {
                    notionSchema = schema
                    isLoadingNotionSchema = false
                    notionSchemaError = nil
                    refreshNotionTaskLayout()
                }
            } catch {
                await MainActor.run {
                    notionSchema = nil
                    isLoadingNotionSchema = false
                    notionSchemaError = error.localizedDescription
                    refreshNotionTaskLayout()
                }
            }
        }
    }

    private func resetNotionTaskState(clearTitle: Bool) {
        if clearTitle {
            notionTaskTitle = ""
        }
        notionSelectedCategory = NotionFieldSelection.none
        notionSelectedPriority = NotionFieldSelection.none
        notionDueDate = nil
        isNotionSubmitting = false
        notionStatusMessage = nil
        notionErrorMessage = nil
        lastCreatedNotionTaskURL = nil
    }

}

struct UmbrellaSunPreset: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var brightness: Float
    var colorTemp: Int
    var isDarkroom: Bool

    init(id: String = UUID().uuidString, name: String, brightness: Float, colorTemp: Int, isDarkroom: Bool = false) {
        self.id = id
        self.name = name
        self.brightness = brightness
        self.colorTemp = colorTemp
        self.isDarkroom = isDarkroom
    }
}

enum UmbrellaPermissionState {
    case allowed
    case notRequested
    case notAllowed

    var label: String {
        switch self {
        case .allowed:
            return "Allowed"
        case .notRequested:
            return "Not requested"
        case .notAllowed:
            return "Not allowed"
        }
    }
}

private enum UmbrellaBlueLightManager {
    static func apply(colorTemp: Int, brightness: Float, darkroom: Bool) {
        let dim = max(0.05, min(1, brightness))
        let channels: (Float, Float, Float)
        if darkroom {
            channels = (0.8 * dim, 0.0, 0.0)
        } else {
            let multipliers = gammaMultipliers(forKelvin: colorTemp)
            channels = (multipliers.0 * dim, multipliers.1 * dim, multipliers.2 * dim)
        }

        for display in onlineDisplayIDs() {
            CGSetDisplayTransferByFormula(
                display,
                0, channels.0, 1,
                0, channels.1, 1,
                0, channels.2, 1
            )
        }
    }

    static func reset() {
        CGDisplayRestoreColorSyncSettings()
    }

    static func warmthLabel(for kelvin: Int) -> String {
        switch kelvin {
        case 6200...6500: return "Daylight"
        case 5000..<6200: return "Bright White"
        case 4000..<5000: return "Fluorescent"
        case 3200..<4000: return "Halogen"
        case 2500..<3200: return "Incandescent"
        case 1800..<2500: return "Candle"
        default: return "Ember"
        }
    }

    private static func onlineDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else {
            return [CGMainDisplayID()]
        }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        var actual = count
        guard CGGetOnlineDisplayList(count, &displays, &actual) == .success else {
            return [CGMainDisplayID()]
        }
        return Array(displays.prefix(Int(actual)))
    }

    private static func gammaMultipliers(forKelvin kelvin: Int) -> (Float, Float, Float) {
        let k = max(1200, min(6500, kelvin))
        let target = rawRGB(kelvin: k)
        let reference = rawRGB(kelvin: 6500)
        return (
            min(target.0 / reference.0, 1),
            min(target.1 / reference.1, 1),
            min(target.2 / reference.2, 1)
        )
    }

    private static func rawRGB(kelvin: Int) -> (Float, Float, Float) {
        let t = Float(kelvin) / 100
        var r: Float
        var g: Float
        var b: Float

        if t <= 66 {
            r = 255
            g = 99.4708 * log(t) - 161.11957
        } else {
            r = 329.69873 * pow(t - 60, -0.13320476)
            g = 288.12216 * pow(t - 60, -0.07551485)
        }

        if t >= 66 {
            b = 255
        } else if t <= 19 {
            b = 0
        } else {
            b = 138.51773 * log(t - 10) - 305.0448
        }

        return (max(r, 0), max(g, 0), max(b, 0))
    }
}

final class UmbrellaBrightnessOverlayState: ObservableObject {
    @Published var brightness: Double = 1
    @Published var colorTemp: Double = 6500
    @Published var isDarkroom: Bool = false
}

struct UmbrellaBrightnessOverlayView: View {
    static let panelSize = NSSize(width: 460, height: 108)
    private static let trackWidth: CGFloat = 300
    private static let contentWidth: CGFloat = 420

    @ObservedObject var state: UmbrellaBrightnessOverlayState

    private var warmthProgress: Double {
        guard !state.isDarkroom else { return 1 }
        return (6500 - state.colorTemp) / (6500 - 1200)
    }

    var body: some View {
        VStack(spacing: 14) {
            row(
                icon: "sun.max.fill",
                iconColor: .yellow,
                progress: state.brightness,
                label: "\(Int((state.brightness * 100).rounded()))%",
                trackFill: LinearGradient(
                    colors: [.white.opacity(0.95), .white.opacity(0.7)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            row(
                icon: state.isDarkroom ? "eye.slash.fill" : "thermometer.medium",
                iconColor: state.isDarkroom ? .red : .orange,
                progress: warmthProgress,
                label: state.isDarkroom ? "Darkroom" : "\(Int(state.colorTemp.rounded()))K",
                trackFill: LinearGradient(
                    colors: state.isDarkroom
                        ? [.red.opacity(0.9), .red.opacity(0.5)]
                        : [.blue, .cyan, .yellow, .orange, .red],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
        .frame(width: Self.contentWidth)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: NSColor(white: 0.12, alpha: 0.88)))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        }
        .animation(.easeInOut(duration: 0.25), value: state.brightness)
        .animation(.easeInOut(duration: 0.25), value: state.colorTemp)
        .animation(.easeInOut(duration: 0.25), value: state.isDarkroom)
    }

    private func row(
        icon: String,
        iconColor: Color,
        progress: Double,
        label: String,
        trackFill: LinearGradient
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 20)

            track(progress: progress, fill: trackFill)

            Text(label)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: 64, alignment: .trailing)
        }
        .frame(width: Self.contentWidth)
    }

    private func track(progress: Double, fill: LinearGradient) -> some View {
        let clamped = min(1, max(0, progress))
        return ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.18))
            Capsule()
                .fill(fill)
                .frame(width: max(4, Self.trackWidth * clamped))
            if clamped > 0.04 && clamped < 0.96 {
                Circle()
                    .fill(.white)
                    .frame(width: 6, height: 6)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    .offset(x: Self.trackWidth * clamped - 3)
            }
        }
        .frame(width: Self.trackWidth, height: 8)
    }
}

final class UmbrellaBrightnessOverlayController {
    static let shared = UmbrellaBrightnessOverlayController()

    private let state = UmbrellaBrightnessOverlayState()
    private var panel: NSPanel?
    private var hideTimer: Timer?

    private init() {}

    func show(brightness: Float, colorTemp: Int, isDarkroom: Bool) {
        DispatchQueue.main.async {
            self.state.brightness = Double(brightness)
            self.state.colorTemp = Double(colorTemp)
            self.state.isDarkroom = isDarkroom
            self.ensurePanel()
            self.positionPanel()
            self.panel?.alphaValue = 1
            self.panel?.orderFrontRegardless()
            self.resetHideTimer()
        }
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let size = UmbrellaBrightnessOverlayView.panelSize
        let host = NSHostingView(rootView: UmbrellaBrightnessOverlayView(state: state))
        host.frame = NSRect(origin: .zero, size: size)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.contentView = host
        self.panel = panel
    }

    private func positionPanel() {
        guard let panel else { return }
        let screen = MainActor.assumeIsolated { ActiveScreenTracker.presentationScreen(excluding: panel) }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(
            NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2 + frame.height * 0.12)
        )
    }

    private func resetHideTimer() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            guard let panel = self?.panel else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                panel.animator().alphaValue = 0
            } completionHandler: {
                panel.orderOut(nil)
                panel.alphaValue = 1
            }
        }
    }
}

@MainActor
final class UmbrellaBrightnessFeature: ObservableObject {
    static let brightnessStep: Float = 0.05
    static let colorTempStep: Int = 100

    @Published var brightness: Float
    @Published var colorTemp: Int
    @Published var isDarkroom: Bool
    @Published var isAutoMode: Bool
    @Published var useLocationSchedule: Bool
    @Published var sunriseMinutes: Int
    @Published var sunsetMinutes: Int
    @Published var transitionMinutes: Int
    @Published var isKeepAwakeEnabled: Bool
    @Published var presets: [UmbrellaSunPreset]
    @Published var dayPresetID: String
    @Published var nightPresetID: String
    @Published var locationName: String?

    private var keepAwakeActivity: NSObjectProtocol?
    private var timer: Timer?
    private let defaults = UserDefaults.standard
    private let presetKey = "umbrella.sunscreen.presets"
    private let overlayController = UmbrellaBrightnessOverlayController.shared

    init() {
        let loadedPresets = Self.loadPresets(from: defaults, key: presetKey)
        brightness = defaults.object(forKey: "umbrella.sunscreen.brightness") as? Float ?? 1.0
        colorTemp = defaults.object(forKey: "umbrella.sunscreen.colorTemp") as? Int ?? 6500
        isDarkroom = defaults.object(forKey: "umbrella.sunscreen.darkroom") as? Bool ?? false
        isAutoMode = defaults.object(forKey: "umbrella.sunscreen.auto") as? Bool ?? true
        useLocationSchedule = defaults.object(forKey: "umbrella.sunscreen.useLocation") as? Bool ?? false
        sunriseMinutes = defaults.object(forKey: "umbrella.sunscreen.sunrise") as? Int ?? 420
        sunsetMinutes = defaults.object(forKey: "umbrella.sunscreen.sunset") as? Int ?? 1200
        transitionMinutes = defaults.object(forKey: "umbrella.sunscreen.transitionMinutes") as? Int ?? 30
        isKeepAwakeEnabled = defaults.object(forKey: "umbrella.sunscreen.keepAwake") as? Bool ?? false
        presets = loadedPresets
        dayPresetID = defaults.string(forKey: "umbrella.sunscreen.dayPresetID")
            ?? loadedPresets.first?.id
            ?? ""
        nightPresetID = defaults.string(forKey: "umbrella.sunscreen.nightPresetID")
            ?? loadedPresets.dropFirst().first?.id
            ?? loadedPresets.first?.id
            ?? ""
    }

    func start() {
        applyKeepAwake()
        refreshAutoStateIfNeeded()
        apply()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAutoStateIfNeeded()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        releaseKeepAwake()
        UmbrellaBlueLightManager.reset()
    }

    func setBrightness(_ value: Float) {
        isAutoMode = false
        brightness = max(0.05, min(1, value))
        isDarkroom = false
        apply()
        showAdjustmentOverlay()
    }

    func adjustBrightness(by delta: Float) {
        setBrightness(brightness + delta)
    }

    func setColorTemp(_ value: Int) {
        isAutoMode = false
        colorTemp = max(1200, min(6500, value))
        isDarkroom = false
        apply()
        showAdjustmentOverlay()
    }

    func adjustColorTemp(by delta: Int) {
        setColorTemp(colorTemp + delta)
    }

    func setDarkroom(_ enabled: Bool) {
        if enabled { isAutoMode = false }
        isDarkroom = enabled
        apply()
        showAdjustmentOverlay()
    }

    func setAutoMode(_ enabled: Bool) {
        isAutoMode = enabled
        refreshAutoStateIfNeeded()
    }

    func setUseLocationSchedule(_ enabled: Bool) {
        useLocationSchedule = enabled
        if enabled {
            locationName = "Using system location"
        } else {
            locationName = nil
        }
        save()
    }

    func setKeepAwake(_ enabled: Bool) {
        isKeepAwakeEnabled = enabled
        applyKeepAwake()
        save()
    }

    func updateSunrise(_ minutes: Int) {
        sunriseMinutes = max(0, min(1439, minutes))
        refreshAutoStateIfNeeded()
    }

    func updateSunset(_ minutes: Int) {
        sunsetMinutes = max(0, min(1439, minutes))
        refreshAutoStateIfNeeded()
    }

    func updateTransitionMinutes(_ minutes: Int) {
        transitionMinutes = max(15, min(240, minutes))
        refreshAutoStateIfNeeded()
    }

    func addPreset(name: String) {
        let preset = UmbrellaSunPreset(
            name: name.isEmpty ? UmbrellaBlueLightManager.warmthLabel(for: colorTemp) : name,
            brightness: brightness,
            colorTemp: colorTemp,
            isDarkroom: isDarkroom
        )
        presets.append(preset)
        if dayPresetID.isEmpty { dayPresetID = preset.id }
        if nightPresetID.isEmpty { nightPresetID = preset.id }
        save()
    }

    func updatePreset(_ preset: UmbrellaSunPreset) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[index] = preset
        save()
    }

    func removePreset(_ presetID: String) {
        presets.removeAll(where: { $0.id == presetID })
        if dayPresetID == presetID { dayPresetID = presets.first?.id ?? "" }
        if nightPresetID == presetID { nightPresetID = presets.dropFirst().first?.id ?? presets.first?.id ?? "" }
        save()
    }

    func applyPreset(id: String) {
        guard let preset = presets.first(where: { $0.id == id }) else { return }
        brightness = preset.brightness
        colorTemp = preset.colorTemp
        isDarkroom = preset.isDarkroom
        isAutoMode = false
        apply()
        showAdjustmentOverlay()
    }

    func refreshAutoStateIfNeeded() {
        guard isAutoMode else {
            save()
            return
        }

        let now = Calendar.current.component(.hour, from: Date()) * 60
            + Calendar.current.component(.minute, from: Date())
        let transition = max(15, min(240, transitionMinutes))
        let sunriseStart = sunriseMinutes - transition
        let sunsetStart = sunsetMinutes - transition

        let dayPreset = presets.first(where: { $0.id == dayPresetID }) ?? presets.first
        let nightPreset = presets.first(where: { $0.id == nightPresetID }) ?? presets.last ?? presets.first

        guard let dayPreset, let nightPreset else {
            save()
            return
        }

        if now >= sunriseMinutes && now < sunsetStart {
            brightness = dayPreset.brightness
            colorTemp = dayPreset.colorTemp
            isDarkroom = dayPreset.isDarkroom
        } else if now < sunriseStart || now >= sunsetMinutes {
            brightness = nightPreset.brightness
            colorTemp = nightPreset.colorTemp
            isDarkroom = nightPreset.isDarkroom
        } else if now >= sunriseStart && now < sunriseMinutes {
            let progress = Float(now - sunriseStart) / Float(max(1, transition))
            brightness = interpolate(from: nightPreset.brightness, to: dayPreset.brightness, progress: progress)
            colorTemp = interpolate(from: nightPreset.colorTemp, to: dayPreset.colorTemp, progress: progress)
            isDarkroom = false
        } else {
            let progress = Float(now - sunsetStart) / Float(max(1, transition))
            brightness = interpolate(from: dayPreset.brightness, to: nightPreset.brightness, progress: progress)
            colorTemp = interpolate(from: dayPreset.colorTemp, to: nightPreset.colorTemp, progress: progress)
            isDarkroom = false
        }
        apply()
    }

    private func interpolate(from start: Float, to end: Float, progress: Float) -> Float {
        let t = max(0, min(1, progress))
        let smooth = t * t * (3 - 2 * t)
        return start + (end - start) * smooth
    }

    private func interpolate(from start: Int, to end: Int, progress: Float) -> Int {
        let t = max(0, min(1, progress))
        let smooth = t * t * (3 - 2 * t)
        return start + Int(Float(end - start) * smooth)
    }

    private func apply() {
        UmbrellaBlueLightManager.apply(colorTemp: colorTemp, brightness: brightness, darkroom: isDarkroom)
        save()
    }

    private func showAdjustmentOverlay() {
        overlayController.show(brightness: brightness, colorTemp: colorTemp, isDarkroom: isDarkroom)
    }

    private func applyKeepAwake() {
        if isKeepAwakeEnabled {
            guard keepAwakeActivity == nil else { return }
            keepAwakeActivity = ProcessInfo.processInfo.beginActivity(
                options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled],
                reason: "Umbrella Keep Awake"
            )
        } else {
            releaseKeepAwake()
        }
    }

    private func releaseKeepAwake() {
        guard let keepAwakeActivity else { return }
        ProcessInfo.processInfo.endActivity(keepAwakeActivity)
        self.keepAwakeActivity = nil
    }

    private func save() {
        defaults.set(brightness, forKey: "umbrella.sunscreen.brightness")
        defaults.set(colorTemp, forKey: "umbrella.sunscreen.colorTemp")
        defaults.set(isDarkroom, forKey: "umbrella.sunscreen.darkroom")
        defaults.set(isAutoMode, forKey: "umbrella.sunscreen.auto")
        defaults.set(useLocationSchedule, forKey: "umbrella.sunscreen.useLocation")
        defaults.set(sunriseMinutes, forKey: "umbrella.sunscreen.sunrise")
        defaults.set(sunsetMinutes, forKey: "umbrella.sunscreen.sunset")
        defaults.set(transitionMinutes, forKey: "umbrella.sunscreen.transitionMinutes")
        defaults.set(isKeepAwakeEnabled, forKey: "umbrella.sunscreen.keepAwake")
        defaults.set(dayPresetID, forKey: "umbrella.sunscreen.dayPresetID")
        defaults.set(nightPresetID, forKey: "umbrella.sunscreen.nightPresetID")
        if let data = try? JSONEncoder().encode(presets) {
            defaults.set(data, forKey: presetKey)
        }
    }

    private static func loadPresets(from defaults: UserDefaults, key: String) -> [UmbrellaSunPreset] {
        if let data = defaults.data(forKey: key),
           let loaded = try? JSONDecoder().decode([UmbrellaSunPreset].self, from: data),
           !loaded.isEmpty {
            return loaded
        }
        return [
            UmbrellaSunPreset(name: "Daylight", brightness: 1.0, colorTemp: 6500),
            UmbrellaSunPreset(name: "Incandescent", brightness: 0.45, colorTemp: 2700),
            UmbrellaSunPreset(name: "Candle", brightness: 0.35, colorTemp: 1900),
        ]
    }
}

@MainActor
final class UmbrellaSimpleSnipFeature: ObservableObject {
    @Published var screenshotFolderPath: String
    @Published var recordingFolderPath: String
    @Published var revealScreenshotInFinder: Bool
    @Published var revealRecordingInFinder: Bool
    @Published var recordSystemAudio: Bool
    @Published var recordMicrophone: Bool
    @Published var isRecording = false
    @Published var lastSavedPath: String?
    @Published private(set) var screenCaptureState: UmbrellaPermissionState
    @Published private(set) var microphoneState: UmbrellaPermissionState
    @Published private(set) var debugLog: [String] = []

    private let defaults = UserDefaults.standard
    private let screenRecorder = UmbrellaScreenRecorder()
    private var recordingOverlay: UmbrellaRecordingOverlay?
    private var areaSelector: UmbrellaAreaSelectionOverlay?
    private var startRecordingTask: Task<Void, Never>?
    private var recordingStartGeneration = 0
    private var isStartingRecording = false
    private var requestedScreenPermissionThisSession = false

    init() {
        let screenshots = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Screenshots")
            .path
        let recordings = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies")
            .appendingPathComponent("Umbrella Helper Recordings")
            .path
        screenshotFolderPath = defaults.string(forKey: "umbrella.snip.screenshotFolder") ?? screenshots
        recordingFolderPath = defaults.string(forKey: "umbrella.snip.recordingFolder") ?? recordings
        revealScreenshotInFinder = defaults.object(forKey: "umbrella.snip.revealScreenshot") as? Bool ?? false
        revealRecordingInFinder = defaults.object(forKey: "umbrella.snip.revealRecording") as? Bool ?? false
        recordSystemAudio = defaults.object(forKey: "umbrella.snip.recordSystemAudio") as? Bool ?? true
        recordMicrophone = defaults.object(forKey: "umbrella.snip.recordMicrophone") as? Bool ?? false
        lastSavedPath = defaults.string(forKey: "umbrella.snip.lastSavedPath")
        screenCaptureState = CGPreflightScreenCaptureAccess() ? .allowed : .notRequested
        microphoneState = Self.microphoneState(from: AVCaptureDevice.authorizationStatus(for: .audio))
    }

    func start() {
        refreshPermissionState()
    }

    func stop() {
        startRecordingTask?.cancel()
        startRecordingTask = nil
        recordingOverlay?.dismiss()
        recordingOverlay = nil
        Task { await screenRecorder.cancelRecording() }
        isRecording = false
        isStartingRecording = false
    }

    func saveSettings() {
        defaults.set(screenshotFolderPath, forKey: "umbrella.snip.screenshotFolder")
        defaults.set(recordingFolderPath, forKey: "umbrella.snip.recordingFolder")
        defaults.set(revealScreenshotInFinder, forKey: "umbrella.snip.revealScreenshot")
        defaults.set(revealRecordingInFinder, forKey: "umbrella.snip.revealRecording")
        defaults.set(recordSystemAudio, forKey: "umbrella.snip.recordSystemAudio")
        defaults.set(recordMicrophone, forKey: "umbrella.snip.recordMicrophone")
    }

    func chooseScreenshotFolder() {
        if let path = chooseFolder(message: "Choose a folder for screenshots") {
            screenshotFolderPath = path
            saveSettings()
        }
    }

    func chooseRecordingFolder() {
        if let path = chooseFolder(message: "Choose a folder for recordings") {
            recordingFolderPath = path
            saveSettings()
        }
    }

    func openScreenshotFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: screenshotFolderPath))
    }

    func openRecordingFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: recordingFolderPath))
    }

    func revealLastSavedItem() {
        guard let lastSavedPath, FileManager.default.fileExists(atPath: lastSavedPath) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: lastSavedPath)])
    }

    func takeAreaSnip() {
        presentAreaSelector()
    }

    func takeWindowSnip() {
        _ = ensureScreenCaptureAccess()
        let output = screenshotOutputPath()
        runScreencapture(arguments: ["-i", "-w", "-x", output], outputPath: output, reveal: revealScreenshotInFinder)
    }

    func takeFullScreenSnip() {
        _ = ensureScreenCaptureAccess()
        let output = screenshotOutputPath()
        runScreencapture(arguments: ["-x", output], outputPath: output, reveal: revealScreenshotInFinder)
    }

    func copyTextFromAreaSnip() {
        presentAreaSelector(preferTextCopy: true)
    }

    func toggleRecording() {
        if isRecording || isStartingRecording {
            finishRecording()
        } else {
            recordArea()
        }
    }

    private func recordArea() {
        guard areaSelector == nil, !isStartingRecording, !isRecording else { return }
        _ = ensureScreenCaptureAccess()
        NSApp.activate(ignoringOtherApps: true)
        logDebug("record: presenting area selector")
        let selector = UmbrellaAreaSelectionOverlay(
            onComplete: { [weak self] selection, _ in
                self?.areaSelector = nil
                self?.beginRecording(selection: selection)
            },
            onCancel: { [weak self] in
                self?.areaSelector = nil
                self?.logDebug("record: selection cancelled")
            }
        )
        areaSelector = selector
        selector.present()
    }

    private func beginRecording(selection: CGRect) {
        guard !isRecording, !isStartingRecording else { return }
        recordingStartGeneration += 1
        let generation = recordingStartGeneration
        isStartingRecording = true
        logDebug("record begin: requesting permissions")

        startRecordingTask?.cancel()
        startRecordingTask = Task { @MainActor in
            defer { self.startRecordingTask = nil }

            var includeMic = false
            if recordMicrophone {
                includeMic = await ensureMicrophoneAccessAsync()
                if !includeMic {
                    logDebug("record begin: microphone unavailable, continuing without mic")
                }
            }

            let config = UmbrellaRecordingConfig(
                folder: URL(fileURLWithPath: recordingFolderPath),
                recordSystemAudio: recordSystemAudio,
                recordMicrophone: includeMic
            )
            logDebug("record begin: sysAudio=\(config.recordSystemAudio) mic=\(config.recordMicrophone)")

            do {
                let outputURL = try await screenRecorder.startRecording(selection: selection, config: config)
                guard generation == recordingStartGeneration else {
                    await screenRecorder.cancelRecording()
                    isStartingRecording = false
                    return
                }
                isStartingRecording = false
                isRecording = true
                screenCaptureState = .allowed

                let showsAudio = config.recordSystemAudio || config.recordMicrophone
                let overlay = UmbrellaRecordingOverlay(
                    selection: selection,
                    audioLevelMeter: screenRecorder.audioLevelMeter,
                    showsAudioVisualizer: showsAudio,
                    onStop: { [weak self] in self?.finishRecording() },
                    onCancel: { [weak self] in self?.cancelRecording() }
                )
                recordingOverlay = overlay
                overlay.present()
                UmbrellaRecordingSoundFeedback.playStart()
                logDebug("record started: \(outputURL.lastPathComponent)")
            } catch {
                isStartingRecording = false
                logDebug("record start failed: \(error.localizedDescription)")
                postNotification(title: "Umbrella Helper", body: "Could not start recording: \(error.localizedDescription)")
            }
        }
    }

    private func cancelPendingRecording() {
        recordingStartGeneration += 1
        startRecordingTask?.cancel()
        startRecordingTask = nil
        isStartingRecording = false
        Task { await screenRecorder.cancelRecording() }
        logDebug("record: pending start cancelled")
    }

    private func finishRecording() {
        if isStartingRecording {
            cancelPendingRecording()
            return
        }
        guard isRecording else { return }

        UmbrellaRecordingSoundFeedback.playStop()
        recordingOverlay?.dismiss()
        recordingOverlay = nil

        Task { @MainActor in
            do {
                guard let url = try await screenRecorder.stopRecording() else {
                    isRecording = false
                    logDebug("record stop: no file saved")
                    return
                }
                isRecording = false
                let path = url.path
                lastSavedPath = path
                defaults.set(path, forKey: "umbrella.snip.lastSavedPath")
                if recordMicrophone {
                    microphoneState = Self.microphoneState(from: AVCaptureDevice.authorizationStatus(for: .audio))
                }
                logDebug("record saved: \(url.lastPathComponent)")
                postNotification(title: "Umbrella Helper", body: "Saved recording \(url.lastPathComponent)")
                if revealRecordingInFinder {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            } catch {
                isRecording = false
                logDebug("record stop failed: \(error.localizedDescription)")
                postNotification(title: "Umbrella Helper", body: "Recording failed: \(error.localizedDescription)")
            }
        }
    }

    private func cancelRecording() {
        guard isRecording else { return }
        isRecording = false
        recordingOverlay?.dismiss()
        recordingOverlay = nil
        Task { await screenRecorder.cancelRecording() }
        logDebug("record: cancelled by user")
    }

    private func presentAreaSelector(preferTextCopy: Bool = false) {
        guard areaSelector == nil, !isStartingRecording, !isRecording else { return }
        _ = ensureScreenCaptureAccess()
        NSApp.activate(ignoringOtherApps: true)
        logDebug("snip: presenting area selector\(preferTextCopy ? " (text copy)" : "")")
        let selector = UmbrellaAreaSelectionOverlay(
            allowsTextCopy: true,
            initialTextCopy: preferTextCopy,
            onComplete: { [weak self] selection, copyText in
                guard let self else { return }
                self.areaSelector = nil
                self.logDebug("snip: selection complete copyText=\(copyText)")
                if copyText {
                    self.finishTextSnip(selection: selection)
                } else {
                    self.finishImageSnip(selection: selection)
                }
            },
            onCancel: { [weak self] in
                self?.areaSelector = nil
                self?.logDebug("snip: selection cancelled")
            }
        )
        areaSelector = selector
        selector.present()
    }

    private func finishImageSnip(selection: CGRect) {
        let output = screenshotOutputPath()
        captureSelectionRegion(selection, outputPath: output) { [weak self] success in
            guard let self else { return }
            if success {
                self.screenCaptureState = .allowed
                self.lastSavedPath = output
                self.defaults.set(output, forKey: "umbrella.snip.lastSavedPath")
                let copied = self.copyImageToClipboard(from: output)
                self.logDebug("snip clipboard copy: \(copied ? "ok" : "FAILED")")
                self.postNotification(
                    title: "Umbrella Helper",
                    body: "Saved \((output as NSString).lastPathComponent) and copied to clipboard"
                )
                if self.revealScreenshotInFinder {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: output)])
                }
            } else if !CGPreflightScreenCaptureAccess() {
                self.screenCaptureState = .notAllowed
                self.postNotification(
                    title: "Umbrella Helper",
                    body: "Screen capture access is required. Enable Umbrella Helper in Screen & System Audio Recording."
                )
            } else {
                self.postNotification(title: "Umbrella Helper", body: "Capture failed.")
            }
        }
    }

    private func finishTextSnip(selection: CGRect) {
        let output = textCaptureOutputPath()
        captureSelectionRegion(selection, outputPath: output) { [weak self] success in
            guard let self else { return }
            if success {
                self.screenCaptureState = .allowed
                self.extractTextToClipboard(from: output)
            } else if !CGPreflightScreenCaptureAccess() {
                self.screenCaptureState = .notAllowed
                self.postNotification(
                    title: "Umbrella Helper",
                    body: "Screen capture access is required. Enable Umbrella Helper in Screen & System Audio Recording."
                )
            } else {
                self.postNotification(title: "Umbrella Helper", body: "Text capture failed.")
            }
        }
    }

    private func captureSelectionRegion(_ selection: CGRect, outputPath: String, completion: @escaping (Bool) -> Void) {
        ensureDirectory(screenshotFolderPath)
        let args = Self.screencaptureRegionArguments(for: selection, outputPath: outputPath)
        logDebug("snip run: screencapture \(args.joined(separator: " "))")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = args
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.terminationHandler = { [weak self] task in
            let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let fileExists = FileManager.default.fileExists(atPath: outputPath)
            Task { @MainActor in
                guard let self else { return }
                self.logDebug("snip exit=\(task.terminationStatus) file=\(fileExists ? "yes" : "no")\(stderr.isEmpty ? "" : " stderr=\(stderr)")")
                completion(task.terminationStatus == 0 && fileExists)
            }
        }
        do {
            try process.run()
        } catch {
            logDebug("snip launch error: \(error.localizedDescription)")
            completion(false)
        }
    }

    private static func screencaptureRegionArguments(for selection: CGRect, outputPath: String) -> [String] {
        let globalTop = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        let x = Int(selection.minX.rounded())
        let y = Int((globalTop - selection.maxY).rounded())
        let w = max(1, Int(selection.width.rounded()))
        let h = max(1, Int(selection.height.rounded()))
        return ["-R", "\(x),\(y),\(w),\(h)", "-x", outputPath]
    }

    private func runScreencapture(arguments: [String], outputPath: String, reveal: Bool) {
        ensureDirectory(screenshotFolderPath)
        logDebug("snip run: screencapture \(arguments.joined(separator: " "))")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.terminationHandler = { [weak self] task in
            let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            Task { @MainActor in
                guard let self else { return }
                let fileExists = FileManager.default.fileExists(atPath: outputPath)
                self.logDebug("snip exit=\(task.terminationStatus) file=\(fileExists ? "yes" : "no")\(stderr.isEmpty ? "" : " stderr=\(stderr)")")
                if task.terminationStatus == 0, fileExists {
                    self.screenCaptureState = .allowed
                    self.lastSavedPath = outputPath
                    self.defaults.set(outputPath, forKey: "umbrella.snip.lastSavedPath")
                    let copied = self.copyImageToClipboard(from: outputPath)
                    self.logDebug("snip clipboard copy: \(copied ? "ok" : "FAILED")")
                    self.postNotification(
                        title: "Umbrella Helper",
                        body: "Saved \((outputPath as NSString).lastPathComponent) and copied to clipboard"
                    )
                    if reveal {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: outputPath)])
                    }
                } else if !CGPreflightScreenCaptureAccess() {
                    self.screenCaptureState = .notAllowed
                    self.postNotification(
                        title: "Umbrella Helper",
                        body: "Screen capture access is required. Enable Umbrella Helper in Screen & System Audio Recording."
                    )
                }
            }
        }
        do {
            try process.run()
        } catch {
            logDebug("snip launch error: \(error.localizedDescription)")
            postNotification(title: "Umbrella Helper", body: "Capture failed: \(error.localizedDescription)")
        }
    }

    private func runTextCapture(arguments: [String], outputPath: String) {
        logDebug("text run: screencapture \(arguments.joined(separator: " "))")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.terminationHandler = { [weak self] task in
            let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            Task { @MainActor in
                guard let self else { return }
                let fileExists = FileManager.default.fileExists(atPath: outputPath)
                self.logDebug("text exit=\(task.terminationStatus) file=\(fileExists ? "yes" : "no")\(stderr.isEmpty ? "" : " stderr=\(stderr)")")
                if task.terminationStatus == 0, fileExists {
                    self.screenCaptureState = .allowed
                    self.extractTextToClipboard(from: outputPath)
                } else if !CGPreflightScreenCaptureAccess() {
                    self.screenCaptureState = .notAllowed
                    self.postNotification(
                        title: "Umbrella Helper",
                        body: "Screen capture access is required. Enable Umbrella Helper in Screen & System Audio Recording."
                    )
                }
            }
        }

        do {
            try process.run()
        } catch {
            logDebug("text launch error: \(error.localizedDescription)")
            postNotification(title: "Umbrella Helper", body: "Text capture failed: \(error.localizedDescription)")
        }
    }

    private func screenshotOutputPath() -> String {
        ensureDirectory(screenshotFolderPath)
        let name = "snip-\(Self.timestamp()).png"
        return URL(fileURLWithPath: screenshotFolderPath).appendingPathComponent(name).path
    }

    private func textCaptureOutputPath() -> String {
        let name = "umbrella-text-\(Self.timestamp()).png"
        return FileManager.default.temporaryDirectory.appendingPathComponent(name).path
    }

    private func recordingOutputPathValue() -> String {
        ensureDirectory(recordingFolderPath)
        let name = "recording-\(Self.timestamp()).mov"
        return URL(fileURLWithPath: recordingFolderPath).appendingPathComponent(name).path
    }

    private func chooseFolder(message: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = message
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }

    private func ensureDirectory(_ path: String) {
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    @discardableResult
    private func copyImageToClipboard(from path: String) -> Bool {
        guard let image = NSImage(contentsOfFile: path) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([image])
    }

    private func extractTextToClipboard(from path: String) {
        guard let image = NSImage(contentsOfFile: path),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            logDebug("text OCR: could not read image at \(path)")
            postNotification(title: "Umbrella Helper", body: "Could not read captured image for text recognition.")
            try? FileManager.default.removeItem(atPath: path)
            return
        }

        Task.detached(priority: .userInitiated) { [weak self] in
            let recognizedText = Self.recognizeText(from: cgImage)
            await MainActor.run {
                guard let self else { return }
                if recognizedText.isEmpty {
                    self.logDebug("text OCR: 0 chars recognized")
                    self.postNotification(title: "Umbrella Helper", body: "No text detected in selected area.")
                } else {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    let ok = pasteboard.setString(recognizedText, forType: .string)
                    self.logDebug("text OCR: \(recognizedText.count) chars, clipboard \(ok ? "ok" : "FAILED")")
                    self.postNotification(title: "Umbrella Helper", body: "Copied text to clipboard.")
                }
            }
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    nonisolated private static func recognizeText(from image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
            let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
            let sorted = observations.sorted { lhs, rhs in
                let verticalDelta = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
                if verticalDelta > 0.03 {
                    return lhs.boundingBox.midY > rhs.boundingBox.midY
                }
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }
            return sorted
                .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        } catch {
            return ""
        }
    }

    func refreshPermissionState() {
        if CGPreflightScreenCaptureAccess() {
            screenCaptureState = .allowed
        } else if requestedScreenPermissionThisSession {
            screenCaptureState = .notAllowed
        } else {
            screenCaptureState = .notRequested
        }
        microphoneState = Self.microphoneState(from: AVCaptureDevice.authorizationStatus(for: .audio))
    }

    func openScreenCaptureSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Deterministic, user-initiated microphone request from the foreground
    /// Settings window. This reliably shows the TCC prompt (and registers the
    /// app in System Settings → Microphone) far better than requesting mid-capture.
    func requestMicrophonePermission() {
        Task { @MainActor in
            _ = await ensureMicrophoneAccessAsync()
        }
    }

    @discardableResult
    private func ensureMicrophoneAccessAsync() async -> Bool {
        refreshPermissionState()
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        logDebug("mic status=\(Self.statusName(status))")
        switch status {
        case .authorized:
            microphoneState = .allowed
            return true
        case .notDetermined:
            microphoneState = .notRequested
            NSApp.activate(ignoringOtherApps: true)
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
            microphoneState = granted ? .allowed : .notAllowed
            logDebug("mic request resolved: \(granted ? "granted" : "denied")")
            if !granted {
                postNotification(
                    title: "Umbrella Helper",
                    body: "Microphone access is required to record audio."
                )
            }
            return granted
        case .denied, .restricted:
            microphoneState = .notAllowed
            postNotification(
                title: "Umbrella Helper",
                body: "Enable Umbrella Helper in System Settings → Privacy & Security → Microphone."
            )
            openMicrophoneSettings()
            return false
        @unknown default:
            microphoneState = .notAllowed
            return false
        }
    }

    private func ensureScreenCaptureAccess() -> Bool {
        refreshPermissionState()
        logDebug("screen preflight=\(CGPreflightScreenCaptureAccess() ? "allowed" : "no")")
        if screenCaptureState == .allowed { return true }

        if !requestedScreenPermissionThisSession {
            requestedScreenPermissionThisSession = true
            let granted = CGRequestScreenCaptureAccess()
            screenCaptureState = granted ? .allowed : .notAllowed
            if granted { return true }
        }

        // CGPreflight/CGRequest can be stale on some macOS builds.
        // Allow screencapture to run so macOS can evaluate real-time TCC state.
        return false
    }

    func logDebug(_ message: String) {
        let entry = "[\(Self.debugTimestamp())] \(message)"
        debugLog.insert(entry, at: 0)
        if debugLog.count > 14 {
            debugLog.removeLast(debugLog.count - 14)
        }
    }

    func clearDebugLog() {
        debugLog.removeAll()
    }

    func copyDebugLog() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(debugLog.reversed().joined(separator: "\n"), forType: .string)
    }

    private static func debugTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }

    private static func statusName(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "authorized"
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .restricted: return "restricted"
        @unknown default: return "unknown"
        }
    }

    private static func microphoneState(from status: AVAuthorizationStatus) -> UmbrellaPermissionState {
        switch status {
        case .authorized:
            return .allowed
        case .notDetermined:
            return .notRequested
        case .denied, .restricted:
            return .notAllowed
        @unknown default:
            return .notAllowed
        }
    }

    private func postNotification(title: String, body: String) {
        let center = NSUserNotificationCenter.default
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = body
        center.deliver(notification)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }
}

@MainActor
final class UmbrellaNeewerHUDBridge: NSObject {
    private let notificationName = Notification.Name("com.kevinwolfrom.neewerhud.update")
    private var panel: UmbrellaNeewerHUDPanel?
    private var hideTimer: Timer?

    func start() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleUpdate(_:)),
            name: notificationName,
            object: nil
        )
    }

    func stop() {
        DistributedNotificationCenter.default().removeObserver(self)
        hideTimer?.invalidate()
        panel?.orderOut(nil)
    }

    @objc private func handleUpdate(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let brightness = userInfo["brightness"] as? Int,
              let kelvin = userInfo["kelvin"] as? Int
        else {
            return
        }
        let focusRaw = userInfo["focus"] as? String
        let focus: UmbrellaNeewerHUDFocus = {
            switch focusRaw {
            case "brightness": return .brightness
            case "temp": return .temp
            default: return .both
            }
        }()

        if panel == nil {
            panel = UmbrellaNeewerHUDPanel()
        }
        panel?.update(brightness: brightness, kelvin: kelvin, focus: focus)
        positionPanel()

        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { [weak self] _ in
            self?.panel?.fadeOut {
                self?.panel?.orderOut(nil)
            }
        }
    }

    private func positionPanel() {
        guard let panel else { return }
        let screen = MainActor.assumeIsolated { ActiveScreenTracker.presentationScreen(excluding: panel) }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - panel.frame.width / 2,
            y: visible.maxY - panel.frame.height - 18
        )
        panel.setFrameOrigin(origin)
    }
}

private enum UmbrellaNeewerHUDFocus {
    case brightness
    case temp
    case both
}

private final class UmbrellaNeewerHUDPanel: NSPanel {
    private let brightnessBar = UmbrellaHUDLevelBarView(tint: .systemYellow)
    private let tempBar = UmbrellaHUDLevelBarView(tint: .systemOrange)
    private let brightnessValue = NSTextField(labelWithString: "80%")
    private let tempValue = NSTextField(labelWithString: "5600K")

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 108),
            styleMask: [.nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        isFloatingPanel = true
        hidesOnDeactivate = false
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.94)
        isOpaque = false

        let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 108))
        contentView = root

        let title = NSTextField(labelWithString: "Neewer GL1")
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.textColor = .secondaryLabelColor
        title.frame = NSRect(x: 16, y: 78, width: 268, height: 16)
        root.addSubview(title)

        let brightnessLabel = NSTextField(labelWithString: "Brightness")
        brightnessLabel.font = .systemFont(ofSize: 11, weight: .medium)
        brightnessLabel.frame = NSRect(x: 16, y: 54, width: 90, height: 14)
        root.addSubview(brightnessLabel)
        brightnessValue.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        brightnessValue.alignment = .right
        brightnessValue.frame = NSRect(x: 212, y: 54, width: 72, height: 14)
        root.addSubview(brightnessValue)
        brightnessBar.frame = NSRect(x: 16, y: 42, width: 268, height: 8)
        root.addSubview(brightnessBar)

        let tempLabel = NSTextField(labelWithString: "Color")
        tempLabel.font = .systemFont(ofSize: 11, weight: .medium)
        tempLabel.frame = NSRect(x: 16, y: 22, width: 90, height: 14)
        root.addSubview(tempLabel)
        tempValue.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        tempValue.alignment = .right
        tempValue.frame = NSRect(x: 212, y: 22, width: 72, height: 14)
        root.addSubview(tempValue)
        tempBar.frame = NSRect(x: 16, y: 10, width: 268, height: 8)
        root.addSubview(tempBar)
    }

    func update(brightness: Int, kelvin: Int, focus: UmbrellaNeewerHUDFocus) {
        let clampedBri = max(1, min(100, brightness))
        let clampedKelvin = max(2900, min(7000, kelvin))
        brightnessValue.stringValue = "\(clampedBri)%"
        tempValue.stringValue = "\(clampedKelvin)K"
        brightnessBar.level = CGFloat(clampedBri) / 100
        tempBar.level = CGFloat(clampedKelvin - 2900) / CGFloat(7000 - 2900)
        brightnessBar.emphasis = (focus == .brightness || focus == .both) ? 1 : 0.35
        tempBar.emphasis = (focus == .temp || focus == .both) ? 1 : 0.35
        brightnessBar.needsDisplay = true
        tempBar.needsDisplay = true

        if !isVisible {
            alphaValue = 0
            orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                animator().alphaValue = 1
            }
        }
    }

    func fadeOut(completion: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = 0.18
                animator().alphaValue = 0
            },
            completionHandler: completion
        )
    }
}

private final class UmbrellaHUDLevelBarView: NSView {
    var level: CGFloat = 0
    var emphasis: CGFloat = 1
    let tint: NSColor

    init(tint: NSColor) {
        self.tint = tint
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let track = bounds.insetBy(dx: 0, dy: 1)
        guard track.width > 0, track.height > 0 else { return }

        let trackPath = NSBezierPath(roundedRect: track, xRadius: 4, yRadius: 4)
        NSColor.quaternaryLabelColor.withAlphaComponent(0.55).setFill()
        trackPath.fill()

        let clamped = max(0, min(1, level))
        let fillRect = NSRect(x: track.minX, y: track.minY, width: track.width * clamped, height: track.height)
        guard fillRect.width > 0.5 else { return }
        NSGraphicsContext.saveGraphicsState()
        trackPath.addClip()
        tint.withAlphaComponent(0.35 + 0.65 * emphasis).setFill()
        fillRect.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

// MARK: - Screen recording stack (ported from SimpleSnip)

extension NSScreen {
    var umbrellaDisplayID: CGDirectDisplayID {
        CGDirectDisplayID(truncatingIfNeeded: (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0)
    }
}

enum UmbrellaScreenCoordinateSpace {
    static var mainScreen: NSScreen? {
        let mainDisplayID = CGMainDisplayID()
        if let matched = NSScreen.screens.first(where: { $0.umbrellaDisplayID == mainDisplayID }) {
            return matched
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    static var mainDisplayAppKitMaxY: CGFloat {
        mainScreen?.frame.maxY ?? NSScreen.screens.map(\.frame.maxY).max() ?? 0
    }

    static func sourceRect(for selection: CGRect, on screen: NSScreen) -> CGRect {
        let intersection = screen.frame.intersection(selection)
        guard !intersection.isNull else { return .zero }
        return CGRect(
            x: intersection.origin.x - screen.frame.origin.x,
            y: screen.frame.maxY - intersection.maxY,
            width: intersection.width,
            height: intersection.height
        )
    }
}

final class UmbrellaAudioLevelMeter {
    private let lock = NSLock()
    private var systemLevel: Float = 0
    private var micLevel: Float = 0

    func reset() {
        lock.lock()
        systemLevel = 0
        micLevel = 0
        lock.unlock()
    }

    func ingestSystemAudio(_ sampleBuffer: CMSampleBuffer) {
        update(source: .system, level: Self.level(from: sampleBuffer))
    }

    func ingestMicrophone(_ sampleBuffer: CMSampleBuffer) {
        update(source: .microphone, level: Self.level(from: sampleBuffer))
    }

    func combinedLevel() -> Float {
        lock.lock()
        defer { lock.unlock() }
        return max(systemLevel, micLevel)
    }

    func applyDecay(factor: Float = 0.82) {
        lock.lock()
        systemLevel *= factor
        micLevel *= factor
        lock.unlock()
    }

    private enum Source {
        case system
        case microphone
    }

    private func update(source: Source, level: Float) {
        lock.lock()
        switch source {
        case .system:
            systemLevel = Self.smooth(systemLevel, new: level)
        case .microphone:
            micLevel = Self.smooth(micLevel, new: level)
        }
        lock.unlock()
    }

    private static func smooth(_ current: Float, new: Float) -> Float {
        max(current * 0.35, new)
    }

    private static func level(from sampleBuffer: CMSampleBuffer) -> Float {
        guard sampleBuffer.isValid,
              CMSampleBufferGetNumSamples(sampleBuffer) > 0,
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let basicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee else {
            return 0
        }

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return 0 }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        ) == noErr, let dataPointer, length > 0 else {
            return 0
        }

        let isFloat = (basicDescription.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isSigned = (basicDescription.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0
        let bytesPerSample = Int(basicDescription.mBitsPerChannel / 8)
        guard bytesPerSample > 0 else { return 0 }

        let channelCount = max(1, Int(basicDescription.mChannelsPerFrame))
        guard length >= bytesPerSample * channelCount else { return 0 }

        var peak: Float = 0
        let rawData = UnsafeRawPointer(dataPointer)

        if isFloat && bytesPerSample == 4 {
            let samples = rawData.assumingMemoryBound(to: Float.self)
            let sampleCount = length / bytesPerSample
            for index in 0..<sampleCount {
                peak = max(peak, abs(samples[index]))
            }
        } else if isSigned && bytesPerSample == 2 {
            let samples = rawData.assumingMemoryBound(to: Int16.self)
            let sampleCount = length / bytesPerSample
            let scale = 1.0 / Float(Int16.max)
            for index in 0..<sampleCount {
                peak = max(peak, abs(Float(samples[index]) * scale))
            }
        } else if bytesPerSample == 1 {
            let samples = rawData.assumingMemoryBound(to: UInt8.self)
            for index in 0..<length {
                let centered = (Float(samples[index]) - 127.5) / 127.5
                peak = max(peak, abs(centered))
            }
        }

        guard peak > 0 else { return 0 }
        let db = 20 * log10(peak)
        let normalized = (db + 50) / 50
        return min(1, max(0, normalized))
    }
}

enum UmbrellaRecordingSoundFeedback {
    static func playStart() { NSSound(named: NSSound.Name("Pop"))?.play() }
    static func playStop() { NSSound(named: NSSound.Name("Bottle"))?.play() }
}

final class UmbrellaAreaSelectionOverlay {
    private var overlayWindows: [OverlayWindow] = []
    private var startPoint: NSPoint?
    private var currentSelection: NSRect = .zero
    private var keyEventMonitor: Any?
    private var globalKeyEventMonitor: Any?
    private var textCopyKeyMonitor: Any?
    private var isFinishing = false
    private var textCopyModeActive = false
    private var textCopyRequested = false
    private var screenParametersObserver: NSObjectProtocol?
    private let allowsTextCopy: Bool
    private let initialTextCopy: Bool
    private let textCopyKeyCode: UInt16
    private let onComplete: (CGRect, Bool) -> Void
    private let onCancel: () -> Void

    init(
        allowsTextCopy: Bool = false,
        initialTextCopy: Bool = false,
        textCopyKeyCode: UInt16 = UInt16(kVK_Tab),
        onComplete: @escaping (CGRect, Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.allowsTextCopy = allowsTextCopy
        self.initialTextCopy = initialTextCopy
        self.textCopyKeyCode = textCopyKeyCode
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    func present() {
        isFinishing = false
        textCopyModeActive = allowsTextCopy && initialTextCopy
        textCopyRequested = textCopyModeActive
        NSCursor.crosshair.push()
        rebuildOverlayWindows()

        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.rebuildOverlayWindows() }
        }

        overlayWindows.first?.makeKeyAndOrderFront(nil)

        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53 else { return event }
            self.finish(cancelled: true)
            return nil
        }
        globalKeyEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            self?.finish(cancelled: true)
        }

        if allowsTextCopy {
            textCopyKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                guard let self, event.keyCode == self.textCopyKeyCode else { return event }
                if event.type == .keyDown {
                    self.textCopyRequested = true
                    self.setTextCopyModeActive(true)
                } else {
                    self.setTextCopyModeActive(false)
                }
                return nil
            }
        }
    }

    private func setTextCopyModeActive(_ active: Bool) {
        guard allowsTextCopy, textCopyModeActive != active else { return }
        textCopyModeActive = active
        refreshOverlays()
    }

    private func engageTextCopyMode() {
        guard allowsTextCopy else { return }
        textCopyRequested = true
        setTextCopyModeActive(true)
    }

    private func rebuildOverlayWindows() {
        guard !isFinishing else { return }
        overlayWindows.forEach { $0.orderOut(nil) }
        overlayWindows.removeAll()

        for screen in NSScreen.screens {
            let window = OverlayWindow(screen: screen, selector: self)
            window.selectionRect = currentSelection
            window.showsTextCopyIndicator = allowsTextCopy && textCopyModeActive
            overlayWindows.append(window)
            window.orderFrontRegardless()
        }

        if startPoint != nil {
            overlayWindows.first?.makeKey()
        } else {
            overlayWindows.first?.makeKeyAndOrderFront(nil)
        }
        refreshOverlays()
    }

    fileprivate func beginSelection(at point: NSPoint, in view: OverlayView) {
        startPoint = point
        currentSelection = NSRect(origin: point, size: .zero)
        textCopyRequested = allowsTextCopy && initialTextCopy
        textCopyModeActive = textCopyRequested
        refreshOverlays()

        view.window?.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp, .keyDown, .keyUp],
            timeout: .infinity,
            mode: .eventTracking
        ) { [weak self] event, stop in
            guard let self, let event else { return }
            switch event.type {
            case .leftMouseDragged:
                self.updateSelection(to: NSEvent.mouseLocation)
            case .leftMouseUp:
                self.completeSelection(at: NSEvent.mouseLocation)
                stop.pointee = true
            case .keyDown where event.keyCode == 53:
                self.finish(cancelled: true)
                stop.pointee = true
            case .keyDown where self.allowsTextCopy && event.keyCode == self.textCopyKeyCode:
                self.engageTextCopyMode()
            case .keyUp where self.allowsTextCopy && event.keyCode == self.textCopyKeyCode:
                self.setTextCopyModeActive(false)
            default:
                break
            }
        }
    }

    fileprivate func cancelSelection() {
        finish(cancelled: true)
    }

    private func updateSelection(to point: NSPoint) {
        guard let start = startPoint else { return }
        currentSelection = rect(from: start, to: point)
        refreshOverlays()
    }

    private func completeSelection(at point: NSPoint) {
        guard let start = startPoint else { return }
        let selection = rect(from: start, to: point)
        guard selection.width >= 10, selection.height >= 10 else {
            startPoint = nil
            currentSelection = .zero
            refreshOverlays()
            return
        }
        startPoint = nil
        finish(cancelled: false, selection: selection)
    }

    private func refreshOverlays() {
        for window in overlayWindows {
            window.selectionRect = currentSelection
            window.showsTextCopyIndicator = allowsTextCopy && textCopyModeActive
            window.contentView?.needsDisplay = true
        }
    }

    private func finish(cancelled: Bool, selection: NSRect = .zero) {
        guard !isFinishing else { return }
        isFinishing = true

        if let keyEventMonitor { NSEvent.removeMonitor(keyEventMonitor); self.keyEventMonitor = nil }
        if let globalKeyEventMonitor { NSEvent.removeMonitor(globalKeyEventMonitor); self.globalKeyEventMonitor = nil }
        if let textCopyKeyMonitor { NSEvent.removeMonitor(textCopyKeyMonitor); self.textCopyKeyMonitor = nil }
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
            self.screenParametersObserver = nil
        }
        NSCursor.pop()
        startPoint = nil
        currentSelection = .zero
        let copyText = !cancelled && allowsTextCopy && textCopyRequested
        textCopyModeActive = false
        textCopyRequested = false
        overlayWindows.forEach { $0.orderOut(nil) }
        overlayWindows.removeAll()

        let completion = onComplete
        let cancellation = onCancel
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if cancelled {
                cancellation()
            } else {
                completion(selection, copyText)
            }
        }
    }

    private func rect(from start: NSPoint, to end: NSPoint) -> NSRect {
        NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    fileprivate final class OverlayWindow: NSWindow {
        var selectionRect: NSRect = .zero
        var showsTextCopyIndicator = false
        private weak var selector: UmbrellaAreaSelectionOverlay?

        init(screen: NSScreen, selector: UmbrellaAreaSelectionOverlay) {
            self.selector = selector
            super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            level = .screenSaver
            isOpaque = false
            backgroundColor = .clear
            hasShadow = false
            ignoresMouseEvents = false
            collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            acceptsMouseMovedEvents = true
            contentView = OverlayView(selector: selector)
        }

        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { selector?.cancelSelection(); return }
            super.keyDown(with: event)
        }
    }

    fileprivate final class OverlayView: NSView {
        private weak var selector: UmbrellaAreaSelectionOverlay?

        init(selector: UmbrellaAreaSelectionOverlay) {
            self.selector = selector
            super.init(frame: .zero)
            wantsLayer = true
            layerContentsRedrawPolicy = .onSetNeedsDisplay
            layer?.backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override var isOpaque: Bool { false }
        override var isFlipped: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let selector else { return }
            window?.makeKey()
            selector.beginSelection(at: NSEvent.mouseLocation, in: self)
        }

        override func draw(_ dirtyRect: NSRect) {
            guard let window = window as? OverlayWindow else { return }
            NSColor.black.withAlphaComponent(0.18).setFill()
            bounds.fill()

            let selection = window.selectionRect
            guard selection.width > 0, selection.height > 0 else { return }
            let localSelection = window.convertFromScreen(selection)
            guard localSelection.intersects(bounds) else { return }
            let visible = localSelection.intersection(bounds)
            guard visible.width > 0, visible.height > 0 else { return }

            NSColor.clear.setFill()
            visible.fill(using: .clear)

            let path = NSBezierPath(rect: visible)
            path.lineWidth = 2.5
            effectiveAppearance.performAsCurrentDrawingAppearance {
                if window.showsTextCopyIndicator {
                    NSColor.systemGreen.setStroke()
                } else {
                    NSColor.systemCyan.setStroke()
                }
                path.stroke()
            }

            if window.showsTextCopyIndicator {
                drawTextCopyIndicator(near: visible)
            }
        }

        private func drawTextCopyIndicator(near selection: NSRect) {
            let label = "Text copy"
            let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white,
            ]
            let textSize = (label as NSString).size(withAttributes: attributes)
            let horizontalPadding: CGFloat = 10
            let verticalPadding: CGFloat = 5
            let pillSize = NSSize(
                width: textSize.width + horizontalPadding * 2,
                height: textSize.height + verticalPadding * 2
            )
            var pillOrigin = NSPoint(
                x: selection.maxX + 8,
                y: selection.minY - pillSize.height - 8
            )
            pillOrigin.x = min(pillOrigin.x, bounds.maxX - pillSize.width - 4)
            pillOrigin.y = max(pillOrigin.y, bounds.minY + 4)

            let pillRect = NSRect(origin: pillOrigin, size: pillSize)
            let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 6, yRadius: 6)
            effectiveAppearance.performAsCurrentDrawingAppearance {
                NSColor.systemGreen.setFill()
                pillPath.fill()
            }

            let textOrigin = NSPoint(
                x: pillRect.midX - textSize.width / 2,
                y: pillRect.midY - textSize.height / 2
            )
            (label as NSString).draw(at: textOrigin, withAttributes: attributes)
        }
    }
}

final class UmbrellaRecordingOverlay {
    private var borderWindows: [BorderWindow] = []
    private var controlPanel: ControlPanel?
    private var pulseTimer: Timer?
    private var keyEventMonitor: Any?
    private var pulseOn = false
    private let selection: NSRect
    private let onStop: () -> Void
    private let onCancel: () -> Void
    private let audioLevelMeter: UmbrellaAudioLevelMeter?
    private let showsAudioVisualizer: Bool

    init(
        selection: NSRect,
        audioLevelMeter: UmbrellaAudioLevelMeter? = nil,
        showsAudioVisualizer: Bool = false,
        onStop: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.selection = selection
        self.audioLevelMeter = audioLevelMeter
        self.showsAudioVisualizer = showsAudioVisualizer
        self.onStop = onStop
        self.onCancel = onCancel
    }

    func present() {
        for screen in NSScreen.screens {
            let window = BorderWindow(screen: screen, selection: selection)
            borderWindows.append(window)
            window.orderFrontRegardless()
        }

        let panel = ControlPanel(
            showsAudioVisualizer: showsAudioVisualizer,
            audioLevelMeter: audioLevelMeter,
            onStop: onStop
        )
        panel.show(for: selection)
        controlPanel = panel

        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.pulseOn.toggle()
            self.borderWindows.forEach { window in
                window.pulseOn = self.pulseOn
                window.contentView?.needsDisplay = true
            }
            self.controlPanel?.setRecordingPulse(self.pulseOn)
        }

        keyEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            DispatchQueue.main.async { self?.onCancel() }
        }
    }

    func dismiss() {
        if let keyEventMonitor { NSEvent.removeMonitor(keyEventMonitor); self.keyEventMonitor = nil }
        pulseTimer?.invalidate()
        pulseTimer = nil
        borderWindows.forEach { $0.orderOut(nil) }
        borderWindows.removeAll()
        controlPanel?.close()
        controlPanel = nil
    }

    fileprivate final class BorderWindow: NSWindow {
        var pulseOn = false
        init(screen: NSScreen, selection: NSRect) {
            super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            level = .screenSaver
            isOpaque = false
            backgroundColor = .clear
            ignoresMouseEvents = true
            collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            contentView = BorderView(selection: selection)
        }
    }

    private final class BorderView: NSView {
        let selection: NSRect
        init(selection: NSRect) {
            self.selection = selection
            super.init(frame: .zero)
        }
        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override var isFlipped: Bool { false }

        override func draw(_ dirtyRect: NSRect) {
            guard let window = window as? BorderWindow else { return }
            let localSelection = window.convertFromScreen(selection)
            guard localSelection.intersects(bounds) else { return }
            let visible = localSelection.intersection(bounds)
            guard visible.width > 0, visible.height > 0 else { return }

            let borderColor = NSColor.systemRed.withAlphaComponent(window.pulseOn ? 1.0 : 0.55)
            borderColor.setStroke()
            let path = NSBezierPath(rect: visible.insetBy(dx: 1.5, dy: 1.5))
            path.lineWidth = 3
            path.stroke()
            drawCornerBrackets(in: visible, color: borderColor)
        }

        private func drawCornerBrackets(in rect: NSRect, color: NSColor) {
            let length: CGFloat = 18
            color.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 4
            path.move(to: NSPoint(x: rect.minX, y: rect.minY + length))
            path.line(to: NSPoint(x: rect.minX, y: rect.minY))
            path.line(to: NSPoint(x: rect.minX + length, y: rect.minY))
            path.move(to: NSPoint(x: rect.maxX - length, y: rect.minY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.minY + length))
            path.move(to: NSPoint(x: rect.minX, y: rect.maxY - length))
            path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
            path.line(to: NSPoint(x: rect.minX + length, y: rect.maxY))
            path.move(to: NSPoint(x: rect.maxX - length, y: rect.maxY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - length))
            path.stroke()
        }
    }

    private final class AudioVisualizerView: NSView {
        private let barCount = 5
        private var level: Float = 0
        func setLevel(_ level: Float) { self.level = level; needsDisplay = true }
        override func draw(_ dirtyRect: NSRect) {
            let barWidth: CGFloat = 3
            let spacing: CGFloat = 2
            let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
            var x = (bounds.width - totalWidth) / 2
            let maxHeight = bounds.height - 2
            let baseY = bounds.minY + 1
            for index in 0..<barCount {
                let threshold = Float(index + 1) / Float(barCount + 1)
                let barLevel = max(0, min(1, (level - threshold * 0.55) / (1 - threshold * 0.55)))
                let height = max(2, CGFloat(barLevel) * maxHeight)
                let rect = NSRect(x: x, y: baseY, width: barWidth, height: height)
                let color = NSColor.systemRed.withAlphaComponent(0.35 + CGFloat(barLevel) * 0.65)
                color.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
                x += barWidth + spacing
            }
        }
    }

    private final class ControlPanel: NSPanel {
        private let onStop: () -> Void
        private let timeLabel: NSTextField
        private let recDot: NSView
        private let audioVisualizer: AudioVisualizerView?
        private let audioLevelMeter: UmbrellaAudioLevelMeter?
        private var elapsedTimer: Timer?
        private var visualizerTimer: Timer?
        private let startedAt = Date()

        init(showsAudioVisualizer: Bool, audioLevelMeter: UmbrellaAudioLevelMeter?, onStop: @escaping () -> Void) {
            self.onStop = onStop
            self.audioLevelMeter = audioLevelMeter
            self.audioVisualizer = showsAudioVisualizer ? AudioVisualizerView(frame: .zero) : nil

            timeLabel = NSTextField(labelWithString: "0:00")
            timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
            timeLabel.textColor = .labelColor
            timeLabel.alignment = .center

            recDot = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
            recDot.wantsLayer = true
            recDot.layer?.backgroundColor = NSColor.systemRed.cgColor
            recDot.layer?.cornerRadius = 5

            let panelHeight: CGFloat = showsAudioVisualizer ? 88 : 72
            super.init(
                contentRect: NSRect(x: 0, y: 0, width: 240, height: panelHeight),
                styleMask: [.nonactivatingPanel, .hudWindow],
                backing: .buffered,
                defer: false
            )
            level = .screenSaver
            isFloatingPanel = true
            hidesOnDeactivate = false
            backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92)
            isOpaque = false
            hasShadow = true
            collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let container = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: panelHeight))
            let recLabel = NSTextField(labelWithString: "REC")
            recLabel.font = NSFont.systemFont(ofSize: 12, weight: .bold)
            recLabel.textColor = .systemRed

            recDot.frame = NSRect(x: 16, y: panelHeight - 26, width: 10, height: 10)
            recLabel.frame = NSRect(x: 30, y: panelHeight - 29, width: 32, height: 16)
            timeLabel.frame = NSRect(x: 68, y: panelHeight - 32, width: 156, height: 22)

            if let audioVisualizer {
                audioVisualizer.frame = NSRect(x: 93, y: 34, width: 54, height: 18)
                container.addSubview(audioVisualizer)
            }

            let button = NSButton(title: "Stop Recording", target: nil, action: nil)
            button.bezelStyle = .rounded
            button.controlSize = .regular
            button.target = self
            button.action = #selector(stopClicked)
            button.frame = NSRect(x: 20, y: 8, width: 200, height: 28)

            container.addSubview(recDot)
            container.addSubview(recLabel)
            container.addSubview(timeLabel)
            container.addSubview(button)
            contentView = container

            elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.updateElapsedTime()
            }
            updateElapsedTime()

            if audioVisualizer != nil {
                visualizerTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                    self?.updateVisualizer()
                }
            }
        }

        func show(for selection: NSRect) {
            let screen = NSScreen.screens.first { $0.frame.intersects(selection) } ?? NSScreen.main ?? NSScreen.screens.first
            let visible = screen?.visibleFrame ?? selection
            var origin = NSPoint(x: selection.midX - frame.width / 2, y: selection.minY - frame.height - 16)
            if origin.y < visible.minY { origin.y = selection.maxY + 16 }
            origin.x = max(visible.minX + 8, min(origin.x, visible.maxX - frame.width - 8))
            origin.y = max(visible.minY + 8, min(origin.y, visible.maxY - frame.height - 8))
            setFrameOrigin(origin)
            orderFrontRegardless()
        }

        func setRecordingPulse(_ on: Bool) { recDot.alphaValue = on ? 1.0 : 0.35 }

        private func updateElapsedTime() {
            let elapsed = max(0, Date().timeIntervalSince(startedAt))
            let minutes = Int(elapsed) / 60
            let seconds = Int(elapsed) % 60
            timeLabel.stringValue = String(format: "%d:%02d", minutes, seconds)
        }

        private func updateVisualizer() {
            guard let audioLevelMeter else { return }
            audioLevelMeter.applyDecay()
            audioVisualizer?.setLevel(audioLevelMeter.combinedLevel())
        }

        override func close() {
            elapsedTimer?.invalidate()
            elapsedTimer = nil
            visualizerTimer?.invalidate()
            visualizerTimer = nil
            super.close()
        }

        @objc private func stopClicked() { onStop() }
    }
}

struct UmbrellaRecordingConfig {
    var folder: URL
    var recordSystemAudio: Bool
    var recordMicrophone: Bool
}

enum UmbrellaRecorderError: LocalizedError {
    case noDisplay
    case writerSetupFailed
    case noFramesCaptured
    case noMicrophone
    case microphonePermissionDenied

    var errorDescription: String? {
        switch self {
        case .noDisplay: return "Could not find a display for the selected area."
        case .writerSetupFailed: return "Could not set up the video writer."
        case .noFramesCaptured: return "No video frames were captured."
        case .noMicrophone: return "No microphone is available."
        case .microphonePermissionDenied: return "Microphone access is required to record audio."
        }
    }
}

final class UmbrellaScreenRecorder: NSObject, SCStreamDelegate {
    let audioLevelMeter = UmbrellaAudioLevelMeter()
    private let sampleQueue = DispatchQueue(label: "com.kevinwolfrom.umbrella.recorder")
    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var micAudioInput: AVAssetWriterInput?
    private var streamOutput: StreamOutput?
    private var microphoneCapture: MicrophoneCapture?
    private var outputURL: URL?
    private var frameCount = 0

    func startRecording(selection: CGRect, config: UmbrellaRecordingConfig) async throws -> URL {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let match = displayMatch(for: selection, displays: content.displays) else {
            throw UmbrellaRecorderError.noDisplay
        }

        try FileManager.default.createDirectory(at: config.folder, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let fileURL = config.folder.appendingPathComponent("recording-" + formatter.string(from: Date()) + ".mov")

        let cropRect = match.relativeRect
        let scaleFactor = displayScaleFactor(for: match.display.displayID, fallback: match.screen)
        let width = max(2, Int(cropRect.width) * scaleFactor)
        let height = max(2, Int(cropRect.height) * scaleFactor)

        let recordSystemAudio = config.recordSystemAudio
        let recordMicrophone = config.recordMicrophone
        audioLevelMeter.reset()

        let streamConfig = SCStreamConfiguration()
        streamConfig.sourceRect = cropRect
        streamConfig.width = width
        streamConfig.height = height
        streamConfig.queueDepth = 6
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        streamConfig.showsCursor = true
        streamConfig.capturesAudio = recordSystemAudio
        if recordSystemAudio {
            streamConfig.sampleRate = 48_000
            streamConfig.channelCount = 2
            streamConfig.excludesCurrentProcessAudio = false
        }
        if recordMicrophone {
            if #available(macOS 15.0, *) {
                streamConfig.captureMicrophone = true
                streamConfig.microphoneCaptureDeviceID = AVCaptureDevice.default(for: .audio)?.uniqueID
            }
        }
        streamConfig.pixelFormat = kCVPixelFormatType_32BGRA
        streamConfig.colorSpaceName = CGColorSpace.sRGB

        let filter = contentFilter(for: match.display, content: content)

        let writer = try AVAssetWriter(outputURL: fileURL, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw UmbrellaRecorderError.writerSetupFailed }
        writer.add(input)

        var systemInput: AVAssetWriterInput?
        if recordSystemAudio {
            let audioWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 48_000,
                AVEncoderBitRateKey: 192_000,
            ])
            audioWriterInput.expectsMediaDataInRealTime = true
            guard writer.canAdd(audioWriterInput) else { throw UmbrellaRecorderError.writerSetupFailed }
            writer.add(audioWriterInput)
            systemInput = audioWriterInput
            systemAudioInput = audioWriterInput
        }

        var micCapture: MicrophoneCapture?
        if recordMicrophone {
            let micInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: 44_100,
                AVEncoderBitRateKey: 128_000,
            ])
            micInput.expectsMediaDataInRealTime = true
            guard writer.canAdd(micInput) else { throw UmbrellaRecorderError.writerSetupFailed }
            writer.add(micInput)
            micAudioInput = micInput
            if #unavailable(macOS 15.0) {
                micCapture = try MicrophoneCapture(audioInput: micInput, audioLevelMeter: audioLevelMeter)
            }
        }

        guard writer.startWriting() else { throw writer.error ?? UmbrellaRecorderError.writerSetupFailed }

        let output = StreamOutput(
            videoInput: input,
            systemAudioInput: systemInput,
            micAudioInput: micAudioInput,
            audioLevelMeter: audioLevelMeter,
            parent: self
        )
        streamOutput = output
        assetWriter = writer
        videoInput = input
        microphoneCapture = micCapture
        outputURL = fileURL
        frameCount = 0

        let stream = SCStream(filter: filter, configuration: streamConfig, delegate: self)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: sampleQueue)
        if recordSystemAudio {
            try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: sampleQueue)
        }
        if recordMicrophone {
            if #available(macOS 15.0, *) {
                try stream.addStreamOutput(output, type: .microphone, sampleHandlerQueue: sampleQueue)
            }
        }
        self.stream = stream
        try await stream.startCapture()
        micCapture?.startCapture()
        writer.startSession(atSourceTime: .zero)
        output.sessionStarted = true
        micCapture?.sessionStarted = true
        return fileURL
    }

    func stopRecording() async throws -> URL? {
        guard let stream else { return nil }
        microphoneCapture?.stopCapture()
        microphoneCapture = nil
        try await stream.stopCapture()
        self.stream = nil

        if let output = streamOutput, let lastSample = output.lastVideoSampleBuffer, let input = videoInput, input.isReadyForMoreMediaData {
            let elapsed = CMTime(seconds: ProcessInfo.processInfo.systemUptime, preferredTimescale: 100) - output.firstVideoSampleTime
            let timing = CMSampleTimingInfo(duration: lastSample.duration, presentationTimeStamp: elapsed, decodeTimeStamp: lastSample.decodeTimeStamp)
            if let padded = try? CMSampleBuffer(copying: lastSample, withNewTiming: [timing]) {
                input.append(padded)
            }
        }

        assetWriter?.endSession(atSourceTime: streamOutput?.lastVideoSampleBuffer?.presentationTimeStamp ?? .zero)
        videoInput?.markAsFinished()
        systemAudioInput?.markAsFinished()
        micAudioInput?.markAsFinished()

        if let writer = assetWriter {
            await writer.finishWriting()
            if writer.status == .failed { throw writer.error ?? UmbrellaRecorderError.writerSetupFailed }
        }

        let url = outputURL
        let frames = frameCount
        assetWriter = nil
        videoInput = nil
        systemAudioInput = nil
        micAudioInput = nil
        streamOutput = nil
        outputURL = nil

        guard frames > 0, let url else {
            if let url { try? FileManager.default.removeItem(at: url) }
            throw UmbrellaRecorderError.noFramesCaptured
        }
        return url
    }

    func cancelRecording() async {
        microphoneCapture?.stopCapture()
        microphoneCapture = nil
        if let stream {
            try? await stream.stopCapture()
            self.stream = nil
        }
        let url = outputURL
        assetWriter?.cancelWriting()
        assetWriter = nil
        videoInput = nil
        systemAudioInput = nil
        micAudioInput = nil
        streamOutput = nil
        outputURL = nil
        frameCount = 0
        audioLevelMeter.reset()
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("Umbrella stream stopped with error")
    }

    private func contentFilter(for display: SCDisplay, content: SCShareableContent) -> SCContentFilter {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.kevinwolfrom.umbrella"
        let ownApps = content.applications.filter { $0.bundleIdentifier == bundleID }
        if !ownApps.isEmpty {
            return SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        }
        return SCContentFilter(display: display, excludingWindows: [])
    }

    private struct DisplayMatch {
        let display: SCDisplay
        let screen: NSScreen
        let relativeRect: CGRect
    }

    private func displayMatch(for selection: CGRect, displays: [SCDisplay]) -> DisplayMatch? {
        var best: DisplayMatch?
        var bestArea: CGFloat = 0
        for screen in NSScreen.screens {
            guard let display = displays.first(where: { $0.displayID == screen.umbrellaDisplayID }) else { continue }
            let intersection = screen.frame.intersection(selection)
            guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { continue }
            let area = intersection.width * intersection.height
            guard area > bestArea else { continue }
            bestArea = area
            best = DisplayMatch(display: display, screen: screen, relativeRect: UmbrellaScreenCoordinateSpace.sourceRect(for: selection, on: screen))
        }
        return best
    }

    private func displayScaleFactor(for displayID: CGDirectDisplayID, fallback screen: NSScreen) -> Int {
        if let mode = CGDisplayCopyDisplayMode(displayID) {
            return max(1, mode.pixelWidth / mode.width)
        }
        return max(1, Int(screen.backingScaleFactor))
    }

    private final class StreamOutput: NSObject, SCStreamOutput {
        let videoInput: AVAssetWriterInput
        let systemAudioInput: AVAssetWriterInput?
        let micAudioInput: AVAssetWriterInput?
        private let audioLevelMeter: UmbrellaAudioLevelMeter
        private unowned let parent: UmbrellaScreenRecorder
        var sessionStarted = false
        var firstVideoSampleTime: CMTime = .zero
        var firstSystemAudioSampleTime: CMTime = .zero
        var firstMicSampleTime: CMTime = .zero
        var lastVideoSampleBuffer: CMSampleBuffer?

        init(
            videoInput: AVAssetWriterInput,
            systemAudioInput: AVAssetWriterInput?,
            micAudioInput: AVAssetWriterInput?,
            audioLevelMeter: UmbrellaAudioLevelMeter,
            parent: UmbrellaScreenRecorder
        ) {
            self.videoInput = videoInput
            self.systemAudioInput = systemAudioInput
            self.micAudioInput = micAudioInput
            self.audioLevelMeter = audioLevelMeter
            self.parent = parent
        }

        func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
            guard sessionStarted, sampleBuffer.isValid else { return }
            switch outputType {
            case .screen:
                appendVideoSample(sampleBuffer)
            case .audio:
                appendSystemAudioSample(sampleBuffer)
            case .microphone:
                appendMicSample(sampleBuffer)
            @unknown default:
                break
            }
        }

        private func appendVideoSample(_ sampleBuffer: CMSampleBuffer) {
            guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let attachments = attachmentsArray.first,
                  let statusRawValue = attachments[SCStreamFrameInfo.status] as? Int,
                  let status = SCFrameStatus(rawValue: statusRawValue),
                  status == .complete else { return }
            guard videoInput.isReadyForMoreMediaData else { return }
            if firstVideoSampleTime == .zero { firstVideoSampleTime = sampleBuffer.presentationTimeStamp }
            let presentationTime = sampleBuffer.presentationTimeStamp - firstVideoSampleTime
            let timing = CMSampleTimingInfo(duration: sampleBuffer.duration, presentationTimeStamp: presentationTime, decodeTimeStamp: sampleBuffer.decodeTimeStamp)
            guard let retimed = try? CMSampleBuffer(copying: sampleBuffer, withNewTiming: [timing]) else { return }
            lastVideoSampleBuffer = retimed
            videoInput.append(retimed)
            parent.frameCount += 1
        }

        private func appendSystemAudioSample(_ sampleBuffer: CMSampleBuffer) {
            guard let systemAudioInput, systemAudioInput.isReadyForMoreMediaData else { return }
            if firstSystemAudioSampleTime == .zero { firstSystemAudioSampleTime = sampleBuffer.presentationTimeStamp }
            let presentationTime = sampleBuffer.presentationTimeStamp - firstSystemAudioSampleTime
            let timing = CMSampleTimingInfo(duration: sampleBuffer.duration, presentationTimeStamp: presentationTime, decodeTimeStamp: sampleBuffer.decodeTimeStamp)
            guard let retimed = try? CMSampleBuffer(copying: sampleBuffer, withNewTiming: [timing]) else { return }
            audioLevelMeter.ingestSystemAudio(sampleBuffer)
            systemAudioInput.append(retimed)
        }

        private func appendMicSample(_ sampleBuffer: CMSampleBuffer) {
            guard let micAudioInput, micAudioInput.isReadyForMoreMediaData else { return }
            if firstMicSampleTime == .zero { firstMicSampleTime = sampleBuffer.presentationTimeStamp }
            let presentationTime = sampleBuffer.presentationTimeStamp - firstMicSampleTime
            let timing = CMSampleTimingInfo(duration: sampleBuffer.duration, presentationTimeStamp: presentationTime, decodeTimeStamp: sampleBuffer.decodeTimeStamp)
            guard let retimed = try? CMSampleBuffer(copying: sampleBuffer, withNewTiming: [timing]) else { return }
            audioLevelMeter.ingestMicrophone(sampleBuffer)
            micAudioInput.append(retimed)
        }
    }

    private final class MicrophoneCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
        private let captureSession = AVCaptureSession()
        private let audioOutput = AVCaptureAudioDataOutput()
        private let queue = DispatchQueue(label: "com.kevinwolfrom.umbrella.mic")
        private let audioInput: AVAssetWriterInput
        private let audioLevelMeter: UmbrellaAudioLevelMeter
        var sessionStarted = false
        private var firstSampleTime: CMTime = .zero

        init(audioInput: AVAssetWriterInput, audioLevelMeter: UmbrellaAudioLevelMeter) throws {
            self.audioInput = audioInput
            self.audioLevelMeter = audioLevelMeter
            super.init()
            guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
                throw UmbrellaRecorderError.microphonePermissionDenied
            }
            captureSession.beginConfiguration()
            guard let device = AVCaptureDevice.default(for: .audio) else { throw UmbrellaRecorderError.noMicrophone }
            let deviceInput = try AVCaptureDeviceInput(device: device)
            guard captureSession.canAddInput(deviceInput) else { throw UmbrellaRecorderError.writerSetupFailed }
            captureSession.addInput(deviceInput)
            audioOutput.setSampleBufferDelegate(self, queue: queue)
            guard captureSession.canAddOutput(audioOutput) else { throw UmbrellaRecorderError.writerSetupFailed }
            captureSession.addOutput(audioOutput)
            captureSession.commitConfiguration()
        }

        func startCapture() { queue.async { [captureSession] in captureSession.startRunning() } }
        func stopCapture() {
            sessionStarted = false
            queue.async { [captureSession] in captureSession.stopRunning() }
        }

        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            guard sessionStarted, sampleBuffer.isValid, audioInput.isReadyForMoreMediaData else { return }
            if firstSampleTime == .zero { firstSampleTime = sampleBuffer.presentationTimeStamp }
            let presentationTime = sampleBuffer.presentationTimeStamp - firstSampleTime
            let timing = CMSampleTimingInfo(duration: sampleBuffer.duration, presentationTimeStamp: presentationTime, decodeTimeStamp: sampleBuffer.decodeTimeStamp)
            guard let retimed = try? CMSampleBuffer(copying: sampleBuffer, withNewTiming: [timing]) else { return }
            audioLevelMeter.ingestMicrophone(sampleBuffer)
            audioInput.append(retimed)
        }
    }
}
