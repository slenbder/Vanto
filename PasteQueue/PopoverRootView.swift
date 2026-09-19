import SwiftUI

/// True root of the popover content. Owns which of the two screens is showing, the shared
/// status row above both of them, the popover's outer padding/width (moved here from
/// PasteStackMenu, which is now unpadded per-screen content), and the language override
/// applied to the whole subtree via .environment(\.locale:).
///
/// A fresh instance of this view is created every time the popover opens (see AppDelegate's
/// makePopoverContentController) — screen deliberately always starts at .queue, matching
/// every other piece of this popover's state (drag state, recording state, …) already
/// resetting on reopen.
struct PopoverRootView: View {
    @ObservedObject var stack: PasteStack
    @ObservedObject var hotkeyManager: HotkeyManager
    @ObservedObject var languageStore: LanguagePreferenceStore
    let minimumQueueListHeight: CGFloat
    let onPaste: () -> Void

    @State private var screen: PopoverScreen = .queue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PopoverStatusRow(stack: stack, screen: $screen)

            switch screen {
            case .queue:
                PasteStackMenu(stack: stack, minimumQueueListHeight: minimumQueueListHeight, onPaste: onPaste)
            case .settings:
                SettingsMenu(stack: stack, hotkeyManager: hotkeyManager, languageStore: languageStore)
            }
        }
        .padding()
        // Localizable.xcstrings' ru/es/de shortcut-row labels were shortened (dropped the
        // trailing object noun — "elemento"/"Element"/"элемент" — leaning on the row's own
        // context to carry it) to avoid paying a width tax for the longest string in the
        // longest language. After that, the binding constraint is the RU status header
        // ("Остановлено · Очередь пуста" ≈ 230pt content width, measured against NSFont
        // directly) rather than the shortcut rows. 270 covers every shipped locale
        // (en/ru/es/de) on both the header and the two shortcut rows with a small margin.
        .frame(width: 270)
        .environment(\.locale, resolvedLocale)
    }

    private var resolvedLocale: Locale {
        guard let code = languageStore.preferredLanguageCode else { return .autoupdatingCurrent }
        return Locale(identifier: code)
    }
}
