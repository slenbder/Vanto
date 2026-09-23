@testable import PasteQueue
import XCTest

final class TrialAccessControllerTests: XCTestCase {
    func testFirstLaunchStartsFourteenDayTrialAndPersistsIt() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let store = MockTrialStateStore()

        let controller = TrialAccessController(store: store, now: { start })

        XCTAssertEqual(
            controller.state,
            .active(daysRemaining: 14, expiresAt: start.addingTimeInterval(TrialAccessController.trialDuration))
        )
        XCTAssertEqual(store.record, TrialRecord(startedAt: start, latestObservedAt: start))
        XCTAssertTrue(controller.grantsAccess)
    }

    func testRestartKeepsOriginalTrialStart() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let current = start.addingTimeInterval(2 * 24 * 60 * 60)
        let store = MockTrialStateStore(
            record: TrialRecord(startedAt: start, latestObservedAt: start)
        )

        let controller = TrialAccessController(store: store, now: { current })

        XCTAssertEqual(
            controller.state,
            .active(daysRemaining: 12, expiresAt: start.addingTimeInterval(TrialAccessController.trialDuration))
        )
        XCTAssertEqual(store.record?.startedAt, start)
        XCTAssertEqual(store.record?.latestObservedAt, current)
    }

    func testTrialExpiresAtExactFourteenDayBoundary() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let expiration = start.addingTimeInterval(TrialAccessController.trialDuration)
        let store = MockTrialStateStore(
            record: TrialRecord(startedAt: start, latestObservedAt: start)
        )

        let controller = TrialAccessController(store: store, now: { expiration })

        XCTAssertEqual(controller.state, .expired(expiredAt: expiration))
        XCTAssertFalse(controller.grantsAccess)
    }

    func testClockRollbackDoesNotRestoreElapsedTrialTime() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let latestObserved = start.addingTimeInterval(10 * 24 * 60 * 60)
        let rolledBackDate = start.addingTimeInterval(24 * 60 * 60)
        let store = MockTrialStateStore(
            record: TrialRecord(startedAt: start, latestObservedAt: latestObserved)
        )

        let controller = TrialAccessController(store: store, now: { rolledBackDate })

        XCTAssertEqual(
            controller.state,
            .active(daysRemaining: 4, expiresAt: start.addingTimeInterval(TrialAccessController.trialDuration))
        )
        XCTAssertEqual(store.record?.latestObservedAt, latestObserved)
    }

    func testPartialLastDayRoundsUpToOneDayRemaining() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let current = start.addingTimeInterval(13.5 * 24 * 60 * 60)
        let store = MockTrialStateStore(
            record: TrialRecord(startedAt: start, latestObservedAt: start)
        )

        let controller = TrialAccessController(store: store, now: { current })

        XCTAssertEqual(
            controller.state,
            .active(daysRemaining: 1, expiresAt: start.addingTimeInterval(TrialAccessController.trialDuration))
        )
    }

    func testStorageFailureDoesNotLockUserOut() {
        let store = MockTrialStateStore(error: MockTrialStateStore.TestError.unavailable)

        let controller = TrialAccessController(store: store)

        XCTAssertEqual(controller.state, .storageUnavailable)
        XCTAssertTrue(controller.grantsAccess)
    }
}

private final class MockTrialStateStore: TrialStateStoring {
    enum TestError: Error {
        case unavailable
    }

    var record: TrialRecord?
    var error: Error?

    init(record: TrialRecord? = nil, error: Error? = nil) {
        self.record = record
        self.error = error
    }

    func load() throws -> TrialRecord? {
        if let error { throw error }
        return record
    }

    func save(_ record: TrialRecord) throws {
        if let error { throw error }
        self.record = record
    }
}
