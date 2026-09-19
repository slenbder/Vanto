@testable import PasteQueue
import XCTest

final class LanguagePreferenceStoreTests: XCTestCase {
    func testInitLoadsExistingPreferenceFromStore() {
        let store = MockLanguagePreferenceStore()
        store.preferredLanguageCode = "de"

        let preference = LanguagePreferenceStore(store: store)

        XCTAssertEqual(preference.preferredLanguageCode, "de")
    }

    func testDefaultsToFollowingSystemWhenNothingStored() {
        let preference = LanguagePreferenceStore(store: MockLanguagePreferenceStore())
        XCTAssertNil(preference.preferredLanguageCode)
    }

    func testSetPreferredLanguageCodePersistsThroughStore() {
        let store = MockLanguagePreferenceStore()
        let preference = LanguagePreferenceStore(store: store)

        preference.setPreferredLanguageCode("ja")

        XCTAssertEqual(preference.preferredLanguageCode, "ja")
        XCTAssertEqual(store.preferredLanguageCode, "ja")
    }

    func testSetPreferredLanguageCodeNilRevertsToFollowingSystem() {
        let store = MockLanguagePreferenceStore()
        store.preferredLanguageCode = "ru"
        let preference = LanguagePreferenceStore(store: store)

        preference.setPreferredLanguageCode(nil)

        XCTAssertNil(preference.preferredLanguageCode)
        XCTAssertNil(store.preferredLanguageCode)
    }

    func testSupportedLanguageCasesMatchRequiredLocaleSet() {
        let identifiers = Set(SupportedLanguage.allCases.map(\.rawValue))
        XCTAssertEqual(identifiers, ["en", "ru", "zh-Hans", "es", "ja", "de", "pt-BR"])
    }
}
