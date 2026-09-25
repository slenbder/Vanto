import SwiftUI

/// Which of the popover's two screens is currently showing.
enum PopoverScreen {
    case queue
    case settings
}

/// Shared header across both popover screens: recording indicator and queue count on
/// one line, plus the trailing gearshape button that switches to
/// Settings. The status text and the gear button are deliberately separate accessibility
/// elements — folding the gear into the same `.accessibilityElement(children: .ignore)`
/// group as the status text would make it permanently unreachable to VoiceOver.
struct PopoverStatusRow: View {
    @ObservedObject var stack: PasteStack
    @Binding var screen: PopoverScreen
    let displayedQueueCount: String

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                recordingIndicator
                queueCountLabel
            }
            // Keep the two visual labels as one announcement for VoiceOver.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(statusAccessibilityText)

            Spacer(minLength: 8)

            Button {
                screen = (screen == .queue) ? .settings : .queue
            } label: {
                Image(systemName: screen == .queue ? "gearshape" : "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(gearAccessibilityText)
        }
    }

    // Ternary of two Text literals (not a String ternary passed to .accessibilityLabel)
    // so both branches unambiguously resolve through Text's LocalizedStringKey initializer.
    private var gearAccessibilityText: Text {
        screen == .queue ? Text("Settings") : Text("Close Settings")
    }

    /// Bound ONLY to isCollecting — never reads queue.count, so recording state can never
    /// be inferred from (or confused with) how many items happen to be queued.
    @ViewBuilder
    private var recordingIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(stack.isCollecting ? Color.red : Color.secondary)
                .frame(width: 8, height: 8)
            Text(stack.isCollecting ? "Recording" : "Stopped")
                .font(.headline)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    /// Localized by the root view, which inserts the German visual line break.
    /// The HStack centers the two-line block beside the unchanged recording indicator;
    /// both lines start at the same leading edge.
    private var queueCountLabel: some View {
        Text(verbatim: displayedQueueCount)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: true, vertical: true)
    }

    /// Built from Text (not a plain String) so it stays environment-locale-aware — a plain
    /// String built via interpolation would need an explicit Locale threaded through by
    /// hand (see AppDelegate's AppKit-side accessibility labels, which have no SwiftUI
    /// environment and do need that).
    private var statusAccessibilityText: Text {
        let recordingPart: Text = stack.isCollecting ? Text("Recording") : Text("Stopped")
        let queuePart: Text = stack.queue.count > 0
            ? Text("\(stack.queue.count) items in queue")
            : Text("queue empty")
        return recordingPart + Text(", ") + queuePart
    }
}
