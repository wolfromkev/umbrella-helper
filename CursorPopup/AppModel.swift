import AppKit
import Combine
import SwiftUI

enum HistoryNavigationDirection {
    case newer
    case older
}

enum WorkspaceNavigationDirection {
    case previous
    case next
}

@MainActor
final class AppModel: ObservableObject {
    @Published var isVisible = false
    @Published var isChatBoxVisible = false
    @Published var isSettingsVisible = false
    @Published var isNotionTaskVisible = false
    @Published var prompt = ""
    @Published var notionTaskTitle = ""
    @Published var notionSelectedCategory = NotionFieldSelection.none
    @Published var notionSelectedPriority = NotionFieldSelection.none
    @Published var notionDueDate: Date? = Date()
    @Published var notionSchema: NotionDatabaseSchema?
    @Published var isLoadingNotionSchema = false
    @Published var notionSchemaError: String?
    @Published var isNotionSubmitting = false
    @Published var notionStatusMessage: String?
    @Published var notionErrorMessage: String?
    @Published var lastCreatedNotionTaskURL: URL?
    @Published var messages: [ChatMessage] = []
    @Published var savedSessions: [SavedChatSession] = []
    @Published var historyIndex = 0
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var pendingAttachments: [PendingAttachment] = []
    @Published private(set) var activeWorkspacePath: String = AppSettings.shared.defaultWorkspacePath

    let settings = AppSettings.shared
    private let panelController = PanelController()
    private let chatPanelController = ChatPanelController()
    private let settingsPanelController = SettingsPanelController()
    private let notionTaskPanelController = NotionTaskPanelController()
    private let chatBoxHotKey = GlobalHotKey(registrationID: 2)
    private let notionTaskHotKey = GlobalHotKey(registrationID: 3)
    private let agentRunner = AgentRunner()
    private var sessionID: String?
    private var streamingAssistantID: UUID?
    private var agentRunGeneration = 0
    private var pasteMonitor: Any?
    private var sessionsByWorkspace: [String: [SavedChatSession]] = [:]

    var usesFloatingChatBox: Bool { settings.usesFloatingChatBox }

    var historyLabel: String {
        if historyIndex == 0 {
            return "New Chat"
        }
        guard historyIndex - 1 < savedSessions.count else { return "New Chat" }
        return savedSessions[historyIndex - 1].title
    }

    var canBrowseHistory: Bool {
        !savedSessions.isEmpty
    }

    var isBrandNewChat: Bool {
        historyIndex == 0
    }

    var canBrowseWorkspaces: Bool {
        settings.workspaceFolders.count > 1
    }

    var workspaceLabel: String {
        settings.displayName(for: activeWorkspacePath)
    }

    var notionTaskHasKeyboardFocus: Bool {
        notionTaskPanelController.hasKeyboardFocus
    }

    func canNavigateWorkspace(_ direction: WorkspaceNavigationDirection) -> Bool {
        let folders = settings.workspaceFolders
        guard folders.count > 1,
              let index = folders.firstIndex(of: activeWorkspacePath) else {
            return false
        }

        switch direction {
        case .previous:
            return index > 0
        case .next:
            return index < folders.count - 1
        }
    }

    var hasChatConversation: Bool {
        !messages.isEmpty
    }

    func start() {
        ActiveScreenTracker.start()
        panelController.configure(model: self)
        chatPanelController.configure(model: self)
        settingsPanelController.configure(model: self)
        notionTaskPanelController.configure(model: self)
        settings.bootstrapNotionConfiguration()
        resetActiveWorkspaceToDefault()
        reloadHotKeys()

        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            settings.launchAtLogin = true
        }

        if settings.launchAtLogin {
            LaunchAtLoginManager.setEnabled(true)
        }

        preloadStartupData()
    }

    private var isNotionConfigured: Bool {
        guard let token = KeychainStorage.notionToken, !token.isEmpty else { return false }
        return !settings.notionDatabaseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func preloadStartupData() {
        preloadWorkspaceSessions()
        // Notion schema (and keychain token read) loads on first F6 / Settings use — not at launch.
    }

    func refreshWorkspaceSessionCache() {
        preloadWorkspaceSessions()
    }

    private func preloadWorkspaceSessions() {
        let folders = settings.workspaceFolders
        let defaultPath = activeWorkspacePath

        Task.detached(priority: .utility) {
            var cache: [String: [SavedChatSession]] = [:]
            for folder in folders {
                cache[folder] = ChatSessionStore.loadSessions(for: folder)
            }

            await MainActor.run {
                self.sessionsByWorkspace = cache
                self.applyCachedSessions(for: defaultPath)
            }
        }
    }

    private func applyCachedSessions(for workspacePath: String) {
        savedSessions = sessionsByWorkspace[workspacePath] ?? []
        if historyIndex > savedSessions.count {
            historyIndex = savedSessions.count
        }
    }

    func stop() {
        ActiveScreenTracker.stop()
        chatBoxHotKey.unregister()
        notionTaskHotKey.unregister()
        removePasteMonitor()
        panelController.closePanel()
        chatPanelController.closePanel()
        settingsPanelController.closePanel()
        notionTaskPanelController.closePanel()
        agentRunner.cancel()
    }

    func reloadHotKeys() {
        chatBoxHotKey.register(hotKeyID: settings.chatBoxHotKey) { [weak self] in
            Task { @MainActor in self?.toggleChatBox() }
        }
        notionTaskHotKey.register(hotKeyID: settings.notionTaskHotKey) { [weak self] in
            Task { @MainActor in self?.toggleNotionTask() }
        }
    }

    func togglePopup() {
        if isVisible {
            hidePopup()
        } else {
            showPopup()
        }
    }

    func showPopup() {
        reloadSavedSessions()
        if !isLoading {
            historyIndex = 0
            applyHistorySelection(clearChatBox: true)
        }
        panelController.showPanel()
        isVisible = true
        updatePasteMonitor()
        NSApp.activate(ignoringOtherApps: true)
        panelController.focusPrompt()
    }

    func hidePopup() {
        guard isVisible else { return }
        isVisible = false
        updatePasteMonitor()
        panelController.closePanel()
    }

    func toggleChatBox() {
        if isChatBoxVisible {
            hideChatBox()
        } else {
            showChatBox()
        }
    }

    func showChatBox() {
        reloadSavedSessions()
        chatPanelController.showPanel()
        isChatBoxVisible = true
        updatePasteMonitor()
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideChatBox() {
        chatPanelController.closePanel()
        isChatBoxVisible = false
        updatePasteMonitor()
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
        if isChatBoxVisible {
            hideChatBox()
        }
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
        notionDueDate = Date()
        isNotionSubmitting = false
        notionStatusMessage = nil
        notionErrorMessage = nil
        lastCreatedNotionTaskURL = nil
    }

    func addPastedImage(_ image: NSImage) {
        guard pendingAttachments.count < AttachmentStore.maxAttachments else { return }
        guard let attachment = AttachmentStore.save(image) else { return }
        pendingAttachments.append(attachment)
        refreshInputLayout()
    }

    func removeAttachment(id: UUID) {
        pendingAttachments.removeAll { $0.id == id }
        refreshInputLayout()
    }

    func clearAttachments() {
        pendingAttachments.removeAll()
        refreshInputLayout()
    }

    var canSubmitPrompt: Bool {
        let hasPrompt = !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty
        let hasWorkspace = !activeWorkspacePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasPrompt && hasWorkspace
    }

    func reloadSavedSessions(forceReload: Bool = false) {
        let path = activeWorkspacePath

        if forceReload || sessionsByWorkspace[path] == nil {
            let loaded = ChatSessionStore.loadSessions(for: path)
            sessionsByWorkspace[path] = loaded
        }

        applyCachedSessions(for: path)
    }

    func resetActiveWorkspaceToDefault() {
        settings.ensureDefaultWorkspaceIsValid()
        activeWorkspacePath = settings.defaultWorkspacePath
    }

    func syncActiveWorkspaceWithSettings() {
        settings.ensureDefaultWorkspaceIsValid()
        let folders = settings.workspaceFolders
        guard !folders.isEmpty else { return }

        if !folders.contains(activeWorkspacePath) {
            activeWorkspacePath = settings.defaultWorkspacePath
            historyIndex = 0
            applyHistorySelection(clearChatBox: true)
        }

        refreshWorkspaceSessionCache()
    }

    func navigateWorkspace(_ direction: WorkspaceNavigationDirection) -> Bool {
        guard prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              pendingAttachments.isEmpty,
              !isLoading else {
            return false
        }

        let folders = settings.workspaceFolders
        guard folders.count > 1,
              let index = folders.firstIndex(of: activeWorkspacePath) else {
            return false
        }

        let newIndex: Int
        switch direction {
        case .previous:
            guard index > 0 else { return false }
            newIndex = index - 1
        case .next:
            guard index < folders.count - 1 else { return false }
            newIndex = index + 1
        }

        activeWorkspacePath = folders[newIndex]
        historyIndex = 0
        applyHistorySelection(clearChatBox: false)
        reloadSavedSessions()

        if isVisible && !usesFloatingChatBox {
            panelController.resizeToFitContent()
        }
        if isChatBoxVisible {
            chatPanelController.resizeToFitContent()
        }
        return true
    }

    func navigateHistory(_ direction: HistoryNavigationDirection) -> Bool {
        guard prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              pendingAttachments.isEmpty,
              !isLoading else {
            return false
        }

        reloadSavedSessions()

        switch direction {
        case .older:
            guard historyIndex < savedSessions.count else { return false }
            historyIndex += 1
        case .newer:
            guard historyIndex > 0 else { return false }
            historyIndex -= 1
        }

        applyHistorySelection()
        if !usesFloatingChatBox {
            panelController.resizeToFitContent()
        }
        return true
    }

    func applyHistorySelection(clearChatBox: Bool = false, clearPrompt: Bool = true) {
        if clearPrompt {
            prompt = ""
        }
        clearAttachments()
        errorMessage = nil
        isLoading = false
        streamingAssistantID = nil
        agentRunGeneration += 1
        agentRunner.cancel()

        if clearChatBox {
            hideChatBox()
        }

        if historyIndex == 0 {
            messages = []
            sessionID = nil
        } else {
            let session = savedSessions[historyIndex - 1]
            messages = session.messages
            sessionID = session.id
        }

        if isChatBoxVisible {
            chatPanelController.resizeToFitContent()
        }
    }

    func submitPrompt() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let imagePaths = pendingAttachments.map(\.filePath)
        guard canSubmitPrompt else { return }

        let outgoingPrompt = trimmed.isEmpty ? "What's in this image?" : trimmed

        if isLoading {
            finalizeInFlightAssistantForFollowUp()
        }

        agentRunGeneration += 1
        let runGeneration = agentRunGeneration

        isLoading = true
        errorMessage = nil
        prompt = ""
        clearAttachments()

        messages.append(ChatMessage(role: .user, text: outgoingPrompt, imagePaths: imagePaths))
        let assistantID = UUID()
        streamingAssistantID = assistantID
        messages.append(ChatMessage(id: assistantID, role: .assistant, text: "", isStreaming: true))

        if settings.usesFloatingChatBox {
            showChatBox()
            hidePopup()
            chatPanelController.resizeToFitContent()
        } else {
            panelController.resizeToFitContent()
        }

        schedulePanelResize()

        agentRunner.send(
            prompt: outgoingPrompt,
            workspace: activeWorkspacePath,
            sessionID: sessionID,
            imagePaths: imagePaths
        ) { [weak self] event in
            Task { @MainActor in
                guard let self, self.agentRunGeneration == runGeneration else { return }
                self.handleAgentEvent(event)
            }
        }
    }

    func refreshChatPanelLayout() {
        guard isChatBoxVisible else { return }
        chatPanelController.resizeToFitContent()
    }

    private func refreshInputLayout() {
        if isVisible {
            panelController.resizeToFitContent()
        }
        if isChatBoxVisible {
            chatPanelController.resizeToFitContent()
        }
    }

    private func schedulePanelResize() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshInputLayout()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.refreshInputLayout()
        }
    }

    private func updatePasteMonitor() {
        if isVisible || isChatBoxVisible {
            installPasteMonitorIfNeeded()
        } else {
            removePasteMonitor()
        }
    }

    private func installPasteMonitorIfNeeded() {
        guard pasteMonitor == nil else { return }

        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard
                let self,
                event.modifierFlags.contains(.command),
                event.charactersIgnoringModifiers?.lowercased() == "v",
                AttachmentStore.pasteboardHasImage(),
                let image = AttachmentStore.imageFromPasteboard()
            else {
                return event
            }

            self.addPastedImage(image)
            return nil
        }
    }

    private func removePasteMonitor() {
        if let pasteMonitor {
            NSEvent.removeMonitor(pasteMonitor)
            self.pasteMonitor = nil
        }
    }

    private func handleAgentEvent(_ event: AgentEvent) {
        switch event {
        case .sessionStarted(let id):
            sessionID = id
        case .textDelta(let delta):
            appendToStreamingAssistant(delta)
            if settings.usesFloatingChatBox {
                if isChatBoxVisible {
                    chatPanelController.resizeToFitContent()
                }
            } else if isVisible {
                panelController.resizeToFitContent()
            }
        case .textFinal(let text):
            replaceStreamingAssistantText(text)
            if settings.usesFloatingChatBox {
                if isChatBoxVisible {
                    chatPanelController.resizeToFitContent()
                }
            } else if isVisible {
                panelController.resizeToFitContent()
            }
        case .completed:
            finishStreamingAssistant()
            isLoading = false
            reloadSavedSessions(forceReload: true)
            playResponseCompletionSoundIfNeeded()
            if settings.usesFloatingChatBox, isChatBoxVisible {
                chatPanelController.resizeToFitContent()
            }
        case .failed(let message):
            finishStreamingAssistant()
            isLoading = false
            errorMessage = message
            if settings.usesFloatingChatBox {
                if isChatBoxVisible {
                    chatPanelController.resizeToFitContent()
                }
            } else if isVisible {
                panelController.resizeToFitContent()
            }
        }
    }

    private func appendToStreamingAssistant(_ delta: String) {
        guard let streamingAssistantID,
              let index = messages.firstIndex(where: { $0.id == streamingAssistantID }) else { return }
        var updated = messages[index]
        updated.text += delta
        updated.text = AssistantMessageFormatter.displayText(from: updated.text)
        messages[index] = updated
    }

    private func replaceStreamingAssistantText(_ text: String) {
        guard let streamingAssistantID,
              let index = messages.firstIndex(where: { $0.id == streamingAssistantID }) else { return }
        var updated = messages[index]
        updated.text = AssistantMessageFormatter.displayText(from: text)
        messages[index] = updated
    }

    private func finishStreamingAssistant() {
        guard let streamingAssistantID,
              let index = messages.firstIndex(where: { $0.id == streamingAssistantID }) else { return }
        var updated = messages[index]
        updated.isStreaming = false
        messages[index] = updated
        self.streamingAssistantID = nil
    }

    private func playResponseCompletionSoundIfNeeded() {
        guard messages.contains(where: { $0.role == .assistant && !$0.text.isEmpty }) else { return }
        ResponseSoundPlayer.playCompletion()
    }

    private func finalizeInFlightAssistantForFollowUp() {
        guard let streamingAssistantID,
              let index = messages.firstIndex(where: { $0.id == streamingAssistantID }) else { return }

        var updated = messages[index]
        updated.isStreaming = false
        if updated.text.isEmpty {
            messages.remove(at: index)
        } else {
            messages[index] = updated
        }
        self.streamingAssistantID = nil
    }

    var latestAssistantText: String {
        guard let text = messages.last(where: { $0.role == .assistant })?.text else { return "" }
        return AssistantMessageFormatter.displayText(from: text)
    }

    func openInCursorAgent() {
        CursorLauncher.openInCursorAgent(
            workspace: activeWorkspacePath,
            messages: messages,
            sessionID: sessionID,
            handoffMode: settings.cursorHandoffMode
        )
    }
}
