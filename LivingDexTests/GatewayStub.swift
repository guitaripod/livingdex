import Foundation
import MidgarCore
@testable import LivingDex

/// Answers every request of a gateway client with a fixed status and body, or fails it with a transport error, and
/// records what was sent, so a test sees the exact URL and headers a call put on the wire and how often it was sent.
final class GatewayStub: URLProtocol, @unchecked Sendable {
    /// Written only by the serialized suites before a request starts.
    nonisolated(unsafe) static var status = 200
    /// Written only by the serialized suites before a request starts.
    nonisolated(unsafe) static var responseBody = Data()
    /// Written only by the serialized suites before a request starts.
    nonisolated(unsafe) static var transportError: URLError?
    /// Written by the loading thread, read by the test after the request finished.
    nonisolated(unsafe) static var captured: URLRequest?
    /// Counts the requests of the running test.
    nonisolated(unsafe) static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.captured = request
        Self.requestCount += 1
        if let error = Self.transportError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// A gateway whose client talks to the stub, with the app id the app uses for the worker and mako.
    static func gateway(status: Int = 200, body: String = "", transportError: URLError? = nil) -> LivingDexGateway {
        Self.status = status
        Self.responseBody = Data(body.utf8)
        Self.transportError = transportError
        Self.captured = nil
        Self.requestCount = 0
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GatewayStub.self]
        return LivingDexGateway(
            client: MidgarHTTPClient(
                configuration: MidgarHTTPConfiguration(
                    appID: LivingDexMidgar.tenantID, session: URLSession(configuration: configuration))))
    }
}
