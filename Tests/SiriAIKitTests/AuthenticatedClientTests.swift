import Foundation
import Testing
@testable import SiriAIKit

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

struct AuthenticatedClientTests {
    static let base = URL(string: "https://api.example.com")!
    static let saved = Tokens(accessToken: "a1", refreshToken: "r1")
    static let refreshed = Tokens(accessToken: "a2", refreshToken: "r2")

    let stub = StubURLProtocol.makeStub()
    let store = InMemoryTokenStore(Self.saved)
    let refreshCount = Counter()
    let outcomes = ToolOutcomeLog(defaults: UserDefaults(suiteName: UUID().uuidString)!)

    struct RefreshFailed: Error {}

    func makeClient(
        expiredStatuses: Set<Int> = [401],
        refreshDelay: Duration = .zero,
        refreshFails: Bool = false
    ) -> ToolHTTPClient {
        let count = refreshCount
        let auth = TokenAuthenticator(store: store, expiredStatuses: expiredStatuses) { _ in
            count.increment()
            try await Task.sleep(for: refreshDelay)
            if refreshFails { throw RefreshFailed() }
            return Self.refreshed
        }
        return ToolHTTPClient(baseURL: Self.base, session: stub.session, auth: auth, outcomes: outcomes)
    }

    /// 200 for the given access token, `expiredStatus` for any other.
    func acceptOnly(_ token: String, otherwise expiredStatus: Int = 401) {
        stub.respond { request in
            let ok = request.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)"
            return StubURLProtocol.reply(ok ? 200 : expiredStatus, #"{"name":"cart"}"#, for: request)
        }
    }

    var sentTokens: [String?] { stub.requests.map { $0.value(forHTTPHeaderField: "Authorization") } }

    @Test func freshTokenIsUsed() async throws {
        acceptOnly("a1")
        #expect(try await makeClient().get("cart", as: Item.self) == Item(name: "cart"))
        #expect(sentTokens == ["Bearer a1"])
        #expect(outcomes.last.hasPrefix("used saved token at "))
        #expect(refreshCount.value == 0)
    }

    @Test func expiredTokenRefreshesOnceAndRetries() async throws {
        acceptOnly("a2")
        #expect(try await makeClient().get("cart", as: Item.self) == Item(name: "cart"))
        #expect(sentTokens == ["Bearer a1", "Bearer a2"])
        #expect(refreshCount.value == 1)
        #expect(try store.load() == Self.refreshed)
        #expect(outcomes.last.hasPrefix("refreshed after 401 at "))
    }

    @Test func refreshThrowsGivesSignedOut() async {
        acceptOnly("a2")
        await #expect(throws: ToolError.signedOut) { try await makeClient(refreshFails: true).get("cart", as: Item.self) }
        #expect(outcomes.last.hasPrefix("signed out at "))
        #expect(sentTokens == ["Bearer a1"])
    }

    @Test func retryAlsoRejectedGivesSignedOut() async {
        acceptOnly("never")
        await #expect(throws: ToolError.signedOut) { try await makeClient().get("cart", as: Item.self) }
        #expect(refreshCount.value == 1)
        #expect(sentTokens == ["Bearer a1", "Bearer a2"])
        #expect(outcomes.last.hasPrefix("signed out at "))
    }

    @Test func statusNotInExpiredSetIsRejected() async {
        acceptOnly("a2", otherwise: 403)
        await #expect(throws: ToolError.rejected(status: 403)) { try await makeClient().get("cart", as: Item.self) }
        #expect(refreshCount.value == 0)
    }

    @Test func customExpiredStatuses() async throws {
        acceptOnly("a2", otherwise: 403)
        #expect(try await makeClient(expiredStatuses: [401, 403]).get("cart", as: Item.self) == Item(name: "cart"))
        #expect(refreshCount.value == 1)
        #expect(outcomes.last.hasPrefix("refreshed after 403 at "))
    }

    @Test func noTokensGivesSignedOutWithoutRequest() async {
        store.clear()
        acceptOnly("a1")
        await #expect(throws: ToolError.signedOut) { try await makeClient().get("cart", as: Item.self) }
        #expect(stub.requests.isEmpty)
        #expect(outcomes.last.hasPrefix("signed out at "))
    }

    @Test func keychainReadFailureGivesSignedOut() async {
        store.failLoads = -25308
        acceptOnly("a1")
        await #expect(throws: ToolError.signedOut) { try await makeClient().get("cart", as: Item.self) }
        #expect(stub.requests.isEmpty)
        #expect(outcomes.last.contains("-25308"))
    }

    @Test func saveFailureAfterRefreshGivesSignedOut() async {
        store.failSaves = -34018
        acceptOnly("a2")
        await #expect(throws: ToolError.signedOut) { try await makeClient().get("cart", as: Item.self) }
        #expect(outcomes.last.contains("-34018"))
        #expect(!sentTokens.contains("Bearer a2"))
    }

    @Test func concurrentExpiredCallsShareOneRefresh() async throws {
        acceptOnly("a2")
        let client = makeClient(refreshDelay: .milliseconds(100))
        async let first = client.get("cart", as: Item.self)
        async let second = client.get("cart", as: Item.self)
        #expect(try await [first, second] == [Item(name: "cart"), Item(name: "cart")])
        #expect(refreshCount.value == 1)
    }

    @Test func concurrentCallsWhenRefreshFails() async {
        acceptOnly("a2")
        let client = makeClient(refreshDelay: .milliseconds(100), refreshFails: true)
        async let first = Result(catching: { try await client.get("cart", as: Item.self) })
        async let second = Result(catching: { try await client.get("cart", as: Item.self) })
        let results = await [first, second]
        for result in results {
            #expect(throws: ToolError.signedOut) { try result.get() }
        }
        #expect(refreshCount.value == 1)
    }
}

extension Result where Failure == any Error {
    init(catching body: () async throws -> Success) async {
        do { self = .success(try await body()) } catch { self = .failure(error) }
    }
}
