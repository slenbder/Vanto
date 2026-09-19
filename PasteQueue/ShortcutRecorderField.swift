import SwiftUI

/// One rebindable-shortcut row: label, key capsule, reset-to-default icon, and an inline
/// caption for either a duplicate rejection or a system-Copy/Paste/Cut conflict warning.
/// Owns the recording-mode local NSEvent monitor; all classification is delegated to the
/// pure functions in HotkeySpec.swift and all persisted state changes go through
/// HotkeyManager — this view holds no shortcut logic of its own.
struct ShortcutRecorderField: View {
    let action: ShortcutAction
    @ObservedObject var hotkeyManager: HotkeyManager
    /// Lifted to the parent so starting to record one row cancels any recording already in
    /// progress on the other row (single-flight across the two rows).
    @Binding var currentlyRecording: ShortcutAction?

    // Dynamic strings built at runtime (the duplicate/conflict captions) can't rely on
    // Text's automatic LocalizedStringKey extraction the way a literal like Text("Stopped")
    // can — they're routed through String(localized:locale:) instead, explicitly reading
    // this environment value so they still track the in-app language picker.
    @Environment(\.locale) private var locale

    @State private var duplicateMessage: String?
    @State private var monitor: Any?

    private static let escapeKeyCode: UInt16 = 53

    private var isRecording: Bool { currentlyRecording == action }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                actionLabel
                    .font(.callout)
                Spacer()
                keyCapsule
                resetButton
            }
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: currentlyRecording) { newValue in
            // Another row just started recording — this one loses the single-flight race.
            // Only tear down THIS row's own monitor; the hotkeyManager pause/interceptor
            // now belong to whichever row is actually active, so don't touch them here.
            if newValue != action, monitor != nil {
                stopRecording(releasingHotkeyManager: false)
            }
        }
        .onDisappear {
            if isRecording {
                stopRecording(releasingHotkeyManager: true)
            }
        }
    }

    @ViewBuilder
    private var keyCapsule: some View {
        Button {
            isRecording ? stopRecording(releasingHotkeyManager: true) : startRecording()
        } label: {
            // Branched (not Text(isRecording ? "Recording…" : displaySpec)) — that ternary
            // unifies on displaySpec's String type and silently skips the "Recording…"
            // literal's LocalizedStringKey extraction.
            Group {
                if isRecording {
                    Text("Recording…")
                } else {
                    Text(displaySpec)
                }
            }
                .font(.callout.monospaced())
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                // minWidth so a short spec like "⌃⌘C" still gets the same visual weight as a
                // longer one, instead of shrink-wrapping down to a cramped-looking sliver.
                .frame(minWidth: 54)
                // RoundedRectangle with a small fixed radius instead of Capsule (radius =
                // height/2, i.e. fully pill-shaped) — a noticeably squarer field per request.
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var resetButton: some View {
        Button {
            hotkeyManager.setOverride(nil, for: action)
            duplicateMessage = nil
        } label: {
            Image(systemName: "arrow.counterclockwise.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .disabled(hotkeyManager.overrides[action] == nil)
        .accessibilityLabel("Reset to default")
    }

    // Text literals directly per case (not Text(action.displayName), a runtime String)
    // so both branches go through Text's LocalizedStringKey initializer and get
    // auto-extracted into the catalog like every other static label in this app.
    @ViewBuilder
    private var actionLabel: some View {
        switch action {
        case .startStopCollecting:
            Text("Start/Stop Collecting")
        case .pasteNext:
            Text("Paste Next Item")
        }
    }

    private var displaySpec: String {
        hotkeyManager.effectiveSpec(for: action)?.displayString ?? action.defaultDisplayString
    }

    private var caption: String? {
        if let duplicateMessage { return duplicateMessage }
        if let spec = hotkeyManager.effectiveSpec(for: action), ShortcutRecording.isSystemCopyPasteCutConflict(spec) {
            return String(
                localized: "Matches macOS's own Copy/Paste/Cut — will also fire on every ordinary use elsewhere.",
                locale: locale
            )
        }
        return nil
    }

    private func startRecording() {
        duplicateMessage = nil
        currentlyRecording = action
        hotkeyManager.pauseForRecording()
        hotkeyManager.escapeRecordingInterceptor = { [self] in
            stopRecording(releasingHotkeyManager: true)
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            // Escape is owned entirely by AppDelegate's monitor + escapeRecordingInterceptor
            // above (see PasteQueueApp.swift) — NOT handled here, so there's a single
            // deterministic decision-maker instead of two independently-registered local
            // monitors racing over the same keydown.
            guard event.keyCode != Self.escapeKeyCode else { return event }
            handle(event)
            return nil // swallow every other key while recording
        }
    }

    private func handle(_ event: NSEvent) {
        let outcome = ShortcutRecording.classify(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags,
            isRepeat: event.isARepeat
        )
        guard case .captured(let spec) = outcome else { return }
        capture(spec)
    }

    private func capture(_ spec: HotkeySpec) {
        let otherAction: ShortcutAction = (action == .startStopCollecting) ? .pasteNext : .startStopCollecting
        if let otherSpec = hotkeyManager.effectiveSpec(for: otherAction), ShortcutRecording.isDuplicate(spec, otherSpec) {
            duplicateMessage = String(
                localized: "Already used by \(otherAction.displayName(locale: locale)).",
                locale: locale
            )
            stopRecording(releasingHotkeyManager: true)
            return
        }
        hotkeyManager.setOverride(spec, for: action)
        stopRecording(releasingHotkeyManager: true)
    }

    private func stopRecording(releasingHotkeyManager: Bool) {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        if currentlyRecording == action {
            currentlyRecording = nil
        }
        if releasingHotkeyManager {
            hotkeyManager.resumeAfterRecording()
            hotkeyManager.escapeRecordingInterceptor = nil
        }
    }
}
