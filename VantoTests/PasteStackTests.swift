@testable import Vanto
import AppKit
import Carbon
import XCTest

final class PasteStackTests: XCTestCase {
    private var testRoot: URL!

    override func setUpWithError() throws {
        testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("VantoTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: testRoot)
        testRoot = nil
    }

    private func makeStack(
        pasteboard: MockPasteboard = MockPasteboard(),
        storageDirectory: URL? = nil,
        commandVRecorder: CommandVRecorder = CommandVRecorder(),
        scheduleCleanup: @escaping PasteStack.CleanupScheduler = { _, action in action() },
        accessibilityTrustProvider: @escaping () -> Bool = { true }
    ) -> PasteStack {
        PasteStack(
            pasteboard: pasteboard,
            clipboardFilesDirectory: storageDirectory ?? testRoot.appendingPathComponent(UUID().uuidString),
            commandVEventFactory: commandVRecorder.makePoster,
            scheduleCleanup: scheduleCleanup,
            accessibilityTrustProvider: accessibilityTrustProvider,
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

    private func writeSourceFile(
        named name: String,
        contents: String,
        subdirectory: String = "Sources"
    ) throws -> URL {
        let sources = testRoot.appendingPathComponent(subdirectory, isDirectory: true)
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

    func testPasteNextSynchronouslyCapturesPendingItemWhenCollectingAndQueueIsEmpty() {
        let mock = MockPasteboard()
        let recorder = CommandVRecorder()
        let stack = makeStack(pasteboard: mock, commandVRecorder: recorder)
        stack.toggleCollecting()

        mock.changeCount = 1
        mock.stringValue = "A"

        stack.pasteNext()

        XCTAssertEqual(mock.writtenItems, [.text("A")])
        XCTAssertEqual(recorder.requestCount, 1)
        XCTAssertTrue(stack.queue.isEmpty)
        XCTAssertFalse(stack.isCollecting)
    }

    func testPasteNextCapturesPendingItemAfterExistingQueueBeforePastingFIFO() {
        let mock = MockPasteboard()
        let recorder = CommandVRecorder()
        let stack = makeStack(pasteboard: mock, commandVRecorder: recorder)
        stack.toggleCollecting()

        mock.changeCount = 1
        mock.stringValue = "A"
        stack.checkPasteboard()
        mock.changeCount = 2
        mock.stringValue = "B"

        stack.pasteNext()

        XCTAssertEqual(mock.writtenItems, [.text("A")])
        XCTAssertEqual(recorder.requestCount, 1)
        XCTAssertEqual(stack.queue.map(\.content), [.text("B")])
        XCTAssertTrue(stack.isCollecting)

        stack.checkPasteboard()

        XCTAssertEqual(stack.queue.map(\.content), [.text("B")])
    }

    func testPasteNextDoesNotCaptureExternalPasteboardWhenCollectionIsOff() {
        let mock = MockPasteboard()
        let recorder = CommandVRecorder()
        let stack = makeStack(pasteboard: mock, commandVRecorder: recorder)

        mock.changeCount = 1
        mock.stringValue = "A"

        stack.pasteNext()

        XCTAssertTrue(stack.queue.isEmpty)
        XCTAssertTrue(mock.writtenItems.isEmpty)
        XCTAssertEqual(recorder.requestCount, 0)
    }

    func testPasteNextPreservesHeadWhenAccessibilityIsUnavailable() {
        let mock = MockPasteboard()
        let recorder = CommandVRecorder()
        let cleanup = CleanupSchedulerRecorder()
        let stack = makeStack(
            pasteboard: mock,
            commandVRecorder: recorder,
            scheduleCleanup: cleanup.schedule,
            accessibilityTrustProvider: { false }
        )
        mock.changeCount = 1
        mock.stringValue = "A"
        stack.checkPasteboard()
        let queuedID = stack.queue[0].id
        stack.toggleCollecting()

        let result = stack.pasteNext()

        XCTAssertEqual(result, .accessibilityUnavailable)
        XCTAssertEqual(stack.queue.first?.id, queuedID)
        XCTAssertEqual(stack.queue.map(\.content), [.text("A")])
        XCTAssertEqual(mock.replaceContentsCallCount, 0)
        XCTAssertEqual(recorder.factoryRequestCount, 0)
        XCTAssertEqual(recorder.requestCount, 0)
        XCTAssertTrue(cleanup.delays.isEmpty)
        XCTAssertTrue(stack.isCollecting)
    }

    func testPasteNextPreservesHeadWhenCommandVEventCreationFails() {
        let mock = MockPasteboard()
        let recorder = CommandVRecorder()
        recorder.shouldCreateEvents = false
        let cleanup = CleanupSchedulerRecorder()
        let stack = makeStack(
            pasteboard: mock,
            commandVRecorder: recorder,
            scheduleCleanup: cleanup.schedule
        )
        mock.changeCount = 1
        mock.stringValue = "A"
        stack.checkPasteboard()
        let queuedID = stack.queue[0].id
        stack.toggleCollecting()

        let result = stack.pasteNext()

        XCTAssertEqual(result, .eventCreationFailed)
        XCTAssertEqual(stack.queue.first?.id, queuedID)
        XCTAssertEqual(stack.queue.map(\.content), [.text("A")])
        XCTAssertEqual(mock.replaceContentsCallCount, 0)
        XCTAssertEqual(recorder.factoryRequestCount, 1)
        XCTAssertEqual(recorder.requestCount, 0)
        XCTAssertTrue(cleanup.delays.isEmpty)
        XCTAssertTrue(stack.isCollecting)
    }

    func testPasteNextPreservesFileCacheWhenPasteboardWriteFails() throws {
        let source = try writeSourceFile(named: "keep-on-failure.txt", contents: "cached bytes")
        let mock = MockPasteboard()
        mock.fileURLs = [source]
        let recorder = CommandVRecorder()
        let cleanup = CleanupSchedulerRecorder()
        let stack = makeStack(
            pasteboard: mock,
            commandVRecorder: recorder,
            scheduleCleanup: cleanup.schedule
        )
        mock.changeCount = 1
        stack.checkPasteboard()
        guard let queuedItem = stack.queue.first,
              case .file(let storedURL, _) = queuedItem.content else {
            return XCTFail("expected a stored file")
        }
        let itemDirectory = storedURL.deletingLastPathComponent()
        stack.toggleCollecting()
        mock.replaceContentsResult = false

        let result = stack.pasteNext()

        XCTAssertEqual(result, .pasteboardWriteFailed)
        XCTAssertEqual(stack.queue.first?.id, queuedItem.id)
        XCTAssertEqual(mock.replaceContentsCallCount, 1)
        XCTAssertTrue(mock.writtenItems.isEmpty)
        XCTAssertEqual(recorder.factoryRequestCount, 1)
        XCTAssertEqual(recorder.requestCount, 0)
        XCTAssertTrue(cleanup.delays.isEmpty)
        XCTAssertTrue(stack.isCollecting)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: itemDirectory.path))

        let readsAfterFailedWrite = mock.readFileURLsCallCount
        stack.checkPasteboard()
        XCTAssertEqual(mock.readFileURLsCallCount, readsAfterFailedWrite)
        XCTAssertEqual(stack.queue.first?.id, queuedItem.id)
    }

    func testCommandPostedRemovesOnlyFIFOHeadAndStopsCollectionWhenDrained() {
        let mock = MockPasteboard()
        let recorder = CommandVRecorder()
        let cleanup = CleanupSchedulerRecorder()
        let stack = makeStack(
            pasteboard: mock,
            commandVRecorder: recorder,
            scheduleCleanup: cleanup.schedule
        )
        mock.changeCount = 1
        mock.stringValue = "A"
        stack.checkPasteboard()
        mock.changeCount = 2
        mock.stringValue = "B"
        stack.checkPasteboard()
        let firstID = stack.queue[0].id
        let secondID = stack.queue[1].id
        stack.toggleCollecting()

        let firstResult = stack.pasteNext()

        XCTAssertEqual(firstResult, .commandPosted)
        XCTAssertEqual(stack.queue.map(\.id), [secondID])
        XCTAssertFalse(stack.queue.contains { $0.id == firstID })
        XCTAssertEqual(mock.writtenItems, [.text("A")])
        XCTAssertEqual(recorder.requestCount, 1)
        XCTAssertEqual(cleanup.delays, [2])
        XCTAssertTrue(stack.isCollecting)

        let secondResult = stack.pasteNext()

        XCTAssertEqual(secondResult, .commandPosted)
        XCTAssertTrue(stack.queue.isEmpty)
        XCTAssertEqual(mock.writtenItems, [.text("A"), .text("B")])
        XCTAssertEqual(recorder.requestCount, 2)
        XCTAssertEqual(cleanup.delays, [2, 2])
        XCTAssertFalse(stack.isCollecting)
    }

    func testPasteAllTextUsesQueueOrderAndOneCommandWithoutTrimmingFragments() {
        let mock = MockPasteboard()
        let recorder = CommandVRecorder()
        let cleanup = CleanupSchedulerRecorder()
        let stack = makeStack(
            pasteboard: mock,
            commandVRecorder: recorder,
            scheduleCleanup: cleanup.schedule
        )
        stack.queue = [
            QueuedClipboardItem(content: .text(" A ")),
            QueuedClipboardItem(content: .text("B\n")),
            QueuedClipboardItem(content: .text("C")),
        ]
        stack.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        stack.toggleCollecting()
        let expectedIDs = stack.queue.map(\.id)

        let result = stack.pasteAllText(separator: " / ", expectedIDs: expectedIDs)

        XCTAssertEqual(result, .commandPosted)
        XCTAssertEqual(mock.writtenItems, [.text("C /  A  / B\n")])
        XCTAssertEqual(mock.replaceContentsCallCount, 1)
        XCTAssertEqual(recorder.requestCount, 1)
        XCTAssertTrue(cleanup.delays.isEmpty)
        XCTAssertTrue(stack.queue.isEmpty)
        XCTAssertFalse(stack.isCollecting)

        stack.checkPasteboard()
        XCTAssertTrue(stack.queue.isEmpty, "The combined paste must not be captured as a new copy")
    }

    func testPasteAllTextRejectsMixedQueueWithoutChangingPasteboardOrFileCache() throws {
        let source = try writeSourceFile(named: "attachment.txt", contents: "file bytes")
        let mock = MockPasteboard()
        mock.fileURLs = [source]
        let recorder = CommandVRecorder()
        let stack = makeStack(pasteboard: mock, commandVRecorder: recorder)
        mock.changeCount = 1
        stack.checkPasteboard()
        guard case .file(let storedURL, _) = stack.queue[0].content else {
            return XCTFail("expected a cached file")
        }
        stack.queue.append(QueuedClipboardItem(content: .text("A")))
        let expectedIDs = stack.queue.map(\.id)

        let result = stack.pasteAllText(separator: "\n", expectedIDs: expectedIDs)

        XCTAssertEqual(result, .containsNonText)
        XCTAssertEqual(stack.queue.map(\.id), expectedIDs)
        XCTAssertEqual(mock.replaceContentsCallCount, 0)
        XCTAssertEqual(recorder.factoryRequestCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))
        stack.clear()
    }

    func testPasteAllTextCapturesPendingCopyAndRequiresUpdatedPreview() {
        let mock = MockPasteboard()
        let recorder = CommandVRecorder()
        let stack = makeStack(pasteboard: mock, commandVRecorder: recorder)
        stack.queue = [
            QueuedClipboardItem(content: .text("A")),
            QueuedClipboardItem(content: .text("B")),
        ]
        stack.toggleCollecting()
        let expectedIDs = stack.queue.map(\.id)
        mock.changeCount += 1
        mock.stringValue = "C"

        let result = stack.pasteAllText(separator: ", ", expectedIDs: expectedIDs)

        XCTAssertEqual(result, .queueChanged)
        XCTAssertEqual(stack.queue.map(\.content), [.text("A"), .text("B"), .text("C")])
        XCTAssertEqual(mock.replaceContentsCallCount, 0)
        XCTAssertEqual(recorder.factoryRequestCount, 0)
        XCTAssertTrue(stack.isCollecting)
    }

    func testPasteAllTextPreservesQueueWhenPreparationOrWriteFails() {
        for failure in [PasteAttemptResult.accessibilityUnavailable, .eventCreationFailed, .pasteboardWriteFailed] {
            let mock = MockPasteboard()
            let recorder = CommandVRecorder()
            let stack = makeStack(
                pasteboard: mock,
                commandVRecorder: recorder,
                accessibilityTrustProvider: { failure != .accessibilityUnavailable }
            )
            stack.queue = [
                QueuedClipboardItem(content: .text("A")),
                QueuedClipboardItem(content: .text("B")),
            ]
            stack.toggleCollecting()
            if failure == .eventCreationFailed { recorder.shouldCreateEvents = false }
            if failure == .pasteboardWriteFailed { mock.replaceContentsResult = false }
            let expectedIDs = stack.queue.map(\.id)

            let result = stack.pasteAllText(separator: "\n", expectedIDs: expectedIDs)

            XCTAssertEqual(result, failure)
            XCTAssertEqual(stack.queue.map(\.id), expectedIDs)
            XCTAssertTrue(stack.isCollecting)
            XCTAssertEqual(recorder.requestCount, 0)
            XCTAssertTrue(mock.writtenItems.isEmpty)
        }
    }

    func testPasteAllTextRejectsEmptyOrReorderedQueue() {
        let mock = MockPasteboard()
        let recorder = CommandVRecorder()
        let stack = makeStack(pasteboard: mock, commandVRecorder: recorder)
        XCTAssertEqual(stack.pasteAllText(separator: " ", expectedIDs: []), .queueEmpty)

        stack.queue = [
            QueuedClipboardItem(content: .text("A")),
            QueuedClipboardItem(content: .text("B")),
        ]
        let expectedIDs = stack.queue.map(\.id)
        stack.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)

        XCTAssertEqual(stack.pasteAllText(separator: " ", expectedIDs: expectedIDs), .queueChanged)
        XCTAssertEqual(mock.replaceContentsCallCount, 0)
        XCTAssertEqual(recorder.factoryRequestCount, 0)
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
        XCTAssertEqual(storedFiles.map { $0.0.lastPathComponent }, ["first.txt", "second.txt"])
        XCTAssertNotEqual(storedFiles[0].0.deletingLastPathComponent(), storedFiles[1].0.deletingLastPathComponent())
        XCTAssertEqual(try String(contentsOf: storedFiles[0].0, encoding: .utf8), "first bytes")
        XCTAssertEqual(try String(contentsOf: storedFiles[1].0, encoding: .utf8), "second bytes")

        stack.clear()
    }

    func testFileCopyFailureDoesNotBlockSubsequentFiles() throws {
        let missingFile = testRoot.appendingPathComponent("does-not-exist.txt")
        let goodFile = try writeSourceFile(named: "good.txt", contents: "still here")
        let storage = testRoot.appendingPathComponent("FailureStorage", isDirectory: true)
        let mock = MockPasteboard()
        mock.fileURLs = [missingFile, goodFile]
        let stack = makeStack(pasteboard: mock, storageDirectory: storage)

        mock.changeCount = 1
        stack.checkPasteboard()

        XCTAssertEqual(stack.queue.count, 1)
        guard case .file(let storedURL, let originalFilename) = stack.queue.first?.content else {
            return XCTFail("expected the surviving entry to be a file")
        }
        XCTAssertEqual(originalFilename, goodFile.lastPathComponent)
        XCTAssertEqual(storedURL.lastPathComponent, goodFile.lastPathComponent)
        XCTAssertEqual(try String(contentsOf: storedURL, encoding: .utf8), "still here")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: storage, includingPropertiesForKeys: nil).count, 1)

        stack.clear()
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(at: storage, includingPropertiesForKeys: nil).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: goodFile.path))
    }

    func testEqualFilenamesUseSeparateItemDirectoriesAndRemovingOnePreservesTheOther() throws {
        let file1 = try writeSourceFile(named: "Report.PDF", contents: "first report", subdirectory: "SourceOne")
        let file2 = try writeSourceFile(named: "Report.PDF", contents: "second report", subdirectory: "SourceTwo")
        let mock = MockPasteboard()
        mock.fileURLs = [file1, file2]
        let stack = makeStack(pasteboard: mock)
        mock.changeCount = 1
        stack.checkPasteboard()

        guard stack.queue.count == 2 else {
            return XCTFail("expected two queued files")
        }
        guard case .file(let stored1, _) = stack.queue[0].content,
              case .file(let stored2, _) = stack.queue[1].content else {
            return XCTFail("expected two stored files")
        }
        XCTAssertEqual(stored1.lastPathComponent, "Report.PDF")
        XCTAssertEqual(stored2.lastPathComponent, "Report.PDF")
        XCTAssertNotEqual(stored1.deletingLastPathComponent(), stored2.deletingLastPathComponent())
        XCTAssertEqual(try String(contentsOf: stored1, encoding: .utf8), "first report")
        XCTAssertEqual(try String(contentsOf: stored2, encoding: .utf8), "second report")

        let firstID = stack.queue[0].id
        let firstDirectory = stored1.deletingLastPathComponent()
        stack.remove(id: firstID)

        XCTAssertFalse(FileManager.default.fileExists(atPath: firstDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stored2.path))
        XCTAssertEqual(try String(contentsOf: stored2, encoding: .utf8), "second report")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file1.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file2.path))
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
        XCTAssertTrue(FileManager.default.fileExists(atPath: source1.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source2.path))
    }

    func testFilePastePreservesNameAndUsesInjectedCleanupScheduler() throws {
        let source = try writeSourceFile(named: "IMG_2218.JPG", contents: "jpeg bytes")
        let mock = MockPasteboard()
        mock.fileURLs = [source]
        let recorder = CommandVRecorder()
        let cleanup = CleanupSchedulerRecorder()
        let stack = makeStack(
            pasteboard: mock,
            commandVRecorder: recorder,
            scheduleCleanup: cleanup.schedule
        )
        mock.changeCount = 1
        stack.checkPasteboard()
        guard case .file(let storedURL, _) = stack.queue.first?.content else {
            return XCTFail("expected a stored file")
        }
        let itemDirectory = storedURL.deletingLastPathComponent()
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))
        XCTAssertEqual(storedURL.lastPathComponent, "IMG_2218.JPG")
        XCTAssertEqual(try String(contentsOf: storedURL, encoding: .utf8), "jpeg bytes")

        stack.pasteNext()

        XCTAssertEqual(recorder.requestCount, 1)
        XCTAssertEqual(cleanup.delays, [2])
        guard case .file(let writtenURL, _) = mock.writtenItems.first else {
            return XCTFail("expected a file pasteboard write")
        }
        XCTAssertEqual(writtenURL.lastPathComponent, "IMG_2218.JPG")
        XCTAssertEqual(try String(contentsOf: writtenURL, encoding: .utf8), "jpeg bytes")

        cleanup.runAll()

        XCTAssertFalse(FileManager.default.fileExists(atPath: itemDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testClearRemovesItemDirectoriesButPreservesSourcesAndOtherStorage() throws {
        let source1 = try writeSourceFile(named: "clear-one.txt", contents: "one")
        let source2 = try writeSourceFile(named: "clear-two.txt", contents: "two")
        let storage = testRoot.appendingPathComponent("ClearStorage", isDirectory: true)
        let otherStorage = testRoot.appendingPathComponent("OtherStorage", isDirectory: true)
        try FileManager.default.createDirectory(at: otherStorage, withIntermediateDirectories: true)
        let sentinel = otherStorage.appendingPathComponent("sentinel")
        try "keep".write(to: sentinel, atomically: true, encoding: .utf8)
        let mock = MockPasteboard()
        mock.fileURLs = [source1, source2]
        let stack = makeStack(pasteboard: mock, storageDirectory: storage)
        mock.changeCount = 1
        stack.checkPasteboard()
        let itemDirectories = stack.queue.compactMap { item -> URL? in
            guard case .file(let url, _) = item.content else { return nil }
            return url.deletingLastPathComponent()
        }

        stack.clear()

        XCTAssertTrue(itemDirectories.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertTrue(FileManager.default.fileExists(atPath: source1.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source2.path))
        XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "keep")
    }

    func testStartupCleanupRemovesLegacyFilesAndCurrentItemDirectories() throws {
        let storage = testRoot.appendingPathComponent("StartupStorage", isDirectory: true)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        let legacyFile = storage.appendingPathComponent("\(UUID().uuidString).txt")
        try "legacy".write(to: legacyFile, atomically: true, encoding: .utf8)
        let currentDirectory = storage.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: currentDirectory, withIntermediateDirectories: false)
        let currentFile = currentDirectory.appendingPathComponent("Original.PDF")
        try "current".write(to: currentFile, atomically: true, encoding: .utf8)

        _ = makeStack(storageDirectory: storage)

        XCTAssertTrue(try FileManager.default.contentsOfDirectory(at: storage, includingPropertiesForKeys: nil).isEmpty)
    }

    func testTestHostRuntimeIsDetected() {
        XCTAssertTrue(AppRuntime.isRunningTests)
    }

    private enum TestError: Error {
        case expectedFile
    }
}

final class HotkeyManagerShortcutTests: XCTestCase {
    func testShortcutModifierFiltering() {
        XCTAssertTrue(HotkeyManager.shouldHandleShortcut(modifierFlags: [.control, .command], isRepeat: false))
        XCTAssertTrue(HotkeyManager.shouldHandleShortcut(modifierFlags: [.control, .command, .capsLock], isRepeat: false))
        XCTAssertTrue(HotkeyManager.shouldHandleShortcut(modifierFlags: [.control, .command, .function, .numericPad], isRepeat: false))

        XCTAssertFalse(HotkeyManager.shouldHandleShortcut(modifierFlags: [.control, .command], isRepeat: true))
        XCTAssertFalse(HotkeyManager.shouldHandleShortcut(modifierFlags: [.control, .command, .shift], isRepeat: false))
        XCTAssertFalse(HotkeyManager.shouldHandleShortcut(modifierFlags: [.control, .command, .option], isRepeat: false))
        XCTAssertFalse(HotkeyManager.shouldHandleShortcut(modifierFlags: [.command], isRepeat: false))
        XCTAssertFalse(HotkeyManager.shouldHandleShortcut(modifierFlags: [.control], isRepeat: false))
    }

    func testCommandKeyCodeSearchFindsNonANSIKeyCode() {
        let keyCode = KeyboardLayoutTranslator.commandKeyCode(for: "v") { candidate, _ in
            candidate == 42 ? "V" : nil
        }

        XCTAssertEqual(keyCode, 42)
    }

    func testCommandKeyCodeSearchUsesCommandModifierState() {
        var receivedModifierStates: [UInt32] = []

        _ = KeyboardLayoutTranslator.commandKeyCode(for: "v") { _, modifierKeyState in
            receivedModifierStates.append(modifierKeyState)
            return nil
        }

        XCTAssertEqual(receivedModifierStates.count, 128)
        XCTAssertTrue(receivedModifierStates.allSatisfy {
            $0 == UInt32((cmdKey >> 8) & 0xFF)
        })
    }

    func testCommandVKeyCodeFallsBackToANSIKeyCodeWhenNoMatchExists() {
        let match = KeyboardLayoutTranslator.commandKeyCode(for: "v") { _, _ in nil }
        let keyCode = KeyboardLayoutTranslator.commandVKeyCode { _, _ in nil }

        XCTAssertNil(match)
        XCTAssertEqual(keyCode, 9)
    }
}
