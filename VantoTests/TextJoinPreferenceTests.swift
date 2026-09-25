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
        let suiteName = "VantoTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("could not create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsTextJoinPreferenceStore(defaults: defaults)

        XCTAssertEqual(store.load(), TextJoinPreference(choice: .newline, customSeparator: ""))

        let preference = TextJoinPreference(choice: .custom, customSeparator: " / ")
        store.save(preference)

        XCTAssertEqual(UserDefaultsTextJoinPreferenceStore(defaults: defaults).load(), preference)
    }
}
