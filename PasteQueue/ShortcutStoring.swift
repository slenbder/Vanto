import Foundation
import os

private let logger = Logger(subsystem: "com.slenbder.pastequeue", category: "ShortcutStoring")

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
        do {
            return try JSONDecoder().decode(HotkeySpec.self, from: data)
        } catch {
            // Stored Data exists but no longer decodes (e.g. a future HotkeySpec schema
            // change) — falls back to nil (live default) rather than crashing, but logged so
            // this doesn't look identical to "user never set an override."
            let nsError = error as NSError
            logger.error("override(for:) decode failed action=\(action.rawValue, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)")
            return nil
        }
    }

    func setOverride(_ spec: HotkeySpec?, for action: ShortcutAction) {
        let key = Self.key(for: action)
        guard let spec else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        do {
            let data = try JSONEncoder().encode(spec)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            // HotkeyManager.overrides already reflects the new spec in memory (it updates
            // that before calling here) even though persistence failed — logged so a silent
            // revert to the factory default on next launch has a diagnosable cause instead
            // of looking like the user's custom binding just vanished.
            let nsError = error as NSError
            logger.error("setOverride(_:for:) encode failed action=\(action.rawValue, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)")
        }
    }
}
