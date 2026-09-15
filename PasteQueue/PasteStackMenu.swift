import SwiftUI

struct PasteStackMenu: View {
    @ObservedObject var stack: PasteStack
    let minimumQueueListHeight: CGFloat
    let onPaste: () -> Void

    // Manual drag-to-reorder state. AppKit's List backing draws its own insertion-line +
    // lifted-ghost visuals during onMove drags with no public SwiftUI hook to suppress
    // them, so reordering is hand-rolled here via DragGesture instead of List(onMove:).
    @State private var draggingID: UUID?
    @State private var rawTranslation: CGFloat = 0
    @State private var swapCompensation: CGFloat = 0
    @State private var rowHeights: [UUID: CGFloat] = [:]

    private static let rowSpacing: CGFloat = 8
    private static let fallbackRowHeight: CGFloat = 32
    private static let maxListHeight: CGFloat = 230
    private static let dragCoordinateSpace = "queueRows"

    // The dragged row's live vertical offset: raw finger/cursor translation minus however
    // much has already been "spent" on live array swaps, so the row keeps tracking the
    // cursor smoothly across swaps instead of jumping by a row height each time.
    private var dragOffset: CGFloat {
        rawTranslation - swapCompensation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !stack.isAccessibilityTrusted {
                Button("⚠️ Accessibility required") {
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    NSWorkspace.shared.open(url)
                }
                .foregroundColor(.orange)
                Text("Hotkeys won't fire until this app is approved in System Settings.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Divider()
            }

            if stack.launchAtLoginDesynced {
                Button {
                    stack.toggleLaunchAtLogin()
                } label: {
                    Text("⚠️ Launch at Login disabled")
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundColor(.orange)
                Text("This was turned off in System Settings. Click to re-enable.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Divider()
            }

            // Recording state and queue count are two independent dimensions of state
            // (see PasteStack's type-level doc) — each gets its own view bound only to
            // its own source of truth, rather than being folded into one combined phrase
            // that would read as a single linear step ("Collecting… (N)" -> "Ready").
            HStack(spacing: 6) {
                recordingIndicator
                Text("·")
                    .foregroundColor(.secondary)
                queueCountLabel
            }
            // The dot separator is purely visual — as three separate elements VoiceOver
            // would stop on it and announce nothing, so it's folded into one label here.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(statusAccessibilityLabel)

            if effectiveListHeight > 0 {
                Divider()
                // A ScrollView asked for its *ideal* height (no incoming height proposal,
                // which is exactly what MenuBarExtra's .window style does when it measures
                // this content to size its popover) reports zero — `.frame(maxHeight:)`
                // alone can't rescue that because it only clamps an already-zero ideal
                // height. Giving the ScrollView an explicit, content-derived `height`
                // sidesteps the ideal-size measurement entirely: rows still show, and the
                // view shrinks for short queues while capping at 230 for long ones.
                ScrollView {
                    VStack(alignment: .leading, spacing: Self.rowSpacing) {
                        ForEach(Array(stack.queue.enumerated()), id: \.element.id) { index, entry in
                            queueRow(index: index, entry: entry)
                        }
                    }
                    .coordinateSpace(name: Self.dragCoordinateSpace)
                }
                .frame(height: effectiveListHeight)
            }

            Divider()

            // Bottom two rows, styled as plain text links rather than buttons —
            // row 1 is the frequently-used actions, row 2 is app-level utilities.
            HStack(spacing: 10) {
                Button(stack.isCollecting ? "Stop" : "Start") {
                    stack.toggleCollecting()
                }

                Button("Paste") {
                    onPaste()
                }
                .foregroundColor(stack.queue.isEmpty ? .secondary : .primary)
                .disabled(stack.queue.isEmpty)

                Button("Clear") {
                    stack.clear()
                }
                .foregroundColor(stack.queue.isEmpty ? .secondary : .primary)
                .disabled(stack.queue.isEmpty)
            }
            .buttonStyle(.plain)
            .font(.callout)

            Divider()

            HStack {
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

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
            .buttonStyle(.plain)
            .font(.callout)
        }
        .padding()
        .frame(width: 220)
        .onAppear {
            stack.refreshAccessibilityStatus()
            stack.refreshLaunchAtLoginStatus()
        }
        // rowHeights is keyed by item id and only ever grows via queueRow's onAppear —
        // prune entries whose item has left the queue (paste, delete, clear) so it doesn't
        // accumulate one stale entry per item ever queued over the app's lifetime.
        .onChange(of: stack.queue) { newQueue in
            let liveIDs = Set(newQueue.map(\.id))
            rowHeights = rowHeights.filter { liveIDs.contains($0.key) }
        }
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
        }
    }

    /// Bound ONLY to queue.count — never reads isCollecting, so the count reads as a fact
    /// about the queue, not as a step in whatever the recording state happens to be doing.
    @ViewBuilder
    private var queueCountLabel: some View {
        Text(stack.queue.count > 0 ? "\(stack.queue.count) in queue" : "Queue empty")
            .font(.subheadline)
            .foregroundColor(.secondary)
    }

    private var statusAccessibilityLabel: String {
        let recordingPart = stack.isCollecting ? "Recording" : "Stopped"
        let queuePart = stack.queue.count > 0 ? "\(stack.queue.count) in queue" : "queue empty"
        return "\(recordingPart), \(queuePart)"
    }

    @ViewBuilder
    private func queueRow(index: Int, entry: QueuedClipboardItem) -> some View {
        QueueRowView(index: index, entry: entry) {
            stack.remove(id: entry.id)
        }
        .background(
            GeometryReader { geo in
                Color.clear.onAppear { rowHeights[entry.id] = geo.size.height }
            }
        )
        .offset(y: draggingID == entry.id ? dragOffset : 0)
        .zIndex(draggingID == entry.id ? 1 : 0)
        // Dragging the row body itself reorders it — no separate drag handle.
        // minimumDistance keeps a plain click on the delete "x" from being
        // swallowed as a drag start: the gesture only takes over once the
        // cursor has actually moved, so a stationary tap reaches the Button.
        .gesture(
            // Named coordinate space anchored on the VStack (not this row) is deliberate:
            // this row also carries .offset(y: dragOffset), derived from this same
            // gesture's translation. The default .local space measures translation
            // relative to the row's OWN frame, which is itself moving because of that
            // offset — a feedback loop that made translation drift once a live swap
            // animated the row. .global avoids the loop but isn't reliably recognized
            // for gestures nested inside a ScrollView; a named space on a stable ancestor
            // gets the same stability without that problem.
            DragGesture(minimumDistance: 10, coordinateSpace: .named(Self.dragCoordinateSpace))
                .onChanged { value in
                    if draggingID != entry.id {
                        draggingID = entry.id
                        swapCompensation = 0
                    }
                    rawTranslation = value.translation.height
                    attemptSwap(entry: entry)
                }
                .onEnded { _ in
                    // The array is already in its final order by this point
                    // (swaps happen live in attemptSwap) — releasing just
                    // animates away whatever sub-row-height offset is left.
                    withAnimation(.default) {
                        rawTranslation = 0
                        swapCompensation = 0
                        draggingID = nil
                    }
                }
        )
    }

    private var effectiveListHeight: CGFloat {
        max(Self.listHeight(for: stack.queue), minimumQueueListHeight)
    }

    static func listHeight(for queue: [QueuedClipboardItem]) -> CGFloat {
        min(queue.reduce(CGFloat(0)) { $0 + estimatedRowHeight(for: $1) }, maxListHeight)
    }

    // ~8 rows' worth of height: text rows run ~20pt (`.callout`) + row padding + 8pt
    // inter-row spacing ≈ 32pt/row, image/file rows are taller (28pt frame ≈ 38pt/row).
    // Capped at maxListHeight so a long queue scrolls instead of pushing the buttons below off
    // the bottom of the popover.
    private static func estimatedRowHeight(for entry: QueuedClipboardItem) -> CGFloat {
        switch entry.content {
        case .text:
            return 32
        case .image, .file:
            return 38
        }
    }

    // Swaps the dragged row past a neighbor once its (live, offset-adjusted) position has
    // crossed that neighbor's midpoint — matching Finder/Notes/Reminders' reorder feel.
    // Runs in a loop so a single fast drag can cross more than one row in one callback.
    private func attemptSwap(entry: QueuedClipboardItem) {
        while true {
            guard let currentIndex = stack.queue.firstIndex(where: { $0.id == entry.id }) else { return }
            let myHeight = rowHeights[entry.id] ?? Self.fallbackRowHeight
            let offset = dragOffset

            if offset > 0, currentIndex < stack.queue.count - 1 {
                let nextEntry = stack.queue[currentIndex + 1]
                let nextHeight = rowHeights[nextEntry.id] ?? Self.fallbackRowHeight
                let threshold = myHeight / 2 + Self.rowSpacing + nextHeight / 2
                if offset > threshold {
                    withAnimation(.default) {
                        stack.move(fromOffsets: IndexSet(integer: currentIndex), toOffset: currentIndex + 2)
                    }
                    swapCompensation += nextHeight + Self.rowSpacing
                    continue
                }
            }

            if offset < 0, currentIndex > 0 {
                let prevEntry = stack.queue[currentIndex - 1]
                let prevHeight = rowHeights[prevEntry.id] ?? Self.fallbackRowHeight
                let threshold = myHeight / 2 + Self.rowSpacing + prevHeight / 2
                if -offset > threshold {
                    withAnimation(.default) {
                        stack.move(fromOffsets: IndexSet(integer: currentIndex), toOffset: currentIndex - 1)
                    }
                    swapCompensation -= prevHeight + Self.rowSpacing
                    continue
                }
            }

            break
        }
    }
}

/// A single row in the queue list: the position number, the item's content preview,
/// and a delete button that only shows up while the row is hovered.
private struct QueueRowView: View {
    let index: Int
    let entry: QueuedClipboardItem
    let onDelete: () -> Void

    @State private var isHovering = false
    // .disabled(!isHovering) alone makes the delete button permanently unreachable for
    // VoiceOver, which never hovers with a pointer — this tracks VoiceOver's on/off state
    // (there's no AppKit notification specific to VoiceOver; the general accessibility
    // display-options notification is the standard way to observe it) so the button stays
    // enabled for VoiceOver regardless of hover.
    @State private var isVoiceOverRunning = NSWorkspace.shared.isVoiceOverEnabled

    var body: some View {
        HStack {
            Group {
                Text("\(index + 1).")
                    .font(.callout)
                switch entry.content {
                case .text(let str):
                    Text(str.prefix(40))
                        .font(.callout)
                        .lineLimit(1)
                case .image(let nsImage):
                    Image(nsImage: nsImage)
                        .resizable()
                        .frame(width: 28, height: 28)
                case .file(let url, let originalFilename):
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: 28, height: 28)
                    Text(originalFilename)
                        .font(.callout)
                        .lineLimit(1)
                }
            }
            // Scoped to just the number + content, not the whole row, so the delete
            // button below stays its own independently-focusable element.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(contentAccessibilityLabel)

            Spacer(minLength: 4)

            // Always present (never conditionally inserted) so the row's height stays
            // constant whether or not the button is visible — toggling it in and out of
            // the view tree instead made hovered rows grow taller than their neighbors,
            // which shoved every row below it down.
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            // opacity 0 turned out to not just be a visual affordance — confirmed live that
            // VoiceOver's linear Next-Item navigation skips a zero-opacity element outright,
            // so leaving it invisible-but-enabled during VoiceOver still made it unreachable.
            .opacity(isHovering || isVoiceOverRunning ? 1 : 0)
            .disabled(!isHovering && !isVoiceOverRunning)
            .accessibilityLabel("Delete item \(index + 1)")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .padding(.trailing, 8)
        .background(
            Capsule()
                .fill(Color.primary.opacity(isHovering ? 0.08 : 0))
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .onReceive(
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
        ) { _ in
            isVoiceOverRunning = NSWorkspace.shared.isVoiceOverEnabled
        }
    }

    private var contentAccessibilityLabel: String {
        switch entry.content {
        case .text(let str):
            return "Item \(index + 1): text, \(str.prefix(40))"
        case .image:
            return "Item \(index + 1): image"
        case .file(_, let originalFilename):
            return "Item \(index + 1): file, \(originalFilename)"
        }
    }
}

#Preview("Short queue") {
    let stack = PasteStack()
    stack.queue = [
        QueuedClipboardItem(content: .text("first clipboard item")),
        QueuedClipboardItem(content: .text("second")),
        QueuedClipboardItem(content: .text("third")),
    ]
    stack.isCollecting = true
    return PasteStackMenu(stack: stack, minimumQueueListHeight: PasteStackMenu.listHeight(for: stack.queue)) {
        stack.pasteNext()
    }
}

#Preview("Long queue") {
    let stack = PasteStack()
    stack.queue = (1...25).map { QueuedClipboardItem(content: .text("clipboard item number \($0)")) }
    stack.isCollecting = true
    return PasteStackMenu(stack: stack, minimumQueueListHeight: PasteStackMenu.listHeight(for: stack.queue)) {
        stack.pasteNext()
    }
}
