import SwiftUI

/// One rebindable-shortcut row: label, key capsule, reset-to-default icon, and an inline
/// caption for either a duplicate rejection or a system-Copy/Paste/Cut conflict warning.
/// Owns the recording-mode local NSEvent monitor; all classification is delegated to the
/// pure functions in HotkeySpec.swift and all persisted state changes go through
/// HotkeyManager — this view holds no shortcut logic of its own.
struct ShortcutRecorderField: View {
    let action: ShortcutAction
    @ObservedObject var hotkeyManager: HotkeyManager
    let languageCode: String?

    // Dynamic strings built at runtime (the duplicate/conflict captions) can't rely on
    // Text's automatic LocalizedStringKey extraction the way a literal like Text("Stopped")
    // can — they are rebuilt with the selected catalog and environment locale so they
    // track changes in the in-app language picker.
    @Environment(\.locale) private var locale

    private var localizedBundle: Bundle { AppLocalization.bundle(for: languageCode) }

    @State private var duplicateAction: ShortcutAction?
    @State private var monitor: Any?

    // "Is anything being recorded, and is it THIS row" now lives on hotkeyManager
    // (recordingAction) — single-flight across rows falls out of both rows observing the
    // same @Published property, with no separate @State/@Binding to keep in sync.
    private var isRecording: Bool { hotkeyManager.recordingAction == action }

    var body: some View {
        // Resolved once per body evaluation and handed to both the capsule and the caption —
        // effectiveSpec's un-overridden path does a live keyboard-layout scan, so computing
        // it twice per render (once for the label, once for the conflict caption) doubled
        // that cost for no reason.
        let currentSpec = hotkeyManager.effectiveSpec(for: action)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                actionText
                    .font(.callout)
                Spacer()
                keyCapsule(currentSpec: currentSpec)
                resetButton
            }
            if let caption = caption(for: currentSpec) {
                Text(caption)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: hotkeyManager.recordingAction) { newValue in
            // Another row just started recording — this one loses the single-flight race.
            // Only tear down THIS row's own monitor; the hotkeyManager pause/handler
            // now belong to whichever row is actually active, so don't touch them here.
            if newValue != action, monitor != nil {
                stopRecording(releasingHotkeyManager: false)
            }
        }
        .onDisappear {
            // The popover delegate may clear recordingAction before this callback runs.
            // Always remove this view's monitor, even when it no longer owns the pause.
            if monitor != nil {
                stopRecording(releasingHotkeyManager: isRecording)
            }
        }
    }

    @ViewBuilder
    private func keyCapsule(currentSpec: HotkeySpec?) -> some View {
        Button {
            isRecording ? stopRecording(releasingHotkeyManager: true) : startRecording()
        } label: {
            // Branched (not a ternary unifying on one Text) — that ternary would silently
            // skip the "Recording…" literal's LocalizedStringKey extraction.
            Group {
                if isRecording {
                    Text("Recording…")
                } else {
                    Text(currentSpec?.displayString ?? action.defaultDisplayString)
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
        .accessibilityLabel(actionText)
        .accessibilityValue(isRecording ? Text("Recording…") : Text(currentSpec?.displayString ?? action.defaultDisplayString))
    }

    @ViewBuilder
    private var resetButton: some View {
        Button {
            hotkeyManager.setOverride(nil, for: action)
            duplicateAction = nil
        } label: {
            Image(systemName: "arrow.counterclockwise.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .disabled(hotkeyManager.overrides[action] == nil)
        .accessibilityLabel(Text("Reset to default") + Text(", ") + actionText)
    }

    // Text literals directly per case (not Text(action.displayName), a runtime String)
    // so both branches go through Text's LocalizedStringKey initializer and get
    // auto-extracted into the catalog like every other static label in this app.
    private var actionText: Text {
        switch action {
        case .startStopCollecting:
            Text("Start/Stop Collecting")
        case .pasteNext:
            Text("Paste Next Item")
        }
    }

    private func caption(for currentSpec: HotkeySpec?) -> String? {
        if let duplicateAction {
            return String(
                localized: "Already used by \(duplicateAction.displayName(locale: locale, bundle: localizedBundle)).",
                bundle: localizedBundle,
                locale: locale
            )
        }
        if let overridingAction = hotkeyManager.overridingAction(forDefault: action) {
            return String(
                localized: "Already used by \(overridingAction.displayName(locale: locale, bundle: localizedBundle)).",
                bundle: localizedBundle,
                locale: locale
            )
        }
        if let currentSpec, ShortcutRecording.isSystemCopyPasteCutConflict(currentSpec) {
            return String(
                localized: "Matches macOS's own Copy/Paste/Cut — will also fire on every ordinary use elsewhere.",
                bundle: localizedBundle,
                locale: locale
            )
        }
        return nil
    }

    private func startRecording() {
        duplicateAction = nil
        hotkeyManager.pauseForRecording(action: action)
        hotkeyManager.cancelRecordingHandler = { [self] in
            stopRecording(releasingHotkeyManager: true)
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            // Escape is owned entirely by AppDelegate's monitor + cancelRecordingHandler
            // above (see PasteQueueApp.swift) — NOT handled here, so there's a single
            // deterministic decision-maker instead of two independently-registered local
            // monitors racing over the same keydown. This guard still matters regardless of
            // that ordering: without it, the swallow-everything branch below would eat
            // Escape itself if this monitor ever saw it before AppDelegate's did.
            guard event.keyCode != ShortcutRecording.escapeKeyCode else { return event }
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
        for otherAction in ShortcutAction.allCases where otherAction != action {
            guard let otherSpec = hotkeyManager.effectiveSpec(for: otherAction),
                  ShortcutRecording.isDuplicate(spec, otherSpec) else { continue }
            duplicateAction = otherAction
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
        if releasingHotkeyManager {
            hotkeyManager.resumeAfterRecording()
            hotkeyManager.cancelRecordingHandler = nil
        }
    }
}
