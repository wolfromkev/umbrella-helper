import AppKit
import Combine
import Foundation

enum UmbrellaNeewerPowerOnMode: String, Codable, CaseIterable, Identifiable {
    case lastValue
    case defaultValue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lastValue: return "Last value"
        case .defaultValue: return "Default value"
        }
    }

    var detail: String {
        switch self {
        case .lastValue:
            return "After a Mac restart, the first time you turn the light on it restores the last brightness and warmth you used."
        case .defaultValue:
            return "After a Mac restart, the first time you turn the light on it applies your default brightness and warmth."
        }
    }
}

struct UmbrellaNeewerPreset: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    /// 1...100
    var brightness: Int
    /// Kelvin, e.g. 5600
    var kelvin: Int

    init(id: String = UUID().uuidString, name: String, brightness: Int, kelvin: Int) {
        self.id = id
        self.name = name
        self.brightness = max(1, min(100, brightness))
        self.kelvin = max(2900, min(7000, kelvin))
    }

    /// NeewerLite temperature units (29...70).
    var temperature: Int {
        max(29, min(70, Int((Double(kelvin) / 100.0).rounded())))
    }
}


@MainActor
final class UmbrellaNeewerLightFeature: ObservableObject {
    static let minBrightness = 1
    static let maxBrightness = 100
    static let minKelvin = 2900
    static let maxKelvin = 7000
    static let kelvinStep = 100

    @Published var powerOnMode: UmbrellaNeewerPowerOnMode
    @Published var brightness: Int
    @Published var kelvin: Int
    @Published var defaultBrightness: Int
    @Published var defaultKelvin: Int
    @Published var presets: [UmbrellaNeewerPreset]
    @Published var statusMessage: String?
    @Published var isBusy = false
    @Published var isPoweredOn = false
    @Published var isReachable = false
    @Published var hasSyncedFromLight = false
    @Published var isSyncingFromLight = false
    /// Up to 3 preset IDs shown in the menu bar Light section.
    @Published var menuBarFavoriteIDs: [String]

    static let maxMenuBarFavorites = 3

    private let defaults = UserDefaults.standard
    private let configURL: URL
    private let bootMarkerURL: URL
    private let lightName = "NEEWER-GL1 PRO"
    private let apiBase = "http://localhost:18486"
    private let apiUA = "neewerlite.sdPlugin/umbrella"
    private let presetKey = "umbrella.neewer.presets"
    private let menuBarFavoritesKey = "umbrella.neewer.menuBarFavoriteIDs"
    private let powerOnModeKey = "umbrella.neewer.powerOnMode"
    private let defaultBrightnessKey = "umbrella.neewer.defaultBrightness"
    private let defaultKelvinKey = "umbrella.neewer.defaultKelvin"
    private var pendingApplyFocus = "both"
    private var coalesceGeneration: UInt64 = 0
    private var isSendingCCT = false
    private var queuedCCT: (brightness: Int, kelvin: Int, focus: String)?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        configURL = home
            .appendingPathComponent(".config/karabiner/neewer-light-config.json")
        bootMarkerURL = home
            .appendingPathComponent(".config/karabiner/neewer-light-boot.json")

        let loadedPresets = Self.loadPresets(from: defaults, key: presetKey)
        presets = loadedPresets

        if let raw = defaults.string(forKey: powerOnModeKey),
           let mode = UmbrellaNeewerPowerOnMode(rawValue: raw) {
            powerOnMode = mode
        } else {
            powerOnMode = .lastValue
        }

        let rawBrightness = defaults.object(forKey: defaultBrightnessKey) as? Int ?? 80
        let rawKelvin = defaults.object(forKey: defaultKelvinKey) as? Int ?? 5600
        defaultBrightness = max(Self.minBrightness, min(Self.maxBrightness, rawBrightness))
        defaultKelvin = Self.clampKelvin(rawKelvin)

        let state = Self.readStateFile()
        brightness = state.brightness
        kelvin = state.kelvin

        let storedFavorites = defaults.stringArray(forKey: menuBarFavoritesKey) ?? []
        let validFavoriteIDs = storedFavorites.filter { id in loadedPresets.contains(where: { $0.id == id }) }
        if validFavoriteIDs.isEmpty {
            menuBarFavoriteIDs = Array(loadedPresets.prefix(Self.maxMenuBarFavorites).map(\.id))
        } else {
            menuBarFavoriteIDs = Array(validFavoriteIDs.prefix(Self.maxMenuBarFavorites))
        }
        defaults.set(menuBarFavoriteIDs, forKey: menuBarFavoritesKey)
    }

    var menuBarFavoritePresets: [UmbrellaNeewerPreset] {
        menuBarFavoriteIDs.compactMap { id in presets.first(where: { $0.id == id }) }
    }

    func start() {
        exportConfig()
        Task { await refreshFromAPI() }
    }

    func stop() {
            coalesceGeneration &+= 1
            queuedCCT = nil
            exportConfig()
        }

    func setPowerOnMode(_ mode: UmbrellaNeewerPowerOnMode) {
        powerOnMode = mode
        save()
    }

    func setBrightness(_ value: Int) {
        brightness = max(Self.minBrightness, min(Self.maxBrightness, value))
        statusMessage = "\(brightness)% · \(kelvin)K"
        scheduleApply(focus: "brightness")
    }

    func setKelvin(_ value: Int) {
        kelvin = Self.clampKelvin(value)
        statusMessage = "\(brightness)% · \(kelvin)K"
        scheduleApply(focus: "temp")
    }

    func setDefaultBrightness(_ value: Int) {
        defaultBrightness = max(Self.minBrightness, min(Self.maxBrightness, value))
        save()
    }

    func setDefaultKelvin(_ value: Int) {
        defaultKelvin = Self.clampKelvin(value)
        save()
    }

    func refreshCurrentValuesFromDisk() {
        let state = Self.readStateFile()
        brightness = state.brightness
        kelvin = state.kelvin
    }

    @discardableResult
    func refreshFromAPI() async -> Bool {
        isSyncingFromLight = true
        defer { isSyncingFromLight = false }

        do {
            let light = try await Self.fetchLight(lightName: lightName, apiBase: apiBase, apiUA: apiUA)
            isReachable = true
            isPoweredOn = light.isOn
            brightness = light.brightness
            kelvin = light.kelvin
            hasSyncedFromLight = true
            if light.isOn {
                statusMessage = "\(light.brightness)% · \(light.kelvin)K"
            } else {
                statusMessage = "Off · \(light.brightness)% · \(light.kelvin)K"
            }
            Self.writeStateFile(
                brightness: light.brightness,
                temperature: max(29, min(70, Int((Double(light.kelvin) / 100.0).rounded())))
            )
            return true
        } catch {
            isReachable = false
            hasSyncedFromLight = false
            return false
        }
    }

    func setPoweredOn(_ on: Bool) {
        Task { @MainActor in
            await applyPower(on)
        }
    }

    func togglePower() {
        setPoweredOn(!isPoweredOn)
    }

    func addPreset(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let preset = UmbrellaNeewerPreset(
            name: trimmed.isEmpty ? "\(brightness)% · \(kelvin)K" : trimmed,
            brightness: brightness,
            kelvin: kelvin
        )
        presets.append(preset)
        save()
    }

    func updatePreset(_ preset: UmbrellaNeewerPreset) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        var updated = preset
        updated.brightness = max(Self.minBrightness, min(Self.maxBrightness, updated.brightness))
        updated.kelvin = Self.clampKelvin(updated.kelvin)
        presets[index] = updated
        save()
    }

    func removePreset(_ presetID: String) {
        presets.removeAll(where: { $0.id == presetID })
        menuBarFavoriteIDs.removeAll { $0 == presetID }
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
        kelvin = preset.kelvin
        statusMessage = "\(brightness)% · \(kelvin)K"
        applyValues(brightness: preset.brightness, kelvin: preset.kelvin, focus: "both", immediate: true)
    }

    func applyDefaultsNow() {
        brightness = defaultBrightness
        kelvin = defaultKelvin
        statusMessage = "\(brightness)% · \(kelvin)K"
        applyValues(brightness: defaultBrightness, kelvin: defaultKelvin, focus: "both", immediate: true)
    }

    private func scheduleApply(focus: String) {
        pendingApplyFocus = focus
        // Write intended state immediately so other tools stay in sync even if BLE lags.
        let bri = brightness
        let temp = max(29, min(70, Int((Double(kelvin) / 100.0).rounded())))
        Self.writeStateFile(brightness: bri, temperature: temp)

        // Generation coalesce instead of Task.cancel — canceling the trailing
        // sleep could drop the final slider value until another control moved.
        coalesceGeneration &+= 1
        let generation = coalesceGeneration
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 20_000_000)
            guard generation == self.coalesceGeneration else { return }
            self.enqueueCCT(
                brightness: self.brightness,
                kelvin: self.kelvin,
                focus: self.pendingApplyFocus
            )
        }
    }

    /// Force-send the current slider values (e.g. when the user releases a drag).
    func flushPendingApply() {
        coalesceGeneration &+= 1
        Self.writeStateFile(
            brightness: brightness,
            temperature: max(29, min(70, Int((Double(kelvin) / 100.0).rounded())))
        )
        enqueueCCT(brightness: brightness, kelvin: kelvin, focus: pendingApplyFocus)
    }

    private func applyValues(brightness: Int, kelvin: Int, focus: String, immediate: Bool) {
        if immediate {
            coalesceGeneration &+= 1
        }
        let bri = max(Self.minBrightness, min(Self.maxBrightness, brightness))
        let kelvinClamped = Self.clampKelvin(kelvin)
        statusMessage = "\(bri)% · \(kelvinClamped)K"
        Self.writeStateFile(
            brightness: bri,
            temperature: max(29, min(70, Int((Double(kelvinClamped) / 100.0).rounded())))
        )
        enqueueCCT(brightness: bri, kelvin: kelvinClamped, focus: focus)
    }

    /// Sends CCT updates without canceling in-flight HTTP (which dropped mid-drag commands).
    /// While a request is running, only the latest values are kept and flushed when it finishes.
    private func enqueueCCT(brightness: Int, kelvin: Int, focus: String) {
        let bri = max(Self.minBrightness, min(Self.maxBrightness, brightness))
        let kelvinClamped = Self.clampKelvin(kelvin)
        queuedCCT = (bri, kelvinClamped, focus)
        pumpCCTQueue()
    }

    private func pumpCCTQueue() {
        guard !isSendingCCT, let next = queuedCCT else { return }
        queuedCCT = nil
        isSendingCCT = true
        isBusy = true

        let bri = next.brightness
        let kelvinClamped = next.kelvin
        let temp = max(29, min(70, Int((Double(kelvinClamped) / 100.0).rounded())))

        Task {
            defer {
                Task { @MainActor in
                    self.isSendingCCT = false
                    self.isBusy = self.queuedCCT != nil
                    self.pumpCCTQueue()
                }
            }

            do {
                try await Self.postCCT(
                    lightName: lightName,
                    brightness: bri,
                    temperature: temp,
                    apiBase: apiBase,
                    apiUA: apiUA
                )
                await MainActor.run {
                    self.isReachable = true
                    self.isPoweredOn = true
                    // Don't overwrite slider values — user may have moved further already.
                    if self.queuedCCT == nil {
                        self.statusMessage = "\(self.brightness)% · \(self.kelvin)K"
                    }
                }
            } catch {
                await MainActor.run {
                    self.isReachable = false
                    self.statusMessage = "Couldn’t reach NeewerLite — is it running?"
                }
            }
        }
    }

    private func applyPower(_ on: Bool) async {
        isBusy = true
        defer { isBusy = false }

        do {
            if on {
                let shouldRestore = Self.isFirstPowerOnThisBoot(markerURL: bootMarkerURL)
                if shouldRestore {
                    let restore = restoreValuesForPowerOn()
                    try await Self.postSwitch(lightName: lightName, state: true, apiBase: apiBase, apiUA: apiUA)
                    let temp = max(29, min(70, Int((Double(restore.kelvin) / 100.0).rounded())))
                    try await Self.postCCT(
                        lightName: lightName,
                        brightness: restore.brightness,
                        temperature: temp,
                        apiBase: apiBase,
                        apiUA: apiUA
                    )
                    Self.writeStateFile(brightness: restore.brightness, temperature: temp)
                    Self.markPowerOnThisBoot(markerURL: bootMarkerURL)
                    brightness = restore.brightness
                    kelvin = restore.kelvin
                    statusMessage = "\(restore.brightness)% · \(restore.kelvin)K"
                } else {
                    try await Self.postSwitch(lightName: lightName, state: true, apiBase: apiBase, apiUA: apiUA)
                    statusMessage = "\(brightness)% · \(kelvin)K"
                }
                isPoweredOn = true
            } else {
                try await Self.postSwitch(lightName: lightName, state: false, apiBase: apiBase, apiUA: apiUA)
                isPoweredOn = false
                statusMessage = "Off · \(brightness)% · \(kelvin)K"
            }
            isReachable = true
            _ = await refreshFromAPI()
            if isPoweredOn {
                statusMessage = "\(brightness)% · \(kelvin)K"
            } else {
                statusMessage = "Off · \(brightness)% · \(kelvin)K"
            }
        } catch {
            isReachable = false
            statusMessage = "Couldn’t reach NeewerLite — is it running?"
        }
    }

    private func restoreValuesForPowerOn() -> (brightness: Int, kelvin: Int) {
        switch powerOnMode {
        case .defaultValue:
            return (defaultBrightness, defaultKelvin)
        case .lastValue:
            let state = Self.readStateFile()
            return (state.brightness, state.kelvin)
        }
    }


    private func save() {
        defaults.set(powerOnMode.rawValue, forKey: powerOnModeKey)
        defaults.set(defaultBrightness, forKey: defaultBrightnessKey)
        defaults.set(defaultKelvin, forKey: defaultKelvinKey)
        defaults.set(menuBarFavoriteIDs, forKey: menuBarFavoritesKey)
        if let data = try? JSONEncoder().encode(presets) {
            defaults.set(data, forKey: presetKey)
        }
        exportConfig()
    }

    private func exportConfig() {
        let payload: [String: Any] = [
            "powerOnMode": powerOnMode.rawValue,
            "defaultBrightness": defaultBrightness,
            "defaultTemperature": max(29, min(70, Int((Double(defaultKelvin) / 100.0).rounded()))),
            "defaultKelvin": defaultKelvin,
            "presets": presets.map { preset in
                [
                    "id": preset.id,
                    "name": preset.name,
                    "brightness": preset.brightness,
                    "temperature": preset.temperature,
                    "kelvin": preset.kelvin,
                ] as [String: Any]
            },
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        let dir = configURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: configURL, options: .atomic)
    }

    private static func clampKelvin(_ value: Int) -> Int {
        let stepped = Int((Double(value) / Double(kelvinStep)).rounded()) * kelvinStep
        return max(minKelvin, min(maxKelvin, stepped))
    }

    private static func stateFileURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/karabiner/neewer-light-state.json")
    }

    private static func readStateFile() -> (brightness: Int, kelvin: Int) {
        let url = stateFileURL()
        guard
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return (80, 5600)
        }
        let brightness = max(minBrightness, min(maxBrightness, (json["brightness"] as? Int) ?? 80))
        let temp: Int
        if let t = json["temp"] as? Int {
            temp = max(29, min(70, t))
        } else if let cct = json["cct"] as? Int {
            temp = max(29, min(70, Int((Double(cct) / 100.0).rounded())))
        } else {
            temp = 56
        }
        return (brightness, temp * 100)
    }

    private static func writeStateFile(brightness: Int, temperature: Int) {
        let url = stateFileURL()
        let payload: [String: Int] = [
            "brightness": max(minBrightness, min(maxBrightness, brightness)),
            "temp": max(29, min(70, temperature)),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private static func postCCT(
        lightName: String,
        brightness: Int,
        temperature: Int,
        apiBase: String,
        apiUA: String
    ) async throws {
        guard let url = URL(string: "\(apiBase)/cct") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiUA, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 1.5
        let body: [String: Any] = [
            "lights": [lightName],
            "brightness": brightness,
            "temperature": temperature,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private static func postSwitch(
        lightName: String,
        state: Bool,
        apiBase: String,
        apiUA: String
    ) async throws {
        guard let url = URL(string: "\(apiBase)/switch") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiUA, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 3
        let body: [String: Any] = [
            "lights": [lightName],
            "state": state,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private static func fetchLight(
        lightName: String,
        apiBase: String,
        apiUA: String
    ) async throws -> (isOn: Bool, brightness: Int, kelvin: Int) {
        guard let url = URL(string: "\(apiBase)/listLights") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiUA, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 3
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let lights = json["lights"] as? [[String: Any]],
            let light = lights.first(where: { ($0["name"] as? String) == lightName })
        else {
            throw URLError(.cannotParseResponse)
        }

        let isOn = boolValue(light["state"]) ?? false
        let brightness = max(minBrightness, min(maxBrightness, intValue(light["brightness"]) ?? 80))
        let temperature: Int
        if let temp = intValue(light["temperature"]) {
            temperature = max(29, min(70, temp))
        } else if let cct = intValue(light["cct"]) {
            temperature = max(29, min(70, Int((Double(cct) / 100.0).rounded())))
        } else {
            temperature = 56
        }
        return (isOn, brightness, temperature * 100)
    }

    /// NeewerLite returns many numeric fields as strings (e.g. `"2"`, `"56"`).
    private static func intValue(_ raw: Any?) -> Int? {
        switch raw {
        case let value as Int:
            return value
        case let value as Double:
            return Int(value.rounded())
        case let value as Float:
            return Int(value.rounded())
        case let value as NSNumber:
            return value.intValue
        case let value as String:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if let int = Int(trimmed) { return int }
            if let double = Double(trimmed) { return Int(double.rounded()) }
            return nil
        default:
            return nil
        }
    }

    private static func boolValue(_ raw: Any?) -> Bool? {
        switch raw {
        case let value as Bool:
            return value
        case let value as Int:
            return value != 0
        case let value as NSNumber:
            return value.boolValue
        case let value as String:
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "on", "yes":
                return true
            case "0", "false", "off", "no":
                return false
            default:
                return nil
            }
        default:
            return nil
        }
    }

    private static func currentBootID() -> String {
        var size = 0
        sysctlbyname("kern.boottime", nil, &size, nil, 0)
        var boottime = timeval()
        var boottimeSize = MemoryLayout<timeval>.size
        if sysctlbyname("kern.boottime", &boottime, &boottimeSize, nil, 0) == 0 {
            return String(boottime.tv_sec)
        }
        return "0"
    }

    private static func isFirstPowerOnThisBoot(markerURL: URL) -> Bool {
        let bootID = currentBootID()
        guard
            let data = try? Data(contentsOf: markerURL),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let stored = json["bootId"] as? String
        else {
            return true
        }
        return stored != bootID
    }

    private static func markPowerOnThisBoot(markerURL: URL) {
        let payload = ["bootId": currentBootID()]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        let dir = markerURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: markerURL, options: .atomic)
    }

    private static func loadPresets(from defaults: UserDefaults, key: String) -> [UmbrellaNeewerPreset] {
        if let data = defaults.data(forKey: key),
           let loaded = try? JSONDecoder().decode([UmbrellaNeewerPreset].self, from: data) {
            return loaded
        }
        return [
            UmbrellaNeewerPreset(name: "Desk", brightness: 45, kelvin: 4500),
            UmbrellaNeewerPreset(name: "Video", brightness: 80, kelvin: 5600),
            UmbrellaNeewerPreset(name: "Warm", brightness: 30, kelvin: 3200),
        ]
    }
}

