import Combine
import Foundation
import Security
import os

private let trialLogger = Logger(subsystem: "com.slenbder.pastequeue", category: "Trial")

struct TrialRecord: Codable, Equatable {
    let startedAt: Date
    var latestObservedAt: Date
}

protocol TrialStateStoring {
    func load() throws -> TrialRecord?
    func save(_ record: TrialRecord) throws
}

enum TrialAccessState: Equatable {
    case active(daysRemaining: Int, expiresAt: Date)
    case expired(expiredAt: Date)
    case storageUnavailable

    /// A local storage failure must not unexpectedly lock a paying user out of the app.
    /// The UI can still surface the failure while the licensing service is unavailable.
    var grantsAccess: Bool {
        switch self {
        case .active, .storageUnavailable:
            return true
        case .expired:
            return false
        }
    }
}

enum KeychainTrialStateStoreError: Error {
    case unexpectedData
    case unhandledStatus(OSStatus)
}

/// Stores only the local trial clock in Keychain. The license key and Lemon Squeezy
/// instance will be added to a separate credential record when activation is connected.
final class KeychainTrialStateStore: TrialStateStoring {
    private let service: String
    private let account: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        service: String = "com.slenbder.pastequeue.trial",
        account: String = "trial-state-v1"
    ) {
        self.service = service
        self.account = account
    }

    func load() throws -> TrialRecord? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainTrialStateStoreError.unhandledStatus(status)
        }
        guard let data = result as? Data else {
            throw KeychainTrialStateStoreError.unexpectedData
        }
        return try decoder.decode(TrialRecord.self, from: data)
    }

    func save(_ record: TrialRecord) throws {
        let data = try encoder.encode(record)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainTrialStateStoreError.unhandledStatus(updateStatus)
        }

        var insert = baseQuery
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let insertStatus = SecItemAdd(insert as CFDictionary, nil)
        guard insertStatus == errSecSuccess else {
            throw KeychainTrialStateStoreError.unhandledStatus(insertStatus)
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

/// Owns the local 14-day trial clock. It has no network or Lemon Squeezy dependency,
/// which keeps trial boundary behavior deterministic and independently testable.
final class TrialAccessController: ObservableObject {
    static let trialDuration: TimeInterval = 14 * 24 * 60 * 60
    private static let persistenceInterval: TimeInterval = 60 * 60

    @Published private(set) var state: TrialAccessState = .storageUnavailable

    private let store: TrialStateStoring
    private let now: () -> Date
    private var record: TrialRecord?

    init(store: TrialStateStoring, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
        loadOrStartTrial()
    }

    var grantsAccess: Bool {
        state.grantsAccess
    }

    /// Re-evaluates the trial before an action or when the popover opens. The latest
    /// observed time only moves forward, so moving the system clock back cannot extend it.
    func refresh() {
        guard var record else {
            loadOrStartTrial()
            return
        }

        let currentDate = now()
        let effectiveDate = max(currentDate, record.latestObservedAt)
        let expirationDate = record.startedAt.addingTimeInterval(Self.trialDuration)

        if currentDate.timeIntervalSince(record.latestObservedAt) >= Self.persistenceInterval
            || effectiveDate >= expirationDate {
            record.latestObservedAt = effectiveDate
            do {
                try store.save(record)
                self.record = record
            } catch {
                handleStorageFailure(error)
                return
            }
        }

        state = Self.makeState(at: effectiveDate, expirationDate: expirationDate)
    }

    private func loadOrStartTrial() {
        let currentDate = now()
        do {
            var loadedRecord = try store.load()
            if loadedRecord == nil {
                loadedRecord = TrialRecord(startedAt: currentDate, latestObservedAt: currentDate)
            } else if currentDate > loadedRecord!.latestObservedAt {
                loadedRecord!.latestObservedAt = currentDate
            }

            guard let loadedRecord else { return }
            try store.save(loadedRecord)
            record = loadedRecord

            let effectiveDate = max(currentDate, loadedRecord.latestObservedAt)
            let expirationDate = loadedRecord.startedAt.addingTimeInterval(Self.trialDuration)
            state = Self.makeState(at: effectiveDate, expirationDate: expirationDate)
        } catch {
            handleStorageFailure(error)
        }
    }

    private static func makeState(at date: Date, expirationDate: Date) -> TrialAccessState {
        let remaining = expirationDate.timeIntervalSince(date)
        guard remaining > 0 else {
            return .expired(expiredAt: expirationDate)
        }
        let daysRemaining = max(1, Int(ceil(remaining / (24 * 60 * 60))))
        return .active(daysRemaining: daysRemaining, expiresAt: expirationDate)
    }

    private func handleStorageFailure(_ error: Error) {
        record = nil
        state = .storageUnavailable
        let nsError = error as NSError
        trialLogger.error(
            "trial state storage failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)"
        )
    }
}
