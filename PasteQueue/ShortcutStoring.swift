import Foundation

/// Persists per-action shortcut overrides. `nil` means "no override — use the live,
/// layout-tracked default" (see ShortcutAction.defaultCharacter).
protocol ShortcutStoring: AnyObject {
    func override(for action: ShortcutAction) -> HotkeySpec?
    func setOverride(_ spec: HotkeySpec?, for action: ShortcutAction)
}

final class UserDefaultsShortcutStore: ShortcutStoring {
    private static func key(for action: ShortcutAction) -> String {
        "shortcutOverride.\(action.rawValue)"
    }

    func override(for action: ShortcutAction) -> HotkeySpec? {
        guard let data = UserDefaults.standard.data(forKey: Self.key(for: action)) else { return nil }
        return try? JSONDecoder().decode(HotkeySpec.self, from: data)
    }

    func setOverride(_ spec: HotkeySpec?, for action: ShortcutAction) {
        let key = Self.key(for: action)
        guard let spec else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        guard let data = try? JSONEncoder().encode(spec) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
