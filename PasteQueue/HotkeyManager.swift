import AppKit
import Carbon
import Combine

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

    private static func keyCode(for character: String, modifierKeyState: UInt32, translator: Translator) -> CGKeyCode? {
        for keyCode in UInt16(0)...UInt16(127) {
            guard let translated = translator(keyCode, modifierKeyState) else { continue }
            if translated.lowercased() == character.lowercased() {
                return CGKeyCode(keyCode)
            }
        }
        return nil
    }

    static func commandKeyCode(for character: String, translator: Translator) -> CGKeyCode? {
        keyCode(for: character, modifierKeyState: commandModifierKeyState, translator: translator)
    }

    /// Reverse of asciiCapableCharacter(for:) — same UNMODIFIED (state 0) table, just the
    /// other direction (character -> keyCode). HotkeyManager.effectiveSpec() uses this (not
    /// commandKeyCode) so its lookup shares matchingAction's exact modifier-state semantics:
    /// on a layout where the Command-modified table disagrees with the unmodified one for a
    /// given physical key, commandKeyCode here would have resolved to a DIFFERENT keyCode
    /// than the one matchingAction actually fires on for the same default character.
    static func asciiCapableKeyCode(for character: String, translator: Translator) -> CGKeyCode? {
        keyCode(for: character, modifierKeyState: 0, translator: translator)
    }

    /// Live variant used to resolve the current physical keyCode for an un-overridden
    /// shortcut's default character (e.g. dedupe/display against "c"/"v") — always
    /// re-queries the active keyboard layout, never caches a stale result.
    static func asciiCapableKeyCode(for character: String) -> CGKeyCode? {
        guard let translator = currentASCIICapableTranslator() else { return nil }
        return asciiCapableKeyCode(for: character, translator: translator)
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

/// Registers two global hotkeys system-wide, one per ShortcutAction:
///   ⌃⌘C  — toggle collecting mode on/off (default; user-rebindable in Settings)
///   ⌃⌘V  — pop the next item off the queue and paste it (default; user-rebindable)
///
/// Needs BOTH a global and a local monitor. Per NSEvent's own documentation:
/// "your handler will not be called for events that are sent to your own application"
/// (addGlobalMonitorForEvents). PasteQueue becomes the active app the moment the user
/// clicks the status item to open the popover — so a shortcut pressed while that popover is
/// open targets PasteQueue itself, not "another" app, and the global-only monitor never
/// sees it. The local monitor covers exactly that case; the global one covers everything else.
/// Both are passive here (local returns the event unmodified) — nothing else is listening
/// for these exact combos by default, but a user-recorded override CAN collide with another
/// app or the system (e.g. a bare ⌘V) — that's an accepted, user-chosen tradeoff, not a bug.
///
/// An un-overridden action matches via LIVE ASCII-layout translation (Dvorak/AZERTY-safe,
/// unaffected by non-Latin IMEs) exactly as before. A user-recorded override matches by raw
/// (keyCode, modifiers) instead — required regardless, since function keys have no ASCII
/// character to translate.
final class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    typealias ActionHandler = () -> Void

    @Published private(set) var overrides: [ShortcutAction: HotkeySpec] = [:]
    /// The action a ShortcutRecorderField is currently capturing a new combo for, if any —
    /// single source of truth for "is anything being recorded right now" (matchingAction
    /// below still suppresses BOTH actions while non-nil; that's intentional, see
    /// matchingAction's own comment). ShortcutRecorderField reads this directly instead of
    /// threading a separately-owned @State/@Binding through SettingsMenu, so there's exactly
    /// one place this can drift out of sync with reality instead of two.
    @Published private(set) var recordingAction: ShortcutAction?
    /// Hook for AppDelegate's own Escape-closes-popover local monitor: when set, Escape
    /// should call this instead of closing the popover. See PasteQueueApp.swift.
    var escapeRecordingInterceptor: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var toggleCollectingHandler: ActionHandler
    private var pasteRequestHandler: ActionHandler
    private let shortcutStore: ShortcutStoring

    // Private: the only production call site is `shared` below. Kept as a *convenience*
    // init (not folded into `shared`'s own initializer) so it still funnels through the
    // designated init's single init path — but private means nothing else in the module can
    // construct a second production-wired instance by accident. Tests bypass this entirely
    // via the designated init below, which stays internal for exactly that purpose.
    private convenience init() {
        self.init(
            shortcutStore: UserDefaultsShortcutStore(),
            toggleCollectingHandler: { PasteStack.shared.toggleCollecting() },
            pasteRequestHandler: { PasteStack.shared.pasteNext() }
        )
    }

    /// Both handlers default to a no-op (not PasteStack.shared) so tests that construct a
    /// HotkeyManager directly never touch the production singleton unless they explicitly
    /// opt in — mirrors PasteStack's own designated-init DI pattern.
    init(
        shortcutStore: ShortcutStoring,
        toggleCollectingHandler: @escaping ActionHandler = {},
        pasteRequestHandler: @escaping ActionHandler = {}
    ) {
        self.shortcutStore = shortcutStore
        self.toggleCollectingHandler = toggleCollectingHandler
        self.pasteRequestHandler = pasteRequestHandler
        for action in ShortcutAction.allCases {
            overrides[action] = shortcutStore.override(for: action)
        }
    }

    /// Installs the real global+local NSEvent monitors and wires the production paste
    /// route. Only ever called from AppDelegate.applicationDidFinishLaunching, which itself
    /// returns before this for the test host — never exercised by PasteQueueTests.
    func start(pasteRequestHandler: @escaping ActionHandler = { PasteStack.shared.pasteNext() }) {
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

    // MARK: - Overrides

    func setOverride(_ spec: HotkeySpec?, for action: ShortcutAction) {
        overrides[action] = spec
        shortcutStore.setOverride(spec, for: action)
    }

    /// The spec currently in effect for an action: its override if customized, else the
    /// LIVE default translated against the current keyboard layout (never frozen/cached) —
    /// used for display and for dedupe-checking a freshly recorded combo against whatever
    /// the OTHER action currently resolves to, override or not.
    func effectiveSpec(for action: ShortcutAction) -> HotkeySpec? {
        if let override = overrides[action] { return override }
        // asciiCapableKeyCode (not commandKeyCode) — see its doc comment above. Using the
        // Command-modified table here used to let this disagree with matchingAction, which
        // always resolves keyCode -> character under the unmodified table.
        guard let keyCode = KeyboardLayoutTranslator.asciiCapableKeyCode(for: action.defaultCharacter) else { return nil }
        return HotkeySpec(keyCode: keyCode, modifierFlags: [.control, .command])
    }

    // MARK: - Recording pause

    /// Suppresses matching for BOTH actions, not just `action` — intentional: while a
    /// ShortcutRecorderField is capturing a new combo, the OTHER action's un-overridden
    /// default could easily be one of the keys the user presses while experimenting, and
    /// letting it fire mid-capture would be confusing. Covered by
    /// testPausingSuppressesAllMatchingUntilResumed.
    func pauseForRecording(action: ShortcutAction) {
        recordingAction = action
    }

    func resumeAfterRecording() {
        recordingAction = nil
    }

    // MARK: - Matching

    private func handle(_ event: NSEvent) {
        guard let action = matchingAction(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags,
            isRepeat: event.isARepeat
        ) else { return }
        perform(action)
    }

    /// Exposed (not private) so tests can drive matching with synthetic values instead of
    /// constructing real NSEvents or real global monitors — same reasoning as
    /// shouldHandleShortcut below.
    func matchingAction(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, isRepeat: Bool) -> ShortcutAction? {
        guard recordingAction == nil, !isRepeat else { return nil }
        // Resolved once per call, not once per un-overridden action in the loop below — this
        // runs on the GLOBAL monitor (every keystroke, system-wide), and the live keyboard-
        // layout query it wraps (TIS/Carbon) isn't free enough to redo per candidate action.
        let translatedCharacter = KeyboardLayoutTranslator.asciiCapableCharacter(for: keyCode)?.lowercased()
        for action in ShortcutAction.allCases {
            if let override = overrides[action] {
                if HotkeySpec(keyCode: keyCode, modifierFlags: modifierFlags) == override {
                    return action
                }
                continue
            }
            guard Self.shouldHandleShortcut(modifierFlags: modifierFlags, isRepeat: isRepeat) else { continue }
            if translatedCharacter == action.defaultCharacter {
                return action
            }
        }
        return nil
    }

    func perform(_ action: ShortcutAction) {
        switch action {
        case .startStopCollecting:
            toggleCollectingHandler()
        case .pasteNext:
            pasteRequestHandler()
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
