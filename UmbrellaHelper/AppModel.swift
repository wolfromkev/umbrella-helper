import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

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
    private let filmModeHotKey = GlobalHotKey(registrationID: 14)
    private var sunPresetHotKeys: [String: GlobalHotKey] = [:]
    private var nextSunPresetHotKeyID: UInt32 = 200
    private var neewerPresetHotKeys: [String: GlobalHotKey] = [:]
    private var nextNeewerPresetHotKeyID: UInt32 = 300
    let brightnessFeature = UmbrellaBrightnessFeature()
    let simpleSnipFeature = UmbrellaSimpleSnipFeature()
    let neewerLightFeature = UmbrellaNeewerLightFeature()

    var notionTaskHasKeyboardFocus: Bool {
        notionTaskPanelController.hasKeyboardFocus
    }

    func start() {
        ActiveScreenTracker.start()
        settingsPanelController.configure(model: self)
        notionTaskPanelController.configure(model: self)
        brightnessFeature.start()
        simpleSnipFeature.start()
        neewerLightFeature.start()
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
        filmModeHotKey.unregister()
        sunPresetHotKeys.values.forEach { $0.unregister() }
        sunPresetHotKeys.removeAll()
        neewerPresetHotKeys.values.forEach { $0.unregister() }
        neewerPresetHotKeys.removeAll()
        settingsPanelController.closePanel()
        notionTaskPanelController.closePanel()
        brightnessFeature.stop()
        simpleSnipFeature.stop()
        neewerLightFeature.stop()
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
        if let filmModeBinding = settings.filmModeHotKey {
            filmModeHotKey.register(hotKeyID: filmModeBinding) { [weak self] in
                Task { @MainActor in self?.brightnessFeature.toggleFilmMode() }
            }
        } else {
            filmModeHotKey.unregister()
        }
        reloadSunPresetHotKeys()
        reloadNeewerPresetHotKeys()
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

    func reloadNeewerPresetHotKeys() {
        neewerPresetHotKeys.values.forEach { $0.unregister() }
        neewerPresetHotKeys.removeAll()
        nextNeewerPresetHotKeyID = 300

        for preset in neewerLightFeature.presets {
            guard let binding = settings.neewerPresetHotKeys[preset.id] else { continue }
            let id = nextNeewerPresetHotKeyID
            nextNeewerPresetHotKeyID += 1
            let hotKey = GlobalHotKey(registrationID: id)
            hotKey.register(hotKeyID: binding) { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.neewerLightFeature.applyPreset(id: preset.id)
                }
            }
            neewerPresetHotKeys[preset.id] = hotKey
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
        // Keep the draft visible while a create is in flight.
        guard !isNotionSubmitting else { return }
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

        isNotionSubmitting = true
        notionErrorMessage = nil
        notionStatusMessage = nil
        refreshNotionTaskLayout()

        Task {
            do {
                let url = try await NotionAPIClient.shared.createTask(input, schema: schema)
                await MainActor.run {
                    isNotionSubmitting = false
                    lastCreatedNotionTaskURL = url
                    // Success — now safe to dismiss and clear the draft.
                    isNotionTaskVisible = false
                    notionTaskPanelController.closePanel()
                    resetNotionTaskState(clearTitle: true)
                }
            } catch {
                await MainActor.run {
                    isNotionSubmitting = false
                    notionErrorMessage = error.localizedDescription
                    refreshNotionTaskLayout()
                }
            }
        }
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
