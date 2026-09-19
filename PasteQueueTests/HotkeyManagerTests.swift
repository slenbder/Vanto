@testable import PasteQueue
import AppKit
import Carbon
import XCTest

final class HotkeyManagerTests: XCTestCase {
    // ANSI US physical keyCodes — same constants HotkeyManagerShortcutTests already relies on.
    private let keyCodeC: UInt16 = 8
    private let keyCodeV: UInt16 = 9
    private let keyCodeF1 = UInt16(kVK_F1)

    private final class Recorder {
        private(set) var callCount = 0
        func handler() { callCount += 1 }
    }

    private func makeManager(
        store: MockShortcutStore = MockShortcutStore(),
        toggleCollecting: Recorder = Recorder(),
        pasteNext: Recorder = Recorder()
    ) -> HotkeyManager {
        HotkeyManager(
            shortcutStore: store,
            toggleCollectingHandler: toggleCollecting.handler,
            pasteRequestHandler: pasteNext.handler
        )
    }

    // MARK: - Default (un-overridden) matching stays exactly as before

    func testDefaultMatchingResolvesBothActions() {
        let manager = makeManager()

        XCTAssertEqual(
            manager.matchingAction(keyCode: keyCodeC, modifierFlags: [.control, .command], isRepeat: false),
            .startStopCollecting
        )
        XCTAssertEqual(
            manager.matchingAction(keyCode: keyCodeV, modifierFlags: [.control, .command], isRepeat: false),
            .pasteNext
        )
    }

    func testDefaultMatchingRejectsExtraModifiersAndRepeats() {
        let manager = makeManager()

        XCTAssertNil(manager.matchingAction(keyCode: keyCodeV, modifierFlags: [.control, .command, .shift], isRepeat: false))
        XCTAssertNil(manager.matchingAction(keyCode: keyCodeV, modifierFlags: [.control, .command], isRepeat: true))
    }

    // MARK: - Overrides

    func testOverrideMatchesRawKeyCodeAndReplacesDefaultEntirely() {
        let manager = makeManager()
        let override = HotkeySpec(keyCode: keyCodeF1, modifierFlags: [.command])
        manager.setOverride(override, for: .pasteNext)

        XCTAssertEqual(
            manager.matchingAction(keyCode: keyCodeF1, modifierFlags: [.command], isRepeat: false),
            .pasteNext
        )
        // The factory-default ⌃⌘V no longer does anything once overridden.
        XCTAssertNil(manager.matchingAction(keyCode: keyCodeV, modifierFlags: [.control, .command], isRepeat: false))
    }

    func testOverrideDoesNotAffectTheOtherAction() {
        let manager = makeManager()
        manager.setOverride(HotkeySpec(keyCode: keyCodeF1, modifierFlags: [.command]), for: .pasteNext)

        XCTAssertEqual(
            manager.matchingAction(keyCode: keyCodeC, modifierFlags: [.control, .command], isRepeat: false),
            .startStopCollecting
        )
    }

    func testSetOverridePersistsThroughStoreAndUpdatesInMemoryState() {
        let store = MockShortcutStore()
        let manager = makeManager(store: store)
        let spec = HotkeySpec(keyCode: keyCodeF1, modifierFlags: [.command])

        manager.setOverride(spec, for: .startStopCollecting)

        XCTAssertEqual(store.override(for: .startStopCollecting), spec)
        XCTAssertEqual(store.setOverrideCallCount, 1)
        XCTAssertEqual(manager.overrides[.startStopCollecting], spec)
    }

    func testInitLoadsExistingOverridesFromStore() {
        let store = MockShortcutStore()
        let spec = HotkeySpec(keyCode: keyCodeF1, modifierFlags: [.command])
        store.setOverride(spec, for: .pasteNext)

        let manager = makeManager(store: store)

        XCTAssertEqual(manager.overrides[.pasteNext], spec)
        XCTAssertEqual(manager.effectiveSpec(for: .pasteNext), spec)
    }

    func testResetToDefaultClearsOverrideAndRestoresLiveMatching() {
        let manager = makeManager()
        manager.setOverride(HotkeySpec(keyCode: keyCodeF1, modifierFlags: [.command]), for: .pasteNext)
        manager.setOverride(nil, for: .pasteNext)

        XCTAssertNil(manager.overrides[.pasteNext])
        XCTAssertEqual(
            manager.matchingAction(keyCode: keyCodeV, modifierFlags: [.control, .command], isRepeat: false),
            .pasteNext
        )
    }

    // MARK: - effectiveSpec

    func testEffectiveSpecFallsBackToLiveDefaultWhenNoOverride() {
        let manager = makeManager()
        XCTAssertEqual(manager.effectiveSpec(for: .startStopCollecting)?.keyCode, keyCodeC)
        XCTAssertEqual(manager.effectiveSpec(for: .pasteNext)?.keyCode, keyCodeV)
    }

    // MARK: - Recording pause

    func testPausingSuppressesAllMatchingUntilResumed() {
        let manager = makeManager()
        manager.pauseForRecording(action: .pasteNext)

        XCTAssertNil(manager.matchingAction(keyCode: keyCodeC, modifierFlags: [.control, .command], isRepeat: false))
        XCTAssertNil(manager.matchingAction(keyCode: keyCodeV, modifierFlags: [.control, .command], isRepeat: false))

        manager.resumeAfterRecording()

        XCTAssertEqual(
            manager.matchingAction(keyCode: keyCodeC, modifierFlags: [.control, .command], isRepeat: false),
            .startStopCollecting
        )
    }

    // MARK: - perform() dispatches to injected handlers only — never touches PasteStack.shared

    func testPerformDispatchesToInjectedHandlers() {
        let toggleCollecting = Recorder()
        let pasteNext = Recorder()
        let manager = makeManager(toggleCollecting: toggleCollecting, pasteNext: pasteNext)

        manager.perform(.startStopCollecting)
        manager.perform(.pasteNext)
        manager.perform(.pasteNext)

        XCTAssertEqual(toggleCollecting.callCount, 1)
        XCTAssertEqual(pasteNext.callCount, 2)
    }
}
