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

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var countLabel: CenteredLabelView?
    private var popover: NSPopover?
    private var queueSubscription: AnyCancellable?
    private var flashSubscription: AnyCancellable?
    private var pasteRecipientApplication: NSRunningApplication?
    private var isRestoringFocusForPaste = false
    private var activationObserver: NSObjectProtocol?
    private var activationTimeout: DispatchWorkItem?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var escapeKeyMonitor: Any?
    private var isClosingPopover = false

    private enum PasteRequestSource: String {
        case button
        case hotkey
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
        HotkeyManager.shared.start { [weak self] in
            self?.requestPaste(source: .hotkey)
        }
        PasteStack.shared.refreshLaunchAtLoginStatus()
        setUpStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
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

        queueSubscription = PasteStack.shared.$queue.combineLatest(PasteStack.shared.$isCollecting).sink { queue, isCollecting in
            let count = queue.count

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

            let itemWord = count == 1 ? "item" : "items"
            if isCollecting {
                button.setAccessibilityLabel("PasteQueue, recording, \(count) \(itemWord) in queue")
            } else if count > 0 {
                button.setAccessibilityLabel("PasteQueue, \(count) \(itemWord) queued, not recording")
            } else {
                button.setAccessibilityLabel("PasteQueue, idle")
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
            rememberExternalFrontmostApplication()
            // .accessory apps never become the active app on their own. Activating when the
            // user explicitly opens the menu lets the popover receive keyboard focus; later
            // paste requests return focus to the remembered external recipient.
            NSApp.activate(ignoringOtherApps: true)
            PasteStack.shared.refreshLaunchAtLoginStatus()
            isClosingPopover = false
            let minimumQueueListHeight = PasteStackMenu.listHeight(for: PasteStack.shared.queue)
            popover.contentViewController = makePopoverContentController(
                minimumQueueListHeight: minimumQueueListHeight
            )
            uiLogger.debug("popover will open queueCount=\(PasteStack.shared.queue.count, privacy: .public) minimumQueueListHeight=\(minimumQueueListHeight, privacy: .public)")
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            installPopoverEventMonitors()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        uiLogger.debug("popoverDidClose")
        removePopoverEventMonitors()
        isClosingPopover = false
    }

    private func makePopoverContentController(
        minimumQueueListHeight: CGFloat
    ) -> NSHostingController<PasteStackMenu> {
        NSHostingController(
            rootView: PasteStackMenu(
                stack: PasteStack.shared,
                minimumQueueListHeight: minimumQueueListHeight
            ) { [weak self] in
                self?.requestPaste(source: .button)
            }
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

    private func requestPaste(source: PasteRequestSource) {
        uiLogger.debug("paste requested source=\(source.rawValue, privacy: .public)")
        guard !isRestoringFocusForPaste else { return }

        let beganInPopover = popover?.isShown == true
        guard beganInPopover else {
            guard !NSApp.isActive else { return }
            let queueCountBeforePaste = PasteStack.shared.queue.count
            PasteStack.shared.pasteNext()
            uiLogger.debug("paste sent queueCountBefore=\(queueCountBeforePaste, privacy: .public) queueCountAfter=\(PasteStack.shared.queue.count, privacy: .public)")
            return
        }

        guard let recipient = pasteRecipientApplication,
              isExternalApplication(recipient),
              !recipient.isTerminated else {
            uiLogger.debug("recipient restore failed")
            return
        }

        isRestoringFocusForPaste = true
        uiLogger.debug("recipient restore started")
        activateRecipientAndPaste(recipient, beganInPopover: beganInPopover)
    }

    private func activateRecipientAndPaste(
        _ recipient: NSRunningApplication,
        beganInPopover: Bool
    ) {
        guard !recipient.isTerminated,
              recipient.activate(options: [.activateIgnoringOtherApps]) else {
            uiLogger.debug("recipient restore failed")
            finishFocusRestore(success: false)
            return
        }

        waitForActivation(of: recipient) { [weak self] success in
            guard let self else { return }
            finishFocusRestore(success: success)
            if success {
                uiLogger.debug("recipient restore confirmed")
                let queueCountBeforePaste = PasteStack.shared.queue.count
                PasteStack.shared.pasteNext()
                uiLogger.debug("paste sent queueCountBefore=\(queueCountBeforePaste, privacy: .public) queueCountAfter=\(PasteStack.shared.queue.count, privacy: .public)")
                if beganInPopover, PasteStack.shared.queue.isEmpty {
                    closePopover(reason: .queueDrained)
                }
            } else {
                uiLogger.debug("recipient restore failed")
            }
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
            guard let self,
                  activationObserver != nil,
                  let activated = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  activated.processIdentifier == recipient.processIdentifier else { return }
            completion(true)
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
            if event.keyCode == 53 {
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
