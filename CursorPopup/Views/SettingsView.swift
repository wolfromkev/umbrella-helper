import AppKit
import SwiftUI

private enum SettingsColors {
    static let window = Color(nsColor: NSColor.windowBackgroundColor)
    static let card = Color(nsColor: NSColor.controlBackgroundColor)
    static let cardBorder = Color.primary.opacity(0.08)
    static let rowDivider = Color.primary.opacity(0.08)
}

private enum ShortcutTarget {
    case chatBox
    case notionTask
}

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @AppStorage(AppSettings.showMenuBarIconKey) private var showMenuBarIcon = true
    @AppStorage(AppSettings.playResponseSoundKey) private var playResponseSound = true
    @AppStorage(AppSettings.responseCompletionSoundKey) private var responseCompletionSound = CompletionSound.defaultSound.rawValue
    @State private var workspaceFolders = AppSettings.shared.workspaceFolders
    @State private var defaultWorkspacePath = AppSettings.shared.defaultWorkspacePath
    @State private var launchAtLogin = AppSettings.shared.launchAtLogin
    @State private var chatBoxHotKey = AppSettings.shared.chatBoxHotKey
    @State private var notionTaskHotKey = AppSettings.shared.notionTaskHotKey
    @State private var savedNotionToken = KeychainStorage.notionToken ?? ""
    @State private var savedNotionDatabaseID = AppSettings.shared.notionDatabaseID
    @State private var isEditingNotionCredentials = false
    @State private var notionTokenDraft = ""
    @State private var notionDatabaseIDDraft = ""
    @State private var responseDisplayMode = AppSettings.shared.responseDisplayMode
    @State private var recordingTarget: ShortcutTarget?
    @State private var shortcutConflict: String?
    @State private var accessibilityGranted = SystemPermissions.isAccessibilityGranted
    @AppStorage(AppSettings.permissionsAutomationDoneKey) private var permissionsAutomationDone = false
    @AppStorage(AppSettings.permissionsLoginItemsDoneKey) private var permissionsLoginItemsDone = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                settingsSection("Workspace") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(workspaceFolders, id: \.self) { folder in
                            workspaceFolderRow(folder)
                            if folder != workspaceFolders.last {
                                rowDivider
                            }
                        }

                        Button("Add folder…") {
                            addWorkspaceFolder()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .padding(.top, workspaceFolders.isEmpty ? 0 : 4)
                    }

                    footerText("Use the arrows in the chat bar to switch between folders. The starred folder opens when the app launches; closing chat keeps your current folder until you quit.")
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

                    footerText("Creates tasks in your Project Tracker database. Category, priority, and due date options are loaded live from Notion when you open the task popup.")
                }

                settingsSection("Shortcuts") {
                    settingsRow("Chat box") {
                        HotKeyRecorderView(
                            binding: $chatBoxHotKey,
                            isRecording: recordingTarget == .chatBox,
                            onBegin: { beginRecording(.chatBox) },
                            onCommit: { commitHotKey($0, target: .chatBox) },
                            onCancel: { cancelRecording() }
                        )
                    }

                    rowDivider

                    settingsRow("Notion task") {
                        HotKeyRecorderView(
                            binding: $notionTaskHotKey,
                            isRecording: recordingTarget == .notionTask,
                            onBegin: { beginRecording(.notionTask) },
                            onCommit: { commitHotKey($0, target: .notionTask) },
                            onCancel: { cancelRecording() }
                        )
                    }

                    if let shortcutConflict {
                        Text(shortcutConflict)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    footerText("Click a shortcut to record a new one. Press Esc to cancel.")
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

                    footerText("When hidden, use \(chatBoxHotKey.displayName) and \(notionTaskHotKey.displayName) as usual. Open Cursor Popup from Applications to reach Settings and restore the icon.")
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
                            title: "Grant Accessibility permission",
                            isComplete: accessibilityGranted,
                            isAutomatic: true
                        ) {
                            SystemPermissions.requestAccessibilityPrompt()
                        }

                        permissionTaskRow(
                            title: "Enable Cursor Popup in Accessibility settings",
                            isComplete: accessibilityGranted,
                            isAutomatic: true
                        ) {
                            SystemPermissions.openAccessibilitySettings()
                        }

                        permissionTaskRow(
                            title: "Allow Cursor Popup in Automation settings",
                            isComplete: permissionsAutomationDone,
                            isAutomatic: false,
                            onToggle: { permissionsAutomationDone = $0 }
                        ) {
                            SystemPermissions.openAutomationSettings()
                        }

                        permissionTaskRow(
                            title: "Add Cursor Popup to Login Items",
                            isComplete: permissionsLoginItemsDone,
                            isAutomatic: false,
                            onToggle: { permissionsLoginItemsDone = $0 }
                        ) {
                            SystemPermissions.openLoginItemsSettings()
                        }
                    }

                    footerText("Needed to detect clicks outside popups and place them on the correct screen. Grant these once in System Settings. If prompts keep coming back after reinstalling, open the project in Xcode, set your Team under Signing & Capabilities, and build from there so macOS remembers the app.")
                }

                settingsSection("About") {
                    footerText("Cursor Popup sends questions to the Cursor agent in ask mode against your Cursor Chat workspace. Each popup opens a fresh chat; follow-ups continue that session.")
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
            workspaceFolders = AppSettings.shared.workspaceFolders
            defaultWorkspacePath = AppSettings.shared.defaultWorkspacePath
            responseDisplayMode = AppSettings.shared.responseDisplayMode
            chatBoxHotKey = AppSettings.shared.chatBoxHotKey
            notionTaskHotKey = AppSettings.shared.notionTaskHotKey
            reloadSavedNotionCredentials()
            isEditingNotionCredentials = false
            accessibilityGranted = SystemPermissions.isAccessibilityGranted
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityGranted = SystemPermissions.isAccessibilityGranted
        }
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

    private func workspaceFolderRow(_ folder: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                setDefaultWorkspace(folder)
            } label: {
                Image(systemName: defaultWorkspacePath == folder ? "star.fill" : "star")
                    .font(.system(size: 13))
                    .foregroundStyle(defaultWorkspacePath == folder ? Color(red: 0.98, green: 0.55, blue: 0.18) : .secondary)
            }
            .buttonStyle(.plain)
            .help("Default on launch")

            VStack(alignment: .leading, spacing: 2) {
                Text(AppSettings.shared.displayName(for: folder))
                    .font(.system(size: 13, weight: .medium))
                Text(folder)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if workspaceFolders.count > 1 {
                Button {
                    removeWorkspaceFolder(folder)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove folder")
            }
        }
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

    private func persistWorkspaceFolders() {
        AppSettings.shared.workspaceFolders = workspaceFolders
        AppSettings.shared.defaultWorkspacePath = defaultWorkspacePath
        appModel.syncActiveWorkspaceWithSettings()
    }

    private func setDefaultWorkspace(_ folder: String) {
        defaultWorkspacePath = folder
        AppSettings.shared.defaultWorkspacePath = folder
    }

    private func addWorkspaceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.message = "Choose a folder to chat against in Cursor."

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let path = url.path
        guard !workspaceFolders.contains(path) else { return }

        workspaceFolders.append(path)
        if workspaceFolders.count == 1 {
            defaultWorkspacePath = path
        }
        persistWorkspaceFolders()
    }

    private func removeWorkspaceFolder(_ folder: String) {
        workspaceFolders.removeAll { $0 == folder }
        if defaultWorkspacePath == folder {
            defaultWorkspacePath = workspaceFolders.first ?? AppSettings.defaultWorkspace
        }
        persistWorkspaceFolders()
    }

    private func beginRecording(_ target: ShortcutTarget) {
        shortcutConflict = nil
        recordingTarget = target
    }

    private func cancelRecording() {
        recordingTarget = nil
        chatBoxHotKey = AppSettings.shared.chatBoxHotKey
        notionTaskHotKey = AppSettings.shared.notionTaskHotKey
    }

    private func commitHotKey(_ binding: HotKeyBinding, target: ShortcutTarget) {
        recordingTarget = nil

        let others: [(ShortcutTarget, HotKeyBinding)] = [
            (.chatBox, chatBoxHotKey),
            (.notionTask, notionTaskHotKey),
        ].filter { $0.0 != target }

        if others.contains(where: { $0.1 == binding }) {
            shortcutConflict = "Each shortcut must be unique."
            chatBoxHotKey = AppSettings.shared.chatBoxHotKey
            notionTaskHotKey = AppSettings.shared.notionTaskHotKey
            return
        }

        shortcutConflict = nil

        switch target {
        case .chatBox:
            chatBoxHotKey = binding
            AppSettings.shared.chatBoxHotKey = binding
        case .notionTask:
            notionTaskHotKey = binding
            AppSettings.shared.notionTaskHotKey = binding
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
