import Combine
import Foundation
import Security
import os

private let licenseLogger = Logger(subsystem: "com.slenbder.pastequeue", category: "License")

struct LicenseCredential: Codable, Equatable {
    let licenseKey: String
    let instanceID: String
    let activatedAt: Date
    var lastValidatedAt: Date
}

protocol LicenseCredentialStoring {
    func load() throws -> LicenseCredential?
    func save(_ credential: LicenseCredential) throws
    func delete() throws
}

protocol TrialWarningStoring {
    func hasShownWarning(daysRemaining: Int) -> Bool
    func markWarningShown(daysRemaining: Int)
}

final class UserDefaultsTrialWarningStore: TrialWarningStoring {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "trial-warning-thresholds-v1") {
        self.defaults = defaults
        self.key = key
    }

    func hasShownWarning(daysRemaining: Int) -> Bool {
        shownThresholds.contains(daysRemaining)
    }

    func markWarningShown(daysRemaining: Int) {
        var thresholds = shownThresholds
        thresholds.insert(daysRemaining)
        defaults.set(Array(thresholds).sorted(), forKey: key)
    }

    private var shownThresholds: Set<Int> {
        Set(defaults.array(forKey: key) as? [Int] ?? [])
    }
}

enum KeychainLicenseCredentialStoreError: Error {
    case unexpectedData
    case unhandledStatus(OSStatus)
}

final class KeychainLicenseCredentialStore: LicenseCredentialStoring {
    private let service: String
    private let account: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        service: String = "com.slenbder.pastequeue.license",
        account: String = "license-credential-v1"
    ) {
        self.service = service
        self.account = account
    }

    func load() throws -> LicenseCredential? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainLicenseCredentialStoreError.unhandledStatus(status)
        }
        guard let data = result as? Data else {
            throw KeychainLicenseCredentialStoreError.unexpectedData
        }
        return try decoder.decode(LicenseCredential.self, from: data)
    }

    func save(_ credential: LicenseCredential) throws {
        let data = try encoder.encode(credential)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainLicenseCredentialStoreError.unhandledStatus(updateStatus)
        }

        var insert = baseQuery
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let insertStatus = SecItemAdd(insert as CFDictionary, nil)
        guard insertStatus == errSecSuccess else {
            throw KeychainLicenseCredentialStoreError.unhandledStatus(insertStatus)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainLicenseCredentialStoreError.unhandledStatus(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

enum LicenseAccessState: Equatable {
    case trial(daysRemaining: Int, expiresAt: Date)
    case licensed
    case expired(expiredAt: Date)
    case storageUnavailable

    var grantsAccess: Bool {
        switch self {
        case .trial, .licensed, .storageUnavailable:
            return true
        case .expired:
            return false
        }
    }
}

enum LicenseActivationError: Equatable {
    case invalidKey
    case activationLimitReached
    case noNetwork
    case wrongProduct
    case storageUnavailable
    case configurationUnavailable
    case serviceUnavailable
}

enum LicenseDeactivationError: Equatable {
    case noNetwork
    case storageUnavailable
    case configurationUnavailable
    case serviceUnavailable
}

@MainActor
final class LicenseAccessController: ObservableObject {
    static let validationInterval: TimeInterval = 7 * 24 * 60 * 60
    static let validationRetryInterval: TimeInterval = 6 * 60 * 60

    @Published private(set) var state: LicenseAccessState
    @Published private(set) var isActivating = false
    @Published private(set) var activationError: LicenseActivationError?
    @Published private(set) var isDeactivating = false
    @Published private(set) var deactivationError: LicenseDeactivationError?
    @Published private(set) var trialWarningDays: Int?

    let checkoutURL: URL?

    private let trialController: TrialAccessController
    private let credentialStore: LicenseCredentialStoring
    private let licenseService: LicenseServicing?
    private let trialWarningStore: TrialWarningStoring?
    private let now: () -> Date
    private let instanceName: () -> String
    private var credential: LicenseCredential?
    private var needsLocalCredentialCleanup = false
    private var needsCredentialReload = false
    private var retryValidationAt: Date?
    private var isValidating = false

    init(
        trialController: TrialAccessController,
        credentialStore: LicenseCredentialStoring,
        licenseService: LicenseServicing?,
        checkoutURL: URL?,
        trialWarningStore: TrialWarningStoring? = nil,
        now: @escaping () -> Date = Date.init,
        instanceName: @escaping () -> String = {
            Host.current().localizedName.map { "PasteQueue on \($0)" } ?? "PasteQueue Mac"
        }
    ) {
        self.trialController = trialController
        self.credentialStore = credentialStore
        self.licenseService = licenseService
        self.checkoutURL = checkoutURL
        self.trialWarningStore = trialWarningStore
        self.now = now
        self.instanceName = instanceName
        state = Self.state(from: trialController.state)

        loadStoredCredential()
    }

    var grantsAccess: Bool {
        state.grantsAccess
    }

    /// The next time the app should ask the service to validate the stored instance. A failed
    /// due check keeps access available and retries later instead of spinning continuously.
    var nextValidationAt: Date? {
        guard !isValidating, let credential, licenseService != nil else { return nil }
        return retryValidationAt
            ?? credential.lastValidatedAt.addingTimeInterval(Self.validationInterval)
    }

    func refresh() {
        if needsCredentialReload {
            loadStoredCredential()
            // Until the stored license can be read, access stays open instead of falling
            // back to a possibly expired trial and locking out a paying user.
            if needsCredentialReload { return }
        }
        guard credential == nil else {
            state = .licensed
            return
        }
        trialController.refresh()
        state = Self.state(from: trialController.state)
    }

    func activate(licenseKey rawLicenseKey: String) async {
        let licenseKey = rawLicenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !licenseKey.isEmpty else {
            activationError = .invalidKey
            return
        }
        guard let licenseService else {
            activationError = .configurationUnavailable
            return
        }

        isActivating = true
        activationError = nil
        defer { isActivating = false }

        do {
            let activation = try await licenseService.activate(
                licenseKey: licenseKey,
                instanceName: instanceName()
            )
            let activationDate = now()
            let newCredential = LicenseCredential(
                licenseKey: licenseKey,
                instanceID: activation.instanceID,
                activatedAt: activationDate,
                lastValidatedAt: activationDate
            )

            do {
                try credentialStore.save(newCredential)
            } catch {
                try? await licenseService.deactivate(
                    licenseKey: licenseKey,
                    instanceID: activation.instanceID
                )
                logStorageFailure(error)
                activationError = .storageUnavailable
                return
            }

            credential = newCredential
            needsCredentialReload = false
            retryValidationAt = nil
            trialWarningDays = nil
            state = .licensed
        } catch {
            activationError = Self.activationError(from: error)
        }
    }

    /// A stored credential grants access immediately. Validation runs periodically in the
    /// background; transport/server failures preserve paid access, while an explicit invalid
    /// response removes the credential and falls back to the local trial state.
    func validateIfNeeded(force: Bool = false) async {
        guard var credential, let licenseService else { return }
        guard !isValidating else { return }
        let currentDate = now()
        let dueAt = retryValidationAt
            ?? credential.lastValidatedAt.addingTimeInterval(Self.validationInterval)
        guard force || currentDate >= dueAt else { return }

        isValidating = true
        defer { isValidating = false }

        do {
            let validation = try await licenseService.validate(
                licenseKey: credential.licenseKey,
                instanceID: credential.instanceID
            )
            guard validation.isValid else {
                invalidateStoredCredential()
                return
            }

            credential.lastValidatedAt = now()
            retryValidationAt = nil
            self.credential = credential
            do {
                try credentialStore.save(credential)
            } catch {
                // The existing credential remains usable. A Keychain write failure must not
                // lock out someone whose license was just confirmed by the server. Keep the
                // refreshed timestamp in memory so the running app does not retry in a loop.
                logStorageFailure(error)
            }
            state = .licensed
        } catch let error as LemonSqueezyLicenseError {
            switch error {
            case .productMismatch, .inactiveLicense, .missingInstance:
                invalidateStoredCredential()
            case .httpError(let statusCode, _)
                where Self.definitiveCredentialStatusCodes.contains(statusCode):
                invalidateStoredCredential()
            case .invalidResponse, .httpError, .rejected:
                retryValidationAt = now().addingTimeInterval(Self.validationRetryInterval)
                state = .licensed
            }
        } catch {
            retryValidationAt = now().addingTimeInterval(Self.validationRetryInterval)
            state = .licensed
        }
    }

    func clearActivationError() {
        activationError = nil
    }

    func deactivateCurrentDevice() async {
        guard let credential else { return }

        isDeactivating = true
        deactivationError = nil
        defer { isDeactivating = false }

        if !needsLocalCredentialCleanup {
            guard let licenseService else {
                deactivationError = .configurationUnavailable
                return
            }

            do {
                try await licenseService.deactivate(
                    licenseKey: credential.licenseKey,
                    instanceID: credential.instanceID
                )
                needsLocalCredentialCleanup = true
            } catch let error as LemonSqueezyLicenseError {
                if case .httpError(let statusCode, _) = error,
                   Self.definitiveCredentialStatusCodes.contains(statusCode) {
                    // The server no longer recognizes this key/instance. For a user-requested
                    // deactivation, removing the stale local credential is the correct recovery.
                    needsLocalCredentialCleanup = true
                } else {
                    deactivationError = Self.deactivationError(from: error)
                    state = .licensed
                    return
                }
            } catch {
                deactivationError = Self.deactivationError(from: error)
                state = .licensed
                return
            }
        }

        do {
            try credentialStore.delete()
        } catch {
            logStorageFailure(error)
            deactivationError = .storageUnavailable
            state = .licensed
            return
        }

        needsLocalCredentialCleanup = false
        self.credential = nil
        retryValidationAt = nil
        trialWarningDays = nil
        trialController.refresh()
        state = Self.state(from: trialController.state)
    }

    func clearDeactivationError() {
        deactivationError = nil
    }

    func prepareTrialWarning() {
        guard case .trial(let daysRemaining, _) = state,
              let threshold = Self.warningThreshold(for: daysRemaining),
              let trialWarningStore else {
            trialWarningDays = nil
            return
        }

        if trialWarningDays == threshold {
            return
        }
        guard !trialWarningStore.hasShownWarning(daysRemaining: threshold) else {
            trialWarningDays = nil
            return
        }
        trialWarningStore.markWarningShown(daysRemaining: threshold)
        trialWarningDays = threshold
    }

    func dismissTrialWarning() {
        trialWarningDays = nil
    }

    private func loadStoredCredential() {
        do {
            credential = try credentialStore.load()
            needsCredentialReload = false
            if credential != nil {
                state = .licensed
            }
        } catch {
            logStorageFailure(error)
            needsCredentialReload = true
            state = .storageUnavailable
        }
    }

    private func invalidateStoredCredential() {
        do {
            try credentialStore.delete()
        } catch {
            logStorageFailure(error)
        }
        credential = nil
        retryValidationAt = nil
        trialWarningDays = nil
        trialController.refresh()
        state = Self.state(from: trialController.state)
    }

    private static func state(from trialState: TrialAccessState) -> LicenseAccessState {
        switch trialState {
        case .active(let daysRemaining, let expiresAt):
            return .trial(daysRemaining: daysRemaining, expiresAt: expiresAt)
        case .expired(let expiredAt):
            return .expired(expiredAt: expiredAt)
        case .storageUnavailable:
            return .storageUnavailable
        }
    }

    private static func warningThreshold(for daysRemaining: Int) -> Int? {
        if daysRemaining <= 1 { return 1 }
        if daysRemaining <= 3 { return 3 }
        if daysRemaining <= 7 { return 7 }
        return nil
    }

    private static func activationError(from error: Error) -> LicenseActivationError {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                 .cannotConnectToHost, .dnsLookupFailed, .timedOut:
                return .noNetwork
            default:
                return .serviceUnavailable
            }
        }

        guard let lemonError = error as? LemonSqueezyLicenseError else {
            return .serviceUnavailable
        }
        switch lemonError {
        case .productMismatch:
            return .wrongProduct
        case .inactiveLicense, .missingInstance:
            return .invalidKey
        case .invalidResponse:
            return .serviceUnavailable
        case .httpError(let statusCode, let message):
            if statusCode == 429 || statusCode >= 500 {
                return .serviceUnavailable
            }
            return activationError(fromServerMessage: message, statusCode: statusCode)
        case .rejected(let message):
            return activationError(fromServerMessage: message)
        }
    }

    private static func activationError(
        fromServerMessage message: String,
        statusCode: Int? = nil
    ) -> LicenseActivationError {
        let normalizedMessage = message.lowercased()
        if normalizedMessage.contains("activation limit") {
            return .activationLimitReached
        }
        if statusCode == 404
            || normalizedMessage.contains("license key")
                && (normalizedMessage.contains("invalid") || normalizedMessage.contains("not found")) {
            return .invalidKey
        }
        return .serviceUnavailable
    }

    private static func deactivationError(from error: Error) -> LicenseDeactivationError {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                 .cannotConnectToHost, .dnsLookupFailed, .timedOut:
                return .noNetwork
            default:
                return .serviceUnavailable
            }
        }

        return .serviceUnavailable
    }

    private static let definitiveCredentialStatusCodes: Set<Int> = [400, 404, 422]

    private func logStorageFailure(_ error: Error) {
        let nsError = error as NSError
        licenseLogger.error(
            "license storage failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)"
        )
    }
}
