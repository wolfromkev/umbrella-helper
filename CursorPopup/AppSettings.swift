import AppKit
import Carbon

struct HotKeyBinding: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let `default` = HotKeyBinding(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey)
    )

    static let chatBoxDefault = HotKeyBinding(
        keyCode: UInt32(kVK_F5),
        modifiers: 0
    )

    var displayName: String {
        var parts: [String] = []
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(keyCodeDisplayName)
        return parts.joined()
    }

    private var keyCodeDisplayName: String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_K: return "K"
        case kVK_F5: return "F5"
        default: return "Key \(keyCode)"
        }
    }
}

final class AppSettings {
    static let shared = AppSettings()

    static let showMenuBarIconKey = "showMenuBarIcon"

    private enum Keys {
        static let workspacePath = "workspacePath"
        static let hotKey = "hotKey"
        static let chatBoxHotKey = "chatBoxHotKey"
        static let launchAtLogin = "launchAtLogin"
        static let responseDisplayMode = "responseDisplayMode"
        static let showMenuBarIcon = showMenuBarIconKey
    }

    static let defaultWorkspace = "~/Cursor Chat"

    var workspacePath: String {
        get {
            UserDefaults.standard.string(forKey: Keys.workspacePath) ?? Self.defaultWorkspace
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.workspacePath)
        }
    }

    var hotKey: HotKeyBinding {
        get {
            guard
                let data = UserDefaults.standard.data(forKey: Keys.hotKey),
                let binding = try? JSONDecoder().decode(HotKeyBinding.self, from: data)
            else {
                return .default
            }
            return binding
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Keys.hotKey)
            }
        }
    }

    var chatBoxHotKey: HotKeyBinding {
        get {
            guard
                let data = UserDefaults.standard.data(forKey: Keys.chatBoxHotKey),
                let binding = try? JSONDecoder().decode(HotKeyBinding.self, from: data)
            else {
                return .chatBoxDefault
            }
            return binding
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Keys.chatBoxHotKey)
            }
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
}
