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
                Text("Opening chat…")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
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
                LogoMarkView(size: 22)
                    .frame(width: 28)

                TextField("What can I help you with today?", text: $model.prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .foregroundStyle(.primary)
                    .focused($isPromptFocused)
                    .lineLimit(1...4)
                    .disabled(model.isLoading)
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
                }

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
                .keyboardShortcut(.return, modifiers: [])
            }
        }
    }

    @ViewBuilder
    private var inlineResponseSection: some View {
        if model.isLoading || !model.latestAssistantText.isEmpty || model.errorMessage != nil {
            VStack(alignment: .leading, spacing: 10) {
                if model.isLoading && model.latestAssistantText.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Thinking…")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
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
        }
    }
}
