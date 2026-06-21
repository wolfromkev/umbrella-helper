import SwiftUI

private enum ChatScrollAnchor {
    static let bottom = "chat-scroll-bottom"
}

struct FloatingChatView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var isInputFocused: Bool

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
            OpenInCursorAgentButton {
                model.openInCursorAgent()
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
        .frame(width: ChatPanelMetrics.contentWidth, height: ChatPanelMetrics.expandedHeight - 32, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.28), radius: 20, y: 8)
        )
        .padding(16)
        .frame(width: ChatPanelMetrics.panelWidth, height: ChatPanelMetrics.expandedHeight)
    }

    private var compactInputBar: some View {
        PromptInputShell(
            attachments: model.pendingAttachments,
            onRemoveAttachment: model.removeAttachment
        ) {
            HStack(spacing: 12) {
                LogoMarkView(size: 22)
                    .frame(width: 28)

                TextField("What can I help you with today?", text: $model.prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .foregroundStyle(.primary)
                    .focused($isInputFocused)
                    .lineLimit(1...4)
                    .disabled(model.isLoading)
                    .onSubmit { model.submitPrompt() }

                VStack(alignment: .trailing, spacing: 2) {
                    Text(model.historyLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 140, alignment: .trailing)
                    if model.canBrowseHistory {
                        Text("↑↓ history")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.secondary.opacity(0.7))
                    }
                }
                .padding(.horizontal, 2)

                Button(action: model.submitPrompt) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(model.canSubmitPrompt ? Color(red: 0.98, green: 0.55, blue: 0.18) : Color.gray.opacity(0.35))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!model.canSubmitPrompt)
            }
        }
    }

    private var header: some View {
        HStack {
            LogoMarkView(size: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("Cursor Chat")
                    .font(.system(size: 15, weight: .semibold))
                if model.canBrowseHistory {
                    Text("\(model.historyLabel) · ↑↓ history")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(model.messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }

                    if model.isLoading && (model.messages.last?.role != .assistant || model.messages.last?.text.isEmpty == true) {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Thinking…")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4)
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
            .onAppear {
                scrollToBottomAfterLayout(proxy: proxy)
            }
            .onChange(of: model.historyIndex) { _ in
                scrollToBottomAfterLayout(proxy: proxy)
            }
            .onChange(of: model.messages.count) { _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: model.messages.last?.text ?? "") { _ in
                scrollToBottom(proxy: proxy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }

            VStack(alignment: .leading, spacing: 8) {
                if !message.imagePaths.isEmpty {
                    MessageImageStrip(imagePaths: message.imagePaths)
                }

                if !message.text.isEmpty || message.isStreaming {
                    Text(message.text.isEmpty && message.isStreaming ? "…" : message.text)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(message.role == .user
                          ? Color(red: 0.98, green: 0.55, blue: 0.18).opacity(0.22)
                          : Color(nsColor: NSColor(calibratedWhite: 0.14, alpha: 0.95)))
            )

            if message.role == .assistant { Spacer(minLength: 40) }
        }
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
                    .disabled(model.isLoading)
                    .onSubmit { model.submitPrompt() }

                Button(action: model.submitPrompt) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(model.canSubmitPrompt ? Color(red: 0.98, green: 0.55, blue: 0.18) : Color.gray.opacity(0.35))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!model.canSubmitPrompt)
            }
        }
    }
}
