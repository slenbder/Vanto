import SwiftUI
import AppKit
import Combine
import os

private let uiLogger = Logger(subsystem: "com.slenbder.pastequeue", category: "UI")

enum AppRuntime {
    static var isRunningTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }
}

@main
struct PasteQueueApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // All UI (status item, count label, popover) is owned by AppDelegate via plain
        // AppKit — see the comment there for why. This Settings scene only exists
        // because `App` requires at least one Scene; it never becomes visible.
        Settings {
            EmptyView()
        }
    }
}

// NSTextField/NSTextFieldCell rendering was found to not honor .center alignment
// against a manually-assigned frame the way expected here: two rounds of tuning the
// frame's width and Y offset (verified via logging to actually take effect at the
// exact numbers intended, with the build confirmed non-stale) produced zero visible
// change in where the digit rendered. Rather than keep guessing at NSTextFieldCell's
// internal insets/baseline logic, this draws the string directly and centers it
// against its own measured size — nothing else participates in laying it out.
final class CenteredLabelView: NSView {
    var text: String = "" { didSet { needsDisplay = true } }
    var textColor: NSColor = .labelColor { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let size = (text as NSString).size(withAttributes: attrs)
        let rect = NSRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
        (text as NSString).draw(in: rect, withAttributes: attrs)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var countLabel: CenteredLabelView?
    private var popover: NSPopover?
    private var queueSubscription: AnyCancellable?
    private var flashSubscription: AnyCancellable?
    private var accessSubscription: AnyCancellable?
    private var trialExpirationTimer: Timer?
    private var updateController: AppUpdateController?
    private var pasteRecipientApplication: NSRunningApplication?
    private var isRestoringFocusForPaste = false
    private var activationObserver: NSObjectProtocol?
    private var activationTimeout: DispatchWorkItem?
    private var pendingBulkPasteID: UUID?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var escapeKeyMonitor: Any?
    private var isClosingPopover = false
    private var accessController: LicenseAccessController?

    private enum PasteRequestSource: String {
        case button
        case hotkey
    }

    private enum PasteRequestKind {
        case next
        case allText(separator: String, expectedIDs: [UUID])
    }

    private enum PopoverCloseReason: String {
        case statusItem
        case outsideClick
        case escape
        case queueDrained
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // PasteQueueTests run inside this executable via TEST_HOST. Return before touching
        // either singleton so the host cannot monitor keys, prompt for Accessibility, poll
        // the system pasteboard, sweep production file storage, or query login-item state.
        guard !AppRuntime.isRunningTests else { return }

        // Hide the Dock icon — this is a menu-bar-only utility.
        NSApp.setActivationPolicy(.accessory)
        updateController = AppUpdateController()
        let accessController = makeAccessController()
        self.accessController = accessController
        accessSubscription = accessController.$state.sink { [weak self] state in
            Task { @MainActor [weak self] in
                self?.handleAccessState(state)
            }
        }
        HotkeyManager.shared.start(
            toggleCollectingHandler: { [weak self] in
                self?.requestToggleCollecting()
            },
            pasteRequestHandler: { [weak self] in
                self?.requestPaste(source: .hotkey)
            }
        )
        PasteStack.shared.refreshLaunchAtLoginStatus()
        setUpStatusItem()
        Task {
            await accessController.validateIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        trialExpirationTimer?.invalidate()
        removePopoverEventMonitors()
    }

    // MenuBarExtra's label is hosted by the system status item, but it gives no
    // access to the underlying NSStatusBarButton — which is what's needed to read
    // `effectiveAppearance` for the *button itself* (the documented, KVO-observable
    // signal AppKit uses to color a status item, driven by what's actually behind
    // the menu bar — e.g. desktop wallpaper — not `NSApplication.effectiveAppearance`,
    // which only reflects the systemwide Light/Dark setting and can disagree with it).
    // Managing the status item directly in AppKit means the button's `image.isTemplate`
    // is colored by the system automatically, correctly, with no observer needed at all.
    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = item.button else { return }

        // Both "menuBarIcon" (idle, with the drawn-in lines) and "menuBarIconFrame"
        // (same outer silhouette, hollow — used once the queue holds something so the
        // count label has room to sit inside it) share an identical 18x18 canvas and
        // outer contour, so swapping between them never changes the icon's apparent
        // size or position.
        let idleIcon = NSImage(named: "menuBarIcon")
        idleIcon?.size = NSSize(width: 18, height: 18)
        idleIcon?.isTemplate = true

        let activeIcon = NSImage(named: "menuBarIconFrame")
        activeIcon?.size = NSSize(width: 18, height: 18)
        activeIcon?.isTemplate = true

        button.image = idleIcon
        button.target = self
        button.action = #selector(statusItemClicked)

        // The count label is a plain view layered on top of the button, entirely
        // outside the template image — same reasoning as the old badge it replaces:
        // a template NSImage is recolored as a flat mask by the system, so text baked
        // into the bitmap couldn't be styled (e.g. turn red at the 99 cap) independent
        // of that recoloring. Framed to a safe zone centered inside the button's real
        // bounds (an NSStatusBarButton measures 22x22 in practice, not the 18x18 the
        // icon art itself is drawn at) — 16pt wide so two-digit counts like "10" fit
        // without clipping, which the earlier 14pt width didn't leave room for.
        let countLabel = CenteredLabelView()
        countLabel.isHidden = true
        // Frame is NOT computed here. It used to be calculated once, right at setup,
        // from button.bounds — but setUpStatusItem() runs during
        // applicationDidFinishLaunching, before AppKit necessarily has had a layout
        // pass to settle the new status item into its final size. Two rounds of tuning
        // 16pt width and the y-nudge had zero visible effect, which pointed at the
        // frame being computed once against a bounds value that may not be the "real"
        // one the button ends up with — not at the constants themselves being wrong.
        // The fix: recompute this frame inside the queue sink below, every time it
        // fires, against whatever button.bounds actually is at that moment.
        button.addSubview(countLabel)
        // The digit is spoken as part of the button's own accessibilityLabel (set in the
        // queue sink below) — without this, VoiceOver would announce it a second time as
        // its own unlabeled element when moving focus onto the status item.
        countLabel.setAccessibilityElement(false)

        statusItem = item
        self.countLabel = countLabel

        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.delegate = self
        self.popover = popover

        queueSubscription = PasteStack.shared.$queue
            .combineLatest(PasteStack.shared.$isCollecting, LanguagePreferenceStore.shared.$preferredLanguageCode)
            .sink { queue, isCollecting, preferredLanguageCode in
            let count = queue.count
            // AppKit accessibility labels have no SwiftUI environment to inherit a locale
            // override from — resolved explicitly here so they track the in-app language
            // picker exactly like the popover's own SwiftUI text does.
            let locale: Locale = preferredLanguageCode.map(Locale.init(identifier:)) ?? .autoupdatingCurrent
            let localizedBundle = AppLocalization.bundle(for: preferredLanguageCode)

            // Recomputed every time, against the current button.bounds — see the
            // comment where countLabel is created for why this can't just be done once.
            let labelWidth: CGFloat = 16
            let labelHeight: CGFloat = 11
            let centeredX = (button.bounds.width - labelWidth) / 2
            let centeredY = (button.bounds.height - labelHeight) / 2
            // NSStatusBarButton measured `isFlipped == true` (origin top-left, Y grows
            // downward), so moving the label toward the bottom means *adding* to y, not
            // subtracting — the opposite of a normal unflipped AppKit view. Branching on
            // `button.isFlipped` here (rather than hardcoding the sign) keeps this
            // correct even if a future AppKit revision changes that.
            let downwardYNudge: CGFloat = button.isFlipped ? 1.5 : -1.5
            countLabel.frame = NSRect(
                x: centeredX,
                y: centeredY + downwardYNudge,
                width: labelWidth,
                height: labelHeight
            )

            // Icon reflects "is a recording session active" (isCollecting OR there's still
            // something queued from one) — not just whether the queue happens to be non-empty.
            // Otherwise starting a collecting session with nothing copied yet looks identical
            // to idle, with no way to tell from the menu bar alone whether recording is on.
            button.image = (isCollecting || count > 0) ? activeIcon : idleIcon

            if count == 0 {
                countLabel.isHidden = true
            } else {
                countLabel.isHidden = false
                countLabel.text = "\(count)"
                countLabel.textColor = count >= 99 ? .systemRed : .labelColor
            }

            if isCollecting {
                button.setAccessibilityLabel(String(localized: "PasteQueue, recording, \(count) items in queue", bundle: localizedBundle, locale: locale))
            } else if count > 0 {
                button.setAccessibilityLabel(String(localized: "PasteQueue, \(count) items queued, not recording", bundle: localizedBundle, locale: locale))
            } else {
                button.setAccessibilityLabel(String(localized: "PasteQueue, idle", bundle: localizedBundle, locale: locale))
            }
        }

        flashSubscription = PasteStack.shared.flashRequested.sink { [weak self] in
            self?.flashMenuBarIcon()
        }
    }

    /// Brief alpha dip on the status item button — feedback for a ⌘⌥V that had nothing to
    /// paste. Two nested runAnimationGroup calls (rather than one group with a reversed
    /// autoreverses) so the exact ~0.1s-down/~0.1s-up shape is explicit and doesn't depend
    /// on autoreverses' timing curve behaving the way we'd expect.
    private func flashMenuBarIcon() {
        guard let button = statusItem?.button else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            button.animator().alphaValue = 0.3
        } completionHandler: {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.1
                button.animator().alphaValue = 1.0
            }
        }
    }

    @objc private func statusItemClicked() {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            closePopover(reason: .statusItem)
        } else {
            showPopover(relativeTo: button, popover: popover)
        }
    }

    private func showPopover(relativeTo button: NSStatusBarButton? = nil, popover: NSPopover? = nil) {
        guard let button = button ?? statusItem?.button,
              let popover = popover ?? self.popover,
              !popover.isShown else { return }

        rememberExternalFrontmostApplication()
        // .accessory apps never become the active app on their own. Activating when the
        // user explicitly opens the menu lets the popover receive keyboard focus; later
        // paste requests return focus to the remembered external recipient.
        NSApp.activate(ignoringOtherApps: true)
        PasteStack.shared.refreshLaunchAtLoginStatus()
        _ = refreshAccess()
        isClosingPopover = false
        let minimumQueueListHeight = PasteStackMenu.listHeight(for: PasteStack.shared.queue)
        popover.contentViewController = makePopoverContentController(
            minimumQueueListHeight: minimumQueueListHeight
        )
        uiLogger.debug("popover will open queueCount=\(PasteStack.shared.queue.count, privacy: .public) minimumQueueListHeight=\(minimumQueueListHeight, privacy: .public)")
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        installPopoverEventMonitors()
    }

    func popoverDidClose(_ notification: Notification) {
        uiLogger.debug("popoverDidClose")
        cancelPendingBulkPaste()
        removePopoverEventMonitors()
        isClosingPopover = false
        // Cancel through the field while its monitor is still available. Clearing only
        // recordingAction here could make onDisappear skip monitor removal after close.
        HotkeyManager.shared.cancelRecordingHandler?()
        HotkeyManager.shared.resumeAfterRecording()
        HotkeyManager.shared.cancelRecordingHandler = nil
    }

    private func makePopoverContentController(
        minimumQueueListHeight: CGFloat
    ) -> NSHostingController<PopoverRootView> {
        NSHostingController(
            rootView: PopoverRootView(
                stack: PasteStack.shared,
                hotkeyManager: HotkeyManager.shared,
                languageStore: LanguagePreferenceStore.shared,
                accessController: accessController!,
                minimumQueueListHeight: minimumQueueListHeight,
                onPaste: { [weak self] in
                    self?.requestPaste(source: .button)
                },
                onPasteAll: { [weak self] separator, expectedIDs, completion in
                    guard let self else {
                        completion(.recipientUnavailable)
                        return
                    }
                    self.requestPaste(
                        source: .button,
                        kind: .allText(separator: separator, expectedIDs: expectedIDs),
                        completion: completion
                    )
                },
                onCancelPasteAll: { [weak self] in
                    self?.cancelPendingBulkPaste()
                }
            )
        )
    }

    private func rememberExternalFrontmostApplication() {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              isExternalApplication(frontmost) else {
            pasteRecipientApplication = nil
            return
        }
        pasteRecipientApplication = frontmost
    }

    private func requestPaste(
        source: PasteRequestSource,
        kind: PasteRequestKind = .next,
        completion: ((PasteAttemptResult) -> Void)? = nil
    ) {
        uiLogger.debug("paste requested source=\(source.rawValue, privacy: .public)")
        guard refreshAccess() else {
            showPopover()
            return
        }
        guard !isRestoringFocusForPaste else {
            reportPasteResult(.requestInProgress, for: kind, completion: completion)
            return
        }

        let beganInPopover = popover?.isShown == true
        guard beganInPopover else {
            guard !NSApp.isActive else {
                reportPasteResult(.recipientUnavailable, for: kind, completion: completion)
                return
            }
            let queueCountBeforePaste = PasteStack.shared.queue.count
            let result = performPaste(kind)
            uiLogger.debug("paste attempt outcome=\(result.rawValue, privacy: .public) queueCountBefore=\(queueCountBeforePaste, privacy: .public) queueCountAfter=\(PasteStack.shared.queue.count, privacy: .public)")
            reportPasteResult(result, for: kind, completion: completion)
            return
        }

        guard let recipient = pasteRecipientApplication,
              isExternalApplication(recipient),
              !recipient.isTerminated else {
            uiLogger.debug("recipient restore failed")
            reportPasteResult(.recipientUnavailable, for: kind, completion: completion)
            return
        }

        let bulkPasteID: UUID?
        if case .allText = kind {
            bulkPasteID = UUID()
            pendingBulkPasteID = bulkPasteID
        } else {
            bulkPasteID = nil
        }
        isRestoringFocusForPaste = true
        uiLogger.debug("recipient restore started")
        activateRecipientAndPaste(
            recipient,
            beganInPopover: beganInPopover,
            kind: kind,
            bulkPasteID: bulkPasteID,
            completion: completion
        )
    }

    private func requestToggleCollecting() {
        guard refreshAccess() else {
            showPopover()
            return
        }
        PasteStack.shared.toggleCollecting()
    }

    @discardableResult
    private func refreshAccess() -> Bool {
        guard let accessController else { return true }
        accessController.refresh()
        if !accessController.grantsAccess, PasteStack.shared.isCollecting {
            PasteStack.shared.toggleCollecting()
        }
        return accessController.grantsAccess
    }

    private func handleAccessState(_ state: LicenseAccessState) {
        trialExpirationTimer?.invalidate()
        trialExpirationTimer = nil

        switch state {
        case .trial(_, let expiresAt):
            let timer = Timer(fire: expiresAt, interval: 0, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    _ = self?.refreshAccess()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            trialExpirationTimer = timer
        case .expired:
            if PasteStack.shared.isCollecting {
                PasteStack.shared.toggleCollecting()
            }
        case .licensed, .storageUnavailable:
            break
        }
    }

    private func makeAccessController() -> LicenseAccessController {
#if DEBUG
        let keychainSuffix = ".debug"
#else
        let keychainSuffix = ""
#endif
        let configuration = LicenseProductConfiguration.current
        let trialController = TrialAccessController(
            store: KeychainTrialStateStore(service: "com.slenbder.pastequeue.trial\(keychainSuffix)")
        )
        return LicenseAccessController(
            trialController: trialController,
            credentialStore: KeychainLicenseCredentialStore(
                service: "com.slenbder.pastequeue.license\(keychainSuffix)"
            ),
            licenseService: configuration.map { LemonSqueezyLicenseClient(configuration: $0) },
            checkoutURL: configuration?.checkoutURL,
            trialWarningStore: UserDefaultsTrialWarningStore(
                key: "trial-warning-thresholds-v1\(keychainSuffix)"
            )
        )
    }

    private func activateRecipientAndPaste(
        _ recipient: NSRunningApplication,
        beganInPopover: Bool,
        kind: PasteRequestKind,
        bulkPasteID: UUID?,
        completion: ((PasteAttemptResult) -> Void)?
    ) {
        guard !recipient.isTerminated,
              recipient.activate(options: [.activateIgnoringOtherApps]) else {
            uiLogger.debug("recipient restore failed")
            pendingBulkPasteID = nil
            finishFocusRestore(success: false)
            reportPasteResult(
                .recipientUnavailable,
                for: kind,
                completion: completion,
                restorePopoverFocus: true
            )
            return
        }

        waitForActivation(of: recipient) { [weak self] success in
            guard let self else { return }
            if let bulkPasteID {
                guard pendingBulkPasteID == bulkPasteID else { return }
                pendingBulkPasteID = nil
            }
            finishFocusRestore(success: success)
            if success {
                uiLogger.debug("recipient restore confirmed")
                let queueCountBeforePaste = PasteStack.shared.queue.count
                let result = performPaste(kind)
                uiLogger.debug("paste attempt outcome=\(result.rawValue, privacy: .public) queueCountBefore=\(queueCountBeforePaste, privacy: .public) queueCountAfter=\(PasteStack.shared.queue.count, privacy: .public)")
                reportPasteResult(
                    result,
                    for: kind,
                    completion: completion,
                    restorePopoverFocus: true
                )
                if beganInPopover, result == .commandPosted, PasteStack.shared.queue.isEmpty {
                    closePopover(reason: .queueDrained)
                }
            } else {
                uiLogger.debug("recipient restore failed")
                reportPasteResult(
                    .recipientUnavailable,
                    for: kind,
                    completion: completion,
                    restorePopoverFocus: true
                )
            }
        }
    }

    private func cancelPendingBulkPaste() {
        guard pendingBulkPasteID != nil else { return }
        pendingBulkPasteID = nil
        finishFocusRestore(success: true)
    }

    private func reportPasteResult(
        _ result: PasteAttemptResult,
        for kind: PasteRequestKind,
        completion: ((PasteAttemptResult) -> Void)?,
        restorePopoverFocus: Bool = false
    ) {
        completion?(result)
        if restorePopoverFocus,
           case .allText = kind,
           result != .commandPosted,
           popover?.isShown == true {
            NSApp.activate(ignoringOtherApps: true)
            popover?.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
        }
    }

    private func performPaste(_ kind: PasteRequestKind) -> PasteAttemptResult {
        switch kind {
        case .next:
            return PasteStack.shared.pasteNext()
        case .allText(let separator, let expectedIDs):
            return PasteStack.shared.pasteAllText(separator: separator, expectedIDs: expectedIDs)
        }
    }

    private func waitForActivation(
        of recipient: NSRunningApplication,
        completion: @escaping (Bool) -> Void
    ) {
        if isFrontmost(recipient) {
            completion(true)
            return
        }

        let notificationCenter = NSWorkspace.shared.notificationCenter
        activationObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self,
                      activationObserver != nil,
                      let activated = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      activated.processIdentifier == recipient.processIdentifier else { return }
                completion(true)
            }
        }

        let timeout = DispatchWorkItem { [weak self] in
            guard let self, activationTimeout != nil else { return }
            if !isFrontmost(recipient) {
                uiLogger.debug("recipient restore timeout")
            }
            completion(isFrontmost(recipient))
        }
        activationTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: timeout)
    }

    private func finishFocusRestore(success: Bool) {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        activationTimeout?.cancel()
        activationTimeout = nil
        isRestoringFocusForPaste = false
        if !success {
            pasteRecipientApplication = nil
        }
    }

    private func isFrontmost(_ application: NSRunningApplication) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier
    }

    private func isExternalApplication(_ application: NSRunningApplication) -> Bool {
        application.processIdentifier != ProcessInfo.processInfo.processIdentifier
    }

    private func installPopoverEventMonitors() {
        guard globalMouseMonitor == nil,
              localMouseMonitor == nil,
              escapeKeyMonitor == nil else { return }

        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self] event in
            guard let self else { return }
            let screenPoint = screenLocation(for: event)
            if !isScreenPointInsidePopover(screenPoint), !isScreenPointOnStatusItem(screenPoint) {
                closePopover(reason: .outsideClick)
            }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self] event in
            guard let self else { return event }
            if !isEventInsidePopover(event), !isEventOnStatusItem(event) {
                closePopover(reason: .outsideClick)
            }
            return event
        }

        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == ShortcutRecording.escapeKeyCode {
                // A ShortcutRecorderField currently recording claims Escape for itself
                // (cancel the recording, keep the popover open) instead of the usual
                // close-popover behavior. Routed through this single existing monitor
                // rather than a second, independently-registered one, since AppKit doesn't
                // document firing order between two local monitors for the same event type.
                if let cancelRecording = HotkeyManager.shared.cancelRecordingHandler {
                    cancelRecording()
                    return nil
                }
                closePopover(reason: .escape)
                return nil
            }
            return event
        }
    }

    private func closePopover(reason: PopoverCloseReason) {
        guard !isClosingPopover,
              popover?.isShown == true else { return }
        isClosingPopover = true
        uiLogger.debug("popover close requested reason=\(reason.rawValue, privacy: .public)")
        cancelPendingBulkPaste()
        popover?.close()
    }

    private func removePopoverEventMonitors() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let escapeKeyMonitor {
            NSEvent.removeMonitor(escapeKeyMonitor)
            self.escapeKeyMonitor = nil
        }
    }

    private func screenLocation(for event: NSEvent) -> NSPoint {
        guard let window = event.window else { return event.locationInWindow }
        return window.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
    }

    private func isScreenPointInsidePopover(_ screenPoint: NSPoint) -> Bool {
        guard let popoverWindow = popover?.contentViewController?.view.window else { return false }
        return popoverWindow.frame.contains(screenPoint)
    }

    private func isScreenPointOnStatusItem(_ screenPoint: NSPoint) -> Bool {
        guard let button = statusItem?.button,
              let window = button.window else { return false }
        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrameInScreen = window.convertToScreen(buttonFrameInWindow)
        return buttonFrameInScreen.contains(screenPoint)
    }

    private func isEventInsidePopover(_ event: NSEvent) -> Bool {
        guard let popoverWindow = popover?.contentViewController?.view.window else { return false }
        return event.window === popoverWindow
    }

    private func isEventOnStatusItem(_ event: NSEvent) -> Bool {
        guard let button = statusItem?.button,
              event.window === button.window else { return false }
        let locationInButton = button.convert(event.locationInWindow, from: nil)
        return button.bounds.contains(locationInButton)
    }
}
