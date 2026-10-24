import Foundation
import LivingDexCore
import Testing
@testable import LivingDex

@Suite("Calls through the Midgar gateway", .serialized)
struct GatewayCallTests {
    private let candidate = SpeciesCandidate(
        speciesId: "gbif:5231190", commonName: "Red Fox", scientificName: "Vulpes vulpes",
        realm: .animals, rarity: .common, confidence: 0.9)
    private let context = CaptureContext(latitude: 60.16952, longitude: 24.93841, elevationMeters: nil)

    private let enrichBody = """
        {"taxonKey":5231190,"rarity":"rare","factSheet":{"scientificName":"Vulpes vulpes","commonName":"Red Fox","summary":"A fox.","iucnCategory":"LC"}}
        """

    @Test("The enrichment goes to the worker route behind the gateway with the coarse location and no credential")
    func enrichUsesTheWorkerRoute() async throws {
        let enricher = SpeciesEnricher(gateway: GatewayStub.gateway(body: enrichBody))
        let result = await enricher.enrich(candidate: candidate, context: context)
        guard case .resolved(let enrichment) = result else {
            Issue.record("expected a resolved enrichment")
            return
        }
        #expect(enrichment.rarity == .rare)
        let request = try #require(GatewayStub.captured)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString
            == "https://api.midgarcorp.cc/v1/livingdex/v1/enrich?name=Vulpes%20vulpes&taxonKey=5231190&lat=60.2&lng=24.9")
        #expect(request.value(forHTTPHeaderField: "X-App-ID") == "livingdex")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("A species the worker cannot confirm is unresolved")
    func workerNotFoundIsUnresolved() async {
        let gateway = GatewayStub.gateway(status: 404, body: #"{"error":"unresolved species","resolved":false}"#)
        let result = await SpeciesEnricher(gateway: gateway).enrich(candidate: candidate, context: context)
        guard case .unresolved = result else {
            Issue.record("expected unresolved")
            return
        }
    }

    @Test("A 404 from the gateway itself never rejects a species")
    func gatewayNotFoundIsUnavailable() async {
        let gateway = GatewayStub.gateway(status: 404, body: #"{"error":{"code":"unknown_service","message":"Unknown service."}}"#)
        let result = await SpeciesEnricher(gateway: gateway).enrich(candidate: candidate, context: context)
        guard case .unavailable = result else {
            Issue.record("expected unavailable")
            return
        }
    }

    @Test("A gateway failure is attempted once and leaves the species unconfirmed")
    func enrichIsNotRepeated() async {
        let gateway = GatewayStub.gateway(status: 503, body: #"{"error":"upstream"}"#)
        let result = await SpeciesEnricher(gateway: gateway).enrich(candidate: candidate, context: context)
        guard case .unavailable = result else {
            Issue.record("expected unavailable")
            return
        }
        #expect(GatewayStub.requestCount == 1)
    }

    @Test("The Regional Dex asks the worker for the cell centre")
    func regionUsesTheWorkerRoute() async throws {
        let body = #"{"count":1,"species":[{"taxonKey":1,"commonName":"Robin","scientificName":"Erithacus rubecula","realm":"animals","rarity":"common"}]}"#
        let store = RegionStore(gateway: GatewayStub.gateway(body: body))
        store.clear()
        defer { store.clear() }
        let species = await store.regionalSpecies(latitude: 60.1, longitude: 24.9)
        #expect(species?.map(\.speciesId) == ["gbif:1"])
        let request = try #require(GatewayStub.captured)
        #expect(request.url?.absoluteString
            == "https://api.midgarcorp.cc/v1/livingdex/v1/region?lat=60.0&lng=25.0&limit=120")
        #expect(request.value(forHTTPHeaderField: "X-App-ID") == "livingdex")
    }

    @Test("A species call is fetched from the worker's detail route")
    func detailUsesTheWorkerRoute() async throws {
        let body = #"{"call":{"url":"https://example.test/call.mp3","recordist":"A","license":"CC0","source":"xeno-canto"}}"#
        let service = SpeciesDetailService(gateway: GatewayStub.gateway(body: body))
        let call = await service.call(scientificName: "Erithacus rubecula")
        #expect(call?.source == "xeno-canto")
        let request = try #require(GatewayStub.captured)
        #expect(request.url?.absoluteString
            == "https://api.midgarcorp.cc/v1/livingdex/v1/detail?name=Erithacus%20rubecula")
    }
}

@Suite("Remote account deletion behind the gateway", .serialized)
struct MakoAccountDeleterTests {
    private func deleter(_ gateway: LivingDexGateway, key: String? = "key-123") -> MakoAccountDeleter {
        MakoAccountDeleter(gateway: gateway, apiKey: { key })
    }

    private func failure(of gateway: LivingDexGateway) async -> AccountDeletionError? {
        do {
            try await deleter(gateway).deleteRemoteAccount()
            return nil
        } catch {
            return error as? AccountDeletionError
        }
    }

    @Test("The deletion is an authenticated DELETE on mako's identity route behind the gateway")
    func sendsAuthenticatedDelete() async throws {
        try await deleter(GatewayStub.gateway()).deleteRemoteAccount()
        let request = try #require(GatewayStub.captured)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.absoluteString == "https://api.midgarcorp.cc/v1/intelligence/v1/identity")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer key-123")
        #expect(request.value(forHTTPHeaderField: "X-App-ID") == "livingdex")
    }

    @Test("No identity means nothing to delete")
    func noIdentityMeansNothingToDelete() async throws {
        try await deleter(GatewayStub.gateway(), key: nil).deleteRemoteAccount()
        #expect(GatewayStub.requestCount == 0)
    }

    @Test("A key mako no longer knows counts as deleted")
    func unknownKeyCountsAsDeleted() async throws {
        try await deleter(GatewayStub.gateway(status: 401)).deleteRemoteAccount()
    }

    @Test("A missing endpoint is not treated as deleted")
    func missingEndpointBlocksDeletion() async {
        #expect(await failure(of: GatewayStub.gateway(status: 404)) == .server)
    }

    @Test("A server error blocks deletion and is not repeated")
    func serverErrorBlocksDeletion() async {
        #expect(await failure(of: GatewayStub.gateway(status: 500)) == .server)
        #expect(GatewayStub.requestCount == 1)
    }

    @Test("A transport failure reads as offline")
    func transportFailureReadsAsOffline() async {
        #expect(await failure(of: GatewayStub.gateway(transportError: URLError(.notConnectedToInternet))) == .offline)
    }
}
