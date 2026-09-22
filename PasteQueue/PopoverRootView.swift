import AppKit
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
    let onPasteAll: (String, [UUID], @escaping (PasteAttemptResult) -> Void) -> Void
    let onCancelPasteAll: () -> Void

    @State private var screen: PopoverScreen = .queue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PopoverStatusRow(
                stack: stack,
                screen: $screen,
                displayedQueueCount: displayedQueueCount
            )
            Divider()

            switch screen {
            case .queue:
                PasteStackMenu(
                    stack: stack,
                    minimumQueueListHeight: minimumQueueListHeight,
                    onPaste: onPaste,
                    onPasteAll: onPasteAll,
                    onCancelPasteAll: onCancelPasteAll
                )
            case .settings:
                SettingsMenu(stack: stack, hotkeyManager: hotkeyManager, languageStore: languageStore)
            }
        }
        .padding()
        .frame(width: popoverWidth)
        .environment(\.locale, resolvedLocale)
    }

    /// Grow only when the localized status needs more room than the ordinary
    /// 270-point popover. The queue and Settings share this width.
    private var popoverWidth: CGFloat {
        let locale = resolvedLocale
        let bundle = AppLocalization.bundle(for: languageStore.preferredLanguageCode)
        let status = stack.isCollecting
            ? String(localized: "Recording", bundle: bundle, locale: locale)
            : String(localized: "Stopped", bundle: bundle, locale: locale)
        let statusWidth = (status as NSString).size(
            withAttributes: [.font: NSFont.preferredFont(forTextStyle: .headline)]
        ).width
        let countFont = NSFont.preferredFont(forTextStyle: .subheadline)
        let countWidth = displayedQueueCount.split(separator: "\n").map {
            ($0 as NSString).size(withAttributes: [.font: countFont]).width
        }.max() ?? 0
        // Dot + its gap, label gap, gear + its gap, outer padding, and a little
        // allowance for SwiftUI/AppKit text metrics and fractional point rounding.
        return max(270, ceil(statusWidth + countWidth + 8 + 4 + 8 + 8 + 18 + 32 + 12))
    }

    private var displayedQueueCount: String {
        let locale = resolvedLocale
        let bundle = AppLocalization.bundle(for: languageStore.preferredLanguageCode)
        let count = stack.queue.isEmpty
            ? String(localized: "Queue empty", bundle: bundle, locale: locale)
            : String(localized: "\(stack.queue.count) items in queue", bundle: bundle, locale: locale)

        // Only the visual header is split; the accessibility announcement remains
        // the ordinary, uninterrupted localized sentence.
        guard !stack.queue.isEmpty,
              locale.language.languageCode?.identifier == "de",
              let lastSpace = count.lastIndex(of: " ") else { return count }
        return String(count[..<lastSpace]) + "\n" + String(count[count.index(after: lastSpace)...])
    }

    private var resolvedLocale: Locale {
        guard let code = languageStore.preferredLanguageCode else { return .autoupdatingCurrent }
        return Locale(identifier: code)
    }
}
