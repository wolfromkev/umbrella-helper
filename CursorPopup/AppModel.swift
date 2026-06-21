import AppKit
import Combine
import SwiftUI

enum HistoryNavigationDirection {
    case newer
    case older
}

@MainActor
final class AppModel: ObservableObject {
    @Published var isVisible = false
    @Published var isChatBoxVisible = false
    @Published var isSettingsVisible = false
    @Published var prompt = ""
    @Published var messages: [ChatMessage] = []
    @Published var savedSessions: [SavedChatSession] = []
    @Published var historyIndex = 0
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var pendingAttachments: [PendingAttachment] = []

    let settings = AppSettings.shared
    private let panelController = PanelController()
    private let chatPanelController = ChatPanelController()
    private let settingsPanelController = SettingsPanelController()
    private let hotKey = GlobalHotKey(registrationID: 1)
    private let chatBoxHotKey = GlobalHotKey(registrationID: 2)
    private let agentRunner = AgentRunner()
    private var sessionID: String?
    private var streamingAssistantID: UUID?
    private var pasteMonitor: Any?

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

    var hasChatConversation: Bool {
        !messages.isEmpty
    }

    func start() {
        panelController.configure(model: self)
        chatPanelController.configure(model: self)
        settingsPanelController.configure(model: self)
        hotKey.register(hotKeyID: settings.hotKey) { [weak self] in
            Task { @MainActor in self?.togglePopup() }
        }
        chatBoxHotKey.register(hotKeyID: settings.chatBoxHotKey) { [weak self] in
            Task { @MainActor in self?.toggleChatBox() }
        }

        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            settings.launchAtLogin = true
        }

        if settings.launchAtLogin {
            LaunchAtLoginManager.setEnabled(true)
        }
    }

    func stop() {
        hotKey.unregister()
        chatBoxHotKey.unregister()
        removePasteMonitor()
        panelController.closePanel()
        chatPanelController.closePanel()
        settingsPanelController.closePanel()
        agentRunner.cancel()
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
        historyIndex = 0
        applyHistorySelection(clearChatBox: true)
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
        if !isChatBoxVisible {
            agentRunner.cancel()
        }
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
        if isLoading {
            agentRunner.cancel()
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
        (!prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty) && !isLoading
    }

    func reloadSavedSessions() {
        savedSessions = ChatSessionStore.loadSessions(for: settings.workspacePath)
        if historyIndex > savedSessions.count {
            historyIndex = savedSessions.count
        }
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

        agentRunner.send(
            prompt: outgoingPrompt,
            workspace: settings.workspacePath,
            sessionID: sessionID,
            imagePaths: imagePaths
        ) { [weak self] event in
            Task { @MainActor in
                self?.handleAgentEvent(event)
            }
        }
    }

    private func refreshInputLayout() {
        if isVisible {
            panelController.resizeToFitContent()
        }
        if isChatBoxVisible {
            chatPanelController.resizeToFitContent()
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
            if !settings.usesFloatingChatBox {
                panelController.resizeToFitContent()
            }
        case .completed:
            finishStreamingAssistant()
            isLoading = false
            reloadSavedSessions()
        case .failed(let message):
            finishStreamingAssistant()
            isLoading = false
            errorMessage = message
            if !settings.usesFloatingChatBox {
                panelController.resizeToFitContent()
            }
        }
    }

    private func appendToStreamingAssistant(_ delta: String) {
        guard let streamingAssistantID,
              let index = messages.firstIndex(where: { $0.id == streamingAssistantID }) else { return }
        messages[index].text += delta
    }

    private func finishStreamingAssistant() {
        guard let streamingAssistantID,
              let index = messages.firstIndex(where: { $0.id == streamingAssistantID }) else { return }
        messages[index].isStreaming = false
        self.streamingAssistantID = nil
    }

    var latestAssistantText: String {
        messages.last(where: { $0.role == .assistant })?.text ?? ""
    }

    func openInCursorAgent() {
        CursorLauncher.openInCursorAgent(
            workspace: settings.workspacePath,
            messages: messages
        )
    }
}
