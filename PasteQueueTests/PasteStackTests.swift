@testable import PasteQueue
import AppKit
import XCTest

final class PasteStackTests: XCTestCase {
    private var testRoot: URL!

    override func setUpWithError() throws {
        testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteQueueTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: testRoot)
        testRoot = nil
    }

    private func makeStack(
        pasteboard: MockPasteboard = MockPasteboard(),
        storageDirectory: URL? = nil,
        commandVRecorder: CommandVRecorder = CommandVRecorder()
    ) -> PasteStack {
        PasteStack(
            pasteboard: pasteboard,
            clipboardFilesDirectory: storageDirectory ?? testRoot.appendingPathComponent(UUID().uuidString),
            sendCommandV: commandVRecorder.send,
            scheduleCleanup: { _, action in action() },
            accessibilityTrustProvider: { false },
            launchAtLoginService: MockLaunchAtLoginService(),
            automaticallyPolls: false
        )
    }

    private func makeImage(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        color.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 4, height: 4)).fill()
        image.unlockFocus()
        return image
    }

    private func writeSourceFile(named name: String, contents: String) throws -> URL {
        let sources = testRoot.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let url = sources.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testFIFOOrder() {
        let mock = MockPasteboard()
        let recorder = CommandVRecorder()
        let stack = makeStack(pasteboard: mock, commandVRecorder: recorder)

        mock.changeCount = 1
        mock.stringValue = "A"
        stack.checkPasteboard()
        mock.changeCount = 2
        mock.stringValue = "B"
        stack.checkPasteboard()
        mock.changeCount = 3
        mock.stringValue = "C"
        stack.checkPasteboard()

        XCTAssertEqual(stack.queue.map(\.content), [.text("A"), .text("B"), .text("C")])

        stack.pasteNext()
        XCTAssertEqual(stack.queue.map(\.content), [.text("B"), .text("C")], "A should have been popped first")
        stack.pasteNext()
        XCTAssertEqual(stack.queue.map(\.content), [.text("C")], "B should have been popped second")
        stack.pasteNext()

        XCTAssertTrue(stack.queue.isEmpty, "C should have been popped third")
        XCTAssertEqual(mock.writtenItems, [.text("A"), .text("B"), .text("C")])
        XCTAssertEqual(recorder.requestCount, 3)
    }

    func testOwnPasteboardWriteIsNotRequeuedOnNextPoll() {
        let mock = MockPasteboard()
        let stack = makeStack(pasteboard: mock)

        mock.changeCount = 1
        mock.stringValue = "A"
        stack.checkPasteboard()
        mock.changeCount = 2
        mock.stringValue = "B"
        stack.checkPasteboard()

        stack.pasteNext()
        stack.checkPasteboard()

        XCTAssertEqual(stack.queue.map(\.content), [.text("B")])
        XCTAssertEqual(mock.writtenItems, [.text("A")])
    }

    func testRemoveByIdDeletesTheCorrectDuplicate() {
        let mock = MockPasteboard()
        let stack = makeStack(pasteboard: mock)

        for (changeCount, value) in [(1, "Считаю"), (2, "Считаю"), (3, "C")] {
            mock.changeCount = changeCount
            mock.stringValue = value
            stack.checkPasteboard()
        }

        XCTAssertEqual(stack.queue.count, 3)
        let middleID = stack.queue[1].id
        stack.remove(id: middleID)

        XCTAssertEqual(stack.queue.map(\.content), [.text("Считаю"), .text("C")])
        XCTAssertFalse(stack.queue.contains { $0.id == middleID })
    }

    func testEmptyStringsAreNotAddedToQueue() {
        let mock = MockPasteboard()
        let stack = makeStack(pasteboard: mock)

        mock.changeCount = 1
        mock.stringValue = ""
        stack.checkPasteboard()

        XCTAssertTrue(stack.queue.isEmpty)
    }

    func testPasteNextOnEmptyQueueDoesNotCrash() {
        let mock = MockPasteboard()
        let recorder = CommandVRecorder()
        let stack = makeStack(pasteboard: mock, commandVRecorder: recorder)

        stack.pasteNext()
        stack.pasteNext()

        XCTAssertTrue(stack.queue.isEmpty)
        XCTAssertTrue(mock.writtenItems.isEmpty)
        XCTAssertEqual(recorder.requestCount, 0)
    }

    func testClearEmptiesTheQueue() {
        let mock = MockPasteboard()
        let stack = makeStack(pasteboard: mock)

        mock.changeCount = 1
        mock.stringValue = "A"
        stack.checkPasteboard()
        mock.changeCount = 2
        mock.stringValue = "B"
        stack.checkPasteboard()
        XCTAssertEqual(stack.queue.count, 2)

        stack.clear()

        XCTAssertTrue(stack.queue.isEmpty)
    }

    func testToggleCollectingDoesNotReAddStaleClipboardContentOnRestart() {
        let mock = MockPasteboard()
        mock.changeCount = 1
        mock.stringValue = "A"
        let stack = makeStack(pasteboard: mock)

        stack.toggleCollecting()
        XCTAssertTrue(stack.isCollecting)

        mock.changeCount = 2
        stack.checkPasteboard()
        XCTAssertEqual(stack.queue.map(\.content), [.text("A")])

        stack.toggleCollecting()
        XCTAssertFalse(stack.isCollecting)
        stack.toggleCollecting()
        XCTAssertTrue(stack.isCollecting)
        stack.checkPasteboard()
        XCTAssertEqual(stack.queue.map(\.content), [.text("A")])

        mock.changeCount = 3
        mock.stringValue = "B"
        stack.checkPasteboard()
        XCTAssertEqual(stack.queue.map(\.content), [.text("A"), .text("B")])
    }

    func testMultipleImagesAreAllQueued() {
        let mock = MockPasteboard()
        mock.images = [makeImage(.red), makeImage(.blue)]
        let stack = makeStack(pasteboard: mock)

        mock.changeCount = 1
        stack.checkPasteboard()

        XCTAssertEqual(stack.queue.count, 2)
        for entry in stack.queue {
            guard case .image = entry.content else {
                return XCTFail("expected every queued entry to be an image")
            }
        }
    }

    func testMultipleFilesAreAllQueuedAndCopiedExactly() throws {
        let file1 = try writeSourceFile(named: "first.txt", contents: "first bytes")
        let file2 = try writeSourceFile(named: "second.txt", contents: "second bytes")
        let mock = MockPasteboard()
        mock.fileURLs = [file1, file2]
        let stack = makeStack(pasteboard: mock)

        mock.changeCount = 1
        stack.checkPasteboard()

        XCTAssertEqual(stack.queue.count, 2)
        let storedFiles = try stack.queue.map { entry -> (URL, String) in
            guard case .file(let url, let originalFilename) = entry.content else {
                throw TestError.expectedFile
            }
            return (url, originalFilename)
        }
        XCTAssertEqual(storedFiles.map { $0.1 }, [file1.lastPathComponent, file2.lastPathComponent])
        XCTAssertEqual(try String(contentsOf: storedFiles[0].0, encoding: .utf8), "first bytes")
        XCTAssertEqual(try String(contentsOf: storedFiles[1].0, encoding: .utf8), "second bytes")

        stack.clear()
    }

    func testFileCopyFailureDoesNotBlockSubsequentFiles() throws {
        let missingFile = testRoot.appendingPathComponent("does-not-exist.txt")
        let goodFile = try writeSourceFile(named: "good.txt", contents: "still here")
        let mock = MockPasteboard()
        mock.fileURLs = [missingFile, goodFile]
        let stack = makeStack(pasteboard: mock)

        mock.changeCount = 1
        stack.checkPasteboard()

        XCTAssertEqual(stack.queue.count, 1)
        guard case .file(let storedURL, let originalFilename) = stack.queue.first?.content else {
            return XCTFail("expected the surviving entry to be a file")
        }
        XCTAssertEqual(originalFilename, goodFile.lastPathComponent)
        XCTAssertEqual(try String(contentsOf: storedURL, encoding: .utf8), "still here")

        stack.clear()
    }

    func testSeparateStorageCleanupDoesNotDeleteAnotherStacksFiles() throws {
        let source1 = try writeSourceFile(named: "one.txt", contents: "owned by one")
        let source2 = try writeSourceFile(named: "two.txt", contents: "owned by two")
        let storage1 = testRoot.appendingPathComponent("StorageOne", isDirectory: true)
        let storage2 = testRoot.appendingPathComponent("StorageTwo", isDirectory: true)

        let mock1 = MockPasteboard()
        mock1.fileURLs = [source1]
        let stack1 = makeStack(pasteboard: mock1, storageDirectory: storage1)
        mock1.changeCount = 1
        stack1.checkPasteboard()
        guard case .file(let storedByFirst, _) = stack1.queue.first?.content else {
            return XCTFail("expected first stack to store a file")
        }

        let mock2 = MockPasteboard()
        mock2.fileURLs = [source2]
        let stack2 = makeStack(pasteboard: mock2, storageDirectory: storage2)
        mock2.changeCount = 1
        stack2.checkPasteboard()
        stack2.clear()

        XCTAssertTrue(FileManager.default.fileExists(atPath: storedByFirst.path))
        XCTAssertEqual(try String(contentsOf: storedByFirst, encoding: .utf8), "owned by one")
    }

    func testFilePasteUsesInjectedCleanupSchedulerAndCommandSender() throws {
        let source = try writeSourceFile(named: "paste.txt", contents: "paste bytes")
        let mock = MockPasteboard()
        mock.fileURLs = [source]
        let recorder = CommandVRecorder()
        let stack = makeStack(pasteboard: mock, commandVRecorder: recorder)
        mock.changeCount = 1
        stack.checkPasteboard()
        guard case .file(let storedURL, _) = stack.queue.first?.content else {
            return XCTFail("expected a stored file")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))

        stack.pasteNext()

        XCTAssertFalse(FileManager.default.fileExists(atPath: storedURL.path))
        XCTAssertEqual(recorder.requestCount, 1)
        XCTAssertEqual(mock.writtenItems.count, 1)
    }

    func testTestHostRuntimeIsDetected() {
        XCTAssertTrue(AppRuntime.isRunningTests)
    }

    private enum TestError: Error {
        case expectedFile
    }
}
