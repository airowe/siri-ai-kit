import Foundation

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

    /// New tokens to replace `failed`. Throws `.keychain` if they couldn't be saved, `.timedOut` if the caller
    /// is cancelled or `limit` passes first, and `.signedOut` otherwise.
    ///
    /// The refresh keeps running after a caller gives up, so rotated tokens are still saved.
    func refreshed(after failed: Tokens, within limit: Duration) async throws(ToolError) -> Tokens {
        if Task.isCancelled { throw .timedOut }
        if inFlight == nil, let current = try store.load(), current != failed {
            return current
        }
        let task = inFlight ?? startRefresh(of: failed)
        do {
            return try await Self.value(of: task, within: limit)
        } catch let error as ToolError {
            throw error
        } catch {
            throw .signedOut
        }
    }

    private func finished(_ task: Task<Tokens, any Error>) {
        if inFlight == task { inFlight = nil }
    }

    /// Waits for `task` without tying its lifetime to the caller: cancellation or the deadline end the wait only.
    private static func value(of task: Task<Tokens, any Error>, within limit: Duration) async throws -> Tokens {
        let waiter = SingleResume<Tokens>()
        let deadline = Task {
            try? await Task.sleep(for: limit)
            waiter.resume(with: .failure(ToolError.timedOut))
        }
        defer { deadline.cancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiter.attach(continuation)
                Task { waiter.resume(with: await task.result) }
            }
        } onCancel: {
            waiter.resume(with: .failure(ToolError.timedOut))
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
        Task {
            _ = await task.result
            await self.finished(task)
        }
        return task
    }
}
