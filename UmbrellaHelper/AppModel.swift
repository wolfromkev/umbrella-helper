import AppKit
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published var isSettingsVisible = false

    let settings = AppSettings.shared
    private let settingsPanelController = SettingsPanelController()
    private let snipAreaHotKey = GlobalHotKey(registrationID: 5)
    private let snipWindowHotKey = GlobalHotKey(registrationID: 6)
    private let snipFullScreenHotKey = GlobalHotKey(registrationID: 7)
    private let snipRecordHotKey = GlobalHotKey(registrationID: 8)
    private let snipTextHotKey = GlobalHotKey(registrationID: 13)
    private let brightnessDownHotKey = GlobalHotKey(registrationID: 9)
    private let brightnessUpHotKey = GlobalHotKey(registrationID: 10)
    private let warmthUpHotKey = GlobalHotKey(registrationID: 11)
    private let warmthDownHotKey = GlobalHotKey(registrationID: 12)
    private let filmModeHotKey = GlobalHotKey(registrationID: 14)
    private var sunPresetHotKeys: [String: GlobalHotKey] = [:]
    private var nextSunPresetHotKeyID: UInt32 = 200
    let brightnessFeature = UmbrellaBrightnessFeature()
    let simpleSnipFeature = UmbrellaSimpleSnipFeature()

    func start() {
        ActiveScreenTracker.start()
        settingsPanelController.configure(model: self)
        brightnessFeature.start()
        simpleSnipFeature.onDisplayCaptureSettled = { [weak self] in
            self?.brightnessFeature.reapplyGammaAfterDisplayCapture()
        }
        simpleSnipFeature.start()
        reloadHotKeys()

        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            settings.launchAtLogin = true
        }

        if settings.launchAtLogin {
            LaunchAtLoginManager.setEnabled(true)
        }
    }


    func stop() {
        ActiveScreenTracker.stop()
        snipAreaHotKey.unregister()
        snipWindowHotKey.unregister()
        snipFullScreenHotKey.unregister()
        snipRecordHotKey.unregister()
        snipTextHotKey.unregister()
        brightnessDownHotKey.unregister()
        brightnessUpHotKey.unregister()
        warmthUpHotKey.unregister()
        warmthDownHotKey.unregister()
        filmModeHotKey.unregister()
        sunPresetHotKeys.values.forEach { $0.unregister() }
        sunPresetHotKeys.removeAll()
        settingsPanelController.closePanel()
        simpleSnipFeature.onDisplayCaptureSettled = nil
        brightnessFeature.stop()
        simpleSnipFeature.stop()
    }

    func reloadHotKeys() {
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
        if let filmModeBinding = settings.filmModeHotKey {
            filmModeHotKey.register(hotKeyID: filmModeBinding) { [weak self] in
                Task { @MainActor in self?.brightnessFeature.toggleFilmMode() }
            }
        } else {
            filmModeHotKey.unregister()
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

}
