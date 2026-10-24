import Foundation
import StoreKit
import Testing
import UIKit

/// The parent of every suite that touches StoreKit or the gateway stub. StoreKit's test session and the stub are
/// process-wide, so these suites run one after another and never beside each other.
@MainActor
@Suite("StoreKit", .serialized)
enum StoreKitSuites {}

/// Polls `condition` until it holds or `timeout` passes, for the StoreKit changes that reach the store through
/// `Transaction.updates` a moment after the test session makes them.
@MainActor
func eventually(timeout: Duration = .seconds(10), _ condition: () async -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(100))
    }
    return await condition()
}

/// The window scene of the test host, which every purchase confirms in: StoreKit inside a test host finds no window for
/// a scene-less purchase, so it never completes.
@MainActor
func hostScene() throws -> UIWindowScene {
    guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
        throw URLError(.cannotFindHost)
    }
    return scene
}

/// The StoreKit configuration file the scheme runs with, which every StoreKit test reads.
nonisolated let productsConfigurationURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Products.storekit")

/// The parts of a StoreKit configuration file the product checks read.
nonisolated struct StoreKitFile: Decodable {
    struct Item: Decodable {
        let productID: String
        let displayPrice: String
        let referenceName: String
        let type: String
        let recurringSubscriptionPeriod: String?
        let introductoryOffer: IntroductoryOffer?
    }

    struct IntroductoryOffer: Decodable {
        let paymentMode: String
        let subscriptionPeriod: String
    }

    struct Group: Decodable {
        let name: String
        let subscriptions: [Item]
    }

    let products: [Item]
    let subscriptionGroups: [Group]

    static func load() throws -> StoreKitFile {
        try JSONDecoder().decode(StoreKitFile.self, from: Data(contentsOf: productsConfigurationURL))
    }

    var allProducts: [Item] {
        products + subscriptionGroups.flatMap(\.subscriptions)
    }
}

/// The claims of a signed transaction the validate request carries, read from the JWS payload.
nonisolated struct SignedTransactionPayload: Decodable {
    let transactionId: String
    let productId: String
    let appAccountToken: String?

    init(jws: String) throws {
        let parts = jws.split(separator: ".")
        guard parts.count == 3 else {
            throw URLError(.cannotParseResponse)
        }
        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64) else {
            throw URLError(.cannotDecodeContentData)
        }
        self = try JSONDecoder().decode(SignedTransactionPayload.self, from: data)
    }

    private enum CodingKeys: String, CodingKey {
        case transactionId
        case productId
        case appAccountToken
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transactionId = try container.decode(String.self, forKey: .transactionId)
        productId = try container.decode(String.self, forKey: .productId)
        appAccountToken = try container.decodeIfPresent(String.self, forKey: .appAccountToken)
    }
}
