import SwiftUI

struct PopupContentView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var isPromptFocused: Bool

    private var showsInlineResponse: Bool {
        !model.usesFloatingChatBox
            && (model.isLoading || !model.latestAssistantText.isEmpty || model.errorMessage != nil)
    }

    var body: some View {
        VStack(spacing: showsInlineResponse ? 0 : 14) {
            if showsInlineResponse {
                inlineResponseSection
                Divider().opacity(0.08)
            } else if model.usesFloatingChatBox && model.isLoading {
                ThinkingIndicatorView(
                    label: "Opening chat…",
                    dotColor: Color.white.opacity(0.72),
                    showsPencil: true
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }

            inputBar

            if !showsInlineResponse {
                OpenInCursorAgentButton {
                    model.openInCursorAgent()
                }
            }
        }
        .frame(width: PanelMetrics.popupWidth - 32)
        .background {
            if showsInlineResponse {
                PopupPillBackground(cornerRadius: 28)
            }
        }
        .popupPillShadow()
        .padding(20)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(NotificationCenter.default.publisher(for: .focusPromptField)) { _ in
            isPromptFocused = true
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isPromptFocused = true
            }
        }
    }

    private var inputBar: some View {
        PromptInputShell(
            attachments: model.pendingAttachments,
            onRemoveAttachment: model.removeAttachment,
            showsBackground: !showsInlineResponse
        ) {
            HStack(spacing: 12) {
                if !model.usesFloatingChatBox {
                    InputBarLeadingChevron()
                }

                TextField("What can I help you with today?", text: $model.prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .foregroundStyle(.primary)
                    .focused($isPromptFocused)
                    .lineLimit(1...4)
                    .onSubmit {
                        model.submitPrompt()
                    }

                if model.usesFloatingChatBox {
                    Button("Chat") {
                        model.showChatBox()
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                } else {
                    InputBarTrailingIndicator()
                }

                SettingsToolbarButton {
                    model.showSettings()
                }
            }
        }
    }

    @ViewBuilder
    private var inlineResponseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.isLoading && model.latestAssistantText.isEmpty {
                ThinkingIndicatorView(
                    label: "Thinking…",
                    dotColor: Color.white.opacity(0.72),
                    showsPencil: true
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !model.latestAssistantText.isEmpty {
                ScrollView {
                    Text(model.latestAssistantText)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 320)
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(
            minHeight: model.isLoading && model.latestAssistantText.isEmpty ? 52 : nil,
            alignment: .topLeading
        )
    }
}
