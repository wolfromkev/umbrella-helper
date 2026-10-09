import AppKit
import Combine
import CoreGraphics
import CoreLocation
@preconcurrency import ColorSync
import Darwin
import SwiftUI

struct UmbrellaSunPreset: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var brightness: Float
    var colorTemp: Int
    var isDarkroom: Bool
    var isFilmMode: Bool

    init(
        id: String = UUID().uuidString,
        name: String,
        brightness: Float,
        colorTemp: Int,
        isDarkroom: Bool = false,
        isFilmMode: Bool = false
    ) {
        self.id = id
        self.name = name
        self.brightness = brightness
        self.colorTemp = colorTemp
        self.isDarkroom = isDarkroom
        self.isFilmMode = isFilmMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        brightness = try container.decode(Float.self, forKey: .brightness)
        colorTemp = try container.decode(Int.self, forKey: .colorTemp)
        isDarkroom = try container.decodeIfPresent(Bool.self, forKey: .isDarkroom) ?? false
        isFilmMode = try container.decodeIfPresent(Bool.self, forKey: .isFilmMode) ?? false
    }
}


private enum UmbrellaBlueLightManager {
    /// Near-black gamma for Film Mode external displays (true 0 can look odd on some panels).
    private static let filmModeExternalChannels: (Float, Float, Float) = (0.01, 0.01, 0.01)

    static func apply(colorTemp: Int, brightness: Float, darkroom: Bool, filmMode: Bool) {
        let dim = max(0.05, min(1, brightness))
        let channels: (Float, Float, Float)
        if darkroom {
            channels = (0.8 * dim, 0.0, 0.0)
        } else {
            let multipliers = gammaMultipliers(forKelvin: colorTemp)
            channels = (multipliers.0 * dim, multipliers.1 * dim, multipliers.2 * dim)
        }

        for display in onlineDisplayIDs() {
            let applied = filmMode && !isBuiltInDisplay(display)
                ? filmModeExternalChannels
                : channels
            CGSetDisplayTransferByFormula(
                display,
                0, applied.0, 1,
                0, applied.1, 1,
                0, applied.2, 1
            )
        }
    }

    private static func isBuiltInDisplay(_ displayID: CGDirectDisplayID) -> Bool {
        CGDisplayIsBuiltin(displayID) != 0
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
    @Published var isFilmModeEnabled: Bool
    @Published var presets: [UmbrellaSunPreset]
    @Published var dayPresetID: String
    @Published var nightPresetID: String
    @Published var locationName: String? = nil
    @Published var locationLatitude: Double? = nil
    @Published var locationLongitude: Double? = nil
    /// Up to 3 preset IDs shown in the menu bar Screen section.
    @Published var menuBarFavoriteIDs: [String]

    static let maxMenuBarFavorites = 3

    private var keepAwakeActivity: NSObjectProtocol?
    private var timer: Timer?
    private var screenChangeObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var colorSyncObservers: [NSObjectProtocol] = []
    private var pendingApplyWorkItem: DispatchWorkItem?
    private var screenChangeWorkItem: DispatchWorkItem?
    private var followUpReapplyWorkItem: DispatchWorkItem?
    /// Delayed LUT restores after a snip. Kept separate so a screen-parameter
    /// notification cannot cancel the later pulses.
    private var captureReapplyWorkItems: [DispatchWorkItem] = []
    private var needsPersist = false
    private var lastSolarComputationDay: Int?
    private let locationProvider = UmbrellaLocationProvider()
    private let defaults = UserDefaults.standard
    private let presetKey = "umbrella.sunscreen.presets"
    private let menuBarFavoritesKey = "umbrella.sunscreen.menuBarFavoriteIDs"
    private let latitudeKey = "umbrella.sunscreen.latitude"
    private let longitudeKey = "umbrella.sunscreen.longitude"
    /// Set while Film Mode gamma is applied; cleared only on clean `stop()`.
    /// If still set at next launch, gamma is restored and Film Mode is turned off.
    private let filmModeDirtyKey = "umbrella.sunscreen.filmModeDirty"
    /// Coalesce rapid slider gamma writes (~20 Hz).
    private static let applyThrottleInterval: TimeInterval = 0.05
    /// Wait for display reconnect / wake to settle before re-applying gamma.
    private static let screenChangeDebounceInterval: TimeInterval = 0.35
    /// WindowServer and ColorSync often reset the LUT again after the selector
    /// appears and after `screencapture` exits. Pulse until that settles.
    private static let captureReapplyDelays: [TimeInterval] = [0.2, 0.55, 1.1, 2.0]
    /// Second pass after ColorSync / screen-parameter clobbers.
    private static let followUpReapplyDelay: TimeInterval = 0.6

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
        isFilmModeEnabled = defaults.object(forKey: "umbrella.sunscreen.filmMode") as? Bool ?? false
        presets = loadedPresets
        dayPresetID = defaults.string(forKey: "umbrella.sunscreen.dayPresetID")
            ?? loadedPresets.first?.id
            ?? ""
        nightPresetID = defaults.string(forKey: "umbrella.sunscreen.nightPresetID")
            ?? loadedPresets.dropFirst().first?.id
            ?? loadedPresets.first?.id
            ?? ""
        let storedFavorites = defaults.stringArray(forKey: menuBarFavoritesKey) ?? []
        let validFavoriteIDs = storedFavorites.filter { id in loadedPresets.contains(where: { $0.id == id }) }
        if validFavoriteIDs.isEmpty {
            menuBarFavoriteIDs = Array(loadedPresets.prefix(Self.maxMenuBarFavorites).map(\.id))
        } else {
            menuBarFavoriteIDs = Array(validFavoriteIDs.prefix(Self.maxMenuBarFavorites))
        }
        defaults.set(menuBarFavoriteIDs, forKey: menuBarFavoritesKey)
        if let data = try? JSONEncoder().encode(presets) {
            defaults.set(data, forKey: presetKey)
        }

        if defaults.object(forKey: latitudeKey) != nil {
            locationLatitude = defaults.double(forKey: latitudeKey)
        }
        if defaults.object(forKey: longitudeKey) != nil {
            locationLongitude = defaults.double(forKey: longitudeKey)
        }
        if let latitude = locationLatitude, let longitude = locationLongitude {
            locationName = UmbrellaSolarSchedule.coordinateLabel(
                CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            )
        }

        locationProvider.onLocation = { [weak self] coordinate in
            self?.handleLocation(coordinate)
        }
        locationProvider.onPlaceName = { [weak self] name in
            self?.locationName = name
        }
        locationProvider.onStatus = { [weak self] message in
            self?.locationName = message
        }
    }

    var menuBarFavoritePresets: [UmbrellaSunPreset] {
        menuBarFavoriteIDs.compactMap { id in presets.first(where: { $0.id == id }) }
    }

    func start() {
        // Always restore system gamma first (covers force-quit while Film Mode was on).
        UmbrellaBlueLightManager.reset()
        if defaults.bool(forKey: filmModeDirtyKey) {
            // Unclean exit: don't re-black externals — leave Film Mode off until the user toggles it.
            isFilmModeEnabled = false
            defaults.set(false, forKey: filmModeDirtyKey)
            defaults.set(false, forKey: "umbrella.sunscreen.filmMode")
        }

        applyKeepAwake()
        if useLocationSchedule {
            refreshSolarTimesIfNeeded(force: true)
            locationProvider.start()
        }
        refreshAutoStateIfNeeded()
        apply(persist: true, immediate: true)
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAutoStateIfNeeded()
            }
        }
        if screenChangeObserver == nil {
            screenChangeObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handlePossibleGammaClobber()
                }
            }
        }
        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handlePossibleGammaClobber()
                }
            }
        }
        observeColorSyncProfileChanges()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        locationProvider.stop()
        pendingApplyWorkItem?.cancel()
        pendingApplyWorkItem = nil
        screenChangeWorkItem?.cancel()
        screenChangeWorkItem = nil
        followUpReapplyWorkItem?.cancel()
        followUpReapplyWorkItem = nil
        cancelCaptureReapplyPulses()
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
            self.screenChangeObserver = nil
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        let colorSyncCenter = DistributedNotificationCenter.default()
        colorSyncObservers.forEach { colorSyncCenter.removeObserver($0) }
        colorSyncObservers.removeAll()
        releaseKeepAwake()
        UmbrellaBlueLightManager.reset()
        defaults.set(false, forKey: filmModeDirtyKey)
    }

    /// Updates brightness. Pass `commit: false` while a slider is dragging; call `commitPendingChanges()` on mouse-up.
    func setBrightness(_ value: Float, commit: Bool = true) {
        isAutoMode = false
        brightness = max(0.05, min(1, value))
        isDarkroom = false
        apply(persist: commit, immediate: commit)
    }

    func adjustBrightness(by delta: Float) {
        setBrightness(brightness + delta, commit: true)
    }

    /// Updates color temp. Pass `commit: false` while a slider is dragging; call `commitPendingChanges()` on mouse-up.
    func setColorTemp(_ value: Int, commit: Bool = true) {
        isAutoMode = false
        colorTemp = max(1200, min(6500, value))
        isDarkroom = false
        apply(persist: commit, immediate: commit)
    }

    func adjustColorTemp(by delta: Int) {
        setColorTemp(colorTemp + delta, commit: true)
    }

    /// Flush throttled gamma and persist after continuous slider editing ends.
    func commitPendingChanges() {
        apply(persist: true, immediate: true)
    }

    /// Emergency reset: restore system ColorSync, then re-apply current Umbrella settings once.
    func restoreDisplayColor() {
        pendingApplyWorkItem?.cancel()
        pendingApplyWorkItem = nil
        screenChangeWorkItem?.cancel()
        screenChangeWorkItem = nil
        followUpReapplyWorkItem?.cancel()
        followUpReapplyWorkItem = nil
        cancelCaptureReapplyPulses()
        UmbrellaBlueLightManager.reset()
        apply(persist: true, immediate: true)
    }

    /// Screen capture and the snip selector often wipe `CGSetDisplayTransferByFormula`.
    /// Re-apply the current brightness immediately, then again while WindowServer settles.
    func reapplyGammaAfterDisplayCapture() {
        screenChangeWorkItem?.cancel()
        screenChangeWorkItem = nil
        followUpReapplyWorkItem?.cancel()
        followUpReapplyWorkItem = nil
        cancelCaptureReapplyPulses()
        apply(persist: false, immediate: true)
        for delay in Self.captureReapplyDelays {
            let work = DispatchWorkItem { [weak self] in
                self?.apply(persist: false, immediate: true)
            }
            captureReapplyWorkItems.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func cancelCaptureReapplyPulses() {
        captureReapplyWorkItems.forEach { $0.cancel() }
        captureReapplyWorkItems.removeAll()
    }

    func setDarkroom(_ enabled: Bool) {
        if enabled { isAutoMode = false }
        isDarkroom = enabled
        apply(persist: true, immediate: true)
    }

    func setAutoMode(_ enabled: Bool) {
        isAutoMode = enabled
        refreshAutoStateIfNeeded()
    }

    func setUseLocationSchedule(_ enabled: Bool) {
        useLocationSchedule = enabled
        if enabled {
            locationName = locationName ?? "Finding sunrise and sunset…"
            refreshSolarTimesIfNeeded(force: true)
            locationProvider.start()
        } else {
            locationProvider.stop()
            if locationLatitude == nil {
                locationName = nil
            }
        }
        save()
        refreshAutoStateIfNeeded()
    }

    func setKeepAwake(_ enabled: Bool) {
        isKeepAwakeEnabled = enabled
        applyKeepAwake()
        save()
    }

    func setFilmMode(_ enabled: Bool) {
        isFilmModeEnabled = enabled
        apply(persist: true, immediate: true)
    }

    func toggleFilmMode() {
        setFilmMode(!isFilmModeEnabled)
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
            isDarkroom: isDarkroom,
            isFilmMode: isFilmModeEnabled
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
        menuBarFavoriteIDs.removeAll { $0 == presetID }
        if dayPresetID == presetID { dayPresetID = presets.first?.id ?? "" }
        if nightPresetID == presetID { nightPresetID = presets.dropFirst().first?.id ?? presets.first?.id ?? "" }
        save()
    }

    func isMenuBarFavorite(_ presetID: String) -> Bool {
        menuBarFavoriteIDs.contains(presetID)
    }

    @discardableResult
    func toggleMenuBarFavorite(_ presetID: String) -> Bool {
        guard presets.contains(where: { $0.id == presetID }) else { return false }
        if let index = menuBarFavoriteIDs.firstIndex(of: presetID) {
            menuBarFavoriteIDs.remove(at: index)
            save()
            return true
        }
        guard menuBarFavoriteIDs.count < Self.maxMenuBarFavorites else { return false }
        menuBarFavoriteIDs.append(presetID)
        save()
        return true
    }

    func applyPreset(id: String) {
        guard let preset = presets.first(where: { $0.id == id }) else { return }
        brightness = preset.brightness
        colorTemp = preset.colorTemp
        isDarkroom = preset.isDarkroom
        isFilmModeEnabled = preset.isFilmMode
        isAutoMode = false
        apply(persist: true, immediate: true)
    }

    func refreshAutoStateIfNeeded() {
        if useLocationSchedule {
            refreshSolarTimesIfNeeded(force: false)
        }

        guard isAutoMode else {
            // Capture / ColorSync can wipe the LUT even when auto is off.
            apply(persist: false, immediate: true)
            return
        }

        let now = UmbrellaSolarSchedule.minutesOfDay(from: Date())
        let dayPreset = presets.first(where: { $0.id == dayPresetID }) ?? presets.first
        let nightPreset = presets.first(where: { $0.id == nightPresetID }) ?? presets.last ?? presets.first

        guard let dayPreset, let nightPreset else {
            save()
            return
        }

        let progress = UmbrellaSolarSchedule.daylightProgress(
            at: now,
            sunrise: sunriseMinutes,
            sunset: sunsetMinutes,
            transition: transitionMinutes
        )

        if progress <= 0.001 {
            brightness = nightPreset.brightness
            colorTemp = nightPreset.colorTemp
            isDarkroom = nightPreset.isDarkroom
        } else {
            brightness = lerp(nightPreset.brightness, dayPreset.brightness, progress)
            colorTemp = lerp(nightPreset.colorTemp, dayPreset.colorTemp, progress)
            isDarkroom = false
        }
        apply(persist: true, immediate: true)
    }

    private func lerp(_ start: Float, _ end: Float, _ progress: Float) -> Float {
        let t = max(0, min(1, progress))
        return start + (end - start) * t
    }

    private func lerp(_ start: Int, _ end: Int, _ progress: Float) -> Int {
        let t = max(0, min(1, progress))
        return start + Int((Float(end - start) * t).rounded())
    }

    private func handleLocation(_ coordinate: CLLocationCoordinate2D) {
        locationLatitude = coordinate.latitude
        locationLongitude = coordinate.longitude
        defaults.set(coordinate.latitude, forKey: latitudeKey)
        defaults.set(coordinate.longitude, forKey: longitudeKey)
        refreshSolarTimesIfNeeded(force: true)
        refreshAutoStateIfNeeded()
    }

    private func refreshSolarTimesIfNeeded(force: Bool) {
        guard useLocationSchedule,
              let latitude = locationLatitude,
              let longitude = locationLongitude else { return }

        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date())
        guard force || day != lastSolarComputationDay else { return }
        lastSolarComputationDay = day

        guard let times = UmbrellaSolarSchedule.sunTimes(
            date: Date(),
            latitude: latitude,
            longitude: longitude
        ) else { return }

        sunriseMinutes = times.sunrise
        sunsetMinutes = times.sunset
    }

    private func observeColorSyncProfileChanges() {
        guard colorSyncObservers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        let names = [
            kColorSyncDeviceProfilesNotification,
            kColorSyncDisplayDeviceProfilesNotification
        ].compactMap { constant -> Notification.Name? in
            guard let name = constant?.takeUnretainedValue() as String? else { return nil }
            return Notification.Name(name)
        }
        for name in names {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.handlePossibleGammaClobber()
                }
            }
            colorSyncObservers.append(observer)
        }
    }

    /// Re-apply current settings after something else reset the display LUT.
    /// Do not ColorSync-restore first — that flashes identity brightness and
    /// races with `screencapture`, which can then restore the identity table.
    private func handlePossibleGammaClobber() {
        screenChangeWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.apply(persist: false, immediate: true)
            self.scheduleFollowUpReapply(after: Self.followUpReapplyDelay)
        }
        screenChangeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.screenChangeDebounceInterval, execute: work)
    }

    private func scheduleFollowUpReapply(after delay: TimeInterval) {
        followUpReapplyWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.followUpReapplyWorkItem = nil
            self.apply(persist: false, immediate: true)
        }
        followUpReapplyWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func apply(persist: Bool, immediate: Bool) {
        if persist { needsPersist = true }

        if immediate {
            pendingApplyWorkItem?.cancel()
            pendingApplyWorkItem = nil
            performApply()
            return
        }

        guard pendingApplyWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingApplyWorkItem = nil
            self.performApply()
        }
        pendingApplyWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.applyThrottleInterval, execute: work)
    }

    private func performApply() {
        UmbrellaBlueLightManager.apply(
            colorTemp: colorTemp,
            brightness: brightness,
            darkroom: isDarkroom,
            filmMode: isFilmModeEnabled
        )
        // Dirty while Film Mode gamma is live so force-quit can recover on next launch.
        defaults.set(isFilmModeEnabled, forKey: filmModeDirtyKey)
        if needsPersist {
            needsPersist = false
            save()
        }
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
        defaults.set(isFilmModeEnabled, forKey: "umbrella.sunscreen.filmMode")
        defaults.set(dayPresetID, forKey: "umbrella.sunscreen.dayPresetID")
        defaults.set(nightPresetID, forKey: "umbrella.sunscreen.nightPresetID")
        defaults.set(menuBarFavoriteIDs, forKey: menuBarFavoritesKey)
        if let locationLatitude {
            defaults.set(locationLatitude, forKey: latitudeKey)
        }
        if let locationLongitude {
            defaults.set(locationLongitude, forKey: longitudeKey)
        }
        if let data = try? JSONEncoder().encode(presets) {
            defaults.set(data, forKey: presetKey)
        }
    }

    private static func loadPresets(from defaults: UserDefaults, key: String) -> [UmbrellaSunPreset] {
        var loaded: [UmbrellaSunPreset]
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([UmbrellaSunPreset].self, from: data),
           !decoded.isEmpty {
            loaded = decoded
        } else {
            loaded = defaultPresets()
        }
        if !loaded.contains(where: { $0.isFilmMode || $0.name.caseInsensitiveCompare("Film Mode") == .orderedSame }) {
            loaded.append(
                UmbrellaSunPreset(
                    name: "Film Mode",
                    brightness: 1.0,
                    colorTemp: 6500,
                    isDarkroom: false,
                    isFilmMode: true
                )
            )
        }
        return loaded
    }

    private static func defaultPresets() -> [UmbrellaSunPreset] {
        [
            UmbrellaSunPreset(name: "Daylight", brightness: 1.0, colorTemp: 6500),
            UmbrellaSunPreset(name: "Incandescent", brightness: 0.45, colorTemp: 2700),
            UmbrellaSunPreset(name: "Candle", brightness: 0.35, colorTemp: 1900),
            UmbrellaSunPreset(
                name: "Film Mode",
                brightness: 1.0,
                colorTemp: 6500,
                isDarkroom: false,
                isFilmMode: true
            ),
        ]
    }
}

