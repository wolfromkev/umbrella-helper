import AppKit
import Carbon

struct HotKeyBinding: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let notionTaskDefault = HotKeyBinding(
        keyCode: UInt32(kVK_F4),
        modifiers: 0
    )

    static let newChatDefault = HotKeyBinding(
        keyCode: UInt32(kVK_ANSI_N),
        modifiers: UInt32(cmdKey | shiftKey)
    )

    static let snipAreaDefault = HotKeyBinding(
        keyCode: UInt32(kVK_ANSI_S),
        modifiers: UInt32(cmdKey | shiftKey)
    )

    static let snipWindowDefault = HotKeyBinding(
        keyCode: UInt32(kVK_ANSI_W),
        modifiers: UInt32(cmdKey | shiftKey)
    )

    static let snipFullScreenDefault = HotKeyBinding(
        keyCode: UInt32(kVK_ANSI_A),
        modifiers: UInt32(cmdKey | shiftKey)
    )

    static let recordAreaDefault = HotKeyBinding(
        keyCode: UInt32(kVK_ANSI_R),
        modifiers: UInt32(cmdKey | shiftKey)
    )

    static let snipTextDefault = HotKeyBinding(
        keyCode: UInt32(kVK_ANSI_T),
        modifiers: UInt32(cmdKey | shiftKey)
    )

    static let brightnessDownDefault = HotKeyBinding(
        keyCode: UInt32(kVK_F1),
        modifiers: 0
    )

    static let brightnessUpDefault = HotKeyBinding(
        keyCode: UInt32(kVK_F2),
        modifiers: 0
    )

    static let warmthUpDefault = HotKeyBinding(
        keyCode: UInt32(kVK_F1),
        modifiers: UInt32(shiftKey)
    )

    static let warmthDownDefault = HotKeyBinding(
        keyCode: UInt32(kVK_F2),
        modifiers: UInt32(shiftKey)
    )

    var displayName: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(Self.keyCodeDisplayName(keyCode))
        return parts.joined()
    }

    static func from(event: NSEvent) -> HotKeyBinding? {
        guard !Self.isModifierKeyCode(event.keyCode) else { return nil }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbonModifiers: UInt32 = 0
        if flags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if flags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }

        return HotKeyBinding(keyCode: UInt32(event.keyCode), modifiers: carbonModifiers)
    }

    private static func isModifierKeyCode(_ keyCode: UInt16) -> Bool {
        switch Int(keyCode) {
        case kVK_Shift, kVK_RightShift,
             kVK_Command, kVK_RightCommand,
             kVK_Option, kVK_RightOption,
             kVK_Control, kVK_RightControl,
             kVK_CapsLock, kVK_Function:
            return true
        default:
            return false
        }
    }

    private static func keyCodeDisplayName(_ keyCode: UInt32) -> String {
        if let name = namedKeyCodes[Int(keyCode)] {
            return name
        }
        return "Key \(keyCode)"
    }

    private static let namedKeyCodes: [Int: String] = [
        Int(kVK_Space): "Space",
        Int(kVK_Return): "Return",
        Int(kVK_Tab): "Tab",
        Int(kVK_Escape): "Esc",
        Int(kVK_Delete): "Delete",
        Int(kVK_ForwardDelete): "Forward Delete",
        Int(kVK_UpArrow): "↑",
        Int(kVK_DownArrow): "↓",
        Int(kVK_LeftArrow): "←",
        Int(kVK_RightArrow): "→",
        Int(kVK_Home): "Home",
        Int(kVK_End): "End",
        Int(kVK_PageUp): "Page Up",
        Int(kVK_PageDown): "Page Down",
        Int(kVK_F1): "F1",
        Int(kVK_F2): "F2",
        Int(kVK_F3): "F3",
        Int(kVK_F4): "F4",
        Int(kVK_F5): "F5",
        Int(kVK_F6): "F6",
        Int(kVK_F7): "F7",
        Int(kVK_F8): "F8",
        Int(kVK_F9): "F9",
        Int(kVK_F10): "F10",
        Int(kVK_F11): "F11",
        Int(kVK_F12): "F12",
        Int(kVK_F13): "F13",
        Int(kVK_F14): "F14",
        Int(kVK_F15): "F15",
        Int(kVK_F16): "F16",
        Int(kVK_F17): "F17",
        Int(kVK_F18): "F18",
        Int(kVK_F19): "F19",
        Int(kVK_F20): "F20",
        Int(kVK_ANSI_A): "A",
        Int(kVK_ANSI_B): "B",
        Int(kVK_ANSI_C): "C",
        Int(kVK_ANSI_D): "D",
        Int(kVK_ANSI_E): "E",
        Int(kVK_ANSI_F): "F",
        Int(kVK_ANSI_G): "G",
        Int(kVK_ANSI_H): "H",
        Int(kVK_ANSI_I): "I",
        Int(kVK_ANSI_J): "J",
        Int(kVK_ANSI_K): "K",
        Int(kVK_ANSI_L): "L",
        Int(kVK_ANSI_M): "M",
        Int(kVK_ANSI_N): "N",
        Int(kVK_ANSI_O): "O",
        Int(kVK_ANSI_P): "P",
        Int(kVK_ANSI_Q): "Q",
        Int(kVK_ANSI_R): "R",
        Int(kVK_ANSI_S): "S",
        Int(kVK_ANSI_T): "T",
        Int(kVK_ANSI_U): "U",
        Int(kVK_ANSI_V): "V",
        Int(kVK_ANSI_W): "W",
        Int(kVK_ANSI_X): "X",
        Int(kVK_ANSI_Y): "Y",
        Int(kVK_ANSI_Z): "Z",
        Int(kVK_ANSI_0): "0",
        Int(kVK_ANSI_1): "1",
        Int(kVK_ANSI_2): "2",
        Int(kVK_ANSI_3): "3",
        Int(kVK_ANSI_4): "4",
        Int(kVK_ANSI_5): "5",
        Int(kVK_ANSI_6): "6",
        Int(kVK_ANSI_7): "7",
        Int(kVK_ANSI_8): "8",
        Int(kVK_ANSI_9): "9",
        Int(kVK_ANSI_Grave): "`",
        Int(kVK_ANSI_Minus): "-",
        Int(kVK_ANSI_Equal): "=",
        Int(kVK_ANSI_LeftBracket): "[",
        Int(kVK_ANSI_RightBracket): "]",
        Int(kVK_ANSI_Backslash): "\\",
        Int(kVK_ANSI_Semicolon): ";",
        Int(kVK_ANSI_Quote): "'",
        Int(kVK_ANSI_Comma): ",",
        Int(kVK_ANSI_Period): ".",
        Int(kVK_ANSI_Slash): "/",
    ]
}

final class AppSettings {
    static let shared = AppSettings()

    static let showMenuBarIconKey = "showMenuBarIcon"
    static let playResponseSoundKey = Keys.playResponseSound
    static let responseCompletionSoundKey = Keys.responseCompletionSound

    private enum Keys {
        static let workspacePath = "workspacePath"
        static let workspaceFolders = "workspaceFolders"
        static let defaultWorkspacePath = "defaultWorkspacePath"
        static let notionTaskHotKey = "notionTaskHotKey"
        static let newChatHotKey = "newChatHotKey"
        static let snipAreaHotKey = "snipAreaHotKey"
        static let snipWindowHotKey = "snipWindowHotKey"
        static let snipFullScreenHotKey = "snipFullScreenHotKey"
        static let snipRecordHotKey = "snipRecordHotKey"
        static let snipTextHotKey = "snipTextHotKey"
        static let brightnessDownHotKey = "brightnessDownHotKey"
        static let brightnessUpHotKey = "brightnessUpHotKey"
        static let warmthUpHotKey = "warmthUpHotKey"
        static let warmthDownHotKey = "warmthDownHotKey"
        static let sunScreenPresetHotKeys = "sunScreenPresetHotKeys"
        static let notionDatabaseID = "notionDatabaseID"
        static let launchAtLogin = "launchAtLogin"
        static let responseDisplayMode = "responseDisplayMode"
        static let chatBackend = "chatBackend"
        static let openWebUIBaseURL = "openWebUIBaseURL"
        static let openWebUIModel = "openWebUIModel"
        static let openWebUIActiveFolderID = "openWebUIActiveFolderID"
        static let openWebUISyncChats = "openWebUISyncChats"
        static let cursorHandoffMode = "cursorHandoffMode"
        static let cursorHandoffTarget = "cursorHandoffTarget"
        static let playResponseSound = "playResponseSound"
        static let responseCompletionSound = "responseCompletionSound"
        static let showMenuBarIcon = showMenuBarIconKey
        static let permissionsAutomationDone = "permissionsAutomationDone"
        static let permissionsLoginItemsDone = "permissionsLoginItemsDone"
    }

    static let permissionsAutomationDoneKey = Keys.permissionsAutomationDone
    static let permissionsLoginItemsDoneKey = Keys.permissionsLoginItemsDone

    static let defaultWorkspace = ""
    static let defaultNotionDatabaseID = ""
    static let defaultOpenWebUIBaseURL = "http://localhost:8080"
    static let defaultOpenWebUIModel = ""
    static let notionDefaultStatus = "Not started"

    func bootstrapNotionConfiguration() {
        KeychainStorage.seedBootstrapCredentialsIfNeeded()
    }

    var workspaceFolders: [String] {
        get {
            if let data = UserDefaults.standard.data(forKey: Keys.workspaceFolders),
               let folders = try? JSONDecoder().decode([String].self, from: data),
               !folders.isEmpty {
                return folders
            }

            let legacy = UserDefaults.standard.string(forKey: Keys.workspacePath) ?? Self.defaultWorkspace
            let trimmed = legacy.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [trimmed]
        }
        set {
            let trimmed = newValue
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if let data = try? JSONEncoder().encode(trimmed) {
                UserDefaults.standard.set(data, forKey: Keys.workspaceFolders)
            }
            ensureDefaultWorkspaceIsValid()
        }
    }

    var defaultWorkspacePath: String {
        get {
            if let path = UserDefaults.standard.string(forKey: Keys.defaultWorkspacePath),
               workspaceFolders.contains(path) {
                return path
            }
            return workspaceFolders.first ?? Self.defaultWorkspace
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.defaultWorkspacePath)
        }
    }

    /// Legacy single-folder accessor; reads/writes the first folder in the list.
    var workspacePath: String {
        get { workspaceFolders.first ?? Self.defaultWorkspace }
        set {
            var folders = workspaceFolders
            if folders.isEmpty {
                folders = [newValue]
            } else {
                folders[0] = newValue
            }
            workspaceFolders = folders
            if defaultWorkspacePath.isEmpty || !folders.contains(defaultWorkspacePath) {
                defaultWorkspacePath = newValue
            }
        }
    }

    func ensureDefaultWorkspaceIsValid() {
        let folders = workspaceFolders
        guard !folders.isEmpty else { return }
        if !folders.contains(defaultWorkspacePath) {
            defaultWorkspacePath = folders[0]
        }
    }

    func displayName(for path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? path : name
    }

    /// Removes the legacy external chat hotkey (F3 / Cursor / Open WebUI launcher).
    func removeExternalChatHotKeyIfNeeded() {
        let migrationKey = "externalChatHotKeyRemoved_v2"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        UserDefaults.standard.removeObject(forKey: "chatBoxHotKey")
        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    var notionTaskHotKey: HotKeyBinding {
        get {
            guard
                let data = UserDefaults.standard.data(forKey: Keys.notionTaskHotKey),
                let binding = try? JSONDecoder().decode(HotKeyBinding.self, from: data)
            else {
                return .notionTaskDefault
            }
            return binding
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Keys.notionTaskHotKey)
            }
        }
    }

    var newChatHotKey: HotKeyBinding {
        get {
            guard
                let data = UserDefaults.standard.data(forKey: Keys.newChatHotKey),
                let binding = try? JSONDecoder().decode(HotKeyBinding.self, from: data)
            else {
                return .newChatDefault
            }
            return binding
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Keys.newChatHotKey)
            }
        }
    }

    var snipAreaHotKey: HotKeyBinding {
        get {
            guard
                let data = UserDefaults.standard.data(forKey: Keys.snipAreaHotKey),
                let binding = try? JSONDecoder().decode(HotKeyBinding.self, from: data)
            else {
                return .snipAreaDefault
            }
            return binding
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Keys.snipAreaHotKey)
            }
        }
    }

    var snipWindowHotKey: HotKeyBinding {
        get {
            guard
                let data = UserDefaults.standard.data(forKey: Keys.snipWindowHotKey),
                let binding = try? JSONDecoder().decode(HotKeyBinding.self, from: data)
            else {
                return .snipWindowDefault
            }
            return binding
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Keys.snipWindowHotKey)
            }
        }
    }

    var snipFullScreenHotKey: HotKeyBinding {
        get {
            guard
                let data = UserDefaults.standard.data(forKey: Keys.snipFullScreenHotKey),
                let binding = try? JSONDecoder().decode(HotKeyBinding.self, from: data)
            else {
                return .snipFullScreenDefault
            }
            return binding
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Keys.snipFullScreenHotKey)
            }
        }
    }

    var snipRecordHotKey: HotKeyBinding {
        get {
            guard
                let data = UserDefaults.standard.data(forKey: Keys.snipRecordHotKey),
                let binding = try? JSONDecoder().decode(HotKeyBinding.self, from: data)
            else {
                return .recordAreaDefault
            }
            return binding
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Keys.snipRecordHotKey)
            }
        }
    }

    var snipTextHotKey: HotKeyBinding {
        get {
            guard
                let data = UserDefaults.standard.data(forKey: Keys.snipTextHotKey),
                let binding = try? JSONDecoder().decode(HotKeyBinding.self, from: data)
            else {
                return .snipTextDefault
            }
            return binding
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Keys.snipTextHotKey)
            }
        }
    }

    var brightnessDownHotKey: HotKeyBinding {
        get {
            guard
                let data = UserDefaults.standard.data(forKey: Keys.brightnessDownHotKey),
                let binding = try? JSONDecoder().decode(HotKeyBinding.self, from: data)
            else {
                return .brightnessDownDefault
            }
            return binding
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Keys.brightnessDownHotKey)
            }
        }
    }

    var brightnessUpHotKey: HotKeyBinding {
        get {
            guard
                let data = UserDefaults.standard.data(forKey: Keys.brightnessUpHotKey),
                let binding = try? JSONDecoder().decode(HotKeyBinding.self, from: data)
            else {
                return .brightnessUpDefault
            }
            return binding
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Keys.brightnessUpHotKey)
            }
        }
    }

    var warmthUpHotKey: HotKeyBinding {
        get {
            guard
                let data = UserDefaults.standard.data(forKey: Keys.warmthUpHotKey),
                let binding = try? JSONDecoder().decode(HotKeyBinding.self, from: data)
            else {
                return .warmthUpDefault
            }
            return binding
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Keys.warmthUpHotKey)
            }
        }
    }

    var warmthDownHotKey: HotKeyBinding {
        get {
            guard
                let data = UserDefaults.standard.data(forKey: Keys.warmthDownHotKey),
                let binding = try? JSONDecoder().decode(HotKeyBinding.self, from: data)
            else {
                return .warmthDownDefault
            }
            return binding
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Keys.warmthDownHotKey)
            }
        }
    }

    var sunScreenPresetHotKeys: [String: HotKeyBinding] {
        get {
            guard
                let data = UserDefaults.standard.data(forKey: Keys.sunScreenPresetHotKeys),
                let bindings = try? JSONDecoder().decode([String: HotKeyBinding].self, from: data)
            else {
                return [:]
            }
            return bindings
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Keys.sunScreenPresetHotKeys)
            }
        }
    }

    var notionDatabaseID: String {
        get {
            UserDefaults.standard.string(forKey: Keys.notionDatabaseID) ?? Self.defaultNotionDatabaseID
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.notionDatabaseID)
        }
    }

    var launchAtLogin: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.launchAtLogin) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.launchAtLogin) }
    }

    var responseDisplayMode: ResponseDisplayMode {
        get {
            guard
                let raw = UserDefaults.standard.string(forKey: Keys.responseDisplayMode),
                let mode = ResponseDisplayMode(rawValue: raw)
            else {
                return .inline
            }
            return mode
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Keys.responseDisplayMode)
        }
    }

    var usesFloatingChatBox: Bool {
        responseDisplayMode == .floatingChat
    }

    var chatBackend: ChatBackend {
        get {
            guard
                let raw = UserDefaults.standard.string(forKey: Keys.chatBackend),
                let backend = ChatBackend(rawValue: raw)
            else {
                return .openWebUI
            }
            return backend
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Keys.chatBackend)
        }
    }

    /// One-time migration: Open WebUI is the default chat backend.
    func migrateToOpenWebUIIfNeeded() {
        let migrationKey = "defaultedToOpenWebUI_v1"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        chatBackend = .openWebUI
        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    var usesOpenWebUI: Bool {
        chatBackend == .openWebUI
    }

    var openWebUIBaseURL: String {
        get {
            let stored = UserDefaults.standard.string(forKey: Keys.openWebUIBaseURL)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return stored?.isEmpty == false ? stored! : Self.defaultOpenWebUIBaseURL
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.openWebUIBaseURL)
        }
    }

    var normalizedOpenWebUIBaseURL: String {
        var url = openWebUIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while url.hasSuffix("/") {
            url.removeLast()
        }
        return url
    }

    var openWebUIModel: String {
        get {
            UserDefaults.standard.string(forKey: Keys.openWebUIModel) ?? Self.defaultOpenWebUIModel
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.openWebUIModel)
        }
    }

    var openWebUIActiveFolderID: String? {
        get {
            let stored = UserDefaults.standard.string(forKey: Keys.openWebUIActiveFolderID)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return stored?.isEmpty == false ? stored : nil
        }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: Keys.openWebUIActiveFolderID)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.openWebUIActiveFolderID)
            }
        }
    }

    var openWebUISyncChats: Bool {
        get {
            if UserDefaults.standard.object(forKey: Keys.openWebUISyncChats) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Keys.openWebUISyncChats)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.openWebUISyncChats)
        }
    }

    var cursorHandoffMode: CursorHandoffMode {
        get {
            guard
                let raw = UserDefaults.standard.string(forKey: Keys.cursorHandoffMode),
                let mode = CursorHandoffMode(rawValue: raw)
            else {
                return .formattedHistory
            }
            return mode
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Keys.cursorHandoffMode)
        }
    }

    var cursorHandoffTarget: CursorHandoffTarget {
        get {
            guard
                let raw = UserDefaults.standard.string(forKey: Keys.cursorHandoffTarget),
                let target = CursorHandoffTarget(rawValue: raw)
            else {
                return .agentsWindow
            }
            return target
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Keys.cursorHandoffTarget)
        }
    }

    var playResponseSound: Bool {
        get {
            if UserDefaults.standard.object(forKey: Keys.playResponseSound) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Keys.playResponseSound)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.playResponseSound)
        }
    }

    var responseCompletionSound: String {
        get {
            UserDefaults.standard.string(forKey: Keys.responseCompletionSound)
                ?? CompletionSound.defaultSound.rawValue
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.responseCompletionSound)
        }
    }

    var showMenuBarIcon: Bool {
        get {
            if UserDefaults.standard.object(forKey: Keys.showMenuBarIcon) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Keys.showMenuBarIcon)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.showMenuBarIcon)
        }
    }

    var permissionsAutomationDone: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.permissionsAutomationDone) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.permissionsAutomationDone) }
    }

    var permissionsLoginItemsDone: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.permissionsLoginItemsDone) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.permissionsLoginItemsDone) }
    }
}
