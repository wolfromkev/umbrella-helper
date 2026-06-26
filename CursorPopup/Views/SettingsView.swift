import AppKit
import SwiftUI

private enum SettingsColors {
    static let window = Color(nsColor: NSColor.windowBackgroundColor)
    static let card = Color(nsColor: NSColor.controlBackgroundColor)
    static let cardBorder = Color.primary.opacity(0.08)
    static let rowDivider = Color.primary.opacity(0.08)
}

private enum ShortcutTarget {
    case notionTask
    case newChat
}

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @AppStorage(AppSettings.showMenuBarIconKey) private var showMenuBarIcon = true
    @AppStorage(AppSettings.playResponseSoundKey) private var playResponseSound = true
    @AppStorage(AppSettings.responseCompletionSoundKey) private var responseCompletionSound = CompletionSound.defaultSound.rawValue
    @State private var launchAtLogin = AppSettings.shared.launchAtLogin
    @State private var notionTaskHotKey = AppSettings.shared.notionTaskHotKey
    @State private var newChatHotKey = AppSettings.shared.newChatHotKey
    @State private var savedNotionToken = KeychainStorage.notionToken ?? ""
    @State private var savedNotionDatabaseID = AppSettings.shared.notionDatabaseID
    @State private var isEditingNotionCredentials = false
    @State private var notionTokenDraft = ""
    @State private var notionDatabaseIDDraft = ""
    @State private var responseDisplayMode = AppSettings.shared.responseDisplayMode
    @State private var openWebUIBaseURL = AppSettings.shared.openWebUIBaseURL
    @State private var openWebUIModel = AppSettings.shared.openWebUIModel
    @State private var savedOpenWebUIAPIKey = KeychainStorage.openWebUIAPIKey ?? ""
    @State private var isEditingOpenWebUICredentials = false
    @State private var openWebUIAPIKeyDraft = ""
    @State private var availableOpenWebUIModels: [String] = []
    @State private var isLoadingOpenWebUIModels = false
    @State private var openWebUIStatusMessage: String?
    @State private var openWebUISyncChats = AppSettings.shared.openWebUISyncChats
    @State private var recordingTarget: ShortcutTarget?
    @State private var shortcutConflict: String?
    @State private var accessibilityGranted = SystemPermissions.isAccessibilityGranted
    @State private var loginItemRegistered = LaunchAtLoginManager.isEnabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                settingsSection("Open WebUI") {
                    openWebUISettings
                }

                settingsSection("Response") {
                    settingsRow("Show replies in") {
                        Picker("", selection: $responseDisplayMode) {
                            ForEach(ResponseDisplayMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 240)
                        .onChange(of: responseDisplayMode) { newValue in
                            AppSettings.shared.responseDisplayMode = newValue
                        }
                    }

                    footerText("Floating chat opens a separate window you can drag and keep open while you work. Inline mode shows replies above the input bar.")
                }

                settingsSection("Sounds") {
                    settingsRow("Play on response") {
                        Toggle("", isOn: $playResponseSound)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: playResponseSound) { newValue in
                                AppSettings.shared.playResponseSound = newValue
                            }
                    }

                    rowDivider

                    settingsRow("Completion sound") {
                        HStack(spacing: 8) {
                            Picker("", selection: $responseCompletionSound) {
                                ForEach(CompletionSound.allCases) { sound in
                                    Text(sound.rawValue).tag(sound.rawValue)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 180)
                            .disabled(!playResponseSound)
                            .onChange(of: responseCompletionSound) { newValue in
                                AppSettings.shared.responseCompletionSound = newValue
                                ResponseSoundPlayer.playPreview(CompletionSound.fromStoredValue(newValue))
                            }

                            Button("Preview") {
                                ResponseSoundPlayer.playPreview(
                                    CompletionSound.fromStoredValue(responseCompletionSound)
                                )
                            }
                            .disabled(!playResponseSound)
                        }
                    }

                    footerText("Plays when a chat response finishes. macOS system sounds live in /System/Library/Sounds — pick one and use Preview to hear it.")
                }

                settingsSection("Notion") {
                    if isEditingNotionCredentials {
                        settingsRow("Integration token") {
                            SecureField("Secret", text: $notionTokenDraft)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 280)
                        }

                        rowDivider

                        settingsRow("Tasks database ID") {
                            TextField("Database ID", text: $notionDatabaseIDDraft)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 280)
                        }

                        HStack(spacing: 8) {
                            Button("Save") {
                                saveNotionCredentials()
                            }
                            .keyboardShortcut(.return, modifiers: .command)
                            .disabled(!notionCredentialsCanSave)

                            Button("Cancel") {
                                cancelEditingNotionCredentials()
                            }
                            .keyboardShortcut(.cancelAction)
                        }
                        .padding(.top, 2)
                    } else {
                        settingsRow("Integration token") {
                            Text(maskedNotionToken(savedNotionToken))
                                .foregroundStyle(savedNotionToken.isEmpty ? Color.orange : .secondary)
                                .textSelection(.enabled)
                        }

                        rowDivider

                        settingsRow("Tasks database ID") {
                            Text(savedNotionDatabaseID)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                                .frame(maxWidth: 280, alignment: .trailing)
                        }

                        Button("Edit credentials…") {
                            beginEditingNotionCredentials()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    }

                    footerText("Creates tasks in your Notion tasks database. Category, priority, and due date options are loaded from Notion when you open the task popup.")
                }

                settingsSection("Shortcuts") {
                    settingsRow("Notion task") {
                        HotKeyRecorderView(
                            binding: $notionTaskHotKey.asOptional,
                            isRecording: recordingTarget == .notionTask,
                            onBegin: { beginRecording(.notionTask) },
                            onCommit: { commitHotKey($0, target: .notionTask) },
                            onCancel: { cancelRecording() }
                        )
                    }

                    rowDivider

                    settingsRow("New chat") {
                        HotKeyRecorderView(
                            binding: $newChatHotKey.asOptional,
                            isRecording: recordingTarget == .newChat,
                            onBegin: { beginRecording(.newChat) },
                            onCommit: { commitHotKey($0, target: .newChat) },
                            onCancel: { cancelRecording() }
                        )
                    }

                    if let shortcutConflict {
                        Text(shortcutConflict)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    footerText(shortcutsFooter)
                }

                settingsSection("Menu Bar") {
                    Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
                        .toggleStyle(.switch)
                        .onChange(of: showMenuBarIcon) { visible in
                            NotificationCenter.default.post(
                                name: .menuBarIconVisibilityChanged,
                                object: nil,
                                userInfo: ["visible": visible]
                            )
                        }

                    footerText(menuBarShortcutFooter)
                }

                settingsSection("Startup") {
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .onChange(of: launchAtLogin) { enabled in
                            LaunchAtLoginManager.setEnabled(enabled)
                        }
                }

                settingsSection("Permissions") {
                    VStack(alignment: .leading, spacing: 8) {
                        permissionTaskRow(
                            title: "Accessibility access",
                            isComplete: accessibilityGranted,
                            isAutomatic: true
                        ) {
                            SystemPermissions.openAccessibilitySettings()
                        }

                        if !accessibilityGranted {
                            Text("Turn on Cursor Popup in System Settings → Privacy & Security → Accessibility, then quit and reopen the app.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        permissionTaskRow(
                            title: "Launch at login",
                            isComplete: loginItemRegistered,
                            isAutomatic: true
                        ) {
                            SystemPermissions.openLoginItemsSettings()
                        }
                    }

                    footerText("Accessibility lets popups follow your cursor across displays and dismiss when you click outside.")
                }

                settingsSection("About") {
                    footerText(aboutFooter)
                }

                HStack(spacing: 10) {
                    Spacer()
                    Button("Restart") {
                        AppRelauncher.restart()
                    }
                    Button("Quit") {
                        NSApp.terminate(nil)
                    }
                    .keyboardShortcut("q", modifiers: .command)
                }
                .padding(.top, 4)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SettingsColors.window)
        .onAppear {
            launchAtLogin = LaunchAtLoginManager.isEnabled
            responseDisplayMode = AppSettings.shared.responseDisplayMode
            openWebUIBaseURL = AppSettings.shared.openWebUIBaseURL
            openWebUIModel = AppSettings.shared.openWebUIModel
            openWebUISyncChats = AppSettings.shared.openWebUISyncChats
            savedOpenWebUIAPIKey = KeychainStorage.openWebUIAPIKey ?? ""
            isEditingOpenWebUICredentials = false
            notionTaskHotKey = AppSettings.shared.notionTaskHotKey
            newChatHotKey = AppSettings.shared.newChatHotKey
            reloadSavedNotionCredentials()
            isEditingNotionCredentials = false
            refreshPermissionStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionStatus()
        }
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            refreshPermissionStatus()
        }
    }

    private var shortcutsFooter: String {
        "Click a shortcut to record a new one. Notion and popup new-chat shortcuts stay active unless cleared later. Press Esc to cancel while recording."
    }

    private var aboutFooter: String {
        "Cursor Popup sends questions to your local Open WebUI server. With sync enabled, chats are stored in Open WebUI and open directly in the desktop app. Use ←→ to pick a project on new chats, and ↑↓ for history."
    }

    @ViewBuilder
    private var openWebUISettings: some View {
        rowDivider

        settingsRow("Server URL") {
            TextField("http://localhost:8080", text: $openWebUIBaseURL)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
                .onChange(of: openWebUIBaseURL) { newValue in
                    AppSettings.shared.openWebUIBaseURL = newValue
                }
        }

        rowDivider

        if isEditingOpenWebUICredentials {
            settingsRow("Open WebUI API key") {
                SecureField("sk-...", text: $openWebUIAPIKeyDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
            }

            HStack(spacing: 8) {
                Button("Save") {
                    saveOpenWebUICredentials()
                }
                .disabled(openWebUIAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Cancel") {
                    cancelEditingOpenWebUICredentials()
                }
            }
            .padding(.top, 2)
        } else {
            settingsRow("Open WebUI API key") {
                Text(maskedOpenWebUIAPIKey(savedOpenWebUIAPIKey))
                    .foregroundStyle(savedOpenWebUIAPIKey.isEmpty ? Color.orange : .secondary)
                    .textSelection(.enabled)
            }

            Button("Edit Open WebUI API key…") {
                beginEditingOpenWebUICredentials()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
        }

        rowDivider

        settingsRow("Model") {
            HStack(spacing: 8) {
                if availableOpenWebUIModels.isEmpty {
                    TextField("llama3.2", text: $openWebUIModel)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 180)
                        .onChange(of: openWebUIModel) { newValue in
                            AppSettings.shared.openWebUIModel = newValue
                        }
                } else {
                    Picker("", selection: $openWebUIModel) {
                        if openWebUIModel.isEmpty {
                            Text("Select a model").tag("")
                        }
                        ForEach(availableOpenWebUIModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 180)
                    .onChange(of: openWebUIModel) { newValue in
                        AppSettings.shared.openWebUIModel = newValue
                    }
                }

                Button(isLoadingOpenWebUIModels ? "Loading…" : "Refresh") {
                    refreshOpenWebUIModels()
                }
                .disabled(isLoadingOpenWebUIModels)
            }
        }

        if let openWebUIStatusMessage {
            Text(openWebUIStatusMessage)
                .font(.caption)
                .foregroundStyle(openWebUIStatusMessage.contains("Could not") ? .red : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        Toggle("Sync chats with Open WebUI", isOn: $openWebUISyncChats)
            .toggleStyle(.switch)
            .onChange(of: openWebUISyncChats) { newValue in
                AppSettings.shared.openWebUISyncChats = newValue
                appModel.refreshWorkspaceSessionCache()
                appModel.refreshOpenWebUIProjects()
            }

        footerText("This is your Open WebUI account API key (Account → Settings → Account → API keys). It authenticates Cursor Popup with your local Open WebUI server — not an OpenAI, Ollama, or other model provider key. The key is saved in macOS Keychain only and is never written to project files or git.")
    }

    private func maskedOpenWebUIAPIKey(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Not configured" }
        let visibleSuffix = trimmed.suffix(4)
        return "••••••••\(visibleSuffix)"
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
        let baseURL = openWebUIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = (isEditingOpenWebUICredentials ? openWebUIAPIKeyDraft : savedOpenWebUIAPIKey)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !baseURL.isEmpty else {
            openWebUIStatusMessage = "Enter a server URL first."
            return
        }
        guard !apiKey.isEmpty else {
            openWebUIStatusMessage = "Add your API key first."
            return
        }

        isLoadingOpenWebUIModels = true
        openWebUIStatusMessage = nil

        Task {
            do {
                let models = try await OpenWebUIRunner.fetchModels(baseURL: baseURL, apiKey: apiKey)
                await MainActor.run {
                    availableOpenWebUIModels = models
                    isLoadingOpenWebUIModels = false
                    if models.isEmpty {
                        openWebUIStatusMessage = "No models returned. Enter the model ID manually."
                    } else if openWebUIModel.isEmpty || !models.contains(openWebUIModel) {
                        openWebUIModel = models[0]
                        AppSettings.shared.openWebUIModel = models[0]
                        openWebUIStatusMessage = "Loaded \(models.count) model(s)."
                    } else {
                        openWebUIStatusMessage = "Loaded \(models.count) model(s)."
                    }
                }
            } catch {
                await MainActor.run {
                    availableOpenWebUIModels = []
                    isLoadingOpenWebUIModels = false
                    openWebUIStatusMessage = "Could not load models: \(error.localizedDescription)"
                }
            }
        }
    }

    private func refreshPermissionStatus() {
        accessibilityGranted = SystemPermissions.isAccessibilityGranted
        loginItemRegistered = LaunchAtLoginManager.isEnabled
    }

    private func permissionTaskRow(
        title: String,
        isComplete: Bool,
        isAutomatic: Bool,
        onToggle: ((Bool) -> Void)? = nil,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            permissionStatusDot(isComplete: isComplete, isAutomatic: isAutomatic) {
                onToggle?(!isComplete)
            }

            Button(action: action) {
                Text(title)
                    .font(.system(size: 13))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
        }
    }

    private func permissionStatusDot(
        isComplete: Bool,
        isAutomatic: Bool,
        onToggle: @escaping () -> Void
    ) -> some View {
        Group {
            if isAutomatic {
                permissionStatusDotView(isComplete: isComplete)
            } else {
                Button(action: onToggle) {
                    permissionStatusDotView(isComplete: isComplete)
                }
                .buttonStyle(.plain)
                .help(isComplete ? "Mark as not done" : "Mark as done")
            }
        }
        .frame(width: 16, height: 16)
    }

    private func permissionStatusDotView(isComplete: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay {
                Circle()
                    .fill(isComplete ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
            }
            .frame(width: 16, height: 16)
    }

    private var notionCredentialsCanSave: Bool {
        let token = notionTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let databaseID = notionDatabaseIDDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !databaseID.isEmpty else { return false }

        let savedToken = savedNotionToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedDatabaseID = savedNotionDatabaseID.trimmingCharacters(in: .whitespacesAndNewlines)
        return token != savedToken || databaseID != savedDatabaseID
    }

    private func reloadSavedNotionCredentials() {
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
        reloadSavedNotionCredentials()
        isEditingNotionCredentials = false
        appModel.loadNotionSchema(force: true)
    }

    private func maskedNotionToken(_ token: String) -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Not configured" }
        let visibleSuffix = trimmed.suffix(4)
        return "••••••••\(visibleSuffix)"
    }

    private func beginRecording(_ target: ShortcutTarget) {
        shortcutConflict = nil
        recordingTarget = target
    }

    private func cancelRecording() {
        recordingTarget = nil
        notionTaskHotKey = AppSettings.shared.notionTaskHotKey
        newChatHotKey = AppSettings.shared.newChatHotKey
    }

    private var menuBarShortcutFooter: String {
        "When hidden, use \(notionTaskHotKey.displayName) for Notion tasks. Open Cursor Popup from Applications to reach Settings and restore the icon."
    }

    private func commitHotKey(_ binding: HotKeyBinding, target: ShortcutTarget) {
        recordingTarget = nil

        let others: [(ShortcutTarget, HotKeyBinding?)] = [
            (.notionTask, notionTaskHotKey),
            (.newChat, newChatHotKey),
        ].filter { $0.0 != target }

        if others.compactMap(\.1).contains(where: { $0 == binding }) {
            shortcutConflict = "Each shortcut must be unique."
            notionTaskHotKey = AppSettings.shared.notionTaskHotKey
            newChatHotKey = AppSettings.shared.newChatHotKey
            return
        }

        shortcutConflict = nil

        switch target {
        case .notionTask:
            notionTaskHotKey = binding
            AppSettings.shared.notionTaskHotKey = binding
        case .newChat:
            newChatHotKey = binding
            AppSettings.shared.newChatHotKey = binding
        }

        appModel.reloadHotKeys()
    }

    @ViewBuilder
    private func settingsSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(SettingsColors.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(SettingsColors.cardBorder, lineWidth: 1)
            )
        }
    }

    private func settingsRow<Trailing: View>(_ label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
            Spacer(minLength: 8)
            trailing()
        }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(SettingsColors.rowDivider)
            .frame(height: 1)
    }

    private func footerText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
