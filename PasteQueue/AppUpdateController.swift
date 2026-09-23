import Foundation
import Sparkle

struct SparkleUpdateConfiguration: Equatable {
    let feedURL: URL
    let publicEDKey: String

    static func load(from bundle: Bundle = .main) -> SparkleUpdateConfiguration? {
        load(from: bundle.infoDictionary ?? [:])
    }

    static func load(from infoDictionary: [String: Any]) -> SparkleUpdateConfiguration? {
        guard let feedURLString = infoDictionary["SUFeedURL"] as? String,
              let feedURL = URL(string: feedURLString),
              feedURL.scheme == "https",
              let publicEDKey = infoDictionary["SUPublicEDKey"] as? String,
              let decodedKey = Data(base64Encoded: publicEDKey),
              decodedKey.count == 32 else {
            return nil
        }
        return SparkleUpdateConfiguration(feedURL: feedURL, publicEDKey: publicEDKey)
    }
}

/// Starts Sparkle only after both release values are embedded in Info.plist, preventing the
/// updater from presenting a configuration error when a local build is missing either value.
@MainActor
final class AppUpdateController {
    private(set) var updaterController: SPUStandardUpdaterController?

    init(bundle: Bundle = .main) {
        guard SparkleUpdateConfiguration.load(from: bundle) != nil else { return }
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var isConfigured: Bool {
        updaterController != nil
    }
}
