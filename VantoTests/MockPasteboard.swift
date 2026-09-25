@testable import Vanto
import AppKit

final class MockPasteboard: PasteboardProviding {
    var changeCount: Int = 0
    var stringValue: String?
    var fileURLs: [URL] = []
    var images: [NSImage] = []
    var replaceContentsResult = true
    private(set) var writtenItems: [ClipboardItem] = []
    private(set) var replaceContentsCallCount = 0
    private(set) var readFileURLsCallCount = 0

    func readFileURLs() -> [URL] {
        readFileURLsCallCount += 1
        return fileURLs
    }

    func readImages() -> [NSImage] {
        images
    }

    func string(forType type: NSPasteboard.PasteboardType) -> String? {
        stringValue
    }

    func replaceContents(with item: ClipboardItem) -> Bool {
        replaceContentsCallCount += 1
        fileURLs = []
        images = []
        stringValue = nil
        changeCount += 1

        guard replaceContentsResult else { return false }

        switch item {
        case .text(let string):
            stringValue = string
        case .image(let image):
            images = [image]
        case .file(let url, _):
            fileURLs = [url]
        }

        writtenItems.append(item)
        return true
    }
}

final class MockLaunchAtLoginService: LaunchAtLoginProviding {
    var status: LaunchAtLoginStatus = .notRegistered
    var userIntendedEnabled = false
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    func register() throws {
        registerCallCount += 1
        status = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        status = .notRegistered
    }

    func setUserIntendedEnabled(_ enabled: Bool) {
        userIntendedEnabled = enabled
    }
}

final class CommandVRecorder {
    var shouldCreateEvents = true
    private(set) var factoryRequestCount = 0
    private(set) var requestCount = 0

    func makePoster() -> PasteStack.CommandVEventPoster? {
        factoryRequestCount += 1
        guard shouldCreateEvents else { return nil }
        return { [weak self] in
            self?.requestCount += 1
        }
    }
}

final class CleanupSchedulerRecorder {
    private(set) var delays: [TimeInterval] = []
    private var actions: [() -> Void] = []

    func schedule(delay: TimeInterval, action: @escaping () -> Void) {
        delays.append(delay)
        actions.append(action)
    }

    func runAll() {
        let pendingActions = actions
        actions.removeAll()
        pendingActions.forEach { $0() }
    }
}

final class MockShortcutStore: ShortcutStoring {
    private var overrides: [ShortcutAction: HotkeySpec] = [:]
    private(set) var setOverrideCallCount = 0

    func override(for action: ShortcutAction) -> HotkeySpec? {
        overrides[action]
    }

    func setOverride(_ spec: HotkeySpec?, for action: ShortcutAction) {
        setOverrideCallCount += 1
        overrides[action] = spec
    }
}

final class MockLanguagePreferenceStore: LanguagePreferenceStoring {
    var preferredLanguageCode: String?
}
