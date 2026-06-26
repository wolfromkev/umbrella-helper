import SwiftUI

private enum ChatScrollAnchor {
    static let bottom = "chat-scroll-bottom"
}

private struct MessagesContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct FloatingChatView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var isInputFocused: Bool
    @State private var messagesContentHeight: CGFloat = 0
    @State private var stickToBottom = true

    private var hasConversation: Bool {
        model.hasChatConversation
    }

    var body: some View {
        Group {
            if hasConversation {
                expandedBody
            } else {
                compactBody
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusChatInputField)) { _ in
            isInputFocused = true
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isInputFocused = true
            }
        }
    }

    private var compactBody: some View {
        compactInputBar
            .popupPillShadow()
            .padding(20)
            .frame(width: ChatPanelMetrics.panelWidth)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var expandedBody: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.12)
            messagesList
            Divider().opacity(0.12)
            expandedInputSection
            OpenInCursorAgentButton(title: model.externalChatHandoffLabel) {
                model.openInCursorAgent()
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
        .frame(width: ChatPanelMetrics.contentWidth, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.28), radius: 20, y: 8)
        )
        .padding(16)
        .frame(width: ChatPanelMetrics.panelWidth)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var messagesScrollHeight: CGFloat {
        guard messagesContentHeight > 0 else { return 0 }
        return min(messagesContentHeight, ChatPanelMetrics.messagesMaxHeight)
    }

    private var compactInputBar: some View {
        PromptInputShell(
            attachments: model.pendingAttachments,
            onRemoveAttachment: model.removeAttachment
        ) {
            HStack(spacing: 12) {
                InputBarLeadingChevron()

                TextField("What can I help you with today?", text: $model.prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .foregroundStyle(.primary)
                    .focused($isInputFocused)
                    .lineLimit(1...4)
                    .onSubmit { model.submitPrompt() }

                InputBarTrailingIndicator()

                SettingsToolbarButton {
                    model.showSettings()
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                if model.canBrowseWorkspaces || model.isBrandNewChat {
                    WorkspaceNavigatorView()
                } else {
                    Text(model.workspaceLabel)
                        .font(.system(size: 15, weight: .semibold))
                }
                if model.canBrowseHistory {
                    Text("\(model.historyLabel) · ↑↓ history")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()

            NewChatToolbarButton {
                model.startNewChat()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                messagesContent
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: MessagesContentHeightKey.self,
                                value: geometry.size.height
                            )
                        }
                    }
            }
            .frame(height: messagesScrollHeight > 0 ? messagesScrollHeight : nil)
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        if value.translation.height > 6 {
                            stickToBottom = false
                        } else if value.translation.height < -6 {
                            stickToBottom = true
                        }
                    }
            )
            .onPreferenceChange(MessagesContentHeightKey.self) { height in
                guard abs(height - messagesContentHeight) > 0.5 else { return }

                let previousScrollHeight = messagesScrollHeight
                messagesContentHeight = height
                let newScrollHeight = messagesScrollHeight

                if abs(previousScrollHeight - newScrollHeight) > 0.5 {
                    model.refreshChatPanelLayout()
                }
            }
            .onAppear {
                stickToBottom = true
                scrollToBottomAfterLayout(proxy: proxy)
            }
            .onChange(of: model.historyIndex) { _ in
                stickToBottom = true
                scrollToBottomAfterLayout(proxy: proxy)
            }
            .onChange(of: model.messages.count) { _ in
                stickToBottom = true
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: model.messages.last?.text ?? "") { _ in
                guard stickToBottom else { return }
                scrollToBottom(proxy: proxy, animated: false)
            }
        }
    }

    private var messagesContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(model.messages) { message in
                messageBubble(message)
                    .id(message.id)
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Color.clear
                .frame(height: 1)
                .id(ChatScrollAnchor.bottom)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user { Spacer(minLength: 40) }

            VStack(alignment: .leading, spacing: 8) {
                if !message.imagePaths.isEmpty {
                    MessageImageStrip(imagePaths: message.imagePaths)
                }

                if message.role == .assistant && displayText(for: message).isEmpty && (message.isStreaming || model.isLoading) {
                    ThinkingIndicatorView()
                } else if message.role == .assistant, !displayText(for: message).isEmpty {
                    MarkdownMessageText(text: displayText(for: message), fontSize: 14)
                } else if !message.text.isEmpty {
                    Text(message.text)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: ChatPanelMetrics.messageBubbleMaxWidth, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(message.role == .user ? ChatBubbleColors.user : ChatBubbleColors.assistant)
            )

            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }

    private func displayText(for message: ChatMessage) -> String {
        guard message.role == .assistant else { return message.text }
        return AssistantMessageFormatter.displayText(from: message.text)
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        let scroll = {
            proxy.scrollTo(ChatScrollAnchor.bottom, anchor: .bottom)
        }
        if animated {
            withAnimation(.easeOut(duration: 0.12)) {
                scroll()
            }
        } else {
            scroll()
        }
    }

    private func scrollToBottomAfterLayout(proxy: ScrollViewProxy) {
        scrollToBottom(proxy: proxy, animated: false)
        DispatchQueue.main.async {
            scrollToBottom(proxy: proxy, animated: false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            scrollToBottom(proxy: proxy, animated: false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            scrollToBottom(proxy: proxy, animated: false)
        }
    }

    private var expandedInputSection: some View {
        PromptInputShell(
            attachments: model.pendingAttachments,
            onRemoveAttachment: model.removeAttachment
        ) {
            HStack(spacing: 10) {
                TextField("Follow up…", text: $model.prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($isInputFocused)
                    .lineLimit(1...4)
                    .onSubmit { model.submitPrompt() }
            }
        }
    }
}
