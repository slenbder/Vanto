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

    func testExplicitLanguageSelectsLocalizedBundleForDynamicStrings() {
        let locale = Locale(identifier: "ru")
        let bundle = AppLocalization.bundle(for: "ru")

        XCTAssertEqual(
            String(localized: "PasteQueue, idle", bundle: bundle, locale: locale),
            "PasteQueue, ожидание"
        )
        XCTAssertEqual(
            String(localized: "PasteQueue, recording, \(2) items in queue", bundle: bundle, locale: locale),
            "PasteQueue, запись, 2 элемента в очереди"
        )
        let actionName = ShortcutAction.pasteNext.displayName(locale: locale, bundle: bundle)
        XCTAssertEqual(actionName, "Вставить следующий")
        XCTAssertEqual(
            String(localized: "Already used by \(actionName).", bundle: bundle, locale: locale),
            "Уже занято действием «Вставить следующий»."
        )
    }

    func testTrialDaysLeftUsesPluralForms() {
        let english = AppLocalization.bundle(for: "en")
        let englishLocale = Locale(identifier: "en")
        XCTAssertEqual(
            String(localized: "Trial: \(1) days left", bundle: english, locale: englishLocale),
            "Trial: 1 day left"
        )
        XCTAssertEqual(
            String(localized: "Trial: \(3) days left", bundle: english, locale: englishLocale),
            "Trial: 3 days left"
        )

        let russian = AppLocalization.bundle(for: "ru")
        let russianLocale = Locale(identifier: "ru")
        XCTAssertEqual(
            String(localized: "Trial: \(1) days left", bundle: russian, locale: russianLocale),
            "Пробный период: остался 1 день"
        )
        XCTAssertEqual(
            String(localized: "Trial: \(3) days left", bundle: russian, locale: russianLocale),
            "Пробный период: осталось 3 дня"
        )
        XCTAssertEqual(
            String(localized: "Trial: \(7) days left", bundle: russian, locale: russianLocale),
            "Пробный период: осталось 7 дней"
        )
    }
}
