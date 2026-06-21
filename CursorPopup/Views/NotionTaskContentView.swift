import AppKit
import SwiftUI

private enum NotionMetadataField: Hashable {
    case category
    case priority
    case dueDate
}

private enum NotionPanelLayout {
    static let contentWidth: CGFloat = 560
}

struct NotionTaskContentView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var isTaskFocused: Bool
    @FocusState private var isSettingsFocused: Bool
    @State private var focusedMetadataField: NotionMetadataField?
    @State private var dueDateShowsActualDate = false

    private var showsFeedback: Bool {
        model.isNotionSubmitting || model.notionStatusMessage != nil || model.notionErrorMessage != nil
    }

    var body: some View {
        VStack(spacing: showsFeedback ? 0 : 8) {
            if showsFeedback {
                feedbackSection
                Divider().opacity(0.08)
            }

            inputCard
        }
        .frame(width: NotionPanelLayout.contentWidth)
        .background {
            if showsFeedback {
                PopupPillBackground(cornerRadius: 28)
            }
        }
        .popupPillShadow()
        .padding(14)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(NotificationCenter.default.publisher(for: .focusNotionTaskField)) { _ in
            isTaskFocused = true
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isTaskFocused = true
            }
        }
        .onChange(of: model.isLoadingNotionSchema) { _ in
            model.refreshNotionTaskLayout()
        }
        .onChange(of: model.notionSchema) { _ in
            model.refreshNotionTaskLayout()
            focusedMetadataField = nil
            dueDateShowsActualDate = false
        }
        .onChange(of: focusedMetadataField) { field in
            if field != nil {
                isSettingsFocused = false
            }
            if field != .dueDate {
                dueDateShowsActualDate = false
            }
        }
        .localKeyMonitor { handleKeyEvent($0) }
    }

    private var inputCard: some View {
        PromptInputShell(
            attachments: [],
            onRemoveAttachment: { _ in },
            showsBackground: !showsFeedback,
            horizontalPadding: 14,
            verticalPadding: 10
        ) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)

                    TextField("Add a task to notion", text: $model.notionTaskTitle, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                        .focused($isTaskFocused)
                        .lineLimit(1...3)
                        .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
                        .disabled(model.isNotionSubmitting)
                        .onSubmit {
                            model.submitNotionTask()
                        }
                        .onChange(of: isTaskFocused) { isFocused in
                            if isFocused {
                                focusedMetadataField = nil
                                isSettingsFocused = false
                            }
                        }

                    if model.isLoadingNotionSchema {
                        ProgressView()
                            .controlSize(.small)
                    } else if let schema = model.notionSchema {
                        inlineMetadataFields(schema: schema)
                    }

                    HStack(spacing: 6) {
                        Text("Notion")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        SettingsToolbarButton {
                            model.showSettings()
                        }
                        .focused($isSettingsFocused)
                        .onChange(of: isSettingsFocused) { focused in
                            if focused {
                                focusedMetadataField = nil
                                isTaskFocused = false
                            }
                        }
                    }
                }

                if let schemaError = model.notionSchemaError {
                    Text(schemaError)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
    }

    @ViewBuilder
    private func inlineMetadataFields(schema: NotionDatabaseSchema) -> some View {
        HStack(spacing: 6) {
            if schema.categoryProperty != nil {
                inlineOptionalPicker(
                    selection: $model.notionSelectedCategory,
                    options: schema.categoryOptions
                )
                .metadataFieldFocus(.category, focusedField: $focusedMetadataField, taskFocused: $isTaskFocused)
            }

            if schema.priorityProperty != nil {
                inlineOptionalPicker(
                    selection: $model.notionSelectedPriority,
                    options: schema.priorityOptions
                )
                .metadataFieldFocus(.priority, focusedField: $focusedMetadataField, taskFocused: $isTaskFocused)
            }

            if schema.dueDateProperty != nil {
                inlineDueDateLabel
                    .metadataFieldFocus(.dueDate, focusedField: $focusedMetadataField, taskFocused: $isTaskFocused)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var inlineDueDateLabel: some View {
        Text(dueDateDisplayText)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
    }

    private var dueDateDisplayText: String {
        let date = model.notionDueDate ?? Date()

        if dueDateShowsActualDate {
            return Self.formatDueDate(date)
        }

        if Calendar.current.isDateInToday(date) {
            return "Today"
        }

        return Self.formatDueDate(date)
    }

    private static func formatDueDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func inlineOptionalPicker(selection: Binding<String>, options: [String]) -> some View {
        let display = selection.wrappedValue == NotionFieldSelection.none ? "None" : selection.wrappedValue

        return Menu {
            Button("None") {
                selection.wrappedValue = NotionFieldSelection.none
            }
            Divider()
            ForEach(options, id: \.self) { option in
                Button(option) {
                    selection.wrappedValue = option
                }
            }
        } label: {
            Text(display)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func availableMetadataFields(schema: NotionDatabaseSchema) -> [NotionMetadataField] {
        var fields: [NotionMetadataField] = []
        if schema.categoryProperty != nil { fields.append(.category) }
        if schema.priorityProperty != nil { fields.append(.priority) }
        if schema.dueDateProperty != nil { fields.append(.dueDate) }
        return fields
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        guard model.isNotionTaskVisible else { return event }
        guard !model.isNotionSubmitting else { return event }

        let fields = model.notionSchema.map { availableMetadataFields(schema: $0) } ?? []

        if event.keyCode == HistoryKeyCodes.tab {
            if event.modifierFlags.contains(.shift) {
                focusPrevious(in: fields)
            } else {
                focusNext(in: fields)
            }
            return nil
        }

        guard let schema = model.notionSchema else { return event }
        guard !fields.isEmpty else { return event }

        switch event.keyCode {
        case HistoryKeyCodes.leftArrow:
            if isSettingsFocused {
                if let last = fields.last {
                    focusMetadataField(last)
                } else {
                    focusTaskField()
                }
                return nil
            }
            if let focusedMetadataField,
               fields.firstIndex(of: focusedMetadataField) == 0 {
                focusTaskField()
                return nil
            }
            if focusedMetadataField != nil {
                moveMetadataFocus(in: fields, direction: -1)
                return nil
            }
            return event

        case HistoryKeyCodes.rightArrow:
            if isTaskFocused {
                focusFirstMetadataField(in: fields)
                return nil
            }
            if isSettingsFocused {
                focusTaskField()
                return nil
            }
            if let focusedMetadataField,
               fields.lastIndex(of: focusedMetadataField) == fields.count - 1 {
                focusSettingsField()
                return nil
            }
            if focusedMetadataField != nil {
                moveMetadataFocus(in: fields, direction: 1)
                return nil
            }
            return event

        case HistoryKeyCodes.downArrow:
            if isTaskFocused {
                focusFirstMetadataField(in: fields)
                return nil
            }
            if let focusedMetadataField {
                adjustMetadataValue(for: focusedMetadataField, schema: schema, direction: 1)
                return nil
            }
            return event

        case HistoryKeyCodes.upArrow:
            if let focusedMetadataField {
                adjustMetadataValue(for: focusedMetadataField, schema: schema, direction: -1)
                return nil
            }
            return event

        default:
            if let focusedMetadataField,
               let typedLetter = Self.typedLetter(from: event) {
                switch focusedMetadataField {
                case .category:
                    selectFirstOption(
                        startingWith: typedLetter,
                        options: schema.categoryOptions,
                        selection: \.notionSelectedCategory
                    )
                    return nil
                case .priority:
                    selectFirstOption(
                        startingWith: typedLetter,
                        options: schema.priorityOptions,
                        selection: \.notionSelectedPriority
                    )
                    return nil
                case .dueDate:
                    break
                }
            }
            return event
        }
    }

    private static func typedLetter(from event: NSEvent) -> Character? {
        guard
            !event.modifierFlags.contains(.command),
            !event.modifierFlags.contains(.control),
            !event.modifierFlags.contains(.option),
            let characters = event.charactersIgnoringModifiers,
            characters.count == 1,
            let character = characters.first,
            character.isLetter
        else {
            return nil
        }
        return character
    }

    private func selectFirstOption(
        startingWith letter: Character,
        options: [String],
        selection: ReferenceWritableKeyPath<AppModel, String>
    ) {
        let prefix = String(letter).lowercased()
        guard let match = options.first(where: { $0.lowercased().hasPrefix(prefix) }) else { return }
        model[keyPath: selection] = match
    }

    private func focusTaskField() {
        focusedMetadataField = nil
        isSettingsFocused = false
        isTaskFocused = true
    }

    private func focusSettingsField() {
        focusedMetadataField = nil
        isTaskFocused = false
        isSettingsFocused = true
    }

    private func focusMetadataField(_ field: NotionMetadataField) {
        isTaskFocused = false
        isSettingsFocused = false
        focusedMetadataField = field
    }

    private func focusNext(in fields: [NotionMetadataField]) {
        if isSettingsFocused {
            focusTaskField()
            return
        }

        if let focusedMetadataField,
           let index = fields.firstIndex(of: focusedMetadataField) {
            if index + 1 < fields.count {
                focusMetadataField(fields[index + 1])
            } else {
                focusSettingsField()
            }
            return
        }

        if isTaskFocused {
            if let first = fields.first {
                focusMetadataField(first)
            } else {
                focusSettingsField()
            }
            return
        }

        focusTaskField()
    }

    private func focusPrevious(in fields: [NotionMetadataField]) {
        if isSettingsFocused {
            if let last = fields.last {
                focusMetadataField(last)
            } else {
                focusTaskField()
            }
            return
        }

        if let focusedMetadataField,
           let index = fields.firstIndex(of: focusedMetadataField) {
            if index > 0 {
                focusMetadataField(fields[index - 1])
            } else {
                focusTaskField()
            }
            return
        }

        if isTaskFocused {
            focusSettingsField()
            return
        }

        focusTaskField()
    }

    private func focusFirstMetadataField(in fields: [NotionMetadataField]) {
        guard let first = fields.first else { return }
        focusMetadataField(first)
    }

    private func moveMetadataFocus(in fields: [NotionMetadataField], direction: Int) {
        guard let focusedMetadataField,
              let currentIndex = fields.firstIndex(of: focusedMetadataField) else { return }

        let nextIndex = currentIndex + direction
        guard fields.indices.contains(nextIndex) else { return }
        self.focusedMetadataField = fields[nextIndex]
    }

    private func adjustMetadataValue(for field: NotionMetadataField, schema: NotionDatabaseSchema, direction: Int) {
        switch field {
        case .category:
            model.notionSelectedCategory = cycleSelection(
                current: model.notionSelectedCategory,
                options: schema.categoryOptions,
                direction: direction
            )
        case .priority:
            model.notionSelectedPriority = cycleSelection(
                current: model.notionSelectedPriority,
                options: schema.priorityOptions,
                direction: direction
            )
        case .dueDate:
            dueDateShowsActualDate = true
            let dueDate = model.notionDueDate ?? Date()
            model.notionDueDate = Calendar.current.date(byAdding: .day, value: direction, to: dueDate) ?? dueDate
        }
    }

    private func cycleSelection(current: String, options: [String], direction: Int) -> String {
        let allOptions = [NotionFieldSelection.none] + options
        guard let index = allOptions.firstIndex(of: current) else { return current }
        let nextIndex = (index + direction + allOptions.count) % allOptions.count
        return allOptions[nextIndex]
    }

    @ViewBuilder
    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.isNotionSubmitting {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Adding to Notion…")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }

            if let notionStatusMessage = model.notionStatusMessage {
                Text(notionStatusMessage)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
            }

            if let errorMessage = model.notionErrorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

private struct MetadataFieldFocusModifier: ViewModifier {
    let field: NotionMetadataField
    @Binding var focusedField: NotionMetadataField?
    var taskFocused: FocusState<Bool>.Binding

    private var isFocused: Bool {
        focusedField == field
    }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        Color(nsColor: NSColor(
                            calibratedWhite: isFocused ? 0.24 : 0.18,
                            alpha: isFocused ? 0.95 : 0
                        ))
                    )
            }
            .shadow(color: .black.opacity(isFocused ? 0.24 : 0), radius: isFocused ? 5 : 0, y: isFocused ? 2 : 0)
            .offset(y: isFocused ? -1 : 0)
            .animation(.easeOut(duration: 0.14), value: isFocused)
            .contentShape(Rectangle())
            .onHover { isHovering in
                if isHovering {
                    taskFocused.wrappedValue = false
                    focusedField = field
                }
            }
            .onTapGesture {
                taskFocused.wrappedValue = false
                focusedField = field
            }
    }
}

private extension View {
    func metadataFieldFocus(
        _ field: NotionMetadataField,
        focusedField: Binding<NotionMetadataField?>,
        taskFocused: FocusState<Bool>.Binding
    ) -> some View {
        modifier(MetadataFieldFocusModifier(field: field, focusedField: focusedField, taskFocused: taskFocused))
    }

    func localKeyMonitor(_ handler: @escaping (NSEvent) -> NSEvent?) -> some View {
        modifier(LocalKeyMonitorModifier(handler: handler))
    }
}

private struct LocalKeyMonitorModifier: ViewModifier {
    let handler: (NSEvent) -> NSEvent?
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: handler)
            }
            .onDisappear {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                }
            }
    }
}
