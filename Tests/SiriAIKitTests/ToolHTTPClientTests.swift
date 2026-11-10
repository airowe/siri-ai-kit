import Foundation
import Testing
@testable import SiriAIKit

struct Item: Codable, Equatable { let name: String }

struct ToolHTTPClientTests {
    static let base = URL(string: "https://api.example.com/v2")!
    let stub = StubURLProtocol.makeStub()

    func makeClient() -> ToolHTTPClient {
        ToolHTTPClient(baseURL: Self.base, session: stub.session, outcomes: ToolOutcomeLog(defaults: UserDefaults(suiteName: UUID().uuidString)!))
    }

    func result(_ status: Int, _ body: String) async -> Result<Item, ToolError> {
        stub.respond { StubURLProtocol.reply(status, body, for: $0) }
        do throws(ToolError) {
            return .success(try await makeClient().get("items/1", as: Item.self))
        } catch {
            return .failure(error)
        }
    }

    @Test func decodesSuccess() async {
        #expect(await result(200, #"{"name":"lamp"}"#) == .success(Item(name: "lamp")))
    }

    @Test(arguments: [
        (500, #"{"name":"lamp"}"#, ToolError.rejected(status: 500)),
        (404, "", .rejected(status: 404)),
        (200, "not json", .invalidResponse),
        (200, "", .invalidResponse),
    ])
    func mapsFailures(status: Int, body: String, expected: ToolError) async {
        #expect(await result(status, body) == .failure(expected))
    }

    @Test(arguments: [(URLError.Code.timedOut, ToolError.timedOut), (.notConnectedToInternet, .unreachable), (.cannotFindHost, .unreachable)])
    func mapsTransportErrors(code: URLError.Code, expected: ToolError) async {
        stub.respond { _ in throw URLError(code) }
        await #expect(throws: expected) { try await makeClient().get("items/1", as: Item.self) }
    }

    @Test func cancelledTaskMapsToTimedOut() async {
        stub.respond { request in
            Thread.sleep(forTimeInterval: 2)
            return StubURLProtocol.reply(200, #"{"name":"late"}"#, for: request)
        }
        let client = makeClient()
        let task = Task { try await client.get("items/1", as: Item.self) }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        let started = ContinuousClock.now
        await #expect(throws: ToolError.timedOut) { try await task.value }
        #expect(ContinuousClock.now - started < .seconds(1))
    }

    @Test(arguments: ["carts/1", "/carts/1"])
    func joinsPaths(path: String) async throws {
        stub.respond { StubURLProtocol.reply(200, #"{"name":"cart"}"#, for: $0) }
        _ = try await makeClient().get(path, as: Item.self)
        #expect(stub.requests.map(\.url?.absoluteString) == ["https://api.example.com/v2/carts/1"])
    }

    @Test func sendEncodesJSONBody() async throws {
        stub.respond { StubURLProtocol.reply(201, #"{"name":"saved"}"#, for: $0) }
        let saved = try await makeClient().send(.post, "items", body: Item(name: "lamp"), as: Item.self)
        #expect(saved == Item(name: "saved"))
        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(try JSONDecoder().decode(Item.self, from: try #require(request.httpBody)) == Item(name: "lamp"))
    }

    @Test func appliesTimeout() async throws {
        stub.respond { StubURLProtocol.reply(200, #"{"name":"x"}"#, for: $0) }
        _ = try await makeClient().get("items/1", as: Item.self)
        #expect(stub.requests.first?.timeoutInterval == 10)
    }

    @Test func noAuthorizationHeaderWithoutAuth() async throws {
        stub.respond { StubURLProtocol.reply(200, #"{"name":"x"}"#, for: $0) }
        _ = try await makeClient().get("items/1", as: Item.self)
        #expect(stub.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
    }
}
