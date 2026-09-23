@testable import PasteQueue
import XCTest

final class AppUpdateControllerTests: XCTestCase {
    private let publicKey = Data(repeating: 7, count: 32).base64EncodedString()

    func testConfigurationAcceptsHTTPSFeedAndEdDSAPublicKey() {
        let configuration = SparkleUpdateConfiguration.load(from: [
            "SUFeedURL": "https://example.com/appcast.xml",
            "SUPublicEDKey": publicKey
        ])

        XCTAssertEqual(
            configuration,
            SparkleUpdateConfiguration(
                feedURL: URL(string: "https://example.com/appcast.xml")!,
                publicEDKey: publicKey
            )
        )
    }

    func testConfigurationRejectsMissingOrInsecureReleaseValues() {
        XCTAssertNil(SparkleUpdateConfiguration.load(from: [:]))
        XCTAssertNil(SparkleUpdateConfiguration.load(from: [
            "SUFeedURL": "http://example.com/appcast.xml",
            "SUPublicEDKey": publicKey
        ]))
        XCTAssertNil(SparkleUpdateConfiguration.load(from: [
            "SUFeedURL": "https://example.com/appcast.xml",
            "SUPublicEDKey": "not-a-valid-ed25519-key"
        ]))
    }

    func testBundledSettingsEnableAutomaticUpdatesFromProductionFeed() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        let bundledPublicKey = try XCTUnwrap(info["SUPublicEDKey"] as? String)
        let feedURL = try XCTUnwrap(info["SUFeedURL"] as? String)

        XCTAssertEqual(info["SUEnableAutomaticChecks"] as? Bool, true)
        XCTAssertEqual(info["SUAllowsAutomaticUpdates"] as? Bool, true)
        XCTAssertEqual(info["SUAutomaticallyUpdate"] as? Bool, true)
        XCTAssertEqual(Data(base64Encoded: bundledPublicKey)?.count, 32)
        XCTAssertEqual(
            feedURL,
            "https://raw.githubusercontent.com/slenbder/PasteQueue/main/appcast.xml"
        )
        XCTAssertNotNil(SparkleUpdateConfiguration.load(from: info))
    }
}
