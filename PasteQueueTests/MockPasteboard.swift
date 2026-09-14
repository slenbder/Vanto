@testable import PasteQueue
import AppKit

final class MockPasteboard: PasteboardProviding {
    var changeCount: Int = 0
    var stringValue: String?
    var fileURLs: [URL] = []
    var images: [NSImage] = []
    private(set) var writtenItems: [ClipboardItem] = []

    func readFileURLs() -> [URL] {
        fileURLs
    }

    func readImages() -> [NSImage] {
        images
    }

    func string(forType type: NSPasteboard.PasteboardType) -> String? {
        stringValue
    }

    func replaceContents(with item: ClipboardItem) {
        fileURLs = []
        images = []
        stringValue = nil

        switch item {
        case .text(let string):
            stringValue = string
        case .image(let image):
            images = [image]
        case .file(let url, _):
            fileURLs = [url]
        }

        writtenItems.append(item)
        changeCount += 1
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
    private(set) var requestCount = 0

    func send() {
        requestCount += 1
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
