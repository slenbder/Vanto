import SwiftUI
import AppKit
import Combine

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

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var countLabel: CenteredLabelView?
    private var popover: NSPopover?
    private var queueSubscription: AnyCancellable?
    private var flashSubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // PasteQueueTests run inside this executable via TEST_HOST. Return before touching
        // either singleton so the host cannot monitor keys, prompt for Accessibility, poll
        // the system pasteboard, sweep production file storage, or query login-item state.
        guard !AppRuntime.isRunningTests else { return }

        // Hide the Dock icon — this is a menu-bar-only utility.
        NSApp.setActivationPolicy(.accessory)
        HotkeyManager.shared.start()
        PasteStack.shared.refreshLaunchAtLoginStatus()
        setUpStatusItem()
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
        popover.contentViewController = NSHostingController(rootView: PasteStackMenu(stack: PasteStack.shared))
        popover.behavior = .transient
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
            popover.close()
        } else {
            // .accessory apps never become the active app on their own — without this,
            // clicking outside the popover (another app's window, Dock, desktop) never
            // triggers the "app resigns active" transition that .transient's automatic
            // dismissal relies on, so the popover only ever closes via a repeat click on
            // this same status item button (which counts as interacting with our own window).
            NSApp.activate(ignoringOtherApps: true)
            PasteStack.shared.refreshLaunchAtLoginStatus()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
