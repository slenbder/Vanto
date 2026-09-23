@testable import PasteQueue
import XCTest

final class LemonSqueezyLicenseClientTests: XCTestCase {
    private let configuration = LicenseProductConfiguration(
        storeID: 480340,
        productID: 1379329,
        variantID: 2154757,
        checkoutURL: URL(string: "https://example.com/checkout")!
    )

    func testDebugConfigurationUsesVerifiedTestProduct() throws {
        let current = try XCTUnwrap(LicenseProductConfiguration.current)

        XCTAssertEqual(current.storeID, 480340)
        XCTAssertEqual(current.productID, 1379329)
        XCTAssertEqual(current.variantID, 2154757)
        XCTAssertEqual(
            current.checkoutURL.absoluteString,
            "https://slenbder.lemonsqueezy.com/checkout/buy/b2f5795c-0447-4e32-85ce-a04ecf70ec25"
        )
    }

    func testActivationPostsEncodedKeyAndReturnsInstance() async throws {
        let session = MockURLSession { request in
            XCTAssertEqual(request.url?.path, "/v1/licenses/activate")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8)
            XCTAssertEqual(body, "instance_name=PasteQueue%20Mac&license_key=TEST%20KEY")
            return Self.response(
                for: request,
                json: Self.activationJSON(storeID: 480340, productID: 1379329, variantID: 2154757)
            )
        }

        let activation = try await makeClient(session: session).activate(
            licenseKey: "TEST KEY",
            instanceName: "PasteQueue Mac"
        )

        XCTAssertEqual(
            activation,
            LicenseActivation(instanceID: "instance-1", activationLimit: 3, activationUsage: 1)
        )
    }

    func testActivationRejectsKeyFromAnotherProductAndReleasesCreatedInstance() async throws {
        var requestedPaths: [String] = []
        let session = MockURLSession { request in
            requestedPaths.append(request.url?.path ?? "")
            if request.url?.path.hasSuffix("/activate") == true {
                return Self.response(
                    for: request,
                    json: Self.activationJSON(storeID: 480340, productID: 999, variantID: 2154757)
                )
            }
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8)
            XCTAssertEqual(body, "instance_id=instance-1&license_key=TEST-KEY")
            return Self.response(
                for: request,
                json: Self.deactivationJSON(storeID: 480340, productID: 999, variantID: 2154757)
            )
        }

        do {
            _ = try await makeClient(session: session).activate(licenseKey: "TEST-KEY", instanceName: "Test")
            XCTFail("Expected product mismatch")
        } catch let error as LemonSqueezyLicenseError {
            XCTAssertEqual(error, .productMismatch)
        }
        XCTAssertEqual(requestedPaths, ["/v1/licenses/activate", "/v1/licenses/deactivate"])
    }

    func testActivationLimitErrorIsPreservedForUserFacingMapping() async throws {
        let session = MockURLSession { request in
            Self.response(
                for: request,
                json: """
                {
                  "activated": false,
                  "error": "This license key has reached the activation limit.",
                  "license_key": {"status":"active","activation_limit":3,"activation_usage":3},
                  "instance": null,
                  "meta": {"store_id":480340,"product_id":1379329,"variant_id":2154757}
                }
                """
            )
        }

        do {
            _ = try await makeClient(session: session).activate(licenseKey: "TEST-KEY", instanceName: "Test")
            XCTFail("Expected rejected activation")
        } catch let error as LemonSqueezyLicenseError {
            XCTAssertEqual(
                error,
                .rejected(message: "This license key has reached the activation limit.")
            )
        }
    }

    func testValidationIncludesInstanceAndRequiresMatchingMetadata() async throws {
        let session = MockURLSession { request in
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8)
            XCTAssertEqual(body, "instance_id=instance-1&license_key=TEST-KEY")
            return Self.response(
                for: request,
                json: """
                {
                  "valid": true,
                  "error": null,
                  "license_key": {"status":"active","activation_limit":3,"activation_usage":2},
                  "instance": {"id":"instance-1"},
                  "meta": {"store_id":480340,"product_id":1379329,"variant_id":2154757}
                }
                """
            )
        }

        let validation = try await makeClient(session: session).validate(
            licenseKey: "TEST-KEY",
            instanceID: "instance-1"
        )

        XCTAssertEqual(
            validation,
            LicenseValidation(isValid: true, activationLimit: 3, activationUsage: 2)
        )
    }

    private func makeClient(session: URLSessionDataLoading) -> LemonSqueezyLicenseClient {
        LemonSqueezyLicenseClient(
            configuration: configuration,
            session: session
        )
    }

    private static func response(for request: URLRequest, json: String) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
            Data(json.utf8)
        )
    }

    private static func activationJSON(storeID: Int, productID: Int, variantID: Int) -> String {
        """
        {
          "activated": true,
          "error": null,
          "license_key": {"status":"active","activation_limit":3,"activation_usage":1},
          "instance": {"id":"instance-1"},
          "meta": {"store_id":\(storeID),"product_id":\(productID),"variant_id":\(variantID)}
        }
        """
    }

    private static func deactivationJSON(storeID: Int, productID: Int, variantID: Int) -> String {
        """
        {
          "deactivated": true,
          "error": null,
          "license_key": {"status":"active","activation_limit":3,"activation_usage":0},
          "meta": {"store_id":\(storeID),"product_id":\(productID),"variant_id":\(variantID)}
        }
        """
    }
}

private final class MockURLSession: URLSessionDataLoading {
    private let handler: (URLRequest) throws -> (HTTPURLResponse, Data)

    init(handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let (response, data) = try handler(request)
        return (data, response)
    }
}
