@testable import Vanto
import XCTest

final class TextJoinPreferenceTests: XCTestCase {
    func testPresetSeparatorsHaveExactLiteralValues() {
        XCTAssertEqual(TextSeparatorChoice.newline.separator(custom: "ignored"), "\n")
        XCTAssertEqual(TextSeparatorChoice.blankLine.separator(custom: "ignored"), "\n\n")
        XCTAssertEqual(TextSeparatorChoice.space.separator(custom: "ignored"), " ")
        XCTAssertEqual(TextSeparatorChoice.commaSpace.separator(custom: "ignored"), ", ")
        XCTAssertEqual(TextSeparatorChoice.none.separator(custom: "ignored"), "")
        XCTAssertEqual(TextSeparatorChoice.custom.separator(custom: " • "), " • ")
    }

    func testPreferenceDefaultsAndPersistsCustomSeparator() {
        let defaults = InMemoryUserDefaults()
        let store = UserDefaultsTextJoinPreferenceStore(defaults: defaults)

        XCTAssertEqual(store.load(), TextJoinPreference(choice: .newline, customSeparator: ""))

        let preference = TextJoinPreference(choice: .custom, customSeparator: " / ")
        store.save(preference)

        XCTAssertEqual(UserDefaultsTextJoinPreferenceStore(defaults: defaults).load(), preference)
    }
}

/// `UserDefaults` kept entirely in memory. A real suite, even after
/// `removePersistentDomain`, gets an empty `<suite>.plist` written to
/// ~/Library/Preferences by cfprefsd some seconds later, so every run would
/// leave a file behind. Typed getters such as `string(forKey:)` route through
/// `object(forKey:)`, so overriding the primitives is enough.
private final class InMemoryUserDefaults: UserDefaults {
    private var storage: [String: Any] = [:]

    override func object(forKey defaultName: String) -> Any? {
        storage[defaultName]
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        storage[defaultName] = value
    }

    override func removeObject(forKey defaultName: String) {
        storage[defaultName] = nil
    }
}
