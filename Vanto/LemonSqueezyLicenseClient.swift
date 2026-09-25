import Foundation

struct LicenseProductConfiguration: Equatable {
    let storeID: Int
    let productID: Int
    let variantID: Int
    let checkoutURL: URL

    /// Values come from per-configuration build settings in project.yml: Debug points at
    /// the test-mode product, Release at the live one.
    static var current: LicenseProductConfiguration? {
        load()
    }

    static func load(from bundle: Bundle = .main) -> LicenseProductConfiguration? {
        guard let storeID = integerValue(bundle.object(forInfoDictionaryKey: "LemonSqueezyStoreID")),
              let productID = integerValue(bundle.object(forInfoDictionaryKey: "LemonSqueezyProductID")),
              let variantID = integerValue(bundle.object(forInfoDictionaryKey: "LemonSqueezyVariantID")),
              let checkoutURLString = bundle.object(forInfoDictionaryKey: "LemonSqueezyCheckoutURL") as? String,
              let checkoutURL = URL(string: checkoutURLString),
              checkoutURL.scheme == "https" else {
            return nil
        }

        return LicenseProductConfiguration(
            storeID: storeID,
            productID: productID,
            variantID: variantID,
            checkoutURL: checkoutURL
        )
    }

    fileprivate func matches(_ metadata: LemonLicenseMetadata) -> Bool {
        storeID == metadata.storeID
            && productID == metadata.productID
            && variantID == metadata.variantID
    }

    private static func integerValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? String { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }
}

struct LicenseActivation: Equatable {
    let instanceID: String
    let activationLimit: Int
    let activationUsage: Int
}

struct LicenseValidation: Equatable {
    let isValid: Bool
    let activationLimit: Int
    let activationUsage: Int
}

enum LemonSqueezyLicenseError: Error, Equatable {
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case rejected(message: String)
    case productMismatch
    case inactiveLicense
    case missingInstance
}

protocol LicenseServicing {
    func activate(licenseKey: String, instanceName: String) async throws -> LicenseActivation
    func validate(licenseKey: String, instanceID: String) async throws -> LicenseValidation
    func deactivate(licenseKey: String, instanceID: String) async throws
}

protocol URLSessionDataLoading {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionDataLoading {}

final class LemonSqueezyLicenseClient: LicenseServicing {
    private let configuration: LicenseProductConfiguration
    private let session: URLSessionDataLoading
    private let baseURL: URL
    private let decoder: JSONDecoder

    init(
        configuration: LicenseProductConfiguration,
        session: URLSessionDataLoading = URLSession.shared,
        baseURL: URL = URL(string: "https://api.lemonsqueezy.com/v1/licenses/")!
    ) {
        self.configuration = configuration
        self.session = session
        self.baseURL = baseURL
        decoder = JSONDecoder()
    }

    func activate(licenseKey: String, instanceName: String) async throws -> LicenseActivation {
        let response: LemonActivationResponse = try await post(
            endpoint: "activate",
            form: ["license_key": licenseKey, "instance_name": instanceName]
        )

        guard response.activated else {
            throw LemonSqueezyLicenseError.rejected(message: response.error ?? "Activation failed.")
        }
        guard configuration.matches(response.meta) else {
            if let instanceID = response.instance?.id {
                try? await deactivateWithoutValidation(licenseKey: licenseKey, instanceID: instanceID)
            }
            throw LemonSqueezyLicenseError.productMismatch
        }
        guard response.licenseKey.status == "active" else {
            if let instanceID = response.instance?.id {
                try? await deactivateWithoutValidation(licenseKey: licenseKey, instanceID: instanceID)
            }
            throw LemonSqueezyLicenseError.inactiveLicense
        }
        guard let instanceID = response.instance?.id else {
            throw LemonSqueezyLicenseError.missingInstance
        }

        return LicenseActivation(
            instanceID: instanceID,
            activationLimit: response.licenseKey.activationLimit,
            activationUsage: response.licenseKey.activationUsage
        )
    }

    func validate(licenseKey: String, instanceID: String) async throws -> LicenseValidation {
        let response: LemonValidationResponse = try await post(
            endpoint: "validate",
            form: ["license_key": licenseKey, "instance_id": instanceID]
        )

        guard configuration.matches(response.meta) else {
            throw LemonSqueezyLicenseError.productMismatch
        }
        return LicenseValidation(
            isValid: response.valid && response.licenseKey.status == "active",
            activationLimit: response.licenseKey.activationLimit,
            activationUsage: response.licenseKey.activationUsage
        )
    }

    func deactivate(licenseKey: String, instanceID: String) async throws {
        let response: LemonDeactivationResponse = try await post(
            endpoint: "deactivate",
            form: ["license_key": licenseKey, "instance_id": instanceID]
        )

        guard response.deactivated else {
            throw LemonSqueezyLicenseError.rejected(message: response.error ?? "Deactivation failed.")
        }
        guard configuration.matches(response.meta) else {
            throw LemonSqueezyLicenseError.productMismatch
        }
    }

    private func deactivateWithoutValidation(licenseKey: String, instanceID: String) async throws {
        let _: LemonDeactivationResponse = try await post(
            endpoint: "deactivate",
            form: ["license_key": licenseKey, "instance_id": instanceID]
        )
    }

    private func post<Response: Decodable>(
        endpoint: String,
        form: [String: String]
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = form
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, urlResponse) = try await session.data(for: request)
        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            throw LemonSqueezyLicenseError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = (try? decoder.decode(LemonErrorResponse.self, from: data).error)
                ?? "License request failed."
            throw LemonSqueezyLicenseError.httpError(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw LemonSqueezyLicenseError.invalidResponse
        }
    }
}

private struct LemonErrorResponse: Decodable {
    let error: String?
}

private struct LemonLicenseMetadata: Decodable {
    let storeID: Int
    let productID: Int
    let variantID: Int

    private enum CodingKeys: String, CodingKey {
        case storeID = "store_id"
        case productID = "product_id"
        case variantID = "variant_id"
    }
}

private struct LemonLicenseKey: Decodable {
    let status: String
    let activationLimit: Int
    let activationUsage: Int

    private enum CodingKeys: String, CodingKey {
        case status
        case activationLimit = "activation_limit"
        case activationUsage = "activation_usage"
    }
}

private struct LemonLicenseInstance: Decodable {
    let id: String
}

private struct LemonActivationResponse: Decodable {
    let activated: Bool
    let error: String?
    let licenseKey: LemonLicenseKey
    let instance: LemonLicenseInstance?
    let meta: LemonLicenseMetadata

    private enum CodingKeys: String, CodingKey {
        case activated
        case error
        case licenseKey = "license_key"
        case instance
        case meta
    }
}

private struct LemonValidationResponse: Decodable {
    let valid: Bool
    let licenseKey: LemonLicenseKey
    let meta: LemonLicenseMetadata

    private enum CodingKeys: String, CodingKey {
        case valid
        case licenseKey = "license_key"
        case meta
    }
}

private struct LemonDeactivationResponse: Decodable {
    let deactivated: Bool
    let error: String?
    let meta: LemonLicenseMetadata
}
