import Foundation
import Combine

/// The 7 locales PasteQueue ships translations for — chosen to cover the largest
/// practical share of the internet's population across Asia, wealthier Europe, and
/// Latin America with a deliberately small string surface.
enum SupportedLanguage: String, CaseIterable, Identifiable {
    case en
    case ru
    case zhHans = "zh-Hans"
    case es
    case ja
    case de
    case ptBR = "pt-BR"

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .en: return "English"
        case .ru: return "Русский"
        case .zhHans: return "简体中文"
        case .es: return "Español"
        case .ja: return "日本語"
        case .de: return "Deutsch"
        case .ptBR: return "Português (Brasil)"
        }
    }
}

/// nil means "follow system" — no override is applied.
protocol LanguagePreferenceStoring: AnyObject {
    var preferredLanguageCode: String? { get set }
}

final class UserDefaultsLanguagePreferenceStore: LanguagePreferenceStoring {
    private static let key = "preferredLanguageCode"

    var preferredLanguageCode: String? {
        get { UserDefaults.standard.string(forKey: Self.key) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: Self.key)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.key)
            }
        }
    }
}

/// nil preferredLanguageCode means "follow system" — PopoverRootView skips the
/// .environment(\.locale:) override entirely in that case rather than forcing one.
final class LanguagePreferenceStore: ObservableObject {
    static let shared = LanguagePreferenceStore()

    @Published private(set) var preferredLanguageCode: String?

    private let store: LanguagePreferenceStoring

    convenience init() {
        self.init(store: UserDefaultsLanguagePreferenceStore())
    }

    init(store: LanguagePreferenceStoring) {
        self.store = store
        self.preferredLanguageCode = store.preferredLanguageCode
    }

    func setPreferredLanguageCode(_ code: String?) {
        preferredLanguageCode = code
        store.preferredLanguageCode = code
    }
}
