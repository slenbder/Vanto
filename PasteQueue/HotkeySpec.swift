import AppKit
import Carbon

/// One rebindable global-shortcut target. Extend this enum to add more.
enum ShortcutAction: String, CaseIterable, Codable {
    case startStopCollecting
    case pasteNext

    /// The physical letter this action's factory-default binding maps to. HotkeyManager
    /// translates this live against the current keyboard layout (KeyboardLayoutTranslator)
    /// rather than freezing it to a keyCode, preserving Dvorak/AZERTY-safety for the
    /// un-customized default exactly as today.
    var defaultCharacter: String {
        switch self {
        case .startStopCollecting: return "c"
        case .pasteNext: return "v"
        }
    }

    var defaultDisplayString: String {
        "⌃⌘\(defaultCharacter.uppercased())"
    }

    /// User-facing name for the "already used by …" duplicate caption. The row's own label
    /// (ShortcutRecorderField.actionLabel) renders the same two literals directly as Text
    /// instead of calling this — this exists for contexts that need a plain String to
    /// interpolate into another message, where Text's automatic extraction doesn't apply.
    func displayName(locale: Locale) -> String {
        switch self {
        case .startStopCollecting:
            return String(localized: "Start/Stop Collecting", locale: locale)
        case .pasteNext:
            return String(localized: "Paste Next Item", locale: locale)
        }
    }
}

/// A recorded (keyCode, modifiers) pair. `modifiersRawValue` is pre-masked to the four
/// shortcut-relevant flags at construction so two specs built from slightly different raw
/// NSEvent.modifierFlags (differing device/numpad bits) still compare and hash equal
/// whenever they represent the same user-visible combo.
struct HotkeySpec: Codable, Hashable {
    let keyCode: UInt16
    let modifiersRawValue: UInt

    static let relevantModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    init(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiersRawValue = modifierFlags.intersection(Self.relevantModifiers).rawValue
    }

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiersRawValue)
    }

    /// Apple's canonical on-screen modifier order: Control, Option, Shift, Command.
    var displayString: String {
        var symbols = ""
        if modifierFlags.contains(.control) { symbols += "⌃" }
        if modifierFlags.contains(.option) { symbols += "⌥" }
        if modifierFlags.contains(.shift) { symbols += "⇧" }
        if modifierFlags.contains(.command) { symbols += "⌘" }
        return symbols + Self.keySymbol(for: keyCode)
    }

    private static func keySymbol(for keyCode: UInt16) -> String {
        if let named = functionKeySymbols[keyCode] {
            return named
        }
        if let character = KeyboardLayoutTranslator.asciiCapableCharacter(for: keyCode) {
            return character.uppercased()
        }
        return "Key \(keyCode)"
    }

    /// Layout-independent physical positions — stable regardless of the active input source.
    static let functionKeySymbols: [UInt16: String] = [
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3", UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6", UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9", UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
        UInt16(kVK_F13): "F13", UInt16(kVK_F14): "F14", UInt16(kVK_F15): "F15", UInt16(kVK_F16): "F16",
        UInt16(kVK_F17): "F17", UInt16(kVK_F18): "F18", UInt16(kVK_F19): "F19", UInt16(kVK_F20): "F20",
    ]
}

/// Outcome of a single keydown observed while a ShortcutRecorderField is recording.
enum ShortcutRecordingOutcome: Equatable {
    /// Escape was pressed — recording should abort and the field should revert. Never
    /// itself recordable as a bound key.
    case cancelled
    /// The key doesn't qualify yet (no modifier held, or an unsupported key) — keep
    /// listening silently; this is not an error state, just "not done yet."
    case ignored
    case captured(HotkeySpec)
}

/// Pure classification/validation logic for shortcut recording — no AppKit event loop, no
/// view code, fully unit-testable with synthetic keyCode/modifierFlags inputs.
enum ShortcutRecording {
    private static let escapeKeyCode: UInt16 = 53

    static func classify(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        isRepeat: Bool
    ) -> ShortcutRecordingOutcome {
        guard !isRepeat else { return .ignored }
        guard keyCode != escapeKeyCode else { return .cancelled }

        let modifiers = modifierFlags.intersection(HotkeySpec.relevantModifiers)
        guard !modifiers.isEmpty else { return .ignored }
        guard isSupportedKey(keyCode) else { return .ignored }

        return .captured(HotkeySpec(keyCode: keyCode, modifierFlags: modifiers))
    }

    /// Letters, digits, and function keys only. Tab/Space/Return/Delete/Arrows are excluded
    /// even with a modifier held — they're far likelier to be brushed by accident mid-use
    /// than a dedicated F-key is, and the app's own Escape-to-cancel already claims Escape.
    private static func isSupportedKey(_ keyCode: UInt16) -> Bool {
        if HotkeySpec.functionKeySymbols[keyCode] != nil { return true }
        guard let character = KeyboardLayoutTranslator.asciiCapableCharacter(for: keyCode),
              let onlyCharacter = character.first,
              character.count == 1 else { return false }
        return onlyCharacter.isLetter || onlyCharacter.isNumber
    }

    /// True only for a BARE single-⌘ combo whose key resolves to c/v/x — the literal
    /// system Copy/Paste/Cut shortcuts, the only combos that actively corrupt ordinary
    /// clipboard use elsewhere (see HotkeyManager's passive, non-blocking global monitor).
    static func isSystemCopyPasteCutConflict(_ spec: HotkeySpec) -> Bool {
        guard spec.modifierFlags == [.command] else { return false }
        guard let character = KeyboardLayoutTranslator.asciiCapableCharacter(for: spec.keyCode)?.lowercased() else {
            return false
        }
        return ["c", "v", "x"].contains(character)
    }

    static func isDuplicate(_ lhs: HotkeySpec, _ rhs: HotkeySpec) -> Bool {
        lhs == rhs
    }
}
