import XCTest
@testable import LivingDex

final class AccountDeletionTests: XCTestCase {
    private actor Recorder {
        private(set) var events: [String] = []
        func add(_ event: String) { events.append(event) }
    }

    private struct StubRemote: RemoteAccountDeleting {
        let recorder: Recorder
        let failure: AccountDeletionError?
        func deleteRemoteAccount() async throws {
            await recorder.add("remote")
            if let failure { throw failure }
        }
    }

    private func service(_ recorder: Recorder, failure: AccountDeletionError? = nil, eraseFails: Bool = false) -> AccountDeletionService {
        AccountDeletionService(
            remote: StubRemote(recorder: recorder, failure: failure),
            signOut: { await recorder.add("signOut") },
            eraseLocal: {
                if eraseFails { throw AccountDeletionError.server }
                Task { await recorder.add("erase") }
            })
    }

    func testDeletesRemoteFirstThenCredentialsThenLocalData() async throws {
        let recorder = Recorder()
        try await service(recorder).deleteEverything()
        try await Task.sleep(nanoseconds: 50_000_000)
        let events = await recorder.events
        XCTAssertEqual(events, ["remote", "signOut", "erase"])
    }

    func testOfflineFailureLeavesTheDeviceUntouched() async {
        let recorder = Recorder()
        do {
            try await service(recorder, failure: .offline).deleteEverything()
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(error as? AccountDeletionError, .offline)
        }
        let events = await recorder.events
        XCTAssertEqual(events, ["remote"])
    }

    func testServerFailureLeavesTheDeviceUntouched() async {
        let recorder = Recorder()
        do {
            try await service(recorder, failure: .server).deleteEverything()
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(error as? AccountDeletionError, .server)
        }
        let events = await recorder.events
        XCTAssertEqual(events, ["remote"])
    }
}

final class MakoAccountDeleterTests: XCTestCase {
    private final class StubProtocol: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
        nonisolated(unsafe) static var requests: [URLRequest] = []

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.requests.append(request)
            do {
                let (status, data) = try Self.handler?(request) ?? (200, Data())
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    override func setUp() {
        super.setUp()
        StubProtocol.handler = nil
        StubProtocol.requests = []
    }

    private func deleter(key: String? = "key-123") -> MakoAccountDeleter {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return MakoAccountDeleter(
            baseURL: URL(string: "https://example.test")!, appID: "livingdex",
            session: URLSession(configuration: config), apiKey: { key })
    }

    func testSendsAuthenticatedDeleteToTheIdentityEndpoint() async throws {
        StubProtocol.handler = { _ in (200, Data()) }
        try await deleter().deleteRemoteAccount()
        let request = try XCTUnwrap(StubProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.path, "/v1/identity")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer key-123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-App-ID"), "livingdex")
    }

    func testNoIdentityMeansNothingToDelete() async throws {
        try await deleter(key: nil).deleteRemoteAccount()
        XCTAssertTrue(StubProtocol.requests.isEmpty)
    }

    func testUnknownKeyCountsAsAlreadyDeleted() async throws {
        StubProtocol.handler = { _ in (401, Data()) }
        try await deleter().deleteRemoteAccount()
    }

    func testServerErrorThrows() async {
        StubProtocol.handler = { _ in (500, Data()) }
        do {
            try await deleter().deleteRemoteAccount()
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(error as? AccountDeletionError, .server)
        }
    }

    func testTransportFailureReadsAsOffline() async {
        StubProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do {
            try await deleter().deleteRemoteAccount()
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(error as? AccountDeletionError, .offline)
        }
    }
}
