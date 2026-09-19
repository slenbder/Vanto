import SwiftUI

/// Settings screen: the two rebindable-shortcut rows, language picker, Launch at Login
/// (moved here from the queue screen), the website link, and the version/build caption.
struct SettingsMenu: View {
    @ObservedObject var stack: PasteStack
    @ObservedObject var hotkeyManager: HotkeyManager
    @ObservedObject var languageStore: LanguagePreferenceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Single-flight recording state (starting to record one row cancels the other)
            // lives on hotkeyManager.recordingAction now — both rows observe the same
            // @ObservedObject, so there's no separate @State to thread through here anymore.
            VStack(alignment: .leading, spacing: 8) {
                ShortcutRecorderField(action: .startStopCollecting, hotkeyManager: hotkeyManager)
                ShortcutRecorderField(action: .pasteNext, hotkeyManager: hotkeyManager)
            }

            Divider()

            languagePicker

            Divider()

            launchAtLoginSection

            Divider()

            // Website + version share the bottom row now — version anchored to the trailing
            // edge instead of sitting on its own line below.
            HStack {
                Button {
                    // Placeholder destination — the real marketing/contact site, swap freely.
                    if let url = URL(string: "https://pastequeue-first-look.slenbder.chatgpt.site") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text("Visit our website")
                }
                .buttonStyle(.plain)
                .font(.callout)

                Spacer()

                Text("Version \(appVersion) (\(appBuild))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            stack.refreshLaunchAtLoginStatus()
        }
    }

    @ViewBuilder
    private var languagePicker: some View {
        Picker("Language", selection: languageSelection) {
            Text("System").tag(nil as String?)
            ForEach(SupportedLanguage.allCases) { language in
                Text(language.nativeName).tag(language.rawValue as String?)
            }
        }
        .pickerStyle(.menu)
        .font(.callout)
    }

    private var languageSelection: Binding<String?> {
        Binding(
            get: { languageStore.preferredLanguageCode },
            set: { languageStore.setPreferredLanguageCode($0) }
        )
    }

    @ViewBuilder
    private var launchAtLoginSection: some View {
        if stack.launchAtLoginDesynced {
            Button {
                stack.toggleLaunchAtLogin()
            } label: {
                Text("⚠️ Launch at Login disabled")
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)
            .foregroundColor(.orange)
            Text("This was turned off in System Settings. Click to re-enable.")
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            Button {
                stack.toggleLaunchAtLogin()
            } label: {
                HStack(spacing: 4) {
                    Text("Launch at Login")
                    if stack.launchAtLoginEnabled {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .buttonStyle(.plain)
            .font(.callout)
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}
