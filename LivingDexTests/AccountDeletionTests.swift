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

    func testALocalFailureAfterTheRemoteDeletionIsReportedAsLeftovers() async {
        let recorder = Recorder()
        do {
            try await service(recorder, eraseFails: true).deleteEverything()
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(error as? AccountDeletionError, .localCleanup)
        }
        let events = await recorder.events
        XCTAssertEqual(events, ["remote", "signOut"])
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
