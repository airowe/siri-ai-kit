/// Hands out the saved tokens and refreshes them when the API says they've expired.
///
/// Refreshes once per expiry: calls that fail at the same moment share one refresh.
public actor TokenAuthenticator {
    let store: any TokenStore
    let expiredStatuses: Set<Int>
    private let refresh: @Sendable (Tokens) async throws -> Tokens
    private var inFlight: Task<Tokens, any Error>?

    public init(
        store: some TokenStore,
        expiredStatuses: Set<Int> = [401],
        refresh: @escaping @Sendable (Tokens) async throws -> Tokens
    ) {
        self.store = store
        self.expiredStatuses = expiredStatuses
        self.refresh = refresh
    }

    func currentTokens() throws(ToolError) -> Tokens {
        guard let tokens = try store.load() else { throw .signedOut }
        return tokens
    }

    /// New tokens to replace `failed`. Throws `.keychain` if they couldn't be saved, `.signedOut` otherwise.
    func refreshed(after failed: Tokens) async throws(ToolError) -> Tokens {
        if inFlight == nil, let current = try store.load(), current != failed {
            return current
        }
        let task = inFlight ?? startRefresh(of: failed)
        defer { if inFlight == task { inFlight = nil } }
        do {
            return try await task.value
        } catch let error as ToolError {
            throw error
        } catch {
            throw .signedOut
        }
    }

    private func startRefresh(of failed: Tokens) -> Task<Tokens, any Error> {
        let store = store
        let refresh = refresh
        let task = Task<Tokens, any Error> {
            let fresh: Tokens
            do {
                fresh = try await refresh(failed)
            } catch {
                throw ToolError.signedOut
            }
            try store.save(fresh)
            return fresh
        }
        inFlight = task
        return task
    }
}
