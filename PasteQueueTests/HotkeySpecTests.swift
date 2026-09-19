@testable import PasteQueue
import AppKit
import Carbon
import XCTest

final class HotkeySpecTests: XCTestCase {
    // ANSI US physical keyCodes used throughout — matches the constants already relied on
    // by HotkeyManagerShortcutTests (keyCode 9 == V's fallback keyCode).
    private let keyCodeC: UInt16 = 8
    private let keyCodeV: UInt16 = 9
    private let keyCodeSpace: UInt16 = 49
    private let keyCodeTab: UInt16 = 48
    private let keyCodeEscape: UInt16 = 53
    private let keyCodeF1 = UInt16(kVK_F1)

    // MARK: - HotkeySpec equality/masking

    func testEqualSpecsIgnoreIrrelevantModifierBits() {
        let a = HotkeySpec(keyCode: keyCodeV, modifierFlags: [.control, .command])
        let b = HotkeySpec(keyCode: keyCodeV, modifierFlags: [.control, .command, .capsLock, .numericPad])

        XCTAssertEqual(a, b)
        XCTAssertTrue(ShortcutRecording.isDuplicate(a, b))
    }

    func testDifferentKeyCodesAreNotDuplicates() {
        let a = HotkeySpec(keyCode: keyCodeC, modifierFlags: [.command])
        let b = HotkeySpec(keyCode: keyCodeV, modifierFlags: [.command])

        XCTAssertFalse(ShortcutRecording.isDuplicate(a, b))
    }

    func testDisplayStringUsesFunctionKeySymbolAndModifierOrder() {
        let spec = HotkeySpec(keyCode: keyCodeF1, modifierFlags: [.command, .control, .shift, .option])
        XCTAssertEqual(spec.displayString, "⌃⌥⇧⌘F1")
    }

    // MARK: - classify(keyCode:modifierFlags:isRepeat:)

    func testClassifyRejectsRepeats() {
        let outcome = ShortcutRecording.classify(keyCode: keyCodeV, modifierFlags: [.command], isRepeat: true)
        XCTAssertEqual(outcome, .ignored)
    }

    func testClassifyTreatsEscapeAsCancelRegardlessOfModifiers() {
        XCTAssertEqual(
            ShortcutRecording.classify(keyCode: keyCodeEscape, modifierFlags: [], isRepeat: false),
            .cancelled
        )
        XCTAssertEqual(
            ShortcutRecording.classify(keyCode: keyCodeEscape, modifierFlags: [.command, .control], isRepeat: false),
            .cancelled
        )
    }

    func testClassifyIgnoresBareKeyWithNoModifier() {
        let outcome = ShortcutRecording.classify(keyCode: keyCodeV, modifierFlags: [], isRepeat: false)
        XCTAssertEqual(outcome, .ignored)
    }

    func testClassifyIgnoresBareModifierPlusUnsupportedKey() {
        XCTAssertEqual(
            ShortcutRecording.classify(keyCode: keyCodeSpace, modifierFlags: [.command], isRepeat: false),
            .ignored
        )
        XCTAssertEqual(
            ShortcutRecording.classify(keyCode: keyCodeTab, modifierFlags: [.command], isRepeat: false),
            .ignored
        )
    }

    func testClassifyAcceptsSingleBareModifierPlusLetter() {
        let outcome = ShortcutRecording.classify(keyCode: keyCodeV, modifierFlags: [.command], isRepeat: false)
        XCTAssertEqual(outcome, .captured(HotkeySpec(keyCode: keyCodeV, modifierFlags: [.command])))
    }

    func testClassifyAcceptsFunctionKeyWithModifier() {
        let outcome = ShortcutRecording.classify(keyCode: keyCodeF1, modifierFlags: [.control], isRepeat: false)
        XCTAssertEqual(outcome, .captured(HotkeySpec(keyCode: keyCodeF1, modifierFlags: [.control])))
    }

    func testClassifyMasksIrrelevantModifierBitsInCapturedSpec() {
        let outcome = ShortcutRecording.classify(
            keyCode: keyCodeV,
            modifierFlags: [.command, .capsLock, .function],
            isRepeat: false
        )
        XCTAssertEqual(outcome, .captured(HotkeySpec(keyCode: keyCodeV, modifierFlags: [.command])))
    }

    // MARK: - isSystemCopyPasteCutConflict

    func testSystemConflictDetectsBareCommandCVX() {
        XCTAssertTrue(ShortcutRecording.isSystemCopyPasteCutConflict(HotkeySpec(keyCode: keyCodeC, modifierFlags: [.command])))
        XCTAssertTrue(ShortcutRecording.isSystemCopyPasteCutConflict(HotkeySpec(keyCode: keyCodeV, modifierFlags: [.command])))
    }

    func testSystemConflictIgnoresAdditionalModifiers() {
        // ⌃⌘V is the app's own default binding, not a bare system Paste conflict.
        XCTAssertFalse(
            ShortcutRecording.isSystemCopyPasteCutConflict(HotkeySpec(keyCode: keyCodeV, modifierFlags: [.control, .command]))
        )
    }

    func testSystemConflictIgnoresUnrelatedLetters() {
        XCTAssertFalse(
            ShortcutRecording.isSystemCopyPasteCutConflict(HotkeySpec(keyCode: keyCodeF1, modifierFlags: [.command]))
        )
    }
}
