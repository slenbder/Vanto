@testable import PasteQueue
import XCTest

@MainActor
final class LicenseAccessControllerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testExpiredTrialWithoutCredentialBlocksAccess() {
        let controller = makeController(
            now: start.addingTimeInterval(TrialAccessController.trialDuration),
            trialStartedAt: start
        )

        XCTAssertEqual(
            controller.state,
            .expired(expiredAt: start.addingTimeInterval(TrialAccessController.trialDuration))
        )
        XCTAssertFalse(controller.grantsAccess)
    }

    func testStoredCredentialGrantsAccessBeforeNetworkValidation() {
        let credential = LicenseCredential(
            licenseKey: "KEY",
            instanceID: "instance-1",
            activatedAt: start,
            lastValidatedAt: start
        )

        let controller = makeController(
            now: start.addingTimeInterval(30 * 24 * 60 * 60),
            trialStartedAt: start,
            credentialStore: MockLicenseCredentialStore(credential: credential),
            service: MockLicenseService(validateError: URLError(.notConnectedToInternet))
        )

        XCTAssertEqual(controller.state, .licensed)
        XCTAssertTrue(controller.grantsAccess)
    }

    func testActivationPersistsCredentialAndUnlocksImmediately() async {
        let store = MockLicenseCredentialStore()
        let service = MockLicenseService(
            activation: LicenseActivation(instanceID: "instance-1", activationLimit: 3, activationUsage: 1)
        )
        let controller = makeController(
            now: start.addingTimeInterval(TrialAccessController.trialDuration),
            trialStartedAt: start,
            credentialStore: store,
            service: service
        )

        await controller.activate(licenseKey: "  KEY  ")

        XCTAssertEqual(controller.state, .licensed)
        XCTAssertEqual(store.credential?.licenseKey, "KEY")
        XCTAssertEqual(store.credential?.instanceID, "instance-1")
        XCTAssertEqual(service.activatedKeys, ["KEY"])
        XCTAssertNil(controller.activationError)
    }

    func testActivationStorageFailureReleasesInstanceAndKeepsTrialState() async {
        let store = MockLicenseCredentialStore(saveError: MockLicenseCredentialStore.TestError.unavailable)
        let service = MockLicenseService(
            activation: LicenseActivation(instanceID: "instance-1", activationLimit: 3, activationUsage: 1)
        )
        let controller = makeController(
            now: start.addingTimeInterval(TrialAccessController.trialDuration),
            trialStartedAt: start,
            credentialStore: store,
            service: service
        )

        await controller.activate(licenseKey: "KEY")

        XCTAssertEqual(controller.activationError, .storageUnavailable)
        XCTAssertEqual(service.deactivatedInstanceIDs, ["instance-1"])
        XCTAssertFalse(controller.grantsAccess)
    }

    func testOfflineValidationKeepsPaidAccess() async {
        let current = start.addingTimeInterval(8 * 24 * 60 * 60)
        let credential = LicenseCredential(
            licenseKey: "KEY",
            instanceID: "instance-1",
            activatedAt: start,
            lastValidatedAt: start
        )
        let service = MockLicenseService(validateError: URLError(.notConnectedToInternet))
        let controller = makeController(
            now: current,
            trialStartedAt: start,
            credentialStore: MockLicenseCredentialStore(credential: credential),
            service: service
        )

        await controller.validateIfNeeded()

        XCTAssertEqual(controller.state, .licensed)
        XCTAssertEqual(service.validatedInstanceIDs, ["instance-1"])
    }

    func testExplicitInvalidValidationDeletesCredentialAndFallsBackToExpiredTrial() async {
        let current = start.addingTimeInterval(20 * 24 * 60 * 60)
        let store = MockLicenseCredentialStore(
            credential: LicenseCredential(
                licenseKey: "KEY",
                instanceID: "instance-1",
                activatedAt: start,
                lastValidatedAt: start
            )
        )
        let service = MockLicenseService(
            validation: LicenseValidation(isValid: false, activationLimit: 3, activationUsage: 1)
        )
        let controller = makeController(
            now: current,
            trialStartedAt: start,
            credentialStore: store,
            service: service
        )

        await controller.validateIfNeeded()

        XCTAssertNil(store.credential)
        XCTAssertEqual(
            controller.state,
            .expired(expiredAt: start.addingTimeInterval(TrialAccessController.trialDuration))
        )
    }

    func testRecentValidationSkipsNetworkRequest() async {
        let current = start.addingTimeInterval(2 * 24 * 60 * 60)
        let credential = LicenseCredential(
            licenseKey: "KEY",
            instanceID: "instance-1",
            activatedAt: start,
            lastValidatedAt: start
        )
        let service = MockLicenseService()
        let controller = makeController(
            now: current,
            trialStartedAt: start,
            credentialStore: MockLicenseCredentialStore(credential: credential),
            service: service
        )

        await controller.validateIfNeeded()

        XCTAssertTrue(service.validatedInstanceIDs.isEmpty)
        XCTAssertEqual(controller.state, .licensed)
    }

    func testActivationLimitGetsSpecificUserFacingError() async {
        let service = MockLicenseService(
            activateError: LemonSqueezyLicenseError.rejected(
                message: "This license key has reached the activation limit."
            )
        )
        let controller = makeController(
            now: start,
            trialStartedAt: start,
            service: service
        )

        await controller.activate(licenseKey: "KEY")

        XCTAssertEqual(controller.activationError, .activationLimitReached)
        XCTAssertTrue(controller.grantsAccess)
    }

    func testDeactivationReleasesInstanceAndFallsBackToExpiredTrial() async {
        let current = start.addingTimeInterval(20 * 24 * 60 * 60)
        let store = MockLicenseCredentialStore(
            credential: LicenseCredential(
                licenseKey: "KEY",
                instanceID: "instance-1",
                activatedAt: start,
                lastValidatedAt: start
            )
        )
        let service = MockLicenseService()
        let controller = makeController(
            now: current,
            trialStartedAt: start,
            credentialStore: store,
            service: service
        )

        await controller.deactivateCurrentDevice()

        XCTAssertEqual(service.deactivatedInstanceIDs, ["instance-1"])
        XCTAssertNil(store.credential)
        XCTAssertFalse(controller.grantsAccess)
        XCTAssertEqual(
            controller.state,
            .expired(expiredAt: start.addingTimeInterval(TrialAccessController.trialDuration))
        )
    }

    func testOfflineDeactivationKeepsLicenseActive() async {
        let store = MockLicenseCredentialStore(
            credential: LicenseCredential(
                licenseKey: "KEY",
                instanceID: "instance-1",
                activatedAt: start,
                lastValidatedAt: start
            )
        )
        let service = MockLicenseService(deactivateError: URLError(.notConnectedToInternet))
        let controller = makeController(
            now: start,
            trialStartedAt: start,
            credentialStore: store,
            service: service
        )

        await controller.deactivateCurrentDevice()

        XCTAssertEqual(controller.state, .licensed)
        XCTAssertEqual(controller.deactivationError, .noNetwork)
        XCTAssertNotNil(store.credential)
    }

    func testTrialWarningsAppearOnceAtSevenThreeAndOneDayThresholds() {
        let warningStore = MockTrialWarningStore()
        var current = start.addingTimeInterval(7 * 24 * 60 * 60)
        let trialStore = AccessMockTrialStore(
            record: TrialRecord(startedAt: start, latestObservedAt: start)
        )
        let trialController = TrialAccessController(store: trialStore, now: { current })
        let controller = LicenseAccessController(
            trialController: trialController,
            credentialStore: MockLicenseCredentialStore(),
            licenseService: MockLicenseService(),
            checkoutURL: URL(string: "https://example.com/buy"),
            trialWarningStore: warningStore,
            now: { current },
            instanceName: { "Test Mac" }
        )

        controller.prepareTrialWarning()
        XCTAssertEqual(controller.trialWarningDays, 7)
        controller.dismissTrialWarning()
        controller.prepareTrialWarning()
        XCTAssertNil(controller.trialWarningDays)

        current = start.addingTimeInterval(11 * 24 * 60 * 60)
        controller.refresh()
        controller.prepareTrialWarning()
        XCTAssertEqual(controller.trialWarningDays, 3)

        current = start.addingTimeInterval(13.5 * 24 * 60 * 60)
        controller.refresh()
        controller.prepareTrialWarning()
        XCTAssertEqual(controller.trialWarningDays, 1)
        XCTAssertEqual(warningStore.shownThresholds, [1, 3, 7])
    }

    private func makeController(
        now current: Date,
        trialStartedAt: Date,
        credentialStore: MockLicenseCredentialStore = MockLicenseCredentialStore(),
        service: MockLicenseService? = MockLicenseService()
    ) -> LicenseAccessController {
        let trialStore = AccessMockTrialStore(
            record: TrialRecord(startedAt: trialStartedAt, latestObservedAt: trialStartedAt)
        )
        let trialController = TrialAccessController(store: trialStore, now: { current })
        return LicenseAccessController(
            trialController: trialController,
            credentialStore: credentialStore,
            licenseService: service,
            checkoutURL: URL(string: "https://example.com/buy"),
            now: { current },
            instanceName: { "Test Mac" }
        )
    }
}

private final class MockTrialWarningStore: TrialWarningStoring {
    var shownThresholds: Set<Int> = []

    func hasShownWarning(daysRemaining: Int) -> Bool {
        shownThresholds.contains(daysRemaining)
    }

    func markWarningShown(daysRemaining: Int) {
        shownThresholds.insert(daysRemaining)
    }
}

private final class AccessMockTrialStore: TrialStateStoring {
    var record: TrialRecord?

    init(record: TrialRecord?) {
        self.record = record
    }

    func load() throws -> TrialRecord? { record }
    func save(_ record: TrialRecord) throws { self.record = record }
}

private final class MockLicenseCredentialStore: LicenseCredentialStoring {
    enum TestError: Error { case unavailable }

    var credential: LicenseCredential?
    var loadError: Error?
    var saveError: Error?
    var deleteError: Error?

    init(
        credential: LicenseCredential? = nil,
        loadError: Error? = nil,
        saveError: Error? = nil,
        deleteError: Error? = nil
    ) {
        self.credential = credential
        self.loadError = loadError
        self.saveError = saveError
        self.deleteError = deleteError
    }

    func load() throws -> LicenseCredential? {
        if let loadError { throw loadError }
        return credential
    }

    func save(_ credential: LicenseCredential) throws {
        if let saveError { throw saveError }
        self.credential = credential
    }

    func delete() throws {
        if let deleteError { throw deleteError }
        credential = nil
    }
}

private final class MockLicenseService: LicenseServicing {
    var activation: LicenseActivation
    var validation: LicenseValidation
    var activateError: Error?
    var validateError: Error?
    var deactivateError: Error?
    var activatedKeys: [String] = []
    var validatedInstanceIDs: [String] = []
    var deactivatedInstanceIDs: [String] = []

    init(
        activation: LicenseActivation = LicenseActivation(
            instanceID: "instance-1",
            activationLimit: 3,
            activationUsage: 1
        ),
        validation: LicenseValidation = LicenseValidation(
            isValid: true,
            activationLimit: 3,
            activationUsage: 1
        ),
        activateError: Error? = nil,
        validateError: Error? = nil,
        deactivateError: Error? = nil
    ) {
        self.activation = activation
        self.validation = validation
        self.activateError = activateError
        self.validateError = validateError
        self.deactivateError = deactivateError
    }

    func activate(licenseKey: String, instanceName: String) async throws -> LicenseActivation {
        activatedKeys.append(licenseKey)
        if let activateError { throw activateError }
        return activation
    }

    func validate(licenseKey: String, instanceID: String) async throws -> LicenseValidation {
        validatedInstanceIDs.append(instanceID)
        if let validateError { throw validateError }
        return validation
    }

    func deactivate(licenseKey: String, instanceID: String) async throws {
        deactivatedInstanceIDs.append(instanceID)
        if let deactivateError { throw deactivateError }
    }
}
