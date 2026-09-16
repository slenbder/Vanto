import AppKit
import Combine
import ServiceManagement
import os

private let logger = Logger(subsystem: "com.slenbder.pastequeue", category: "PasteStack")

enum LaunchAtLoginStatus {
    case enabled
    case requiresApproval
    case notRegistered
    case notFound
}

enum PasteAttemptResult: String, Equatable {
    case queueEmpty
    case accessibilityUnavailable
    case eventCreationFailed
    case pasteboardWriteFailed
    case commandPosted
}

protocol LaunchAtLoginProviding: AnyObject {
    var status: LaunchAtLoginStatus { get }
    var userIntendedEnabled: Bool { get }
    func register() throws
    func unregister() throws
    func setUserIntendedEnabled(_ enabled: Bool)
}

final class SystemLaunchAtLoginService: LaunchAtLoginProviding {
    private static let userEnabledKey = "userEnabledLaunchAtLogin"

    var status: LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered:
            return .notRegistered
        case .notFound:
            return .notFound
        @unknown default:
            return .notRegistered
        }
    }

    var userIntendedEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.userEnabledKey)
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    func setUserIntendedEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.userEnabledKey)
    }
}

/// Holds the FIFO queue of copied items and drives clipboard polling + synthetic paste.
/// FIFO by design: first thing you copy is the first thing that gets pasted.
final class PasteStack: ObservableObject {
    static let shared = PasteStack()

    typealias CleanupScheduler = (_ delay: TimeInterval, _ action: @escaping () -> Void) -> Void
    typealias CommandVEventPoster = () -> Void
    typealias CommandVEventFactory = () -> CommandVEventPoster?

    private enum StopReason: String {
        case manualToggle
        case queueDrained
    }

    /// Soft cap so a runaway collecting session can't grow the queue forever.
    static let maxQueueSize = 99

    @Published var queue: [QueuedClipboardItem] = []
    @Published var isCollecting: Bool = false
    @Published var isAccessibilityTrusted: Bool
    @Published var launchAtLoginEnabled: Bool
    @Published var launchAtLoginDesynced: Bool = false

    /// Fires when pasteNext() is invoked with nothing queued — a distinct signal (not a
    /// @Published state flag) because there's nothing to hold onto: the UI reaction is a
    /// one-shot icon flash, not persistent state that should survive a redraw.
    let flashRequested = PassthroughSubject<Void, Never>()

    private let pasteboard: PasteboardProviding
    private let clipboardFilesDirectory: URL
    private let commandVEventFactory: CommandVEventFactory
    private let scheduleCleanup: CleanupScheduler
    private let accessibilityTrustProvider: () -> Bool
    private let launchAtLoginService: LaunchAtLoginProviding
    private let automaticallyPolls: Bool
    private var pollTimer: Timer?
    private var lastChangeCount: Int

    // Own copies of captured files live here instead of referencing the original external
    // path. Some source paths (Photos.app derivatives, other sandboxed apps' containers)
    // only grant this process a read handle for the instant of the readObjects() call —
    // by the time pasteNext() hands the URL to another process via the pasteboard, the
    // sandbox extension needed for THAT process to read it can't be created, so
    // writeObjects() reports success while no bytes ever arrive. Copying the bytes into
    // our own Application Support directory at capture time sidesteps that entirely: the
    // file we hand out at paste time is one we actually own.
    private static var productionClipboardFilesDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("PasteQueue/ClipboardFiles", isDirectory: true)
    }

    convenience init() {
        self.init(
            pasteboard: NSPasteboard.general,
            clipboardFilesDirectory: Self.productionClipboardFilesDirectory,
            commandVEventFactory: Self.makeCommandVEventPoster,
            scheduleCleanup: { delay, action in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
            },
            accessibilityTrustProvider: { AXIsProcessTrusted() },
            launchAtLoginService: SystemLaunchAtLoginService(),
            automaticallyPolls: true
        )
    }

    init(
        pasteboard: PasteboardProviding,
        clipboardFilesDirectory: URL,
        commandVEventFactory: @escaping CommandVEventFactory,
        scheduleCleanup: @escaping CleanupScheduler,
        accessibilityTrustProvider: @escaping () -> Bool,
        launchAtLoginService: LaunchAtLoginProviding,
        automaticallyPolls: Bool
    ) {
        self.pasteboard = pasteboard
        self.clipboardFilesDirectory = clipboardFilesDirectory
        self.commandVEventFactory = commandVEventFactory
        self.scheduleCleanup = scheduleCleanup
        self.accessibilityTrustProvider = accessibilityTrustProvider
        self.launchAtLoginService = launchAtLoginService
        self.automaticallyPolls = automaticallyPolls
        self.lastChangeCount = pasteboard.changeCount
        self.isAccessibilityTrusted = accessibilityTrustProvider()
        self.launchAtLoginEnabled = launchAtLoginService.status == .enabled

        try? FileManager.default.createDirectory(at: clipboardFilesDirectory, withIntermediateDirectories: true)
        var excludable = clipboardFilesDirectory
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? excludable.setResourceValues(resourceValues)

        // A force-quit while the queue held file items leaves their copies orphaned on
        // disk with nothing left in memory to clean them up — sweep once at startup.
        cleanupOrphanedFiles(referencedBy: queue)
        refreshLaunchAtLoginStatus()
    }

    func refreshAccessibilityStatus() {
        isAccessibilityTrusted = accessibilityTrustProvider()
    }

    func refreshLaunchAtLoginStatus() {
        let status = launchAtLoginService.status
        let userIntendedEnabled = launchAtLoginService.userIntendedEnabled
        launchAtLoginEnabled = (status == .enabled)
        // .requiresApproval — переходное состояние сразу после успешного register(),
        // пока юзер не подтвердил Login Item в System Settings. Это НЕ рассинхрон —
        // рассинхрон это когда система/юзер вне приложения реально снял регистрацию
        // (.notRegistered) или бандл не найден (.notFound), при том что юзер сам
        // включал через приложение.
        launchAtLoginDesynced = userIntendedEnabled && (status == .notRegistered || status == .notFound)
        logger.debug("refreshLaunchAtLoginStatus status=\(String(describing: status), privacy: .public) userIntended=\(userIntendedEnabled, privacy: .public) desynced=\(self.launchAtLoginDesynced, privacy: .public)")
    }

    func toggleLaunchAtLogin() {
        do {
            if launchAtLoginEnabled {
                try launchAtLoginService.unregister()
                launchAtLoginService.setUserIntendedEnabled(false)
            } else {
                try launchAtLoginService.register()
                launchAtLoginService.setUserIntendedEnabled(true)
            }
        } catch {
            let nsError = error as NSError
            logger.debug("toggleLaunchAtLogin failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)")
        }
        refreshLaunchAtLoginStatus()
    }

    func toggleCollecting() {
        isCollecting.toggle()
        logger.debug("toggleCollecting isCollecting=\(self.isCollecting, privacy: .public) queue.count=\(self.queue.count, privacy: .public)")
        if isCollecting {
            // Don't pick up whatever was already on the clipboard before we started.
            lastChangeCount = pasteboard.changeCount
            startPolling()
        } else {
            stopCollecting(reason: .manualToggle)
        }
    }

    private func stopCollecting(reason: StopReason) {
        isCollecting = false
        stopPolling()
        logger.debug("stopCollecting reason=\(reason.rawValue, privacy: .public) queue.count=\(self.queue.count, privacy: .public)")
    }

    private func startPolling() {
        guard automaticallyPolls else { return }
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // Internal (not private) so tests can drive polling ticks directly instead of racing a real Timer.
    func checkPasteboard() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        let previousChangeCount = lastChangeCount
        lastChangeCount = pasteboard.changeCount
        logger.debug("checkPasteboard changeCount \(previousChangeCount, privacy: .public) -> \(self.lastChangeCount, privacy: .public)")

        guard queue.count < Self.maxQueueSize else { return }

        // File detection must run BEFORE image detection: copying a file in Finder (⌘C on a
        // file) puts a file URL (public.file-url) on the pasteboard, not raw image bytes. If we
        // ask readObjects(forClasses: [NSImage.self]) first, NSImage will still "succeed" against
        // that URL, but by falling back to the generic file-type icon instead of decoding the
        // file's actual content — so a copied jpg/png pastes back as a wrong, non-representative
        // icon bitmap. Catching the file URL first preserves the original bytes/format by
        // immediately copying the file into our own storage (see clipboardFilesDirectory) and
        // queuing a URL to that copy, not the external one.
        //
        // This intentionally catches ANY copied file, not just images — same raw pasteboard
        // mechanics apply whether it's a jpg or a txt/pdf/whatever else copied from Finder.
        //
        // The production pasteboard implementation keeps these reads backed by AppKit's
        // readObjects API; tests provide the same typed values without touching the system.
        let fileURLs = pasteboard.readFileURLs()

        if !fileURLs.isEmpty {
            // Multi-selection copies (Finder, Photos) hand back every selected file in one
            // array — queue each as its own item, in the order the pasteboard gave them
            // (that's Finder's/Photos' own selection order; not ours to second-guess).
            for fileURL in fileURLs {
                guard queue.count < Self.maxQueueSize else { break }
                let itemID = UUID()
                let originalFilename = fileURL.lastPathComponent
                guard let storedURL = copyToClipboardStorage(fileURL, itemID: itemID) else { continue }
                queue.append(QueuedClipboardItem(id: itemID, content: .file(url: storedURL, originalFilename: originalFilename)))
                logger.debug("queue append type=file queue.count=\(self.queue.count, privacy: .public)")
            }
        } else {
            let images = pasteboard.readImages()
            if !images.isEmpty {
                // Same reasoning as the file branch above: a single copy action can hand back
                // more than one image (e.g. multi-selection in an app that vends several image
                // representations at once) — queue each in the order the pasteboard gave them.
                for image in images {
                    guard queue.count < Self.maxQueueSize else { break }
                    queue.append(QueuedClipboardItem(content: .image(image)))
                    logger.debug("queue append type=image queue.count=\(self.queue.count, privacy: .public)")
                }
            } else if let str = pasteboard.string(forType: .string), !str.isEmpty {
                queue.append(QueuedClipboardItem(content: .text(str)))
                logger.debug("queue append type=text queue.count=\(self.queue.count, privacy: .public)")
            }
        }
    }

    /// Keeps the receiver-visible filename while isolating equal names in per-item folders.
    private func copyToClipboardStorage(_ sourceURL: URL, itemID: UUID) -> URL? {
        let itemDirectory = clipboardFilesDirectory.appendingPathComponent(itemID.uuidString, isDirectory: true)
        let destinationURL = itemDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: itemDirectory, withIntermediateDirectories: false)
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            // createDirectory may have succeeded before copyItem failed. The item owns this
            // UUID directory exclusively, so remove it without leaving an empty orphan.
            try? FileManager.default.removeItem(at: itemDirectory)
            let nsError = error as NSError
            logger.error("copyToClipboardStorage failed itemID=\(itemID.uuidString, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)")
            return nil
        }
    }

    private func deleteStoredFile(for item: QueuedClipboardItem) {
        guard case .file = item.content else { return }
        guard let storageEntry = ownedStorageEntry(for: item) else {
            logger.error("deleteStoredFile refused itemID=\(item.id.uuidString, privacy: .public) reason=ownershipValidationFailed")
            return
        }
        // New-format items remove their UUID directory. Legacy flat items remove only the
        // file itself. FileManager.removeItem handles both without leaving empty folders.
        try? FileManager.default.removeItem(at: storageEntry)
    }

    /// Resolves only the two layouts PasteQueue owns. Exact normalized parent equality and
    /// the queue item's UUID prevent a crafted path (including `..`) from escaping this
    /// instance's storage or deleting a sibling item.
    private func ownedStorageEntry(for item: QueuedClipboardItem) -> URL? {
        guard case .file(let url, _) = item.content else { return nil }
        let root = clipboardFilesDirectory.standardizedFileURL
        let file = url.standardizedFileURL
        let parent = file.deletingLastPathComponent()

        // Legacy layout: ClipboardFiles/<UUID>.<extension>
        if parent == root {
            guard file.deletingPathExtension().lastPathComponent == item.id.uuidString else { return nil }
            return file
        }

        // Current layout: ClipboardFiles/<UUID>/<original filename>
        guard parent.deletingLastPathComponent() == root,
              parent.lastPathComponent == item.id.uuidString else { return nil }
        return parent
    }

    private func cleanupOrphanedFiles(referencedBy queue: [QueuedClipboardItem]) {
        let referencedEntries = Set(queue.compactMap { ownedStorageEntry(for: $0)?.standardizedFileURL })
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: clipboardFilesDirectory,
            includingPropertiesForKeys: nil
        ) else { return }
        // Top-level contents can be legacy flat files or new per-item directories.
        for entry in contents where !referencedEntries.contains(entry.standardizedFileURL) {
            try? FileManager.default.removeItem(at: entry)
        }
    }

    @discardableResult
    func pasteNext() -> PasteAttemptResult {
        // Close the polling window for a just-copied item before choosing what to paste.
        // When collecting is off, paste remains a pure queue operation and never captures
        // whatever external app currently has on the system pasteboard.
        if isCollecting {
            checkPasteboard()
        }

        guard !queue.isEmpty else {
            flashRequested.send()
            return .queueEmpty
        }

        refreshAccessibilityStatus()
        guard isAccessibilityTrusted else {
            return .accessibilityUnavailable
        }

        guard let postCommandV = commandVEventFactory() else {
            return .eventCreationFailed
        }

        let item = queue.first!
        let pasteboardWriteSucceeded = pasteboard.replaceContents(with: item.content)
        // clearContents() can change the pasteboard even when the subsequent write fails.
        // Always sync to the resulting count so polling cannot treat our own attempt as Copy.
        lastChangeCount = pasteboard.changeCount
        guard pasteboardWriteSucceeded else {
            return .pasteboardWriteFailed
        }

        postCommandV()

        queue.removeFirst()
        logger.debug("queue removeFirst queue.count=\(self.queue.count, privacy: .public)")

        if queue.isEmpty {
            stopCollecting(reason: .queueDrained)
        }

        // Deleting the stored copy right here (synchronously) would race the synthetic ⌘V:
        // that keystroke is only just now being posted to the event tap, and the receiving
        // app resolves the pasteboard's file-url flavor on its own schedule afterward — an
        // immediate delete could remove the file before that read happens, reintroducing the
        // exact "reports success but nothing pastes" failure this on-disk copy exists to fix.
        // A short delay gives that read time to complete before cleanup runs.
        scheduleCleanup(2) { [weak self] in
            self?.deleteStoredFile(for: item)
        }
        return .commandPosted
    }

    func clear() {
        for item in queue {
            deleteStoredFile(for: item)
        }
        queue.removeAll()
        logger.debug("queue clear queue.count=\(self.queue.count, privacy: .public)")
    }

    /// Removes a single queue entry by its stable id, not by content match — two entries
    /// can carry equal content (e.g. the same text copied twice in a row), so matching by
    /// content could remove the wrong one of a pair of duplicates.
    func remove(id: UUID) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        let removed = queue.remove(at: index)
        deleteStoredFile(for: removed)
        logger.debug("queue remove queue.count=\(self.queue.count, privacy: .public)")
    }

    /// Reorders queue entries in place (array move, not remove+insert) so ids stay stable —
    /// matches List's onMove(perform:) signature directly.
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
        logger.debug("queue move queue.count=\(self.queue.count, privacy: .public)")
    }

    private static func makeCommandVEventPoster() -> CommandVEventPoster? {
        let src = CGEventSource(stateID: .hidSystemState)
        let vKeyCode = KeyboardLayoutTranslator.commandVKeyCode()

        guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: false) else {
            return nil
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        return {
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }
}
