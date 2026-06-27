import AppKit
import SwiftUI

private enum UmbrellaSettingsTab: Hashable {
    case keybindings
    case brightness
    case simpleSnip
    case notionPopup
}

private enum KeybindingTarget: Hashable {
    case notionTask
    case newChat
    case snipArea
    case snipWindow
    case snipFullScreen
    case snipRecord
    case snipText
    case brightnessDown
    case brightnessUp
    case warmthUp
    case warmthDown
    case sunPreset(String)
}

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedTab: UmbrellaSettingsTab = .keybindings
    @State private var launchAtLogin = AppSettings.shared.launchAtLogin
    @State private var responseDisplayMode = AppSettings.shared.responseDisplayMode

    @State private var notionTaskHotKey = AppSettings.shared.notionTaskHotKey
    @State private var newChatHotKey = AppSettings.shared.newChatHotKey
    @State private var snipAreaHotKey = AppSettings.shared.snipAreaHotKey
    @State private var snipWindowHotKey = AppSettings.shared.snipWindowHotKey
    @State private var snipFullScreenHotKey = AppSettings.shared.snipFullScreenHotKey
    @State private var snipRecordHotKey = AppSettings.shared.snipRecordHotKey
    @State private var snipTextHotKey = AppSettings.shared.snipTextHotKey
    @State private var brightnessDownHotKey = AppSettings.shared.brightnessDownHotKey
    @State private var brightnessUpHotKey = AppSettings.shared.brightnessUpHotKey
    @State private var warmthUpHotKey = AppSettings.shared.warmthUpHotKey
    @State private var warmthDownHotKey = AppSettings.shared.warmthDownHotKey
    @State private var sunPresetHotKeys = AppSettings.shared.sunScreenPresetHotKeys
    @State private var recordingTarget: KeybindingTarget?
    @State private var shortcutConflict: String?

    @State private var savedNotionToken = KeychainStorage.notionToken ?? ""
    @State private var savedNotionDatabaseID = AppSettings.shared.notionDatabaseID
    @State private var isEditingNotionCredentials = false
    @State private var notionTokenDraft = ""
    @State private var notionDatabaseIDDraft = ""

    @State private var openWebUIBaseURL = AppSettings.shared.openWebUIBaseURL
    @State private var openWebUIModel = AppSettings.shared.openWebUIModel
    @State private var openWebUISyncChats = AppSettings.shared.openWebUISyncChats
    @State private var savedOpenWebUIAPIKey = KeychainStorage.openWebUIAPIKey ?? ""
    @State private var openWebUIAPIKeyDraft = ""
    @State private var isEditingOpenWebUICredentials = false
    @State private var availableOpenWebUIModels: [String] = []
    @State private var isLoadingOpenWebUIModels = false
    @State private var openWebUIStatusMessage: String?

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

            notionPopupTab
                .tabItem { Text("Notion Pop-up") }
                .tag(UmbrellaSettingsTab.notionPopup)
        }
        .padding(16)
        .onAppear {
            launchAtLogin = LaunchAtLoginManager.isEnabled
            responseDisplayMode = AppSettings.shared.responseDisplayMode
            refreshPresetBindings()
            reloadNotionCredentials()
            openWebUIBaseURL = AppSettings.shared.openWebUIBaseURL
            openWebUIModel = AppSettings.shared.openWebUIModel
            openWebUISyncChats = AppSettings.shared.openWebUISyncChats
            savedOpenWebUIAPIKey = KeychainStorage.openWebUIAPIKey ?? ""
            detectShortcutConflict()
        }
    }

    private var keybindingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionCard("SimpleSnip") {
                    editableBindingRow("Snip area", target: .snipArea)
                    editableBindingRow("Snip window", target: .snipWindow)
                    editableBindingRow("Snip full screen", target: .snipFullScreen)
                    editableBindingRow("Record area / Stop recording", target: .snipRecord)
                    editableBindingRow("Copy text from area", target: .snipText)
                }

                sectionCard("Notion Pop-up") {
                    editableBindingRow("New Notion task", target: .notionTask)
                    editableBindingRow("New chat", target: .newChat)
                }

                sectionCard("Neewer light control") {
                    readOnlyBindingRow("Toggle light", value: "Hyper + F1")
                    readOnlyBindingRow("Brightness down", value: "Hyper + F9")
                    readOnlyBindingRow("Brightness up", value: "Hyper + F10")
                    readOnlyBindingRow("Warmth down", value: "Hyper + F11")
                    readOnlyBindingRow("Warmth up", value: "Hyper + F12")
                    Text("Managed in Karabiner. Umbrella Helper shows these bindings for reference only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                sectionCard("SunScreen") {
                    editableBindingRow("Brightness down", target: .brightnessDown)
                    editableBindingRow("Brightness up", target: .brightnessUp)
                    editableBindingRow("Warmer", target: .warmthUp)
                    editableBindingRow("Cooler", target: .warmthDown)

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

    private var notionPopupTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionCard("Open WebUI") {
                    row(label: "Server URL") {
                        TextField("http://localhost:8080", text: $openWebUIBaseURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 320)
                            .onChange(of: openWebUIBaseURL) { AppSettings.shared.openWebUIBaseURL = $0 }
                    }

                    row(label: "API key") {
                        if isEditingOpenWebUICredentials {
                            SecureField("sk-...", text: $openWebUIAPIKeyDraft)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 220)
                        } else {
                            Text(maskedOpenWebUIAPIKey(savedOpenWebUIAPIKey))
                                .foregroundStyle(savedOpenWebUIAPIKey.isEmpty ? .orange : .secondary)
                                .textSelection(.enabled)
                                .frame(width: 220, alignment: .leading)
                        }
                    }

                    HStack(spacing: 8) {
                        if isEditingOpenWebUICredentials {
                            Button("Save") { saveOpenWebUICredentials() }
                                .disabled(openWebUIAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Button("Cancel") { cancelEditingOpenWebUICredentials() }
                        } else {
                            Button("Edit API key…") { beginEditingOpenWebUICredentials() }
                        }
                    }

                    row(label: "Model") {
                        if availableOpenWebUIModels.isEmpty {
                            TextField("llama3.2", text: $openWebUIModel)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 220)
                                .onChange(of: openWebUIModel) { AppSettings.shared.openWebUIModel = $0 }
                        } else {
                            Picker("", selection: $openWebUIModel) {
                                ForEach(availableOpenWebUIModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 220)
                            .onChange(of: openWebUIModel) { AppSettings.shared.openWebUIModel = $0 }
                        }
                    }

                    HStack(spacing: 8) {
                        Button(isLoadingOpenWebUIModels ? "Loading…" : "Refresh models") {
                            refreshOpenWebUIModels()
                        }
                        .disabled(isLoadingOpenWebUIModels)

                        Toggle("Sync chats to Open WebUI", isOn: $openWebUISyncChats)
                            .onChange(of: openWebUISyncChats) {
                                AppSettings.shared.openWebUISyncChats = $0
                                appModel.refreshWorkspaceSessionCache()
                                appModel.refreshOpenWebUIProjects()
                            }
                    }

                    if let openWebUIStatusMessage {
                        Text(openWebUIStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                sectionCard("Notion") {
                    row(label: "Integration token") {
                        if isEditingNotionCredentials {
                            SecureField("Secret", text: $notionTokenDraft)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 320)
                        } else {
                            Text(maskedNotionToken(savedNotionToken))
                                .foregroundStyle(savedNotionToken.isEmpty ? .orange : .secondary)
                                .textSelection(.enabled)
                                .frame(width: 320, alignment: .leading)
                        }
                    }

                    row(label: "Database ID") {
                        if isEditingNotionCredentials {
                            TextField("Database ID", text: $notionDatabaseIDDraft)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 320)
                        } else {
                            Text(savedNotionDatabaseID)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                                .frame(width: 320, alignment: .leading)
                        }
                    }

                    HStack(spacing: 8) {
                        if isEditingNotionCredentials {
                            Button("Save") { saveNotionCredentials() }
                                .disabled(!notionCredentialsCanSave)
                            Button("Cancel") { cancelEditingNotionCredentials() }
                        } else {
                            Button("Edit credentials…") { beginEditingNotionCredentials() }
                        }
                    }
                }

                sectionCard("Behavior") {
                    row(label: "Show replies in") {
                        Picker("", selection: $responseDisplayMode) {
                            ForEach(ResponseDisplayMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                        .onChange(of: responseDisplayMode) { AppSettings.shared.responseDisplayMode = $0 }
                    }

                    row(label: "Launch at login") {
                        Toggle("", isOn: $launchAtLogin)
                            .labelsHidden()
                            .onChange(of: launchAtLogin) {
                                AppSettings.shared.launchAtLogin = $0
                                LaunchAtLoginManager.setEnabled($0)
                            }
                    }
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

    @ViewBuilder
    private func readOnlyBindingRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func binding(for target: KeybindingTarget) -> Binding<HotKeyBinding?> {
        Binding<HotKeyBinding?>(
            get: {
                switch target {
                case .notionTask: return notionTaskHotKey
                case .newChat: return newChatHotKey
                case .snipArea: return snipAreaHotKey
                case .snipWindow: return snipWindowHotKey
                case .snipFullScreen: return snipFullScreenHotKey
                case .snipRecord: return snipRecordHotKey
                case .snipText: return snipTextHotKey
                case .brightnessDown: return brightnessDownHotKey
                case .brightnessUp: return brightnessUpHotKey
                case .warmthUp: return warmthUpHotKey
                case .warmthDown: return warmthDownHotKey
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
        case .notionTask:
            notionTaskHotKey = binding
            AppSettings.shared.notionTaskHotKey = binding
        case .newChat:
            newChatHotKey = binding
            AppSettings.shared.newChatHotKey = binding
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
        case .notionTask:
            notionTaskHotKey = .notionTaskDefault
            AppSettings.shared.notionTaskHotKey = .notionTaskDefault
        case .newChat:
            newChatHotKey = .newChatDefault
            AppSettings.shared.newChatHotKey = .newChatDefault
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
        case .sunPreset(let id):
            sunPresetHotKeys.removeValue(forKey: id)
            AppSettings.shared.sunScreenPresetHotKeys = sunPresetHotKeys
        }
        appModel.reloadHotKeys()
        detectShortcutConflict()
    }

    private func canClear(_ target: KeybindingTarget) -> Bool {
        switch target {
        case .sunPreset(let id):
            return sunPresetHotKeys[id] != nil
        default:
            return true
        }
    }

    private func detectShortcutConflict() {
        let all: [(String, HotKeyBinding)] = [
            ("Notion task", notionTaskHotKey),
            ("New chat", newChatHotKey),
            ("Snip area", snipAreaHotKey),
            ("Snip window", snipWindowHotKey),
            ("Snip full screen", snipFullScreenHotKey),
            ("Record area", snipRecordHotKey),
            ("Copy text", snipTextHotKey),
            ("Brightness down", brightnessDownHotKey),
            ("Brightness up", brightnessUpHotKey),
            ("Warmer", warmthUpHotKey),
            ("Cooler", warmthDownHotKey),
        ] + appModel.brightnessFeature.presets.compactMap { preset in
            guard let binding = sunPresetHotKeys[preset.id] else { return nil }
            return ("Preset: \(preset.name)", binding)
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
        var current = AppSettings.shared.sunScreenPresetHotKeys
        let validIDs = Set(appModel.brightnessFeature.presets.map(\.id))
        current = current.filter { validIDs.contains($0.key) }
        AppSettings.shared.sunScreenPresetHotKeys = current
        sunPresetHotKeys = current
        detectShortcutConflict()
    }

    private func maskedNotionToken(_ token: String) -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Not set" }
        guard trimmed.count > 8 else { return String(repeating: "•", count: trimmed.count) }
        let suffix = trimmed.suffix(4)
        return "\(String(repeating: "•", count: max(4, trimmed.count - 4)))\(suffix)"
    }

    private var notionCredentialsCanSave: Bool {
        !notionTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !notionDatabaseIDDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func reloadNotionCredentials() {
        savedNotionToken = KeychainStorage.notionToken ?? ""
        savedNotionDatabaseID = AppSettings.shared.notionDatabaseID
    }

    private func beginEditingNotionCredentials() {
        notionTokenDraft = savedNotionToken
        notionDatabaseIDDraft = savedNotionDatabaseID
        isEditingNotionCredentials = true
    }

    private func cancelEditingNotionCredentials() {
        notionTokenDraft = savedNotionToken
        notionDatabaseIDDraft = savedNotionDatabaseID
        isEditingNotionCredentials = false
    }

    private func saveNotionCredentials() {
        let token = notionTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let databaseID = notionDatabaseIDDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !databaseID.isEmpty else { return }
        KeychainStorage.notionToken = token
        AppSettings.shared.notionDatabaseID = databaseID
        isEditingNotionCredentials = false
        reloadNotionCredentials()
    }

    private func maskedOpenWebUIAPIKey(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Not set" }
        guard trimmed.count > 8 else { return String(repeating: "•", count: trimmed.count) }
        let suffix = trimmed.suffix(4)
        return "\(String(repeating: "•", count: max(4, trimmed.count - 4)))\(suffix)"
    }

    private func beginEditingOpenWebUICredentials() {
        openWebUIAPIKeyDraft = savedOpenWebUIAPIKey
        isEditingOpenWebUICredentials = true
    }

    private func cancelEditingOpenWebUICredentials() {
        openWebUIAPIKeyDraft = savedOpenWebUIAPIKey
        isEditingOpenWebUICredentials = false
    }

    private func saveOpenWebUICredentials() {
        let key = openWebUIAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        KeychainStorage.openWebUIAPIKey = key
        savedOpenWebUIAPIKey = key
        isEditingOpenWebUICredentials = false
    }

    private func refreshOpenWebUIModels() {
        openWebUIStatusMessage = nil
        let baseURL = openWebUIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = (isEditingOpenWebUICredentials ? openWebUIAPIKeyDraft : savedOpenWebUIAPIKey)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !baseURL.isEmpty else {
            openWebUIStatusMessage = "Enter a server URL first."
            return
        }
        guard !apiKey.isEmpty else {
            openWebUIStatusMessage = "Set an Open WebUI API key first."
            return
        }

        isLoadingOpenWebUIModels = true
        Task {
            do {
                let models = try await OpenWebUIRunner.fetchModels(baseURL: baseURL, apiKey: apiKey)
                await MainActor.run {
                    availableOpenWebUIModels = models
                    if openWebUIModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       let first = models.first {
                        openWebUIModel = first
                        AppSettings.shared.openWebUIModel = first
                    }
                    openWebUIStatusMessage = models.isEmpty
                        ? "No models returned. Check your Open WebUI permissions."
                        : "Loaded \(models.count) model\(models.count == 1 ? "" : "s")."
                    isLoadingOpenWebUIModels = false
                }
            } catch {
                await MainActor.run {
                    availableOpenWebUIModels = []
                    openWebUIStatusMessage = error.localizedDescription
                    isLoadingOpenWebUIModels = false
                }
            }
        }
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

    @ViewBuilder
    private func row<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center) {
            Text(label)
                .frame(width: 130, alignment: .leading)
            content()
            Spacer()
        }
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
                    Toggle("Blue Light Removal", isOn: Binding(
                        get: { feature.isDarkroom },
                        set: { feature.setDarkroom($0) }
                    ))
                    Toggle("Keep Awake", isOn: Binding(
                        get: { feature.isKeepAwakeEnabled },
                        set: { feature.setKeepAwake($0) }
                    ))
                    Toggle("Use location schedule", isOn: Binding(
                        get: { feature.useLocationSchedule },
                        set: { feature.setUseLocationSchedule($0) }
                    ))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Brightness: \(Int(feature.brightness * 100))%")
                        Slider(
                            value: Binding(
                                get: { Double(feature.brightness) },
                                set: { feature.setBrightness(Float($0)) }
                            ),
                            in: 0.05...1.0
                        )
                        .disabled(feature.isAutoMode)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Color temperature: \(feature.isDarkroom ? "Darkroom" : "\(feature.colorTemp)K")")
                        Slider(
                            value: Binding(
                                get: { Double(feature.colorTemp) },
                                set: { feature.setColorTemp(Int($0)) }
                            ),
                            in: 1200...6500,
                            step: Double(UmbrellaBrightnessFeature.colorTempStep)
                        )
                        .disabled(feature.isAutoMode || feature.isDarkroom)
                    }
                }

                section("Schedule") {
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

                    HStack {
                        Text("Transition minutes")
                        Stepper(
                            value: Binding(
                                get: { feature.transitionMinutes },
                                set: { feature.updateTransitionMinutes($0) }
                            ),
                            in: 15...240,
                            step: 5
                        ) {
                            Text("\(feature.transitionMinutes)")
                        }
                    }

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

                    if feature.useLocationSchedule {
                        Text(feature.locationName ?? "Using system location")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                section("Presets") {
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
                                .frame(width: 220)

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
                                    in: 0.05...1.0
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
        Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date)
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

                    Button("Refresh permission status") {
                        feature.refreshPermissionState()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Text("If prompts keep appearing, grant access in System Settings, then quit and relaunch Umbrella Helper once.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Snips require screen capture only. Microphone applies to recordings when enabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                section("Capture") {
                    HStack(spacing: 8) {
                        Button("Snip Area") { feature.takeAreaSnip() }
                        Button("Snip Window") { feature.takeWindowSnip() }
                        Button("Snip Full Screen") { feature.takeFullScreenSnip() }
                        Button("Copy Text") { feature.copyTextFromAreaSnip() }
                    }
                    HStack(spacing: 8) {
                        Button(feature.isRecording ? "Stop Recording" : "Record Area") {
                            feature.toggleRecording()
                        }
                        if feature.isRecording {
                            Text("Recording in progress…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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

                section("Recent") {
                    if let last = feature.lastSavedPath {
                        Text(last)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Reveal Last Capture") {
                            feature.revealLastSavedItem()
                        }
                    } else {
                        Text("No captures yet.")
                            .foregroundStyle(.secondary)
                    }
                }

                section("Debug") {
                    HStack(spacing: 8) {
                        Button("Copy log") { feature.copyDebugLog() }
                            .disabled(feature.debugLog.isEmpty)
                        Button("Clear") { feature.clearDebugLog() }
                            .disabled(feature.debugLog.isEmpty)
                        Spacer()
                    }

                    if feature.debugLog.isEmpty {
                        Text("Run a capture/record to see live diagnostics here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(feature.debugLog.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
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
