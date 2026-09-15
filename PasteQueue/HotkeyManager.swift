import AppKit
import Carbon

/// Registers two global hotkeys system-wide:
///   ⌃⌘C  — toggle collecting mode on/off
///   ⌃⌘V  — pop the next item off the queue and paste it
///
/// Needs BOTH a global and a local monitor. Per NSEvent's own documentation:
/// "your handler will not be called for events that are sent to your own application"
/// (addGlobalMonitorForEvents). PasteQueue becomes the active app the moment the user
/// clicks the status item to open the popover — so a ⌃⌘C pressed while that popover is
/// open targets PasteQueue itself, not "another" app, and the global-only monitor never
/// sees it (isCollecting genuinely never changes; it's not a SwiftUI redraw problem).
/// The local monitor covers exactly that case; the global one covers everything else.
/// Both are passive here (local returns the event unmodified) — nothing else is listening
/// for this exact combo, so there's no conflict in practice.
final class HotkeyManager {
    static let shared = HotkeyManager()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pasteRequestHandler: () -> Void = {
        PasteStack.shared.pasteNext()
    }

    private init() {}

    func start(pasteRequestHandler: @escaping () -> Void = { PasteStack.shared.pasteNext() }) {
        self.pasteRequestHandler = pasteRequestHandler
        requestAccessibilityIfNeeded()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == [.control, .command] else { return }

        switch Self.asciiCapableCharacter(for: event.keyCode)?.lowercased() {
        case "c":
            PasteStack.shared.toggleCollecting()
        case "v":
            pasteRequestHandler()
        default:
            break
        }
    }

    /// Translates a virtual keyCode into the character it would produce under the
    /// system's ASCII-capable hardware layout, ignoring the currently active Unicode
    /// input source (e.g. Cyrillic, Japanese). This is what keeps ⌃⌘C/⌃⌘V tracking the
    /// physical hardware key under Dvorak/AZERTY, while staying unaffected by non-Latin
    /// input sources, since those are software input methods layered on the same
    /// physical ANSI hardware rather than alternate hardware layouts.
    private static func asciiCapableCharacter(for keyCode: UInt16) -> String? {
        guard let inputSource = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue() else { return nil }
        guard let layoutDataPointer = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutDataPointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layoutData.withUnsafeBytes { rawBuffer -> OSStatus in
            let keyboardLayout = rawBuffer.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self)
            return UCKeyTranslate(
                keyboardLayout,
                keyCode,
                UInt16(kUCKeyActionDown),
                0,
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }

    private func requestAccessibilityIfNeeded() {
        // Prompts the system Accessibility permission dialog on first launch if not yet granted.
        // Required for both global key monitoring and posting synthetic CGEvents.
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options: [String: Any] = [promptKey: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
