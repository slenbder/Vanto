import AppKit
import Carbon

internal enum KeyboardLayoutTranslator {
    typealias Translator = (_ keyCode: UInt16, _ modifierKeyState: UInt32) -> String?

    static let commandModifierKeyState = UInt32((cmdKey >> 8) & 0xFF)
    static let fallbackVKeyCode: CGKeyCode = 9

    /// Translates a virtual key code under the ASCII-capable hardware layout with no
    /// modifiers. Input shortcut matching intentionally uses this path unchanged.
    static func asciiCapableCharacter(for keyCode: UInt16) -> String? {
        guard let translator = currentASCIICapableTranslator() else { return nil }
        return translator(keyCode, 0)
    }

    static func commandKeyCode(for character: String, translator: Translator) -> CGKeyCode? {
        for keyCode in UInt16(0)...UInt16(127) {
            guard let translated = translator(keyCode, commandModifierKeyState) else { continue }
            if translated.lowercased() == character.lowercased() {
                return CGKeyCode(keyCode)
            }
        }
        return nil
    }

    static func commandVKeyCode() -> CGKeyCode {
        guard let translator = currentASCIICapableTranslator() else { return fallbackVKeyCode }
        return commandVKeyCode(translator: translator)
    }

    static func commandVKeyCode(translator: Translator) -> CGKeyCode {
        commandKeyCode(for: "v", translator: translator) ?? fallbackVKeyCode
    }

    private static func currentASCIICapableTranslator() -> Translator? {
        guard let inputSource = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue() else { return nil }
        guard let layoutDataPointer = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutDataPointer).takeUnretainedValue() as Data

        return { keyCode, modifierKeyState in
            translate(keyCode: keyCode, modifierKeyState: modifierKeyState, layoutData: layoutData)
        }
    }

    private static func translate(keyCode: UInt16, modifierKeyState: UInt32, layoutData: Data) -> String? {
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layoutData.withUnsafeBytes { rawBuffer -> OSStatus in
            guard let baseAddress = rawBuffer.baseAddress else { return OSStatus(paramErr) }
            let keyboardLayout = baseAddress.assumingMemoryBound(to: UCKeyboardLayout.self)
            return UCKeyTranslate(
                keyboardLayout,
                keyCode,
                UInt16(kUCKeyActionDown),
                modifierKeyState,
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
}

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
        guard Self.shouldHandleShortcut(modifierFlags: event.modifierFlags, isRepeat: event.isARepeat) else { return }

        switch KeyboardLayoutTranslator.asciiCapableCharacter(for: event.keyCode)?.lowercased() {
        case "c":
            PasteStack.shared.toggleCollecting()
        case "v":
            pasteRequestHandler()
        default:
            break
        }
    }

    internal static func shouldHandleShortcut(modifierFlags: NSEvent.ModifierFlags, isRepeat: Bool) -> Bool {
        guard !isRepeat else { return false }

        let shortcutModifiers = modifierFlags.intersection([.control, .command, .shift, .option])
        return shortcutModifiers == [.control, .command]
    }

    private func requestAccessibilityIfNeeded() {
        // Prompts the system Accessibility permission dialog on first launch if not yet granted.
        // Required for both global key monitoring and posting synthetic CGEvents.
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options: [String: Any] = [promptKey: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
