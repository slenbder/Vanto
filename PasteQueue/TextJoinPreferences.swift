import Foundation

enum TextSeparatorChoice: String, CaseIterable, Identifiable {
    case newline
    case blankLine
    case space
    case commaSpace
    case none
    case custom

    var id: String { rawValue }

    func separator(custom: String) -> String {
        switch self {
        case .newline: return "\n"
        case .blankLine: return "\n\n"
        case .space: return " "
        case .commaSpace: return ", "
        case .none: return ""
        case .custom: return custom
        }
    }
}

struct TextJoinPreference: Equatable {
    let choice: TextSeparatorChoice
    let customSeparator: String
}

protocol TextJoinPreferenceStoring {
    func load() -> TextJoinPreference
    func save(_ preference: TextJoinPreference)
}

final class UserDefaultsTextJoinPreferenceStore: TextJoinPreferenceStoring {
    private enum Key {
        static let choice = "textJoinSeparatorChoice"
        static let custom = "textJoinCustomSeparator"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> TextJoinPreference {
        let choice = defaults.string(forKey: Key.choice)
            .flatMap(TextSeparatorChoice.init(rawValue:)) ?? .newline
        return TextJoinPreference(
            choice: choice,
            customSeparator: defaults.string(forKey: Key.custom) ?? ""
        )
    }

    func save(_ preference: TextJoinPreference) {
        defaults.set(preference.choice.rawValue, forKey: Key.choice)
        defaults.set(preference.customSeparator, forKey: Key.custom)
    }
}
