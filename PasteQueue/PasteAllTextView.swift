import SwiftUI

/// A short, in-popover confirmation screen. It keeps a record of the queue IDs last
/// presented to the user so a just-copied item cannot be pasted without appearing here.
struct PasteAllTextView: View {
    @ObservedObject var stack: PasteStack
    let onBack: () -> Void
    let onCancelPending: () -> Void
    let onPaste: (String, [UUID], @escaping (PasteAttemptResult) -> Void) -> Void

    private let preferenceStore: TextJoinPreferenceStoring
    @State private var choice: TextSeparatorChoice
    @State private var customSeparator: String
    @State private var displayedIDs: [UUID] = []
    @State private var isSubmitting = false
    @State private var failure: PasteAttemptResult?

    init(
        stack: PasteStack,
        preferenceStore: TextJoinPreferenceStoring = UserDefaultsTextJoinPreferenceStore(),
        onBack: @escaping () -> Void,
        onCancelPending: @escaping () -> Void,
        onPaste: @escaping (String, [UUID], @escaping (PasteAttemptResult) -> Void) -> Void
    ) {
        self.stack = stack
        self.preferenceStore = preferenceStore
        self.onBack = onBack
        self.onCancelPending = onCancelPending
        self.onPaste = onPaste
        let preference = preferenceStore.load()
        _choice = State(initialValue: preference.choice)
        _customSeparator = State(initialValue: preference.customSeparator)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Combine and Paste")
                .font(.headline)

            Picker("Separator", selection: $choice) {
                Text("New line").tag(TextSeparatorChoice.newline)
                Text("Blank line").tag(TextSeparatorChoice.blankLine)
                Text("Space").tag(TextSeparatorChoice.space)
                Text("Comma and space").tag(TextSeparatorChoice.commaSpace)
                Text("None").tag(TextSeparatorChoice.none)
                Text("Custom…").tag(TextSeparatorChoice.custom)
            }
            .pickerStyle(.menu)

            if choice == .custom {
                TextField("Custom separator", text: $customSeparator)
                    .textFieldStyle(.roundedBorder)
            }

            if allItemsAreText {
                Text("Preview")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(preview)
                    .font(.callout)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            } else {
                Text("All queued items must be text. Paste files and images separately.")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let failure {
                failureMessage(for: failure)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Back") {
                    if isSubmitting { onCancelPending() }
                    onBack()
                }
                Spacer()
                Button("Paste All", action: pasteAll)
                    .disabled(!canPaste)
            }
            .buttonStyle(.plain)
            .font(.callout)
        }
        .onAppear {
            if stack.isCollecting { stack.checkPasteboard() }
            displayedIDs = stack.queue.map(\.id)
        }
        .onChange(of: stack.queue) { queue in
            displayedIDs = queue.map(\.id)
        }
        .onDisappear {
            if isSubmitting { onCancelPending() }
        }
    }

    private var separator: String {
        choice.separator(custom: customSeparator)
    }

    private var allItemsAreText: Bool {
        stack.queue.allSatisfy {
            if case .text = $0.content { return true }
            return false
        }
    }

    private var canPaste: Bool {
        stack.queue.count >= 2 && allItemsAreText && !isSubmitting
            && (choice != .custom || !customSeparator.isEmpty)
    }

    private var preview: String {
        let fragments = stack.queue.prefix(3).compactMap { item -> String? in
            guard case .text(let text) = item.content else { return nil }
            return String(text.prefix(80))
        }
        let sample = fragments.joined(separator: separator)
        let wasShortened = stack.queue.count > 3 || sample.count > 200
            || stack.queue.prefix(3).contains {
                if case .text(let text) = $0.content { return text.count > 80 }
                return false
            }
        return String(sample.prefix(200)) + (wasShortened ? "…" : "")
    }

    private func pasteAll() {
        guard canPaste else { return }
        let expectedIDs = displayedIDs
        if stack.isCollecting { stack.checkPasteboard() }
        guard stack.queue.map(\.id) == expectedIDs else {
            displayedIDs = stack.queue.map(\.id)
            failure = .queueChanged
            return
        }

        let preference = TextJoinPreference(choice: choice, customSeparator: customSeparator)
        isSubmitting = true
        failure = nil
        onPaste(separator, expectedIDs) { result in
            isSubmitting = false
            if result == .commandPosted {
                preferenceStore.save(preference)
            } else if result == .containsNonText {
                failure = nil // the mixed-queue explanation is already visible above
            } else {
                failure = result
            }
        }
    }

    @ViewBuilder
    private func failureMessage(for result: PasteAttemptResult) -> some View {
        switch result {
        case .queueChanged:
            Text("The queue changed. Review the preview and try again.")
        case .containsNonText:
            Text("All queued items must be text. Paste files and images separately.")
        case .recipientUnavailable:
            Text("The target app is unavailable. Open the menu from the app you want to paste into.")
        case .accessibilityUnavailable:
            Text("Allow PasteQueue in Accessibility settings, then try again.")
        case .queueEmpty:
            Text("The queue is empty.")
        case .eventCreationFailed, .pasteboardWriteFailed, .requestInProgress:
            Text("Could not paste. The queue is unchanged; try again.")
        case .commandPosted:
            EmptyView()
        }
    }
}
