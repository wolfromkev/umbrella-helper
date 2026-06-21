import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.showMenuBarIconKey) private var showMenuBarIcon = true
    @State private var workspacePath = AppSettings.shared.workspacePath
    @State private var launchAtLogin = AppSettings.shared.launchAtLogin
    @State private var hotKeyLabel = AppSettings.shared.hotKey.displayName
    @State private var chatBoxHotKeyLabel = AppSettings.shared.chatBoxHotKey.displayName
    @State private var responseDisplayMode = AppSettings.shared.responseDisplayMode

    var body: some View {
        VStack(spacing: 0) {
            Text("Settings")
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 10)

            Form {
                Section("Workspace") {
                    TextField("Cursor Chat folder", text: $workspacePath)
                        .onChange(of: workspacePath) { newValue in
                            AppSettings.shared.workspacePath = newValue
                        }
                }

                Section("Response") {
                    Picker("Show replies in", selection: $responseDisplayMode) {
                        ForEach(ResponseDisplayMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .onChange(of: responseDisplayMode) { newValue in
                        AppSettings.shared.responseDisplayMode = newValue
                    }

                    Text("Floating chat opens a separate window you can drag and keep open while you work. Inline mode shows replies above the input bar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Shortcuts") {
                    LabeledContent("Quick input") {
                        Text(hotKeyLabel)
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Chat box") {
                        Text(chatBoxHotKeyLabel)
                            .foregroundStyle(.secondary)
                    }
                    Text("Quick input defaults to ⌥Space. The chat box toggles with F5 and keeps your draft if you hide it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Menu Bar") {
                    Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
                        .onChange(of: showMenuBarIcon) { visible in
                            NotificationCenter.default.post(
                                name: .menuBarIconVisibilityChanged,
                                object: nil,
                                userInfo: ["visible": visible]
                            )
                        }

                    Text("When hidden, use ⌥Space and F5 as usual. Open Cursor Popup from Applications to reach Settings and restore the icon.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Startup") {
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { enabled in
                            LaunchAtLoginManager.setEnabled(enabled)
                        }
                }

                Section("About") {
                    Text("Cursor Popup sends questions to the Cursor agent in ask mode against your Cursor Chat workspace. Each popup opens a fresh chat; follow-ups continue that session.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .frame(width: 480, height: 500)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .popupPillShadow()
        .padding(24)
        .onAppear {
            launchAtLogin = LaunchAtLoginManager.isEnabled
            responseDisplayMode = AppSettings.shared.responseDisplayMode
        }
    }
}
